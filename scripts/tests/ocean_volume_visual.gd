extends Node
## 实际菜单链、固定机位A/B与退出重进；只允许隔离profile。
const MAIN := "res://scenes/main_menu.tscn"
const MAP_SELECT := "res://scenes/survivor_map_select.tscn"
const AIR_SELECT := "res://scenes/survivor_select.tscn"
const GAME := "res://scenes/survivor_mode.tscn"
const VIEWS := [
	["base", Vector2(-10300, -6500), 0.26],
	["base", Vector2(-10300, -6500), 0.65],
	["launch", Vector2(-10900, -5860), 0.98],
	["hangars", Vector2(-11080, -7000), 0.98],
	["coast", Vector2(-4500, 7000), 0.26],
	["coast", Vector2(-4500, 7000), 0.65],
	["ridge", Vector2(-10368, 14115), 0.26],
	["ridge", Vector2(-10368, 14115), 0.65],
	["northeast", Vector2(9000, -9000), 0.26],
	["northeast", Vector2(9000, -9000), 0.65],
	["sea", Vector2.ZERO, 0.26],
	["overview", Vector2.ZERO, 0.06],
	["overview", Vector2.ZERO, 0.13]]
var _fail := 0
var _records: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	var initial_orphans := Node.get_orphan_node_ids()
	if not OS.get_user_data_dir().replace("\\", "/").contains("/tmp/ocean-volume/profile/"):
		push_error("ocean menu test requires isolated tmp/ocean-volume/profile")
		tree.quit(1)
		return
	tree.current_scene = null
	for key in ["bench_mode", "bench_scenario", "bench_duration", "external_volume_experiment"]:
		if tree.has_meta(key):
			tree.remove_meta(key)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	tree.change_scene_to_file(MAIN)
	for enabled: bool in [false, true]:
		OS.set_environment("AGL_OCEAN_VOLUME", "" if enabled else "off")
		if not await _wait_scene(MAIN): return
		tree.current_scene._on_survivor_pressed()
		if not await _wait_scene(MAP_SELECT): return
		tree.current_scene._on_map_selected(2)
		if not await _wait_scene(AIR_SELECT): return
		tree.current_scene._on_aircraft_selected(0)
		if not await _wait_scene(GAME): return
		await tree.create_timer(2.0, true, false, true).timeout
		var mode: Node = tree.current_scene
		_check(mode._map_id == "ocean_islands_preview" and mode._map_preview_only, "real ocean selection preserves preview contract")
		var overlay: Variant = mode._map_features._ocean_volume
		_check(is_instance_valid(overlay) == enabled, "normal entry chooses requested presentation")
		_check(mode._building_renderer.visible == not enabled, "only one building presentation")
		if enabled and OS.get_environment("AGL_MAP_LOD_AUDIT") == "1":
			_fail += await preload("res://scripts/tests/map_lod_acceptance_probe.gd").new().run(mode, "ocean")
		mode._camera_ctrl.follow_enabled = false
		for view in VIEWS:
			mode.camera.position = view[1]
			mode._camera_ctrl.target_zoom = float(view[2])
			mode.camera.zoom = Vector2.ONE * float(view[2])
			mode.camera.force_update_scroll()
			await tree.create_timer(1.5, true, false, true).timeout
			await RenderingServer.frame_post_draw
			var suffix := "r4" if enabled else "baseline"
			if enabled and OS.get_environment("AGL_OCEAN_MSAA_REVIEW") == "1":
				await _capture_msaa_pair(overlay, String(view[0]) + "_%03d" % roundi(float(view[2]) * 100))
			var path := "res://bench/results/ocean_%s_%s_%03d.png" % [suffix, view[0], roundi(float(view[2]) * 100)]
			_check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture " + path)
			# 额外清晰度检查不替代上面的带天气正式画面或后续真实战斗负载。
			mode._weather.hide()
			await RenderingServer.frame_post_draw
			_check(get_viewport().get_texture().get_image().save_png(path.replace(".png", "_clear.png")) == OK, "clear inspection " + path)
			mode._weather.show()
			if enabled:
				var state: Dictionary = overlay.debug_state()
				state["view"] = view[0]
				state["zoom"] = view[2]
				_records.append(state)
				if OS.get_environment("AGL_OCEAN_COVERED_REVIEW") == "1":
					var output := OS.get_environment("AGL_MAP_LOD_AUDIT_OUT")
					DirAccess.make_dir_recursive_absolute(output)
					var native_path := output.path_join("native_%s_%03d.png" % [view[0], roundi(float(view[2]) * 100)])
					overlay._viewport.get_texture().get_image().save_png(native_path)
					state["native_rgba"] = native_path
					if view[0] == "base" and float(view[2]) == 0.65:
						_check(state.covered_raster_suppressed, "interior avoids duplicate raster")
				_check(state.misses == 0 and state.planes <= 17 and state.runtime_mesh_builds == 0, "prebuilt shared terrain at " + view[0])
		mode.camera.position = Vector2(-10300, -6500)
		mode._camera_ctrl.target_zoom = 0.65
		mode.camera.zoom = Vector2.ONE * 0.65
		mode.camera.force_update_scroll()
		await tree.create_timer(2.0, true, false, true).timeout
		if enabled:
			var before: int = overlay.redraws
			var before_state := {"canvas": str(get_viewport().get_canvas_transform()), "map": overlay.debug_state(),
				"raster": mode._map_features._raster_basemap.debug_state(), "base_zoom": mode._camera_ctrl._base_zoom,
				"cine_zoom": mode._camera_ctrl.cine_zoom_mult, "trauma": mode._camera_ctrl.cine_shake_trauma}
			await tree.create_timer(0.5, true, false, true).timeout
			if overlay.redraws != before:
				print("[Ocean stationary diagnostic] before=", JSON.stringify(before_state), " after=",
					JSON.stringify({"canvas": str(get_viewport().get_canvas_transform()), "map": overlay.debug_state(),
					"raster": mode._map_features._raster_basemap.debug_state(), "base_zoom": mode._camera_ctrl._base_zoom,
					"cine_zoom": mode._camera_ctrl.cine_zoom_mult, "trauma": mode._camera_ctrl.cine_shake_trauma}))
			_check(overlay.redraws == before, "stationary settled map does not redraw")
		var event := InputEventKey.new()
		event.keycode = KEY_TAB
		event.physical_keycode = KEY_TAB
		event.pressed = true
		Input.parse_input_event(event)
		var released := event.duplicate() as InputEventKey
		released.pressed = false
		Input.parse_input_event(released)
		await tree.create_timer(0.5, true, false, true).timeout
		_check(mode._tactical_map.is_open(), "real Tab opens")
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://bench/results/ocean_tab_%s.png" % str(enabled))
		Input.parse_input_event(event)
		Input.parse_input_event(released)
		await tree.process_frame
		var mode_ref: WeakRef = weakref(mode)
		var overlay_ref: WeakRef = weakref(overlay) if enabled else null
		mode._quit_to_main_menu()
		mode = null
		overlay = null
		if not await _wait_scene(MAIN): return
		await tree.create_timer(0.3, true, false, true).timeout
		_check(mode_ref.get_ref() == null and (overlay_ref == null or overlay_ref.get_ref() == null), "actual exit releases map before reentry")
		for identity: int in Node.get_orphan_node_ids():
			_check(identity in initial_orphans, "actual menu exit leaves no new orphan " + str(identity))
	var file := FileAccess.open("res://bench/results/ocean_visual_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail": _fail, "views": _records}, "\t"))
	file.close()
	print("[Ocean menu Visual] fail=", _fail, " captures=", _records.size(), " actual menu A/B and exit; not combat acceptance")
	if OS.get_environment("AGL_BENCH_VERBOSE") == "1":
		for identity: int in Node.get_orphan_node_ids():
			var orphan: Variant = instance_from_id(identity)
			if typeof(orphan) == TYPE_OBJECT and is_instance_valid(orphan):
				var script: Script = orphan.get_script()
				print("[Ocean orphan] id=", identity, " name=", orphan.name, " script=", script.resource_path if script != null else "native")
	tree.quit(1 if _fail else 0)


func _capture_msaa_pair(overlay: Node, label: String) -> void:
	var output := OS.get_environment("AGL_MAP_LOD_AUDIT_OUT")
	assert(not output.is_empty(), "MSAA review requires explicit output")
	DirAccess.make_dir_recursive_absolute(output)
	var original: int = overlay._viewport.msaa_3d
	for quality: int in [Viewport.MSAA_4X, Viewport.MSAA_2X]:
		overlay._viewport.msaa_3d = quality
		overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := output.path_join("%s_%dx.png" % [label, 4 if quality == Viewport.MSAA_4X else 2])
		_check(overlay._viewport.get_texture().get_image().save_png(path) == OK, "native map MSAA pair " + path)
	overlay._viewport.msaa_3d = original
	overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _wait_scene(path: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 35000:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and scene.scene_file_path == path and scene.is_node_ready():
			if OS.get_environment("AGL_BENCH_VERBOSE") == "1":
				print("[Ocean scene orphans] ", path, " ", Node.get_orphan_node_ids())
			return true
	_check(false, "timeout entering " + path)
	get_tree().quit(1)
	return false


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fail += 1
		push_error("Ocean Visual: " + label)
