extends "res://scripts/tests/volume_combat_smoke.gd"
## 独立 root 验证器跨过真实 F8/退出；不注入手动战局、不代替完整局或性能门。


func run(mode: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tree := get_tree()
	await tree.create_timer(1.0, true, false, true).timeout
	_check(not mode._bench_mode and not mode._boss_debug_mode and not mode._map_preview_only,
		"real desert gameplay, no benchmark AI or preview-only mode")
	_check(mode._aircraft_volume_overlay == null,
		"experimental desert owns the sole aircraft volume renderer")
	_check(mode._map_id == "desert_railway_preview" and mode._ugc_doc != null,
		"desert MapDocument is actual gameplay authority")
	_check(mode._zone_data != null and mode._zone_mission != null and mode._desert_front != null,
		"zone missions and real ground fronts initialized")
	_check(mode._desert_front.live_ground_counts() == Vector2i(3, 3), "initial ground battle remains 3v3")
	_check(mode._ugc_doc.airports.size() == 3 and mode._ugc_doc.railways.size() == 1,
		"three airports and source railway retained")
	_check(not mode._map_features.visible and not mode._building_renderer.visible,
		"replaced flat map and fake buildings hidden")
	_check(mode.volume_probe._map_triangles > 7757 and mode.volume_probe._root_map.get_child_count() == 8,
		"detailed 3D map, one crisp route batch and three urban districts actually attached")
	_check(is_instance_valid(mode.volume_probe._satellite_ground)
		and mode.volume_probe._satellite_ground.debug_state().planes > 1,
		"real gameplay shares resident satellite detail textures")
	_check(mode.volume_probe._satellite_ground.debug_state().relief
		and mode.volume_probe._satellite_ground.debug_state().vegetation == 1200
		and mode.volume_probe._satellite_ground.debug_state().outcrops == 360,
		"real gameplay includes source relief, scrub and raised rock outcrops")
	_check(mode.volume_probe._satellite_ground.debug_state().prebuilt_terrain
		and mode.volume_probe._satellite_ground.debug_state().archive_misses == 0,
		"real gameplay uses current prebuilt geometry without synchronous fallback")
	_check(mode.game_time > 0.0 and not tree.paused, "normal mission clock runs")
	var screen: Vector2 = get_viewport().get_visible_rect().size * Vector2(0.30, 0.40)
	var world: Vector2 = mode._camera_ctrl.screen_to_world(screen)
	_mouse(MOUSE_BUTTON_LEFT, screen, true)
	_mouse(MOUSE_BUTTON_LEFT, screen, false)
	_check(mode.player_aircraft.target_position.distance_to(world) < 0.1, "tilted view click preserves ground coordinates")
	_key(KEY_TAB)
	await tree.create_timer(0.4, true, false, true).timeout
	_check(mode._tactical_map.is_open() and tree.paused, "Tab opens real tactical map and pauses")
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://bench/results/volume_desert_tab.png") == OK, "tactical map captured")
	_key(KEY_TAB)
	await tree.create_timer(0.4, true, false, true).timeout
	_check(not mode._tactical_map.is_open() and not tree.paused, "Tab restores real combat")
	# 三机场与工业区采样使用真正 Camera2D；仅验证器移动镜头，不传送演员或改变模拟。
	mode._camera_ctrl.follow_enabled = false
	var points := [Vector2(4800, 400), Vector2(8672, 4318), Vector2(-8500, -1500), Vector2(-3000, 12000)]
	for region: PackedVector2Array in mode._ugc_doc.layer_polygons.urban:
		var center := Vector2.ZERO
		for point in region:
			center += point / float(region.size())
		points.append(center)
	points.append_array([Vector2(11227, 43), Vector2(4413, -1335), Vector2(2400, 1500),
		Vector2(-11000, -10500), Vector2(-6359.84, -15465.87)])
	for i in points.size():
		mode.camera.global_position = points[i]
		mode._camera_ctrl.target_zoom = 0.65
		mode.camera.zoom = Vector2.ONE * 0.65
		await tree.create_timer(1.0, true, false, true).timeout
		await RenderingServer.frame_post_draw
		_check(get_viewport().get_texture().get_image().save_png("res://bench/results/volume_desert_area_%d.png" % i) == OK, "actual desert camera area %d captured" % i)
	_check(mode.volume_probe.max_projection_error_px < 0.1, "actual actor anchors and UI remain aligned")
	_check(mode.volume_probe._satellite_ground.debug_state().archive_misses == 0,
		"all twelve real camera locations retain exact cached terrain bindings")
	print(mode.volume_probe.summary())
	print("[Volume satellite runtime] ", mode.volume_probe._satellite_ground.debug_state(),
		" owner=", mode._map_features._raster_basemap.debug_state())
	var previous: WeakRef = weakref(mode)
	_key(KEY_F8)
	if not await _wait_for_scene_release(previous):
		_check(false, "desert F8 releases scene within six seconds")
		tree.quit(1)
		return
	await tree.process_frame
	mode = tree.current_scene
	_check(mode.scene_file_path == "res://scenes/tests/volume_3d_desert.tscn", "F8 retains 3D desert entry")
	_check(mode._map_id == "desert_railway_preview" and mode._desert_front != null
		and not mode._map_preview_only and is_instance_valid(mode.volume_probe), "F8 rebuilds gameplay and renderer together")
	_check(mode._aircraft_volume_overlay == null,
		"F8 keeps the experimental probe as the sole aircraft volume renderer")
	var restarted: WeakRef = weakref(mode)
	mode._quit_to_main_menu()
	_check(await _wait_for_scene_release(restarted), "quit releases desert and 3D bindings")
	await tree.process_frame
	_check(tree.current_scene.scene_file_path == "res://scenes/main_menu.tscn" and not tree.paused,
		"quit restores unpaused main menu")
	print("[Volume desert smoke] pass=%d fail=%d; entry/input/lifecycle only, NOT full run or FPS acceptance" % [_pass, _fail])
	tree.quit(0 if _fail == 0 else 1)
