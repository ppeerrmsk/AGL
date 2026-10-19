extends RefCounted
const Overlay := preload("res://scripts/rendering/tokyo_hierarchical_overlay.gd")
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")
var _pass := 0
var _fail := 0


func run(parent: Node, overlay_script: Script = Overlay) -> int:
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
	camera.zoom = Vector2.ONE * (2.2 * 5.0 / 6.0)
	camera.make_current()
	camera.force_update_scroll()
	var overlay: Overlay = overlay_script.new()
	view.add_child(overlay)
	_check(overlay.setup(source, camera), "native hierarchy setup")
	await _ready_cut(parent, overlay, 5)
	var state := overlay.debug_state()
	_check(state.active_cells == 16 and state.triangles == 187165, "real north cut matches R40 sixteen-block native reference")
	var solves := overlay._cut_solves
	var commits := overlay._cut_commits
	var redraws := overlay.redraws
	await parent.get_tree().create_timer(0.25).timeout
	_check(overlay._cut_solves == solves and overlay._cut_commits == commits and overlay.redraws == redraws, "static camera does not solve bind or redraw")
	for zoom_value: float in [5.0, 2.2, 0.98, 0.52, 0.26, 0.13, 0.06, 2.2]:
		camera.zoom = Vector2.ONE * zoom_value * (5.0 / 6.0)
		camera.force_update_scroll()
		await _ready_cut(parent, overlay)
		_check(overlay.debug_state().stream.failures.is_empty(), "six-level transition has no invalid resources")
	# 缺包只修改私有目标，不能污染共享目录；未齐时保留全部旧块。
	var saved: Array[Dictionary] = overlay._target_cut.duplicate()
	var before := overlay._current_paths.duplicate()
	var missing := "res://resources/maps/tokyo_volume_preview/r40_pages/intentional_missing.res"
	var first: Dictionary = overlay._target_cut[0].duplicate()
	if first.has("path"):
		first.path = missing
	else:
		first.building = missing
	overlay._target_cut[0] = first
	overlay._descriptors[missing] = {"id": 192, "level": 5, "bytes": 1, "height_hash": ""}
	overlay._target_paths = Overlay.paths_for(overlay._target_cut)
	overlay._stream.request(overlay._target_paths, overlay._current_paths)
	await parent.get_tree().create_timer(0.15).timeout
	_check(overlay._stream._failures.has(missing) and overlay._current_paths == before, "one missing child preserves entire previous cut")
	overlay._target_cut = saved
	overlay._target_paths = Overlay.paths_for(saved)
	overlay._stream.request(overlay._target_paths, overlay._current_paths)
	overlay._stream._failures.erase(missing)
	overlay._descriptors.erase(missing)
	await _ready_cut(parent, overlay, 5)
	var references: Array[WeakRef] = []
	var discarded: int = overlay._stream.discarded
	camera.position = Vector2(-5300, -700)
	camera.force_update_scroll()
	overlay._lod_clock = 0.0
	overlay._process(0.0)
	overlay._stream._process(0.0)
	_check(overlay._stream.summary().pending > 0, "camera cancellation has a genuine new in-flight cut")
	camera.position = Vector2(-5600, -2900)
	camera.force_update_scroll()
	overlay._lod_clock = 0.0
	overlay._process(0.0)
	await _ready_cut(parent, overlay, 5)
	_check(overlay._stream.discarded > discarded and overlay._current_paths == before, "cancelled cut drains while the original complete cut remains")
	for path: String in overlay._current_paths:
		references.append(weakref(overlay._stream.resource(path)))
	source.hide()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	_check(overlay._batches.is_empty() and overlay._stream.summary().cached == 0, "hide retires whole cut and cache pins")
	for reference: WeakRef in references:
		_check(reference.get_ref() == null, "hidden cut resource actually released")
	source.show()
	await _ready_cut(parent, overlay, 5)
	overlay.set_enabled(false)
	overlay.set_enabled(true)
	overlay._lod_clock = 0.0
	overlay._process(0.0)
	overlay._stream._process(0.0)
	_check(overlay._stream.summary().pending > 0, "teardown fixture owns a genuine asynchronous request")
	var stream_ref: WeakRef = weakref(overlay._stream)
	var overlay_ref: WeakRef = weakref(overlay)
	view.queue_free()
	var deadline := Time.get_ticks_msec() + 10000
	while stream_ref.get_ref() != null and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	_check(stream_ref.get_ref() == null and overlay_ref.get_ref() == null and Stream._busy.is_empty(), "real owner terminal drains pending registry beyond following frame")
	print("[Tokyo hierarchical lifecycle] pass=", _pass, " fail=", _fail)
	return _fail


func _ready_cut(parent: Node, overlay: Node, expected: int = -1) -> void:
	await parent.get_tree().create_timer(0.15).timeout
	var deadline := Time.get_ticks_msec() + 10000
	var old_paths: PackedStringArray = overlay._current_paths.duplicate()
	var old_commits: int = overlay._cut_commits
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = overlay.debug_state()
		_check(state.nodes <= 48 and overlay._city.get_child_count() <= 48 and state.active_cells <= 16 and state.stream.peak_bytes <= Stream.BUDGET and state.stream.peak_pending <= 2, "actual nodes and old new pending stay bounded")
		_check(overlay._cut_commits != old_commits or overlay._current_paths == old_paths, "no partial cut changes between atomic commits")
		if not state.transition_blocked.is_empty():
			_check(false, "transition admission failed: " + str(state))
			return
		if state.cut_ready and state.active_cells > 0 and state.stream.pending == 0 and (expected < 0 or state.level == expected):
			return
		await parent.get_tree().process_frame
	_check(false, "timed out waiting for complete hierarchical cut: " + str(overlay.debug_state()))


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo hierarchical lifecycle: " + label)
