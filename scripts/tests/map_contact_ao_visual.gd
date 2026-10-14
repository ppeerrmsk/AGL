extends Node
## 正式菜单链、暂停同帧 A/B 和真实退出；不触碰用户存档。
const MAIN := "res://scenes/main_menu.tscn"
const SELECT := "res://scenes/survivor_map_select.tscn"
const AIR := "res://scenes/survivor_select.tscn"
const GAME := "res://scenes/survivor_mode.tscn"
const AO := preload("res://scripts/rendering/map_contact_ao.gd")
const VIEWS := {
	"desert": [["industrial_near", Vector2(4800, 400), 1.3], ["industrial_far", Vector2(4800, 400), 0.26],
		["industrial_rotate", Vector2(4800, 400), 0.65], ["outside", Vector2(-5900, -6250), 0.65]],
	"ocean": [["launch", Vector2(-10800, -5700), 1.3], ["hangar", Vector2(-11080, -7000), 1.3],
		["base_far", Vector2(-10300, -6500), 0.26], ["outside", Vector2(9000, -9000), 0.65]]}
var _pass := 0
var _fail := 0
var _records: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	if not OS.get_user_data_dir().replace("\\", "/").contains("/tmp/map-contact-ao/profile/"):
		push_error("AO menu test requires its isolated profile")
		tree.quit(1)
		return
	tree.current_scene = null
	for key in ["bench_mode", "bench_scenario", "bench_duration", "external_volume_experiment"]:
		if tree.has_meta(key): tree.remove_meta(key)
	OS.set_environment("AGL_MAP_CONTACT_AO", "")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	tree.change_scene_to_file(MAIN)
	for map_key: String in VIEWS:
		if not await _wait_scene(MAIN): return
		tree.current_scene._on_survivor_pressed()
		if not await _wait_scene(SELECT): return
		var map_index := -1
		for i in tree.current_scene.MAP_LIST.size():
			if tree.current_scene.MAP_LIST[i].id == ("desert_railway_preview" if map_key == "desert" else "ocean_islands_preview"):
				map_index = i
		_check(map_index >= 0, "real map selection " + map_key)
		if map_index < 0:
			tree.quit(1)
			return
		tree.current_scene._on_map_selected(map_index)
		if not await _wait_scene(AIR): return
		tree.current_scene._on_aircraft_selected(0)
		if not await _wait_scene(GAME): return
		await tree.create_timer(2.0, true, false, true).timeout
		var mode: Node = tree.current_scene
		var renderer: Node = mode._desert_volume_renderer if map_key == "desert" else mode._map_features._ocean_volume
		_check(is_instance_valid(renderer), "normal entry renderer " + map_key)
		if not is_instance_valid(renderer):
			tree.quit(1)
			return
		if map_key == "desert":
			var preloaded: Dictionary = renderer.get_meta("desert_preload", {})
			_check(preloaded.get("reused", false) and preloaded.get("rendered_frames", 0) >= 4, "AO prepared in real loading handoff")
		mode._camera_ctrl.follow_enabled = false
		mode.camera.ignore_rotation = false
		for view: Array in VIEWS[map_key]:
			mode.camera.position = view[1]
			mode.camera.zoom = Vector2.ONE * float(view[2])
			mode._camera_ctrl.target_zoom = float(view[2])
			mode._camera_ctrl._base_zoom = float(view[2])
			mode.camera.rotation = deg_to_rad(12) if String(view[0]).contains("rotate") else 0.0
			mode.camera.force_update_scroll()
			await tree.create_timer(1.5, true, false, true).timeout
			var materials: Array[ShaderMaterial] = []
			_collect(renderer, materials)
			_check(materials.size() >= 2, "actual AO receiver materials " + map_key)
			tree.paused = true
			var before: Image
			for enabled: bool in [false, true]:
				for material in materials:
					material.set_shader_parameter("contact_ao_strength", 0.65 if enabled else 0.0)
				if map_key == "desert" and view[0] == "industrial_near" and not enabled:
					var apron: MeshInstance3D = renderer._root_map
					var candidate := apron.material_override
					apron.material_override = preload("res://scripts/experiments/volume_mesh_factory.gd").material()
					await tree.process_frame
					await RenderingServer.frame_post_draw
					await tree.process_frame
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("res://bench/results/contact_ao_desert_legacy_material.png")
					apron.material_override = candidate
				if map_key == "ocean": renderer._viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				await tree.process_frame
				await RenderingServer.frame_post_draw
				await tree.process_frame
				await RenderingServer.frame_post_draw
				var shot := get_viewport().get_texture().get_image()
				var suffix := "on" if enabled else "off"
				var path := "res://bench/results/contact_ao_%s_%s_%s.png" % [map_key, view[0], suffix]
				_check(shot.save_png(path) == OK, "capture " + path)
				if not enabled: before = shot
				else:
					var changed := _changed_pixels(before, shot)
					_records.append({"map": map_key, "view": view[0], "materials": materials.size(), "changed_pixels": changed})
					_check(changed == 0 if view[0] == "outside" else changed > 20, "AO pixel effect scoped to region " + map_key + "/" + view[0] + ": " + str(changed))
			tree.paused = false
		# 正式 Tab 输入，不把同帧对拍当成完整战局证据。
		var event := InputEventKey.new()
		event.keycode = KEY_TAB
		event.physical_keycode = KEY_TAB
		event.pressed = true
		Input.parse_input_event(event)
		await tree.process_frame
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		await tree.create_timer(0.3, true, false, true).timeout
		_check(mode._tactical_map.is_open(), "Tab remains reachable " + map_key)
		var mode_ref: WeakRef = weakref(mode)
		var renderer_ref: WeakRef = weakref(renderer)
		mode._quit_to_main_menu()
		mode = null
		renderer = null
		if not await _wait_scene(MAIN): return
		await tree.create_timer(0.3, true, false, true).timeout
		_check(mode_ref.get_ref() == null and renderer_ref.get_ref() == null, "actual map exit releases receivers " + map_key)
	var report := FileAccess.open("res://bench/results/contact_ao_visual.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"pass": _pass, "fail": _fail, "views": _records}, "\t"))
	report.close()
	print("[Contact AO menu Visual] pass=", _pass, " fail=", _fail, " views=", _records.size())
	tree.quit(1 if _fail else 0)


func _collect(node: Node, materials: Array[ShaderMaterial]) -> void:
	if node is MeshInstance3D and node.material_override is ShaderMaterial:
		var material: ShaderMaterial = node.material_override
		if material.get_shader_parameter("contact_ao_texture") is Texture2D and not materials.has(material):
			materials.append(material)
	for child in node.get_children(): _collect(child, materials)


func _changed_pixels(a: Image, b: Image) -> int:
	var first := a.get_data()
	var second := b.get_data()
	var changed := 0
	var channels := 4 if a.get_format() == Image.FORMAT_RGBA8 else 3
	for index in range(0, first.size(), channels):
		if first[index] != second[index] or first[index + 1] != second[index + 1] or first[index + 2] != second[index + 2]: changed += 1
	return changed


func _wait_scene(path: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 35000:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == path and scene.is_node_ready(): return true
	_check(false, "timeout entering " + path)
	get_tree().quit(1)
	return false


func _check(ok: bool, label: String) -> void:
	if ok: _pass += 1
	else:
		_fail += 1
		push_error("AO Visual: " + label)
