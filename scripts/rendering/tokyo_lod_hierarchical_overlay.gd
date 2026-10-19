extends "res://scripts/rendering/tokyo_hierarchical_overlay.gd"
## 独立中近档原生目录，共用R41完整切面事务，不增加流送器或节点池。
var _lod_catalogs: Dictionary = {}


func _load_archive() -> Resource:
	var original: Resource = super._load_archive()
	if original == null:
		return null
	for variant: String in ["full", "mid"]:
		var path := "res://resources/maps/tokyo_volume_preview/r42_lod_pages/" + variant + "/index.res"
		if not ResourceLoader.exists(path):
			return null
		var catalog: Resource = load(path)
		if catalog == null or not catalog.valid() or catalog.source_hash != original.source_hash or catalog.package_variant != variant:
			return null
		_lod_catalogs[variant] = catalog
	_candidate = "R42"
	return original


func _setup_geometry() -> void:
	super._setup_geometry()
	for catalog: Resource in _lod_catalogs.values():
		for parent: Dictionary in catalog.parents:
			var id := int(parent.parent_id)
			_descriptors[parent.building] = {"id": id, "level": 4,
				"bytes": int(parent.bytes) - int(_archive.cells[id].fixed_bytes), "height_hash": _archive.cells[id].levels[4].height_hash}
			for child: Dictionary in parent.children:
				_register_lod_entry(child)


func _register_lod_entry(entry: Dictionary) -> void:
	_descriptors[entry.path] = {"id": entry.cell_id, "level": 4, "bytes": entry.bytes,
		"height_hash": entry.height_hash, "source_hash": entry.source_hash, "package_variant": entry.package_variant}
	for child: Dictionary in entry.get("children", []):
		_register_lod_entry(child)


func _select_cut(view: Rect2) -> Array[Dictionary]:
	if _level != 4:
		return super._select_cut(view)
	_cut_solves += 1
	var inverse := _city.basis.inverse()
	var camera_ray := inverse * _camera.basis.z
	var light_ray := inverse * _sun.basis.z
	var catalog: Resource = _lod_catalogs["mid" if _relief_active else "full"]
	var query := Cut.choose(catalog.parents, view, _last_canvas, Vector2(_viewport.size) * _screen.scale,
		-Vector2(camera_ray.x, camera_ray.z) / camera_ray.y, -Vector2(light_ray.x, light_ray.z) / light_ray.y)
	_max_solver_usec = maxi(_max_solver_usec, int(query.solver_usec))
	var entries: Array[Dictionary] = []
	entries.assign(query.entries)
	return entries
