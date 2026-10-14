extends Node
## 单次载入所有者：准备同一份静态地图节点，交接后无常驻缓存或 tick。
const GROUP := &"desert_map_preload"
const MAP_PATH := "res://resources/maps/desert_railway_preview.aglmap"
const Ground := preload("res://scripts/experiments/volume_satellite_ground.gd")
const MapFactory := preload("res://scripts/experiments/volume_map_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Airframes := preload("res://scripts/experiments/volume_aircraft_catalog.gd")
const Mounts := preload("res://scripts/experiments/volume_aircraft_mount_catalog.gd")
const TIMEOUT_MS := 30000
var status := "starting"
var stage := 0
var rendered_frames := 0
var headless_frames := 0
var stage_ms: Array[float] = []
var ground: Node3D
var map_root: MeshInstance3D
var triangles := 0
var _loading_ref: WeakRef
var _viewport: SubViewport
var _source: RasterBasemapRenderer
var _doc: MapDocument
var _deadline := 0
var _selection := ""
var _far_warmed := false
var _context_job: Dictionary = {}
var _catalog_index := 0
var _context_peak_ms := 0.0
var _catalog_peak_ms := 0.0
var _armed_scene_id := 0


static func eligible(tree: SceneTree) -> bool:
	return String(tree.get_meta("ugc_map_path", "")) == MAP_PATH \
		and not tree.has_meta("boss_debug_mode") \
		and not bool(tree.get_meta(BenchRunner.VOLUME_EXPERIMENT_META, false)) \
		and OS.get_environment("AGL_DESERT_VOLUME").strip_edges().to_lower() not in ["0", "false", "off", "2d"] \
		and Ground.TacticalContext.is_enabled("desert")


static func start(owner_node: Node) -> WeakRef:
	if not eligible(owner_node.get_tree()):
		return null
	for old: Node in owner_node.get_tree().get_nodes_in_group(GROUP):
		old.cancel()
	var session: Node = load("res://scripts/rendering/desert_map_preload.gd").new()
	session._loading_ref = weakref(owner_node)
	session._selection = OS.get_environment("AGL_DESERT_BASEMAP")
	owner_node.get_tree().root.add_child.call_deferred(session)
	return weakref(session)


static func take(mode: Node, target: Node3D) -> Dictionary:
	for session: Node in mode.get_tree().get_nodes_in_group(GROUP):
		if session.status != "armed":
			continue
		var features: Variant = mode.get("_map_features")
		var source: Variant = features.get("_raster_basemap") if typeof(features) == TYPE_OBJECT and is_instance_valid(features) else null
		if session._selection != OS.get_environment("AGL_DESERT_BASEMAP") \
				or not Ground.TacticalContext.is_enabled("desert") \
				or typeof(source) != TYPE_OBJECT or not is_instance_valid(source) \
				or not source is RasterBasemapRenderer or not session.ground.rebind_native_source(source):
			session.free()
			return {}
		var result := {"root": session.map_root, "ground": session.ground, "triangles": session.triangles}
		session.ground.reparent(target, false)
		session.map_root.reparent(target, false)
		target.set_meta("desert_preload", {"reused": true, "rendered_frames": session.rendered_frames,
			"headless_frames": session.headless_frames, "stage_ms": session.stage_ms.duplicate(),
			"context_peak_ms": session._context_peak_ms, "catalog_peak_ms": session._catalog_peak_ms})
		session.status = "claimed"
		session.set_process(false)
		session.queue_free()
		return result
	return {}


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1200
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	var owner_node: Variant = _loading_ref.get_ref()
	if typeof(owner_node) != TYPE_OBJECT or not is_instance_valid(owner_node):
		cancel()
		return
	owner_node.tree_exiting.connect(_loading_exited, CONNECT_ONE_SHOT)
	status = "loading"
	RenderingServer.frame_post_draw.connect(_after_draw)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() >= _deadline:
		push_warning("Desert preload timeout; release before normal map fallback")
		cancel()
		return
	if status == "armed":
		var current := get_tree().current_scene
		if current != null and current.get_instance_id() != _armed_scene_id \
				and current.scene_file_path != "res://scenes/survivor_mode.tscn":
			cancel()
		return
	if status == "warming":
		if DisplayServer.get_name() == "headless":
			headless_frames += 1
		var frames := rendered_frames + headless_frames
		if frames >= 2 and not _far_warmed:
			_switch_lod(true)
			_far_warmed = true
		if frames >= 4:
			_switch_lod(false)
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			status = "ready"
			set_process(false)
			print("[Desert preload] ready stages_ms=", stage_ms, " rendered=", rendered_frames, " headless=", headless_frames)
		return
	# 每一阶段先让载入 UI 得到一次更新，不在进入战场后再构图。
	var started := Time.get_ticks_usec()
	match stage:
		0:
			_doc = MapDocument.load_from(MAP_PATH)
			if _doc == null:
				cancel()
				return
			_viewport = SubViewport.new()
			_viewport.size = Vector2i(320, 180)
			_viewport.own_world_3d = true
			_viewport.world_2d = World2D.new()
			_viewport.msaa_3d = Viewport.MSAA_2X
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			add_child(_viewport)
			var camera := Camera2D.new()
			camera.enabled = false
			camera.zoom = Vector2.ONE * 0.05
			_viewport.add_child(camera)
			_source = RasterBasemapRenderer.new()
			_viewport.add_child(_source)
			var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_doc.basemap.meta_path))
			if not _source.setup(camera, Ground.Relief.Archive.source_rect(metadata), "desert"):
				cancel()
				return
			_source.set_active(false)
		1:
			ground = Ground.new()
			_viewport.add_child(ground)
			ground.enable_relief()
		2:
			if _context_job.is_empty():
				_context_job = Ground.TacticalContext.begin_build(ground.relief)
			var complete := Ground.TacticalContext.step_build(_context_job)
			_context_peak_ms = maxf(_context_peak_ms, float(Time.get_ticks_usec() - started) / 1000.0)
			if not complete:
				return
		3:
			ground.setup(_source, _context_job)
			_context_job.clear()
		4:
			var packet := MapFactory.build(_doc, true, true)
			if not packet.get("ok", false):
				cancel()
				return
			triangles = packet.triangles
			map_root = MeshInstance3D.new()
			MapFactory.configure_instance(map_root, packet, Geometry.material())
			_viewport.add_child(map_root)
		5:
			# 使用已有共享目录缓存；不创建飞机、挂载实体或另一套模型。
			var keys := Airframes.supported_keys()
			while _catalog_index < keys.size():
				var key: String = keys[_catalog_index]
				Airframes.build_runtime(key)
				if Airframes.supports_body_lod(key):
					Airframes.build_runtime_lod(key, Airframes.BODY_LOD_MEDIUM)
					Airframes.build_runtime_lod(key, Airframes.BODY_LOD_LOW)
				_catalog_index += 1
				if Time.get_ticks_usec() - started >= 4000:
					break
			_catalog_peak_ms = maxf(_catalog_peak_ms, float(Time.get_ticks_usec() - started) / 1000.0)
			if _catalog_index < keys.size():
				return
			for key: String in Mounts.supported_kinds():
				Mounts.build(key)
		6:
			var sun := DirectionalLight3D.new()
			MapFactory.configure_sun(sun)
			sun.directional_shadow_max_distance = 80000.0
			_viewport.add_child(sun)
			var camera := Camera3D.new()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 80000.0
			camera.far = 150000.0
			camera.position = Vector3(0, 60000, 45000)
			_viewport.add_child(camera)
			camera.look_at(Vector3.ZERO)
			camera.make_current()
			ground.sync(0.0)
			_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			status = "warming"
	stage_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
	stage += 1


func _switch_lod(far: bool) -> void:
	ground._cover_far = far
	for part: MeshInstance3D in ground._details.get_children():
		for prefix: String in ["cover", "context"]:
			if part.has_meta(prefix + "_near_mesh"):
				part.mesh = part.get_meta(prefix + ("_far_mesh" if far else "_near_mesh"))
				if prefix == "context":
					part.set_meta("context_far", far)


func _after_draw() -> void:
	if status == "warming" and _viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) > 0:
		rendered_frames += 1


func progress() -> float:
	return 1.0 if status in ["ready", "armed", "claimed", "cancelled"] else minf(0.9, float(stage) / 8.0)


func arm() -> bool:
	if status != "ready":
		return false
	status = "armed"
	var current := get_tree().current_scene
	_armed_scene_id = current.get_instance_id() if current != null else 0
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	set_process(true)
	return true


func _loading_exited() -> void:
	if status not in ["armed", "claimed"]:
		cancel()


func cancel() -> void:
	status = "cancelled"
	set_process(false)
	queue_free()


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_after_draw):
		RenderingServer.frame_post_draw.disconnect(_after_draw)
