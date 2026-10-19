extends RefCounted
## 完全体与 FANG 的独立机体资源；增强只进入参数，不装额外机动技能。

static func make_airframe(fang: bool = false) -> AircraftParams:
	var p := AircraftParams.new()
	p.display_name = "FANG" if fang else "ORION"
	p.is_unmanned = true
	p.max_hp = 250.0 if fang else 600.0
	p.armor = 0.0
	p.max_speed = 2800.0 if fang else 3000.0
	p.cruise_speed = 1500.0 if fang else 1600.0
	p.stall_speed_base = 170.0 if fang else 180.0
	p.acceleration = 80.0 if fang else 90.0
	p.deceleration = 100.0 if fang else 150.0
	p.max_g = 16.0 if fang else 18.0
	p.max_g_structural = 18.0 if fang else 24.0
	p.roll_rate = 6.0
	p.max_altitude = 15000.0
	p.climb_rate_max = 300.0 if fang else 260.0
	p.radar_range = 3000.0 if fang else 4400.0
	p.radar_half_angle = 90.0 if fang else 60.0
	p.lock_time = 1.2 if fang else 2.6
	p.visual_length_m = 14.0 if fang else 36.0
	p.visual_span_m = 18.0 if fang else 44.0
	p.icon_color = Color(0.9, 0.94, 1.0)
	p.wing_color = Color(0.3, 0.8, 1.0)
	p.combat = preload("res://resources/default_combat.tres").duplicate(true)
	if not fang:
		p.flare = preload("res://resources/default_flare.tres").duplicate(true)
		p.flare.max_flares = 2
		p.flare.burst_count = 1
		p.flare.reload_time = 20.0
	return p


static func make_admm() -> MissileParams:
	var p := MissileParams.new()
	p.display_name = "ADMM"
	p.damage = 35.0
	p.max_speed = 2600.0 / 3.6
	p.max_g = 18.0
	p.max_lifetime = 14.0
	p.max_count = 16
	p.min_range = 0.0
	p.is_vls_salvo = true
	p.vls_climb_time = 0.7
	p.vls_transition_time = 0.35
	p.vls_speed_variance = 0.0
	# 主动雷达仍走热诱弹与断制导判定；与 AGM 的抗诱饵模式分开。
	p.active_radar_guidance = true
	p.airborne_vertical_launch = true
	return p
