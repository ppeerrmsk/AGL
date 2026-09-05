class_name LandCarrierUnit
extends GroundUnit

## 独立履带式陆地航母。它不是列车或落地海船：主体是低矮连续履带陆战平台，
## 不依赖铁路，并以嵌入式停机位停放、放飞战机。

const CIWS_SCRIPT := preload("res://scripts/survivor/tier3_siege_ciws.gd")
const SAM_SCRIPT := preload("res://scripts/survivor/tier3_siege_sam.gd")
const FLAK_SCRIPT := preload("res://scripts/survivor/tier3_siege_flak.gd")
const AA_BASE_PARAMS: AircraftParams = preload("res://resources/aa_gun_params.tres")
const SAM_BASE_PARAMS: AircraftParams = preload("res://resources/sam_params.tres")
const FLAK_BASE_PARAMS: AircraftParams = preload("res://resources/airburst_aa_params.tres")

const HULL_LENGTH_PX := 620.0
const HULL_WIDTH_PX := 280.0
const TRACK_WIDTH_PX := 38.0
const SPAWN_EDGE_MARGIN_PX := 2200.0
const SPAWN_INSET_PX := 700.0
const INITIAL_INGRESS_PX := 1400.0
const PARK_OFFSETS: Array[Vector2] = [
	Vector2(-70.0, -86.0), Vector2(42.0, -58.0),
	Vector2(-58.0, 18.0), Vector2(48.0, 48.0),
]

var _parked_aircraft: Array[Aircraft] = []
var _mounts: Array[CombatUnit] = []
var _scene_root: Node = null


func configure_patrol(center: Vector2) -> void:
	var clamped_anchor := MapBoundary.clamp_inside(center, SPAWN_EDGE_MARGIN_PX)
	var inward := clamped_anchor.direction_to(Vector2.ZERO)
	if inward == Vector2.ZERO:
		inward = Vector2.UP
	global_position = MapBoundary.clamp_inside(
		clamped_anchor + inward * SPAWN_INSET_PX, SPAWN_EDGE_MARGIN_PX)
	var ingress := MapBoundary.clamp_inside(
		global_position + inward * INITIAL_INGRESS_PX, SPAWN_EDGE_MARGIN_PX)
	var lateral := Vector2(-inward.y, inward.x) * 620.0
	var inner_leg := MapBoundary.clamp_inside(ingress + inward * 760.0,
		SPAWN_EDGE_MARGIN_PX)
	waypoints = PackedVector2Array([
		ingress,
		MapBoundary.clamp_inside(ingress + lateral, SPAWN_EDGE_MARGIN_PX),
		inner_leg,
		MapBoundary.clamp_inside(ingress - lateral, SPAWN_EDGE_MARGIN_PX),
	])
	current_waypoint_index = 0
	target_position = waypoints[0]
	heading = atan2(inward.x, -inward.y)
	initial_heading_deg = rad_to_deg(heading)
	rotation = heading
	arrival_distance = 120.0
	max_ground_speed = 14.0


func spawn_parked_aircraft(scene_root: Node, count: int = 4) -> int:
	_scene_root = scene_root
	if scene_root == null or not ("_spawner" in scene_root):
		push_warning("LandCarrierUnit: scene_root has no spawner")
		return 0
	var spawner: Node = scene_root._spawner
	var spawned := 0
	for i in range(mini(count, PARK_OFFSETS.size())):
		var offset := PARK_OFFSETS[i]
		var ac: Aircraft = spawner._create_enemy(
			SurvivorSpawner.EnemyType.FA18, _local_to_world(offset), rad_to_deg(heading))
		if ac == null:
			continue
		ac.set_meta(&"park_offset", offset)
		ac.set_meta(&"parent_carrier", self)
		ac.set_meta(&"category", "land_carrier_airwing")
		ac.set_meta(&"no_kill_reward", true)
		ac.hide_data_label = true
		ac.process_mode = Node.PROCESS_MODE_DISABLED
		_parked_aircraft.append(ac)
		spawned += 1
	EventLogger.log_event("BOSS", "LandCarrierParked",
		"parked=%d" % _parked_aircraft.size())
	return spawned


func launch_parked_aircraft(count: int = 1) -> Array[Aircraft]:
	var launched: Array[Aircraft] = []
	for _i in range(count):
		if _parked_aircraft.is_empty():
			break
		var ac: Aircraft = _parked_aircraft.pop_front()
		if ac == null or not is_instance_valid(ac):
			continue
		ac.altitude = 100.0
		ac.speed = 85.0
		ac.heading = heading
		ac.rotation = heading
		var forward := Vector2(sin(heading), -cos(heading))
		ac.target_position = ac.global_position + forward * 3000.0
		ac.process_mode = Node.PROCESS_MODE_INHERIT
		ac.hide_data_label = false
		ac.remove_meta(&"parent_carrier")
		launched.append(ac)
	EventLogger.log_event("BOSS", "LandCarrierLaunch",
		"launched=%d parked=%d" % [launched.size(), _parked_aircraft.size()])
	return launched


func parked_aircraft_count() -> int:
	_prune_parked()
	return _parked_aircraft.size()


func arm_mounts(world: Node, bullet_mgr: Node2D, missile_mgr: Node2D) -> void:
	if world == null or not _mounts.is_empty():
		return
	for offset in [Vector2(-125.0, -190.0), Vector2(125.0, -190.0),
			Vector2(-125.0, 205.0), Vector2(125.0, 205.0)]:
		_spawn_ciws(world, bullet_mgr, offset)
	for offset in [Vector2(-95.0, -70.0), Vector2(95.0, 115.0)]:
		_spawn_sam(world, missile_mgr, offset)
	for offset in [Vector2(-105.0, 35.0), Vector2(105.0, -5.0)]:
		_spawn_flak(world, bullet_mgr, offset)


func mount_world_pose(local_offset: Vector2) -> Dictionary:
	return {"position": _local_to_world(local_offset), "heading": heading}


func _spawn_ciws(world: Node, bullet_mgr: Node2D, offset: Vector2) -> void:
	var mount = CIWS_SCRIPT.new()
	var p := AA_BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = "LAND CARRIER CIWS"
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
	mount.configure(self, offset)
	world.add_child(mount)
	_mounts.append(mount)


func _spawn_sam(world: Node, missile_mgr: Node2D, offset: Vector2) -> void:
	var mount = SAM_SCRIPT.new()
	var p := SAM_BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = "LAND CARRIER VLS"
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
	mount.configure(self, offset)
	world.add_child(mount)
	_mounts.append(mount)


func _spawn_flak(world: Node, bullet_mgr: Node2D, offset: Vector2) -> void:
	var mount = FLAK_SCRIPT.new()
	var p := FLAK_BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = "LAND CARRIER FLAK"
	p.max_hp = 999999.0
	mount.params = p
	mount.bullet_manager = bullet_mgr
	mount.configure(self, offset)
	world.add_child(mount)
	_mounts.append(mount)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_destroyed:
		return
	_prune_parked()
	for ac in _parked_aircraft:
		var offset: Vector2 = ac.get_meta(&"park_offset", Vector2.ZERO)
		ac.global_position = _local_to_world(offset)
		ac.heading = heading
		ac.rotation = heading


func _local_to_world(offset: Vector2) -> Vector2:
	return global_position + offset.rotated(heading)


func take_missile_damage(amount: float) -> void:
	# 巨型装甲单位不使用普通地面软目标的一发必杀规则。
	take_damage(amount, null, "missile")


func _draw_cloud_shadow() -> void:
	pass


func _draw_ground_icon() -> void:
	var hostile := GameConstants.team_color(team)
	var armor := Color(0.16, 0.17, 0.15)
	var armor_high := Color(0.24, 0.25, 0.21)
	var armor_dark := Color(0.075, 0.08, 0.07)
	var half_l := HULL_LENGTH_PX * 0.5
	var half_w := HULL_WIDTH_PX * 0.5
	# 参考图语义：低矮长车体、轻度楔首和宽厚装甲肩；禁止船艏剪影。
	var hull := PackedVector2Array([
		Vector2(-half_w * 0.62, -half_l), Vector2(half_w * 0.62, -half_l),
		Vector2(half_w, -half_l * 0.78), Vector2(half_w, half_l * 0.80),
		Vector2(half_w * 0.78, half_l), Vector2(-half_w * 0.78, half_l),
		Vector2(-half_w, half_l * 0.80), Vector2(-half_w, -half_l * 0.78),
	])
	draw_colored_polygon(hull, armor)
	var hull_outline := hull.duplicate()
	hull_outline.append(hull[0])
	draw_polyline(hull_outline, hostile, 5.0)
	# 两条贯穿式履带使用连续履带块与横向履齿，不再像船舷舷窗。
	for side_value in [-1.0, 1.0]:
		var side := float(side_value)
		var x := side * (half_w + TRACK_WIDTH_PX * 0.46)
		var track_rect := Rect2(x - TRACK_WIDTH_PX * 0.5, -half_l * 0.86,
			TRACK_WIDTH_PX, half_l * 1.72)
		draw_rect(track_rect, armor_dark, true)
		draw_rect(track_rect, hostile.darkened(0.38), false, 4.0)
		for y in range(-252, 253, 34):
			draw_line(Vector2(x - TRACK_WIDTH_PX * 0.42, float(y)),
				Vector2(x + TRACK_WIDTH_PX * 0.42, float(y)), hostile.darkened(0.53), 3.0)
	# 前部复合装甲楔面和车体分区线，强调陆战平台而不是平直飞行甲板。
	var glacis := PackedVector2Array([
		Vector2(-86.0, -286.0), Vector2(86.0, -286.0),
		Vector2(118.0, -224.0), Vector2(-118.0, -224.0),
	])
	draw_colored_polygon(glacis, armor_high)
	draw_polyline(PackedVector2Array([
		glacis[0], glacis[1], glacis[2], glacis[3], glacis[0]]),
		hostile.darkened(0.18), 3.0)
	for y in [-188.0, -104.0, -18.0, 72.0, 164.0, 238.0]:
		draw_line(Vector2(-116.0, y), Vector2(116.0, y), hostile.darkened(0.60), 2.0)
	# 四个嵌入式停机/起降位：保留陆地航母能力，但没有贯穿式航母跑道。
	for offset in PARK_OFFSETS:
		var bay := Rect2(offset - Vector2(27.0, 20.0), Vector2(54.0, 40.0))
		draw_rect(bay, armor_dark, true)
		draw_rect(bay, hostile.darkened(0.28), false, 2.0)
		draw_line(offset + Vector2(-12.0, 0.0), offset + Vector2(12.0, 0.0),
			hostile.darkened(0.35), 2.0)
	# 后部中央装甲指挥舱和雷达桅杆；不是偏置舰岛。
	var citadel := PackedVector2Array([
		Vector2(-72.0, 104.0), Vector2(72.0, 104.0), Vector2(92.0, 142.0),
		Vector2(64.0, 218.0), Vector2(-64.0, 218.0), Vector2(-92.0, 142.0),
	])
	draw_colored_polygon(citadel, armor_high)
	draw_polyline(PackedVector2Array([
		citadel[0], citadel[1], citadel[2], citadel[3], citadel[4], citadel[5], citadel[0]]),
		hostile, 4.0)
	draw_line(Vector2(0.0, 128.0), Vector2(0.0, 64.0), hostile.lightened(0.28), 7.0)
	draw_arc(Vector2(0.0, 54.0), 23.0, 0.0, TAU, 24, hostile, 5.0)
	draw_line(Vector2(-28.0, 178.0), Vector2(28.0, 178.0), hostile.darkened(0.30), 3.0)
	# 分散式 VLS、肩部近防炮与前部双联主炮，强化“多挂点陆战堡垒”。
	for x in [-88.0, -64.0, 64.0, 88.0]:
		for y in [-194.0, -170.0]:
			draw_rect(Rect2(float(x) - 8.0, float(y) - 8.0, 16.0, 16.0),
				hostile.darkened(0.18), false, 2.0)
	for turret_pos in [Vector2(-88.0, -124.0), Vector2(88.0, -124.0),
			Vector2(-102.0, 66.0), Vector2(102.0, 66.0)]:
		draw_circle(turret_pos, 17.0, armor_dark)
		draw_arc(turret_pos, 17.0, 0.0, TAU, 16, hostile.darkened(0.15), 3.0)
		draw_line(turret_pos, turret_pos + Vector2(0.0, -29.0), hostile.lightened(0.16), 5.0)
	draw_circle(Vector2(0.0, -242.0), 27.0, armor_dark)
	draw_arc(Vector2(0.0, -242.0), 27.0, 0.0, TAU, 20, hostile, 4.0)
	draw_line(Vector2(-8.0, -252.0), Vector2(-8.0, -306.0), hostile.lightened(0.22), 7.0)
	draw_line(Vector2(8.0, -252.0), Vector2(8.0, -306.0), hostile.lightened(0.22), 7.0)
	# 后部动力格栅。
	for x in [-82.0, -54.0, 54.0, 82.0]:
		draw_rect(Rect2(x - 9.0, 250.0, 18.0, 34.0), hostile.darkened(0.52), false, 2.0)


func _status_label_lines(compact: bool) -> PackedStringArray:
	var lines := PackedStringArray(["LAND CARRIER"])
	if compact:
		return lines
	lines.append(AircraftRenderer.status_hp_text(hp, params.max_hp if params else hp))
	lines.append("AIRWING %d PARKED" % parked_aircraft_count())
	lines.append(AircraftRenderer.status_ground_speed_text(speed))
	var dist_m := _status_label_distance_m()
	lines.append(AircraftRenderer.status_range_text(dist_m, dist_m >= 0.0))
	return lines


func _status_label_icon_radius_world() -> float:
	return 360.0


func _start_destroy() -> void:
	_cleanup_children()
	super._start_destroy()


func _exit_tree() -> void:
	_cleanup_children()


func _prune_parked() -> void:
	for i in range(_parked_aircraft.size() - 1, -1, -1):
		var ac: Variant = _parked_aircraft[i]
		if typeof(ac) != TYPE_OBJECT or ac == null or not is_instance_valid(ac):
			_parked_aircraft.remove_at(i)


func _cleanup_children() -> void:
	for ac in _parked_aircraft:
		if ac != null and is_instance_valid(ac):
			ac.queue_free()
	_parked_aircraft.clear()
	for mount in _mounts:
		if mount != null and is_instance_valid(mount):
			mount.queue_free()
	_mounts.clear()
