extends Node
## 独立根观察者穿过真实Loading/Survivor/菜单；不把此路线截图冒充战斗FPS。
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
var _fail := 0
var _output := "res://bench/results"


func run() -> void:
	var requested := OS.get_environment("AGL_TOKYO_PRELOAD_OUT")
	if not requested.is_empty():
		if DirAccess.dir_exists_absolute(requested) or DirAccess.make_dir_recursive_absolute(requested) != OK:
			get_tree().quit(1)
			return
		_output = requested
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tree := get_tree()
	# 正式相机/地图入口，使用现有预览隔离避免写生涯；不让压力场改出生点和镜头倍率。
	tree.set_meta("bench_mode", false)
	tree.set_meta("map_preview_only", true)
	tree.set_meta("bench_scenario", "")
	tree.set_meta("bench_duration", 120.0)
	if OS.get_environment("AGL_TOKYO_SHORELINE") != "":
		_fail += await preload("res://scripts/tests/tokyo_shoreline_runtime_review.gd").cancelled_loading(self)
	if OS.get_environment("AGL_TOKYO_AO_PRELOAD") != "":
		_fail += await preload("res://scripts/tests/tokyo_preloaded_ao_review.gd").cancelled_loading(self)
	var error := tree.change_scene_to_file("res://scenes/building_preloader.tscn")
	if error != OK:
		tree.quit(1)
		return
	var prepared_ref: WeakRef
	var overlay_id := 0
	var viewport_id := 0
	var stream_id := 0
	var captured := false
	var native_captured := false
	var ao_texture_ref: WeakRef
	var fixed_texture_ref: WeakRef
	var fixed_texture_refs: Array[WeakRef] = []
	var shore_mesh_refs: Array[WeakRef] = []
	var low_wall_refs: Array[WeakRef] = []
	var record := {"headless": DisplayServer.get_name() == "headless", "fps_evidence": false, "route_preview_only": true}
	var deadline := Time.get_ticks_msec() + 60000
	var battle: Variant = null
	while Time.get_ticks_msec() < deadline:
		for candidate: Node in tree.get_nodes_in_group(Session.GROUP):
			if prepared_ref == null and is_instance_valid(candidate.overlay):
				prepared_ref = weakref(candidate)
				overlay_id = candidate.overlay.get_instance_id()
				viewport_id = candidate.overlay._viewport.get_instance_id()
				if candidate.overlay.debug_state().has("stream"):
					stream_id = candidate.overlay._stream.get_instance_id()
			if candidate.status in ["ready", "armed", "retained", "claimed"]:
				record["rendered_frames"] = candidate.rendered_frames
				if not native_captured:
					if OS.get_environment("AGL_TOKYO_FIXED_ATLAS")!="":
						record["prepared_fixed_atlas"]=candidate.overlay._fixed_atlas.stats.duplicate(true)
						fixed_texture_ref=weakref(candidate.overlay._fixed_atlas._texture)
						for member: RefCounted in candidate.overlay._fixed_atlas.members():
							fixed_texture_refs.append(weakref(member._texture))
					if OS.get_environment("AGL_TOKYO_SHORELINE") != "":
						record["prepared_shoreline"] = candidate.overlay._shoreline.stats.duplicate(true)
						for index in candidate.overlay._shoreline._meshes.size():
							shore_mesh_refs.append(weakref(candidate.overlay._shoreline._meshes[index]))
					if OS.get_environment("AGL_TOKYO_AO_PRELOAD") != "":
						record["prepared_ao"] = candidate.overlay.debug_state().ao_preloaded
						ao_texture_ref = weakref(candidate.overlay._preloaded_ao._texture)
					_native_capture(candidate.overlay, "tokyo_r48_prepared_native.png")
					native_captured = true
		var scene := tree.current_scene
		if scene != null and scene.scene_file_path == "res://scenes/building_preloader.tscn":
			if not captured and scene._volume_progress() > 0.1 and scene._bar.value > 0.0:
				record["loading_progress"] = scene._bar.value
				await _capture("tokyo_r48_loading.png")
				captured = true
		scene = tree.current_scene
		if scene != null and scene.scene_file_path == "res://scenes/survivor_mode.tscn" and is_instance_valid(scene._map_features):
			battle = scene
			break
		await tree.process_frame
	if typeof(battle) != TYPE_OBJECT or not is_instance_valid(battle):
		push_error("Tokyo preload route did not reach Survivor")
		tree.quit(1)
		return
	var session: Variant = prepared_ref.get_ref() if prepared_ref != null else null
	var map: Variant = battle._map_features._tokyo_volume
	if typeof(session) != TYPE_OBJECT or not is_instance_valid(session) or not is_instance_valid(map):
		tree.quit(1)
		return
	_fail += int(map.get_instance_id() != overlay_id or map._viewport.get_instance_id() != viewport_id)
	if stream_id != 0:
		_fail += int(map._stream.get_instance_id() != stream_id)
	record["sea_status"] = session.status
	if OS.get_environment("AGL_TOKYO_LOW_WALL_MANIFEST") != "":
		record["low_wall_loading_identity"] = session.low_wall_manifest == OS.get_environment("AGL_TOKYO_LOW_WALL_MANIFEST")
		record.low_wall_loading_identity = record.low_wall_loading_identity and session.low_wall_fade == OS.get_environment("AGL_TOKYO_LOW_WALL_FADE")
		_fail += int(not record.low_wall_loading_identity)
	record["sea_state"] = map.debug_state()
	record["entry_camera"] = str(battle.camera.position)
	await tree.create_timer(0.3).timeout
	await _capture("tokyo_r48_spawn.png")
	battle._camera_ctrl.follow_enabled = false
	battle._camera_ctrl.target_zoom = CameraController.START_ZOOM
	battle.camera.zoom = Vector2.ONE * CameraController.START_ZOOM
	battle.camera.position = map._archive.bounds.get_center()
	battle.camera.force_update_scroll()
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = map.debug_state()
		if session.status == "claimed" and Session.state_ready(state):
			break
		await tree.process_frame
	_fail += int(session.status != "claimed" or not Session.state_ready(map.debug_state()))
	if DisplayServer.get_name() != "headless":
		_fail += int(record.get("rendered_frames", 0) < 2)
	await tree.create_timer(0.5).timeout
	await _capture("tokyo_r48_first_city.png")
	_native_capture(map, "tokyo_r48_claimed_native.png")
	record["city_state"] = map.debug_state()
	if stream_id != 0:
		_fail += int(record.city_state.stream.started != record.sea_state.stream.started)
		record["no_same_view_reloads"] = record.city_state.stream.started == record.sea_state.stream.started
	record["same_overlay"] = map.get_instance_id() == overlay_id
	record["same_viewport"] = map._viewport.get_instance_id() == viewport_id
	if not shore_mesh_refs.is_empty():
		var warmed: Dictionary = record.prepared_shoreline.get("material_warmup", {})
		_fail += int(DisplayServer.get_name() != "headless" and (not warmed.get("rendered", false) or warmed.get("submitted_frames", 0) < 2))
		_fail += int(map._shoreline.stats.get("material_warmup", {}).get("reserved_bytes", -1) != 0)
		record["same_shoreline_meshes"] = record.prepared_shoreline.mesh_ids == map._shoreline.stats.mesh_ids
		_fail += int(not record.same_shoreline_meshes)
	if OS.get_environment("AGL_TOKYO_AO_PRELOAD") != "":
		_fail += int(not record.get("prepared_ao", {}).get("preloaded", false))
		_fail += int(record.prepared_ao.texture_id != map._preloaded_ao._texture.get_instance_id())
		record["ao_strength_review_skipped"] = OS.get_environment("AGL_TOKYO_AO_STRENGTH_REVIEW") == "0"
		if not record.ao_strength_review_skipped and OS.get_environment("AGL_TOKYO_TILE_GROUND_REVIEW") != "1" and OS.get_environment("AGL_TOKYO_TILE_STREAM_REVIEW") != "1":
			_fail += await preload("res://scripts/tests/tokyo_preloaded_ao_review.gd").run(battle, map, _output)
	if OS.get_environment("AGL_TOKYO_AO") != "":
		_fail += await preload("res://scripts/tests/tokyo_ao_review.gd").run(battle, map, _output)
	if OS.get_environment("AGL_TOKYO_LOW_WALL_REVIEW") == "1":
		_fail += await preload("res://scripts/tests/tokyo_component_review.gd").run(battle,map,_output)
		if OS.get_environment("AGL_TOKYO_LOW_WALL_FADE") == "1":
			_fail += await preload("res://scripts/tests/tokyo_low_wall_review.gd").run(battle,map,_output)
	elif OS.get_environment("AGL_TOKYO_FULL_GRID_REVIEW") == "1":
		_fail += await preload("res://scripts/tests/tokyo_full_grid_review.gd").run(battle, map, _output)
	elif OS.get_environment("AGL_TOKYO_COMPONENTS") != "" and OS.get_environment("AGL_TOKYO_TILE_GROUND_REVIEW") != "1" and OS.get_environment("AGL_TOKYO_TILE_STREAM_REVIEW") != "1" and OS.get_environment("AGL_TOKYO_REGIONAL_REVIEW") != "1" and OS.get_environment("AGL_TOKYO_VISIBLE_GROUND_REVIEW") != "1" and OS.get_environment("AGL_TOKYO_FIXED_ATLAS_REVIEW")=="" and OS.get_environment("AGL_TOKYO_RAIL_REVIEW") != "1":
		_fail += await preload("res://scripts/tests/tokyo_component_review.gd").run(battle, map, _output)
	if OS.get_environment("AGL_TOKYO_TILE_STREAM_REVIEW") == "1":
		_fail += await preload("res://scripts/tests/tokyo_tile_stream_review.gd").run(battle,map,_output)
	if OS.get_environment("AGL_TOKYO_TILE_GROUND_REVIEW") == "1":
		if OS.get_environment("AGL_TOKYO_DISTRICT_FINISH_REVIEW") == "1":
			_fail += await preload("res://scripts/tests/tokyo_district_finish_review.gd").run(battle,map,_output)
		elif OS.get_environment("AGL_TOKYO_DISTRICT_BOUNDARY_REVIEW") == "1":
			_fail += await preload("res://scripts/tests/tokyo_district_boundary_review.gd").run(battle,map,_output)
		elif OS.get_environment("AGL_TOKYO_SHORELINE_REVIEW") == "1":
			_fail += await preload("res://scripts/tests/tokyo_shoreline_runtime_review.gd").run(battle,map,_output)
		elif OS.get_environment("AGL_TOKYO_SHORELINE_DATA") != "":
			_fail += await preload("res://scripts/tests/tokyo_shoreline_review.gd").run(battle,map,_output)
		elif OS.get_environment("AGL_TOKYO_GROUND_BOUNDARY_REVIEW") == "1":
			_fail += await preload("res://scripts/tests/tokyo_ground_boundary_review.gd").run(battle,map,_output)
		elif OS.get_environment("AGL_TOKYO_WATER_PALETTE_REVIEW") == "1":
			_fail += await preload("res://scripts/tests/tokyo_water_palette_review.gd").run(battle,map,_output)
		elif OS.get_environment("AGL_TOKYO_GEOREFERENCE_REVIEW") == "1":
			_fail += await preload("res://scripts/tests/tokyo_georeference_review.gd").run(battle,map,_output)
		elif OS.get_environment("AGL_TOKYO_GROUND_PALETTE_REVIEW") == "1":
			_fail += await preload("res://scripts/tests/tokyo_ground_palette_review.gd").run(battle,map,_output)
		elif OS.get_environment("AGL_TOKYO_GROUND_COLOR_PROBE") == "1":
			_fail += await preload("res://scripts/tests/tokyo_ground_color_probe.gd").run(battle, map, _output)
		else:
			_fail += await preload("res://scripts/tests/tokyo_tile_ground_review.gd").run(battle, map, _output)
	if OS.get_environment("AGL_TOKYO_CANONICAL_REVIEW") == "1" or OS.get_environment("AGL_TOKYO_REGIONAL_REVIEW") == "1":
		var review: Script = load("res://scripts/tests/tokyo_canonical_review.gd")
		if review == null or not review.can_instantiate():
			_fail += 1
		else:
			_fail += await review.run(battle, map, _output)
	if OS.get_environment("AGL_TOKYO_VISIBLE_GROUND_REVIEW")=="1":
		_fail+=await preload("res://scripts/tests/tokyo_visible_ground_review.gd").run(battle,map,_output)
	if OS.get_environment("AGL_TOKYO_FIXED_ATLAS_REVIEW")!="":
		_fail+=await preload("res://scripts/tests/tokyo_fixed_atlas_review.gd").run(battle,map,_output)
	if OS.get_environment("AGL_TOKYO_GAMEPLAY_REVIEW") == "1":
		var review_script: Script = load("res://scripts/tests/tokyo_gameplay_review.gd")
		if review_script == null or not review_script.can_instantiate():
			_fail += 1
		else:
			_fail += await review_script.new().run(battle, map)
	var map_ref: WeakRef = weakref(map)
	var session_ref: WeakRef = weakref(session)
	if OS.get_environment("AGL_TOKYO_LOW_WALL_MANIFEST") != "":
		for node: MeshInstance3D in map._low_wall_nodes.values():
			if node.mesh != null:
				low_wall_refs.append(weakref(node.mesh))
		record["low_wall_final"] = map.debug_state()
		_fail += int(low_wall_refs.is_empty())
	if fixed_texture_ref!=null:
		record["fixed_atlas_final"]=map._fixed_atlas.stats.duplicate(true)
		_fail+=int(fixed_texture_ref.get_ref()!=map._fixed_atlas._texture or int(map._fixed_atlas.stats.applications)<1 or not map._fixed_atlas.warm_ready())
		var members: Array[RefCounted] = map._fixed_atlas.members()
		var same_all := members.size()==fixed_texture_refs.size()
		for index in mini(members.size(),fixed_texture_refs.size()):
			same_all=same_all and fixed_texture_refs[index].get_ref()==members[index]._texture
		record["fixed_all_same_textures"]=same_all
		_fail+=int(not same_all)
	tree.change_scene_to_file("res://scenes/main_menu.tscn")
	for frame in 6:
		await tree.process_frame
	_fail += int(map_ref.get_ref() != null or session_ref.get_ref() != null)
	record["released_after_menu"] = map_ref.get_ref() == null and session_ref.get_ref() == null
	if not low_wall_refs.is_empty():
		var released := true
		for reference: WeakRef in low_wall_refs:
			released = released and reference.get_ref() == null
		record["low_walls_released_after_menu"] = released
		_fail += int(not released)
	if fixed_texture_ref!=null:
		record["fixed_atlas_released_after_menu"]=fixed_texture_ref.get_ref()==null
		_fail+=int(fixed_texture_ref.get_ref()!=null)
		var released_all := true
		for reference: WeakRef in fixed_texture_refs:
			released_all=released_all and reference.get_ref()==null
		record["fixed_all_released_after_menu"]=released_all
		_fail+=int(not released_all)
	if ao_texture_ref != null:
		_fail += int(ao_texture_ref.get_ref() != null)
		record["ao_released_after_menu"] = ao_texture_ref.get_ref() == null
	record["fail"] = _fail
	if not shore_mesh_refs.is_empty():
		var released := true
		for index in shore_mesh_refs.size():
			if shore_mesh_refs[index].get_ref()!=null:
				print("[R99 retained shoreline] index=",index)
				released = false
		record["shoreline_released_after_menu"] = released
		_fail += int(not released)
		record["fail"] = _fail
	var file := FileAccess.open(_output.path_join("tokyo_r48_route.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	print("[Tokyo preload route] same instance=", record.same_overlay, " viewport=", record.same_viewport,
		" warm_draws=", record.get("rendered_frames", 0), " fail=", _fail)
	tree.quit(1 if _fail else 0)


func _native_capture(map: Node, name_value: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var picture: Image = map._viewport.get_texture().get_image()
	var nonempty := false
	for y in range(0, picture.get_height(), 16):
		for x in range(0, picture.get_width(), 16):
			nonempty = nonempty or picture.get_pixel(x, y).a > 0.0
	_fail += int(not nonempty or picture.save_png(_output.path_join(name_value)) != OK)


func _capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(_output.path_join(name_value))
	_fail += int(result != OK)
