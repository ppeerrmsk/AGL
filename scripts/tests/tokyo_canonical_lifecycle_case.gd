extends RefCounted
const Overlay := preload("res://scripts/rendering/tokyo_canonical_overlay.gd")
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
var _fail := 0
var _pass := 0


func run(parent: Node) -> int:
	await ownership(parent)
	var tree := parent.get_tree()
	var view := SubViewport.new()
	view.size = Vector2i(1600, 900)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(view)
	var source := Node2D.new()
	view.add_child(source)
	var camera := Camera2D.new()
	camera.ignore_rotation = false
	camera.position = Vector2(-5650, -1000)
	camera.zoom = Vector2.ONE * 0.13
	view.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	var legacy := BuildingRenderer.new()
	view.add_child(legacy)
	legacy.setup(camera)
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	var overlay := Overlay.new()
	view.add_child(overlay)
	_check(overlay.setup(source, camera), "actual eleven-configuration setup")
	_check(overlay.bind_legacy(legacy), "actual collision cache authority matches")
	if not await _wait(parent, overlay):
		view.queue_free()
		await tree.process_frame
		return 1
	_check(not legacy._volume_sources.is_empty(), "real native bound geometry replaces old building drawing")
	var covered := legacy._volume_sources.duplicate()
	for batch: Dictionary in overlay._batches.values():
		if batch.building.game_sources.is_empty():
			continue
		batch.nodes[1].hide()
		overlay._sync_legacy()
		_check(legacy._volume_sources.size() < covered.size(), "resident but unshown wall layer restores affected old buildings")
		batch.nodes[1].show()
		overlay._sync_legacy()
		_check(legacy._volume_sources == covered, "actual visible wall restoration recovers complete coverage")
		break
	var state := overlay.debug_state()
	print("[R63 initial] config=", state.canonical_configuration, " hidden=", state.hidden_legacy_sources.size(), " faces=", state.triangles, " bytes=", state.stream.peak_bytes)
	var updates := overlay._coverage_updates
	var redraws := overlay.redraws
	await tree.create_timer(0.25).timeout
	_check(overlay._coverage_updates == updates and overlay.redraws == redraws, "unchanged view does not recompute coverage or redraw")
	var planned: Array[Dictionary] = overlay._planned_cut.duplicate(true)
	var paths := overlay._current_paths.duplicate()
	var commits := overlay._cut_commits
	var missing := "res://resources/maps/tokyo_volume_preview/intentional_r63_missing.res"
	var broken: Dictionary = overlay._planned_cut[0].duplicate(true)
	broken.fallback.path = missing
	overlay._planned_cut[0] = broken
	overlay._descriptors[missing] = {"bytes": 1, "canonical_identity": {}}
	overlay._lod_clock = 10.0
	overlay._prepare_target(overlay._cull_view)
	await tree.create_timer(0.2).timeout
	_check(overlay._stream._failures.has(missing) and overlay._current_paths == paths and overlay._cut_commits == commits, "missing fallback prevents partial commit and retains previous complete map")
	overlay._planned_cut = planned
	overlay._descriptors.erase(missing)
	overlay._stream._failures.erase(missing)
	overlay._prepare_target(overlay._cull_view)
	var restores := overlay._instant_restores
	var started: int = overlay._stream.started
	overlay._stream.set_process(false)
	overlay._lod_clock = 10.0
	camera.zoom = Vector2.ONE * 0.26
	camera.force_update_scroll()
	overlay._process(0.0)
	_check(overlay._instant_restores == restores + 1 and overlay.debug_state().canonical_configuration == "lod1_guarded" \
		and overlay._stream.started == started, "sudden zoom binds resident guarded original before any new request completes")
	# 当前已是安全原形，但异步目标仍可能来自旧尺度；不能等0.1秒选档时钟。
	overlay._target_cut=planned.duplicate(true)
	overlay._target_paths=Overlay.Pair.paths(overlay._target_cut)
	overlay._planned_cut=planned.duplicate(true)
	overlay._lod_clock=10.0
	overlay._selection_canvas=overlay._last_canvas
	overlay._process(0.0)
	_check(overlay._target_cut.is_empty() or not overlay._is_cluster(overlay._target_cut) or int(overlay._target_cut[0].level)>1,"stale pending low cut rejected while current guarded original is safe")
	_check(overlay._stream.started==started,"stale cut invalidation needs no synchronous resource load")
	overlay._stream.set_process(true)
	for scale_value: float in [0.26, 0.52, 0.8, 0.98, 2.2, 5.0, 0.06, 0.13]:
		camera.zoom = Vector2.ONE * scale_value
		camera.force_update_scroll()
		if not await _wait(parent, overlay):
			break
		state = overlay.debug_state()
		_check(state.nodes == 48 and state.materials == 6 and state.stream.peak_bytes <= Overlay.Stream.BUDGET, "same pooled nodes/materials and geometry budget")
		_check(var_to_bytes(BuildingRenderer._cache_entries) == collision and var_to_bytes(legacy._districts) == collision, "LOD handoff never edits collision or source order")
		print("[R63 pose] scale=", scale_value, " configuration=", state.canonical_configuration, " hidden=", state.hidden_legacy_sources.size(), " faces=", state.triangles, " bytes=", state.stream.peak_bytes)
	var before_hidden := legacy._volume_sources.duplicate()
	overlay.set_enabled(false)
	_check(legacy._volume_sources.is_empty(), "disable synchronously restores every old building")
	await tree.process_frame
	_check(legacy._volume_sources.is_empty(), "disabled coverage stays clear across the next frame")
	overlay.set_enabled(true)
	if await _wait(parent, overlay):
		_check(legacy._volume_sources == before_hidden, "reenable restores exact same source coverage")
	var map_ref: WeakRef = weakref(overlay)
	var stream_ref: WeakRef = weakref(overlay._stream)
	overlay.queue_free()
	await tree.process_frame
	await tree.process_frame
	_check(map_ref.get_ref() == null and legacy._volume_sources.is_empty() and legacy._volume_owner_id == 0, "map owner exit clears visual mask without freed-object reads")
	var deadline := Time.get_ticks_msec() + 10000
	while stream_ref.get_ref() != null and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	_check(stream_ref.get_ref() == null, "single stream drains and releases after owner exit")
	view.queue_free()
	await tree.process_frame
	print("[R63 lifecycle] pass=", _pass, " fail=", _fail)
	return 1 if _fail else 0


func ownership(parent: Node) -> int:
	var tree := parent.get_tree()
	var legacy := BuildingRenderer.new()
	parent.add_child(legacy)
	# 无相机的独立绘制实例，来源列表可独立；不能改全局碰撞缓存来搭测试。
	legacy._districts = [{}, {}, {}]
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	var first := Node.new()
	var second := Node.new()
	parent.add_child(first)
	parent.add_child(second)
	_check(legacy.set_volume_coverage(first, PackedInt32Array([0, 2])), "instance visual mask accepts valid source IDs")
	_check(not legacy.set_volume_coverage(second, PackedInt32Array([1])) and legacy._volume_sources == PackedInt32Array([0, 2]), "second live owner cannot overwrite current visual authority")
	_check(not legacy.set_volume_coverage(first, PackedInt32Array([3])) and legacy._volume_sources == PackedInt32Array([0, 2]), "invalid source rejected atomically")
	first.queue_free()
	await tree.process_frame
	await tree.process_frame
	_check(legacy._volume_sources.is_empty() and legacy._volume_owner_id == 0, "owner signal restores all original building drawing across frame")
	_check(legacy.set_volume_coverage(second, PackedInt32Array([1])), "new live owner can claim after prior exit")
	legacy._clear_volume_coverage(-1)
	_check(legacy._volume_sources == PackedInt32Array([1]), "stale owner cleanup cannot clear replacement coverage")
	_check(var_to_bytes(BuildingRenderer._cache_entries) == collision, "visual mask leaves collision byte-identical")
	legacy.queue_free()
	await tree.process_frame
	second.queue_free()
	await tree.process_frame
	await tree.process_frame
	_check(not is_instance_valid(second), "renderer exits first then owner exits without stale callback")
	print("[R63 coverage ownership] pass=", _pass, " fail=", _fail)
	return 1 if _fail else 0


func _wait(parent: Node, overlay: Node2D) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	await parent.get_tree().process_frame
	while Time.get_ticks_msec() < deadline:
		overlay._process(0.11)
		var state: Dictionary = overlay.debug_state()
		if Session.state_ready(state):
			return true
		if not state.transition_blocked.is_empty() or not state.stream.failures.is_empty():
			_check(false, "canonical transition blocked: " + str(state))
			return false
		await parent.get_tree().process_frame
	_check(false, "canonical ready timeout: " + str(overlay.debug_state()))
	return false


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] R63 canonical lifecycle: " + label)
