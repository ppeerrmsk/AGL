extends RefCounted
## 离线读取完整规范父包；镜头无关，不创建节点或触碰碰撞权威。
const REGION := Rect2(-6150, -1700, 700, 1350)
const SOURCE := "res://resources/maps/yokohama_buildings.json"
const INDEX := "res://resources/maps/tokyo_volume_preview/r34_cells/index.res"


static func run(out: String) -> int:
	if DirAccess.dir_exists_absolute(out):
		push_error("Canonical roof export cannot overwrite prior evidence")
		return 1
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not raw is Dictionary or not raw.get("districts") is Array:
		push_error("Canonical roof export: invalid gameplay district schema")
		return 1
	var buildings: Array = raw.districts
	var accepted: Array = []
	var expected: Array = []
	var heights: Dictionary = {}
	var index: Resource = load(INDEX)
	for building: Dictionary in buildings:
		var entry: Variant = BuildingRenderer._build_entry_static(building)
		if not entry is Dictionary or entry.is_empty():
			continue
		var id := accepted.size()
		accepted.append(entry)
		if not REGION.encloses(entry.bbox) or not index.bounds.encloses(entry.bbox):
			continue
		var points: Array = []
		for point: Vector2 in entry.footprint:
			points.append([point.x, point.y])
		var height := float(entry.max_real_h) * CombatUnit.PIXELS_PER_METER
		heights[roundi(height * 1000)] = true
		expected.append({"source_id": id, "height": height, "points": points})
	if expected.size() != 48:
		push_error("Canonical roof source selection drift")
		return 1
	DirAccess.make_dir_recursive_absolute(out)
	var configurations: Array[Dictionary] = []
	for level in 4:
		for guarded in [false, true]:
			configurations.append({"name": "lod%d_%s" % [level, "guarded" if guarded else "full"], "level": level, "guarded": guarded})
	for variant: String in ["full", "mid"]:
		configurations.append({"name": "lod4_" + variant, "level": 4, "guarded": false, "variant": variant})
	configurations.append({"name": "lod5_full", "level": 5, "guarded": false})
	var manifest: Array = []
	for config: Dictionary in configurations:
		var catalog: Resource = null
		if int(config.level) == 4:
			catalog = load("res://resources/maps/tokyo_volume_preview/r44_lod_pages/%s/index.res" % config.variant)
		elif int(config.level) == 5:
			catalog = load("res://resources/maps/tokyo_volume_preview/r40_pages/index.res")
		var meshes: Array = []
		var roofs: Array = []
		var parents: Array = []
		for parent_id in 16:
			var cell: Dictionary = index.cells[parent_id]
			var path: String = catalog.parents[parent_id].building if catalog != null else cell.levels[int(config.level)].path
			var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var bounds: Rect2 = cell.bounds
			parents.append({"parent_id": parent_id, "path": path, "bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]})
			for kind in 2:
				var guarded: bool = bool(config.guarded) and kind == 0 and resource.precision_original != null
				var mesh: ArrayMesh = resource.precision_original if guarded else resource.meshes[kind]
				var descriptor := {"id": meshes.size(), "parent_id": parent_id, "batch": "parent_%02d" % parent_id,
					"path": path, "kind": kind, "mesh_path": mesh.resource_path, "page": false,
					"precision_guarded": guarded, "source_sha256": FileAccess.get_sha256(path), "surfaces": []}
				_extract(mesh, descriptor, heights, roofs)
				meshes.append(descriptor)
		var data := {"schema": 1, "pose": manifest.size(), "configuration": config, "parents": parents,
			"expected": expected, "meshes": meshes, "native": roofs, "camera_independent": true,
			"collision_sha256": var_to_bytes(accepted).hex_encode().sha256_text(), "game_source_sha256": FileAccess.get_sha256(SOURCE)}
		var destination: String = out.path_join(str(config.name) + ".json")
		var file := FileAccess.open(destination, FileAccess.WRITE)
		file.store_string(JSON.stringify(data))
		file.close()
		manifest.append({"configuration": config, "file": str(config.name) + ".json", "sha256": FileAccess.get_sha256(destination), "native": roofs.size()})
		print("[Tokyo canonical roofs] ", config.name, " parents=16 meshes=", meshes.size(), " roofs=", roofs.size(), " districts=", expected.size())
	var file := FileAccess.open(out.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"configurations": manifest, "game_source_sha256": FileAccess.get_sha256(SOURCE)}))
	file.close()
	return 0


static func _extract(mesh: ArrayMesh, descriptor: Dictionary, heights: Dictionary, roofs: Array) -> void:
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		descriptor.surfaces.append(var_to_bytes(arrays).hex_encode().sha256_text())
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0, count, 3):
			var ids := PackedInt32Array()
			for n in 3:
				ids.append(indices[offset+n] if not indices.is_empty() else offset+n)
			var height := vertices[ids[0]].y
			if not heights.has(roundi(height * 1000)):
				continue
			var valid := true
			for id in ids:
				valid = valid and vertices[id].y == height and normals[id].y > 0.99
			if not valid:
				continue
			var points: Array = []
			var tint: Array = []
			var normal_data: Array = []
			for id in ids:
				points.append([vertices[id].x, vertices[id].z])
				tint.append([colors[id].r, colors[id].g, colors[id].b, colors[id].a])
				normal_data.append([normals[id].x, normals[id].y, normals[id].z])
			roofs.append({"mesh": descriptor.id, "surface": surface, "triangle": offset / 3, "height": height,
				"points": points, "colors": tint, "normals": normal_data})
