extends Node3D
## 已制作专属机体的四视图画廊。截图成功只证明可渲染；人工目检后才可更新 manifest QA。

const Airframes := preload("res://scripts/experiments/volume_aircraft_catalog.gd")
const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const VIEW_IDS: Array[String] = ["top", "side", "front", "gameplay"]
const PAGE_SIZE := 8
const COLUMNS := 4
const X_SPACING := 50.0
const Z_SPACING := 45.0
const LOD1_SCENARIO := "volume_aircraft_lod_multiview"
const LOD2_SCENARIO := "volume_aircraft_lod2_multiview"
const COLORS: Array[Color] = [
	Color("80b9d2"), Color("d8a66a"), Color("ae91cf"), Color("93bd8c"), Color("cf8a86"),
]

var _camera := Camera3D.new()
var _models: Array[MeshInstance3D] = []
var _model_by_key: Dictionary = {}
var _title := Label.new()
var _keys: Array[String] = []
var _pages: Array = []
var _page_index := 0
var _lod_level := 0


func _ready() -> void:
	match String(get_tree().get_meta("bench_scenario", "")):
		LOD1_SCENARIO:
			_lod_level = Airframes.BODY_LOD_MEDIUM
		LOD2_SCENARIO:
			_lod_level = Airframes.BODY_LOD_LOW
		_:
			_lod_level = 0
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_build_environment()
	_build_models()
	_build_overlay()
	_set_page(0)
	if get_tree().has_meta("bench_mode"):
		_capture_sequence.call_deferred()
	else:
		_set_view("gameplay")


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101a21")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d3e5ec")
	environment.ambient_light_energy = 0.55
	_camera.environment = environment
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 125.0
	_camera.near = 0.1
	_camera.far = 1000.0
	add_child(_camera)
	_camera.make_current()
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	key_light.light_energy = 1.15
	key_light.shadow_enabled = true
	add_child(key_light)


func _build_models() -> void:
	var requested := OS.get_environment("AGL_VOLUME_MODEL_FILTER").split(",", false)
	for key in Airframes.supported_keys():
		if not requested.is_empty() and key not in requested:
			continue
		if _lod_level == 0 or Airframes.supports_body_lod(key):
			_keys.append(key)
	var regular_keys := _keys.duplicate()
	regular_keys.erase("mother_goose")
	for start in range(0, regular_keys.size(), PAGE_SIZE):
		_pages.append(regular_keys.slice(start, mini(start + PAGE_SIZE, regular_keys.size())))
	if "mother_goose" in _keys:
		_pages.append(["mother_goose"])
	for index in _keys.size():
		var key := _keys[index]
		var model := MeshInstance3D.new()
		model.name = key.to_upper()
		model.mesh = Airframes.build(key) if _lod_level == 0 \
			else Airframes.build_runtime_lod(key, _lod_level)
		var material := Factory.material().duplicate() as StandardMaterial3D
		material.albedo_color = COLORS[index % COLORS.size()]
		material.metallic = 0.12
		material.roughness = 0.68
		model.material_override = material
		add_child(model)
		_models.append(model)
		_model_by_key[key] = model


func _set_page(page_index: int) -> void:
	_page_index = clampi(page_index, 0, maxi(0, _pages.size() - 1))
	var page_keys: Array = _pages[_page_index]
	var page_count := page_keys.size()
	var rows := ceili(float(page_count) / COLUMNS)
	for model in _models:
		model.visible = false
	for local_index in page_count:
		var model: MeshInstance3D = _model_by_key[String(page_keys[local_index])]
		model.visible = true
		var row := floori(float(local_index) / COLUMNS)
		var column := local_index % COLUMNS
		var row_count := mini(COLUMNS, page_count - row * COLUMNS)
		model.position = Vector3((float(column) - 0.5 * float(row_count - 1)) * X_SPACING,
			0.0, (float(row) - 0.5 * float(rows - 1)) * Z_SPACING)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var background := ColorRect.new()
	background.color = Color(0.025, 0.045, 0.06, 0.93)
	background.size = Vector2(1600.0, 92.0)
	layer.add_child(background)
	_title.position = Vector2(30.0, 14.0)
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color("e4f0f4"))
	layer.add_child(_title)


func _set_view(view_id: String) -> void:
	for model in _models:
		model.rotation_degrees = Vector3.ZERO
	match view_id:
		"top":
			_camera.position = Vector3(0.0, 240.0, 0.0)
			_camera.look_at(Vector3.ZERO, Vector3.FORWARD)
		"side":
			for model in _models:
				model.rotation_degrees.z = 90.0
			_camera.position = Vector3(0.0, 240.0, 0.0)
			_camera.look_at(Vector3.ZERO, Vector3.FORWARD)
		"front":
			for model in _models:
				model.rotation_degrees.x = 90.0
			_camera.position = Vector3(0.0, 240.0, 0.0)
			_camera.look_at(Vector3.ZERO, Vector3.FORWARD)
		"gameplay":
			_camera.position = Vector3(48.0, 105.0, 88.0)
			_camera.look_at(Vector3.ZERO, Vector3.UP)
		_:
			push_error("Unknown aircraft QA view: %s" % view_id)
	var page_keys: Array = _pages[_page_index]
	var boss_page := page_keys == ["mother_goose"]
	if boss_page:
		_camera.size = 190.0 if view_id == "side" else 520.0
	else:
		_camera.size = 125.0
	var rows_text := " / ".join(page_keys.slice(0, mini(4, page_keys.size()))).to_upper()
	if page_keys.size() > 4:
		rows_text += "  |  " + " / ".join(page_keys.slice(4)).to_upper()
	var tier_label := "LOD0"
	if _lod_level == Airframes.BODY_LOD_MEDIUM:
		tier_label = "LOD1 ≤320 TRI"
	elif _lod_level == Airframes.BODY_LOD_LOW:
		tier_label = "LOD2 ≤128 TRI"
	var framing_label := "identical physical scale"
	if boss_page:
		framing_label = "dedicated boss framing · native model scale"
	elif _lod_level == Airframes.BODY_LOD_MEDIUM:
		framing_label = "per-key structural components · identical physical scale"
	elif _lod_level == Airframes.BODY_LOD_LOW:
		framing_label = "per-key far silhouette · identical physical scale"
	_title.text = "AGL DEDICATED AIRCRAFT 3D %s — %s — PAGE %d/%d\nROWS: %s  |  %s" % [
		tier_label,
		view_id.to_upper(), _page_index + 1, _pages.size(), rows_text,
		framing_label]


func _capture_sequence() -> void:
	var failed := false
	var captures: Array[String] = []
	var file_stem := "volume_aircraft_multiview"
	if _lod_level == Airframes.BODY_LOD_MEDIUM:
		file_stem = "volume_aircraft_lod1_multiview"
	elif _lod_level == Airframes.BODY_LOD_LOW:
		file_stem = "volume_aircraft_lod2_multiview"
	if not OS.get_environment("AGL_VOLUME_MODEL_FILTER").is_empty():
		file_stem += "_filtered"
	for page_index in _pages.size():
		_set_page(page_index)
		for view_id in VIEW_IDS:
			_set_view(view_id)
			for _frame in 10:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := "res://bench/results/%s_page_%02d_%s.png" % [
				file_stem, page_index + 1, view_id]
			var error := get_viewport().get_texture().get_image().save_png(path)
			print("[Volume aircraft QA] %s result=%d" % [path, error])
			failed = failed or error != OK
			captures.append(path)
	var assets: Array[Dictionary] = []
	for key in _keys:
		var lod_suffix := "" if _lod_level == 0 else "_lod%d" % _lod_level
		var export_path := "res://bench/results/aircraft_volume_%s%s.glb" % [key, lod_suffix]
		var mesh := Airframes.build(key) if _lod_level == 0 \
			else Airframes.build_runtime_lod(key, _lod_level)
		failed = _export_mesh(mesh, key, export_path) or failed
		var record := Airframes.metadata_for(key)
		record["derived_glb"] = export_path
		record["lod_level"] = _lod_level
		record["triangles"] = mesh.surface_get_array_len(0) / 3
		assets.append(record)
	var manifest := FileAccess.open("res://bench/results/%s_manifest.json" % file_stem,
		FileAccess.WRITE)
	if manifest == null:
		failed = true
	else:
		manifest.store_string(JSON.stringify({"aircraft": assets, "captures": captures,
			"qa_policy": "render success is not human multiview approval"}, "\t"))
		manifest.close()
	get_tree().quit(1 if failed else 0)


func _export_mesh(mesh: ArrayMesh, key: String, path: String) -> bool:
	var source := MeshInstance3D.new()
	source.name = key.to_upper()
	source.mesh = mesh
	var exporter := GLTFDocument.new()
	var state := GLTFState.new()
	var result := exporter.append_from_scene(source, state)
	if result == OK:
		result = exporter.write_to_filesystem(state, path)
	source.free()
	print("[Volume aircraft QA] export %s result=%d" % [path, result])
	return result != OK
