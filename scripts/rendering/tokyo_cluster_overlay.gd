extends "res://scripts/rendering/tokyo_lod_hierarchical_overlay.gd"
## R45：备用原形先到齐才启用概括；近景即时整组回退，超内存时先原形换区。
const Pair := preload("res://scripts/experiments/tokyo_cluster_cut.gd")
var _cluster_catalogs: Dictionary = {}
var _cluster_parents: Dictionary = {}
var _planned_cut: Array[Dictionary] = []
var _phase := "target"
var _instant_restores := 0
var _stage_commits := 0
var _trim_commits := 0


func _load_archive() -> Resource:
	var original: Resource = super._load_archive()
	if original == null:
		return null
	for variant: String in ["full", "mid"]:
		var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r44_lod_pages/" + variant + "/index.res")
		if catalog == null or not catalog.valid() or catalog.source_hash != original.source_hash or catalog.package_variant != variant:
			return null
		_cluster_catalogs[variant] = catalog
	_candidate = "R45"
	return original


func _setup_geometry() -> void:
	super._setup_geometry()
	for variant: String in ["full", "mid"]:
		var catalog: Resource = _cluster_catalogs[variant]
		for parent: Dictionary in catalog.parents:
			var id := int(parent.parent_id)
			_descriptors[parent.building] = {"id": id, "level": 4,
				"bytes": int(parent.bytes) - int(_archive.cells[id].fixed_bytes), "height_hash": _archive.cells[id].levels[4].height_hash}
			for child: Dictionary in parent.children:
				_register_lod_entry(child)
		var parents: Array[Dictionary] = []
		for id in 16:
			parents.append(Pair.decorate(catalog.parents[id], _catalog.parents[id], _descriptors))
		_cluster_parents[variant] = parents


func _select_cut(view: Rect2) -> Array[Dictionary]:
	if _level != 4:
		return super._select_cut(view)
	_cut_solves += 1
	var inverse := _city.basis.inverse()
	var camera_ray := inverse * _camera.basis.z
	var light_ray := inverse * _sun.basis.z
	var query := Cut.choose(_cluster_parents["mid" if _relief_active else "full"], view, _last_canvas,
		Vector2(_viewport.size) * _screen.scale, -Vector2(camera_ray.x, camera_ray.z) / camera_ray.y,
		-Vector2(light_ray.x, light_ray.z) / light_ray.y)
	_max_solver_usec = maxi(_max_solver_usec, int(query.solver_usec))
	var entries: Array[Dictionary] = []
	entries.assign(query.entries)
	return entries


func _step_geometry(view: Rect2, scale_value: float, _delta: float) -> bool:
	var changed := false
	# 每帧先处理尺度越界，不等待10Hz选档或任何新加载。
	if _is_cluster(_current_cut) and scale_value > Pair.MAX_SCALE:
		_restore_original()
		_selection_canvas = Transform2D(0, Vector2(INF, INF))
		_lod_clock = 0.0
		changed = true
	if _lod_clock <= 0.0:
		_lod_clock = 0.1
		var next := Archive.choose_level(_level, scale_value)
		var relief := relief_enabled(_relief_active, scale_value)
		if next != _level or relief != _relief_active or _selection_canvas != _last_canvas \
				or _selection_size != _viewport.size or _selection_sun != _sun.basis:
			_previous_level = _level
			lod_switches += int(next != _level)
			_level = next
			_relief_active = relief
			_selection_canvas = _last_canvas
			_selection_size = _viewport.size
			_selection_sun = _sun.basis
			_planned_cut = _select_cut(view)
			changed = _prepare_target(view) or changed
	if _transition_blocked.is_empty() and (_target_paths != _current_paths or _committed_level != _level):
		var ready := true
		for path: String in _target_paths:
			if _stream.resource(path) == null:
				ready = false
				break
		if ready:
			_bind_target(5 if _phase == "stage" else _level)
			changed = true
			if _phase == "stage":
				_stage_commits += 1
				_prepare_target(view)
	changed = _apply_precision_guards(scale_value) or changed
	if changed or view != _cull_view or _camera.basis != _cull_camera or _sun.basis != _cull_light:
		changed = _apply_visibility(view) or changed
		_cull_view = view
		_cull_camera = _camera.basis
		_cull_light = _sun.basis
	if _warm_ready_frame < 0 and not _current_cut.is_empty() and _target_paths == _current_paths and _phase == "target":
		_warm_ready_frame = Engine.get_process_frames()
	return changed


func _prepare_target(view: Rect2) -> bool:
	var restored := false
	var available: int = _stream.geometry_budget()
	_phase = "target"
	_target_cut = _planned_cut.duplicate()
	_target_paths = Pair.paths(_target_cut)
	_union_bytes = union_bytes(_target_paths, _current_paths, _descriptors)
	if union_bytes(_target_paths, PackedStringArray(), _descriptors) > available:
		_transition_blocked = "candidate and original fallback alone exceed 96MiB"
		_stream.request(PackedStringArray(), _current_paths)
		return false
	if _union_bytes > available:
		restored = _trim_current(view)
		_union_bytes = union_bytes(_target_paths, _current_paths, _descriptors)
	if _union_bytes > available and _is_cluster(_current_cut):
		_restore_original()
		restored = true
		_union_bytes = union_bytes(_target_paths, _current_paths, _descriptors)
	if _union_bytes > available and _is_cluster(_target_cut):
		_phase = "stage"
		_target_cut = Pair.original_cut(_planned_cut)
		_target_paths = paths_for(_target_cut)
		_union_bytes = union_bytes(_target_paths, _current_paths, _descriptors)
	_transition_blocked = "complete old/new/fallback union exceeds shared geometry allowance" if _union_bytes > available else ""
	_stream.request(_target_paths if _transition_blocked.is_empty() else PackedStringArray(), _current_paths)
	return restored


func _trim_current(view: Rect2) -> bool:
	_apply_visibility(view)
	var inverse := _city.basis.inverse()
	var camera_ray := inverse * _camera.basis.z
	var light_ray := inverse * _sun.basis.z
	var roof := -Vector2(camera_ray.x, camera_ray.z) / camera_ray.y
	var shadow := -Vector2(light_ray.x, light_ray.z) / light_ray.y
	var retained: Array[Dictionary] = []
	for entry: Dictionary in _current_cut:
		var seen := false
		for node: MeshInstance3D in _batches[entry.key].nodes:
			seen = seen or node.visible
		seen = seen or Pair.fallback_visible(entry, view, _last_canvas, Vector2(_viewport.size) * _screen.scale, roof, shadow)
		if seen:
			retained.append(entry)
		else:
			_remove_cell(entry.key)
	if retained.size() == _current_cut.size():
		return false
	_current_cut = retained
	_current_paths = Pair.paths(retained)
	_stream.request(_current_paths, _current_paths)
	_cut_commits += 1
	_trim_commits += 1
	return true


func _restore_original() -> void:
	assert(_is_cluster(_current_cut))
	var saved_cut := _target_cut
	var saved_paths := _target_paths
	_target_cut = Pair.original_cut(_current_cut)
	_target_paths = paths_for(_target_cut)
	for path: String in _target_paths:
		assert(_stream.resource(path) != null, "visible cluster must already own its complete original fallback")
	_bind_target(5)
	_target_cut = saved_cut
	_target_paths = saved_paths
	# 先释放概括几何，再为新目标预留；未完成的旧请求仍由Stream计入reserved并排空。
	_stream.request(_current_paths, _current_paths)
	_instant_restores += 1


func _bind_target(actual_level: int) -> void:
	var desired_level := _level
	_level = actual_level
	super._commit_cut()
	_level = desired_level


static func _is_cluster(entries: Array[Dictionary]) -> bool:
	return not entries.is_empty() and entries[0].has("fallback")


func _deactivate() -> void:
	_planned_cut.clear()
	_phase = "target"
	super._deactivate()


func debug_state() -> Dictionary:
	var result := super.debug_state()
	result["cluster_active"] = _is_cluster(_current_cut)
	result["cluster_phase"] = _phase
	result["instant_restores"] = _instant_restores
	result["stage_commits"] = _stage_commits
	result["trim_commits"] = _trim_commits
	result["fallback_paths"] = paths_for(Pair.original_cut(_current_cut)).size() if _is_cluster(_current_cut) else 0
	result.cut_ready = bool(result.cut_ready) and _phase == "target"
	return result
