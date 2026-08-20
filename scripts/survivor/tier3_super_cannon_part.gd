class_name Tier3SuperCannonPart
extends GroundUnit

## 三级超级巨炮的单个正式锁定点。四个 BASE 与一个 BODY 都是独立 GroundUnit/TGT；
## 只有 BODY 拥有远距投射状态机，五点共享普通战区伤害与结算路径。

enum PartKind { BASE, BODY }
enum FireState { IDLE, WARNING, FLIGHT }

## 集中调校值：spec 尚未给数值，先用可测试初值；后续只改本表，不散落到任务层。
const MIN_RANGE_PX := 2500.0       ## 5 km 近身死区
const MAX_RANGE_PX := 36000.0      ## 72 km，覆盖 60 km 地图的大部分跨区几何
const TURN_RATE_RAD_S := deg_to_rad(12.0)
const ALIGN_TOLERANCE_RAD := deg_to_rad(3.0)
const WARNING_S := 2.2
const PROJECTILE_SPEED_PX_S := 3200.0
const AOE_RADIUS_PX := 180.0       ## 360 m 半径 / 720 m 全宽直线危险带
const AOE_DAMAGE := 45.0
const FIRE_COOLDOWN_S := 12.0
const FIRST_FIRE_DELAY_S := 4.0
const SHOT_OVERSHOOT_PX := 1200.0

var part_kind: PartKind = PartKind.BASE
var cannon_group_id: StringName = &""

var _fire_state: FireState = FireState.IDLE
var _cooldown_s: float = FIRST_FIRE_DELAY_S
var _warning_s: float = 0.0
var _shot_start: Vector2 = Vector2.ZERO
var _shot_end: Vector2 = Vector2.ZERO
var _shot_progress_px: float = 0.0
var _hit_ids: Dictionary = {}
var _threat_enabled: bool = true


func configure(kind: PartKind, group_id: StringName) -> void:
	part_kind = kind
	cannon_group_id = group_id
	max_ground_speed = 0.0
	target_position = Vector2.INF


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
	if part_kind != PartKind.BODY or not _threat_enabled:
		if is_hovered or is_locked or incoming_lock_progress > 0.0:
			queue_redraw()
		return
	_update_body_fire(delta)
	# IDLE 转向只旋转现有 canvas item；预警/弹体和锁框才需要重新提交 draw。
	if _fire_state != FireState.IDLE or is_hovered or is_locked or incoming_lock_progress > 0.0:
		queue_redraw()


func _update_body_fire(delta: float) -> void:
	match _fire_state:
		FireState.IDLE:
			_cooldown_s = maxf(_cooldown_s - delta, 0.0)
			var player := AircraftRenderer.safe_player_ref()
			if player == null or player.is_destroyed:
				return
			var to_player := player.global_position - global_position
			var distance := to_player.length()
			if not target_in_range(distance):
				return
			var target_heading := atan2(to_player.x, -to_player.y)
			heading = rotate_toward(heading, target_heading, TURN_RATE_RAD_S * delta)
			rotation = heading
			if _cooldown_s <= 0.0 and absf(angle_difference(heading, target_heading)) \
					<= ALIGN_TOLERANCE_RAD:
				_begin_warning(player.global_position)
		FireState.WARNING:
			_warning_s = maxf(_warning_s - delta, 0.0)
			if _warning_s <= 0.0:
				_fire_state = FireState.FLIGHT
				_shot_progress_px = 0.0
		FireState.FLIGHT:
			_update_projectile(delta)


func _begin_warning(target_snapshot: Vector2) -> void:
	var direction := (target_snapshot - global_position).normalized()
	if direction.length_squared() < 0.5:
		return
	_shot_start = global_position + direction * 34.0
	var shot_length := minf(maxf(global_position.distance_to(target_snapshot)
		+ SHOT_OVERSHOOT_PX, MIN_RANGE_PX), MAX_RANGE_PX)
	_shot_end = _shot_start + direction * shot_length
	_warning_s = WARNING_S
	_fire_state = FireState.WARNING
	_hit_ids.clear()
	queue_redraw()
	EventLogger.log_event("TIER3", "SuperCannonWarning",
		"group=%s length=%.0f width=%.0f" % [cannon_group_id, shot_length, AOE_RADIUS_PX])


func _update_projectile(delta: float) -> void:
	var shot_vec := _shot_end - _shot_start
	var shot_length := shot_vec.length()
	if shot_length <= 1.0:
		_finish_shot()
		return
	var direction := shot_vec / shot_length
	var previous := _shot_start + direction * _shot_progress_px
	_shot_progress_px = minf(_shot_progress_px + PROJECTILE_SPEED_PX_S * delta, shot_length)
	var current := _shot_start + direction * _shot_progress_px
	for unit in CombatUnit.all_units:
		if unit == null or not is_instance_valid(unit) or unit.is_destroyed:
			continue
		if not (unit is Aircraft) or unit.team != CombatUnit.TEAM_PLAYER:
			continue
		var uid := unit.get_instance_id()
		if _hit_ids.has(uid):
			continue
		if point_distance_to_segment(unit.global_position, previous, current) > AOE_RADIUS_PX:
			continue
		_hit_ids[uid] = true
		unit.take_damage(AOE_DAMAGE, self, "aoe")
		EventLogger.log_event("TIER3", "SuperCannonHit",
			"group=%s target=%s damage=%.0f" % [cannon_group_id, unit.callsign, AOE_DAMAGE])
	if _shot_progress_px >= shot_length:
		_finish_shot()


func _finish_shot() -> void:
	_fire_state = FireState.IDLE
	_cooldown_s = FIRE_COOLDOWN_S
	_warning_s = 0.0
	_shot_progress_px = 0.0
	_hit_ids.clear()
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
	if part_kind == PartKind.BASE:
		draw_rect(Rect2(-16.0, -14.0, 32.0, 28.0), color.darkened(0.35), true)
		draw_rect(Rect2(-16.0, -14.0, 32.0, 28.0), color, false, 2.0)
		draw_line(Vector2(-11.0, 0.0), Vector2(11.0, 0.0), color.lightened(0.25), 2.0)
		return
	draw_circle(Vector2.ZERO, 23.0, color.darkened(0.45))
	draw_arc(Vector2.ZERO, 23.0, 0.0, TAU, 24, color, 2.0)
	draw_rect(Rect2(-8.0, -32.0, 16.0, 34.0), color, true)
	draw_line(Vector2(0.0, -32.0), Vector2(0.0, -48.0), color.lightened(0.35), 6.0)


func _draw_impl() -> void:
	super._draw_impl()
	if part_kind != PartKind.BODY or is_destroyed or not _threat_enabled:
		return
	if _fire_state == FireState.WARNING:
		var a := to_local(_shot_start)
		var b := to_local(_shot_end)
		var pulse := 0.45 + 0.35 * sin(Time.get_ticks_msec() * 0.018)
		draw_line(a, b, Color(1.0, 0.22, 0.08, pulse), AOE_RADIUS_PX * 2.0)
		draw_line(a, b, Color(1.0, 0.82, 0.25, 0.9), 3.0)
	elif _fire_state == FireState.FLIGHT:
		var shot_vec := _shot_end - _shot_start
		var length := maxf(shot_vec.length(), 1.0)
		var projectile_world := _shot_start + shot_vec / length * _shot_progress_px
		var local_pos := to_local(projectile_world)
		draw_circle(local_pos, 16.0, Color(1.0, 0.85, 0.35, 0.95))
		draw_circle(local_pos, AOE_RADIUS_PX, Color(1.0, 0.22, 0.08, 0.13))
