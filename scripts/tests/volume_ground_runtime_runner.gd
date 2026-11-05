extends Node2D
## 正式透明合成、真实单位/挂点/甲板状态的近景验收。不是自然完整 Boss 局。
const Overlay := preload("res://scripts/rendering/aircraft_volume_overlay.gd")
const GroundLife := preload("res://scripts/tests/volume_ground_lifecycle_case.gd")
var camera := Camera2D.new()
var _map_features: CanvasItem
var _building_renderer: CanvasItem
var _spawner: Node
var _overlay: CanvasLayer
var _actors: Array[Node2D] = []
var _fail := 0
var _pass := 0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_spawner = self
	add_child(camera)
	camera.make_current()
	var background := CanvasLayer.new()
	background.layer = -100
	add_child(background)
	var fill := ColorRect.new()
	fill.size = Vector2(4096, 4096)
	fill.color = Color("727d74")
	background.add_child(fill)
	_overlay = Overlay.new()
	add_child(_overlay)
	_overlay.setup(self)
	_overlay.set_process(false)
	_run.call_deferred()


func _ground(unit: GroundUnit, point: Vector2, label: String) -> GroundUnit:
	unit.params = AircraftParams.new()
	unit.params.display_name = label
	unit.params.max_hp = 100
	unit.params.icon_color = Color("729ec0")
	unit.position = point
	add_child(unit)
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	_actors.append(unit)
	CombatUnit.all_units.append(unit)
	return unit


func _create_enemy(_kind: int, point: Vector2, heading_deg: float) -> Aircraft:
	# 只替代 spawner 的实体创建依赖；驻机跟随/起飞仍走 LandCarrierUnit 正式入口。
	var ac := Aircraft.new()
	ac.params = preload("res://resources/enemy_fa18.tres").duplicate(true)
	ac.params.icon_color = Color("729ec0")
	ac.initial_heading_deg = heading_deg
	ac.position = point
	add_child(ac)
	ac.process_mode = Node.PROCESS_MODE_DISABLED
	_actors.append(ac)
	CombatUnit.all_units.append(ac)
	return ac


func _capture(label: String) -> void:
	camera.force_update_scroll()
	for actor in _actors:
		actor.queue_redraw()
	_overlay._probe._refresh_members()
	_overlay._process(.016)
	for frame in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var path := "res://bench/results/volume_ground_runtime_%s.png" % label
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture " + label)


func _clear() -> void:
	for raw: Variant in _actors:
		if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw):
			if raw is CombatUnit:
				CombatUnit.all_units.erase(raw)
			raw.queue_free()
	_actors.clear()
	await get_tree().process_frame
	_overlay._probe._refresh_members()
	_overlay._process(.11)


func _run() -> void:
	_fail += await GroundLife.new().run(self)
	camera.make_current()
	camera.zoom = Vector2.ONE * 6
	var vehicles: Array[GroundUnit] = [AtmosphereArtilleryUnit.new(), AAGunUnit.new(),
		AirburstAAUnit.new(), SAMUnit.new(), RadarStation.new(), Tier3SiegeTank.new()]
	for i in vehicles.size():
		var unit := _ground(vehicles[i], Vector2((i % 3 - 1) * 65, (i / 3 - .5) * 62),
			["SPG", "AA", "AIRBURST AA", "SAM", "RADAR", "SIEGE TANK"][i])
		if unit is Tier3SiegeTank:
			unit.position = Vector2(90, 48)
		if unit is AAGunUnit:
			unit.turret_heading = .5
	await _capture("vehicles")
	_check(_overlay._probe._ground_presenter.last_bodies == 6, "all six actual ground vehicle identities render")
	for faction in [CombatUnit.TEAM_PLAYER, CombatUnit.TEAM_HOSTILE, CombatUnit.TEAM_ALLY]:
		for unit in vehicles:
			unit.team = faction
		for detailed in [true, false]:
			camera.zoom = Vector2.ONE * (8.0 if detailed else .6)
			await _capture("faction_%d_%s" % [faction, "full" if detailed else "simple"])
			var route := "ground_" + ("full_" if detailed else "simple_") + "aa"
			if not _overlay._probe._batches.has(route):
				_check(false, "expected ground LOD route exists: " + route)
				continue
			var actual: Color = _overlay._probe._batches[route].multimesh.get_instance_color(0)
			var expected := GameConstants.team_color(faction)
			_check(_overlay._probe._counts.get(route, 0) == 1 \
				and Vector3(actual.r, actual.g, actual.b).distance_to(Vector3(expected.r, expected.g, expected.b)) < .001,
				"real actors switch faction and LOD together")
	await _clear()
	camera.zoom = Vector2.ONE * 1.1
	var carrier := _ground(LandCarrierUnit.new(), Vector2.ZERO, "LAND CARRIER") as LandCarrierUnit
	carrier.spawn_parked_aircraft(self, 4)
	carrier.arm_mounts(self, null, null)
	for mount: CombatUnit in carrier._mounts:
		mount.process_mode = Node.PROCESS_MODE_DISABLED
		mount._physics_process(.016)
		_actors.append(mount)
		CombatUnit.all_units.append(mount)
	await _capture("carrier_parked")
	_check(carrier.parked_aircraft_count() == 4, "carrier owns four actual parked aircraft")
	for angle in [.45, 1.1]:
		carrier.heading = angle
		carrier.rotation = angle
		carrier._physics_process(0.0)
		for mount: CombatUnit in carrier._mounts:
			mount._physics_process(0.0)
		await _capture("carrier_turn_%d" % roundi(rad_to_deg(angle)))
	var launched := carrier.launch_parked_aircraft(1)
	_check(launched.size() == 1 and carrier.parked_aircraft_count() == 3 \
		and not launched[0].has_meta(&"parent_carrier"), "actual launch releases deck ownership")
	launched[0].process_mode = Node.PROCESS_MODE_DISABLED
	await _capture("carrier_launched")
	await _clear()
	camera.zoom = Vector2.ONE * 2.4
	var segment := _ground(ArmoredTrainSegment.new(), Vector2.ZERO, "TRAIN TAIL") as ArmoredTrainSegment
	segment.segment_index = 13
	segment.rotation = .55
	await _capture("train_armored")
	segment.set_targetable(true)
	segment.set_damageable(true)
	await _capture("train_weakpoint")
	_check(_overlay._ground_foreground.points.size() == 48 \
		and _overlay._ground_foreground.get_index() > _overlay._screen.get_index(),
		"tail weakpoint draws above shared 3D texture")
	segment.take_damage(1000, null, "missile")
	await get_tree().process_frame
	await _capture("train_detached")
	_check(segment.detached and _overlay._ground_foreground.points.is_empty(),
		"detached segment retains model but clears live weakpoint")
	await _clear()
	await _city_scale_review()
	print("[Ground runtime] pass=%d fail=%d" % [_pass, _fail])
	AudioManager.request_quit(0 if _fail == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Ground runtime: " + label)


## 显式视觉复核读取已校验近景楼体的原始XYZ；不制造缩放过的示意建筑。
func _city_scale_review() -> void:
	var source := OS.get_environment("AGL_GROUND_CITY_REVIEW")
	if source.is_empty():
		return
	var center := Vector2(-15844, -15035)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for layer in 2:
		var bytes := FileAccess.get_file_as_bytes(source.path_join("layer_%d.bin" % layer))
		var points := bytes.to_float32_array()
		for i in range(0, points.size(), 9):
			var a := Vector3(points[i], points[i+1], points[i+2])
			var b := Vector3(points[i+3], points[i+4], points[i+5])
			var c := Vector3(points[i+6], points[i+7], points[i+8])
			if Vector2(a.x, a.z).distance_to(center) > 220.0:
				continue
			var normal := -(b-a).cross(c-a).normalized()
			vertices.append_array(PackedVector3Array([a,b,c]))
			normals.append_array(PackedVector3Array([normal,normal,normal]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var buildings := MeshInstance3D.new()
	buildings.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("949b92")
	buildings.material_override = material
	_overlay._probe.add_child(buildings)
	camera.position = center
	var placed: Array[Vector2] = []
	for i in 3:
		var point := MapGeography.find_ground_spawn_near(center + Vector2((i-1)*75, 40), 130.0)
		_check(point.is_finite(), "city spawn has legal ground point")
		if not point.is_finite():
			continue
		placed.append(point)
		var unit := _ground(AtmosphereArtilleryUnit.new() if i != 1 else AAGunUnit.new(), point, "SPG" if i != 1 else "AAA")
		unit.team = CombatUnit.TEAM_ALLY if i == 0 else CombatUnit.TEAM_HOSTILE
		_check(MapGeography.is_ground_footprint_clear(point), "city vehicle clears actual building occupancy")
	for zoom in [3.0, 6.0]:
		camera.zoom = Vector2.ONE * zoom
		camera.force_update_scroll()
		_overlay._process(.016)
		buildings.basis = _overlay._probe._display_ground
		await _capture("city_scale_%d" % int(zoom))
	buildings.queue_free()
	await _clear()
