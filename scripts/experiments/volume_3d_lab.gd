extends Node3D
## F6 独立看模型与地图。不是战斗性能验收；不修改正式入口或世界存档。
const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Airframes := preload("res://scripts/experiments/volume_aircraft_catalog.gd")
const MapFactory := preload("res://scripts/experiments/volume_map_factory.gd")
const MAP_PATH := "res://resources/maps/desert_railway_preview.aglmap"
const COMBAT_SCENE_PATH := "res://scenes/tests/volume_3d_combat.tscn"
var _camera := Camera3D.new()
var _sun := DirectionalLight3D.new()
var _goose := Node3D.new()
var _label := Label.new()
var _focus := Vector3(4770, 70, 440)
var _material := Factory.material()
var _map: MeshInstance3D
var _map_baseline: MeshInstance3D
var _airframes := Node3D.new()
var _airport_center := Vector3.ZERO


func _ready() -> void:
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
	_sun.rotation_degrees = Vector3(-50, -35, 0)
	_sun.light_energy = 0.8
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 6000
	add_child(_sun)
	var doc := MapDocument.load_from(MAP_PATH)
	var airport_points := MapFactory.airport_polygon(doc.airports[0])
	for point in airport_points:
		_airport_center += Vector3(point.x, 0, point.y) / float(airport_points.size())
	var map_packet := MapFactory.build(doc)
	assert(map_packet.ok, "production map must build")
	_map = _add_mesh(self, map_packet.mesh, Vector3.ZERO, Color.WHITE)
	_map.name = "Desert_MapDocument_BatchA"
	_map_baseline = _add_mesh(self, Factory.map_mesh(doc), Vector3.ZERO, Color.WHITE)
	_map_baseline.hide()
	print("[Volume lab] map batch A triangles=%d buildings=%d airports=%d" % [map_packet.triangles, map_packet.buildings, map_packet.airports])
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
	_airframes.hide()
	_goose.show()
	_map.show()
	_map_baseline.hide()
	_camera.size = 720.0
	_camera.position = _focus + (Vector3(530, 690, 700) if tilted else Vector3(0, 1400, 0))
	_camera.look_at(_focus, Vector3.UP if tilted else Vector3.FORWARD)
	_label.text = "MOTHER GOOSE / %s\n1 Top   2 Tilt   3 Shadow   4 Map   5/6 Aircraft   7 Airport   8 Overview   B COMBAT" % ["TILTED INSPECTION" if tilted else "ORTHOGRAPHIC TOP VIEW"]


func _set_map_view() -> void:
	_airframes.hide()
	_goose.hide()
	_map.show()
	_map_baseline.hide()
	var center := Vector3(4700, 0, 0)
	_camera.size = 2000.0
	_camera.position = center + Vector3(1100, 1900, 1200)
	_camera.look_at(center, Vector3.UP)
	_label.text = "DESERT / INDUSTRIAL DISTRICT / SOURCE FOOTPRINTS\n4 Map   7 Airport   8 Overview   5/6 Aircraft   3 Shadow   B COMBAT"


func _set_aircraft_view(tilted: bool) -> void:
	_goose.hide()
	_map.hide()
	_map_baseline.hide()
	_airframes.show()
	_camera.size = 135.0
	_camera.position = _airframes.position + (Vector3(65, 160, 120) if tilted else Vector3(0, 300, 0))
	_camera.look_at(_airframes.position, Vector3.UP if tilted else Vector3.FORWARD)
	_label.text = "AIRCRAFT BATCH A / LEFT TO RIGHT: F-14 / A-10 / F-47 CONCEPT\n5 Top   6 Tilt   3 Shadow   1/2 Mother Goose   4 Map   B COMBAT / NO GAMEPLAY CHANGES"


func _set_map_location(overview: bool) -> void:
	_set_map_view()
	var center := Vector3.ZERO if overview else _airport_center
	_camera.size = 34000.0 if overview else 1300.0
	_camera.far = 100000.0
	_camera.position = center + (Vector3(0, 50000, 0) if overview else Vector3(550, 1600, 800))
	_camera.look_at(center, Vector3.FORWARD if overview else Vector3.UP)
	_label.text = "DESERT / %s / STATIC GEOMETRY FROM MAPDOCUMENT\n4 Industrial   7 Airport   8 Overview   5/6 Aircraft   3 Shadow   B COMBAT" % ["OVERVIEW" if overview else "NEWMAN AIRPORT"]


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
		KEY_B:
			get_viewport().set_input_as_handled()
			var result := get_tree().change_scene_to_file(COMBAT_SCENE_PATH)
			if result != OK:
				push_error("Volume combat scene failed to open: %d" % result)


func _capture_sequence() -> void:
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
	for child: MeshInstance3D in _airframes.get_children():
		failed = _export_mesh(child.mesh, child.name.to_lower() + "_batch_a") or failed
	failed = _export_mesh(_map.mesh, "desert_batch_a") or failed
	var manifest := FileAccess.open("res://bench/results/volume_batch_a_manifest.json", FileAccess.WRITE)
	if manifest == null:
		failed = true
	else:
		var assets: Array[Dictionary] = []
		for key in Airframes.supported_keys():
			assets.append(Airframes.metadata_for(key))
		manifest.store_string(JSON.stringify({"aircraft": assets, "map_source": MAP_PATH,
			"map_status": "static desert sample, not full geography or collision migration",
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


func _save_view(suffix: String) -> bool:
	for frame in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://bench/results/volume_3d_lab_%s.png" % suffix
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("[Volume lab] %s result=%d" % [path, result])
	return result != OK


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
