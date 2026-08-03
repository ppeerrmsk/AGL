class_name BomberMission
extends Node

## 一次性轰炸任务集中控制器：10Hz 更新整队，不给每架轰炸机增加额外 process 节点。
enum Phase { INGRESS, LINE_UP, RELEASE, EGRESS }

const TICK_S := 0.1
const ARRIVAL_PX := 220.0
const RELEASE_COUNT := 5
const RELEASE_INTERVAL_S := 0.22
const FALL_TIME_S := 3.2
const HORIZONTAL_RETENTION := 0.85
const LATERAL_SCATTER_M := 60.0
const RELEASE_HEADING_GATE_RAD := deg_to_rad(12.0)
const RELEASE_CROSS_TRACK_PX := 140.0
const EXIT_EXTENSION_PX := 5000.0
const MAX_LIFETIME_S := 150.0

var _members: Array[Dictionary] = []
var _bullet_manager: BulletManager
var _target_pos: Vector2
var _tick_accum := 0.0
var _lifetime := 0.0

func setup(aircraft_list: Array[Aircraft], routes: Array, target_pos: Vector2,
		bullet_manager: BulletManager) -> void:
	_bullet_manager = bullet_manager
	_target_pos = target_pos
	for i in range(aircraft_list.size()):
		var ac: Aircraft = aircraft_list[i]
		var route: PackedVector2Array = routes[i]
		var target_index := 0
		var nearest := INF
		for j in range(route.size()):
			var d := route[j].distance_squared_to(target_pos)
			if d < nearest:
				nearest = d
				target_index = j
		_members.append({
			"aircraft": ac, "route": route, "route_index": 1,
			"target_index": target_index, "phase": Phase.INGRESS,
			"release_timer": 0.0, "released": 0,
		})
		var ai: AIController = ac._get_ai_controller()
		if ai != null:
			ai.set_physics_process(false)
		ac.ai_override_pursuit = true
		ac.target_speed_kmh = ac.params.cruise_speed
		ac.set_target_tier(CombatUnit.AltitudeTier.HIGH)
		ac.altitude = CombatUnit.TIER_ALTITUDE[CombatUnit.AltitudeTier.HIGH]

func _physics_process(delta: float) -> void:
	_lifetime += delta
	_tick_accum += delta
	if _tick_accum < TICK_S:
		return
	var dt := _tick_accum
	_tick_accum = 0.0
	var alive_count := 0
	for member in _members:
		var ac_raw: Variant = member["aircraft"]
		if not is_instance_valid(ac_raw) or ac_raw.is_destroyed:
			continue
		alive_count += 1
		_update_member(member, ac_raw as Aircraft, dt)
	if alive_count == 0 or _lifetime >= MAX_LIFETIME_S:
		queue_free()

func _update_member(member: Dictionary, ac: Aircraft, delta: float) -> void:
	var route: PackedVector2Array = member["route"]
	var phase: int = int(member["phase"])
	var idx: int = int(member["route_index"])
	var target_idx: int = int(member["target_index"])
	ac.target_speed_kmh = ac.params.cruise_speed

	if phase == Phase.INGRESS:
		idx = clampi(idx, 0, route.size() - 1)
		ac.target_position = route[idx]
		if ac.global_position.distance_to(route[idx]) <= ARRIVAL_PX:
			idx += 1
			if idx >= target_idx:
				phase = Phase.LINE_UP
			else:
				idx = mini(idx, route.size() - 1)
	elif phase == Phase.LINE_UP:
		ac.target_position = _target_pos
		var fwd := Vector2(sin(ac.heading), -cos(ac.heading))
		var to_target := _target_pos - ac.global_position
		var along: float = to_target.dot(fwd)
		var cross_track: float = absf(to_target.cross(fwd))
		var desired_heading := atan2(to_target.x, -to_target.y)
		var aligned := absf(angle_difference(ac.heading, desired_heading)) <= RELEASE_HEADING_GATE_RAD
		var lead_px := ac.speed * CombatUnit.PIXELS_PER_METER * FALL_TIME_S * HORIZONTAL_RETENTION
		if along >= 0.0 and along <= lead_px and cross_track <= RELEASE_CROSS_TRACK_PX and aligned:
			phase = Phase.RELEASE
			member["release_timer"] = 0.0
		elif along < -ARRIVAL_PX:
			phase = Phase.EGRESS # 错过释放线，不掉头补投。
	elif phase == Phase.RELEASE:
		var egress_point := _egress_point(route, _target_pos)
		ac.target_position = egress_point
		member["release_timer"] = float(member["release_timer"]) - delta
		while int(member["released"]) < RELEASE_COUNT and float(member["release_timer"]) <= 0.0:
			_release_one(ac)
			member["released"] = int(member["released"]) + 1
			member["release_timer"] = float(member["release_timer"]) + RELEASE_INTERVAL_S
		if int(member["released"]) >= RELEASE_COUNT:
			phase = Phase.EGRESS
	else:
		ac.target_position = _egress_point(route, _target_pos)
		ac.keep_target_on_arrival = true

	member["route_index"] = idx
	member["phase"] = phase

func _release_one(ac: Aircraft) -> void:
	if _bullet_manager == null or not is_instance_valid(_bullet_manager):
		return
	var fwd := Vector2(sin(ac.heading), -cos(ac.heading))
	var right := Vector2(cos(ac.heading), sin(ac.heading))
	var fall_time := FALL_TIME_S + randf_range(-0.12, 0.12)
	var lateral_shift_px := randf_range(-LATERAL_SCATTER_M, LATERAL_SCATTER_M) * CombatUnit.PIXELS_PER_METER
	var vel_px := fwd * ac.speed * CombatUnit.PIXELS_PER_METER * HORIZONTAL_RETENTION \
			+ right * (lateral_shift_px / fall_time)
	_bullet_manager.spawn_bomber_bomb(ac.global_position, vel_px, ac, fall_time, 160.0, 75.0)
	EventLogger.log_event("BOMB", ac.callsign, "release %d/%d target=%s" % [
		_count_released_for(ac) + 1, RELEASE_COUNT, _target_pos])

func _count_released_for(ac: Aircraft) -> int:
	for member in _members:
		if is_instance_valid(member["aircraft"]) and member["aircraft"] == ac:
			return int(member["released"])
	return 0

func _egress_point(route: PackedVector2Array, fallback: Vector2) -> Vector2:
	if route.size() >= 2:
		var last := route[route.size() - 1]
		var prev := route[route.size() - 2]
		var dir := (last - prev).normalized()
		return last + dir * EXIT_EXTENSION_PX
	return fallback + Vector2.UP * EXIT_EXTENSION_PX
