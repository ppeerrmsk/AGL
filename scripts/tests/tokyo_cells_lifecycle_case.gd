extends RefCounted
const Overlay := preload("res://scripts/rendering/tokyo_cells_overlay.gd")
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")
var _fail := 0
var _pass := 0


func run(parent: Node) -> int:
	_fail += await preload("res://scripts/tests/test_tokyo_hlod_stream.gd").run(parent)
	_fail += await preload("res://scripts/tests/test_tokyo_ao.gd").lifecycle(parent)
	var canonical: RefCounted = load("res://scripts/tests/tokyo_canonical_lifecycle_case.gd").new()
	_fail += await canonical.ownership(parent)
	var shadow_owner := Node.new()
	parent.add_child(shadow_owner)
	var shadow := preload("res://scripts/experiments/tokyo_static_shadow.gd").new()
	shadow._owner = weakref(shadow_owner)
	shadow._original.append(ShaderMaterial.new())
	shadow._replacement.append(ShaderMaterial.new())
	shadow_owner.queue_free()
	await parent.get_tree().process_frame
	shadow.close()
	shadow.close()
	_check(shadow._owner == null and shadow._original.is_empty() and shadow._replacement.is_empty(), "static shadow owner freed across frame: cleanup completes twice")
	_fail += await preload("res://scripts/tests/tokyo_rid_stream_case.gd").run(parent)
	# Headless 主窗口只有64像素，不能把逻辑zoom冒充输出像素尺度；使用独立原生尺寸视口。
	var test_view := SubViewport.new()
	test_view.size = Vector2i(1600, 900)
	test_view.world_2d = World2D.new()
	test_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(test_view)
	var host := Node2D.new()
	test_view.add_child(host)
	var source := MapFeatureRenderer.new()
	host.add_child(source)
	var camera := Camera2D.new()
	camera.ignore_rotation = false
	host.add_child(camera)
	camera.position = Vector2(8000, 8000)
	camera.zoom = Vector2.ONE * 2.2
	camera.make_current()
	camera.force_update_scroll()
	var overlay := Overlay.new()
	host.add_child(overlay)
	var initial_frame := Engine.get_process_frames()
	_check(overlay.setup(source, camera), "real overlay source/camera setup")
	var warm_deadline := Time.get_ticks_msec() + 2500
	while overlay._warm_ready_frame < 0 and Time.get_ticks_msec() < warm_deadline:
		await parent.get_tree().process_frame
	_check(overlay._warm_ready_frame > initial_frame + 2 and not overlay._screen.visible,
		"offscreen warm waits for real asynchronous meshes beyond two empty frames")
	for frame in 4:
		await parent.get_tree().process_frame
	_check(not overlay._should_prewarm() and overlay._batches.is_empty() and overlay._stream.summary().cached == 0,
		"completed hidden warm releases offscreen geometry")
	camera.position = Vector2(-30, -12550)
	camera.force_update_scroll()
	await _wait_ready(parent, overlay)
	var state: Dictionary = overlay.debug_state()
	_check(state.ready_cells > 0 and state.nodes <= 48 and state.materials == 6, "native bounded cell meshes ready")
	var visible_probe := preload("res://scripts/tests/tokyo_draw_geometry_probe.gd").new()
	_check(visible_probe.setup(overlay),"visible geometry probe setup")
	var update_mode := overlay._viewport.render_target_update_mode
	overlay._viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	visible_probe.capture()
	_check(visible_probe._samples==1 and visible_probe._peak>0,"visible real mesh counts reach draw boundary sample")
	var process_enabled := overlay.is_processing()
	_check(visible_probe._runtime_samples==1 and visible_probe._runtime_peak==visible_probe._peak,"normal draw has independent runtime peak")
	overlay.set_process(false)
	visible_probe.capture()
	_check(visible_probe._reference_samples==1 and visible_probe._runtime_samples==1 and visible_probe._reference_peak==visible_probe._peak,"reference draw counted separately without clearing total peak")
	overlay.set_process(process_enabled)
	overlay._viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	visible_probe.capture()
	_check(visible_probe._samples==2 and visible_probe._skipped==1,"disabled map target does not count repeated retained scene")
	overlay._viewport.render_target_update_mode=update_mode
	visible_probe.close()
	_check(state.stream.peak_pending <= 2 and state.stream.max_completed_per_frame == 1 and state.stream.peak_bytes <= Stream.BUDGET, "bounded threaded requests and single completion")
	var redraws: int = overlay.redraws
	var binds: int = overlay.binds
	for frame in 8:
		await parent.get_tree().process_frame
	_check(overlay.redraws == redraws and overlay.binds == binds, "static camera does not bind or redraw")
	await _test_old_on_missing(parent, overlay, camera)
	camera.zoom = Vector2.ONE * 0.13
	camera.rotation = 0.22
	camera.force_update_scroll()
	await _wait_ready(parent, overlay, 1)
	_check(overlay.debug_state().level == 1, "actual asynchronous LOD downgrade completes")
	camera.zoom = Vector2.ONE * 5.0
	camera.position = Vector2(330, -13420)
	camera.force_update_scroll()
	await _wait_ready(parent, overlay, 5)
	var max_error := 0.0
	var canvas := source.get_viewport().get_canvas_transform()
	for anchor: Vector2 in [Vector2(330, -13420), Vector2(-520, -13870), Vector2(1120, -11590), Vector2(95, -12730)]:
		var actual := overlay._camera.unproject_position(overlay._city.basis * Vector3(anchor.x, 0, anchor.y))
		var expected := (canvas * anchor) * source.get_viewport().get_stretch_transform().get_scale()
		max_error = maxf(max_error, actual.distance_to(expected))
	_check(max_error < 0.5, "cell geometry uses real rotated camera projection")
	var references: Array[WeakRef] = []
	for path: String in overlay._stream._cache:
		references.append(weakref(overlay._stream.resource(path)))
	camera.position = Vector2(8000, 8000)
	camera.force_update_scroll()
	for frame in 6:
		await parent.get_tree().process_frame
	_check(not overlay.debug_state().active and overlay.debug_state().nodes == 0, "offregion disables viewport and retires nodes")
	_check(overlay._stream.summary().cached == 0, "offregion releases cache pins")
	for reference in references:
		_check(reference.get_ref() == null, "retired native resource no longer retained")
	camera.position = Vector2(-30, -12550)
	camera.force_update_scroll()
	await _wait_ready(parent, overlay, 5)
	_check(overlay.debug_state().ready_cells > 0, "return after eviction reloads real resources")
	var loader_ref: WeakRef = weakref(overlay._stream)
	source.queue_free()
	for frame in 3:
		await parent.get_tree().process_frame
	_check(not overlay.debug_state().active and overlay.debug_state().nodes == 0, "freed source reaches safe consumer end")
	# R36：真正释放SceneTree视口后再执行测量回调，避免立即quit掩盖清理路径。
	var phase_probe: RefCounted = load("res://scripts/tests/tokyo_render_trace.gd").new()
	var extra_view := SubViewport.new()
	parent.add_child(extra_view)
	var extra_probe: RefCounted = load("res://scripts/tests/tokyo_render_trace.gd").new()
	extra_probe.setup(test_view, overlay._viewport, true, extra_view)
	_check(extra_probe._views.size() == 3, "backend probe includes optional aircraft viewport")
	extra_view.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	extra_probe._after_draw()
	extra_probe.close()
	extra_probe.close()
	_check(extra_probe._closed and extra_probe._views.is_empty()
		and not RenderingServer.frame_post_draw.is_connected(extra_probe._after_draw), "optional viewport freed alone closes across frames")
	phase_probe.setup(test_view, overlay._viewport, true)
	var geometry_probe := preload("res://scripts/tests/tokyo_draw_geometry_probe.gd").new()
	_check(geometry_probe.setup(overlay) and not geometry_probe.setup(overlay),"draw boundary probe connects once")
	geometry_probe.capture()
	_check(geometry_probe._skipped==1 and geometry_probe._samples==0,"inactive geometry is not a draw sample")
	_check(RenderingServer.frame_pre_draw.is_connected(phase_probe._before_draw), "render phase signals connected")
	test_view.queue_free()
	await _wait_gone(parent, loader_ref)
	phase_probe._begin = Time.get_ticks_usec()
	phase_probe._after_draw()
	phase_probe.close()
	geometry_probe._pending_faces=1
	geometry_probe._verify_report()
	geometry_probe.capture()
	geometry_probe.close()
	_check(geometry_probe._closed and geometry_probe._owner==null and not RenderingServer.frame_pre_draw.is_connected(geometry_probe.capture)
		and not RenderingServer.frame_post_draw.is_connected(geometry_probe._verify_report),"freed geometry owner closes both boundary callbacks across frame")
	_check(phase_probe._closed and phase_probe._views.is_empty()
		and not RenderingServer.frame_pre_draw.is_connected(phase_probe._before_draw)
		and not RenderingServer.frame_post_draw.is_connected(phase_probe._after_draw), "released viewport callback closes idempotently")
	_check(loader_ref.get_ref() == null, "owner teardown retires independent loader")
	await _test_cancel_reenter(parent)
	await _test_missing(parent)
	await _test_empty_coastal_cell(parent)
	await _test_layer_visibility(parent)
	await _test_layer_visibility(parent, true)
	await _test_layer_visibility(parent, true, true)
	await _test_layer_visibility(parent, true, true, true)
	await _test_layer_visibility(parent, true, true, true, true)
	await _test_layer_visibility(parent, true, true, true, true, true)
	await _test_layer_visibility(parent, true, true, true, true, true, "yokohama_coverage_b")
	await _test_layer_visibility(parent, true, true, true, true, true, "yokohama_coverage_c")
	await _test_layer_visibility(parent, true, true, true, true, true, "yokohama_domes_b")
	await _test_layer_visibility(parent, true, true, true, true, true, "yokohama_shadow_depth")
	if ResourceLoader.exists("res://resources/maps/tokyo_volume_preview/r19_cells/index.res"):
		await _test_layer_visibility(parent, true, true, true, true, true, "yokohama_dedup")
	if ResourceLoader.exists("res://resources/maps/tokyo_volume_preview/r20_cells/index.res"):
		await _test_north_coast(parent)
	if ResourceLoader.exists("res://resources/maps/tokyo_volume_preview/r21_cells/index.res"):
		await _test_north_coast(parent, "kawasaki_strokes")
	if ResourceLoader.exists("res://resources/maps/tokyo_volume_preview/r22_cells/index.res"):
		await _test_north_coast(parent, "kawasaki_lod")
	if ResourceLoader.exists("res://resources/maps/tokyo_volume_preview/r26b_cells/index.res"):
		await _test_north_coast(parent, "yokohama_joined")
		await _test_north_coast(parent, "yokohama_joined_depth")
	if ResourceLoader.exists("res://resources/maps/tokyo_volume_preview/r28_cells/index.res"):
		await _test_north_coast(parent, "yokohama_joined_indexed")
		await _test_full_indexed_mid(parent)
	if ResourceLoader.exists("res://resources/maps/tokyo_volume_preview/r29_cells/index.res"):
		await _test_north_coast(parent, "yokohama_joined_spatial")
		await _test_full_indexed_mid(parent, "res://resources/maps/tokyo_volume_preview/r29_cells/index.res")
	if ResourceLoader.exists("res://resources/maps/tokyo_volume_preview/r30_cells/index.res"):
		await _test_north_coast(parent, "yokohama_joined_area")
		await _test_full_indexed_mid(parent, "res://resources/maps/tokyo_volume_preview/r30_cells/index.res")
	if ResourceLoader.exists("res://resources/maps/tokyo_volume_preview/r32_cells/index.res"):
		await _test_north_coast(parent, "yokohama_joined_palette")
		await _test_full_indexed_mid(parent, "res://resources/maps/tokyo_volume_preview/r32_cells/index.res")
	if ResourceLoader.exists("res://resources/maps/tokyo_volume_preview/r34_cells/index.res"):
		await _test_north_coast(parent, "yokohama_joined_coastal")
		await _test_full_indexed_mid(parent, "res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	_check(await preload("res://scripts/tests/test_tokyo_shoreline_layer.gd").lifecycle(parent) == 0, "shoreline material warmup and cancellation release across frames")
	print("[Tokyo cells lifecycle] pass=", _pass, " fail=", _fail, " projection_error=", max_error)
	var hierarchy: RefCounted = load("res://scripts/tests/tokyo_hierarchical_lifecycle_case.gd").new()
	_fail += await hierarchy.run(parent)
	var spatial_lod: RefCounted = load("res://scripts/tests/tokyo_hierarchical_lifecycle_case.gd").new()
	_fail += await spatial_lod.run(parent, load("res://scripts/rendering/tokyo_lod_hierarchical_overlay.gd"))
	var cluster_lod: RefCounted = load("res://scripts/tests/tokyo_cluster_lifecycle_case.gd").new()
	_fail += await cluster_lod.run(parent)
	var stable_lod: RefCounted = load("res://scripts/tests/tokyo_cluster_lifecycle_case.gd").new()
	_fail += await stable_lod.run(parent, load("res://scripts/rendering/tokyo_stable_cluster_overlay.gd"))
	var preload_case: RefCounted = load("res://scripts/tests/tokyo_preload_lifecycle_case.gd").new()
	_fail += await preload_case.run(parent)
	return _fail


func _test_full_indexed_mid(parent: Node, index_path: String = "res://resources/maps/tokyo_volume_preview/r28_cells/index.res") -> void:
	# 此项只证明真实流送容量，不冒充16块同时绘制的性能通过。
	var index: Resource = load(index_path)
	var owner := Node.new()
	parent.add_child(owner)
	var loader := Stream.new()
	var descriptors: Dictionary = {}
	var wanted := PackedStringArray()
	var expected_bytes := 0
	for cell: Dictionary in index.cells:
		descriptors[cell.fixed] = {"id": cell.id, "level": -1, "bytes": cell.fixed_bytes}
		var entry: Dictionary = cell.levels[3]
		descriptors[entry.path] = {"id": cell.id, "level": 3, "bytes": entry.bytes, "height_hash": entry.height_hash}
		wanted.append(cell.fixed)
		wanted.append(entry.path)
		expected_bytes += int(cell.fixed_bytes) + int(entry.bytes)
	loader.configure(owner, descriptors)
	parent.add_child(loader)
	loader.request(wanted, PackedStringArray())
	var deadline := Time.get_ticks_msec() + 15000
	while loader.summary().cached != 32 and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	var state: Dictionary = loader.summary()
	_check(state.cached == 32 and state.pending == 0 and state.failures.is_empty() and state.bytes == expected_bytes \
		and state.peak_bytes <= Stream.BUDGET, "all 16 indexed level3 cells and fixed ground fit original 96MiB")
	print("[Tokyo indexed capacity] cached=", state.cached, " bytes=", state.bytes, " peak=", state.peak_bytes)
	var reference: WeakRef = weakref(loader)
	owner.queue_free()
	await _wait_gone(parent, reference)
	_check(reference.get_ref() == null, "full indexed working set drains after owner exit")


func _test_north_coast(parent: Node, variant: String = "kawasaki") -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1600, 900)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(view)
	var source := MapFeatureRenderer.new()
	view.add_child(source)
	var camera := Camera2D.new()
	camera.ignore_rotation = false
	view.add_child(camera)
	camera.position = Vector2(-4300, -2700)
	if variant in ["yokohama_joined", "yokohama_joined_depth", "yokohama_joined_indexed", "yokohama_joined_spatial", "yokohama_joined_area", "yokohama_joined_palette", "yokohama_joined_coastal"]:
		camera.position = Vector2(-5300, -1700)
	camera.zoom = Vector2.ONE * 0.96
	camera.make_current()
	camera.force_update_scroll()
	var overlay := Overlay.new()
	view.add_child(overlay)
	var previous := OS.get_environment("AGL_TOKYO_CELLS_VARIANT")
	OS.set_environment("AGL_TOKYO_CELLS_VARIANT", variant)
	_check(overlay.setup(source, camera), "R20 native north-coast archive setup")
	if variant in ["yokohama_joined_palette", "yokohama_joined_coastal"]:
		_check(overlay._composite.get_shader_parameter("edge_feather") == 0.0, "native palette candidate has no geometric-edge feather")
	OS.set_environment("AGL_TOKYO_CELLS_VARIANT", previous)
	for zoom_value: float in [0.96, 2.2, 0.13]:
		camera.zoom = Vector2.ONE * zoom_value
		camera.rotation = deg_to_rad(14)
		camera.force_update_scroll()
		await _wait_ready(parent, overlay, 4 if zoom_value == 0.96 else (5 if zoom_value == 2.2 else 1))
		var state: Dictionary = overlay.debug_state()
		_check(state.candidate.begins_with({"kawasaki": "R20 ", "kawasaki_strokes": "R21 ", "kawasaki_lod": "R22 ", "yokohama_joined": "R26 ", "yokohama_joined_depth": "R27 ", "yokohama_joined_indexed": "R28 ", "yokohama_joined_spatial": "R29 ", "yokohama_joined_area": "R30 ", "yokohama_joined_palette": "R32 ", "yokohama_joined_coastal": "R34 "}[variant]) and state.active and state.stream.failures.is_empty(),
			"R20 real rotated LOD transition retains valid regional geometry")
		_check(state.nodes <= 48 and state.materials == 6 and state.stream.peak_bytes <= Stream.BUDGET,
			"R20 native node material and streaming caps")
		# 提交面预算由真实巡检性能门独立裁决；此处只证明异步加载/终态，不冒充性能通过。
		print("[R20 lifecycle geometry] zoom=", zoom_value, " triangles=", state.triangles,
			" peak=", state.max_transition_triangles, " bytes=", state.stream.peak_bytes)
	if variant in ["kawasaki_lod", "yokohama_joined", "yokohama_joined_depth", "yokohama_joined_indexed", "yokohama_joined_spatial", "yokohama_joined_area", "yokohama_joined_palette", "yokohama_joined_coastal"]:
		await _test_precision_jump(parent, overlay, camera)
	var redraws: int = overlay.redraws
	for frame in 8:
		await parent.get_tree().process_frame
	_check(overlay.redraws == redraws, "R20 static camera does not redraw")
	var loader_ref: WeakRef = weakref(overlay._stream)
	source.queue_free()
	for frame in 3:
		await parent.get_tree().process_frame
	_check(not overlay.debug_state().active and overlay.debug_state().nodes == 0, "R20 source exit clears batches")
	view.queue_free()
	await _wait_gone(parent, loader_ref)
	_check(loader_ref.get_ref() == null, "R20 regional loader drains on owner exit")


func _test_precision_jump(parent: Node, overlay: Node, camera: Camera2D) -> void:
	camera.zoom = Vector2.ONE * 0.06
	camera.force_update_scroll()
	await _wait_ready(parent, overlay, 0)
	var guard_count := 0
	for batch: Dictionary in overlay._batches.values():
		guard_count += int(batch.building.precision_original != null)
	_check(guard_count > 0 and overlay.debug_state().precision_guarded == 0, "R22 actual far archive starts with simplified mesh")
	var requests: int = overlay._stream.started
	# 暂停选档，以比真实异步读取更坏的条件证明拉近不依赖新包抵达。
	overlay._lod_clock = 1000.0
	camera.zoom = Vector2.ONE * 5.0
	camera.force_update_scroll()
	for frame in 3:
		await parent.get_tree().process_frame
	var originals := true
	var actual_triangles := 0
	for batch: Dictionary in overlay._batches.values():
		if batch.building.precision_original != null:
			originals = originals and batch.nodes[0].mesh == batch.building.precision_original
		for node: MeshInstance3D in batch.nodes:
			if node.visible and node.mesh.get_surface_count() > 0:
				var corners: int = node.mesh.surface_get_array_index_len(0)
				actual_triangles += (corners if corners > 0 else node.mesh.surface_get_array_len(0)) / 3
	var state: Dictionary = overlay.debug_state()
	_check(overlay._level == 0 and state.precision_guarded == guard_count and originals and overlay._stream.started == requests,
		"R22 zoom jump restores resident original before any new LOD request")
	_check(state.triangles == actual_triangles and state.max_transition_triangles >= actual_triangles,
		"R22 telemetry counts actual original fallback submissions")
	var redraws: int = overlay.redraws
	var precision_binds: int = state.precision_binds
	for frame in 8:
		await parent.get_tree().process_frame
	_check(overlay.redraws == redraws and overlay.debug_state().precision_binds == precision_binds,
		"R22 static precision guard does not bind or redraw")
	camera.zoom = Vector2.ONE * 0.06
	camera.force_update_scroll()
	for frame in 3:
		await parent.get_tree().process_frame
	_check(overlay.debug_state().precision_guarded == 0 and overlay._stream.started == requests,
		"R22 zoom return restores resident simplified mesh without reload")
	overlay._lod_clock = 0.0


func _test_layer_visibility(parent: Node, mid: bool = false, directional: bool = false, adaptive: bool = false, exact: bool = false, coverage: bool = false, coverage_variant: String = "yokohama_coverage") -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1600, 900)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(view)
	var source := MapFeatureRenderer.new()
	view.add_child(source)
	var camera := Camera2D.new()
	camera.ignore_rotation = false
	view.add_child(camera)
	camera.position = Vector2(-5300, -700)
	camera.zoom = Vector2.ONE * (0.96 if mid else 0.98)
	camera.make_current()
	camera.force_update_scroll()
	var overlay := Overlay.new()
	view.add_child(overlay)
	var previous := OS.get_environment("AGL_TOKYO_CELLS_VARIANT")
	OS.set_environment("AGL_TOKYO_CELLS_VARIANT", "yokohama_directional" if directional else ("yokohama_mid" if mid else "yokohama_cull"))
	if adaptive:
		OS.set_environment("AGL_TOKYO_CELLS_VARIANT", "yokohama_frustum" if exact else "yokohama_adaptive")
	if coverage:
		OS.set_environment("AGL_TOKYO_CELLS_VARIANT", coverage_variant)
	_check(overlay.setup(source, camera), "R11 real native archive setup")
	OS.set_environment("AGL_TOKYO_CELLS_VARIANT", previous)
	await _wait_ready(parent, overlay, 4)
	var state: Dictionary = overlay.debug_state()
	var probe := 8
	var restore := 12
	if adaptive:
		for entry: Dictionary in overlay._archive.cells:
			if (entry.bounds as Rect2).has_point(camera.position):
				probe = int(entry.id)
		restore = -1
		for id: int in overlay._batches:
			if overlay._batches[id].layer_triangles[0] > 0 and not overlay._batches[id].nodes[0].visible:
				restore = id
				break
		var expected := "R14" if exact else "R13"
		if coverage:
			expected = {"yokohama_coverage": "R15 ", "yokohama_coverage_b": "R15B ", "yokohama_coverage_c": "R15C ", "yokohama_domes_b": "R17B ", "yokohama_shadow_depth": "R18 ", "yokohama_dedup": "R19 "}[coverage_variant]
		_check(restore >= 0 and state.candidate.begins_with(expected) and state.exact_view == exact and state.nodes <= 48 and state.materials == 6,
			"R13 real density archive retains node/material caps and hidden populated fixture")
	_check(state.layer_culling and state.triangles < state.resident_triangles and state.triangles <= 240000,
		"R11 real mid-view hides offscreen submissions without removing resident geometry")
	if not mid:
		_check(overlay._batches.has(12) and not overlay._batches[12].nodes[0].visible, "R11 south low layer initially hidden")
	else:
		_check(state.mid_relief, "R11B independent viewport enters real mid package")
	var redraws: int = overlay.redraws
	if coverage_variant in ["yokohama_shadow_depth", "yokohama_dedup"]:
		_check(state.tight_depth and state.source_max_height > 0 and state.source_max_height < 500 \
			and state.camera_far - state.camera_near < 1600, "R18 real archive activates fitted camera depth")
	else:
		_check(not state.tight_depth and state.camera_far - state.camera_near >= 2400, "legacy camera depth remains unchanged")
	for frame in 8:
		await parent.get_tree().process_frame
	_check(overlay.redraws == redraws, "R11 static visibility does not redraw")
	_check(overlay._camera.near == state.camera_near and overlay._camera.far == state.camera_far,
		"static camera depth remains unchanged")
	if directional:
		_check(state.directional_cull, "R12 real fixture enables directional culling")
		for degrees: float in [14.0, -14.0]:
			camera.rotation = deg_to_rad(degrees)
			camera.force_update_scroll()
			await _wait_ready(parent, overlay, 4)
			_check(absf(rad_to_deg(overlay.debug_state().canvas_rotation)) > 13.0 \
				and overlay._cull_camera == overlay._camera.basis, "R12 actual symmetric rotation refreshes cached direction")
		camera.rotation = 0.0
		camera.force_update_scroll()
		await _wait_ready(parent, overlay, 4)
	if mid:
		camera.zoom = Vector2.ONE * 1.05
		camera.force_update_scroll()
		await _wait_ready(parent, overlay, 4)
		_check(not overlay.debug_state().mid_relief and overlay._batches[probe].path == overlay._archive.cells[probe].levels[4].path,
			"R11B zoom-up asynchronously restores full walls without global LOD change")
		camera.zoom = Vector2.ONE * 0.96
		camera.force_update_scroll()
		await _wait_ready(parent, overlay, 4)
		_check(overlay.debug_state().mid_relief and overlay._batches[probe].path == overlay._archive.cells[probe].mid.path,
			"R11B zoom-down reloads middle package")
	camera.position.y = -200
	if adaptive and restore >= 0:
		camera.position = (overlay._archive.cells[restore].content_bounds as Rect2).get_center()
	camera.force_update_scroll()
	await _wait_ready(parent, overlay, 4)
	_check(overlay._batches.has(restore) and overlay._batches[restore].nodes[0].visible, "moving into previously hidden low layer restores real node")
	var loader_ref: WeakRef = weakref(overlay._stream)
	source.queue_free()
	for frame in 3:
		await parent.get_tree().process_frame
	_check(not overlay.debug_state().active and overlay.debug_state().nodes == 0, "R11 source exit clears visible and hidden batches")
	view.queue_free()
	await _wait_gone(parent, loader_ref)
	_check(loader_ref.get_ref() == null, "R11 loader drains after layer owner exit")


func _test_cancel_reenter(parent: Node) -> void:
	var owner := Node.new()
	parent.add_child(owner)
	var index: Resource = load("res://resources/maps/tokyo_volume_preview/r6_cells/index.res")
	var entry: Dictionary = index.cells[3].levels[5]
	var descriptors := {entry.path: {"id": 3, "level": 5, "bytes": entry.bytes, "height_hash": entry.height_hash}}
	var old := Stream.new()
	old.configure(owner, descriptors)
	parent.get_tree().root.add_child(old)
	old.request(PackedStringArray([entry.path]), PackedStringArray())
	# 显式发出真实后台请求后立即结束owner，不能靠从未启动的空队列证明取消。
	old._process(0.0)
	_check(old.summary().pending == 1 and old.started == 1, "cancel fixture has a real in-flight request")
	var old_ref: WeakRef = weakref(old)
	owner.queue_free()
	await parent.get_tree().process_frame
	var next_owner := Node.new()
	parent.add_child(next_owner)
	var next := Stream.new()
	next.configure(next_owner, descriptors)
	parent.get_tree().root.add_child(next)
	next.request(PackedStringArray([entry.path]), PackedStringArray())
	var deadline := Time.get_ticks_msec() + 10000
	while next.resource(entry.path) == null and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	_check(next.resource(entry.path) != null and next.summary().failures.is_empty(), "same-path reentry waits for old request drain and loads")
	await _wait_gone(parent, old_ref)
	_check(old_ref.get_ref() == null, "cancelled loader drains and frees without blocking")
	var next_ref: WeakRef = weakref(next)
	next_owner.queue_free()
	await _wait_gone(parent, next_ref)
	_check(next_ref.get_ref() == null and Stream._busy.is_empty(), "reentry terminal clears shared in-flight registry")


func _test_old_on_missing(parent: Node, overlay: Node, camera: Camera2D) -> void:
	var original: Resource = overlay._archive
	# 只改夹具自己的目录副本，不能污染 load() 共享的生产资源。
	overlay._archive = original.duplicate(true)
	var id: int = overlay._desired[0]
	var original_path: String = overlay._archive.cells[id].levels[1].path
	var missing := "res://resources/maps/tokyo_volume_preview/r6_cells/intentional_missing_lod.res"
	overlay._archive.cells[id].levels[1].path = missing
	overlay._descriptors[missing] = overlay._descriptors[original_path].duplicate()
	var old_ref: WeakRef = weakref(overlay._batches[id].building)
	var old_level: int = overlay._batches[id].level
	camera.zoom = Vector2.ONE * 0.13
	camera.force_update_scroll()
	var deadline := Time.get_ticks_msec() + 5000
	while not overlay._stream._failures.has(missing) and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	_check(overlay._stream._failures.has(missing), "failed target LOD enters explicit failure state")
	_check(overlay._batches.has(id) and overlay._batches[id].level == old_level \
		and old_ref.get_ref() == overlay._batches[id].building, "missing new LOD never removes the visible old building")
	overlay._archive = original
	overlay._descriptors.erase(missing)
	overlay._stream._failures.erase(missing)
	overlay._sync_requests()
	await _wait_ready(parent, overlay, 1)
	_check(overlay._batches[id].level == 1, "restored valid target replaces preserved old LOD")


func _test_missing(parent: Node) -> void:
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	var path := "res://resources/maps/tokyo_volume_preview/r6_cells/intentional_missing_fixture.res"
	stream.configure(owner, {path: {"id": 0, "level": 0, "bytes": 100, "height_hash": ""}})
	parent.get_tree().root.add_child(stream)
	stream.request(PackedStringArray([path]), PackedStringArray())
	for frame in 4:
		await parent.get_tree().process_frame
	_check(stream.summary().failures.size() == 1 and stream.started == 0 and not stream.is_processing(), "missing resource recorded once without retry spin")
	var reference: WeakRef = weakref(stream)
	owner.queue_free()
	await _wait_gone(parent, reference)
	_check(reference.get_ref() == null, "idle failed loader also retires on owner exit")


func _wait_ready(parent: Node, overlay: Node, expected_level: int = -1) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	# 先越过镜头同步与10Hz选块tick；不能把前一机位已经就绪当成新请求完成。
	await parent.get_tree().create_timer(0.15).timeout
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = overlay.debug_state()
		if state.active and state.desired_cells > 0 and state.ready_cells == state.desired_cells \
				and (expected_level < 0 or state.level == expected_level) and state.stream.pending == 0:
			return
		await parent.get_tree().process_frame
	_check(false, "timed out waiting for real asynchronous geometry: " + str(overlay.debug_state()))


func _test_empty_coastal_cell(parent: Node) -> void:
	var index: Resource = load("res://resources/maps/tokyo_volume_preview/r9_cells/index.res")
	var entry: Dictionary = index.cells[3].levels[0]
	_check(int(entry.bytes) == 0, "real Yokohama sea-only fixture has zero building geometry")
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	stream.configure(owner, {entry.path: {"id": 3, "level": 0, "bytes": 0, "height_hash": entry.height_hash}})
	parent.get_tree().root.add_child(stream)
	stream.request(PackedStringArray([entry.path]), PackedStringArray())
	var deadline := Time.get_ticks_msec() + 5000
	while stream.resource(entry.path) == null and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	_check(stream.resource(entry.path) != null and stream.completed == 1 and stream.summary().failures.is_empty(),
		"zero-byte sea block loads once through real asynchronous path")
	stream.request(PackedStringArray(), PackedStringArray())
	await parent.get_tree().process_frame
	_check(stream.summary().cached == 0, "empty block evicts without invalid byte accounting")
	var reference: WeakRef = weakref(stream)
	owner.queue_free()
	await _wait_gone(parent, reference)
	_check(reference.get_ref() == null, "empty coastal loader retires after owner exit")


func _wait_gone(parent: Node, reference: WeakRef) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while reference.get_ref() != null and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo cells lifecycle: " + label)
