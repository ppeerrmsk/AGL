extends RefCounted
## 原生完整父包离线导出；AO输入不从屏幕或旧矢量楼体推断。
const REGION := Rect2(-6100, -1300, 400, 400)
const RADIUS := 8.0


static func run(catalog_path: String, output: String, region_name: String = "") -> int:
	var region := region_for(region_name)
	if not region.has_area() or FileAccess.file_exists(output):
		return 1
	var catalog: Resource = load(catalog_path)
	if catalog == null or not catalog.valid():
		return 1
	var rows: Array = []
	var sources: Array = []
	var area := region.grow(RADIUS + 1.0)
	for entry: Dictionary in catalog.configurations.lod5_full:
		var page: Resource = ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if page == null or not page.valid() or FileAccess.get_sha256(entry.path) != entry.sha256 \
				or page.stream_identity() != catalog.descriptors[entry.path].canonical_identity:
			return 1
		sources.append({"path": entry.path, "sha256": entry.sha256})
		for kind in 3:
			var mesh: ArrayMesh = page.meshes[kind]
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for offset in range(0, indices.size(), 3):
					var points: Array = []
					var bounds := Rect2(Vector2(vertices[indices[offset]].x, vertices[indices[offset]].z), Vector2.ZERO)
					var up := true
					for n in 3:
						var id := indices[offset+n]
						var point := vertices[id]
						up = up and normals[id].y > 0.85
						bounds = bounds.expand(Vector2(point.x, point.z))
						points.append([point.x, point.y, point.z])
					if up and bounds.intersects(area, true):
						rows.append({"parent": page.parent_id, "kind": kind, "triangle": offset / 3, "points": points})
	if rows.is_empty():
		return 1
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify({"schema": 1, "bounds": [region.position.x, region.position.y, region.end.x, region.end.y], "radius": RADIUS,
		"catalog_sha256": FileAccess.get_sha256(catalog_path), "collision_sha256": catalog.collision_sha256,
		"configuration": "lod5_full", "sources": sources, "triangles": rows}))
	file.close()
	print("[R64 AO export] native upward triangles=", rows.size(), " verified parents=", sources.size())
	return 0


static func region_for(region_name: String) -> Rect2:
	# 候选必须显式选区；空值保留旧南部烘焙，不因环境影响目录工厂。
	match region_name:
		"", "south":
			return REGION
		"north_density":
			return Rect2(-5600, -3100, 400, 400)
		"west_density":
			return Rect2(-6750, -2400, 400, 400)
		"west_extension_density":
			return Rect2(-7250, -2600, 400, 400)
	return Rect2()
