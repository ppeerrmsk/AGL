class_name Tier3SuperCannonPart
extends GroundUnit

## 三级巨炮的完整单体。历史文件名保留以避免资源路径漂移；运行时只有一个
## GroundUnit/TGT，圆形底座与旋转炮管共用同一伤害、锁定和销毁生命周期。

enum FireState { IDLE, WARNING, FLIGHT }

const DISPLAY_NAME := "AURORA LANCE"
const MIN_RANGE_PX := 2500.0       ## 5 km 近身死区
const MAX_RANGE_PX := 44000.0      ## 88 km，扩大跨区覆盖范围
const TURN_RATE_RAD_S := deg_to_rad(12.0)
const ALIGN_TOLERANCE_RAD := deg_to_rad(3.0)
const WARNING_FILL_S := 4.0
const WARNING_FLASH_S := 1.5
const WARNING_S := WARNING_FILL_S + WARNING_FLASH_S
const WARNING_MIN_WIDTH_PX := 4.0
const WARNING_FLASH_HZ := 3.0
const PROJECTILE_SPEED_PX_S := 12000.0  ## 24000 m/s；高速弹迹只负责表现
const AOE_RADIUS_PX := 90.0        ## 180 m 半径 / 360 m 全宽直线危险带
const AOE_DAMAGE := 45.0
const FIRE_COOLDOWN_S := 12.0
const FIRST_FIRE_DELAY_S := 4.0
const SHOT_OVERSHOOT_PX := 6000.0  ## 锁定目标后再延伸 12 km
const MUZZLE_DISTANCE_PX := 116.0
const END_FADE_START := 0.82
const PROJECTILE_TRAIL_PX := 680.0

var cannon_group_id: StringName = &""

var _fire_state: FireState = FireState.IDLE
var _cooldown_s: float = FIRST_FIRE_DELAY_S
var _warning_s: float = 0.0
var _shot_start: Vector2 = Vector2.ZERO
var _shot_end: Vector2 = Vector2.ZERO
var _shot_progress_px: float = 0.0
var _aim_target_id: int = 0
var _threat_enabled: bool = true


func configure(group_id: StringName) -> void:
	cannon_group_id = group_id
	max_ground_speed = 0.0
	target_position = Vector2.INF
	# 复用 AA 参数只为取得地面单位基础字段；巨炮没有普通 GUN 弹药。
	ammo = 0


static func target_in_range(distance_px: float) -> bool:
	return distance_px >= MIN_RANGE_PX and distance_px <= MAX_RANGE_PX


static func point_distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _physics_process_impl(delta: float) -> void:
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return
	StatusEffects.tick(self, delta)
	if not _threat_enabled:
		if is_hovered or is_locked or incoming_lock_progress > 0.0:
			queue_redraw()
		return
	_update_body_fire(delta)
	# 固定基盘不旋转；heading 变化只重提炮架几何。预警/弹迹和锁框持续刷新动画。
	if _fire_state != FireState.IDLE or is_hovered or is_locked \
			or incoming_lock_progress > 0.0:
		queue_redraw()


func _update_body_fire(delta: float) -> void:
	match _fire_state:
		FireState.IDLE:
			_cooldown_s = maxf(_cooldown_s - delta, 0.0)
			var player := AircraftRenderer.safe_player_ref()
			if player == null or player.is_destroyed:
				_aim_target_id = 0
				return
			var target := _live_aim_target()
			if target == null or not target_in_range(
					global_position.distance_to(target.global_position)):
				target = _choose_aim_target(player)
			if target == null:
				return
			var to_target := target.global_position - global_position
			var target_heading := atan2(to_target.x, -to_target.y)
			_set_body_heading(rotate_toward(
				heading, target_heading, TURN_RATE_RAD_S * delta))
			if _cooldown_s <= 0.0 and absf(angle_difference(heading, target_heading)) \
					<= ALIGN_TOLERANCE_RAD:
				_begin_warning(target.global_position, target.callsign)
		FireState.WARNING:
			_warning_s = maxf(_warning_s - delta, 0.0)
			if _warning_s <= 0.0:
				_fire_snapshot()
		FireState.FLIGHT:
			_update_projectile(delta)


func _set_body_heading(value: float) -> void:
	if is_equal_approx(heading, value):
		return
	heading = value
	# 根 CanvasItem 与基盘保持固定，只有 `_draw_rotating_turret` 消费 heading。
	queue_redraw()


static func warning_elapsed_s(remaining_s: float) -> float:
	return clampf(WARNING_S - remaining_s, 0.0, WARNING_S)


static func warning_fill_ratio(remaining_s: float) -> float:
	return clampf(warning_elapsed_s(remaining_s) / WARNING_FILL_S, 0.0, 1.0)


static func warning_is_flashing(remaining_s: float) -> bool:
	return warning_elapsed_s(remaining_s) >= WARNING_FILL_S


static func warning_width_px(remaining_s: float) -> float:
	return lerpf(WARNING_MIN_WIDTH_PX, AOE_RADIUS_PX * 2.0,
		warning_fill_ratio(remaining_s))


static func warning_flash_bright(remaining_s: float) -> bool:
	if not warning_is_flashing(remaining_s):
		return true
	var flash_elapsed := warning_elapsed_s(remaining_s) - WARNING_FILL_S
	return fmod(flash_elapsed * WARNING_FLASH_HZ, 1.0) < 0.5


func _live_aim_target() -> Aircraft:
	if _aim_target_id <= 0:
		return null
	var value: Variant = instance_from_id(_aim_target_id)
	var target := AircraftRenderer.safe_aircraft_ref(value)
	if target == null or target.is_destroyed or target.team != CombatUnit.TEAM_PLAYER:
		_aim_target_id = 0
		return null
	return target


func _eligible_aim_targets(player: Aircraft) -> Array[Aircraft]:
	var candidates: Array[Aircraft] = []
	if player == null or not is_instance_valid(player) or player.is_destroyed:
		return candidates
	var ai := player._get_ai_controller()
	var squad_value: Variant = ai.squad if ai != null else null
	if typeof(squad_value) == TYPE_OBJECT and squad_value != null \
			and is_instance_valid(squad_value) and squad_value is Squad:
		var squad := squad_value as Squad
		for i in range(squad.members.size()):
			var member_value: Variant = squad.members[i]
			var member := AircraftRenderer.safe_aircraft_ref(member_value)
			if member == null or member.is_destroyed or member.team != CombatUnit.TEAM_PLAYER:
				continue
			if target_in_range(global_position.distance_to(member.global_position)):
				candidates.append(member)
	if candidates.is_empty() and target_in_range(
			global_position.distance_to(player.global_position)):
		candidates.append(player)
	return candidates


func _choose_aim_target(player: Aircraft) -> Aircraft:
	var candidates := _eligible_aim_targets(player)
	if candidates.is_empty():
		_aim_target_id = 0
		return null
	var target := candidates[randi() % candidates.size()]
	_aim_target_id = target.get_instance_id()
	EventLogger.log_event("TIER3", "SuperCannonAim",
		"group=%s target=%s candidates=%d" % [
			cannon_group_id, target.callsign, candidates.size()])
	return target


func _begin_warning(target_snapshot: Vector2, target_callsign: String = "") -> void:
	var direction := (target_snapshot - global_position).normalized()
	if direction.length_squared() < 0.5:
		return
	_shot_start = global_position + direction * MUZZLE_DISTANCE_PX
	var shot_length := minf(maxf(global_position.distance_to(target_snapshot)
		+ SHOT_OVERSHOOT_PX, MIN_RANGE_PX), MAX_RANGE_PX)
	_shot_end = _shot_start + direction * shot_length
	_warning_s = WARNING_S
	_fire_state = FireState.WARNING
	_aim_target_id = 0
	queue_redraw()
	EventLogger.log_event("TIER3", "SuperCannonWarning",
		"group=%s target=%s length=%.0f width=%.0f" % [
			cannon_group_id, target_callsign, shot_length, AOE_RADIUS_PX])


func _fire_snapshot() -> void:
	# 预警结束即一次性结算整条危险带；高速弹迹不再承担延迟命中判定。
	var hit_count := 0
	for value in CombatUnit.all_units:
		var unit := AircraftRenderer.safe_aircraft_ref(value)
		if unit == null or unit.is_destroyed or unit.team != CombatUnit.TEAM_PLAYER:
			continue
		if point_distance_to_segment(unit.global_position, _shot_start, _shot_end) \
				> AOE_RADIUS_PX:
			continue
		unit.take_damage(AOE_DAMAGE, self, "aoe")
		hit_count += 1
		EventLogger.log_event("TIER3", "SuperCannonHit",
			"group=%s target=%s damage=%.0f" % [
				cannon_group_id, unit.callsign, AOE_DAMAGE])
	_fire_state = FireState.FLIGHT
	_shot_progress_px = 0.0
	EventLogger.log_event("TIER3", "SuperCannonFire",
		"group=%s hits=%d speed=%.0f" % [
			cannon_group_id, hit_count, PROJECTILE_SPEED_PX_S])


func _update_projectile(delta: float) -> void:
	var shot_length := (_shot_end - _shot_start).length()
	if shot_length <= 1.0:
		_finish_shot()
		return
	_shot_progress_px = minf(_shot_progress_px + PROJECTILE_SPEED_PX_S * delta,
		shot_length)
	if _shot_progress_px >= shot_length:
		_finish_shot()


func _finish_shot() -> void:
	_fire_state = FireState.IDLE
	_cooldown_s = FIRE_COOLDOWN_S
	_warning_s = 0.0
	_shot_progress_px = 0.0
	_aim_target_id = 0
	queue_redraw()


func cease_tier3_threat() -> void:
	_threat_enabled = false
	_finish_shot()
	queue_redraw()


func _start_destroy() -> void:
	cease_tier3_threat()
	super._start_destroy()


func _draw_ground_icon() -> void:
	var color := Color(0.95, 0.32, 0.18) if team == CombatUnit.TEAM_HOSTILE \
		else Color(0.35, 0.85, 0.52)
	_draw_stationary_base(color)
	draw_set_transform(Vector2.ZERO, heading, Vector2.ONE)
	_draw_rotating_turret(color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_stationary_base(color: Color) -> void:
	var dark := color.darkened(0.58)
	var mid := color.darkened(0.38)
	# 大圆形固定基盘 + 同心回转轨道。
	draw_circle(Vector2.ZERO, 42.0, dark)
	draw_arc(Vector2.ZERO, 42.0, 0.0, TAU, 48, color, 2.5)
	draw_circle(Vector2.ZERO, 34.0, color.darkened(0.50))
	draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 40, mid, 3.0)
	draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 32, color.lightened(0.12), 1.5)
	# 三根承重臂与外圈地脚保持世界朝向不动。
	var brace_lines := PackedVector2Array()
	for angle in [deg_to_rad(-90.0), deg_to_rad(30.0), deg_to_rad(150.0)]:
		var direction := Vector2.RIGHT.rotated(angle)
		brace_lines.append(direction * 19.0)
		brace_lines.append(direction * 37.0)
		draw_circle(direction * 37.0, 3.5, mid)
	draw_multiline(brace_lines, color.darkened(0.18), 5.0, true)


func _draw_rotating_turret(color: Color) -> void:
	var dark := color.darkened(0.55)
	var mid := color.darkened(0.30)
	var light := color.lightened(0.35)
	# 回转座与向后张开的承力架。
	draw_colored_polygon(PackedVector2Array([
		Vector2(-18.0, 8.0), Vector2.ZERO,
		Vector2(-25.0, 36.0), Vector2(-34.0, 31.0)]), mid)
	draw_colored_polygon(PackedVector2Array([
		Vector2.ZERO, Vector2(18.0, 8.0),
		Vector2(34.0, 31.0), Vector2(25.0, 36.0)]), mid)
	draw_circle(Vector2.ZERO, 20.0, dark)
	draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 24, light, 2.0)
	# 参考模型的左右设备舱，中间留出炮管桁架。
	draw_rect(Rect2(-24.0, -37.0, 11.0, 45.0), dark, true)
	draw_rect(Rect2(13.0, -37.0, 11.0, 45.0), dark, true)
	draw_rect(Rect2(-24.0, -37.0, 11.0, 45.0), color, false, 1.5)
	draw_rect(Rect2(13.0, -37.0, 11.0, 45.0), color, false, 1.5)
	# 开放式双轨桁架炮管；斜撑合并为一次 multiline 提交。
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8.0, -98.0), Vector2(8.0, -98.0),
		Vector2(10.0, -18.0), Vector2(-10.0, -18.0)]), dark)
	draw_line(Vector2(-8.0, -98.0), Vector2(-10.0, -18.0), light, 2.0, true)
	draw_line(Vector2(8.0, -98.0), Vector2(10.0, -18.0), light, 2.0, true)
	var truss_lines := PackedVector2Array()
	for y in range(-92, -27, 13):
		truss_lines.append(Vector2(-7.0, float(y)))
		truss_lines.append(Vector2(7.0, float(y + 11)))
		truss_lines.append(Vector2(7.0, float(y)))
		truss_lines.append(Vector2(-7.0, float(y + 11)))
	draw_multiline(truss_lines, color.lightened(0.12), 1.2, true)
	# 前端细长炮口与后部矩形支撑架。
	draw_rect(Rect2(-5.0, -116.0, 10.0, 20.0), mid, true)
	draw_rect(Rect2(-5.0, -116.0, 10.0, 20.0), light, false, 1.5)
	var gantry_lines := PackedVector2Array([
		Vector2(-20.0, 7.0), Vector2(-27.0, 42.0),
		Vector2(-27.0, 42.0), Vector2(27.0, 42.0),
		Vector2(27.0, 42.0), Vector2(20.0, 7.0),
		Vector2(-20.0, 7.0), Vector2(20.0, 7.0)])
	draw_multiline(gantry_lines, light, 2.5, true)
	draw_circle(Vector2.ZERO, 8.0, color.lightened(0.18))


func _status_label_icon_radius_world() -> float:
	# 加长炮管任意朝向都不能钻进屏幕锁定的状态栏。
	return 120.0


func _draw_fading_shot_line(a: Vector2, b: Vector2, color: Color,
		width: float) -> void:
	var fade_start := a.lerp(b, END_FADE_START)
	var transparent := color
	transparent.a = 0.0
	var points := PackedVector2Array([a, fade_start, b])
	var colors := PackedColorArray([color, color, transparent])
	draw_polyline_colors(points, colors, width, true)


func _draw_impl() -> void:
	super._draw_impl()
	if is_destroyed or not _threat_enabled:
		return
	if _fire_state == FireState.WARNING:
		var a := to_local(_shot_start)
		var b := to_local(_shot_end)
		var fill_ratio := warning_fill_ratio(_warning_s)
		var bright := warning_flash_bright(_warning_s)
		var band_alpha := (0.28 + fill_ratio * 0.30) if bright else 0.12
		var center_alpha := 0.95 if bright else 0.32
		_draw_fading_shot_line(a, b, Color(1.0, 0.22, 0.08, band_alpha),
			warning_width_px(_warning_s))
		_draw_fading_shot_line(a, b, Color(1.0, 0.82, 0.25, center_alpha), 3.0)
	elif _fire_state == FireState.FLIGHT:
		var shot_vec := _shot_end - _shot_start
		var length := maxf(shot_vec.length(), 1.0)
		var direction := shot_vec / length
		var nose_world := _shot_start + direction * _shot_progress_px
		var tail_world := _shot_start + direction * maxf(
			_shot_progress_px - PROJECTILE_TRAIL_PX, 0.0)
		var tail := to_local(tail_world)
		var nose := to_local(nose_world)
		var mid := tail.lerp(nose, 0.72)
		var trail_points := PackedVector2Array([tail, mid, nose])
		draw_polyline_colors(trail_points, PackedColorArray([
			Color(1.0, 0.20, 0.06, 0.0), Color(1.0, 0.48, 0.10, 0.52),
			Color(1.0, 0.95, 0.72, 1.0)]), 12.0, true)
		draw_polyline_colors(trail_points, PackedColorArray([
			Color(1.0, 0.70, 0.20, 0.0), Color(1.0, 0.86, 0.42, 0.78),
			Color.WHITE]), 3.0, true)
		draw_circle(nose, 4.0, Color.WHITE)
