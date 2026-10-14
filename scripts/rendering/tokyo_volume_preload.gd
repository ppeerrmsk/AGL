extends Node
## 载入场景的单次预热所有者；同一实例交给战场，不重新读取网格或重建3D视口。
const GROUP := &"tokyo_volume_preload"
const BASE := preload("res://scripts/rendering/tokyo_volume_overlay.gd")
const HLOD := preload("res://scripts/rendering/tokyo_hlod_overlay.gd")
const Installed := preload("res://scripts/rendering/tokyo_installed_map.gd")
const TIMEOUT_MS := 15000
var overlay: Node2D
var status := "starting"
var rendered_frames := 0
var headless_frames := 0
var entry_position := Vector2.ZERO
var entry_zoom := 0.35
var route := ""
var variant := ""
var ao_directory := ""
var component_manifest := ""
var canonical_catalog := ""
var coverage_prefix := ""
var shoreline_directory := ""
var fixed_atlas_directory := ""
var low_wall_manifest := ""
var low_wall_fade := ""
var hlod_package := ""
var hlod_package_sha := ""
var resident_middle := false
var resident_pool_only := false
var loading_ref: WeakRef
var battle_ref: WeakRef
var _stage: SubViewport
var _deadline := 0
var _clock := 0.0
var small_uploads := false
var display_budget := preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").display_limit()
var cache_pool_limit := 96*1024*1024
var resident_foundation := false
var _memory_check_clock := 0.0


static func script_path() -> String:
	if not Installed.package_path().is_empty():
		if OS.get_environment("AGL_TOKYO_STATIC_NATIVE")=="1": return "res://scripts/rendering/tokyo_static_hlod_overlay.gd"
		return "res://scripts/rendering/tokyo_hlod_overlay.gd"
	if OS.get_environment("AGL_TOKYO_VOLUME").to_lower() != "cells":
		return "res://scripts/rendering/tokyo_volume_overlay.gd"
	var variants := {"yokohama_joined_hierarchy": "tokyo_hierarchical_overlay",
		"yokohama_joined_lod_hierarchy": "tokyo_lod_hierarchical_overlay",
		"yokohama_cluster_hierarchy": "tokyo_cluster_overlay",
		"yokohama_cluster_stable": "tokyo_stable_cluster_overlay",
		"yokohama_canonical": "tokyo_canonical_overlay",
		"yokohama_ground": "tokyo_tile_ground_overlay"}
	return "res://scripts/rendering/" + String(variants.get(OS.get_environment("AGL_TOKYO_CELLS_VARIANT"), "tokyo_cells_overlay")) + ".gd"


static func start(owner_node: Node, position: Vector2 = Vector2.INF, zoom: float = -1.0) -> WeakRef:
	var tree := owner_node.get_tree()
	if tree.has_meta("boss_debug_mode") or tree.has_meta("ugc_map_path") or not BASE.default_enabled("tokyo"):
		return null
	for old: Node in tree.get_nodes_in_group(GROUP):
		old.cancel()
	var session: Node = load("res://scripts/rendering/tokyo_volume_preload.gd").new()
	session.loading_ref = weakref(owner_node)
	session.entry_position = MapBoundary.get_player_start() if not position.is_finite() else position
	session.entry_zoom = CameraController.START_ZOOM if zoom <= 0.0 else zoom
	session.route = script_path()
	session.variant = OS.get_environment("AGL_TOKYO_CELLS_VARIANT")
	session.ao_directory = OS.get_environment("AGL_TOKYO_AO_PRELOAD")
	session.component_manifest = OS.get_environment("AGL_TOKYO_COMPONENTS")
	session.canonical_catalog = OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG")
	session.coverage_prefix = OS.get_environment("AGL_TOKYO_COVERAGE_PREFIX")
	session.shoreline_directory = OS.get_environment("AGL_TOKYO_SHORELINE")
	session.fixed_atlas_directory = OS.get_environment("AGL_TOKYO_FIXED_ATLAS")
	session.low_wall_manifest = OS.get_environment("AGL_TOKYO_LOW_WALL_MANIFEST")
	session.low_wall_fade = OS.get_environment("AGL_TOKYO_LOW_WALL_FADE")
	session.hlod_package = Installed.package_path()
	session.hlod_package_sha = Installed.package_sha()
	session.resident_middle = OS.get_environment("AGL_TOKYO_RESIDENT_MIDDLE")=="1"
	session.resident_foundation = OS.get_environment("AGL_TOKYO_RESIDENT_FOUNDATION")=="1"
	session.resident_pool_only = OS.get_environment("AGL_TOKYO_RESIDENCY_POOL_ONLY")=="1"
	session.small_uploads = OS.get_environment("AGL_TOKYO_SMALL_UPLOADS")=="1"
	session.cache_pool_limit = preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").candidate_limit()
	tree.root.add_child.call_deferred(session)
	session.call_deferred("_begin")
	return weakref(session)


static func take(source: Node2D, camera: Camera2D) -> Node2D:
	for session: Node in source.get_tree().get_nodes_in_group(GROUP):
		if session.status == "armed":
			if session.route == script_path() and session.variant == OS.get_environment("AGL_TOKYO_CELLS_VARIANT") \
					and session.hlod_package == Installed.package_path() \
					and session.hlod_package_sha == Installed.package_sha() \
					and session.resident_middle == (OS.get_environment("AGL_TOKYO_RESIDENT_MIDDLE")=="1") \
					and session.resident_foundation == (OS.get_environment("AGL_TOKYO_RESIDENT_FOUNDATION")=="1") \
					and session.resident_pool_only == (OS.get_environment("AGL_TOKYO_RESIDENCY_POOL_ONLY")=="1") \
					and session.small_uploads == (OS.get_environment("AGL_TOKYO_SMALL_UPLOADS")=="1") \
					and session.display_budget == preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").display_limit() \
					and session.cache_pool_limit == preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").candidate_limit() \
					and session.ao_directory == OS.get_environment("AGL_TOKYO_AO_PRELOAD") \
					and session.component_manifest == OS.get_environment("AGL_TOKYO_COMPONENTS") \
					and session.canonical_catalog == OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG") \
					and session.coverage_prefix == OS.get_environment("AGL_TOKYO_COVERAGE_PREFIX") \
					and session.shoreline_directory == OS.get_environment("AGL_TOKYO_SHORELINE") \
					and session.low_wall_manifest == OS.get_environment("AGL_TOKYO_LOW_WALL_MANIFEST") \
					and session.low_wall_fade == OS.get_environment("AGL_TOKYO_LOW_WALL_FADE") \
					and session.fixed_atlas_directory == OS.get_environment("AGL_TOKYO_FIXED_ATLAS"):
				return session._claim(source, camera)
			# 已完成且无在途的错误候选须先同步释放，不能与新实例叠出第二份几何预算。
			session.free()
	return null


func _begin() -> void:
	# 先跨过上一预热拥有者的queue_free，不能让两份预加载同时占用预算。
	await get_tree().process_frame
	if hlod_package!=Installed.package_path() or hlod_package_sha!=Installed.package_sha():
		cancel()
		return
	if display_budget!=preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").display_limit() or cache_pool_limit!=preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").candidate_limit():
		cancel()
		return
	if resident_foundation!=(OS.get_environment("AGL_TOKYO_RESIDENT_FOUNDATION")=="1") \
		or resident_middle!=(OS.get_environment("AGL_TOKYO_RESIDENT_MIDDLE")=="1") \
		or resident_pool_only!=(OS.get_environment("AGL_TOKYO_RESIDENCY_POOL_ONLY")=="1") \
		or small_uploads!=(OS.get_environment("AGL_TOKYO_SMALL_UPLOADS")=="1"):
		cancel()
		return
	# 目录/覆盖旁表与网格清单是一份预载身份，变更时不能沿用旧实例。
	if canonical_catalog != OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG") or coverage_prefix != OS.get_environment("AGL_TOKYO_COVERAGE_PREFIX"):
		cancel()
		return
	if low_wall_manifest != OS.get_environment("AGL_TOKYO_LOW_WALL_MANIFEST") or low_wall_fade != OS.get_environment("AGL_TOKYO_LOW_WALL_FADE"):
		cancel()
		return
	if fixed_atlas_directory!=OS.get_environment("AGL_TOKYO_FIXED_ATLAS"):
		cancel()
		return
	if ao_directory != OS.get_environment("AGL_TOKYO_AO_PRELOAD") or component_manifest != OS.get_environment("AGL_TOKYO_COMPONENTS") or shoreline_directory != OS.get_environment("AGL_TOKYO_SHORELINE"):
		cancel()
		return
	var loading: Variant = loading_ref.get_ref()
	if typeof(loading) != TYPE_OBJECT or not is_instance_valid(loading):
		cancel()
		return
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1200
	loading.tree_exiting.connect(_loading_exited, CONNECT_ONE_SHOT)
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	_stage = SubViewport.new()
	_stage.world_2d = World2D.new()
	var main_view: Viewport = loading.get_viewport()
	var output := main_view.get_visible_rect().size * main_view.get_stretch_transform().get_scale()
	_stage.size = Vector2i(output)
	_stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_stage)
	var source := Node2D.new()
	_stage.add_child(source)
	var camera := Camera2D.new()
	camera.ignore_rotation = false
	camera.position = entry_position
	camera.zoom = Vector2.ONE * entry_zoom * main_view.get_stretch_transform().get_scale()
	_stage.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	var script: Script = load(route)
	if script == null or not script.can_instantiate():
		cancel()
		return
	overlay = script.new()
	overlay.name = "TokyoVolumeMap"
	if overlay is HLOD:
		overlay.loading_neighborhood_on_setup=cache_pool_limit>96*1024*1024
	add_child(overlay)
	if not overlay.setup(source, camera):
		cancel()
		return
	if overlay is HLOD:
		# setup验证包后才知道近景资格；首个process前保留真实出生尺度或旧包预热范围。
		camera.zoom=Vector2.ONE*clampf(camera.zoom.x,0.0973,overlay.preload_max_scale)
		camera.force_update_scroll()
		if cache_pool_limit>96*1024*1024:
			_deadline=Time.get_ticks_msec()+60000
		if route.ends_with("/tokyo_static_hlod_overlay.gd") or cache_pool_limit==preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").COMPLETE_POOL: _deadline=Time.get_ticks_msec()+240000
	# 当前出生点可在样区外；载入期间允许既有地图入口档预热完成，不受两秒画外窗口打断。
	if overlay.debug_state().has("stream"):
		overlay._warm_deadline = _deadline
	status = "loading"
	if not RenderingServer.frame_post_draw.is_connected(_after_draw):
		RenderingServer.frame_post_draw.connect(_after_draw)


func _cut_ready() -> bool:
	if not is_instance_valid(overlay):
		return false
	return state_ready(overlay.debug_state())


static func state_ready(state: Dictionary) -> bool:
	if state.get("static_native_required",false) and not state.get("static_native_ready",false): return false
	if state.get("fixed_atlas_required",false) and (not String(state.get("fixed_atlas_error","")).is_empty() or not state.get("fixed_atlas_ready",false)):
		return false
	if state.get("shoreline_required",false) and (not String(state.get("shoreline_error","")).is_empty() or not state.get("shoreline",{}).get("ready",false)):
		return false
	# 普通cells和分层cut协议不同；就绪由实际完整绑定决定，不以旧包或空字段放行。
	if not String(state.get("ao_error", "")).is_empty():
		return false
	if state.get("ao_required", false) and not state.get("ao_ready", false):
		return false
	if state.has("stream"):
		var stream: Variant = state.stream
		if typeof(stream) != TYPE_DICTIONARY or stream.get("pending", -1) != 0:
			return false
		if not stream.get("residency_ready",true): return false
		var failures: Variant = stream.get("failures")
		if typeof(failures) != TYPE_DICTIONARY or not failures.is_empty():
			return false
		if stream.has("texture_pending"):
			if stream.texture_pending!=0 or not stream.get("texture_failures") is Dictionary or not stream.texture_failures.is_empty():
				return false
		var desired: Variant = state.get("desired_cells")
		var ready: Variant = state.get("ready_cells")
		if typeof(desired) != TYPE_INT or typeof(ready) != TYPE_INT or desired <= 0 or ready != desired:
			return false
		if state.has("cut_ready") or state.has("active_cells"):
			return state.get("cut_ready", false) == true and int(state.get("active_cells", 0)) > 0
		return true
	return int(state.get("level", -1)) >= 0 and float(state.get("blend", 0.0)) >= 1.0


func _after_draw() -> void:
	if status == "warming":
		rendered_frames += 1
		if not shoreline_directory.is_empty() and is_instance_valid(overlay):
			overlay._shoreline.warm_draw()


func _process(delta: float) -> void:
	if status in ["loading","warming"] and cache_pool_limit==preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").COMPLETE_POOL:
		_memory_check_clock-=delta
		if _memory_check_clock<=0.0:
			_memory_check_clock=0.5
			if int(OS.get_memory_info().get("free",0))<1024*1024*1024:
				cancel()
				return
	if status in ["loading", "warming"]:
		if route.ends_with("/tokyo_static_hlod_overlay.gd") and is_instance_valid(overlay) and not overlay._enabled:
			push_warning("Tokyo fixed leaf candidate rejected: "+String(overlay.debug_state().get("fallback","")))
			cancel();return
		if Time.get_ticks_msec() >= _deadline:
			push_warning("Tokyo map preload timed out; release before normal fallback")
			cancel()
			return
		if status == "loading" and _cut_ready():
			status = "warming"
			overlay.set_process(false)
			overlay._screen.hide()
			if low_wall_fade == "1":
				overlay.set_low_wall_full_override(true)
			overlay._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			if not shoreline_directory.is_empty():
				overlay._shoreline.begin_warm()
		if status == "warming":
			# 无头测试只证明资源交接；真实材质预热必须另跑Visual并观察draw回调。
			if DisplayServer.get_name() == "headless":
				headless_frames += 1
				if not shoreline_directory.is_empty():
					overlay._shoreline.warm_draw()
			var shore_ready: bool = shoreline_directory.is_empty() or (overlay._shoreline.warm_mask==7 and overlay._shoreline.material_warm_ready())
			if (rendered_frames >= 2 or headless_frames >= 2) and shore_ready:
				if low_wall_fade == "1":
					overlay.set_low_wall_full_override(false)
				overlay._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
				if RenderingServer.frame_post_draw.is_connected(_after_draw):
					RenderingServer.frame_post_draw.disconnect(_after_draw)
				status = "ready"
				set_process(false)
	elif status == "armed":
		if Time.get_ticks_msec() >= _deadline:
			cancel()
	elif status == "retained":
		_clock -= delta
		if _clock > 0.0:
			return
		_clock = 0.1
		var source: Variant = battle_ref.get_ref()
		if typeof(source) != TYPE_OBJECT or not is_instance_valid(source):
			cancel()
			return
		if _intersects(source):
			_activate()


func arm() -> bool:
	if status != "ready":
		return false
	status = "armed"
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	set_process(true)
	return true


func _claim(source: Node2D, camera: Camera2D) -> Node2D:
	assert(status == "armed" and _cut_ready())
	if overlay is HLOD:
		overlay.release_loading_neighborhood()
	battle_ref = weakref(source)
	overlay._source_ref = weakref(source)
	overlay._camera_ref = weakref(camera)
	source.tree_exiting.connect(cancel, CONNECT_ONE_SHOT)
	source.visibility_changed.connect(_visibility_changed)
	_stage.queue_free()
	_stage = null
	status = "retained"
	_clock = 0.0
	set_process(true)
	if _intersects(source):
		_activate()
	return overlay


func _intersects(source: Node2D) -> bool:
	var view := source.get_viewport()
	var inverse := view.get_canvas_transform().affine_inverse()
	var size := view.get_visible_rect().size
	var bounds := Rect2(inverse * Vector2.ZERO, Vector2.ZERO)
	for corner: Vector2 in [Vector2(size.x, 0), size, Vector2(0, size.y)]:
		bounds = bounds.expand(inverse * corner)
	return source.is_visible_in_tree() and overlay._presentation_bounds().intersects(bounds)


func _activate() -> void:
	status = "claimed"
	overlay._active = false
	overlay.set_process(true)
	overlay._process(0.0)
	set_process(false)


func _visibility_changed() -> void:
	var source: Variant = battle_ref.get_ref()
	if typeof(source) != TYPE_OBJECT or not is_instance_valid(source):
		cancel()
	elif not source.is_visible_in_tree():
		overlay._deactivate()
		overlay.set_process(true)
		status = "claimed"
		set_process(false)


func _loading_exited() -> void:
	if status not in ["armed", "retained", "claimed"]:
		cancel()


func cancel() -> void:
	if status == "cancelled":
		return
	status = "cancelled"
	set_process(false)
	if is_instance_valid(overlay):
		overlay._deactivate()
		overlay.set_process(false)
	queue_free()


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_after_draw):
		RenderingServer.frame_post_draw.disconnect(_after_draw)


func progress() -> float:
	if status in ["ready", "armed", "retained", "claimed"]:
		return 1.0
	if status == "warming":
		return 0.95
	if is_instance_valid(overlay):
		var state: Dictionary = overlay.debug_state()
		if state.has("stream"):
			var paths: PackedStringArray = overlay._stream._wanted
			var ready := 0
			for path: String in paths:
				ready += int(overlay._stream.resource(path) != null)
			return 0.9 * float(ready) / maxi(1, paths.size())
	return 0.0
