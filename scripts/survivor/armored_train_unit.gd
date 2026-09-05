class_name ArmoredTrainUnit
extends Node2D

signal route_finished

## IRON SERPENT 的编组控制器。十四节车厢各自是直接挂在场景根下的 GroundUnit，
## 因而可以被玩家独立锁定；本节点维护铁路弧长、车钩、尾节顺序伤害门和电磁炮。

enum RailgunState { IDLE, LOCKING, CHARGING, FLIGHT }

const SEGMENT_SCRIPT := preload("res://scripts/survivor/armored_train_segment.gd")
const CIWS_SCRIPT := preload("res://scripts/survivor/tier3_siege_ciws.gd")
const SAM_SCRIPT := preload("res://scripts/survivor/tier3_siege_sam.gd")
const FLAK_SCRIPT := preload("res://scripts/survivor/tier3_siege_flak.gd")
const SEGMENT_BASE_PARAMS: AircraftParams = preload("res://resources/aa_gun_params.tres")
const AA_BASE_PARAMS: AircraftParams = preload("res://resources/aa_gun_params.tres")
const SAM_BASE_PARAMS: AircraftParams = preload("res://resources/sam_params.tres")
const FLAK_BASE_PARAMS: AircraftParams = preload("res://resources/airburst_aa_params.tres")

const SEGMENT_COUNT := 14
const SEGMENT_LENGTH_PX := 236.0
const SEGMENT_WIDTH_PX := 84.0
const COUPLER_GAP_PX := 18.0
const SEGMENT_PITCH_PX := SEGMENT_LENGTH_PX + COUPLER_GAP_PX
const BOGIE_OFFSET_PX := 88.0
const TOTAL_LENGTH_PX := SEGMENT_COUNT * SEGMENT_LENGTH_PX \
	+ (SEGMENT_COUNT - 1) * COUPLER_GAP_PX

const BASE_SPEED_KMH := 420.0
const SPEED_STEP_KMH := 60.0
const MAX_SPEED_KMH := BASE_SPEED_KMH + SPEED_STEP_KMH * (SEGMENT_COUNT - 1)
const ARRIVAL_START_SPEED_KMH := 330.0
const ARRIVAL_END_SPEED_KMH := BASE_SPEED_KMH
const ARRIVAL_DURATION_S := 6.5
# 0.26 广角下仍需给 236px 车体与边框留下可读安全边距；32px 世界边距折算到
# 屏幕只有约 8px，Camera2D 边界钳制后首节必贴边/裁切。
const ARRIVAL_BOUNDARY_INSET_PX := 420.0
const ARRIVAL_SEARCH_STEP_PX := 12.0

const SEGMENT_NAMES := [
	"ARMORED LOCOMOTIVE",
	"DRIVE TENDER",
	"RAILGUN CAR",
	"VLS ALPHA",
	"VLS BRAVO",
	"COMMAND RADAR",
	"FIRE CONTROL",
	"FLAK ALPHA",
	"FLAK BRAVO",
	"CIWS ALPHA",
	"CIWS BRAVO",
	"ARMORED MAGAZINE",
	"TAIL BATTERY",
	"REAR GUARD",
]
const SEGMENT_HP := [
	240.0, 170.0, 170.0, 130.0, 130.0, 130.0, 110.0,
	110.0, 100.0, 100.0, 90.0, 90.0, 90.0, 140.0,
]
const TOTAL_MAX_HP := 1800.0

const LOCOMOTIVE_INDEX := 0
const DRIVE_TENDER_INDEX := 1
const RAILGUN_INDEX := 2
const VLS_ALPHA_INDEX := 3
const VLS_BRAVO_INDEX := 4
const RADAR_INDEX := 5
const FIRE_CONTROL_INDEX := 6
const FLAK_ALPHA_INDEX := 7
const FLAK_BRAVO_INDEX := 8
const CIWS_ALPHA_INDEX := 9
const CIWS_BRAVO_INDEX := 10
const ARMORED_MAGAZINE_INDEX := 11
const TAIL_BATTERY_INDEX := 12
const REAR_GUARD_INDEX := 13

# 海岸线 AURORA LANCE 的同款 AOE 承诺：4.0s 填宽 + 1.5s 闪烁，随后整线同拍结算。
const RAILGUN_MIN_RANGE_PX := 2500.0
const RAILGUN_MAX_RANGE_PX := 44000.0
const RAILGUN_BLIND_MAX_RANGE_PX := 14000.0
const RAILGUN_TURN_RATE_RAD_S := deg_to_rad(12.0)
const RAILGUN_ALIGN_TOLERANCE_RAD := deg_to_rad(3.0)
const RAILGUN_BROADSIDE_HALF_ARC_RAD := deg_to_rad(50.0)
const RAILGUN_LOCK_S := 1.0
const RAILGUN_WARNING_FILL_S := 4.0
const RAILGUN_WARNING_FLASH_S := 1.5
const RAILGUN_WARNING_S := RAILGUN_WARNING_FILL_S + RAILGUN_WARNING_FLASH_S
const RAILGUN_WARNING_MIN_WIDTH_PX := 4.0
const RAILGUN_WARNING_FLASH_HZ := 3.0
const RAILGUN_AOE_RADIUS_PX := 90.0
const RAILGUN_AOE_DAMAGE := 45.0
const RAILGUN_FIRST_FIRE_DELAY_S := 5.0
const RAILGUN_COOLDOWN_S := 14.0
const RAILGUN_TARGET_SCAN_INTERVAL_S := 0.5
const RAILGUN_PROJECTILE_SPEED_PX_S := 12000.0
const RAILGUN_PROJECTILE_TRAIL_PX := 680.0
const RAILGUN_SHOT_OVERSHOOT_PX := 6000.0
const RAILGUN_MUZZLE_DISTANCE_PX := 72.0

var route := PackedVector2Array()
var route_progress: float = 0.0
var escaped: bool = false
var is_destroyed: bool = false
var speed: float = 0.0
var arrival_ingress_active: bool = false

var _segment_lengths := PackedFloat32Array()
var _route_length_px: float = 0.0
var _traveled_px: float = 0.0
var _active_tail_index: int = REAR_GUARD_INDEX
var _destroyed_segment_count: int = 0
var _cleanup_s: float = 0.0
var _arrival_elapsed_s: float = 0.0
var _arrival_start_distance_px: float = 0.0
var _arrival_fully_inside_distance_px: float = 0.0
var _segments: Array[GroundUnit] = []
var _mounts_by_segment: Dictionary = {}
var _module_world_positions: Array[Vector2] = []
var _module_world_headings := PackedFloat32Array()
var _module_bogie_world_positions: Array[Vector2] = []

var _railgun_state: RailgunState = RailgunState.IDLE
var _railgun_cooldown_s: float = RAILGUN_FIRST_FIRE_DELAY_S
var _railgun_lock_s: float = 0.0
var _railgun_lock_position: Vector2 = Vector2.ZERO
var _railgun_warning_s: float = 0.0
var _railgun_heading: float = 0.0
var _railgun_shot_start: Vector2 = Vector2.ZERO
var _railgun_shot_end: Vector2 = Vector2.ZERO
var _railgun_shot_progress_px: float = 0.0
var _railgun_target_id: int = 0
var _railgun_target_scan_s: float = 0.0


func _ready() -> void:
	z_index = -11


func configure_route(points: PackedVector2Array) -> void:
	route = points.duplicate()
	_segment_lengths.clear()
	_route_length_px = 0.0
	_traveled_px = 0.0
	route_progress = 0.0
	escaped = false
	is_destroyed = false
	_active_tail_index = REAR_GUARD_INDEX
	_destroyed_segment_count = 0
	_cleanup_s = 0.0
	for i in range(maxi(route.size() - 1, 0)):
		var length := route[i].distance_to(route[i + 1])
		_segment_lengths.append(length)
		_route_length_px += length
	if not route.is_empty():
		global_position = route[0]
	if route.size() >= 2:
		# 默认指向右舷；正式目标只能在左右侧舷射界内接管炮口。
		_railgun_heading = wrapf(float(_sample_route_pose(0.0).heading) + PI * 0.5,
			-PI, PI)
	_refresh_segment_poses()


func arm_segments(world: Node, bullet_mgr: Node2D, missile_mgr: Node2D) -> void:
	if world == null or not _segments.is_empty():
		return
	for index in range(SEGMENT_COUNT):
		var segment = SEGMENT_SCRIPT.new()
		var p := SEGMENT_BASE_PARAMS.duplicate(true) as AircraftParams
		p.display_name = SEGMENT_NAMES[index]
		p.max_hp = SEGMENT_HP[index]
		p.radar_range = 0.0
		p.gun = null
		segment.params = p
		segment.team = CombatUnit.TEAM_HOSTILE
		segment.configure(self, index)
		world.add_child(segment)
		segment.hp = p.max_hp
		_segments.append(segment)
	_refresh_segment_poses()
	_set_exposed_segment(REAR_GUARD_INDEX)
	_spawn_function_mounts(world, bullet_mgr, missile_mgr)


func begin_arrival_ingress() -> void:
	if route.size() < 2 or _segments.is_empty():
		return
	arrival_ingress_active = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_arrival_elapsed_s = 0.0
	_arrival_fully_inside_distance_px = _find_fully_inside_distance_px()
	# 演出切镜时整列必须已经在地图内；否则 CameraController 的边界钳制会让
	# 编组中点也无法居中，车尾必然被裁到画外。进场表现来自沿轨加速，不靠场外拖入。
	_arrival_start_distance_px = _arrival_fully_inside_distance_px
	_traveled_px = _arrival_start_distance_px
	speed = ARRIVAL_START_SPEED_KMH / 3.6
	route_progress = clampf(_traveled_px / maxf(_current_travel_limit_px(), 0.001),
		0.0, 1.0)
	_set_exposed_segment(-1)
	_refresh_segment_poses()
	_railgun_state = RailgunState.IDLE
	_railgun_target_id = 0
	_railgun_lock_s = 0.0
	_railgun_warning_s = 0.0
	EventLogger.log_event("BOSS", "ArmoredTrainArrivalBegin",
		"start_px=%.0f full_inside_px=%.0f speed=%.0f" % [
			_arrival_start_distance_px, _arrival_fully_inside_distance_px,
			ARRIVAL_START_SPEED_KMH])


func finish_arrival_ingress() -> void:
	# 演出缺失/被覆盖时同样 fail-open，但开战位置必须保证整列已经入图。
	_traveled_px = maxf(_traveled_px, _arrival_fully_inside_distance_px)
	_arrival_elapsed_s = ARRIVAL_DURATION_S
	arrival_ingress_active = false
	process_mode = Node.PROCESS_MODE_INHERIT
	speed = current_speed_kmh() / 3.6
	route_progress = clampf(_traveled_px / maxf(_current_travel_limit_px(), 0.001),
		0.0, 1.0)
	_refresh_segment_poses()
	_set_exposed_segment(_active_tail_index)
	_railgun_cooldown_s = RAILGUN_FIRST_FIRE_DELAY_S
	EventLogger.log_event("BOSS", "ArmoredTrainArrivalComplete",
		"traveled_px=%.0f speed=%.0f fully_inside=%s" % [
			_traveled_px, current_speed_kmh(), str(is_arrival_fully_inside())])


func arrival_speed_kmh() -> float:
	var t := clampf(_arrival_elapsed_s / ARRIVAL_DURATION_S, 0.0, 1.0)
	return lerpf(ARRIVAL_START_SPEED_KMH, ARRIVAL_END_SPEED_KMH, t)


func is_arrival_fully_inside() -> bool:
	var half := MapBoundary.world_half_px()
	var safe_rect := Rect2(-half, -half, half * 2.0, half * 2.0).grow(
		-ARRIVAL_BOUNDARY_INSET_PX)
	var head: Vector2 = _sample_route_pose(_traveled_px).position
	var tail_rear_distance := _traveled_px - float(maxi(_active_tail_index, 0)) \
		* SEGMENT_PITCH_PX - SEGMENT_LENGTH_PX * 0.5
	var tail_rear: Vector2 = _sample_route_pose(tail_rear_distance).position
	return safe_rect.has_point(head) and safe_rect.has_point(tail_rear)


func _find_fully_inside_distance_px() -> float:
	var d := 0.0
	while d <= _route_length_px:
		_traveled_px = d
		if is_arrival_fully_inside():
			return d
		d += ARRIVAL_SEARCH_STEP_PX
	return minf(_route_length_px, _current_travel_limit_px())


func _spawn_function_mounts(world: Node, bullet_mgr: Node2D,
		missile_mgr: Node2D) -> void:
	# 每一组真实挂点只属于一节车厢；车厢打断后 owner 生命周期自动令挂点退场。
	if missile_mgr != null:
		_spawn_sam(world, missile_mgr, VLS_ALPHA_INDEX, Vector2.ZERO)
		_spawn_sam(world, missile_mgr, VLS_BRAVO_INDEX, Vector2.ZERO)
	if bullet_mgr != null:
		_spawn_flak(world, bullet_mgr, FLAK_ALPHA_INDEX, Vector2.ZERO)
		_spawn_flak(world, bullet_mgr, FLAK_BRAVO_INDEX, Vector2.ZERO)
		_spawn_ciws(world, bullet_mgr, CIWS_ALPHA_INDEX, Vector2.ZERO)
		_spawn_ciws(world, bullet_mgr, CIWS_BRAVO_INDEX, Vector2.ZERO)
		_spawn_flak(world, bullet_mgr, TAIL_BATTERY_INDEX, Vector2.ZERO)
		_spawn_flak(world, bullet_mgr, REAR_GUARD_INDEX, Vector2.ZERO)


func _spawn_ciws(world: Node, bullet_mgr: Node2D, segment_index: int,
		offset: Vector2) -> void:
	var owner := segment_at(segment_index)
	if owner == null:
		return
	var mount = CIWS_SCRIPT.new()
	var p := AA_BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = "TRAIN CIWS"
	p.max_hp = 999999.0
	p.radar_range = 0.0
	if p.gun != null:
		p.gun = p.gun.duplicate(true)
		p.gun.max_range = 2600.0
		p.gun.fire_rate = 2000.0
		p.gun.bullet_damage = 3.0
		p.gun.max_ammo = 3000
	mount.params = p
	mount.bullet_manager = bullet_mgr
	mount.configure(owner, offset)
	world.add_child(mount)
	_register_mount(segment_index, mount)


func _spawn_sam(world: Node, missile_mgr: Node2D, segment_index: int,
		offset: Vector2) -> void:
	var owner := segment_at(segment_index)
	if owner == null:
		return
	var mount = SAM_SCRIPT.new()
	var p := SAM_BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = "TRAIN VLS"
	p.max_hp = 999999.0
	p.radar_range = 12000.0
	p.lock_time = 2.8
	if p.missile != null:
		p.missile = p.missile.duplicate(true)
		p.missile.max_range_rear = 24000.0
		p.missile.max_count = 12
		p.missile.cooldown = 7.0
	mount.params = p
	mount.missile_manager = missile_mgr
	mount.configure(owner, offset)
	world.add_child(mount)
	_register_mount(segment_index, mount)


func _spawn_flak(world: Node, bullet_mgr: Node2D, segment_index: int,
		offset: Vector2) -> void:
	var owner := segment_at(segment_index)
	if owner == null:
		return
	var mount = FLAK_SCRIPT.new()
	var p := FLAK_BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = "TRAIN FLAK"
	p.max_hp = 999999.0
	mount.params = p
	mount.bullet_manager = bullet_mgr
	mount.configure(owner, offset)
	world.add_child(mount)
	_register_mount(segment_index, mount)


func _register_mount(segment_index: int, mount: CombatUnit) -> void:
	var mounts: Array = _mounts_by_segment.get(segment_index, [])
	mounts.append(mount)
	_mounts_by_segment[segment_index] = mounts


func _physics_process(delta: float) -> void:
	if is_destroyed:
		_cleanup_s = maxf(_cleanup_s - delta, 0.0)
		if _cleanup_s <= 0.0:
			_cleanup_all()
			queue_free()
		return
	_update_movement(delta)
	if not arrival_ingress_active:
		_update_railgun(delta)
	queue_redraw()


func _update_movement(delta: float) -> void:
	if escaped or route.size() < 2 or _route_length_px <= 0.0:
		speed = 0.0
		return
	if arrival_ingress_active:
		_arrival_elapsed_s = minf(_arrival_elapsed_s + delta, ARRIVAL_DURATION_S)
		speed = arrival_speed_kmh() / 3.6
	else:
		speed = current_speed_kmh() / 3.6
	var travel_limit := _current_travel_limit_px()
	_traveled_px = minf(_traveled_px + speed * GameConstants.PIXELS_PER_METER * delta,
		travel_limit)
	route_progress = clampf(_traveled_px / maxf(travel_limit, 0.001), 0.0, 1.0)
	var lead := _sample_route_pose(_traveled_px)
	global_position = lead.position
	_refresh_segment_poses()
	if _traveled_px >= travel_limit and not escaped:
		escaped = true
		speed = 0.0
		route_finished.emit()


func _current_travel_limit_px() -> float:
	return _route_length_px + float(maxi(_active_tail_index, 0)) * SEGMENT_PITCH_PX \
		+ SEGMENT_LENGTH_PX * 0.5


func _sample_route_pose(distance_px: float) -> Dictionary:
	if route.size() < 2:
		return {"position": global_position, "heading": 0.0}
	if distance_px <= 0.0:
		var first_dir := (route[1] - route[0]).normalized()
		return {"position": route[0] + first_dir * distance_px,
			"heading": atan2(first_dir.x, -first_dir.y)}
	var remaining := distance_px
	for i in range(_segment_lengths.size()):
		var length := float(_segment_lengths[i])
		if remaining <= length:
			var direction := (route[i + 1] - route[i]).normalized()
			return {"position": route[i] + direction * remaining,
				"heading": atan2(direction.x, -direction.y)}
		remaining -= length
	var last_dir := (route[-1] - route[-2]).normalized()
	return {"position": route[-1] + last_dir * remaining,
		"heading": atan2(last_dir.x, -last_dir.y)}


func _refresh_segment_poses() -> void:
	_module_world_positions.clear()
	_module_world_headings.clear()
	_module_bogie_world_positions.clear()
	for index in range(SEGMENT_COUNT):
		var center_distance := _traveled_px - float(index) * SEGMENT_PITCH_PX
		var pose := _sample_segment_pose(center_distance)
		_module_world_positions.append(pose.position)
		_module_world_headings.append(pose.heading)
		_module_bogie_world_positions.append(pose.front_bogie)
		_module_bogie_world_positions.append(pose.rear_bogie)
		var segment := segment_at(index)
		if segment != null and segment.has_method("set_train_pose"):
			segment.set_train_pose(pose.position, float(pose.heading), speed,
				float(pose.bogie_half_span))


func _sample_segment_pose(center_distance_px: float) -> Dictionary:
	# 长车厢用前后转向架双点定姿；两组轮始终落在铁路弧长上，弯道不再取
	# 中心单点切线造成整节横向甩出轨道。
	var front_pose := _sample_route_pose(center_distance_px + BOGIE_OFFSET_PX)
	var rear_pose := _sample_route_pose(center_distance_px - BOGIE_OFFSET_PX)
	var front: Vector2 = front_pose.position
	var rear: Vector2 = rear_pose.position
	var chord := front - rear
	var heading := float(front_pose.heading)
	if chord.length_squared() > 0.0001:
		heading = atan2(chord.x, -chord.y)
	return {
		"position": (front + rear) * 0.5,
		"heading": heading,
		"front_bogie": front,
		"rear_bogie": rear,
		"bogie_half_span": chord.length() * 0.5,
	}


func on_segment_broken(index: int, broken_segment: GroundUnit) -> void:
	if is_destroyed or index != _active_tail_index:
		return
	CombatUnit.release_target_refs(broken_segment)
	_cleanup_segment_mounts(index)
	if index == RAILGUN_INDEX:
		_reset_railgun()
	_destroyed_segment_count += 1
	_active_tail_index -= 1
	EventLogger.log_event("BOSS", "ArmoredTrainSegmentBroken",
		"segment=%d name=%s remaining=%d speed_kmh=%.0f" % [
			index + 1, SEGMENT_NAMES[index], _active_tail_index + 1,
			current_speed_kmh()])
	if _active_tail_index >= 0:
		_set_exposed_segment(_active_tail_index)
	else:
		is_destroyed = true
		speed = 0.0
		_cleanup_s = 2.1
	queue_redraw()


func _set_exposed_segment(index: int) -> void:
	var combat_active := index >= 0
	for i in range(_segments.size()):
		var segment := segment_at(i)
		if segment != null and segment.has_method("set_targetable"):
			segment.set_targetable(combat_active and i <= index)
			segment.set_damageable(i == index)


func current_speed_kmh() -> float:
	return minf(BASE_SPEED_KMH + float(_destroyed_segment_count) * SPEED_STEP_KMH,
		MAX_SPEED_KMH)


func active_tail_index() -> int:
	return _active_tail_index


func active_segment_name() -> String:
	return SEGMENT_NAMES[_active_tail_index] if _active_tail_index >= 0 else "DESTROYED"


func segment_at(index: int) -> GroundUnit:
	if index < 0 or index >= _segments.size():
		return null
	var value: Variant = _segments[index]
	if typeof(value) != TYPE_OBJECT or value == null or not is_instance_valid(value):
		return null
	return value as GroundUnit


func get_display_segments() -> Array:
	var result: Array = []
	for index in range(_segments.size()):
		var segment := segment_at(index)
		if segment != null and not segment.is_destroyed:
			result.append(segment)
	return result


func aggregate_hp() -> float:
	var total := 0.0
	for index in range(_segments.size()):
		var segment := segment_at(index)
		if segment != null and not segment.is_destroyed:
			total += maxf(segment.hp, 0.0)
	return total


func segment_function_active(index: int) -> bool:
	var segment := segment_at(index)
	return segment != null and not segment.is_destroyed


func railgun_heading() -> float:
	return _railgun_heading


func _railgun_world_position() -> Vector2:
	var segment := segment_at(RAILGUN_INDEX)
	return segment.global_position if segment != null else global_position


func _railgun_max_range_px() -> float:
	return RAILGUN_MAX_RANGE_PX if segment_function_active(RADAR_INDEX) \
		else RAILGUN_BLIND_MAX_RANGE_PX


func _update_railgun(delta: float) -> void:
	if arrival_ingress_active:
		return
	if not segment_function_active(RAILGUN_INDEX):
		_reset_railgun()
		return
	match _railgun_state:
		RailgunState.IDLE:
			_railgun_cooldown_s = maxf(_railgun_cooldown_s - delta, 0.0)
			_railgun_target_scan_s = maxf(_railgun_target_scan_s - delta, 0.0)
			var target := _live_railgun_target()
			if target == null:
				if _railgun_target_scan_s > 0.0:
					return
				target = _choose_railgun_target()
				_railgun_target_scan_s = RAILGUN_TARGET_SCAN_INTERVAL_S
			if target == null:
				return
			var origin := _railgun_world_position()
			var target_heading := atan2((target.global_position - origin).x,
				-(target.global_position - origin).y)
			_railgun_heading = rotate_toward(_railgun_heading, target_heading,
				RAILGUN_TURN_RATE_RAD_S * delta)
			var railgun_segment := segment_at(RAILGUN_INDEX)
			if railgun_segment != null:
				railgun_segment.queue_redraw()
			if _railgun_cooldown_s <= 0.0 and absf(angle_difference(
					_railgun_heading, target_heading)) <= RAILGUN_ALIGN_TOLERANCE_RAD:
				_begin_railgun_lock(target)
		RailgunState.LOCKING:
			var target := _live_railgun_target()
			if target == null:
				_cancel_railgun_lock()
				return
			var origin := _railgun_world_position()
			_railgun_lock_position = target.global_position
			var target_heading := atan2((target.global_position - origin).x,
				-(target.global_position - origin).y)
			_railgun_heading = rotate_toward(_railgun_heading, target_heading,
				RAILGUN_TURN_RATE_RAD_S * delta)
			if absf(angle_difference(_railgun_heading,
					target_heading)) > RAILGUN_ALIGN_TOLERANCE_RAD:
				_railgun_lock_s = RAILGUN_LOCK_S
				return
			_railgun_lock_s = maxf(_railgun_lock_s - delta, 0.0)
			if _railgun_lock_s <= 0.0:
				_begin_railgun_charge(target.global_position, target.callsign)
		RailgunState.CHARGING:
			_railgun_warning_s = maxf(_railgun_warning_s - delta, 0.0)
			if _railgun_warning_s <= 0.0:
				_fire_railgun_snapshot()
		RailgunState.FLIGHT:
			var shot_length := (_railgun_shot_end - _railgun_shot_start).length()
			_railgun_shot_progress_px = minf(_railgun_shot_progress_px
				+ RAILGUN_PROJECTILE_SPEED_PX_S * delta, shot_length)
			if _railgun_shot_progress_px >= shot_length:
				_finish_railgun_shot()


func _live_railgun_target() -> Aircraft:
	if _railgun_target_id <= 0:
		return null
	var value: Variant = instance_from_id(_railgun_target_id)
	var target := AircraftRenderer.safe_aircraft_ref(value)
	if target == null or target.is_destroyed or target.team != CombatUnit.TEAM_PLAYER \
			or not _railgun_target_in_range(target):
		_railgun_target_id = 0
		return null
	return target


func _railgun_target_in_range(target: Aircraft) -> bool:
	var distance := _railgun_world_position().distance_to(target.global_position)
	return distance >= RAILGUN_MIN_RANGE_PX and distance <= _railgun_max_range_px() \
		and railgun_side_for_position(target.global_position) != 0


func railgun_side_for_position(world_position: Vector2) -> int:
	var direction := world_position - _railgun_world_position()
	if direction.length_squared() <= 0.0001:
		return 0
	direction = direction.normalized()
	var car_heading := _railgun_car_heading()
	var right := Vector2(cos(car_heading), sin(car_heading))
	var lateral := direction.dot(right)
	if absf(lateral) < cos(RAILGUN_BROADSIDE_HALF_ARC_RAD):
		return 0
	return 1 if lateral > 0.0 else -1


func _railgun_car_heading() -> float:
	var segment := segment_at(RAILGUN_INDEX)
	if segment != null:
		return segment.heading
	if _module_world_headings.size() > RAILGUN_INDEX:
		return float(_module_world_headings[RAILGUN_INDEX])
	return float(_sample_route_pose(_traveled_px).heading)


func _choose_railgun_target() -> Aircraft:
	var candidates: Array[Aircraft] = []
	for value in CombatUnit.all_units:
		var target := AircraftRenderer.safe_aircraft_ref(value)
		if target != null and not target.is_destroyed \
				and target.team == CombatUnit.TEAM_PLAYER and _railgun_target_in_range(target):
			candidates.append(target)
	if candidates.is_empty():
		_railgun_target_id = 0
		return null
	var target := candidates[randi() % candidates.size()]
	_railgun_target_id = target.get_instance_id()
	return target


func _begin_railgun_lock(target: Aircraft) -> void:
	_railgun_state = RailgunState.LOCKING
	_railgun_lock_s = RAILGUN_LOCK_S
	_railgun_lock_position = target.global_position
	_railgun_target_id = target.get_instance_id()
	var side := railgun_side_for_position(target.global_position)
	EventLogger.log_event("BOSS", "ArmoredTrainRailgunLock",
		"target=%s side=%s lock_s=%.1f" % [target.callsign,
			"STARBOARD" if side > 0 else "PORT", RAILGUN_LOCK_S])


func _cancel_railgun_lock() -> void:
	_railgun_state = RailgunState.IDLE
	_railgun_lock_s = 0.0
	_railgun_lock_position = Vector2.ZERO
	_railgun_target_id = 0
	_railgun_target_scan_s = RAILGUN_TARGET_SCAN_INTERVAL_S


func _begin_railgun_charge(target_snapshot: Vector2, target_callsign: String) -> void:
	var origin := _railgun_world_position()
	var direction := (target_snapshot - origin).normalized()
	if direction.length_squared() < 0.5:
		return
	_railgun_shot_start = origin + direction * RAILGUN_MUZZLE_DISTANCE_PX
	var shot_length := minf(maxf(origin.distance_to(target_snapshot)
		+ RAILGUN_SHOT_OVERSHOOT_PX, RAILGUN_MIN_RANGE_PX), _railgun_max_range_px())
	_railgun_shot_end = _railgun_shot_start + direction * shot_length
	_railgun_warning_s = RAILGUN_WARNING_S
	_railgun_state = RailgunState.CHARGING
	_railgun_lock_s = 0.0
	_railgun_lock_position = Vector2.ZERO
	_railgun_target_id = 0
	EventLogger.log_event("BOSS", "ArmoredTrainRailgunCharge",
		"target=%s length=%.0f width=%.0f" % [
			target_callsign, shot_length, RAILGUN_AOE_RADIUS_PX])


func _fire_railgun_snapshot() -> void:
	var hit_count := 0
	var source := segment_at(RAILGUN_INDEX)
	for value in CombatUnit.all_units:
		var unit := AircraftRenderer.safe_aircraft_ref(value)
		if unit == null or unit.is_destroyed or unit.team != CombatUnit.TEAM_PLAYER:
			continue
		if point_distance_to_segment(unit.global_position, _railgun_shot_start,
				_railgun_shot_end) > RAILGUN_AOE_RADIUS_PX:
			continue
		unit.take_damage(RAILGUN_AOE_DAMAGE, source, "aoe")
		hit_count += 1
	_railgun_state = RailgunState.FLIGHT
	_railgun_shot_progress_px = 0.0
	EventLogger.log_event("BOSS", "ArmoredTrainRailgunFire",
		"hits=%d damage=%.0f" % [hit_count, RAILGUN_AOE_DAMAGE])


func _finish_railgun_shot() -> void:
	_railgun_state = RailgunState.IDLE
	_railgun_cooldown_s = RAILGUN_COOLDOWN_S
	_railgun_lock_s = 0.0
	_railgun_lock_position = Vector2.ZERO
	_railgun_warning_s = 0.0
	_railgun_shot_progress_px = 0.0
	_railgun_target_id = 0


func _reset_railgun() -> void:
	_railgun_state = RailgunState.IDLE
	_railgun_cooldown_s = RAILGUN_COOLDOWN_S
	_railgun_lock_s = 0.0
	_railgun_lock_position = Vector2.ZERO
	_railgun_warning_s = 0.0
	_railgun_shot_progress_px = 0.0
	_railgun_target_id = 0
	_railgun_target_scan_s = 0.0
	queue_redraw()


static func point_distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _draw() -> void:
	_draw_couplers()
	_draw_railgun_telegraph()


func _draw_couplers() -> void:
	var hostile := GameConstants.team_color(CombatUnit.TEAM_HOSTILE)
	for index in range(maxi(_active_tail_index, 0)):
		if index + 1 >= _module_world_positions.size():
			continue
		var front_h := float(_module_world_headings[index])
		var rear_h := float(_module_world_headings[index + 1])
		var front_dir := Vector2(sin(front_h), -cos(front_h))
		var rear_dir := Vector2(sin(rear_h), -cos(rear_h))
		var a := to_local(_module_world_positions[index]
			- front_dir * SEGMENT_LENGTH_PX * 0.5)
		var b := to_local(_module_world_positions[index + 1]
			+ rear_dir * SEGMENT_LENGTH_PX * 0.5)
		draw_line(a, b, Color(0.06, 0.07, 0.08), 9.0, true)
		draw_line(a, b, hostile.darkened(0.25), 3.0, true)
		draw_circle(a, 4.5, Color(0.08, 0.09, 0.10))
		draw_circle(b, 4.5, Color(0.08, 0.09, 0.10))


func _draw_railgun_telegraph() -> void:
	if _railgun_state == RailgunState.LOCKING:
		var a := to_local(_railgun_world_position())
		var b := to_local(_railgun_lock_position)
		var lock_ratio := 1.0 - clampf(_railgun_lock_s / RAILGUN_LOCK_S, 0.0, 1.0)
		draw_dashed_line(a, b, Color(1.0, 0.62, 0.12, 0.72), 2.0, 18.0, true)
		draw_arc(b, 34.0, -PI * 0.5, -PI * 0.5 + TAU * lock_ratio,
			24, Color(1.0, 0.82, 0.25, 0.95), 3.0, true)
		for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
			var outward := Vector2.RIGHT.rotated(angle)
			draw_line(b + outward * 25.0, b + outward * 39.0,
				Color(1.0, 0.40, 0.08, 0.9), 3.0, true)
	elif _railgun_state == RailgunState.CHARGING:
		var a := to_local(_railgun_shot_start)
		var b := to_local(_railgun_shot_end)
		var fill_ratio := clampf((RAILGUN_WARNING_S - _railgun_warning_s)
			/ RAILGUN_WARNING_FILL_S, 0.0, 1.0)
		var flashing := RAILGUN_WARNING_S - _railgun_warning_s \
			>= RAILGUN_WARNING_FILL_S
		var flash_elapsed := maxf(RAILGUN_WARNING_S - _railgun_warning_s
			- RAILGUN_WARNING_FILL_S, 0.0)
		var bright := not flashing or fmod(flash_elapsed * RAILGUN_WARNING_FLASH_HZ, 1.0) < 0.5
		var width := lerpf(RAILGUN_WARNING_MIN_WIDTH_PX,
			RAILGUN_AOE_RADIUS_PX * 2.0, fill_ratio)
		draw_line(a, b, Color(1.0, 0.22, 0.08, 0.58 if bright else 0.12), width, true)
		draw_line(a, b, Color(1.0, 0.82, 0.25, 0.95 if bright else 0.32), 3.0, true)
	elif _railgun_state == RailgunState.FLIGHT:
		var shot_vec := _railgun_shot_end - _railgun_shot_start
		var length := maxf(shot_vec.length(), 1.0)
		var direction := shot_vec / length
		var nose_world := _railgun_shot_start + direction * _railgun_shot_progress_px
		var tail_world := _railgun_shot_start + direction * maxf(
			_railgun_shot_progress_px - RAILGUN_PROJECTILE_TRAIL_PX, 0.0)
		var tail := to_local(tail_world)
		var nose := to_local(nose_world)
		draw_line(tail, nose, Color(1.0, 0.48, 0.10, 0.75), 12.0, true)
		draw_line(tail, nose, Color.WHITE, 3.0, true)
		draw_circle(nose, 4.0, Color.WHITE)


func _cleanup_segment_mounts(index: int) -> void:
	var mounts: Array = _mounts_by_segment.get(index, [])
	for value in mounts:
		if typeof(value) == TYPE_OBJECT and value != null and is_instance_valid(value):
			(value as Node).queue_free()
	_mounts_by_segment.erase(index)


func _cleanup_all() -> void:
	for key in _mounts_by_segment.keys():
		_cleanup_segment_mounts(int(key))
	for index in range(_segments.size()):
		var segment := segment_at(index)
		if segment != null:
			CombatUnit.release_target_refs(segment)
			segment.queue_free()
	_segments.clear()


func _exit_tree() -> void:
	_cleanup_all()
