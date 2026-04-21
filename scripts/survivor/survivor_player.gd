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

func apply_upgrade(upgrade: Dictionary) -> void:
	if not aircraft or not aircraft.params:
		return
	var p := aircraft.params
	var stat: String = upgrade["stat"]

	match stat:
		"max_hp":
			var add: float = upgrade["value"]
			p.max_hp += add
			aircraft.hp += add  # 升级时也恢复
			aircraft.bullet_dodge_chance = minf(aircraft.bullet_dodge_chance + float(upgrade.get("dodge_per_stack", 0.08)), float(upgrade.get("dodge_cap", 0.40)))
		"missile_count":
			if p.missile:
				p.missile.max_count += int(upgrade["value"])
				aircraft.missiles_remaining += int(upgrade["value"])
			# AGM 属性 = AAM 属性，同步升级
			if p.secondary_missile:
				p.secondary_missile.max_count += int(upgrade["value"])
				aircraft.secondary_missiles_remaining += int(upgrade["value"])
		"missile_tracking":
			# 制导升级：导弹过载 +30%，导引常数 +0.5
			if p.missile:
				p.missile.max_g *= (1.0 + float(upgrade["value"]))
				p.missile.nav_constant += 0.5
			if p.secondary_missile:
				p.secondary_missile.max_g *= (1.0 + float(upgrade["value"]))
				p.secondary_missile.nav_constant += 0.5
		"missile_bounce":
			# 进化：连锁弹头，导弹命中后弹跳
			aircraft.missile_bounce_count = int(upgrade["value"])
		"proximity_fuze":
			# 进化：近炸引信，导弹爆炸产生 AOE 区域
			aircraft.missile_proximity_aoe = true
		"missile_reload":
			aircraft.missile_reload_duration *= (1.0 - float(upgrade["value"]))
		"multi_lock":
			aircraft.max_simultaneous_locks += int(upgrade["value"])
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
		"flare_shield":
			# 电子对抗套件：每层增加锁定免疫时间
			aircraft.flare_lock_immunity += float(upgrade["value"])
			# 额外赠送热诱弹
			var _bf: int = int(upgrade.get("bonus_flares", 2))
			if p.flare:
				p.flare.max_flares += _bf
				aircraft.flares_remaining += _bf
		"pilot_stamina":
			# 体能强化：耐力上限×2，恢复速率×2
			p.pilot_stamina *= float(upgrade.get("stamina_mult", 2.0))
			aircraft.pilot_stamina = p.pilot_stamina
			p.stamina_recovery_rate *= float(upgrade.get("recovery_mult", 2.0))
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
			if p.secondary_missile:
				p.secondary_missile = p.secondary_missile.duplicate()
				p.secondary_missile.seeker_fov = minf(p.secondary_missile.seeker_fov * fov_mult, fov_cap)
		"gun_accuracy":
			# 枪械精度：spread_angle ×(1-value)，硬 floor min_deg
			if p.gun:
				p.gun = p.gun.duplicate()
				p.gun.spread_angle = maxf(p.gun.spread_angle * (1.0 - float(upgrade["value"])), float(upgrade.get("min_deg", 0.1)))
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
		"fire_and_forget":
			# 射后不理（战区奖励）：玩家所有导弹发射后不需要持续照射
			if p.missile:
				p.missile = p.missile.duplicate()
				p.missile.fire_and_forget = true
			if p.secondary_missile:
				p.secondary_missile = p.secondary_missile.duplicate()
				p.secondary_missile.fire_and_forget = true
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
		"lock_resistance":
			# 强化吊舱：敌人对我累积锁定速率 ÷ lock_resistance_mult（可堆叠）
			aircraft.lock_resistance_mult *= (1.0 + float(upgrade["value"]))
		"kill_heal":
			# 战场急救：击杀回血，叠加层数记录在 aircraft 上
			aircraft.kill_heal_amount += float(upgrade["value"])
		"dogfight":
			# 格斗大师：降低失速速度、增强减速、改善低速追踪
			p.stall_speed_base *= float(upgrade.get("stall_speed_mult", 0.88))
			p.deceleration *= float(upgrade.get("decel_mult", 1.3))
			p.g_drag_factor *= float(upgrade.get("g_drag_mult", 1.2))
			if p.combat:
				p.combat = p.combat.duplicate()
				p.combat.overshoot_speed_margin *= float(upgrade.get("overshoot_speed_margin_mult", 0.97))
				p.combat.turn_slow_speed_mult *= float(upgrade.get("turn_slow_speed_mult", 0.9))

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
