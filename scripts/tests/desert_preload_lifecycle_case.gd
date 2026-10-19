extends RefCounted
const Session := preload("res://scripts/rendering/desert_map_preload.gd")
const Formal := preload("res://scripts/rendering/desert_volume_presentation.gd")
var _pass := 0
var _fail := 0

class Features:
	extends Node2D
	var _raster_basemap: RasterBasemapRenderer

class Host:
	extends Node2D
	var camera := Camera2D.new()
	var _map_features: Features
	var _building_renderer: Node2D


func run(parent: Node) -> int:
	var tree := parent.get_tree()
	var saved_meta := {}
	for key: String in ["ugc_map_path", "boss_debug_mode", BenchRunner.VOLUME_EXPERIMENT_META]:
		if tree.has_meta(key):
			saved_meta[key] = tree.get_meta(key)
			tree.remove_meta(key)
	var saved_env := {}
	for key: String in ["AGL_DESERT_VOLUME", "AGL_DESERT_STYLE", "AGL_DESERT_BASEMAP"]:
		saved_env[key] = OS.get_environment(key)
		OS.set_environment(key, "")
	_check(not Session.eligible(tree), "Tokyo and unknown maps do not preload desert")
	tree.set_meta("ugc_map_path", Session.MAP_PATH)
	_check(Session.eligible(tree), "normal desert is eligible")
	OS.set_environment("AGL_DESERT_VOLUME", "2d")
	_check(not Session.eligible(tree), "explicit 2D fallback is preserved")
	OS.set_environment("AGL_DESERT_VOLUME", "")
	OS.set_environment("AGL_DESERT_STYLE", "source")
	_check(not Session.eligible(tree), "source imagery fallback does not load native archive")
	OS.set_environment("AGL_DESERT_STYLE", "")
	var loading := Node.new()
	parent.add_child(loading)
	var ref: WeakRef = Session.start(loading)
	await _wait_ready(parent, ref)
	var session: Variant = ref.get_ref()
	if typeof(session) == TYPE_OBJECT and is_instance_valid(session) and session.status == "ready":
		var ground_ref: WeakRef = weakref(session.ground)
		var root_ref: WeakRef = weakref(session.map_root)
		var source_ref: WeakRef = weakref(session._source)
		var mesh_id: int = session.map_root.mesh.get_instance_id()
		var synchronous := Session.Ground.TacticalContext.build(session.ground.relief)
		var identical := true
		for region: MeshInstance3D in synchronous:
			var staged: MeshInstance3D = session.ground._details.get_node(NodePath(region.name))
			for lod: String in ["context_near_mesh", "context_far_mesh"]:
				var a: ArrayMesh = region.get_meta(lod)
				var b: ArrayMesh = staged.get_meta(lod)
				identical = identical and a.surface_get_arrays(0) == b.surface_get_arrays(0)
			region.free()
		_check(identical and synchronous.size() == 4, "incremental and synchronous builds preserve every near/far vertex, normal and color")
		_check(session.ground._planes.size() == 1 and session.triangles > 0, "all native terrain and route/building geometry prepared")
		_check(session.rendered_frames >= 4 if DisplayServer.get_name() != "headless" else session.headless_frames >= 4,
			"readiness distinguishes real GPU draws from headless resource-only proof")
		_check(session.arm() and not session.arm(), "single-use arm gate")
		loading.queue_free()
		await tree.process_frame
		_check(ref.get_ref() != null, "armed session survives loading scene exit")
		var host := Host.new()
		parent.add_child(host)
		host.add_child(host.camera)
		host._map_features = Features.new()
		host.add_child(host._map_features)
		host._building_renderer = Node2D.new()
		host.add_child(host._building_renderer)
		var source := RasterBasemapRenderer.new()
		host._map_features.add_child(source)
		host._map_features._raster_basemap = source
		source.setup(host.camera, session._source._world_rect, "desert")
		source.set_active(false)
		var presentation := Formal.new()
		host.add_child(presentation)
		presentation.setup_formal(host, false)
		presentation.set_process(false)
		_check(presentation._root_map == root_ref.get_ref() and presentation._satellite_ground == ground_ref.get_ref()
			and presentation._root_map.mesh.get_instance_id() == mesh_id, "formal adapter adopts identical nodes and mesh, no rebuild")
		_check(presentation._satellite_ground._source.get_ref() == source, "native surface rebinds actual battle raster owner")
		_check(presentation.get_meta("desert_preload", {}).get("reused", false), "formal renderer records consumed preload")
		await tree.process_frame
		presentation._satellite_ground.sync(0.11)
		_check(ref.get_ref() == null and source_ref.get_ref() == null, "handoff releases staging viewport and old raster before next consumer tick")
		_check(presentation._satellite_ground._planes.size() == 1, "retired staging source cannot clear active terrain")
		host.queue_free()
		await tree.process_frame
		_check(ground_ref.get_ref() == null and root_ref.get_ref() == null, "battle exit releases transferred map nodes")
	else:
		_check(false, "preloader reaches ready")
		if typeof(session) == TYPE_OBJECT and is_instance_valid(session):
			session.cancel()
		loading.queue_free()
	for cancellation: String in ["owner_exit", "timeout", "mid_build", "ready_exit", "wrong_source"]:
		var owner_node := Node.new()
		parent.add_child(owner_node)
		var cancel_ref: WeakRef = Session.start(owner_node)
		await tree.process_frame
		if cancellation in ["ready_exit", "wrong_source"]:
			await _wait_ready(parent, cancel_ref)
		if cancellation == "mid_build":
			for frame in 100:
				var pending: Variant = cancel_ref.get_ref()
				if typeof(pending) != TYPE_OBJECT or not is_instance_valid(pending) or pending.stage >= 2:
					break
				await tree.process_frame
		if cancellation in ["owner_exit", "mid_build", "ready_exit"]:
			owner_node.queue_free()
		elif cancellation == "wrong_source":
			var candidate: Variant = cancel_ref.get_ref()
			if typeof(candidate) == TYPE_OBJECT and is_instance_valid(candidate):
				candidate.arm()
				OS.set_environment("AGL_DESERT_BASEMAP", "sentinel")
				var target := Node3D.new()
				parent.add_child(target)
				_check(Session.take(parent, target).is_empty(), "source mismatch refuses stale map before normal fallback")
				target.queue_free()
				OS.set_environment("AGL_DESERT_BASEMAP", "")
		else:
			var candidate: Variant = cancel_ref.get_ref()
			if typeof(candidate) == TYPE_OBJECT and is_instance_valid(candidate):
				candidate._deadline = 0
				candidate._process(0.0)
		await tree.process_frame
		await tree.process_frame
		_check(cancel_ref.get_ref() == null, "cancelled session freed across next tick: " + cancellation)
		if is_instance_valid(owner_node):
			owner_node.queue_free()
	await tree.process_frame
	_check(tree.get_nodes_in_group(Session.GROUP).is_empty(), "no persistent preload owner after terminal cases")
	for key: String in ["ugc_map_path", "boss_debug_mode", BenchRunner.VOLUME_EXPERIMENT_META]:
		if tree.has_meta(key):
			tree.remove_meta(key)
		if saved_meta.has(key):
			tree.set_meta(key, saved_meta[key])
	for key: String in saved_env:
		OS.set_environment(key, saved_env[key])
	print("[DesertPreloadLifecycle] pass=%d fail=%d" % [_pass, _fail])
	return _fail


func _wait_ready(parent: Node, ref: WeakRef) -> void:
	var deadline := Time.get_ticks_msec() + 35000
	while Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
		var session: Variant = ref.get_ref()
		if typeof(session) != TYPE_OBJECT or not is_instance_valid(session) or session.status in ["ready", "cancelled"]:
			return


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[DesertPreloadLifecycle] " + label)
