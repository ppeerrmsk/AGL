extends RefCounted
## R34离线：只增加来源地表，原固定角点/打包法线无损展开并重索引；建筑包不复制。
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Joined := preload("res://scripts/tests/build_tokyo_joined_cells.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Palette := preload("res://scripts/experiments/tokyo_palette.gd")
const SOURCE_HASH := "f889a8e655337b7f477a7233a1e130609604a5edf18577165b93765621c848c2"
const OUT := "res://bench/results/tokyo_r34_cells"
const DEST := "res://resources/maps/tokyo_volume_preview/r34_cells"
const HEIGHT := -0.04
var _fail := 0


static func expand(mesh: ArrayMesh) -> ArrayMesh:
	if mesh.get_surface_count() == 0 or mesh.surface_get_array_index_len(0) == 0:
		return mesh
	assert(mesh.get_surface_count() == 1 and mesh.get_blend_shape_count() == 0)
	var source: Dictionary = mesh.get("_surfaces")[0]
	var format := int(source.format)
	assert((format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0 and source.get("lods", []).is_empty())
	assert(source.get("skin_data", PackedByteArray()).is_empty())
	var vertices := int(source.vertex_count)
	var count := int(source.index_count)
	var ps := RenderingServer.mesh_surface_get_format_vertex_stride(format, vertices)
	var ns := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, vertices)
	var cs := RenderingServer.mesh_surface_get_format_attribute_stride(format, vertices)
	var stride := RenderingServer.mesh_surface_get_format_index_stride(format, vertices)
	var raw: PackedByteArray = source.vertex_data
	var attrs: PackedByteArray = source.attribute_data
	var indices: PackedByteArray = source.index_data
	var positions := PackedByteArray()
	var normals := PackedByteArray()
	var colors := PackedByteArray()
	assert(raw.size() == vertices * (ps + ns) and attrs.size() == vertices * cs and stride in [2, 4])
	for corner in count:
		var id := indices.decode_u16(corner * 2) if stride == 2 else indices.decode_u32(corner * 4)
		assert(id < vertices)
		positions.append_array(raw.slice(id * ps, (id + 1) * ps))
		normals.append_array(raw.slice(vertices * ps + id * ns, vertices * ps + (id + 1) * ns))
		colors.append_array(attrs.slice(id * cs, (id + 1) * cs))
	positions.append_array(normals)
	var expanded := source.duplicate()
	expanded.vertex_data = positions
	expanded.attribute_data = colors
	expanded.vertex_count = count
	expanded.index_count = 0
	expanded.index_data = PackedByteArray()
	expanded.format = format & ~Mesh.ARRAY_FORMAT_INDEX
	var result := ArrayMesh.new()
	result.set("_surfaces", [expanded])
	assert(Indexed.triangles(mesh) == Indexed.triangles(result))
	return result


static func add_clipped(builder: RefCounted, points: PackedVector2Array, rect: Rect2) -> void:
	var polygon := PackedVector3Array()
	for point: Vector2 in points:
		polygon.append(Vector3(point.x, HEIGHT, point.y))
	polygon = Builder.clip_polygon(polygon, 0, rect.position.x, true)
	polygon = Builder.clip_polygon(polygon, 0, rect.end.x, false)
	polygon = Builder.clip_polygon(polygon, 2, rect.position.y, true)
	polygon = Builder.clip_polygon(polygon, 2, rect.end.y, false)
	for n in range(1, polygon.size() - 1):
		var cross_y := (polygon[n] - polygon[0]).cross(polygon[n + 1] - polygon[0]).y
		if cross_y > 0:
			builder.triangle(polygon[0], polygon[n], polygon[n + 1], Color(Palette.PAIRS["95958a"]))
		elif cross_y < 0:
			builder.triangle(polygon[0], polygon[n + 1], polygon[n], Color(Palette.PAIRS["95958a"]))


func run() -> void:
	var source_path := OS.get_environment("AGL_TOKYO_COASTAL_SOURCE")
	if FileAccess.get_sha256(source_path) != SOURCE_HASH:
		_fail += 1
		push_error("Tokyo coastal source digest mismatch")
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var source: Resource = load("res://resources/maps/tokyo_volume_preview/r32_cells/index.res")
	var target: Resource = source.duplicate(true)
	var regional: Dictionary = {}
	for region: String in source.joined_sources:
		regional[region] = load(source.joined_sources[region].index)
	var report := {"source_hash": SOURCE_HASH, "source_triangles": data.triangles,
		"cells": [], "added_triangles": 0, "added_bytes": 0, "area": 0.0, "fail": 0}
	DirAccess.make_dir_recursive_absolute(OUT)
	for entry: Dictionary in target.cells:
		var addition := Geometry.new()
		for surface: Dictionary in data.surfaces:
			var points := Factory._points(surface.triangles)
			for start in range(0, points.size(), 3):
				var triangle := PackedVector2Array([points[start], points[start + 1], points[start + 2]])
				for part: int in entry.part_ids:
					add_clipped(addition, triangle, regional[entry.region].cells[part].bounds)
		var extra: ArrayMesh = addition.mesh()
		var original: Resource = load(entry.fixed)
		var cell: Resource = original.duplicate(false)
		var meshes: Array[ArrayMesh] = [Indexed.pack(Joined.merge_meshes([expand(original.meshes[0]), extra]))]
		cell.meshes = meshes
		cell.geometry_bytes = Builder.mesh_bytes(cell.meshes[0])
		cell.triangles = Indexed.triangles(cell.meshes[0])
		entry.fixed = DEST.path_join(String(entry.fixed).get_file())
		entry.fixed_bytes = cell.geometry_bytes
		entry.fixed_triangles = cell.triangles
		var added: int = cell.triangles - original.triangles
		assert(added == Indexed.triangles(extra) and cell.valid())
		_fail += int(ResourceSaver.save(cell, OUT.path_join(String(entry.fixed).get_file()), ResourceSaver.FLAG_COMPRESS) != OK)
		var vertices: Array = []
		if extra.get_surface_count() > 0:
			for point: Vector3 in extra.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				vertices.append([point.x, point.y, point.z])
		report.cells.append({"id": entry.id, "region": entry.region, "part_ids": entry.part_ids,
			"added_triangles": added, "added_bytes": cell.geometry_bytes - original.geometry_bytes, "vertices": vertices})
		report.added_triangles += added
		report.added_bytes += cell.geometry_bytes - original.geometry_bytes
		report.area += Builder.mesh_area(extra)
	target.source_hash = (source.source_hash + ":" + SOURCE_HASH).sha256_text()
	assert(target.valid())
	_fail += int(ResourceSaver.save(target, OUT.path_join("index.res"), ResourceSaver.FLAG_COMPRESS) != OK)
	report.fail = _fail
	var file := FileAccess.open(OUT.path_join("build_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[Tokyo coastal build] added_triangles=", report.added_triangles, " added_bytes=", report.added_bytes, " area=", report.area, " fail=", _fail)
