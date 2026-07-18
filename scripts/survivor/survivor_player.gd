class_name SurvivorPlayer
extends Node

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
## 已生效的里程碑档位（axis → 已应用的 points 档数组）；
## 里程碑应用器（阶段 2）用它做增量应用与换型重放，本阶段仅占位。
var applied_milestones: Dictionary = {}

func add_axis_point(axis: StringName, profile: PlayableAircraft = null) -> void:
	if not axis_points.has(axis):
		push_warning("SurvivorPlayer.add_axis_point: 未知属性轴 %s" % axis)
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

# ── 三轴里程碑应用器（spec evolution-attribute-gates §2.6/§2.7，阶段 2）──

## 加点后应用该轴新跨过的里程碑档（增量、幂等：applied_milestones 记账防重复）。
## 无飞机时不应用也不记账——等飞机就位后重放补上。profile = 起手机覆写表来源。
func apply_crossed_milestones(axis: StringName, profile: PlayableAircraft = null) -> void:
	if not aircraft or not aircraft.params:
		return
	var pts: int = get_axis_points(axis)
	var done: Array = applied_milestones.get(axis, [])
	for m in SurvivorData.milestones_for(axis, profile):
		var need: int = int(m["points"])
		if pts >= need and not done.has(need):
			_apply_milestone_effect(m)
			done.append(need)
			EventLogger.log_event("MILESTONE", "Player",
				"%s %d点 里程碑生效：%s %s" % [axis, need, str(m.get("stat")), str(m.get("value"))])
	applied_milestones[axis] = done

## 换型重放（spec §2.7 玩家层持有）：evolve() 换新 params 后调用——
## 清应用记录、把三轴已达成的全部档位重挂到新机。加成跟玩家不跟机体。
func reapply_all_milestones(profile: PlayableAircraft = null) -> void:
	applied_milestones = {}
	for axis in SurvivorData.AXES:
		apply_crossed_milestones(axis, profile)
	EventLogger.log_event("MILESTONE", "Player", "换型重放完成（斗%d/骑%d/策%d 点）" % [
		get_axis_points(SurvivorData.AXIS_GLADIATOR),
		get_axis_points(SurvivorData.AXIS_KNIGHT),
		get_axis_points(SurvivorData.AXIS_SCHEMER)])

## 应用一档里程碑到当前飞机（语义与 apply_upgrade 同源；表结构见 SurvivorData.MILESTONE_TABLE）。
## mult 类 stat 的 value 是乘数（1.08）；add 类是增量。子资源先 duplicate 防共享污染。
func _apply_milestone_effect(m: Dictionary) -> void:
	if not aircraft or not aircraft.params:
		return
	var p := aircraft.params
	var v: float = float(m.get("value", 0.0))
	match str(m.get("stat", "")):
		"max_hp":
			p.max_hp += v
			aircraft.hp += v  # 达成时也恢复对应量（与升级同语义）
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
				aircraft.ammo += add_ammo
		"max_g":
			# 持续/结构极限同步抬，保持瞬时超越空间不缩水（CLAUDE.md 永久升级=直改 params，AI 经 effective_* 可见）
			p.max_g += v
			p.max_g_structural += v
		"missile_count":
			if p.missile:
				p.missile = p.missile.duplicate()
				p.missile.max_count += int(v)
				aircraft.missiles_remaining += int(v)
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
				aircraft.flares_remaining += int(v)
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

func apply_upgrade(upgrade: Dictionary) -> void:
	if not aircraft or not aircraft.params:
		return
	var p := aircraft.params
	var stat: String = upgrade["stat"]

	match stat:
		"max_hp":
			# 纯 HP 提升（已拆掉闪避加成 → 见 bullet_dodge_flat 独立技能）
			var add: float = upgrade["value"]
			p.max_hp += add
			aircraft.hp += add  # 升级时也恢复
		"bullet_dodge_flat":
			# 独立 +N% 机炮闪避（不通过 hp_up，直接累加）
			# take_bullet_damage 全局 cap MAX_BULLET_DODGE_CAP=0.85 兜底，无需此处 cap
			aircraft.bullet_dodge_chance += float(upgrade["value"])
		"missile_count":
			# 玩家无副导弹（2026-04-29），只 +主槽
			if p.missile:
				p.missile.max_count += int(upgrade["value"])
				aircraft.missiles_remaining += int(upgrade["value"])
		"missile_tracking":
			# 制导升级：导弹过载 +30%，导引常数 +0.5
			if p.missile:
				p.missile.max_g *= (1.0 + float(upgrade["value"]))
				p.missile.nav_constant += 0.5
		"missile_bounce":
			# 进化：连锁弹头，导弹命中后弹跳
			aircraft.missile_bounce_count = int(upgrade["value"])
		"proximity_fuze":
			# 进化：近炸引信，导弹爆炸产生 AOE 区域
			aircraft.missile_proximity_aoe = true
		"missile_reload":
			aircraft.missile_reload_duration *= (1.0 - float(upgrade["value"]))
		"missile_swarm":
			# 替代 multi_lock：max_count +4，同时锁定数提到一个大值（让齐射可对所有锁敌发射），
			# 负面：导弹 max_g ×0.85（轻微追踪减劣，弹群压火力不靠单发精度）
			# 单目标场景仍然只射 1 发（aircraft_weapons._fire_multi_lock_salvo 行为）
			var swarm_n: int = int(upgrade["value"])
			var penalty: float = float(upgrade.get("tracking_penalty", 0.85))
			if p.missile:
				p.missile = p.missile.duplicate()
				p.missile.max_count += swarm_n
				p.missile.max_g *= penalty
				aircraft.missiles_remaining += swarm_n
			# 提到 ≥ max_count 才能让齐射真的"全打"——硬编码到 8 兜底（max_count 通常 4-8）
			aircraft.max_simultaneous_locks = maxi(aircraft.max_simultaneous_locks, 8)
		"gun_damage":
			if p.gun:
				p.gun.bullet_damage *= (1.0 + float(upgrade["value"]))
		"gun_multishot":
			# 进化：多管齐射，额外射出左右两道子弹
			aircraft.gun_extra_barrels = int(upgrade["value"])
		"gun_ammo":
			if p.gun:
				p.gun.max_ammo += int(upgrade["value"])
				aircraft.ammo += int(upgrade["value"])
		"gun_reload":
			aircraft.gun_reload_duration *= (1.0 - float(upgrade["value"]))
		"gun_firerate":
			if p.gun:
				p.gun.fire_rate *= (1.0 + float(upgrade["value"]))
		"gun_range":
			if p.gun:
				p.gun = p.gun.duplicate()
				p.gun.max_range *= (1.0 + float(upgrade["value"]))
		"gun_ciws":
			aircraft.gun_ciws_active = true
		"radar_range":
			p.radar_range *= (1.0 + float(upgrade["value"]))
		"lock_time":
			p.lock_time = maxf(p.lock_time + float(upgrade["value"]), float(upgrade.get("min_lock_time", 0.5)))
		"speed":
			# 只抬最大速度天花板 + 加速度；不动 cruise_speed。
			# aircraft.gd 用 max(corner_speed, cruise*0.85) 作为转弯最低速度地板，
			# 若 cruise 同步放大，堆层后会把飞机压在高速上转不动弯。
			var mult := 1.0 + float(upgrade["value"])
			p.max_speed *= mult
			p.acceleration *= (1.0 + float(upgrade["value"]) * float(upgrade.get("accel_ratio", 0.5)))
		"maneuver":
			p.roll_rate *= (1.0 + float(upgrade["value"]))
			p.max_g += float(upgrade.get("max_g_bonus", 1.0))
			p.max_g_structural += float(upgrade.get("structural_g_bonus", 0.5))
		"flare_cooldown":
			if p.flare:
				p.flare.cooldown *= (1.0 - float(upgrade["value"]))
				p.flare.reload_time *= (1.0 - float(upgrade["value"]))
		"rocket_firerate_range":
			# A-10 火箭弹专属：齐射 CD 减少 + 飞行射程增加
			# value 0.25 → CD ×0.75，max_range ×1.25，max_fire_range ×1.25
			# 衰减末端 (min_damage_mult) 不动，保留"远端略弱"身份
			if p.rocket:
				p.rocket = p.rocket.duplicate()
				var v: float = float(upgrade["value"])
				p.rocket.burst_cooldown *= (1.0 - v)
				p.rocket.max_range *= (1.0 + v)
				p.rocket.max_fire_range *= (1.0 + v)
		"torpedo_tracking_boost":
			# A-10 漂浮雷专属：scan_range + turn_rate 双倍强化
			# value 0.6 → scan ×1.6，turn ×2.0
			if p.torpedo:
				p.torpedo = p.torpedo.duplicate()
				var v2: float = float(upgrade["value"])
				p.torpedo.tracking_scan_range_m *= (1.0 + v2)
				p.torpedo.tracking_turn_rate_dps *= (1.0 + v2 + v2)  ## 1 + 0.6 + 0.6 = ×2.2，第二层 ×3.4 阈值递增明显
		"laser_extra_beams":
			# 激光：可同时照射的目标数 +N
			# 装备数组已由 SurvivorPlayableSetup.deep_dup_weapons 深拷贝，直接改即可
			var laser_eq := p.get_equipment_of_kind("laser") as LaserEquipment
			if laser_eq:
				laser_eq.max_simultaneous_targets += int(upgrade["value"])
		"flare_shield":
			# 电子对抗套件：每层增加锁定免疫时间
			aircraft.flare_lock_immunity += float(upgrade["value"])
			# 额外赠送热诱弹
			var _bf: int = int(upgrade.get("bonus_flares", 2))
			if p.flare:
				p.flare.max_flares += _bf
				aircraft.flares_remaining += _bf
		"fear_squad_spread":
			# 恐惧扩散：玩家击杀任意敌机后对同小队成员施加 FEAR
			aircraft.fear_squad_spread_duration = float(upgrade["value"])
		"fear_chills":
			# 寒颤：所有由玩家施加的 FEAR 同步附带 SLOW
			aircraft.fear_applies_slow = true
		"armor":
			# 复合装甲：DR 软上限公式 armor/(armor+100)；导弹按 50% 穿甲计算
			p.armor += float(upgrade["value"])
		"xp_mult":
			# 经验倍率：每层 +20% 累加，硬顶 ×1.4
			aircraft.xp_multiplier = minf(aircraft.xp_multiplier + float(upgrade["value"]), float(upgrade.get("xp_cap", 1.4)))
		"radar_angle":
			# 广角扫描：radar_half_angle ×(1+value)，硬 cap max_deg
			p.radar_half_angle = minf(p.radar_half_angle * (1.0 + float(upgrade["value"])), float(upgrade.get("max_deg", 90.0)))
		"seeker_fov":
			# 广角导引头：MissileParams.seeker_fov ×(1+value)，硬 cap max_deg
			# 2026-04-21：同步 AGM（AGM 是 AAM 克隆，所有导弹升级都该覆盖）
			var fov_mult := 1.0 + float(upgrade["value"])
			var fov_cap := float(upgrade.get("max_deg", 120.0))
			if p.missile:
				p.missile = p.missile.duplicate()
				p.missile.seeker_fov = minf(p.missile.seeker_fov * fov_mult, fov_cap)
		"gun_accuracy":
			# 枪械精度：spread_angle ×(1-value)，硬 floor min_deg
			if p.gun:
				p.gun = p.gun.duplicate()
				p.gun.spread_angle = maxf(p.gun.spread_angle * (1.0 - float(upgrade["value"])), float(upgrade.get("min_deg", 0.1)))
			# 同时提升飞行员 aim_skill（lead 误差减小），与 spread 减小复合
			var aim_boost: float = float(upgrade.get("aim_skill_boost", 0.0))
			if aim_boost > 0.0:
				aircraft.pilot_aim_skill = clampf(aircraft.pilot_aim_skill + aim_boost, 0.0, 1.0)
		"aim_assist":
			# 瞄准辅助：fire_cone_half_angle ×(1+value)，硬 cap max_deg
			if p.gun:
				p.gun = p.gun.duplicate()
				p.gun.fire_cone_half_angle = minf(p.gun.fire_cone_half_angle * (1.0 + float(upgrade["value"])), float(upgrade.get("max_deg", 45.0)))
		"missile_boost":
			# 火箭助推：cooldown ×0.85 + burn_time ×1.15 + motor_accel ×1.10（每层复合）
			if p.missile:
				p.missile = p.missile.duplicate()
				p.missile.cooldown *= float(upgrade.get("cooldown_mult", 0.85))
				p.missile.motor_burn_time *= float(upgrade.get("burn_mult", 1.15))
				p.missile.motor_acceleration *= float(upgrade.get("accel_mult", 1.10))
		"vapor_dodge":
			# 云雾机动（战区奖励）：高度切换 ×2 + 云中任意档位锁定速率 ×0.1
			aircraft.altitude_authority_mult *= float(upgrade.get("altitude_mult", 2.0))
			aircraft.cloud_lock_stealth = true
		"ecm_pod":
			# ECM 吊舱（战区奖励）：敌方雷达对我的有效距离 ×0.75
			aircraft.ecm_range_mult *= float(upgrade.get("range_mult", 0.75))
		"shock_absorb":
			# 冲击吸收（战区奖励）：伤害的 40% 慢慢回血
			aircraft.shock_absorb_active = true
		"cobra_skill":
			# 眼镜蛇机动技能：开启自动触发 + 确保玩家身上挂 CobraManeuver 子节点
			aircraft.cobra_skill_active = true
			var has_cobra := false
			for child in aircraft.get_children():
				if child is CobraManeuver:
					has_cobra = true
					break
			if not has_cobra:
				var cobra := CobraManeuver.new()
				cobra.name = "CobraManeuver"
				aircraft.add_child(cobra)
		"executioner":
			# 侩子手（战区奖励）：连续不受伤击杀堆层，最高 5 层
			aircraft.executioner_active = true
		# ── X-02 电磁炮升级 ──
		"railgun_charge":
			# 充能时间 -20%（每层）
			var rg := p.get_equipment_of_kind("railgun") as RailgunEquipment
			if rg:
				rg.charge_duration *= (1.0 - float(upgrade["value"]))
		"railgun_range":
			var rg2 := p.get_equipment_of_kind("railgun") as RailgunEquipment
			if rg2:
				rg2.max_range_m += float(upgrade["value"])
		"railgun_damage":
			var rg3 := p.get_equipment_of_kind("railgun") as RailgunEquipment
			if rg3:
				rg3.damage *= (1.0 + float(upgrade["value"]))
		# ── X-02 激光升级 ──
		"laser_cooldown":
			# 散热效率 +25%（每层）
			var le := p.get_equipment_of_kind("laser") as LaserEquipment
			if le:
				le.heat_cooldown_per_second *= (1.0 + float(upgrade["value"]))
		"laser_range":
			var le2 := p.get_equipment_of_kind("laser") as LaserEquipment
			if le2:
				le2.max_range_m *= (1.0 + float(upgrade["value"]))
		"laser_heat":
			# 过热阈值 +30% → 输出更久
			var le3 := p.get_equipment_of_kind("laser") as LaserEquipment
			if le3:
				le3.heat_max *= (1.0 + float(upgrade["value"]))
		"lock_resistance":
			# 强化吊舱：敌人对我累积锁定速率 ÷ lock_resistance_mult（可堆叠）
			aircraft.lock_resistance_mult *= (1.0 + float(upgrade["value"]))
		"kill_heal":
			# 战场急救：击杀回血，叠加层数记录在 aircraft 上
			aircraft.kill_heal_amount += float(upgrade["value"])
		"data_link":
			# F-14 数据链：长机 aura_skill 标记开启 + 现役队友（team 0 飞机）雷达范围加成
			# 锁定共享由 survivor_mode._update_radar_locks 读 aura_skill 触发；发射仍受
			# cone/envelope/range 校验（aircraft_weapons.gd），"看不见就能射" 不会发生
			aircraft.aura_skill = &"data_link"
			var radar_mult := 1.0 + float(upgrade["value"])
			for u in CombatUnit.all_units:
				if not is_instance_valid(u):
					continue
				if u is Aircraft and u.is_player_squad() and u != aircraft and u.params:
					u.params.radar_range *= radar_mult
		"dogfight":
			# 格斗大师：降低失速速度、增强减速、改善低速追踪
			p.stall_speed_base *= float(upgrade.get("stall_speed_mult", 0.88))
			p.deceleration *= float(upgrade.get("decel_mult", 1.3))
			p.g_drag_factor *= float(upgrade.get("g_drag_mult", 0.85))
			if p.combat:
				p.combat = p.combat.duplicate()
				p.combat.overshoot_speed_margin *= float(upgrade.get("overshoot_speed_margin_mult", 0.97))
				p.combat.turn_slow_speed_mult *= float(upgrade.get("turn_slow_speed_mult", 0.9))
		# ── §1.2 evasion_modifiers 写入（边界差量见 aircraft.set_evasion_mode）──
		"evasion_speed_boost":
			# evasion 模式 cruise 速度倍率（physics.update_speed 每帧查 evasion_mode + 此 mult）
			_set_evasion_modifier(aircraft, "cruise_speed_mult", float(upgrade["value"]))
		"evasion_weapon_cd":
			# evasion 模式武器 cd 倍率（gun + missile + rocket 三路；切换瞬间一次性 scale）
			_set_evasion_modifier(aircraft, "weapon_cd_mult", float(upgrade["value"]))
		"evasion_flare_cd":
			# evasion 模式 flare cd 倍率
			_set_evasion_modifier(aircraft, "flare_cd_mult", float(upgrade["value"]))
		"evasion_missile_reload":
			# evasion 模式导弹装填倍率
			_set_evasion_modifier(aircraft, "missile_reload_mult", float(upgrade["value"]))
		# ── C 阶段数值技能 ──
		"lock_panic_g":
			# 被锁时机动加成（每层 +20%，physics.effective_max_g 末乘）
			aircraft.lock_panic_g_mult *= (1.0 + float(upgrade["value"]))
		"low_hp_flare_reload":
			# hp < 50% 时 flare reload 倍率（flares.update reload 累加时查）
			aircraft.low_hp_flare_reload_mult = float(upgrade["value"])
		"high_alt_lock_speed":
			# HIGH 档时锁定速率 bonus（main.gd 雷达循环）
			aircraft.high_alt_lock_speed_bonus = float(upgrade["value"])
		"ab_gun_regen":
			# AB 时机炮 regen/sec（weapons.update_gun 在 ab=true 时累加）
			aircraft.ab_gun_regen_per_sec = float(upgrade["value"])
		"alt_change_stealth":
			# 高度变化时 lock_rate 衰减系数（main.gd 雷达循环）
			aircraft.alt_change_stealth_factor = float(upgrade["value"])
		"head_on_gun_dodge":
			# 对头时机炮闪避加成（take_bullet_damage 几何检查）
			aircraft.head_on_gun_dodge_bonus = float(upgrade["value"])
		"gun_fire_dr":
			# 机炮发射时减伤窗口（aircraft_weapons 开火后刷时间戳；_apply_damage 查）
			aircraft.gun_fire_dr_window = float(upgrade.get("window", 0.4))
			aircraft.gun_fire_dr_amount = float(upgrade["value"])
		"fear_on_lock":
			# 锁定累积达 N 秒后给目标施 FEAR（survivor_mode._update_radar_locks 维护）
			aircraft.fear_on_lock_threshold = float(upgrade["value"])
		"cloud_overload":
			# 进/出云事件 toggle OVERLOAD（aircraft._on_cloud_boundary）
			aircraft.cloud_overload_active = true
		"cloud_weapon_cd":
			# 进/出云事件按倍率 scale 武器 cd（同 evasion_modifiers 模式）
			aircraft.cloud_weapon_cd_mult = float(upgrade["value"])
		"evasion_stealth":
			# 进入 evasion 时启用 STEALTH（独立 bool + 派生 OR；不进 status_effects 避免冲突）
			aircraft.evasion_stealth_active = true
			# 若当前已在 evasion → 立刻同步进派生
			if aircraft.evasion_mode:
				aircraft._in_evasion_stealth = true
		"evasion_overstock":
			# evasion 期间每 N 秒装填 1 发导弹，突破 max_count×2
			aircraft.evasion_overstock_interval = float(upgrade["value"])
		"missile_cd_stealth":
			# 导弹 cd / 装填期间获得 STEALTH（独立 bool + 派生 OR）
			aircraft.missile_cd_stealth_active = true
		"head_on_jam":
			# 我对头某敌人累积 N 秒后给该敌人 JAM
			aircraft.head_on_jam_threshold = float(upgrade["value"])
		"rear_aura_slow":
			# 后半球内敌人每 0.5s 获得 SLOW
			aircraft.rear_aura_slow_radius_px = float(upgrade["value"])
		"low_alt_gun_dodge":
			# 低空时机炮闪避加成（take_bullet_damage LOW/GROUND 分支）
			aircraft.low_alt_gun_dodge_bonus = float(upgrade["value"])
		"jam_aura":
			# 全向 JAM 光环（每 0.5s 半径内敌人 JAM 1.5s）
			aircraft.jam_aura_radius_px = float(upgrade["value"])
		"f14_squad_lock_slow":
			# F-14 专属：全僚机锁定同一敌机时给该敌机施加 SLOW（survivor_mode 雷达循环维护）
			aircraft.f14_squad_lock_slow_active = true
		"evasion_herbst":
			# evasion 模式被攻击启动 J-Turn（钩子在 SkillHooks.dispatch_on_hit）
			# 必须确保 HerbstManeuver 子节点存在
			aircraft.evasion_herbst_active = true
			var has_herbst := false
			for child in aircraft.get_children():
				if child is HerbstManeuver:
					has_herbst = true
					break
			if not has_herbst:
				var hm := HerbstManeuver.new()
				hm.name = "HerbstManeuver"
				aircraft.add_child(hm)

## §1.2 写 evasion_modifiers 倍率
## 关键：若玩家正处于 evasion 模式，先切出再切回 → 让 set_evasion_mode 重新按新倍率
## 缩放当前 cd（保持"边界差量"语义一致，不会因为升级时机不同而出现 cd 错配）
func _set_evasion_modifier(ac: Aircraft, key: String, mult: float) -> void:
	if ac == null:
		return
	var was_evasion: bool = ac.evasion_mode
	if was_evasion:
		ac.set_evasion_mode(false)  # 先 unscale 当前 cd 回正常时间轴
	ac.evasion_modifiers[key] = mult
	if was_evasion:
		ac.set_evasion_mode(true)   # 再按新倍率 scale 当前 cd


## 应用自然成长差量：把 from_level → to_level 的累计 HP/导弹增量加到飞机上
## 由 survivor_mode 在 leveled_up 时调用（profile 可空走默认曲线）
## 同步刷 aircraft.hp（升级回血对应量）和 missiles_remaining（含主+副槽）
func apply_natural_growth(from_level: int, to_level: int, profile: PlayableAircraft = null) -> void:
	if not aircraft or not aircraft.params or to_level <= from_level:
		return
	var prev: Dictionary = SurvivorData.player_growth_at(from_level, profile)
	var curr: Dictionary = SurvivorData.player_growth_at(to_level, profile)
	var hp_delta: int = int(curr["hp"]) - int(prev["hp"])
	var missile_delta: int = int(curr["missile"]) - int(prev["missile"])
	if hp_delta == 0 and missile_delta == 0:
		return
	var p := aircraft.params
	if hp_delta > 0:
		p.max_hp += float(hp_delta)
		aircraft.hp += float(hp_delta)
	if missile_delta > 0:
		# 玩家只有主导弹槽（2026-04-29 决策），副槽逻辑已移除
		if p.missile:
			p.missile.max_count += missile_delta
			aircraft.missiles_remaining += missile_delta
	EventLogger.log_event("GROWTH", "Player",
		"L%d → L%d: +%d HP, +%d missile(s)" % [from_level, to_level, hp_delta, missile_delta])


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
