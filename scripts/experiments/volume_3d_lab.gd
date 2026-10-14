extends Node3D
## F6 独立看模型与地图。不是战斗性能验收；不修改正式入口或世界存档。
const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Airframes := preload("res://scripts/experiments/volume_aircraft_catalog.gd")
const MapFactory := preload("res://scripts/experiments/volume_map_factory.gd")
const SatelliteGround := preload("res://scripts/experiments/volume_satellite_ground.gd")
const VolumeProjection := preload("res://scripts/experiments/volume_projection.gd")
const MAP_PATH := "res://resources/maps/desert_railway_preview.aglmap"
const COMBAT_SCENE_PATH := "res://scenes/tests/volume_3d_combat.tscn"
const DESERT_SCENE_PATH := "res://scenes/tests/volume_3d_desert.tscn"
var _camera := Camera3D.new()
var _sun := DirectionalLight3D.new()
var _goose := Node3D.new()
var _label := Label.new()
var _focus := Vector3(4770, 70, 440)
var _material := Factory.material()
var _map: MeshInstance3D
var _map_baseline: MeshInstance3D
var _map_export: ArrayMesh
var _airframes := Node3D.new()
var _airport_center := Vector3.ZERO
var _district_centers: Array[Vector2] = []
var _district_index := 0
var _raster_camera := Camera2D.new()
var _satellite_ground := SatelliteGround.new()
var _previous_msaa := -1


func _ready() -> void:
	_previous_msaa = get_viewport().msaa_3d
	if _previous_msaa == Viewport.MSAA_DISABLED:
		get_viewport().msaa_3d = Viewport.MSAA_2X
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var world_environment := Environment.new()
	world_environment.background_mode = Environment.BG_COLOR
	world_environment.background_color = Color("202d35")
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color("c8dce6")
	world_environment.ambient_light_energy = 0.35
	_camera.environment = world_environment
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.1
	_camera.far = 8000.0
	add_child(_camera)
	_camera.make_current()
	MapFactory.configure_sun(_sun)
	_sun.directional_shadow_max_distance = 6000
	add_child(_sun)
	var doc := MapDocument.load_from(MAP_PATH)
	var airport_points := MapFactory.airport_polygon(doc.airports[0])
	for point in airport_points:
		_airport_center += Vector3(point.x, 0, point.y) / float(airport_points.size())
	_raster_camera.position = Vector2(4800, 400)
	_raster_camera.zoom = Vector2.ONE * 0.35
	_raster_camera.enabled = false
	add_child(_raster_camera)
	var map_packet := MapFactory.build(doc, true, true)
	assert(map_packet.ok, "production map must build")
	for district: Dictionary in map_packet.districts:
		_district_centers.append(district.center)
	_map_export = map_packet.mesh
	_map = MeshInstance3D.new()
	MapFactory.configure_instance(_map, map_packet, _material)
	add_child(_map)
	_map.add_child(_satellite_ground)
	_satellite_ground.enable_relief()
	assert(_satellite_ground.setup_lab(_raster_camera, String(doc.basemap.meta_path)))
	_map.name = "Desert_MapDocument_Detailed"
	_map_baseline = _add_mesh(self, MapFactory.build(doc, false).mesh, Vector3.ZERO, Color.WHITE)
	_map_baseline.hide()
	print("[Volume lab] detailed map triangles=%d source_buildings=%d airports=%d" % [map_packet.triangles, map_packet.buildings, map_packet.airports])
	_goose.name = "MotherGoose_TechnicalProxy"
	add_child(_goose)
	_goose.position = Vector3(4760, 130, 440)
	var goose_color := Color("4c99cd")
	_add_mesh(_goose, Factory.aircraft("mother_goose"), Vector3.ZERO, goose_color)
	for offset: Vector2 in MotherGooseBoss.PROP_OFFSETS_PX:
		_add_mesh(_goose, Factory.aircraft("prop"), Vector3(offset.y, 8, -offset.x), goose_color)
	for offset: Vector2 in MotherGooseBoss.VLS_OFFSETS_PX:
		_add_mesh(_goose, Factory.aircraft("vls"), Vector3(offset.y, 8, -offset.x), goose_color)
	_goose.get_child(0).name = "Airframe"
	for i in 8:
		_goose.get_child(i + 1).name = "Propeller_%02d" % (i + 1)
	for i in 2:
		_goose.get_child(i + 9).name = "VLS_%02d" % (i + 1)
	add_child(_airframes)
	_airframes.position = Vector3(4760, 180, 440)
	var i := 0
	for kind in ["f14", "a10", "f47"]:
		var aircraft_mesh := Airframes.build(kind)
		var model := _add_mesh(_airframes, aircraft_mesh, Vector3((i - 1) * 65, 0, 0), Color("91adb7"))
		model.name = kind.to_upper()
		print("[Volume lab] %s triangles=%d" % [kind, aircraft_mesh.surface_get_array_len(0) / 3])
		i += 1
	var panel := CanvasLayer.new()
	add_child(panel)
	var background := ColorRect.new()
	background.color = Color(0.035, 0.065, 0.085, 0.94)
	background.size = Vector2(get_viewport().get_visible_rect().size.x, 92)
	panel.add_child(background)
	_label.position = Vector2(28, 16)
	_label.add_theme_font_size_override("font_size", 21)
	panel.add_child(_label)
	_set_view(false)
	if get_tree().has_meta("bench_mode"):
		_capture_sequence.call_deferred()


func _add_mesh(parent: Node3D, mesh: ArrayMesh, position_value: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := _material.duplicate() as StandardMaterial3D
	material.albedo_color = color
	instance.material_override = material
	parent.add_child(instance)
	instance.position = position_value
	return instance


func _set_view(tilted: bool) -> void:
	_map.basis = Basis.IDENTITY
	_camera.near = 0.1
	_airframes.hide()
	_goose.show()
	_map.show()
	_map_baseline.hide()
	_camera.size = 720.0
	_camera.position = _focus + (Vector3(530, 690, 700) if tilted else Vector3(0, 1400, 0))
	_camera.look_at(_focus, Vector3.UP if tilted else Vector3.FORWARD)
	_label.text = "MOTHER GOOSE / %s\n1 Top   2 Tilt   3 Shadow   4 Map   5/6 Aircraft   7 Airport   8 Overview   B BOSS   D DESERT" % ["TILTED INSPECTION" if tilted else "ORTHOGRAPHIC TOP VIEW"]


func _set_map_view() -> void:
	_raster_camera.position = Vector2(4700, 0)
	_raster_camera.zoom = Vector2.ONE * 0.45
	_map.basis = Basis.IDENTITY
	_map_baseline.basis = Basis.IDENTITY
	_camera.near = 0.1
	_airframes.hide()
	_goose.hide()
	_map.show()
	_map_baseline.hide()
	var center := Vector3(4700, 0, 0)
	_camera.size = 2000.0
	_camera.position = center + Vector3(1100, 1900, 1200)
	_camera.look_at(center, Vector3.UP)
	_label.text = "DESERT / INDUSTRIAL DISTRICT / SOURCE FOOTPRINTS\n4 Map   7 Airport   8 Overview   5/6 Aircraft   3 Shadow   B BOSS   D DESERT"


func _set_aircraft_view(tilted: bool) -> void:
	_camera.near = 0.1
	_goose.hide()
	_map.hide()
	_map_baseline.hide()
	_airframes.show()
	_camera.size = 135.0
	_camera.position = _airframes.position + (Vector3(65, 160, 120) if tilted else Vector3(0, 300, 0))
	_camera.look_at(_airframes.position, Vector3.UP if tilted else Vector3.FORWARD)
	_label.text = "AIRCRAFT BATCH A / LEFT TO RIGHT: F-14 / A-10 / F-47 CONCEPT\n5 Top   6 Tilt   3 Shadow   1/2 Mother Goose   4 Map   B BOSS   D DESERT"


func _set_map_location(overview: bool) -> void:
	_set_map_view()
	var center := Vector3.ZERO if overview else _airport_center
	_raster_camera.position = Vector2(center.x, center.z)
	_raster_camera.zoom = Vector2.ONE * (0.025 if overview else 0.65)
	_camera.size = 34000.0 if overview else 1300.0
	_camera.far = 100000.0
	_camera.position = center + (Vector3(0, 50000, 0) if overview else Vector3(550, 1600, 800))
	_camera.look_at(center, Vector3.FORWARD if overview else Vector3.UP)
	_label.text = "DESERT / %s / STATIC GEOMETRY FROM MAPDOCUMENT\n4 Industrial   7 Airport   8 Overview   5/6 Aircraft   3 Shadow   B BOSS   D DESERT" % ["OVERVIEW" if overview else "NEWMAN AIRPORT"]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: _set_view(false)
		KEY_2: _set_view(true)
		KEY_3: _sun.shadow_enabled = not _sun.shadow_enabled
		KEY_4: _set_map_view()
		KEY_5: _set_aircraft_view(false)
		KEY_6: _set_aircraft_view(true)
		KEY_7: _set_map_location(false)
		KEY_8: _set_map_location(true)
		KEY_9: _set_play_map_view(Vector2(4800, 400), 0.65)
		KEY_0:
			_set_district_view(_district_index)
			_district_index = (_district_index + 1) % maxi(_district_centers.size(), 1)
		KEY_B, KEY_D:
			get_viewport().set_input_as_handled()
			var result := get_tree().change_scene_to_file(DESERT_SCENE_PATH if event.keycode == KEY_D else COMBAT_SCENE_PATH)
			if result != OK:
				push_error("Volume combat scene failed to open: %d" % result)


func _set_play_map_view(center: Vector2, zoom_value: float) -> void:
	_set_map_view()
	_raster_camera.position = center
	_raster_camera.zoom = Vector2.ONE * zoom_value
	var canvas := Transform2D.IDENTITY.scaled_local(Vector2.ONE * zoom_value)
	var ground := VolumeProjection.ground_basis(canvas, VolumeProjection.DESERT_TILT)
	var view := VolumeProjection.camera_basis(canvas, VolumeProjection.DESERT_TILT)
	_map.basis = ground
	_map_baseline.basis = ground
	_camera.size = get_viewport().get_visible_rect().size.y / zoom_value
	_camera.transform = Transform3D(view, ground * Vector3(center.x, 0, center.y) + view.z * 50000.0)
	var span := _camera.size * 0.6 + 1200
	_camera.near = 50000 - span
	_camera.far = 50000 + span
	_sun.directional_shadow_max_distance = _camera.far
	_label.text = "DESERT / GAME PROJECTION %.0f DEG / ZOOM %.3f\n9 Industrial game view   0 Districts   4 Inspection   7 Airport   B BOSS   D DESERT" % [VolumeProjection.DESERT_TILT_DEGREES, zoom_value]


func _set_district_view(index: int, zoom_value: float = 0.65) -> void:
	if index < 0 or index >= _district_centers.size():
		return
	_set_play_map_view(_district_centers[index], zoom_value)
	_label.text = "DESERT / DESIGNED DISTRICT %d / SOURCE URBAN BOUNDS / ZOOM %.3f\n0 Next district   9 Industrial   7 Airport   8 Overview   D DESERT COMBAT" % [index + 1, zoom_value]


func _capture_sequence() -> void:
	if OS.get_environment("AGL_VOLUME_RELIEF_LIGHT_QA") == "1":
		var relief_failed := false
		for area: Dictionary in [{"name": "crest_a", "point": Vector2(-5467.63235, -3718.11015)},
			{"name": "crest_b", "point": Vector2(-14092.29482, -6394.81581)},
			{"name": "crest_c", "point": Vector2(1670.01935, -13532.69758)},
			{"name": "industrial", "point": Vector2(4800, 400)}]:
			for zoom_value: float in [0.26, 0.65]:
				_set_play_map_view(area.point, zoom_value)
				await get_tree().create_timer(1.0).timeout
				assert(_satellite_ground._tactical_style and _satellite_ground._planes.size() == 1)
				var entry: Dictionary = _satellite_ground._planes.values()[0]
				var ground_material := entry.node.material_override as ShaderMaterial
				assert(RenderingServer.shader_get_parameter_default(ground_material.shader.get_rid(), "relief_contrast") == 1.5)
				for contrast: float in [1.0, 1.5]:
					ground_material.set_shader_parameter("relief_contrast", contrast)
					relief_failed = await _save_view("relief_light_%s_%d_%s" % [
						area.name, int(zoom_value * 100), "before" if contrast == 1.0 else "after"]) or relief_failed
		print("[Relief light QA] pairs=8 failed=", relief_failed, " FPS_NOT_MEASURED")
		get_tree().quit(1 if relief_failed else 0)
		return
	if OS.get_environment("AGL_VOLUME_CROSSING_QA") == "1":
		await _capture_crossings()
		return
	if OS.get_environment("AGL_VOLUME_WATER_COVERAGE_QA") == "1":
		var coverage_failed := false
		var water_line: MeshInstance3D = _satellite_ground._details.get_node("Source_Water_Contours")
		var water_material := water_line.material_override as ShaderMaterial
		var coverage_value: Variant = water_material.get_shader_parameter("watercourse_coverage_enabled")
		print("[Water coverage shader] path=", water_material.shader.resource_path,
			" packed_has_switch=", water_material.shader.code.contains("watercourse_coverage_enabled"),
			" source_has_switch=", FileAccess.get_file_as_string("res://resources/shaders/volume_map_line.gdshader").contains("watercourse_coverage_enabled"))
		var has_coverage_uniform := false
		for parameter: Dictionary in water_material.shader.get_shader_uniform_list():
			has_coverage_uniform = has_coverage_uniform or (parameter.name == "watercourse_coverage_enabled" and parameter.type == TYPE_BOOL)
		if not has_coverage_uniform:
			push_error("Water coverage QA refuses a shader without the actual switch")
			get_tree().quit(1)
			return
		for area: Dictionary in [{"name": "bend", "point": Vector2(-10100, 10100)},
			{"name": "upstream", "point": Vector2(-14914.4116, 9001.04241)},
			{"name": "junction", "point": Vector2(-3602.54109, 9600.04538)}]:
			for zoom_value: float in [0.13, 0.26, 0.65, 1.30]:
				_set_play_map_view(area.point, zoom_value)
				var original_ink: Variant = water_material.get_shader_parameter("watercourse_color")
				water_material.set_shader_parameter("watercourse_color", Color(0.30, 0.34, 0.29, 0.0))
				coverage_failed = await _save_view("water_coverage_%s_%d_background" % [area.name, int(zoom_value * 100)]) or coverage_failed
				water_material.set_shader_parameter("watercourse_color", original_ink)
				for enabled: bool in [false, true]:
					water_material.set_shader_parameter("watercourse_coverage_enabled", enabled)
					assert(water_material.get_shader_parameter("watercourse_coverage_enabled") == enabled)
					coverage_failed = await _save_view("water_coverage_%s_%d_%s" % [area.name,
						int(zoom_value * 100), "candidate" if enabled else "legacy"]) or coverage_failed
		# 未覆盖的uniform读回Nil；恢复Nil即恢复shader默认值，不能强转bool。
		water_material.set_shader_parameter("watercourse_coverage_enabled", coverage_value)
		print("[Water coverage QA] same geometry and ink, MSAA=", get_viewport().msaa_3d, " FPS_NOT_MEASURED")
		get_tree().quit(1 if coverage_failed else 0)
		return
	if OS.get_environment("AGL_VOLUME_WEST_WATER_QA") == "1":
		var water_failed := false
		for area: Dictionary in [{"name": "bend", "point": Vector2(-10100, 10100)},
			{"name": "upstream", "point": Vector2(-14914.4116, 9001.04241)},
			{"name": "junction", "point": Vector2(-3602.54109, 9600.04538)}]:
			for zoom_value: float in [0.26, 0.65, 1.30]:
				_set_play_map_view(area.point, zoom_value)
				water_failed = await _save_view("west_water_%s_%d" % [area.name, int(zoom_value * 100)]) or water_failed
		get_tree().quit(1 if water_failed else 0)
		return
	if OS.get_environment("AGL_VOLUME_ROAD_JOIN_QA") == "1":
		var join_failed := false
		var road_node: MeshInstance3D = _map.get_node("CrispRouteNetwork")
		var original_mesh := road_node.mesh
		var road_doc := MapDocument.load_from(MAP_PATH)
		var old_packet := MapFactory.build(road_doc, true, true, false)
		var new_packet := MapFactory.build(road_doc, true, true, true)
		assert(old_packet.road_join_count == 0 and new_packet.road_join_count == 2)
		for area: Dictionary in [{"name": "west", "point": Vector2(-10100, 10100)}, {"name": "southwest", "point": Vector2(-11200, 9000)}]:
			for zoom_value: float in [0.26, 0.65, 1.30]:
				_set_play_map_view(area.point, zoom_value)
				for enabled: bool in [false, true]:
					road_node.mesh = new_packet.line_mesh if enabled else old_packet.line_mesh
					join_failed = await _save_view("road_join_%s_%d_%s" % [area.name, int(zoom_value * 100), "after" if enabled else "before"]) or join_failed
		road_node.mesh = original_mesh
		get_tree().quit(1 if join_failed else 0)
		return
	if OS.get_environment("AGL_VOLUME_RAIL_LOD_QA") == "1":
		await _capture_rail_lod()
		return
	if OS.get_environment("AGL_VOLUME_COVER_LOD_QA") == "1":
		await _capture_cover_lod()
		return
	var failed := false
	for tilted in [false, true]:
		_set_view(tilted)
		for frame in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "res://bench/results/volume_3d_lab_%s.png" % ["tilted" if tilted else "top"]
		var error := get_viewport().get_texture().get_image().save_png(path)
		print("[Volume lab] %s result=%d" % [path, error])
		failed = failed or error != OK
	_set_map_view()
	for frame in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var map_error := get_viewport().get_texture().get_image().save_png("res://bench/results/volume_3d_lab_map.png")
	failed = failed or map_error != OK
	# 同机位原型/生产候选比较，只在观察场启用，绝不计入性能窗口。
	_map.hide()
	_map_baseline.show()
	failed = await _save_view("map_baseline") or failed
	_map_baseline.hide()
	for tilted in [false, true]:
		_set_aircraft_view(tilted)
		failed = await _save_view("aircraft_tilt" if tilted else "aircraft_top") or failed
	for overview in [false, true]:
		_set_map_location(overview)
		failed = await _save_view("map_overview" if overview else "airport") or failed
	for zoom_value: float in [0.35, 0.65]:
		_set_play_map_view(Vector2(4800, 400), zoom_value)
		failed = await _save_view("industrial_game_%d" % int(zoom_value * 100)) or failed
		_map.hide()
		_map_baseline.show()
		failed = await _save_view("industrial_game_%d_baseline" % int(zoom_value * 100)) or failed
	_set_play_map_view(Vector2(_airport_center.x, _airport_center.z), 0.65)
	failed = await _save_view("airport_game") or failed
	var airport_doc := MapDocument.load_from(MAP_PATH)
	for index in airport_doc.airports.size():
		var airport_frame := MapFactory.Buildings.frame(MapFactory.airport_polygon(airport_doc.airports[index]))
		for zoom_value: float in [0.65, 1.30]:
			_set_play_map_view(airport_frame.center + airport_frame.side * 70.0, zoom_value)
			failed = await _save_view("airport_%d_services_%d" % [index, int(zoom_value * 100)]) or failed
	for index in _district_centers.size():
		_set_district_view(index, 0.26)
		failed = await _save_view("district_%d_game_26" % index) or failed
		_set_district_view(index)
		failed = await _save_view("district_%d_game" % index) or failed
	for area: Dictionary in [{"name": "lake", "point": Vector2(11227, 43)},
		{"name": "route_gap_west", "point": Vector2(-10100, 10100)},
		{"name": "route_gap_southwest", "point": Vector2(-11200, 9000)},
		{"name": "route_gap_north", "point": Vector2(5900, -8700)},
		{"name": "route_exact_junction", "point": Vector2(-5200, 3700)},
		{"name": "rail_detail", "point": Vector2(4413, -1335)},
		{"name": "rail_yard_source", "point": Vector2(2400, 1500)},
		{"name": "relief", "point": Vector2(-11000, -10500)},
		{"name": "ridge", "point": Vector2(-5900, -6250)},
		{"name": "core_crest_a", "point": Vector2(-5467.63235, -3718.11015)},
		{"name": "core_crest_b", "point": Vector2(-14092.29482, -6394.81581)},
		{"name": "core_crest_c", "point": Vector2(1670.01935, -13532.69758)},
		{"name": "scrub", "point": Vector2(-6359.84, -15465.87)}]:
		for zoom_value: float in [0.26, 0.65]:
			_set_play_map_view(area.point, zoom_value)
			failed = await _save_view("%s_%d" % [area.name, int(zoom_value * 100)]) or failed
	for river: Dictionary in [{"name": "river_kalgan_slope", "point": Vector2(-3761.94, -7540.73)},
		{"name": "river_kalgan_bend", "point": Vector2(-1916.3, -8621.03)},
		{"name": "river_western", "point": Vector2(-757.31, 9538.58)}]:
		for zoom_value: float in [0.26, 0.65, 1.3]:
			_set_play_map_view(river.point, zoom_value)
			failed = await _save_view("%s_%d" % [river.name, int(zoom_value * 100)]) or failed
	for shore: Dictionary in [{"name": "shore_lake_close", "point": Vector2(11742.33, -1421.92)},
		{"name": "shore_island_turn", "point": Vector2(10788.89, -1286.33)},
		{"name": "shore_hairpin", "point": Vector2(-1916.3, -8621.03)}]:
		for zoom_value: float in [1.3, 2.6]:
			_set_play_map_view(shore.point, zoom_value)
			failed = await _save_view("%s_%d" % [shore.name, int(zoom_value * 100)]) or failed
	for child: MeshInstance3D in _airframes.get_children():
		failed = _export_mesh(child.mesh, child.name.to_lower() + "_batch_a") or failed
	failed = _export_mesh(_map_baseline.mesh, "desert_batch_a") or failed
	failed = _export_mesh(_map_export, "desert_volume_current") or failed
	var manifest := FileAccess.open("res://bench/results/volume_batch_a_manifest.json", FileAccess.WRITE)
	if manifest == null:
		failed = true
	else:
		var assets: Array[Dictionary] = []
		for key in Airframes.supported_keys():
			assets.append(Airframes.metadata_for(key))
		manifest.store_string(JSON.stringify({"aircraft": assets, "map_source": MAP_PATH,
			"map_status": "geometry-only GLB; shared streamed satellite ground is runtime-only, not embedded",
			"coordinates": "x right, y up, aircraft forward -z; world unit equals AGL pixel"}, "\t"))
		manifest.close()
	var exporter := GLTFDocument.new()
	var state := GLTFState.new()
	# GLB 以模型原点导出，避免 Blender 中导入到样区数千单位之外。
	_goose.position = Vector3.ZERO
	var result := exporter.append_from_scene(_goose, state)
	if result == OK:
		result = exporter.write_to_filesystem(state, "res://bench/results/mother_goose_technical_proxy.glb")
	print("[Volume lab] editable glTF export result=%d (no gameplay attached)" % result)
	get_tree().quit(1 if failed or result != OK else 0)


func _capture_crossings() -> void:
	# 旧/新都经同一个正式透明材质和批次，不用单独不透明候选代替接入验收。
	var doc := MapDocument.load_from(MAP_PATH)
	var packet := MapFactory.build(doc, true, true, true, false)
	var node: MeshInstance3D = _map.get_node("CrispRouteNetwork")
	var current := node.mesh
	var failed := false
	for area: Dictionary in [{"name":"double", "point":Vector2(615.01011,-3069.83700)},
		{"name":"west", "point":Vector2(-1508.94404,-5111.29061)},
		{"name":"east", "point":Vector2(3410.22448,-1800.78650)}]:
		for zoom_value: float in [0.26,0.65,1.3,2.6]:
			for enabled in [false,true]:
				node.mesh = current if enabled else packet.line_mesh
				_set_play_map_view(area.point,zoom_value)
				failed = await _save_view("crossing_%s_%d_%s" % [area.name,int(zoom_value*100),"new" if enabled else "old"]) or failed
	node.mesh = current
	get_tree().quit(1 if failed else 0)


func _capture_rail_lod() -> void:
	# 同一实际线路材质逐次关闭/开启过滤；没有改图或换一套简化几何。
	var material := _map.get_node("CrispRouteNetwork").material_override as ShaderMaterial
	var enabled: bool = material.get_shader_parameter("rail_lod_enabled")
	var failed := not enabled
	var rows: Array[Dictionary] = []
	for area: Dictionary in [{"name": "bend", "point": Vector2(4413, -1335)},
		{"name": "west", "point": Vector2(-8242, -7411)}]:
		for zoom_value: float in [0.13, 0.26, 0.40, 0.65, 1.30]:
			_set_play_map_view(area.point, zoom_value)
			for filtered in [false, true]:
				material.set_shader_parameter("rail_lod_enabled", filtered)
				var suffix := "rail_lod_%s_%d_%s" % [area.name, int(zoom_value * 100), "filtered" if filtered else "legacy"]
				failed = await _save_view(suffix) or failed
				rows.append({"area": area.name, "zoom": zoom_value, "filtered": filtered,
					"shader_enabled": material.get_shader_parameter("rail_lod_enabled"),
					"rail_width_px": 2.6 * zoom_value * get_viewport().get_stretch_transform().get_scale().x,
					"image": "volume_3d_lab_" + suffix + ".png"})
	material.set_shader_parameter("rail_lod_enabled", enabled)
	var report := FileAccess.open("res://bench/results/volume_rail_lod_qa.json", FileAccess.WRITE)
	if report == null:
		failed = true
	else:
		report.store_string(JSON.stringify({"rows": rows, "failed": failed, "fps_measured": false}, "\t"))
		report.close()
	print("[Rail LOD QA] rows=", rows.size(), " failed=", failed, " FPS_NOT_MEASURED")
	get_tree().quit(1 if failed else 0)


func _capture_cover_lod() -> void:
	# 专项同机位对拍，不属于FPS窗口；冻结桥接更新以强制分别显示已构建的近/远档。
	var failed := false
	var rows: Array[Dictionary] = []
	_set_play_map_view(Vector2(-6359.84, -15465.87), 0.26)
	await get_tree().create_timer(0.2).timeout
	var pixels_per_zoom: float = _satellite_ground.debug_state().cover_lod_error_px / 0.26
	if not is_finite(pixels_per_zoom) or pixels_per_zoom <= 0:
		push_error("cover LOD QA requires a live tilted orthographic camera")
		get_tree().quit(1)
		return
	# 按实际输出换算临界缩放，窗口缩放后也必须真正跨过enter/exit两条线。
	for zoom_value: float in [0.26, 0.65, 0.205 / pixels_per_zoom, 0.19 / pixels_per_zoom, 0.145 / pixels_per_zoom, 0.17 / pixels_per_zoom]:
		_set_play_map_view(Vector2(-6359.84, -15465.87), zoom_value)
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		var automatic: Dictionary = _satellite_ground.debug_state()
		var row := {"zoom": zoom_value, "automatic_far": automatic.cover_lod_far,
			"error_px": automatic.cover_lod_error_px, "swaps": automatic.cover_lod_swaps,
			"archive_misses": automatic.archive_misses, "shots": [],
			"logical_view_size": str(get_viewport().get_visible_rect().size),
			"logical_to_target_scale": str(get_viewport().get_stretch_transform().get_scale()),
			"render_texture_size": str(get_viewport().get_texture().get_size())}
		set_process(false)
		for far in [false, true]:
			_satellite_ground._apply_cover_lod(far)
			for frame in 3:
				await RenderingServer.frame_post_draw
			var path := "res://bench/results/volume_cover_lod_%02d_%s.png" % [rows.size(), "far" if far else "near"]
			failed = get_viewport().get_texture().get_image().save_png(path) != OK or failed
			row.shots.append(path)
		_satellite_ground._apply_cover_lod(automatic.cover_lod_far)
		set_process(true)
		rows.append(row)
	var report := FileAccess.open("res://bench/results/volume_cover_lod_qa.json", FileAccess.WRITE)
	if report == null:
		failed = true
	else:
		report.store_string(JSON.stringify({"rows": rows, "fps_measured": false,
			"forced_pairs": true, "automatic_switches": "includes forced QA swaps; not a performance counter"}, "\t"))
		report.close()
	print("[Cover LOD QA] rows=", rows.size(), " failed=", failed, " FPS_NOT_MEASURED")
	get_tree().quit(1 if failed else 0)


func _save_view(suffix: String) -> bool:
	# 瓦片与渐变使用真实流送器；等已驻留目标，不能截图尚未清晰的父层冒充 Detail。
	await get_tree().create_timer(1.0).timeout
	for frame in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://bench/results/volume_3d_lab_%s.png" % suffix
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("[Volume lab] %s result=%d" % [path, result])
	return result != OK


func _process(delta: float) -> void:
	_satellite_ground.sync(delta)


func _exit_tree() -> void:
	if _previous_msaa >= 0 and get_viewport().msaa_3d == Viewport.MSAA_2X:
		get_viewport().msaa_3d = _previous_msaa


func _export_mesh(mesh: ArrayMesh, name_value: String) -> bool:
	var source := MeshInstance3D.new()
	source.name = name_value
	source.mesh = mesh
	source.material_override = _material
	var exporter := GLTFDocument.new()
	var state := GLTFState.new()
	var result := exporter.append_from_scene(source, state)
	if result == OK:
		result = exporter.write_to_filesystem(state, "res://bench/results/%s.glb" % name_value)
	source.free()
	print("[Volume lab] export %s result=%d" % [name_value, result])
	return result != OK
