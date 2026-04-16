class_name MissileManager
extends Node2D

const PIXELS_PER_METER: float = 0.5

## ── 近炸引信 AOE 常量 ──
const AOE_RADIUS_M: float = 120.0       ## AOE 半径（米）
const AOE_DURATION: float = 1.5         ## 持续时间（秒）
const AOE_ALT_TOLERANCE: float = 300.0  ## 高度容差（米）

var _missile_scene: PackedScene = preload("res://scenes/missile.tscn")

## 场景中所有战斗单位的缓存引用，由 main.gd 每帧更新
var target_list: Array[CombatUnit] = []

## 活跃的 AOE 区域列表
var _aoe_zones: Array = []  # [{pos, altitude, radius_px, time_left, max_time, damage, team, hit_set}]

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

	# 连锁弹头 / 近炸引信进化：仅 Aircraft 有此属性
	if source is Aircraft:
		missile.bounces_remaining = source.missile_bounce_count
		missile.proximity_aoe = source.missile_proximity_aoe
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

## 计数：某射手对某目标在飞的导弹数
func count_active_missiles_at(source: CombatUnit, target: CombatUnit) -> int:
	var count := 0
	for child in get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if m.is_active and m.source == source and m.target == target:
				count += 1
	return count

func _physics_process(delta: float) -> void:
	# ── 导弹命中检测 ──
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
			# 光学隐形：导弹从隐形目标穿过
			if unit is Aircraft and unit.is_cloaked:
				continue
			# 导弹穿透窗口：flare 释放后 1 秒内所有导弹从此单位穿过
			if unit is Aircraft and unit.missile_phase_timer > 0.0:
				continue
			# 2D 距离 + 高度容差（地面单位/flat_altitude 模式跳过高度检查）
			var dist_2d := missile.global_position.distance_to(unit.global_position)
			var flat := unit is Aircraft and unit.flat_altitude
			var alt_ok := flat or unit is GroundUnit or absf(missile.altitude - unit.altitude) < missile.params.proximity_fuse_alt
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
				# 近炸引信：在爆炸点产生 AOE 区域
				if missile.proximity_aoe:
					_spawn_aoe(missile.global_position, missile.altitude,
						missile.params.damage, missile.team, unit)
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

	# ── AOE 区域更新 ──
	_update_aoe_zones(delta)

## 创建 AOE 区域
func _spawn_aoe(pos: Vector2, alt: float, damage: float, team: int, direct_hit: CombatUnit) -> void:
	var hit_set := {}
	# 直接命中的单位已受伤，不重复伤害
	if is_instance_valid(direct_hit):
		hit_set[direct_hit.get_instance_id()] = true
	var zone := {
		"pos": pos,
		"altitude": alt,
		"radius_px": AOE_RADIUS_M * PIXELS_PER_METER,
		"time_left": AOE_DURATION,
		"max_time": AOE_DURATION,
		"damage": damage,
		"team": team,
		"hit_set": hit_set,
	}
	_aoe_zones.append(zone)
	EventLogger.log_event("AOE", "ProxFuze",
		"spawned at (%.0f,%.0f) alt=%.0f r=%.0fm dmg=%.0f" % [
			pos.x, pos.y, alt, AOE_RADIUS_M, damage])

## 每帧更新 AOE 区域：检测新进入的敌方单位，渐退后移除
func _update_aoe_zones(delta: float) -> void:
	if _aoe_zones.is_empty():
		return
	var needs_redraw := false
	var i := _aoe_zones.size() - 1
	while i >= 0:
		var zone: Dictionary = _aoe_zones[i]
		zone["time_left"] -= delta
		if zone["time_left"] <= 0.0:
			_aoe_zones.remove_at(i)
			needs_redraw = true
			i -= 1
			continue
		# 检测圈内新敌方单位
		var zpos: Vector2 = zone["pos"]
		var zalt: float = zone["altitude"]
		var zradius: float = zone["radius_px"]
		var zteam: int = zone["team"]
		var zdmg: float = zone["damage"]
		var zhit: Dictionary = zone["hit_set"]
		for unit in target_list:
			if not is_instance_valid(unit) or unit.is_destroyed:
				continue
			if unit.team == zteam:
				continue
			var uid := unit.get_instance_id()
			if zhit.has(uid):
				continue
			var dist_2d := zpos.distance_to(unit.global_position)
			var alt_diff := absf(zalt - unit.altitude)
			var alt_ok := alt_diff < AOE_ALT_TOLERANCE or unit is GroundUnit
			if dist_2d < zradius and alt_ok:
				unit.take_damage(zdmg)
				zhit[uid] = true
				var tgt_name: String = unit.callsign if unit.callsign != "" else unit.name
				EventLogger.log_event("AOE", "ProxFuze",
					"hit %s (dmg=%.0f)" % [tgt_name, zdmg])
		needs_redraw = true
		i -= 1
	if needs_redraw:
		queue_redraw()

func _draw() -> void:
	# 渲染 AOE 红圈
	for zone in _aoe_zones:
		var ratio: float = zone["time_left"] / zone["max_time"]
		var alpha := ratio * 0.35
		var pos: Vector2 = zone["pos"] - global_position  # 转为本地坐标
		var radius: float = zone["radius_px"]
		# 半透明填充
		draw_circle(pos, radius, Color(1.0, 0.15, 0.1, alpha * 0.4))
		# 描边
		draw_arc(pos, radius, 0.0, TAU, 48, Color(1.0, 0.2, 0.1, alpha), 2.0)

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
