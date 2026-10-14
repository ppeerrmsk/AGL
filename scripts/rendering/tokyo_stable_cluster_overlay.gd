extends "res://scripts/rendering/tokyo_cluster_overlay.gd"
## R46：完整覆盖且实际面数不增加时，优先保留已加载或在途的有效切面。
const Reuse := preload("res://scripts/experiments/tokyo_cut_reuse.gd")
var _native_entries: Dictionary = {}
var _layout_entries: Dictionary = {}
var _reuse_current := 0
var _reuse_pending := 0
var _reuse_checks := 0
var _reuse_rejected_faces := 0
var _reuse_rejected_cover := 0
var _max_reuse_usec := 0


func _load_archive() -> Resource:
	var original: Resource = super._load_archive()
	_candidate = "R46"
	return original


func _setup_geometry() -> void:
	super._setup_geometry()
	for parent: Dictionary in _catalog.parents:
		_register_lookup(parent, _native_entries)
		_register_lookup(parent, _layout_entries)
	for variant: String in ["full", "mid"]:
		for parent: Dictionary in _cluster_catalogs[variant].parents:
			_register_lookup(parent, _native_entries)
		for parent: Dictionary in _cluster_parents[variant]:
			_register_lookup(parent, _layout_entries)


func _register_lookup(entry: Dictionary, destination: Dictionary) -> void:
	destination[entry.key] = entry
	for child: Dictionary in entry.get("children", []):
		_register_lookup(child, destination)


func _select_cut(view: Rect2) -> Array[Dictionary]:
	var fresh: Array[Dictionary] = super._select_cut(view)
	if _level not in [4, 5] or fresh.is_empty():
		return fresh
	var start := Time.get_ticks_usec()
	var inverse := _city.basis.inverse()
	var camera_ray := inverse * _camera.basis.z
	var light_ray := inverse * _sun.basis.z
	var context := {"view": view, "canvas": _last_canvas, "logical": Vector2(_viewport.size) * _screen.scale,
		"roof": -Vector2(camera_ray.x, camera_ray.z) / camera_ray.y, "shadow": -Vector2(light_ray.x, light_ray.z) / light_ray.y}
	var parents: Array[Dictionary] = _cluster_parents["mid" if _relief_active else "full"] if _level == 4 else _catalog.parents
	var fresh_paths := Pair.paths(fresh)
	var fresh_faces := Reuse.faces(fresh, context, _native_entries)
	for index in 2:
		var retained: Array[Dictionary] = _current_cut if index == 0 else _planned_cut
		if not _compatible(retained):
			continue
		var paths := Pair.paths(retained)
		if paths == fresh_paths or union_bytes(paths, PackedStringArray(), _descriptors) > Stream.BUDGET:
			continue
		_reuse_checks += 1
		if Reuse.faces(retained, context, _native_entries) > fresh_faces:
			_reuse_rejected_faces += 1
			continue
		if not Reuse.covers(retained, parents, context):
			_reuse_rejected_cover += 1
			continue
		_reuse_current += int(index == 0)
		_reuse_pending += int(index == 1)
		_max_reuse_usec = maxi(_max_reuse_usec, Time.get_ticks_usec() - start)
		return retained.duplicate()
	_max_reuse_usec = maxi(_max_reuse_usec, Time.get_ticks_usec() - start)
	return fresh


func _compatible(entries: Array[Dictionary]) -> bool:
	if entries.is_empty() or entries.size() > 16:
		return false
	for entry: Dictionary in entries:
		if not _layout_entries.has(entry.key) or entry.has("fallback") != (_level == 4):
			return false
		if _level == 4 and entry.package_variant != ("mid" if _relief_active else "full"):
			return false
		var one: Array[Dictionary] = [entry]
		var canonical: Array[Dictionary] = [_layout_entries[entry.key]]
		if Pair.paths(one) != Pair.paths(canonical):
			return false
	return true


func debug_state() -> Dictionary:
	var result := super.debug_state()
	result["reuse_current"] = _reuse_current
	result["reuse_pending"] = _reuse_pending
	result["reuse_checks"] = _reuse_checks
	result["reuse_rejected_faces"] = _reuse_rejected_faces
	result["reuse_rejected_cover"] = _reuse_rejected_cover
	result["max_reuse_usec"] = _max_reuse_usec
	return result
