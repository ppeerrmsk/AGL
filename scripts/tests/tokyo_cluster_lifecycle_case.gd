extends "res://scripts/tests/tokyo_hierarchical_lifecycle_case.gd"
## 实际SceneTree中的成对流送、立刻近景兜底、取消及释放。
const Cluster := preload("res://scripts/rendering/tokyo_cluster_overlay.gd")


func run(parent: Node, _script: Script = Cluster) -> int:
	var view := SubViewport.new()
	view.size = Vector2i(1600, 900)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(view)
	var source := Node2D.new()
	view.add_child(source)
	var camera := Camera2D.new()
	camera.ignore_rotation = false
	view.add_child(camera)
	camera.position = Vector2(-5600, -2900)
	camera.zoom = Vector2.ONE * 0.98 * (5.0 / 6.0)
	camera.make_current()
	camera.force_update_scroll()
	var overlay: Cluster = _script.new()
	view.add_child(overlay)
	_check(overlay.setup(source, camera), "cluster native setup")
	await _ready_cut(parent, overlay, 4)
	_check(overlay.debug_state().cluster_active and overlay.debug_state().fallback_paths > 0, "cluster only activates with original fallback pins")
	var solves: int = overlay._cut_solves
	var commits: int = overlay._cut_commits
	var redraws: int = overlay.redraws
	await parent.get_tree().create_timer(0.25).timeout
	_check(overlay._cut_solves == solves and overlay._cut_commits == commits and overlay.redraws == redraws, "static pair does not resolve rebind or redraw")
	# 只损坏实例私有计划中的备用路径；不能污染共享原生目录。
	var saved_plan: Array[Dictionary] = overlay._planned_cut.duplicate()
	var saved_paths: PackedStringArray = overlay._current_paths.duplicate()
	var missing := "res://resources/maps/tokyo_volume_preview/r40_pages/intentional_cluster_fallback_missing.res"
	var broken: Dictionary = saved_plan[0].duplicate()
	broken.fallback = broken.fallback.duplicate()
	if broken.fallback.has("path"):
		broken.fallback.path = missing
	else:
		broken.fallback.building = missing
	overlay._planned_cut[0] = broken
	overlay._descriptors[missing] = {"id": 0, "level": 5, "bytes": 1, "height_hash": ""}
	overlay._lod_clock = 10.0
	overlay._prepare_target(overlay._cull_view)
	await parent.get_tree().create_timer(0.2).timeout
	_check(overlay._stream._failures.has(missing) and overlay._current_paths == saved_paths
		and overlay._cut_commits == commits, "missing original fallback prevents partial pair commit and preserves all old geometry")
	overlay._planned_cut = saved_plan
	overlay._descriptors.erase(missing)
	overlay._stream._failures.erase(missing)
	overlay._prepare_target(overlay._cull_view)
	overlay._lod_clock = 0.0
	for pose: Array in [[1.3, 0.0], [1.65, deg_to_rad(14.0)], [1.65, deg_to_rad(-14.0)], [0.98, 0.0]]:
		camera.zoom = Vector2.ONE * float(pose[0]) * (5.0 / 6.0)
		camera.rotation = pose[1]
		camera.force_update_scroll()
		await _ready_cut(parent, overlay, 4)
		_check(overlay.debug_state().cluster_active, "full middle rotated pair actually commits")
	_check(overlay._stage_commits > 0, "real memory pressure exercises original-first staged transition")
	var original_paths := Cluster.paths_for(Cluster.Pair.original_cut(overlay._current_cut))
	var coarse_refs: Array[WeakRef] = []
	for path: String in Cluster.paths_for(overlay._current_cut):
		if path not in original_paths:
			coarse_refs.append(weakref(overlay._stream.resource(path)))
	var restores: int = overlay._instant_restores
	var started: int = overlay._stream.started
	overlay._lod_clock = 10.0
	overlay._stream.set_process(false)
	camera.zoom = Vector2.ONE * 5.0 * (5.0 / 6.0)
	camera.force_update_scroll()
	overlay._process(0.0)
	_check(overlay._instant_restores == restores + 1 and not overlay.debug_state().cluster_active, "large zoom restores original before LOD timer or background load")
	_check(overlay._stream.started == started and overlay._current_paths == original_paths, "immediate restoration uses already resident original cut only")
	for batch: Dictionary in overlay._batches.values():
		_check(batch.level == 5 and batch.nodes[0].mesh == batch.building.meshes[0]
			and batch.nodes[1].mesh == batch.building.meshes[1], "both low and marked-height meshes immediately regain native LOD5")
	for reference: WeakRef in coarse_refs:
		_check(reference.get_ref() == null, "coarse resource released before loading the next near cut")
	await _ready_cut(parent, overlay, 5)
	for zoom_value: float in [2.2, 0.52, 0.26, 0.13, 0.06, 0.98]:
		camera.zoom = Vector2.ONE * zoom_value * (5.0 / 6.0)
		camera.force_update_scroll()
		await _ready_cut(parent, overlay)
	_check(overlay.debug_state().cluster_active, "return from all other LODs restores the paired cluster")
	_check(overlay._trim_commits > 0, "far-to-middle transition actually retires whole offscreen blocks")
	var discarded: int = overlay._stream.discarded
	camera.position = Vector2(-5300, -700)
	camera.force_update_scroll()
	overlay._lod_clock = 0.0
	overlay._process(0.0)
	overlay._stream._process(0.0)
	_check(overlay._stream.summary().pending > 0, "cancellation starts an actual paired background request")
	camera.position = Vector2(-5600, -2900)
	camera.force_update_scroll()
	overlay._lod_clock = 0.0
	overlay._process(0.0)
	await _ready_cut(parent, overlay, 4)
	_check(overlay._stream.discarded > discarded and overlay.debug_state().cluster_active, "cancelled request drains before the correct paired city returns")
	var references: Array[WeakRef] = []
	for path: String in overlay._current_paths:
		references.append(weakref(overlay._stream.resource(path)))
	source.hide()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	_check(overlay._batches.is_empty() and overlay._current_paths.is_empty() and overlay._planned_cut.is_empty()
		and overlay._stream.summary().cached == 0, "hide clears displayed and fallback ownership together")
	for reference: WeakRef in references:
		_check(reference.get_ref() == null, "hidden candidate and fallback native resources released")
	source.show()
	await _ready_cut(parent, overlay, 4)
	overlay.set_enabled(false)
	overlay.set_enabled(true)
	overlay._lod_clock = 0.0
	overlay._process(0.0)
	overlay._stream._process(0.0)
	_check(overlay._stream.summary().pending > 0, "owner teardown has a genuine paired request in flight")
	var stream_ref: WeakRef = weakref(overlay._stream)
	var overlay_ref: WeakRef = weakref(overlay)
	view.queue_free()
	var deadline := Time.get_ticks_msec() + 10000
	while stream_ref.get_ref() != null and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	_check(stream_ref.get_ref() == null and overlay_ref.get_ref() == null and Stream._busy.is_empty(), "paired owner terminal drains actual pending requests")
	print("[Tokyo cluster lifecycle] pass=", _pass, " fail=", _fail)
	return _fail
