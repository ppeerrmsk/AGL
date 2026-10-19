extends RefCounted
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")
var _pass := 0
var _fail := 0


func run(parent: Node) -> int:
	# 独立旧 cells 生命周期夹具不消费外层 HLOD 包；所有出口恢复调用者环境。
	var previous_hlod := {}
	for key: String in ["AGL_TOKYO_HLOD_PACKAGE", "AGL_TOKYO_HLOD_PACKAGE_SHA", "AGL_TOKYO_INSTALLED_TEST"]:
		previous_hlod[key]=OS.get_environment(key)
		OS.set_environment(key, "")
	_fail += await load("res://scripts/tests/tokyo_cells_preload_case.gd").new().run(parent)
	var previous_volume := OS.get_environment("AGL_TOKYO_VOLUME")
	var previous_variant := OS.get_environment("AGL_TOKYO_CELLS_VARIANT")
	OS.set_environment("AGL_TOKYO_VOLUME", "cells")
	OS.set_environment("AGL_TOKYO_CELLS_VARIANT", "yokohama_cluster_stable")
	_check(load("res://scripts/tests/export_tokyo_ground_planes.gd").can_instantiate(), "R47 preserved offline export compiles")
	var view := SubViewport.new()
	view.size = Vector2i(1600, 900)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(view)
	var loading := Node2D.new()
	view.add_child(loading)
	var session_ref: WeakRef = Session.start(loading, Vector2(-5600, -2900), 1.3)
	await _wait_ready(parent, session_ref)
	var session: Variant = session_ref.get_ref()
	if typeof(session) != TYPE_OBJECT or not is_instance_valid(session):
		_check(false, "preload session survived until handoff")
		view.queue_free()
		OS.set_environment("AGL_TOKYO_VOLUME", previous_volume)
		OS.set_environment("AGL_TOKYO_CELLS_VARIANT", previous_variant)
		for key: String in previous_hlod: OS.set_environment(key, previous_hlod[key])
		return _fail
	var overlay_id: int = session.overlay.get_instance_id()
	var viewport_id: int = session.overlay._viewport.get_instance_id()
	var stream_id: int = session.overlay._stream.get_instance_id()
	var paths: PackedStringArray = session.overlay._current_paths.duplicate()
	var native_ids: Dictionary = {}
	var resources: Array[WeakRef] = []
	for path: String in paths:
		native_ids[path] = session.overlay._stream.resource(path).get_instance_id()
		resources.append(weakref(session.overlay._stream.resource(path)))
	var started: int = session.overlay._stream.started
	var redraws: int = session.overlay.redraws
	_check(session.arm(), "ready gate arms exactly one handoff")
	_check(not session.arm(), "handoff cannot be armed twice")
	loading.queue_free()
	await parent.get_tree().process_frame
	_check(session_ref.get_ref() != null, "prepared renderer survives actual loading owner exit")
	var camera := Camera2D.new()
	camera.position = MapBoundary.get_player_start()
	camera.zoom = Vector2.ONE * 1.3
	view.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	var features := MapFeatureRenderer.new()
	view.add_child(features)
	features.setup(camera, Rect2(-20000, -20000, 40000, 40000))
	var overlay: Node2D = features._tokyo_volume
	_check(overlay != null and overlay.get_instance_id() == overlay_id, "real MapFeatureRenderer consumes the same prepared instance")
	_check(overlay._viewport.get_instance_id() == viewport_id and overlay._stream.get_instance_id() == stream_id, "no replacement viewport or resource loader")
	_check(Session.take(features, camera) == null, "prepared renderer cannot be consumed twice")
	await parent.get_tree().create_timer(0.25).timeout
	_check(session.status == "retained" and overlay._current_paths == paths, "sea spawn retains prepared city while offscreen")
	_check(overlay._stream.started == started and overlay.redraws == redraws, "retained city does not load or redraw behind sea")
	camera.position = Vector2(-5600, -2900)
	camera.force_update_scroll()
	session._process(0.11)
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	_check(session.status == "claimed" and overlay._current_paths == paths, "first city entry activates original complete paired cut")
	_check(overlay._stream.started == started, "same first city view does not re-read prepared native packages")
	for path: String in paths:
		_check(overlay._stream.resource(path).get_instance_id() == int(native_ids[path]), "native mesh resource identity survives handoff")
	_check(overlay.debug_state().stream.peak_bytes <= Stream.BUDGET, "preload and handoff stay in the original joint geometry budget")
	features.hide()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	_check(overlay._stream.summary().cached == 0, "explicit map hide clears retained ownership")
	for reference: WeakRef in resources:
		_check(reference.get_ref() == null, "hidden preloaded native resources released")
	var overlay_ref: WeakRef = weakref(overlay)
	var stream_ref: WeakRef = weakref(overlay._stream)
	view.queue_free()
	await _wait_gone(parent, session_ref)
	await _wait_gone(parent, stream_ref)
	_check(overlay_ref.get_ref() == null, "battle source exit releases persistent preloader renderer")

	var abandon := Node2D.new()
	parent.add_child(abandon)
	var abandoned: WeakRef = Session.start(abandon, Vector2(-5600, -2900), 1.3)
	var pending_deadline := Time.get_ticks_msec() + 10000
	var saw_pending := false
	while Time.get_ticks_msec() < pending_deadline:
		var pending_session: Variant = abandoned.get_ref()
		if typeof(pending_session) != TYPE_OBJECT or not is_instance_valid(pending_session):
			break
		if is_instance_valid(pending_session.overlay) and pending_session.overlay._stream.summary().pending > 0:
			saw_pending = true
			break
		await parent.get_tree().process_frame
	_check(saw_pending, "abandon case actually has an in-flight native resource")
	abandon.queue_free()
	await _wait_gone(parent, abandoned)
	var deadline := Time.get_ticks_msec() + 10000
	while not Stream._busy.is_empty() and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	_check(Stream._busy.is_empty(), "abandoned loading drains actual global in-flight slots")
	await _edge_cases(parent)
	await _catalog_identity(parent)
	OS.set_environment("AGL_TOKYO_VOLUME", previous_volume)
	OS.set_environment("AGL_TOKYO_CELLS_VARIANT", previous_variant)
	for key: String in previous_hlod: OS.set_environment(key, previous_hlod[key])
	print("[Tokyo preload lifecycle] pass=", _pass, " fail=", _fail)
	return _fail


func _edge_cases(parent: Node) -> void:
	var loading := Node2D.new()
	parent.add_child(loading)
	var reference: WeakRef = Session.start(loading, Vector2(-5600, -2900), 1.3)
	await _wait_ready(parent, reference)
	var session: Variant = reference.get_ref()
	if typeof(session) != TYPE_OBJECT or not is_instance_valid(session):
		loading.queue_free()
		return
	_check(session.arm(), "variant mismatch fixture is genuinely ready")
	OS.set_environment("AGL_TOKYO_CELLS_VARIANT", "yokohama_cluster_hierarchy")
	var camera := Camera2D.new()
	loading.add_child(camera)
	_check(Session.take(loading, camera) == null and reference.get_ref() == null, "wrong variant is released before a fresh renderer can allocate")
	OS.set_environment("AGL_TOKYO_CELLS_VARIANT", "yokohama_cluster_stable")
	loading.queue_free()
	await parent.get_tree().process_frame
	loading = Node2D.new()
	parent.add_child(loading)
	reference = Session.start(loading, Vector2(-5600, -2900), 1.3)
	await _wait_ready(parent, reference)
	session = reference.get_ref()
	if typeof(session) == TYPE_OBJECT and is_instance_valid(session):
		_check(session.arm(), "expiry fixture has complete native resources")
		session._deadline = Time.get_ticks_msec() - 1
		session._process(0.0)
		await _wait_gone(parent, reference)
	loading.queue_free()
	await parent.get_tree().process_frame
	OS.set_environment("AGL_TOKYO_VOLUME", "")
	loading = Node2D.new()
	parent.add_child(loading)
	reference = Session.start(loading, Vector2(300, -13300), 0.35)
	await _wait_ready(parent, reference)
	session = reference.get_ref()
	if typeof(session) == TYPE_OBJECT and is_instance_valid(session):
		_check(session.overlay.get_script().resource_path.ends_with("tokyo_volume_overlay.gd"), "default R4 uses its original renderer and archive")
		_check(not RenderingServer.frame_post_draw.is_connected(session._after_draw), "warm draw callback is removed when ready")
		loading.queue_free()
		await _wait_gone(parent, reference)
	else:
		loading.queue_free()
	OS.set_environment("AGL_TOKYO_VOLUME", "cells")


func _catalog_identity(parent: Node) -> void:
	for key: String in ["AGL_TOKYO_CANONICAL_CATALOG", "AGL_TOKYO_COVERAGE_PREFIX"]:
		var previous := OS.get_environment(key)
		var loading := Node2D.new()
		parent.add_child(loading)
		var reference: WeakRef = Session.start(loading, Vector2(-5600, -2900), 1.3)
		OS.set_environment(key, previous + "_identity_changed")
		await _wait_gone(parent, reference)
		_check(reference.get_ref() == null, "changed archive identity before begin cancels: " + key)
		OS.set_environment(key, previous)
		loading.queue_free()
		await parent.get_tree().process_frame
		loading = Node2D.new()
		parent.add_child(loading)
		reference = Session.start(loading, Vector2(-5600, -2900), 1.3)
		await _wait_ready(parent, reference)
		var session: Variant = reference.get_ref()
		if typeof(session) == TYPE_OBJECT and is_instance_valid(session):
			_check(session.arm(), "archive mismatch fixture has actually warmed native resources")
			var overlay_ref: WeakRef = weakref(session.overlay)
			var stream_ref: WeakRef = weakref(session.overlay._stream)
			var camera := Camera2D.new()
			loading.add_child(camera)
			OS.set_environment(key, previous + "_identity_changed")
			_check(Session.take(loading, camera) == null and reference.get_ref() == null,
				"changed archive identity cannot claim previously warmed instance: " + key)
			await parent.get_tree().process_frame
			_check(overlay_ref.get_ref() == null and stream_ref.get_ref() == null,
				"rejected archive handoff releases geometry and loader across a frame")
		OS.set_environment(key, previous)
		loading.queue_free()
		await parent.get_tree().process_frame


func _wait_ready(parent: Node, reference: WeakRef) -> void:
	var deadline := Time.get_ticks_msec() + 17000
	while Time.get_ticks_msec() < deadline:
		var session: Variant = reference.get_ref()
		if typeof(session) != TYPE_OBJECT or not is_instance_valid(session):
			break
		if session.status == "ready":
			_check(session.rendered_frames >= 2 or DisplayServer.get_name() == "headless", "real Visual draw callbacks or explicitly headless-only evidence")
			return
		await parent.get_tree().process_frame
	_check(false, "preload reaches complete geometry and warmup gate before deadline")


func _wait_gone(parent: Node, reference: WeakRef) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while reference.get_ref() != null and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	_check(reference.get_ref() == null, "terminal owner is actually freed")


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo preload: " + label)
