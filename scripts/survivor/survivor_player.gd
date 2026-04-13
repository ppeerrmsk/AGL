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

func _ready() -> void:
	xp_to_next = SurvivorData.xp_for_level(2)

func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = SurvivorData.xp_for_level(level + 1)
		EventLogger.log_event("LEVEL", "Player",
			"level up → %d (next=%d xp)" % [level, xp_to_next])
		leveled_up.emit(level)

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
			aircraft.bullet_dodge_chance = minf(aircraft.bullet_dodge_chance + 0.08, 0.40)  # 每层+8%，上限40%
		"missile_count":
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
			p.lock_time = maxf(p.lock_time + float(upgrade["value"]), 0.5)
		"speed":
			var mult := 1.0 + float(upgrade["value"])
			p.max_speed *= mult
			p.cruise_speed *= mult
			p.acceleration *= (1.0 + float(upgrade["value"]) * 0.5)  # 加速也跟着涨一半
		"maneuver":
			p.roll_rate *= (1.0 + float(upgrade["value"]))
			p.max_g += 1.0
			p.max_g_structural += 0.5  # 结构极限也提升
		"flare_cooldown":
			if p.flare:
				p.flare.cooldown *= (1.0 - float(upgrade["value"]))
				p.flare.reload_time *= (1.0 - float(upgrade["value"]))
		"flare_shield":
			# 电子对抗套件：每层增加锁定免疫时间
			aircraft.flare_lock_immunity += float(upgrade["value"])
			# 额外赠送热诱弹
			if p.flare:
				p.flare.max_flares += 2
				aircraft.flares_remaining += 2
		"pilot_stamina":
			# 体能强化：耐力上限×2，恢复速率×2
			p.pilot_stamina *= 2.0
			aircraft.pilot_stamina = p.pilot_stamina  # 立即充满
			p.stamina_recovery_rate *= 2.0
		"kill_heal":
			# 战场急救：击杀回血，叠加层数记录在 aircraft 上
			aircraft.kill_heal_amount += float(upgrade["value"])
		"dogfight":
			# 格斗大师：降低失速速度、增强减速、改善低速追踪
			p.stall_speed_base *= 0.88       # -12% 失速速度 → 更紧的低速转弯
			p.deceleration *= 1.3            # +30% 减速能力 → 更快刹车防冲过
			p.g_drag_factor *= 1.2           # +20% G力阻力 → 转弯时自然减速更多
			if p.combat:
				p.combat = p.combat.duplicate()
				p.combat.overshoot_speed_margin *= 0.97  # 更精确速度匹配
				p.combat.turn_slow_speed_mult *= 0.9     # 大角度转向时减速更多

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
