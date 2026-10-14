extends "res://scripts/rendering/tokyo_cells_overlay.gd"
## 候选：同一流送预算内准备完整切面，所有包就绪才一次性替换，节点原位复用。
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
var _catalog: Resource
var _slots: Array[Array] = []
var _target_cut: Array[Dictionary] = []
var _current_cut: Array[Dictionary] = []
var _target_paths := PackedStringArray()
var _current_paths := PackedStringArray()
var _selection_canvas := Transform2D(0, Vector2(INF, INF))
var _selection_size := Vector2i.ZERO
var _selection_sun := Basis()
var _committed_level := -1
var _transition_blocked := ""
var _union_bytes := 0
var _cut_commits := 0
var _cut_solves := 0
var _max_solver_usec := 0
var _max_commit_usec := 0


func _load_archive() -> Resource:
	_catalog = load("res://resources/maps/tokyo_volume_preview/r40_pages/index.res")
	var original: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	if not _catalog.valid() or _catalog.source_hash != original.source_hash:
		return null
	_candidate = "R41"
	_layer_culling = true
	_directional_cull = true
	_exact_view = true
	_tight_depth = true
	_local_depth = true
	_mid_relief = true
	return original


func _setup_geometry() -> void:
	super._setup_geometry()
	_composite.set_shader_parameter("edge_feather", 0.0)
	for parent: Dictionary in _catalog.parents:
		var id := int(parent.parent_id)
		_descriptors[parent.building] = {"id": id, "level": 5,
			"bytes": int(parent.bytes) - int(_archive.cells[id].fixed_bytes), "height_hash": _archive.cells[id].levels[5].height_hash}
		for child: Dictionary in parent.children:
			_register_page(child)
	for slot in 16:
		var nodes: Array = []
		for kind in 3:
			var node := _add_mesh(null, _materials[4 if kind == 2 else kind], kind < 2)
			node.hide()
			nodes.append(node)
		_slots.append(nodes)


func _register_page(entry: Dictionary) -> void:
	_descriptors[entry.path] = {"id": entry.cell_id, "level": 5, "bytes": entry.bytes,
		"height_hash": entry.height_hash, "source_hash": entry.source_hash}
	for child: Dictionary in entry.get("children", []):
		_register_page(child)


func _step_geometry(view_bounds: Rect2, scale_value: float, _delta: float) -> bool:
	var changed := false
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
			_target_cut = _select_cut(view_bounds)
			_target_paths = paths_for(_target_cut)
			_union_bytes = union_bytes(_target_paths, _current_paths, _descriptors)
			_transition_blocked = "complete old/new union exceeds 96MiB" if _union_bytes > Stream.BUDGET else ""
			_stream.request(_target_paths if _transition_blocked.is_empty() else PackedStringArray(), _current_paths)
	if _transition_blocked.is_empty() and (_target_paths != _current_paths or _committed_level != _level):
		var all_ready := true
		for path: String in _target_paths:
			if _stream.resource(path) == null:
				all_ready = false
				break
		if all_ready:
			_commit_cut()
			changed = true
	changed = _apply_precision_guards(scale_value) or changed
	if changed or view_bounds != _cull_view or _camera.basis != _cull_camera or _sun.basis != _cull_light:
		changed = _apply_visibility(view_bounds) or changed
		_cull_view = view_bounds
		_cull_camera = _camera.basis
		_cull_light = _sun.basis
	if _warm_ready_frame < 0 and not _current_cut.is_empty() and _target_paths == _current_paths:
		_warm_ready_frame = Engine.get_process_frames()
	return changed


func _select_cut(view: Rect2) -> Array[Dictionary]:
	_cut_solves += 1
	if _level < 5:
		var roots: Array[Dictionary] = []
		for id: int in _archive.visible_cells(view):
			var cell: Dictionary = _archive.cells[id]
			roots.append({"key": "root_%02d" % id, "parent_id": id, "cell_id": -1,
				"building": _target_entry(cell).path, "fixed": cell.fixed})
		return roots
	var inverse := _city.basis.inverse()
	var camera_ray := inverse * _camera.basis.z
	var light_ray := inverse * _sun.basis.z
	var logical := Vector2(_viewport.size) * _screen.scale
	var query := Cut.choose(_catalog.parents, view, _last_canvas, logical,
		-Vector2(camera_ray.x, camera_ray.z) / camera_ray.y, -Vector2(light_ray.x, light_ray.z) / light_ray.y)
	_max_solver_usec = maxi(_max_solver_usec, int(query.solver_usec))
	var entries: Array[Dictionary] = []
	entries.assign(query.entries)
	return entries


static func paths_for(entries: Array[Dictionary]) -> PackedStringArray:
	var paths := PackedStringArray()
	for entry: Dictionary in entries:
		var items: Array = [entry.path] if entry.has("path") else [entry.fixed, entry.building]
		for path: String in items:
			if path not in paths:
				paths.append(path)
	return paths


static func union_bytes(wanted: PackedStringArray, pins: PackedStringArray, descriptors: Dictionary) -> int:
	var paths := wanted.duplicate()
	var total := 0
	var physical: Dictionary = {}
	for path: String in pins:
		if path not in paths:
			paths.append(path)
	for path: String in paths:
		var descriptor: Dictionary = descriptors.get(path, {"bytes": Stream.BUDGET + 1})
		var parts: Dictionary = descriptor.get("components", {path: descriptor})
		for key: String in parts:
			var amount := int(parts[key].get("bytes", Stream.BUDGET + 1))
			if amount < 0 or (physical.has(key) and int(physical[key]) != amount):
				return Stream.BUDGET + 1
			if not physical.has(key):
				physical[key] = amount
				total += amount
	return total


func _commit_cut() -> void:
	var started := Time.get_ticks_usec()
	PerfBuckets.mark_frame_event("tokyo_cut_commit")
	# 不await，不创建/销毁节点；当前帧结束前全部旧引用由完整新切面替换。
	for id: Variant in _batches.keys():
		_remove_cell(id)
	for n in _target_cut.size():
		var entry: Dictionary = _target_cut[n]
		var building: Resource = _stream.resource(entry.path if entry.has("path") else entry.building)
		var fixed: Resource = building if entry.has("path") else _stream.resource(entry.fixed)
		var nodes: Array = _slots[n]
		var batch := {"nodes": nodes, "building": building, "fixed": fixed, "path": entry.path if entry.has("path") else entry.building,
			"page": entry.has("path"), "level": _level, "precision_guarded": false, "boxes": [], "layer_bounds": [], "layer_triangles": []}
		for kind in 3:
			var mesh: ArrayMesh = fixed.meshes[2 if entry.has("path") else 0] if kind == 2 else building.meshes[kind]
			nodes[kind].mesh = mesh
			nodes[kind].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind < 2 and _level >= (2 if kind == 0 else 1) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			batch.boxes.append(mesh.get_aabb())
			batch.layer_bounds.append(layer_bounds(mesh.get_aabb()))
			batch.layer_triangles.append(Indexed.triangles(mesh))
		_batches[entry.key] = batch
	_current_cut = _target_cut.duplicate()
	_current_paths = _target_paths.duplicate()
	_committed_level = _level
	_stream.request(_target_paths, _current_paths)
	_cut_commits += 1
	binds += _target_cut.size()
	_max_commit_usec = maxi(_max_commit_usec, Time.get_ticks_usec() - started)
	max_bind_usec = _max_commit_usec


func _apply_precision_guards(output_scale: float) -> bool:
	var changed := false
	for batch: Dictionary in _batches.values():
		if batch.page:
			continue
		var building: Resource = batch.building
		var guarded: bool = building.precision_original != null and output_scale > building.precision_max_scale
		if guarded == bool(batch.precision_guarded):
			continue
		var mesh: ArrayMesh = building.precision_original if guarded else building.meshes[0]
		batch.nodes[0].mesh = mesh
		batch.precision_guarded = guarded
		batch.boxes[0] = mesh.get_aabb()
		batch.layer_bounds[0] = layer_bounds(mesh.get_aabb())
		batch.layer_triangles[0] = building.precision_triangles if guarded else Indexed.triangles(mesh)
		_precision_binds += 1
		changed = true
	return changed


func _remove_cell(id: Variant) -> void:
	for node: MeshInstance3D in _batches[id].nodes:
		node.hide()
		node.mesh = null
	_batches.erase(id)


func _deactivate() -> void:
	# 父类按整数根ID清理，层级候选使用字符串key；这里只复用基类合成终态。
	for id: Variant in _batches.keys():
		_remove_cell(id)
	_current_cut.clear()
	_target_cut.clear()
	_current_paths.clear()
	_target_paths.clear()
	_selection_canvas = Transform2D(0, Vector2(INF, INF))
	_transition_blocked = ""
	_committed_level = -1
	if is_instance_valid(_stream):
		_stream.request(PackedStringArray(), PackedStringArray())
	if is_instance_valid(_screen):
		_screen.hide()
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_active = false


func _exit_tree() -> void:
	_deactivate()
	super._exit_tree()


func debug_state() -> Dictionary:
	var triangles := 0
	var resident := 0
	var visible_nodes := 0
	var guarded := 0
	for batch: Dictionary in _batches.values():
		guarded += int(batch.precision_guarded)
		for kind in 3:
			resident += int(batch.get("low_full_triangles",batch.layer_triangles[kind])) if kind == 0 else int(batch.layer_triangles[kind])
			if batch.nodes[kind].visible:
				triangles += int(batch.layer_triangles[kind])
				visible_nodes += 1
	budget_exceeded = triangles > 240000
	var ready := _target_paths == _current_paths and _committed_level == _level and _transition_blocked.is_empty()
	return {"candidate": _candidate, "active": _active, "enabled": _enabled, "level": _level, "committed_level": _committed_level,
		"previous_level": _previous_level, "blend": 1.0, "lod_switches": lod_switches, "redraws": redraws,
		"nodes": _slots.size() * 3, "materials": _materials.size() + 1, "active_cells": _batches.size(),
		"output_size": _viewport.size if is_instance_valid(_viewport) else Vector2i.ZERO, "setup_ms": setup_ms,
		"triangles": triangles, "resident_triangles": resident, "visible_nodes": visible_nodes, "layer_culling": true,
		"counts": [], "max_transition_triangles": peak_triangles, "cull_view": _cull_view,
		"output_scale": float(_viewport.size.y) / _camera.size if is_instance_valid(_camera) else 0.0,
		"mid_relief": _relief_active and _level == 4, "canvas_rotation": _last_canvas.get_rotation(),
		"precision_guarded": guarded, "precision_binds": _precision_binds, "directional_cull": true, "exact_view": true,
		"tight_depth": true, "local_depth": true, "source_max_height": _source_max_height, "depth_max_height": _depth_max_height,
		"camera_near": _camera.near if is_instance_valid(_camera) else 0.0, "camera_far": _camera.far if is_instance_valid(_camera) else 0.0,
		"desired_cells": _target_cut.size(), "ready_cells": _target_cut.size() if ready else 0, "cut_ready": ready,
		"max_bind_usec": max_bind_usec, "binds": binds, "cut_commits": _cut_commits, "cut_solves": _cut_solves,
		"max_solver_usec": _max_solver_usec, "max_commit_usec": _max_commit_usec, "union_bytes": _union_bytes,
		"transition_blocked": _transition_blocked, "peak_snapshot": _peak_snapshot,
		"budget_exceeded": budget_exceeded, "stream": _stream.summary() if is_instance_valid(_stream) else {}}
