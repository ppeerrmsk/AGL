class_name MissileManager
extends Node2D

const PIXELS_PER_METER: float = 0.5

var _missile_scene: PackedScene = preload("res://scenes/missile.tscn")

## 场景中所有战斗单位的缓存引用，由 main.gd 每帧更新
var target_list: Array[CombatUnit] = []

func spawn_missile(source: CombatUnit, target: CombatUnit, missile_params: MissileParams) -> void:
	var missile: Missile = _missile_scene.instantiate()
	missile.params = missile_params
	missile.source = source
	missile.target = target
	missile.team = source.team
	missile.heading = source.heading
	missile.speed = source.speed + 50.0  # 初速 = 发射单位速度 + 50 m/s
	missile.altitude = source.altitude

	# 初始位置：发射单位前方 15px
	var fwd := Vector2(sin(source.heading), -cos(source.heading))
	missile.global_position = source.global_position + fwd * 15.0

	# 初始化 LOS 角，避免第一帧 PN 尖峰
	var los := target.global_position - missile.global_position
	missile._prev_los_angle = atan2(los.x, -los.y)

	# 连锁弹头进化：仅 Aircraft 有此属性
	if source is Aircraft:
		missile.bounces_remaining = source.missile_bounce_count
	else:
		missile.bounces_remaining = 0

	add_child(missile)

## 检查某目标是否已有在飞的导弹（由指定发射单位发射）
func has_active_missile_at(source: CombatUnit, target: CombatUnit) -> bool:
	for child in get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if m.is_active and m.source == source and m.target == target:
				return true
	return false

func _physics_process(_delta: float) -> void:
	for child in get_children():
		if not child is Missile:
			continue
		var missile: Missile = child as Missile

		if not missile.is_active:
			missile.queue_free()
			continue

		# 引信武装时间检查
		if missile.age < missile.params.guidance_delay:
			continue

		# 命中检测：遍历所有敌方单位
		var fuse_radius_px := missile.params.proximity_fuse_radius * PIXELS_PER_METER
		for unit in target_list:
			if not is_instance_valid(unit) or unit.is_destroyed:
				continue
			if unit.team == missile.team:
				continue
			# 导弹穿透窗口：flare 释放后 1 秒内所有导弹从此单位穿过
			if unit is Aircraft and unit.missile_phase_timer > 0.0:
				continue
			# 2D 距离 + 高度容差（地面单位跳过高度检查）
			var dist_2d := missile.global_position.distance_to(unit.global_position)
			var alt_diff := absf(missile.altitude - unit.altitude)
			var alt_ok := alt_diff < missile.params.proximity_fuse_alt or unit is GroundUnit
			if dist_2d < fuse_radius_px and alt_ok:
				var msl_name: String = missile.params.display_name if missile.params else "MSL"
				var hit_unit: CombatUnit = unit as CombatUnit
				var tgt_name: String = hit_unit.callsign if hit_unit.callsign != "" else hit_unit.name
				if unit is Aircraft and unit.params:
					var side := "Friend" if unit.team == 0 else "Enemy"
					tgt_name = "%s/%s[%s]" % [side, unit.params.display_name, unit.callsign]
				EventLogger.log_event("MISSILE", msl_name,
					"hit %s (dmg=%.0f)" % [tgt_name, missile.params.damage])
				unit.take_damage(missile.params.damage)
				# 连锁弹头：弹跳至最近的其他敌方单位
				if missile.bounces_remaining > 0:
					var next_target := _find_bounce_target(missile, unit)
					if next_target:
						missile.bounces_remaining -= 1
						missile.target = next_target
						missile.is_flare_jammed = false
						missile.has_guidance = true
						var los := next_target.global_position - missile.global_position
						missile._prev_los_angle = atan2(los.x, -los.y)
						var bounce_name: String = next_target.callsign if next_target.callsign != "" else next_target.name
						EventLogger.log_event("MISSILE", msl_name,
							"bounce → %s (bounces_left=%d)" % [
								bounce_name, missile.bounces_remaining])
						break
				missile.is_active = false
				missile.queue_free()
				break

## 寻找弹跳目标：最近的存活敌方单位（排除刚命中的）
func _find_bounce_target(missile: Missile, just_hit: CombatUnit) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for unit in target_list:
		if not is_instance_valid(unit) or unit.is_destroyed:
			continue
		if unit == just_hit or unit.team == missile.team:
			continue
		var dist := missile.global_position.distance_to(unit.global_position)
		if dist < best_dist:
			best_dist = dist
			best = unit
	return best
