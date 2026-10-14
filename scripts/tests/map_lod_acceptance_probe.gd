extends RefCounted
## 正式菜单场景上的边缘/快滚检查；截屏和状态回放不冒充战斗性能。
const SITES := [Vector2(0.5, 0), Vector2(1, 0.5), Vector2(0.5, 1), Vector2(0, 0.5),
	Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
var failures := 0
var samples := 0
var missing_frames := 0
var peak_planes := 0
var screenshots: Array[String] = []


func run(mode: Node, kind: String) -> int:
	var tree := mode.get_tree()
	var root := mode.get_viewport()
	var original_size := DisplayServer.window_get_size()
	var camera: Camera2D = mode.camera
	var original_position := camera.position
	var original_zoom := camera.zoom
	var original_rotation := camera.rotation
	var original_ignore := camera.ignore_rotation
	var original_follow: bool = mode._camera_ctrl.follow_enabled
	mode._camera_ctrl.follow_enabled = false
	camera.ignore_rotation = false
	var output := OS.get_environment("AGL_MAP_LOD_AUDIT_OUT")
	if output.is_empty():
		output = "res://bench/results/map_lod_" + kind
	DirAccess.make_dir_recursive_absolute(output)
	var raster: RasterBasemapRenderer = mode._map_features._raster_basemap
	var ground: Node3D = mode._map_features._ocean_volume._ocean_ground if kind == "ocean" else mode._desert_volume_renderer._satellite_ground
	var bounds: Rect2 = mode._map_boundary.get_camera_bounds()
	var terrain_bounds: Rect2 = ground._archive.terrain_bounds if kind == "ocean" else raster._world_rect
	if not terrain_bounds.encloses(bounds):
		failures += 1
	for index in 40:
		var size := Vector2i(1600, 900) if index < 32 else (Vector2i(900, 1200) if index < 36 else Vector2i(2100, 900))
		DisplayServer.window_set_size(size)
		await tree.process_frame
		var site: Vector2 = SITES[index % 8] if index < 32 else SITES[4 + index % 4]
		var zoom_value: float = [0.20, 0.26, 0.65, 1.30][index / 8] if index < 32 else 0.20
		camera.rotation = deg_to_rad(14.0 if index % 2 else -14.0)
		_place(mode, bounds, site, zoom_value)
		await tree.create_timer(1.4, true, false, true).timeout
		await RenderingServer.frame_post_draw
		_sample(mode, ground, raster, kind)
		var path := output.path_join("edge_%02d.png" % index)
		if root.get_texture().get_image().save_png(path) != OK:
			failures += 1
		screenshots.append(path)
	# 实际滚轮事件与边缘平移；48秒、每50ms一次，共960次输入。
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var started := Time.get_ticks_msec()
	var next_input := 0
	var inputs := 0
	var fast_zoom_min := INF
	var fast_zoom_max := 0.0
	var paused_frames := 0
	while Time.get_ticks_msec() - started < 48000:
		await RenderingServer.frame_post_draw
		_sample(mode, ground, raster, kind)
		fast_zoom_min = minf(fast_zoom_min, camera.zoom.x)
		fast_zoom_max = maxf(fast_zoom_max, camera.zoom.x)
		paused_frames += int(tree.paused)
		var elapsed := Time.get_ticks_msec() - started
		var site_index := mini(7, elapsed / 6000)
		var site: Vector2 = SITES[site_index]
		camera.rotation = deg_to_rad(sin(elapsed * 0.001) * 14.0)
		_place(mode, bounds, site, camera.zoom.x, false)
		if elapsed >= next_input:
			var event := InputEventMouseButton.new()
			event.position = root.get_visible_rect().size * 0.5
			event.button_index = MOUSE_BUTTON_WHEEL_UP if (elapsed / 1500) % 2 == 0 else MOUSE_BUTTON_WHEEL_DOWN
			event.pressed = true
			Input.parse_input_event(event)
			var released := event.duplicate() as InputEventMouseButton
			released.pressed = false
			Input.parse_input_event(released)
			inputs += 1
			next_input = elapsed + 50
	await tree.create_timer(1.5, true, false, true).timeout
	await RenderingServer.frame_post_draw
	_sample(mode, ground, raster, kind)
	if fast_zoom_min > 0.30 or fast_zoom_max < 2.0 or paused_frames > 0 or inputs < 800:
		failures += 1
	var report := {"map": kind, "failures": failures, "samples": samples,
		"fast_zoom_min": fast_zoom_min, "fast_zoom_max": fast_zoom_max, "paused_frames": paused_frames,
		"missing_bridge_frames": missing_frames, "peak_planes": peak_planes, "edge_views": screenshots,
		"input_events": inputs, "raster": raster.debug_state(), "ground": ground.debug_state(),
		"proof": "formal_menu_edge_captures_and_live_bridge_state_not_combat_performance"}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	DisplayServer.window_set_size(original_size)
	camera.position = original_position
	camera.zoom = original_zoom
	camera.rotation = original_rotation
	camera.ignore_rotation = original_ignore
	mode._camera_ctrl.target_zoom = original_zoom.x
	mode._camera_ctrl.follow_enabled = original_follow
	camera.force_update_scroll()
	print("[Map LOD acceptance] map=", kind, " failures=", failures, " missing_frames=", missing_frames, " inputs=", inputs)
	return failures


func _place(mode: Node, bounds: Rect2, site: Vector2, zoom_value: float, set_zoom: bool = true) -> void:
	var camera: Camera2D = mode.camera
	if set_zoom:
		mode._camera_ctrl.target_zoom = zoom_value
		camera.zoom = Vector2.ONE * zoom_value
	var half: Vector2 = mode.get_viewport().get_visible_rect().size / camera.zoom / 2.0
	var c := absf(cos(camera.rotation))
	var s := absf(sin(camera.rotation))
	var extent := Vector2(c * half.x + s * half.y, s * half.x + c * half.y)
	camera.position = bounds.position + extent + site * (bounds.size - 2.0 * extent)
	camera.force_update_scroll()


func _sample(mode: Node, ground: Node3D, raster: RasterBasemapRenderer, kind: String) -> void:
	samples += 1
	peak_planes = maxi(peak_planes, ground._planes.size())
	var missing := false
	if kind == "ocean":
		missing = not mode._map_features._ocean_volume.debug_state().active
		for record: Dictionary in raster.presentation_tiles():
			var sprite: Variant = record.sprite.get_ref()
			if typeof(sprite) != TYPE_OBJECT or not is_instance_valid(sprite):
				continue
			var layer: Variant = record.layer.get_ref() if record.layer != null else null
			if not sprite.visible or (layer != null and not layer.visible):
				continue
			var identity: int = sprite.get_instance_id()
			if not ground._planes.has(identity):
				missing = true
				continue
			var entry: Dictionary = ground._planes[identity]
			missing = missing or not entry.node.visible or entry.material.get_shader_parameter("map_texture") != sprite.texture
			var priority := -100 if layer == null else (-80 if layer.z_index == 2 else -90)
			missing = missing or entry.material.render_priority != priority
	else:
		missing = ground._planes.size() != 1 or not ground._tactical_style or mode._map_features.visible
		for entry: Dictionary in ground._planes.values():
			missing = missing or not entry.node.visible or entry.alpha != 1.0
	if missing or ground._planes.size() > 17:
		missing_frames += 1
		failures += 1
