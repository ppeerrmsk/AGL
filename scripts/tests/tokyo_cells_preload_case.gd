extends RefCounted
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")
var _pass := 0
var _fail := 0


func run(parent: Node) -> int:
	# 此用例明确验证旧 cells；外层安装包覆盖不能替换被测类型，结束后完整恢复。
	var previous_hlod := {}
	for key: String in ["AGL_TOKYO_HLOD_PACKAGE", "AGL_TOKYO_HLOD_PACKAGE_SHA", "AGL_TOKYO_INSTALLED_TEST"]:
		previous_hlod[key]=OS.get_environment(key)
		OS.set_environment(key, "")
	var previous_volume := OS.get_environment("AGL_TOKYO_VOLUME")
	var previous_variant := OS.get_environment("AGL_TOKYO_CELLS_VARIANT")
	OS.set_environment("AGL_TOKYO_VOLUME", "cells")
	OS.set_environment("AGL_TOKYO_CELLS_VARIANT", "yokohama_joined_coastal")
	_test_states()
	await _handoff(parent)
	await _cancel_pending(parent)
	OS.set_environment("AGL_TOKYO_VOLUME", previous_volume)
	OS.set_environment("AGL_TOKYO_CELLS_VARIANT", previous_variant)
	for key: String in previous_hlod: OS.set_environment(key, previous_hlod[key])
	print("[R61 cells preload] pass=", _pass, " fail=", _fail, " headless=", DisplayServer.get_name() == "headless")
	return _fail


func _test_states() -> void:
	var state := {"desired_cells": 2, "ready_cells": 2, "stream": {"pending": 0, "failures": {}}}
	_check(Session.state_ready(state), "ordinary cells complete without hierarchical fields")
	for changes: Dictionary in [{"ready_cells": 1}, {"ready_cells": 3}, {"desired_cells": 0, "ready_cells": 0},
		{"stream": {}}, {"stream": null}, {"stream": {"pending": 1, "failures": {}}},
		{"stream": {"pending": 0, "failures": {"missing": "archive"}}},
		{"cut_ready": false, "active_cells": 2}, {"active_cells": 2}, {"cut_ready": true}]:
		var broken := state.duplicate(true)
		broken.merge(changes, true)
		_check(not Session.state_ready(broken), "incomplete or ambiguous preload fails closed")
	state.merge({"cut_ready": true, "active_cells": 2})
	_check(Session.state_ready(state), "hierarchy additionally has its complete cut")
	_check(Session.state_ready({"level": 0, "blend": 1.0}), "R4 original gate preserved")
	_check(not Session.state_ready({}) and not Session.state_ready({"level": 0, "blend": 0.5}), "unknown or blending R4 not ready")


func _handoff(parent: Node) -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1600,900)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(view)
	var loading := Node2D.new()
	view.add_child(loading)
	var reference := Session.start(loading, Vector2(-4850,-2580), 0.35)
	if not await _wait_ready(parent, reference):
		view.queue_free()
		return
	var session: Variant = reference.get_ref()
	var overlay: Node2D = session.overlay
	var overlay_id := overlay.get_instance_id()
	var viewport_id: int = overlay._viewport.get_instance_id()
	var stream_id: int = overlay._stream.get_instance_id()
	var paths: PackedStringArray = overlay._stream._wanted.duplicate()
	var ids := {}
	var resources: Array[WeakRef] = []
	for path: String in paths:
		ids[path] = overlay._stream.resource(path).get_instance_id()
		resources.append(weakref(overlay._stream.resource(path)))
	var started: int = overlay._stream.started
	var redraws: int = overlay.redraws
	_check(paths.size() > 0 and overlay.debug_state().ready_cells == overlay.debug_state().desired_cells, "R34 actual desired cells and fixed surfaces ready")
	_check(session.arm() and not session.arm(), "ready handoff arms only once")
	loading.queue_free()
	await parent.get_tree().process_frame
	_check(reference.get_ref() != null, "prepared resources survive loading owner exit")
	var camera := Camera2D.new()
	camera.position = MapBoundary.get_player_start()
	camera.zoom = Vector2.ONE * 0.35
	view.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	var features := MapFeatureRenderer.new()
	view.add_child(features)
	features.setup(camera, Rect2(-20000,-20000,40000,40000))
	_check(features._tokyo_volume == overlay and overlay.get_instance_id() == overlay_id, "MapFeatureRenderer takes exact prepared R34")
	_check(overlay._viewport.get_instance_id() == viewport_id and overlay._stream.get_instance_id() == stream_id, "viewport and stream not recreated")
	_check(Session.take(features,camera) == null, "prepared owner consumed once")
	await parent.get_tree().create_timer(0.25).timeout
	_check(session.status == "retained" and overlay._stream.started == started and overlay.redraws == redraws, "offscreen prepared city retained without loads or redraws")
	camera.position = Vector2(-4850,-2580)
	camera.force_update_scroll()
	session._process(0.11)
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	_check(session.status == "claimed" and Session.state_ready(overlay.debug_state()), "first visible R34 frame owns the complete prepared cells")
	_check(overlay._stream.started == started, "same view does not reload prepared native resources")
	for path: String in paths:
		var resource: Resource = overlay._stream.resource(path)
		_check(resource != null and resource.get_instance_id() == int(ids[path]), "native resource identity survives R34 handoff")
	_check(overlay.debug_state().stream.peak_bytes <= Stream.BUDGET, "native memory budget kept")
	features.hide()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	_check(overlay._stream.summary().cached == 0, "R34 explicit hide releases all cached archives")
	for resource: WeakRef in resources:
		_check(resource.get_ref() == null, "hidden R34 resource actually released")
	var overlay_ref: WeakRef = weakref(overlay)
	var stream_ref: WeakRef = weakref(overlay._stream)
	view.queue_free()
	await _wait_gone(parent, reference)
	await _wait_gone(parent, stream_ref)
	_check(overlay_ref.get_ref() == null, "battle exit frees R34 overlay")


func _cancel_pending(parent: Node) -> void:
	var loading := Node2D.new()
	parent.add_child(loading)
	var reference := Session.start(loading, Vector2(-4850,-2580), 0.35)
	var deadline := Time.get_ticks_msec() + 10000
	var pending := false
	while Time.get_ticks_msec() < deadline:
		var session: Variant = reference.get_ref()
		if typeof(session) != TYPE_OBJECT or not is_instance_valid(session):
			break
		if is_instance_valid(session.overlay) and session.overlay._stream.summary().pending > 0:
			pending = true
			break
		await parent.get_tree().process_frame
	_check(pending, "cancel fixture has actual R34 in-flight load")
	loading.queue_free()
	await _wait_gone(parent, reference)
	deadline = Time.get_ticks_msec() + 10000
	while not Stream._busy.is_empty() and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	_check(Stream._busy.is_empty(), "R34 abandoned load drains global slots")


func _wait_ready(parent: Node, reference: WeakRef) -> bool:
	var deadline := Time.get_ticks_msec() + 17000
	while Time.get_ticks_msec() < deadline:
		var session: Variant = reference.get_ref()
		if typeof(session) != TYPE_OBJECT or not is_instance_valid(session):
			break
		if session.status == "ready":
			_check(DisplayServer.get_name() == "headless" or session.rendered_frames >= 2, "native draw warmup or explicit headless-only evidence")
			return true
		await parent.get_tree().process_frame
	_check(false, "R34 readiness deadline")
	return false


func _wait_gone(parent: Node, reference: WeakRef) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while reference.get_ref() != null and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	_check(reference.get_ref() == null, "terminal owner freed across frame")


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] R61 " + label)
