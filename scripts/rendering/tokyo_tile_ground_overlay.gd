extends "res://scripts/rendering/tokyo_canonical_overlay.gd"
## 复用原地图tick；源退役前同步归还纹理，平移不重建平面/材质。
const TileGround := preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd")
var _tile_ground: RefCounted
var _tile_source: WeakRef
var _tile_retry := 0.0
var _tile_binds := 0
var _tile_releases := 0
var _tile_max_usec := 0
var _tile_peak_faces := 0
var _geometry_transaction := false
var _submission_dirty := false
var _submission_samples := 0
var _submission_peak_snapshot: Dictionary = {}
var _tile_shaders: Dictionary = {}
var _projected_reserved := false
var _full_ground_region := OS.get_environment("AGL_TOKYO_GROUND_FULL_REGION") == "1"
var _shoreline: RefCounted
var _shore_error := ""
var _fixed_atlas: RefCounted
var _fixed_atlas_error := ""


func setup(source: Node2D, camera: Camera2D) -> bool:
	return super.setup(source,camera) and _shore_error.is_empty() and _fixed_atlas_error.is_empty()


func _setup_geometry() -> void:
	super._setup_geometry()
	var directory := OS.get_environment("AGL_TOKYO_SHORELINE")
	if not directory.is_empty():
		_shoreline = preload("res://scripts/rendering/tokyo_shoreline_layer.gd").new()
		if not _shoreline.bind(self,directory) or not _shoreline.start_material_warm(self):
			_shore_error = "shoreline preload rejected"
			_enabled = false
	var fixed_directory := OS.get_environment("AGL_TOKYO_FIXED_ATLAS")
	if not fixed_directory.is_empty():
		_fixed_atlas=preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd").new()
		if not _fixed_atlas.bind(self,fixed_directory):
			_fixed_atlas_error="fixed atlas preload rejected"
			_enabled=false


func _sync_tile_source() -> void:
	var owner: Variant = _source_ref.get_ref() if _source_ref != null else null
	var source: Variant = owner.get("_raster_basemap") if typeof(owner)==TYPE_OBJECT and is_instance_valid(owner) else null
	var previous: Variant = _tile_source.get_ref() if _tile_source != null else null
	if typeof(previous)==TYPE_OBJECT and not is_instance_valid(previous):
		previous = null
	if source == previous:
		return
	_release_tile_ground()
	if typeof(previous)==TYPE_OBJECT and is_instance_valid(previous) and previous.presentation_changing.is_connected(_release_tile_ground):
		previous.presentation_changing.disconnect(_release_tile_ground)
	_tile_source = null
	if typeof(source)==TYPE_OBJECT and is_instance_valid(source) and source is RasterBasemapRenderer:
		_tile_source = weakref(source)
		source.presentation_changing.connect(_release_tile_ground)


func _release_tile_ground() -> void:
	if _tile_ground == null:
		return
	_tile_ground.close()
	_tile_ground = null
	_tile_releases += 1
	_tile_retry = 0.0
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_submission_dirty = true
	if not _geometry_transaction:
		_queue_submission_peak()


func _step_geometry(view: Rect2, scale_value: float, delta: float) -> bool:
	_geometry_transaction = true
	if _fixed_atlas!=null:
		_fixed_atlas.suspend()
	_sync_tile_source()
	var projected_source: Variant = _tile_source.get_ref() if _tile_source!=null else null
	var needs_reserve: bool = typeof(projected_source)==TYPE_OBJECT and is_instance_valid(projected_source) and not projected_source.source_projection.is_empty()
	if needs_reserve and not _projected_reserved:
		if not _stream.reserve_auxiliary(get_instance_id(),RasterBasemapRenderer.PROJECTED_GEOMETRY_RESERVE):
			_deactivate()
			_geometry_transaction = false
			return false
		_projected_reserved = true
	elif not needs_reserve:
		_release_projection_reserve()
	var start := Time.get_ticks_usec()
	if _tile_ground != null:
		if not TileGround.texture_resolved(_tile_ground.source_step,scale_value):
			_release_tile_ground()
		else:
			_tile_ground.suspend_fixed()
	var elapsed := Time.get_ticks_usec()-start
	var changed := super._step_geometry(view,scale_value,delta)
	start = Time.get_ticks_usec()
	_tile_retry -= delta
	var source: Variant = _tile_source.get_ref() if _tile_source != null else null
	if not _active or typeof(source)!=TYPE_OBJECT or not is_instance_valid(source) or not source._active or source._transitioning:
		_release_tile_ground()
	elif _tile_ground != null:
		if not _tile_ground.resume_fixed(self):
			_release_tile_ground()
			changed = true
	elif _tile_retry <= 0.0:
		_tile_retry = 0.1
		var candidate := TileGround.new()
		if _full_ground_region:
			candidate.coverage_bounds = _archive.bounds
		candidate.shader_cache = _tile_shaders
		if candidate.bind(self,source,true,true) and not candidate._nodes.is_empty():
			_tile_ground = candidate
			_tile_binds += 1
			changed = true
		else:
			candidate.close()
	if _fixed_atlas!=null and _fixed_atlas_error.is_empty():
		changed=_fixed_atlas.update(self,scale_value,_active) or changed
	if _shoreline!=null and _shore_error.is_empty():
		var tiles: Array[Rect2] = []
		if _tile_ground!=null:
			tiles.assign(_tile_ground._tiles)
		changed = _shoreline.update(scale_value,tiles,_active) or changed
	elapsed += Time.get_ticks_usec()-start
	_tile_max_usec = maxi(_tile_max_usec,elapsed)
	if PerfBuckets.frame_trace_enabled:
		PerfBuckets.tick("tokyo_tile_ground",elapsed)
	_geometry_transaction = false
	if changed or _submission_dirty:
		_queue_submission_peak()
	return changed


func _deactivate() -> void:
	var previous_transaction := _geometry_transaction
	_geometry_transaction = true
	if _fixed_atlas!=null:
		_fixed_atlas.suspend()
	if _shoreline!=null:
		_shoreline.hide()
	_release_tile_ground()
	_release_projection_reserve()
	super._deactivate()
	_geometry_transaction = previous_transaction
	_submission_dirty = false
	if RenderingServer.frame_pre_draw.is_connected(_record_submission_peak):
		RenderingServer.frame_pre_draw.disconnect(_record_submission_peak)


func _release_projection_reserve() -> void:
	if _projected_reserved and is_instance_valid(_stream):
		_stream.release_auxiliary(get_instance_id())
	_projected_reserved = false


func _exit_tree() -> void:
	_geometry_transaction = true
	if _fixed_atlas!=null:
		_fixed_atlas.close()
		_fixed_atlas=null
	if RenderingServer.frame_pre_draw.is_connected(_record_submission_peak):
		RenderingServer.frame_pre_draw.disconnect(_record_submission_peak)
	if _shoreline!=null:
		_shoreline.close()
		_shoreline = null
	_release_tile_ground()
	_release_projection_reserve()
	super._exit_tree()


func debug_state() -> Dictionary:
	var state := super.debug_state()
	state["fixed_atlas_required"]=OS.get_environment("AGL_TOKYO_FIXED_ATLAS")!=""
	state["fixed_atlas_error"]=_fixed_atlas_error
	state["fixed_atlas"]=_fixed_atlas.stats.duplicate(true) if _fixed_atlas!=null else {}
	state["fixed_atlas_ready"]=_fixed_atlas!=null and _fixed_atlas.warm_ready()
	state["shoreline_required"] = OS.get_environment("AGL_TOKYO_SHORELINE")!=""
	state["shoreline_error"] = _shore_error
	state["shoreline"] = _shoreline.stats.duplicate(true) if _shoreline!=null else {}
	state["tile_ground"] = _tile_ground.stats.duplicate(true) if _tile_ground != null else {}
	state["tile_binds"] = _tile_binds
	state["tile_releases"] = _tile_releases
	state["tile_max_usec"] = _tile_max_usec
	state["tile_peak_faces"] = _tile_peak_faces
	# 原峰包含同一同步事务里临时恢复的地表；保留准备成本，提交门只认事务终态。
	state["max_preparation_triangles"] = int(state.max_transition_triangles)
	state["preparation_peak_snapshot"] = state.peak_snapshot
	state["max_transition_triangles"] = _tile_peak_faces
	state["peak_snapshot"] = _submission_peak_snapshot
	state["submission_peak_samples"] = _submission_samples
	state["peak_metric"] = "final_draw_submission_v1"
	state["tile_shader_programs"] = _tile_shaders.size()
	state["projected_source_reserved"] = _projected_reserved
	if _tile_ground != null:
		state["triangles"] += int(_tile_ground.stats.extra_faces)
	if _shoreline!=null:
		state["triangles"] += int(_shoreline.stats.get("faces",0))
		state["resident_triangles"] += int(_shoreline.stats.get("resident_faces",0))
	if _fixed_atlas!=null:
		state["triangles"]+=int(_fixed_atlas.stats.get("faces",0))
		state["resident_triangles"]+=2*int(_fixed_atlas.stats.get("pooled_nodes",0))
	state["auxiliary_visible_nodes"] = int(state.shoreline.get("visible_nodes",0)) + int(state.tile_ground.get("planes",0))
	state["auxiliary_visible_nodes"]+=int(state.fixed_atlas.get("visible_nodes",0))
	state["auxiliary_visible_nodes"]+=int(state.get("low_wall_visible_nodes",0))
	state["total_visible_nodes"] = int(state.get("visible_nodes",0)) + int(state.auxiliary_visible_nodes)
	state["auxiliary_pooled_nodes"] = int(state.shoreline.get("pooled_nodes",0)) + int(state.tile_ground.get("planes",0))
	state["auxiliary_pooled_nodes"]+=int(state.fixed_atlas.get("pooled_nodes",0))
	state["auxiliary_pooled_nodes"]+=int(state.get("low_wall_pooled_nodes",0))
	state["total_pooled_nodes"] = int(state.get("nodes",0)) + int(state.auxiliary_pooled_nodes)
	state["budget_exceeded"] = int(state.triangles)>240000
	return state


func _queue_submission_peak() -> void:
	_submission_dirty = true
	if _active and not RenderingServer.frame_pre_draw.is_connected(_record_submission_peak):
		RenderingServer.frame_pre_draw.connect(_record_submission_peak,CONNECT_ONE_SHOT)


func _record_submission_peak() -> void:
	var trace := PerfBuckets.frame_trace_enabled
	var start := Time.get_ticks_usec() if trace else 0
	_capture_submission_peak()
	if trace:
		var elapsed := Time.get_ticks_usec()-start
		# 收尾已移出_process调用栈，仍归入地图CPU根桶；子桶只作明细，不重复相加。
		PerfBuckets.tick("tokyo_map_process",elapsed)
		PerfBuckets.tick("tokyo_map_submission",elapsed)


func _capture_submission_peak() -> void:
	if _geometry_transaction:
		return
	if RenderingServer.frame_pre_draw.is_connected(_record_submission_peak):
		RenderingServer.frame_pre_draw.disconnect(_record_submission_peak)
	_submission_dirty = false
	if not _active or not is_instance_valid(_screen) or not _screen.visible:
		return
	var auxiliary := int(_tile_ground.stats.get("extra_faces",0)) if _tile_ground!=null else 0
	if _fixed_atlas!=null:
		auxiliary+=int(_fixed_atlas.stats.get("faces",0))
	if _shoreline!=null:
		auxiliary += int(_shoreline.stats.get("faces",0))
	var faces := auxiliary
	for batch: Dictionary in _batches.values():
		for kind in 3:
			if batch.nodes[kind].visible:
				faces += int(batch.layer_triangles[kind])
	_submission_samples += 1
	if faces<=_tile_peak_faces:
		return
	_tile_peak_faces=faces
	var per_cell: Dictionary = {}
	for id: Variant in _batches:
		var batch: Dictionary = _batches[id]
		var counts := PackedInt32Array()
		for kind in 3:
			counts.append(int(batch.layer_triangles[kind]) if batch.nodes[kind].visible else 0)
		per_cell[id]={"path":batch.path,"submitted":counts}
	_submission_peak_snapshot={"frame":Engine.get_process_frames(),"view":_cull_view,"level":_level,
		"output_scale":float(_viewport.size.y)/_camera.size if is_instance_valid(_camera) else 0.0,
		"canvas_rotation":_last_canvas.get_rotation(),"cells":per_cell,"auxiliary_faces":auxiliary,"faces":faces}
	var source: Variant = _tile_source.get_ref() if _tile_source!=null else null
	_submission_peak_snapshot["ground"]=_tile_ground.stats.duplicate(true) if _tile_ground!=null else {}
	_submission_peak_snapshot["source"]={"active":source._active,"transitioning":source._transitioning,"lod":source._current_lod} if typeof(source)==TYPE_OBJECT and is_instance_valid(source) else {}
