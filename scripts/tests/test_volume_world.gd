extends RefCounted

const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Probe := preload("res://scripts/experiments/volume_world_probe.gd")
const Airframes := preload("res://scripts/experiments/volume_aircraft_catalog.gd")
const VolumeProjection := preload("res://scripts/experiments/volume_projection.gd")
const FormalOverlay := preload("res://scripts/rendering/aircraft_volume_overlay.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var warm: SubViewport = load("res://scripts/experiments/volume_material_warmup.gd").new()
	var warm_material := ShaderMaterial.new()
	warm_material.shader=Probe.AIRFRAME_FADE_SHADER
	var warm_materials: Array[ShaderMaterial] = [warm_material,warm_material,warm_material]
	warm.configure_instanced(warm_materials,Environment.new())
	_check(warm._minimum_draws==3 and warm.size==Vector2i(32,32) and warm.transparent_bg,"instanced warmup covers all three material routes")
	for index in 3:
		var instance := warm.get_node("InstancedWarmup%d" % index) as MultiMeshInstance3D
		_check(instance.multimesh.use_custom_data and instance.multimesh.use_colors and instance.multimesh.instance_count==1,
			"warmup uses real instanced color/custom-data format")
		# Dummy后端不保存实例GPU缓冲；透明值的实际提交由Visual暖绘结果验证。
		if DisplayServer.get_name()!="headless":
			_check(absf(instance.multimesh.get_instance_custom_data(0).a-0.5)<0.005,"warmup uses translucent custom alpha")
	warm.free()
	var light_lab: GDScript = load("res://scripts/experiments/volume_3d_lab.gd")
	_check(light_lab != null and light_lab.can_instantiate(), "fixed-view desert relief light comparison compiles")
	for surface_kind: String in ["ground", "opaque"]:
		var surface_material := ShaderMaterial.new()
		surface_material.shader = load("res://resources/shaders/volume_desert_tactical_%s.gdshader" % surface_kind)
		# 材质参数读取只返回覆盖值；实际 shader 默认值由 GL 固定机位入口断言。
		_check(surface_material.shader != null and surface_material.shader.code.contains(
			"volume_desert_tactical_surface.gdshaderinc"),
			"desert %s shares the relief light implementation" % surface_kind)
	var preload_script: GDScript = load("res://scripts/rendering/desert_map_preload.gd")
	_check(preload_script != null and preload_script.can_instantiate(), "desert preload implementation compiles")
	var preload_case: GDScript = load("res://scripts/tests/desert_preload_lifecycle_case.gd")
	_check(preload_case != null and preload_case.can_instantiate(), "desert preload lifecycle fixture compiles")
	var route_script: GDScript = load("res://scripts/tests/volume_desert_route.gd")
	_check(route_script != null and route_script.can_instantiate(), "natural desert route fixture compiles")
	if route_script != null and route_script.can_instantiate():
		_check(route_script.is_isolated_profile("C:/AGL/tmp/desert-volume/route-engine/godot.exe",
			"C:/AGL/tmp/desert-volume/route-engine/profile/Godot/app_userdata/AGL"), "route accepts its exact isolated profile")
		_check(not route_script.is_isolated_profile("C:/Godot/godot.exe",
			"C:/Godot/editor_data/app_userdata/AGL"), "route rejects ordinary self-contained installation")
		_check(not route_script.is_isolated_profile("C:/AGL/tmp/desert-volume/route-engine/godot.exe",
			"C:/Users/player/AppData/Roaming/Godot/app_userdata/AGL"), "route rejects regular player save")
		_check(not route_script.is_isolated_profile("C:/AGL/tmp/desert-volume/route-engine/godot.exe",
			"C:/AGL/tmp/desert-volume/route-engine/profile/Godot/app_userdata/AGL-other"), "route rejects profile prefix collision")
	var lifecycle_script: GDScript = load("res://scripts/tests/volume_world_lifecycle_case.gd")
	_check(lifecycle_script != null and lifecycle_script.can_instantiate(), "volume lifecycle fixture compiles before full regression")
	var timing := load("res://scripts/tests/volume_map_performance.gd").new() as Node
	_check(timing._timing_report() == "render_timing=off"
		and not RenderingServer.frame_post_draw.is_connected(timing._sample_render_times), "render timing defaults to no observer callback")
	_check(not timing._accept_render_frame(0) and timing._accept_render_frame(1)
		and not timing._accept_render_frame(1) and timing._accept_render_frame(2)
		and not timing._accept_render_frame(1) and timing._accept_render_frame(4)
		and timing._timing_last_frame == 4 and timing._timing_skipped_frames == 1,
		"render timing shares FPS warmup and rejects duplicate/backwards frames with explicit gap accounting")
	timing._record_render_sample(1.0, 2.0, 3.0)
	timing._record_render_sample(3.0, 0.0, 1.0)
	timing._record_render_sample(NAN, 1.0, 1.0)
	timing._record_render_sample(1.0, -1.0, 1.0)
	_check(timing._timing_count == 2 and timing._timing_gpu_nonzero == 1 and timing._timing_invalid == 2
		and timing._timing_totals == [4.0, 2.0, 4.0] and timing._timing_peaks == [3.0, 2.0, 3.0],
		"bounded render timing aggregates samples and excludes invalid values")
	timing._record_render_coverage(30, 2, 60, 4, 7)
	_check(timing._coverage_minima == [30, 2, 60, 4], "render coverage initializes minima from first actual sample")
	timing._record_render_coverage(10, 1, 20, 2, 3)
	timing._record_render_coverage(0, 0, 0, 0, 0)
	_check(timing._coverage_count == 3 and timing._coverage_visible_frames == 2 and timing._coverage_shadow_frames == 2
		and timing._coverage_totals == [40, 3, 80, 6] and timing._coverage_minima == [0, 0, 0, 0]
		and timing._coverage_maxima == [30, 2, 60, 4], "render coverage accepts pure 2D zero and aggregates actual submissions")
	timing._record_render_coverage(-1, 1, 20, 2, 3)
	timing._record_render_coverage(10, -1, 20, 2, 3)
	timing._record_render_coverage(10, 1, -1, 2, 3)
	timing._record_render_coverage(10, 1, 20, -1, 3)
	timing._record_render_coverage(10, 1, 20, 2, 2)
	timing._record_render_coverage(0, 0, 0, 0, -1)
	_check(timing._coverage_invalid == 6 and timing._coverage_count == 3
		and timing._coverage_totals == [40, 3, 80, 6], "render coverage rejects negative and stale viewport samples without polluting aggregates")
	_check(timing._coverage_report().contains("visible_primitives_avg=13.33")
		and timing._coverage_report().contains("shadow_draws_avg=2.00")
		and timing._coverage_report().contains("proof=render_lists_and_draw_submission_not_screen_presentation")
		and timing._timing_report() == "render_timing=off", "render coverage reports bounded diagnostics without enabling observer")
	timing._record_render_coverage(10, 3, 20, 0, 3)
	_check(timing._coverage_shadow_frames == 3 and timing._coverage_shadow_draw_frames == 2
		and timing._coverage_report().contains("pass_draw_attribution=raw_backend_counters"),
		"GL shadow primitives are not falsely called absent when shadow draw counter is zero")
	timing.free()
	_check(load("res://scripts/tests/test_volume_camera_sync.gd").new().run(), "camera synchronization exactness and static submission deduplication")
	_check(load("res://scripts/tests/test_volume_tile_edges.gd").new().run(), "canonical adjacent tile meshes and unchanged source UV mapping")
	_check(load("res://scripts/tests/test_volume_tile_visibility.gd").new().run(), "actual rotated viewport tile coverage")
	_check(load("res://scripts/tests/test_volume_aircraft_catalog.gd").run(), "dedicated aircraft production batch")
	_check(load("res://scripts/tests/test_volume_map_factory.gd").new().run(), "static desert production batch")
	_check(load("res://scripts/tests/test_volume_satellite_ground.gd").new().run(), "shared satellite ground contract")
	_check(load("res://scripts/tests/test_volume_desert_relief.gd").new().run(), "georeferenced relief and clean contour contract")
	_check(load("res://scripts/tests/volume_relief_stress.gd").can_instantiate(), "relief transition stress compiles")
	var stream_probe: Node = load("res://scripts/tests/volume_relief_stress.gd").new()
	# 无树夹具不执行 Lab._ready；接管其构造时节点，避免测试本身遗留孤儿 RID。
	for property: String in ["_camera", "_sun", "_goose", "_label", "_airframes", "_raster_camera", "_satellite_ground"]:
		stream_probe.add_child(stream_probe.get(property))
	_check(stream_probe._streaming_snapshot().is_empty(), "streaming snapshot fails closed before source exists")
	var stream_ground: Node3D = stream_probe._satellite_ground
	var stream_owner := RasterBasemapRenderer.new()
	stream_ground._source = weakref(stream_owner)
	stream_owner.free()
	_check(stream_probe._streaming_snapshot().is_empty(), "streaming snapshot rejects a released source before reading fields")
	stream_ground.free()
	_check(stream_probe._streaming_snapshot().is_empty(), "streaming snapshot rejects released terrain")
	stream_probe.free()
	var relief_stress: GDScript = load("res://scripts/tests/volume_relief_stress.gd")
	var disabled_diagnostic: Dictionary = relief_stress._render_diagnostic(RID(), false)
	_check(disabled_diagnostic == {"enabled": false, "scope": "latest_backend_measurement_not_stall_attribution"},
		"disabled stall timing never samples a viewport or claims synchronous attribution")
	_check(relief_stress.render_sample_valid(30, 2, 3)
		and not relief_stress.render_sample_valid(0, 2, 3)
		and not relief_stress.render_sample_valid(30, 0, 3)
		and not relief_stress.render_sample_valid(30, 2, 0)
		and not relief_stress.render_sample_valid(30, 2, 1),
		"terrain stress rejects missing 3D geometry, missing draws and stale viewport counts")
	var manual_scene: PackedScene = load("res://scenes/tests/volume_3d_combat.tscn")
	_check(manual_scene != null and manual_scene.can_instantiate(), "manual combat scene available to F6")
	var manual_script: GDScript = load("res://scripts/experiments/volume_3d_combat.gd")
	_check(manual_script != null and manual_script.can_instantiate(), "manual combat script compiles")
	var smoke_script: GDScript = load("res://scripts/tests/volume_combat_smoke.gd")
	_check(smoke_script != null and smoke_script.can_instantiate(), "manual smoke script compiles before Visual")
	var multiview_script: GDScript = load(
		"res://scripts/tests/volume_aircraft_multiview_qa_runner.gd")
	_check(multiview_script != null and multiview_script.can_instantiate(),
		"LOD0/LOD1 multiview QA runner compiles before Visual")
	_check(BenchRunner.VISUAL_TEST_SCENES.get("volume_aircraft_lod_multiview", "")
		== "res://scenes/tests/volume_aircraft_multiview_qa.tscn",
		"dedicated LOD1 multiview route is registered")
	_check(BenchRunner.VISUAL_TEST_SCENES.get("volume_aircraft_lod2_multiview", "")
		== "res://scenes/tests/volume_aircraft_multiview_qa.tscn",
		"dedicated LOD2 multiview route is registered")
	_check(FormalOverlay.FORMAL_SCENARIO == "volume_3d_formal",
		"formal Survivor renderer uses the production aircraft route")
	_check(is_equal_approx(FormalOverlay.RENDER_SCALE, 1.0),
		"formal compositor preserves native resolution; cadence and AA are tested in the real tree")
	var body_livery := Color(0.08, 0.20, 0.40, 1.0)
	var wing_livery := Color(0.88, 0.50, 0.20, 1.0)
	var livery_ratio := Probe.livery_ratio_for(body_livery, wing_livery)
	_check((Vector3(body_livery.r, body_livery.g, body_livery.b) \
		* Vector3(livery_ratio.r, livery_ratio.g, livery_ratio.b)).is_equal_approx(
		Vector3(wing_livery.r, wing_livery.g, wing_livery.b)),
		"airframe shader custom data reconstructs the optional wing livery")
	_check(Probe.livery_ratio_for(body_livery, Color.TRANSPARENT) == Color.WHITE,
		"single-color aircraft keep the existing icon-color path")
	_check(not Probe.mount_detail_mode_for(false, 20.0) \
		and Probe.mount_detail_mode_for(false, 23.0),
		"all aircraft equipment enters only when its projected span is readable")
	_check(Probe.mount_detail_mode_for(true, 19.0) \
		and not Probe.mount_detail_mode_for(true, 17.0),
		"identity-independent equipment LOD has hysteresis")
	_check(Probe.body_lod_level_for(-1, 23.0) == 0
		and Probe.body_lod_level_for(-1, 12.0) == 1
		and Probe.body_lod_level_for(-1, 7.0) == 2,
		"initial airframe route separates full, intermediate, and truly distant geometry")
	_check(Probe.body_lod_level_for(0, 19.0) == 0
		and Probe.body_lod_level_for(0, 17.0) == 1
		and Probe.body_lod_level_for(1, 23.0) == 0,
		"LOD0/LOD1 transition retains the reviewed 22/18 px hysteresis")
	_check(Probe.body_lod_level_for(1, 9.0) == 1
		and Probe.body_lod_level_for(1, 7.0) == 2
		and Probe.body_lod_level_for(2, 9.0) == 2
		and Probe.body_lod_level_for(2, 12.0) == 1,
		"triangle-like LOD2 is confined below 8 px with an 11 px return threshold")
	var every_airframe_has_visual_lod := true
	for key in Airframes.supported_keys():
		every_airframe_has_visual_lod = every_airframe_has_visual_lod \
			and Airframes.supports_body_lod(key)
	_check(every_airframe_has_visual_lod,
		"every produced aircraft identity participates in visual geometry LOD")
	_check(Airframes.build_runtime_lod("ah64", Airframes.BODY_LOD_LOW) != null,
		"AH-64 has a single-mesh far silhouette instead of dynamic rotor submissions")
	_check(Airframes.build_runtime_lod("ah64", Airframes.BODY_LOD_MEDIUM) != null,
		"AH-64 has an intermediate structural mesh between full and far geometry")
	_check(Airframes.build_runtime_lod("ch47", Airframes.BODY_LOD_LOW) != null,
		"CH-47 has a single-mesh far silhouette instead of dynamic rotor submissions")
	_check(Airframes.build_runtime_lod("mother_goose", Airframes.BODY_LOD_LOW) != null,
		"Mother Goose participates in visual LOD independently from boss simulation")
	_check(Probe.body_lod_level_for(-1, 7.0) == 2,
		"farthest visual scale selects LOD2 regardless of aircraft identity")
	_check(not Probe.mount_detail_mode_for(false, 8.0),
		"farthest visual scale omits unreadable attachments regardless of aircraft identity")
	_check(BenchRunner.VOLUME_EXPERIMENT_META == &"external_volume_experiment",
		"paired experiment carries an explicit single-renderer route marker")
	_check(not FormalOverlay.default_enabled(true),
		"external paired experiment rejects a duplicate formal renderer")
	var desert_presentation := load("res://scripts/rendering/desert_volume_presentation.gd")
	_check(load("res://scripts/tests/desert_formal_entry_runner.gd").can_instantiate(),
		"formal desert menu regression compiles before the Visual run")
	_check(desert_presentation.enabled_for(Probe.MAP_PATH), "formal desert is enabled without F6 or opt-in")
	_check(not desert_presentation.enabled_for(Probe.MAP_PATH, true)
		and not desert_presentation.enabled_for(Probe.MAP_PATH, false, "off")
		and not desert_presentation.enabled_for("res://resources/maps/ocean_islands_preview.aglmap")
		and not desert_presentation.enabled_for("user://maps/desert_copy.aglmap"),
		"formal map policy rejects duplicate backends, explicit rollback and unrelated maps")
	_check(load("res://scripts/survivor/survivor_mode.gd").can_instantiate(),
		"formal Survivor entry compiles with the shared transparent overlay")
	_check(load("res://scripts/experiments/volume_3d_lab.gd").COMBAT_SCENE_PATH
		== "res://scenes/tests/volume_3d_combat.tscn", "model viewer B key routes to manual battle")
	for path in ["res://scripts/experiments/volume_3d_desert.gd", "res://scripts/tests/volume_desert_smoke.gd"]:
		var script: GDScript = load(path)
		_check(script != null and script.can_instantiate(), "desert entry/smoke compiles before Visual")
	_check(load("res://scripts/experiments/volume_3d_lab.gd").DESERT_SCENE_PATH
		== "res://scenes/tests/volume_3d_desert.tscn", "model viewer D key routes to actual desert gameplay")
	for kind in ["fighter", "a10", "mother_goose", "prop", "vls"]:
		var mesh := Factory.aircraft(kind)
		_check(mesh.get_surface_count() == 1, "%s single shared surface" % kind)
		_check(mesh.get_aabb().size.y > 1.0, "%s real thickness" % kind)
		_check(mesh.get_aabb().size.x > 0.0 and mesh.get_aabb().size.z > 0.0, "%s volume" % kind)
		var arrays := mesh.surface_get_arrays(0)
		_check(arrays[Mesh.ARRAY_VERTEX].size() == arrays[Mesh.ARRAY_NORMAL].size(), "%s normals" % kind)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		_check((vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).dot(normals[0]) < 0.0,
			"%s Godot clockwise front agrees with outward normal" % kind)
	_check(Factory.aircraft("mother_goose").get_aabb().size.x > 440.0, "Goose native wingspan")
	for angle in [0.0, 0.25, -0.25, 1.5]:
		for zoom in [0.2, 0.446, 1.0, 2.0]:
			var canvas := Transform2D(angle, Vector2(140, 300)).scaled_local(Vector2.ONE * zoom)
			var screen_center := Vector2(960, 540)
			var center := canvas.affine_inverse() * screen_center
			var point := Vector2(390, -820)
			var relative := Probe.camera_basis(canvas).inverse() * (Probe.world_point(point, 600) - Probe.world_point(center, 50000))
			var projected: Vector2 = screen_center + Vector2(relative.x, -relative.y) * zoom
			_check(projected.distance_to(canvas * point) < 0.001, "orthographic ground/click center match")
			for tilt in [VolumeProjection.TILT, VolumeProjection.DESERT_TILT]:
				var display := VolumeProjection.ground_basis(canvas, tilt)
				var tilted := VolumeProjection.camera_basis(canvas, tilt)
				var camera_origin := display * Probe.world_point(center) + tilted.z * 50000.0
				for height in [0.0, 600.0, 608.0]:
					var actor := VolumeProjection.actor_transform(Transform3D(Basis.IDENTITY, Probe.world_point(point, height)), canvas, tilt)
					var view_point := tilted.inverse() * (actor.origin - camera_origin)
					var screen: Vector2 = screen_center + Vector2(view_point.x, -view_point.y) * zoom
					_check(screen.distance_to(canvas * point) < 0.01, "both entry tilts retain 2D click anchors")
	var doc := MapDocument.load_from(Probe.MAP_PATH)
	_check(doc != null, "map document exists")
	if doc != null:
		var route := Factory.points_from(doc.railways[0].points)
		_check(route == ArmoredTrainBoss.train_route(), "rail mesh uses actual train route SSOT")
		_check(Factory.map_mesh(doc).get_surface_count() == 1, "static map merged once")
	var ac := Aircraft.new()
	Probe._set_body_override(ac, true)
	_check(ac.has_meta(Probe.BODY_META), "body override enabled")
	Probe._set_body_override(ac, false)
	_check(not ac.has_meta(Probe.BODY_META), "fallback restores old body")
	var reference: WeakRef = weakref(ac)
	ac.free()
	_check(reference.get_ref() == null, "weak cache does not retain freed aircraft")
	var mount := WeaponMount.new()
	var params := WeaponMountParams.new()
	params.max_hp = 200.0
	mount.initialize(params)
	_check(mount.apply_damage(200.0) and mount.destroyed, "real damage commits mount destruction")
	print("[Volume focused] pass=%d fail=%d" % [_pass, _fail])


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Volume: " + label)
