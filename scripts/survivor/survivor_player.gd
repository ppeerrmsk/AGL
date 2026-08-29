class_name SurvivorPlayer
extends Node

const SurvivorSkillEffectsScript = preload(
	"res://scripts/survivor/survivor_skill_effects.gd")

## 生存模式状态管理：经验/等级/升级
## 纯数据节点，不干涉飞机操控

signal leveled_up(new_level: int)

# ── 引用 ──
var aircraft: Aircraft

# ── 经验与等级 ──
var xp: int = 0
var level: int = 1
var xp_to_next: int = 30

## 本局累计获得的总 XP（不受经验条/升级清零影响）
## 用于 Game Over / 撤退时折算成功勋（MeritLedger）
var total_xp_gained: int = 0

## 经验倍率（xp_mult 升级，队级单实例）：击杀 XP × 此值，硬顶 1.4。
## 720 T2 起从 Aircraft 实例字段迁到这里——切控/换帅/换型都不丢
var xp_multiplier: float = 1.0

## 722 批 F-16 签名技·智能鹰：XP 第二乘区（独立于 xp_mult 硬顶，两区叠乘）
var sig_xp_mult: float = 1.0

# ── 经验动态填充动画 ──
## 未注入显示条的经验，按 XP_DRAIN_DURATION 内排空的速率回填到 xp
const XP_DRAIN_DURATION := 0.6
const XP_DRAIN_MIN_RATE := 25.0
var _pending_xp: float = 0.0
var _xp_accum: float = 0.0
## 满条等待玩家选升级：此期间 xp==xp_to_next，不再回填
var _awaiting_level_up: bool = false

func _ready() -> void:
	xp_to_next = SurvivorData.xp_for_level(2)

func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	total_xp_gained += amount
	_pending_xp += float(amount)

func _process(delta: float) -> void:
	if _awaiting_level_up or _pending_xp <= 0.0:
		return
	var rate := maxf(_pending_xp / XP_DRAIN_DURATION, XP_DRAIN_MIN_RATE)
	var step := minf(_pending_xp, rate * delta)
	_pending_xp -= step
	_xp_accum += step
	var whole := int(_xp_accum)
	if whole <= 0:
		return
	_xp_accum -= float(whole)
	_commit_xp(whole)

func _commit_xp(amount: int) -> void:
	var room := xp_to_next - xp
	if amount < room:
		xp += amount
		return
	# 先把经验条填到 100%，保留满条让玩家看到升级瞬间
	var overflow := amount - room
	xp = xp_to_next
	_pending_xp += float(overflow)
	level += 1
	_awaiting_level_up = true
	EventLogger.log_event("LEVEL", "Player",
		"level up → %d (next=%d xp)" % [level, SurvivorData.xp_for_level(level + 1)])
	leveled_up.emit(level)

## 升级界面关闭后由 survivor_mode 调用：重置经验条、解除等待
func consume_level_up_display() -> void:
	if not _awaiting_level_up:
		return
	_awaiting_level_up = false
	xp = 0
	xp_to_next = SurvivorData.xp_for_level(level + 1)

# ── 三轴属性点（spec evolution-attribute-gates §2.2）──
## 斗士/骑士/策士技能点：每 3 级卡片三选一，选卡 = 该轴 +1（卡片流阶段 3 接线写入）。
## 纯局内状态，本节点每局新建自然清零；进化门槛与里程碑都查这里。
var axis_points: Dictionary = {
	SurvivorData.AXIS_GLADIATOR: 0,
	SurvivorData.AXIS_KNIGHT: 0,
	SurvivorData.AXIS_SCHEMER: 0,
}
## 当前操控机已生效的里程碑档位（axis → 已应用的 points 档数组）。
## 实际记账逐机存在飞机 meta 上（见 _milestone_record）——里程碑要下发全队，
## 且换帅后新操控机必须带着自己那本账，玩家级单账本做不到。这里只是"当前机那本"的视图。
var applied_milestones: Dictionary:
	get:
		return _milestone_record(aircraft)
	set(value):
		_set_milestone_record(aircraft, value)

## 里程碑下发目标提供器（survivor_mode 注入，返回全部应吃里程碑加成的飞机）。
## 未注入时退化为"只有当前操控机"——单测与沙盒路径行为不变。
var milestone_targets_provider: Callable = Callable()

func add_axis_point(axis: StringName, profile: PlayableAircraft = null) -> void:
	if not axis_points.has(axis):
		push_warning("SurvivorPlayer.add_axis_point: 未知属性轴 %s" % axis)
		return
	# 收入封顶（spec evolution-attribute-gates §2.2 v9）：8 点拿满后选卡只得技能不再加点，
	# 保 §2.5 排他性数学在无等级上限的局内曲线下永久成立。一切加点来源共用本闸。
	if total_axis_points() >= SurvivorData.AXIS_POINT_CAP:
		EventLogger.log_event("AXIS", "Player", "%s 加点跳过：合计 %d 已达封顶" % [
			axis, total_axis_points()])
		return
	axis_points[axis] = int(axis_points[axis]) + 1
	EventLogger.log_event("AXIS", "Player", "%s +1 → %d（合计 %d / 可得 %d）" % [
		axis, int(axis_points[axis]), total_axis_points(),
		SurvivorData.axis_points_earnable(level)])
	apply_crossed_milestones(axis, profile)

func get_axis_points(axis: StringName) -> int:
	return int(axis_points.get(axis, 0))

func total_axis_points() -> int:
	var t: int = 0
	for v in axis_points.values():
		t += int(v)
	return t

## 策士里程碑的玩家级 XP 乘区。动态从当前进度求值，避免按全队飞机数量重复应用。
func milestone_xp_multiplier(profile: PlayableAircraft = null) -> float:
	var mult: float = 1.0
	var pts: int = get_milestone_progress(SurvivorData.AXIS_SCHEMER)
	for m in SurvivorData.milestones_for(SurvivorData.AXIS_SCHEMER, profile):
		if pts >= int(m["points"]) and str(m.get("stat", "")) == "xp_mult":
			mult *= float(m.get("value", 1.0))
	return mult

# ── "+1 轴进度"加成（spec skills-720-rework §1.1）──
## 带 milestone_plus 的技能给对应轴的**里程碑进度** +1——不是进化门槛点数：
## gates 仍只查 axis_points（双计数隔离），里程碑判档用 get_milestone_progress()。
## 每轴 cap = 2（2026-07-21 定案）：超出部分浪费（量表画到顶），保"预留档=稀罕"。
const MILESTONE_BONUS_CAP: int = 2
var milestone_bonus: Dictionary = {
	SurvivorData.AXIS_GLADIATOR: 0,
	SurvivorData.AXIS_KNIGHT: 0,
	SurvivorData.AXIS_SCHEMER: 0,
}

func add_milestone_bonus(axis: StringName, profile: PlayableAircraft = null) -> void:
	if not milestone_bonus.has(axis):
		push_warning("SurvivorPlayer.add_milestone_bonus: 未知属性轴 %s" % axis)
		return
	if int(milestone_bonus[axis]) >= MILESTONE_BONUS_CAP:
		EventLogger.log_event("AXIS", "Player",
			"%s 里程碑加成已满 cap %d，本次 +1 浪费" % [axis, MILESTONE_BONUS_CAP])
		return
	milestone_bonus[axis] = int(milestone_bonus[axis]) + 1
	EventLogger.log_event("AXIS", "Player", "%s 里程碑进度 +1（加成 %d/%d，门槛点不变）" % [
		axis, int(milestone_bonus[axis]), MILESTONE_BONUS_CAP])
	apply_crossed_milestones(axis, profile)

## 里程碑进度 = 门槛点数 + 加成（量表 / 里程碑判档用；进化 gates 仍读 axis_points 纯点）
func get_milestone_progress(axis: StringName) -> int:
	return get_axis_points(axis) + int(milestone_bonus.get(axis, 0))

# ── 局内武器库（spec inrun-weapon-inventory）──
## 特殊武器 = 玩家的外部装备，到手即永久（局内）：进化前快照当前机上的特殊武器
## （存资源**引用**——railgun_charge 等强化就长在资源上，引用即强化载体），换型后补挂到新机。
## equipment 数组类 = railgun/laser；机尾位 = loyal_wingman/torpedo（互斥）；副槽 = QMAAM。
## 底线武器（gun/missile/rocket/ciws/flare）随机体走，不入库。
const SPECIAL_EQUIPMENT_KINDS: Array[String] = ["railgun", "laser", "esm_pod"]

var weapon_inventory: Dictionary = {}  # StringName → Resource

## 进化换型前调用：扫当前 params，把特殊武器（含其强化状态）收进武器库。
## 同 key 用当前引用覆盖（当前 = 强化最全的版本）。
func record_special_weapons() -> void:
	if not aircraft or not aircraft.params:
		return
	var p := aircraft.params
	if p.equipment != null:
		for eq in p.equipment:
			if eq != null and SPECIAL_EQUIPMENT_KINDS.has(eq.equipment_kind):
				weapon_inventory[StringName(eq.equipment_kind)] = eq
	if p.loyal_wingman != null:
		weapon_inventory[&"loyal_wingman"] = p.loyal_wingman
	if p.torpedo != null:
		weapon_inventory[&"torpedo"] = p.torpedo
	if p.secondary_missile != null:
		weapon_inventory[&"secondary_missile"] = p.secondary_missile
	# 火箭 = 外部装备，跟人走（用户 2026-07-23："特殊武器都从战区获取、换机继承"）。
	# 旧版只收 inrun_reward meta 的火箭（区分战区火箭 vs 机型自带火箭）——机体自带火箭
	# 已全部剥离（inrun-weapon-inventory §2.2），此门作废：所有火箭一律入库继承，
	# 否则进化换机会把火箭摘掉（log 20260724_222103：Su-34→J-20 火箭丢失）。
	if p.rocket != null:
		weapon_inventory[&"rocket"] = p.rocket

## 进化换型后调用：把武器库补挂到新机（新机已有同类的不重复；机尾位守互斥）。
func remount_weapons() -> void:
	if not aircraft or not aircraft.params or weapon_inventory.is_empty():
		return
	var p := aircraft.params
	var mounted: Array = []
	for key in weapon_inventory:
		var res: Resource = weapon_inventory[key]
		if res == null:
			continue
		match key:
			&"loyal_wingman":
				if p.loyal_wingman == null and p.torpedo == null:
					p.loyal_wingman = res
					mounted.append(key)
			&"torpedo":
				if p.torpedo == null and p.loyal_wingman == null:
					p.torpedo = res
					mounted.append(key)
			&"secondary_missile":
				if p.secondary_missile == null:
					p.secondary_missile = res
					aircraft.secondary_missiles_remaining = res.max_count
					mounted.append(key)
			&"rocket":
				# 战区奖励火箭补挂（新机自带火箭则不覆盖——自带优先，库存留待下次换型）
				if p.rocket == null:
					p.rocket = res
					aircraft.rockets_remaining = res.max_ammo
					mounted.append(key)
			_:
				if p.get_equipment_of_kind(String(key)) == null:
					if p.equipment == null:
						var arr: Array[EquipmentParams] = []
						p.equipment = arr
					p.equipment.append(res as EquipmentParams)
					mounted.append(key)
	if not mounted.is_empty():
		EventLogger.log_event("WEAPON_INV", "Player", "换型补挂：%s（库存 %s）" % [
			str(mounted), str(weapon_inventory.keys())])

# ── 三轴里程碑应用器（spec evolution-attribute-gates §2.6/§2.7，阶段 2）──

## 逐机里程碑记账：档位记录挂在飞机 meta 上而不是玩家身上。
## 无飞机时落到 _orphan_milestone_record（构建早期 / 单测里 aircraft 尚未就位）。
const MILESTONE_RECORD_META := &"_applied_milestones"
var _orphan_milestone_record: Dictionary = {}

func _milestone_record(target) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return _orphan_milestone_record
	if not target.has_meta(MILESTONE_RECORD_META):
		target.set_meta(MILESTONE_RECORD_META, {})
	return target.get_meta(MILESTONE_RECORD_META)

func _set_milestone_record(target, value: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		_orphan_milestone_record = value
		return
	target.set_meta(MILESTONE_RECORD_META, value)

## 本次里程碑要下发到哪些飞机（默认只有当前操控机）
func _milestone_targets() -> Array:
	if milestone_targets_provider.is_valid():
		var arr = milestone_targets_provider.call()
		if arr is Array:
			return arr
	return [aircraft] if aircraft != null else []

## 加点后把该轴新跨过的里程碑档下发全队（增量、逐机幂等）。
## 无飞机时不应用也不记账——等飞机就位后重放补上。profile = 起手机覆写表来源。
func apply_crossed_milestones(axis: StringName, profile: PlayableAircraft = null) -> void:
	for t in _milestone_targets():
		apply_crossed_milestones_to(t, axis, profile)

## 对单机应用该轴新跨过的档（逐机记账防重复）。
func apply_crossed_milestones_to(target, axis: StringName, profile: PlayableAircraft = null) -> void:
	if target == null or not is_instance_valid(target) or target.params == null:
		return
	var pts: int = get_milestone_progress(axis)   # 点数 + "+1 轴进度"加成（gates 不走这里）
	var rec: Dictionary = _milestone_record(target)
	var done: Array = rec.get(axis, [])
	for m in SurvivorData.milestones_for(axis, profile):
		var need: int = int(m["points"])
		if pts >= need and not done.has(need):
			_apply_milestone_effect_to(target, m)
			done.append(need)
			EventLogger.log_event("MILESTONE", str(target.callsign),
				"%s %d点 里程碑生效：%s %s" % [axis, need, str(m.get("stat")), str(m.get("value"))])
	rec[axis] = done

## 把三轴已达成的全部档补挂到指定飞机（新僚机入队 / 僚机换型后重放）。逐机幂等。
func apply_all_milestones_to(target, profile: PlayableAircraft = null) -> void:
	for axis in SurvivorData.AXES:
		apply_crossed_milestones_to(target, axis, profile)

## 换型重放（spec §2.7 玩家层持有）：evolve() 换新 params 后调用——
## 清该机记录、把三轴已达成的全部档位重挂上去。加成跟玩家不跟机体。
func reapply_all_milestones(profile: PlayableAircraft = null) -> void:
	reapply_all_milestones_to(aircraft, profile)
	EventLogger.log_event("MILESTONE", "Player", "换型重放完成（斗%d/骑%d/策%d 点）" % [
		get_axis_points(SurvivorData.AXIS_GLADIATOR),
		get_axis_points(SurvivorData.AXIS_KNIGHT),
		get_axis_points(SurvivorData.AXIS_SCHEMER)])

## 指定机换型重放：params 被 evolve 换掉后旧记账作废，清空再全量重挂。
func reapply_all_milestones_to(target, profile: PlayableAircraft = null) -> void:
	_set_milestone_record(target, {})
	apply_all_milestones_to(target, profile)

## 当前机便捷入口；实际效果始终显式接收目标飞机。
func _apply_milestone_effect(m: Dictionary) -> void:
	_apply_milestone_effect_to(aircraft, m)


## 应用一档里程碑到指定飞机（表结构见 SurvivorData.MILESTONE_TABLE）。
## mult 类 stat 的 value 是乘数（1.08）；add 类是增量。子资源先 duplicate 防共享污染。
func _apply_milestone_effect_to(target: Aircraft, m: Dictionary) -> void:
	if not target or not target.params:
		return
	var p := target.params
	var v: float = float(m.get("value", 0.0))
	match str(m.get("stat", "")):
		"max_hp":
			p.max_hp += v
			target.hp += v  # 达成时也恢复对应量（与升级同语义）
		"armor":
			# 与普通技能“复合装甲”同源：armor/(armor+100)，导弹按 50% 穿甲。
			p.armor += v
		"missile_locks":
			target.max_simultaneous_locks += int(v)
		"xp_mult":
			pass  # 玩家级动态乘区；不得随全队逐机下发次数重复相乘
		"gun_damage":
			if p.gun:
				p.gun = p.gun.duplicate()
				p.gun.bullet_damage *= v
		"gun_range":
			if p.gun:
				p.gun = p.gun.duplicate()
				p.gun.max_range *= v
		"gun_ammo":
			if p.gun:
				p.gun = p.gun.duplicate()
				var add_ammo: int = int(round(p.gun.max_ammo * (v - 1.0)))
				p.gun.max_ammo += add_ammo
				target.ammo += add_ammo
		"max_g":
			# 持续/结构极限同步抬，保持瞬时超越空间不缩水（CLAUDE.md 永久升级=直改 params，AI 经 effective_* 可见）
			p.max_g += v
			p.max_g_structural += v
		"stall_speed":
			# 永久机动里程碑直改 params；AI 战术经 effective_stall_speed_kmh 自动感知。
			p.stall_speed_base *= v
		"missile_count":
			if p.missile:
				p.missile = p.missile.duplicate()
				p.missile.max_count += int(v)
				target.missiles_remaining += int(v)
		"radar_range":
			p.radar_range *= v
		"speed":
			# 沿用 apply_upgrade("speed") 教训：只抬极速 + 半比例加速，不动 cruise
			# （cruise 同步放大会抬高转弯最低速度地板，堆层后压在高速上转不动弯）
			p.max_speed *= v
			p.acceleration *= (1.0 + (v - 1.0) * 0.5)
		"alt_speed":
			p.climb_rate_max *= v
		"flare_count":
			if p.flare:
				p.flare = p.flare.duplicate()
				p.flare.max_flares += int(v)
				target.flares_remaining += int(v)
		"lock_time":
			p.lock_time = maxf(p.lock_time * v, 0.5)  # 地板 0.5s 与升级路径一致
		"flare_cd":
			if p.flare:
				p.flare = p.flare.duplicate()
				p.flare.cooldown *= v
				p.flare.reload_time *= v
		"radar_cone_deg":
			p.radar_half_angle += v  # 矩阵"锥"口径 = 半角（params.radar_half_angle）
		_:
			push_warning("未知里程碑 stat: %s" % str(m.get("stat")))

## 对指定飞机应用一条升级（全队/品类下发用，spec skills-720-rework T1）。
## 显式传目标给效果执行器，不改写当前操控机引用。
func apply_upgrade_to(target: Aircraft, upgrade: Dictionary) -> void:
	if target == null or not is_instance_valid(target) or target.params == null:
		return
	_apply_upgrade_effect_to(target, upgrade)

## 从指定飞机上剥离一条升级（王牌切控迁移用；仅 SurvivorData.ACE_FIELD_STATS 白名单 stat 有意义，
## 触发型技能走 meta 生效子集天然迁移不经此）。T2 数据批标 ace 的字段型技能必须在此实现逆操作。
func strip_upgrade_from(target: Aircraft, upgrade: Dictionary) -> void:
	if target == null or not is_instance_valid(target) or target.params == null:
		return
	var stat: String = str(upgrade.get("stat", ""))
	if not SurvivorData.ACE_FIELD_STATS.has(stat):
		return
	match stat:
		"missile_swarm":
			var swarm_n: int = int(upgrade.get("value", 4))
			var penalty: float = float(upgrade.get("tracking_penalty", 0.85))
			if target.params.missile:
				target.params.missile = target.params.missile.duplicate()
				target.params.missile.max_count = maxi(0, target.params.missile.max_count - swarm_n)
				if penalty > 0.0:
					target.params.missile.max_g /= penalty
				target.missiles_remaining = mini(target.missiles_remaining, target.params.missile.max_count)
			target.max_simultaneous_locks = maxi(1,
				target.max_simultaneous_locks - int(upgrade.get("lock_bonus", 3)))
		"fear_on_lock":
			target.fear_on_lock_threshold = 0.0
		"fear_squad_spread":
			target.fear_squad_spread_duration = 0.0
		"head_on_jam":
			target.head_on_jam_threshold = 0.0
			target._head_on_jam_seconds.clear()
		"rear_aura_slow":
			target.rear_aura_slow_radius_px = 0.0
		"cloud_overload":
			target.cloud_overload_active = false
		_:
			push_warning("strip_upgrade_from: ACE_FIELD_STATS 登记了 %s 但未实现逆操作" % stat)

func apply_upgrade(upgrade: Dictionary) -> void:
	apply_upgrade_to(aircraft, upgrade)


## 对指定飞机应用静态技能效果。目标显式传入，执行期间不再改写当前操控机引用。
func _apply_upgrade_effect_to(target: Aircraft, upgrade: Dictionary) -> void:
	if target == null or not is_instance_valid(target) or target.params == null:
		return
	SurvivorSkillEffectsScript.apply(self, target, upgrade)


## （自然成长 apply_natural_growth 已退役，2026-07-19 spec player-aircraft-power-curve §6 阶段2：
##   等级只做门槛；HP/导弹成长由三轴里程碑 apply_crossed_milestones 承担，换型可重放不丢失。）


func get_hp() -> float:
	if aircraft:
		return aircraft.hp
	return 0.0

func get_max_hp() -> float:
	if aircraft and aircraft.params:
		return aircraft.params.max_hp
	return 100.0

func is_player_destroyed() -> bool:
	if aircraft:
		return aircraft.is_destroyed
	return true
