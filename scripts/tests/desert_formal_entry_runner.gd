extends Node
## 只在隔离存档运行：通过真实菜单回调进入正式场景，不注入实验派生场景。
const MAIN := "res://scenes/main_menu.tscn"
const MAP_SELECT := "res://scenes/survivor_map_select.tscn"
const AIR_SELECT := "res://scenes/survivor_select.tscn"
const GAME := "res://scenes/survivor_mode.tscn"
var _pass := 0
var _fail := 0
var _results := PackedStringArray()
var _loading_captured := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	var user_path := OS.get_user_data_dir().replace("\\", "/").to_lower()
	if not user_path.contains("/tmp/desert-volume/r53-formal-profile/"):
		push_error("formal entry test requires its isolated r53-formal-profile; refusing career writes")
		tree.quit(1)
		return
	# 只让测试驱动存活；后续所有场景切换仍由正常菜单/退出回调执行。
	tree.current_scene = null
	for key in ["bench_mode", "bench_scenario", "bench_duration", "external_volume_experiment"]:
		if tree.has_meta(key):
			tree.remove_meta(key)
	# 仅在上面已验证的隔离存档准备第二架起手机，仍经正式商店购买/选机门控。
	if not MetaShop.is_owned(MetaShop.ITEM_MIRAGE3):
		MeritLedger.award(MetaShop.get_price(MetaShop.ITEM_MIRAGE3), "isolated formal map fixture")
		_check(MetaShop.buy(MetaShop.ITEM_MIRAGE3), "isolated fixture purchases its second starter")
	tree.change_scene_to_file(MAIN)
	for round_index in 2:
		var before_runs := CareerArchive.get_runs_started()
		if not await _wait_scene(MAIN):
			return
		tree.current_scene._on_survivor_pressed()
		if not await _wait_scene(MAP_SELECT):
			return
		var menu: Node = tree.current_scene
		var desert_index := -1
		for index in menu.MAP_LIST.size():
			if menu.MAP_LIST[index].id == "desert_railway_preview":
				desert_index = index
		_check(desert_index >= 0 and not menu.MAP_LIST[desert_index].preview_only,
			"normal map selection exposes a playable desert")
		if desert_index < 0:
			tree.quit(1)
			return
		menu._on_map_selected(desert_index)
		menu = null
		if not await _wait_scene(AIR_SELECT):
			return
		var picker: Node = tree.current_scene
		# 两次选不同的正常起手机；不能由地图入口偷换成测试用F-15C。
		var selected := 0 if round_index == 0 else 3
		_check(not picker._list[selected].get("locked", true), "selected starter passes actual career unlock gate")
		var selected_path: String = picker._list[selected].resource
		picker._on_aircraft_selected(selected)
		picker = null
		if not await _wait_scene(GAME):
			return
		await tree.create_timer(2.0, true, false, true).timeout
		# 初始化可能跨过墙钟计时；两帧预绘制及queue_free必须按真实绘制/释放屏障验收。
		for frame in 2:
			await RenderingServer.frame_post_draw
			await tree.process_frame
		var mode: Node = tree.current_scene
		if round_index == 0 and OS.get_environment("AGL_MAP_LOD_AUDIT") == "1":
			_fail += await preload("res://scripts/tests/map_lod_acceptance_probe.gd").new().run(mode, "desert")
		_check(mode.get_script().resource_path == "res://scripts/survivor/survivor_mode.gd"
			and mode.archive_enabled() and not mode._bench_mode and not mode._boss_debug_mode,
			"actual formal Survivor keeps normal career and gameplay authority")
		_check(mode._player_profile_path == selected_path, "formal map preserves selected aircraft")
		_check(CareerArchive.get_runs_started() == before_runs + 1,
			"formal entry records exactly one real career start in the isolated profile")
		_check(is_instance_valid(mode._desert_volume_renderer) and mode._aircraft_volume_overlay == null,
			"formal desert automatically owns one combined renderer without F6")
		if OS.get_environment("AGL_DESERT_STYLE") in ["", "tactical"]:
			var preloaded: Dictionary = mode._desert_volume_renderer.get_meta("desert_preload", {})
			_check(preloaded.get("reused", false) and int(preloaded.get("rendered_frames", 0)) >= 4,
				"actual loading screen hands over the same GPU-warmed map: " + JSON.stringify(preloaded))
			_check(tree.get_nodes_in_group(&"desert_map_preload").is_empty(), "formal entry retires temporary preload owner")
		_check(mode._zone_mission != null and mode._desert_front != null and mode._zone_data != null,
			"formal desert retains missions and ground fronts")
		_check(not mode._map_features.visible and not mode._building_renderer.visible,
			"old map visuals are hidden without deleting gameplay owners")
		_check(mode._desert_volume_renderer._satellite_ground.debug_state().archive_misses == 0,
			"formal desert uses prebuilt terrain and shared tile owner")
		_check(mode._desert_volume_renderer._satellite_ground._source.get_ref() == mode._map_features._raster_basemap,
			"formal 3D map borrows the actual initialized MapFeatureRenderer owner, not a lab fallback")
		if OS.get_environment("AGL_DESERT_BASEMAP") == "sentinel":
			_check(mode._desert_volume_renderer._satellite_ground.debug_state().source_kind == "satellite",
				"formal menu chain actually selected the satellite candidate")
		if OS.get_environment("AGL_DESERT_STYLE") in ["", "tactical"]:
			var ground: Node3D = mode._desert_volume_renderer._satellite_ground
			var style_state: Dictionary = ground.debug_state()
			_check(style_state.visual_style == "tactical" and style_state.surface_mode == "native_full"
				and style_state.planes == 1,
				"normal menu chain defaults to the full native tactical terrain without a style switch")
			var terrain_palette_ok: bool = ground._planes.size() == 1
			for plane: Dictionary in ground._planes.values():
				_check(RenderingServer.shader_get_parameter_default(plane.material.shader.get_rid(), "relief_contrast") == 1.5
					and plane.material.get_shader_parameter("relief_contrast") == null,
					"normal menu and preload handoff retain the hard-relief default without a test override")
				for definition: Array in [["sand_color", [0.68,0.63,0.53]], ["rock_color", [0.77,0.71,0.60]]]:
					var value: Variant = RenderingServer.shader_get_parameter_default(plane.material.shader.get_rid(), definition[0])
					var override: Variant = plane.material.get_shader_parameter(definition[0])
					terrain_palette_ok = terrain_palette_ok and typeof(value) in [TYPE_COLOR, TYPE_VECTOR3]
					if typeof(value) in [TYPE_COLOR, TYPE_VECTOR3]:
						for component in 3:
							terrain_palette_ok = terrain_palette_ok and absf(value[component] - definition[1][component]) < 0.0001
					terrain_palette_ok = terrain_palette_ok and (override == null or override == value)
			_check(terrain_palette_ok, "actual GL terrain uses beige sand and pale sandstone without an override")
			var cover_palette_ok := true
			var cover_materials := 0
			for part: MeshInstance3D in ground._details.get_children():
				if not String(part.name).begins_with("Scrub_"):
					continue
				cover_materials += 1
				var material := part.material_override as ShaderMaterial
				for definition: Array in [["sand_color", [0.58,0.55,0.46]], ["rock_color", [0.52,0.48,0.40]]]:
					var value: Variant = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), definition[0])
					cover_palette_ok = cover_palette_ok and typeof(value) in [TYPE_COLOR, TYPE_VECTOR3]
					if typeof(value) in [TYPE_COLOR, TYPE_VECTOR3]:
						for component in 3:
							cover_palette_ok = cover_palette_ok and absf(value[component] - definition[1][component]) < 0.0001
			_check(cover_palette_ok and cover_materials > 0, "actual GL ground cover uses the subdued dry-earth palette")
			var context_palette_ok := true
			var context_cells := 0
			for part: MeshInstance3D in ground._details.get_children():
				if not part.has_meta("context_near_mesh"):
					continue
				context_cells += 1
				var colors: PackedColorArray = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
				var roof_present := false
				for color: Color in colors:
					context_palette_ok = context_palette_ok and color in [Color("b9b1a0"), Color("797466"), Color("73786f")]
					roof_present = roof_present or color == Color("b9b1a0")
				context_palette_ok = context_palette_ok and roof_present and part.material_override.get_shader_parameter("native_palette") == true
			_check(context_palette_ok and context_cells == 4, "normal menu actually renders all four subdued background districts without recoloring roads")
			_check(style_state.outcrops == 0 and style_state.vegetation == 1200,
				"normal menu selects low-density native decoration and retains every vegetation cluster")
			_check(style_state.archive_path == "res://resources/maps/desert_volume_terrain_tactical.res"
				and not ResourceLoader.has_cached("res://resources/maps/desert_volume_terrain.res"),
				"normal menu loads only the selected native archive, never the source fallback")
			_check(style_state.watercourses == 7 and style_state.retained_shorelines == 217,
				"normal menu loads reviewed western and northeast rivers and preserves unmatched shorelines")
			var river_material := ground._details.get_node("Source_Water_Contours").material_override as ShaderMaterial
			_check(river_material.get_shader_parameter("pixel_width_enabled") == true
				and is_equal_approx(float(RenderingServer.shader_get_parameter_default(river_material.shader.get_rid(), "minimum_width_px")),1.25)
				and not river_material.shader.code.contains("depth_test_disabled"),
				"normal native archive enables bounded river pixel coverage and preserves depth testing")
			var coverage_override: Variant = river_material.get_shader_parameter("watercourse_coverage_enabled")
			_check(RenderingServer.shader_get_parameter_default(river_material.shader.get_rid(), "watercourse_coverage_enabled") == true
				and (coverage_override == null or coverage_override == true),
				"normal menu uses narrow watercourse pixel coverage without a QA-only override")
			_check(style_state.material_warmup.get("rendered", false) and ground.get_node_or_null("MaterialWarmup") == null,
				"default formal material really warmed and released its private viewport: " + JSON.stringify(style_state.material_warmup))
		else:
			var state: Dictionary = mode._desert_volume_renderer._satellite_ground.debug_state()
			_check(state.archive_path == "res://resources/maps/desert_volume_terrain.res"
				and not ResourceLoader.has_cached("res://resources/maps/desert_volume_terrain_tactical.res")
				and state.outcrops == 360,
				"explicit source fallback loads only its own archive and retains all original rocks")
			var source_line := mode._desert_volume_renderer._satellite_ground._details.get_node("Source_Water_Contours").material_override as ShaderMaterial
			_check(source_line.get_shader_parameter("pixel_width_enabled") == false,
				"explicit source fallback does not enable native river screen expansion")
		var screen := get_viewport().get_visible_rect().size * Vector2(0.3, 0.4)
		var world: Vector2 = mode._camera_ctrl.screen_to_world(screen)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = screen
		click.global_position = screen
		click.pressed = true
		# 已是视口坐标，禁止再按宿主窗口拉伸；与已有手动场景回归一致。
		get_viewport().push_input(click, true)
		click = click.duplicate()
		click.pressed = false
		get_viewport().push_input(click, true)
		_check(mode.player_aircraft.target_position.distance_to(world) < 0.1,
			"normal input preserves tilted ground click coordinate")
		_key(KEY_TAB)
		await tree.create_timer(0.3, true, false, true).timeout
		_check(mode._tactical_map.is_open() and tree.paused, "formal Tab opens map and pauses")
		if OS.get_environment("AGL_DESERT_BASEMAP") == "sentinel":
			var owner: Variant = mode._desert_volume_renderer._satellite_ground._source.get_ref()
			_check(mode._tactical_map._mm_raster_tex == owner._strategic_sprite.texture,
				"formal Tab borrows the same satellite Strategic texture")
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://bench/results/desert_formal_satellite_tab_%d.png" % round_index)
		_key(KEY_TAB)
		await tree.create_timer(0.3, true, false, true).timeout
		_check(not mode._tactical_map.is_open() and not tree.paused, "formal Tab resumes gameplay")
		var map_renderer: Node3D = mode._desert_volume_renderer
		var was_enabled: bool = map_renderer.bodies_enabled
		_key(KEY_F11, true)
		await tree.process_frame
		_check(map_renderer.bodies_enabled != was_enabled and is_instance_valid(map_renderer._root_map)
			and not mode._map_features.visible, "Shift+F11 toggles aircraft without removing the formal desert")
		_key(KEY_F11, true)
		await tree.process_frame
		_check(map_renderer.bodies_enabled == was_enabled, "Shift+F11 restores aircraft presentation")
		map_renderer = null
		mode._camera_ctrl.follow_enabled = false
		mode.camera.position = Vector2(8672, 4318) if round_index == 0 else Vector2(4800, 400)
		mode._camera_ctrl.target_zoom = 0.65
		mode.camera.zoom = Vector2.ONE * 0.65
		await tree.create_timer(1.0, true, false, true).timeout
		await RenderingServer.frame_post_draw
		_check(get_viewport().get_texture().get_image().save_png(
			"res://bench/results/desert_formal_entry_%d.png" % round_index) == OK, "formal gameplay captured")
		var canvas: Transform2D = mode.get_viewport().canvas_transform
		var capture_meta := FileAccess.open("res://bench/results/desert_formal_entry_%d.json" % round_index, FileAccess.WRITE)
		if capture_meta != null:
			capture_meta.store_string(JSON.stringify({"canvas": [canvas.x.x, canvas.x.y, canvas.y.x, canvas.y.y,
				canvas.origin.x, canvas.origin.y], "actual_zoom": [mode.camera.zoom.x, mode.camera.zoom.y],
				"viewport_size": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
				"map_state": mode._desert_volume_renderer._satellite_ground.debug_state()}))
			capture_meta.close()
		if round_index == 0 and OS.get_environment("AGL_DESERT_STYLE") in ["", "tactical"]:
			for area: Dictionary in [{"name": "a", "point": Vector2(-5467.63235,-3718.11015)}, {"name": "b", "point": Vector2(-14092.29482,-6394.81581)}, {"name": "c", "point": Vector2(1670.01935,-13532.69758)}]:
				for zoom_value: float in [0.26,0.65]:
					mode.camera.position = area.point
					mode._camera_ctrl.target_zoom = zoom_value
					mode.camera.zoom = Vector2.ONE*zoom_value
					await tree.create_timer(1.2,true,false,true).timeout
					await RenderingServer.frame_post_draw
					_check(get_viewport().get_texture().get_image().save_png("res://bench/results/desert_formal_mountain_%s_%d.png" % [area.name,int(zoom_value*100)]) == OK,
						"formal mountain terrain captured without decorative scatter rocks")
					print("[Desert formal mountain] area=",area.name," actual_position=",mode.camera.position," zoom=",mode.camera.zoom,
						" ground=",mode._desert_volume_renderer._satellite_ground.debug_state())
		if round_index == 0 and preload("res://scripts/experiments/volume_desert_tactical_context.gd").is_enabled("desert"):
			for river_area: Dictionary in [{"name":"bend","point":Vector2(-10100,10100)},
				{"name":"upstream","point":Vector2(-14914.4116,9001.04241)},
				{"name":"junction","point":Vector2(-3602.54109,9600.04538)},
				{"name":"northeast","point":Vector2(5260,-13800)},
				{"name":"ridge_creek","point":Vector2(3500,-12300)}]:
				for river_zoom: float in [0.13,1.30]:
					mode.camera.position = river_area.point
					mode.camera.zoom = Vector2.ONE*river_zoom
					mode._camera_ctrl.target_zoom = river_zoom
					mode._camera_ctrl._base_zoom = river_zoom
					await tree.create_timer(1.2,true,false,true).timeout
					await RenderingServer.frame_post_draw
					_check(mode.camera.zoom.is_equal_approx(Vector2.ONE*river_zoom)
						and get_viewport().get_texture().get_image().save_png("res://bench/results/desert_formal_water_%s_%d.png" % [river_area.name,int(river_zoom*100)]) == OK,
						"normal menu river coverage captured at actual near/far game zoom")
			var road_factory := preload("res://scripts/experiments/volume_map_factory.gd")
			var road_doc := MapDocument.load_from("res://resources/maps/desert_railway_preview.aglmap")
			var expected_road := road_factory.build(road_doc, true, true)
			var actual_road: MeshInstance3D = mode._desert_volume_renderer._root_map.get_node("CrispRouteNetwork")
			var route_material := actual_road.material_override as ShaderMaterial
			_check(route_material.get_shader_parameter("route_coverage_enabled") == true
				and RenderingServer.shader_get_parameter_default(route_material.shader.get_rid(), "route_coverage_enabled") == false,
				"normal menu enables rotation-neutral route coverage explicitly; shared shader fallback stays off")
			_check(expected_road.road_join_count == 2 and expected_road.crossing_surfaces.size() == 8 and actual_road.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array()
				== expected_road.line_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array(), "normal menu owns corrected joins and all four road-rail crossing surfaces in the same mesh")
			for road_area: Dictionary in [{"name": "west", "point": Vector2(-10100, 10100)}, {"name": "southwest", "point": Vector2(-11200, 9000)}]:
				mode.camera.position = road_area.point
				mode._camera_ctrl.target_zoom = 0.65
				mode._camera_ctrl._base_zoom = 0.65
				await tree.create_timer(1.2, true, false, true).timeout
				await RenderingServer.frame_post_draw
				var road_path := "res://bench/results/desert_formal_road_join_" + String(road_area.name)
				_check(get_viewport().get_texture().get_image().save_png(road_path + ".png") == OK, "normal gameplay road join captured: " + String(road_area.name))
				var road_meta := FileAccess.open(road_path + ".json", FileAccess.WRITE)
				if road_meta != null:
					road_meta.store_string(JSON.stringify({"join_count": expected_road.road_join_count,
						"camera": [mode.camera.position.x, mode.camera.position.y], "zoom": [mode.camera.zoom.x, mode.camera.zoom.y],
						"map_state": mode._desert_volume_renderer._satellite_ground.debug_state()}))
					road_meta.close()
		if round_index == 0 and preload("res://scripts/experiments/volume_desert_tactical_context.gd").is_enabled("desert"):
			for area: Dictionary in [{"name":"double", "point":Vector2(615.01011,-3069.83700)},
				{"name":"west", "point":Vector2(-1508.94404,-5111.29061)},
				{"name":"east", "point":Vector2(3410.22448,-1800.78650)}]:
				for zoom_value: float in [0.26,1.3]:
					mode.camera.position = area.point
					mode.camera.zoom = Vector2.ONE*zoom_value
					mode._camera_ctrl.target_zoom = zoom_value
					mode._camera_ctrl._base_zoom = zoom_value
					await tree.create_timer(1.2,true,false,true).timeout
					await RenderingServer.frame_post_draw
					_check(mode.camera.position.distance_to(area.point) < 0.1 and mode.camera.zoom.is_equal_approx(Vector2.ONE*zoom_value)
						and get_viewport().get_texture().get_image().save_png("res://bench/results/desert_formal_crossing_%s_%d.png" % [area.name,int(zoom_value*100)]) == OK,
						"normal menu crossing captured at actual requested position and zoom: " + String(area.name))
			var airport_doc := MapDocument.load_from("res://resources/maps/desert_railway_preview.aglmap")
			var airport_factory := preload("res://scripts/experiments/volume_map_factory.gd")
			for airport_index in airport_doc.airports.size():
				var airport_frame: Dictionary = airport_factory.Buildings.frame(airport_factory.airport_polygon(airport_doc.airports[airport_index]))
				mode.camera.position = airport_frame.center
				mode.camera.zoom = Vector2.ONE * 1.3
				mode._camera_ctrl.target_zoom = 1.3
				mode._camera_ctrl._base_zoom = 1.3
				await tree.create_timer(1.2,true,false,true).timeout
				await RenderingServer.frame_post_draw
				_check(mode.camera.position.distance_to(airport_frame.center) < 0.1 and mode.camera.zoom.is_equal_approx(Vector2.ONE*1.3)
					and get_viewport().get_texture().get_image().save_png("res://bench/results/desert_formal_airport_lines_%d.png" % airport_index) == OK,
					"normal menu airport marking coverage captured at the source runway: %d" % airport_index)
		if round_index == 1:
			mode.camera.position = Vector2(4800, 150)
			mode._camera_ctrl.target_zoom = 1.3
			mode._camera_ctrl._base_zoom = 1.3
			await tree.create_timer(0.5, true, false, true).timeout
			await RenderingServer.frame_post_draw
			_check(get_viewport().get_texture().get_image().save_png(
				"res://bench/results/desert_formal_entry_streets_close.png") == OK, "formal source streets captured at double zoom")
			# 四区实际菜单近景；保留正常HUD/玩法，不能拿源图配准代替游戏验收。
			var regions := {"northwest": Vector2(4400, 0), "northeast": Vector2(5200, 0),
				"southwest": Vector2(4400, 800), "southeast": Vector2(5200, 800)}
			for region: String in regions:
				mode.camera.position = regions[region]
				await tree.create_timer(1.2, true, false, true).timeout
				await RenderingServer.frame_post_draw
				var capture_path := "res://bench/results/desert_formal_industrial_%s" % region
				_check(get_viewport().get_texture().get_image().save_png(capture_path + ".png") == OK,
					"formal industrial %s captured at close zoom" % region)
				var region_meta := FileAccess.open(capture_path + ".json", FileAccess.WRITE)
				if region_meta != null:
					region_meta.store_string(JSON.stringify({"region": region,
						"actual_camera": [mode.camera.position.x, mode.camera.position.y],
						"actual_zoom": [mode.camera.zoom.x, mode.camera.zoom.y],
						"map_state": mode._desert_volume_renderer._satellite_ground.debug_state()}))
					region_meta.close()
			if OS.get_environment("AGL_DESERT_BASEMAP") == "sentinel":
				# R60曾出现磁盘已替换但导入纹理仍旧；检查实际驻留像素而非仅manifest。
				var raster: Node = mode._map_features._raster_basemap
				var resident: Sprite2D = raster._sprites[&"detail"].get("r04_c05")
				_check(resident != null and resident.texture != null, "industrial repair tile is actually resident")
				if resident != null and resident.texture != null:
					var record: Dictionary = raster._records[&"detail"].get("r04_c05", {})
					var expected := Image.load_from_file(raster._tile_path(&"detail", record))
					var actual := resident.texture.get_image()
					actual.convert(Image.FORMAT_RGBA8)
					expected.convert(Image.FORMAT_RGBA8)
					_check(actual.get_size() == expected.get_size() and actual.get_data() == expected.get_data(),
						"actual resident industrial texture exactly matches current source pixels")
		var old_mode: WeakRef = weakref(mode)
		var old_renderer: WeakRef = weakref(mode._desert_volume_renderer)
		mode._quit_to_main_menu()
		mode = null
		if not await _wait_scene(MAIN):
			return
		await tree.process_frame
		_check(old_mode.get_ref() == null and old_renderer.get_ref() == null,
			"normal exit releases formal map renderer before another run")
	var result := "[Desert formal entry] pass=%d fail=%d; actual menu chain twice, not full-run/performance acceptance" % [_pass, _fail]
	print(result)
	var report := FileAccess.open("res://bench/results/desert_formal_entry.txt", FileAccess.WRITE)
	if report != null:
		report.store_string("\n".join(_results) + "\n" + result + "\n")
		report.close()
	tree.quit(0 if _fail == 0 else 1)


func _wait_scene(path: String) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 45000:
		await get_tree().process_frame
		var current: Node = get_tree().current_scene
		if path == GAME and not _loading_captured and current != null \
				and current.scene_file_path == "res://scenes/building_preloader.tscn" and current.is_node_ready():
			var session: Variant = current._volume_ref.get_ref() if current._volume_ref != null else null
			if typeof(session) == TYPE_OBJECT and is_instance_valid(session) and int(session.get("stage")) >= 2:
				_loading_captured = true
				_check(current._hint.text == tr("MAP_DESERT_RAILWAY_NAME") and current._bar.value < 100,
					"loading screen names the actual desert and waits for unfinished map work")
				get_viewport().get_texture().get_image().save_png("res://bench/results/desert_preload_loading.png")
		if current != null and current.scene_file_path == path and current.is_node_ready():
			return true
	_check(false, "timed out entering " + path)
	get_tree().quit(1)
	return false


func _key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.shift_pressed = shift
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)


func _check(ok: bool, label: String) -> void:
	_results.append(("PASS " if ok else "FAIL ") + label)
	if ok:
		_pass += 1
		print("[Desert formal] PASS ", label)
	else:
		_fail += 1
		push_error("Desert formal: " + label)
