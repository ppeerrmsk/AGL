extends RefCounted
const Coastal := preload("res://scripts/tests/build_tokyo_coastal_cells.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Corners := preload("res://scripts/tests/test_tokyo_indexed_mesh.gd")
var _fail := 0
var _pass := 0


func run() -> void:
	_check(Coastal.expand(ArrayMesh.new()).get_surface_count() == 0, "empty indexed expansion")
	var geometry := Geometry.new()
	Coastal.add_clipped(geometry, PackedVector2Array([Vector2(-1, -1), Vector2(3, -1), Vector2(-1, 3)]), Rect2(0, 0, 1, 1))
	var clipped: ArrayMesh = geometry.mesh()
	_check(absf(Builder.mesh_area(clipped) - 1.0) < 0.00001, "clipped source triangle covers exact owner rectangle")
	_check(clipped.get_aabb().position.y == float(Vector3(0, Coastal.HEIGHT, 0).y), "display depth is not building height")
	var source: Resource = load("res://resources/maps/tokyo_volume_preview/r32_cells/index.res")
	var checker := Corners.new()
	for entry: Dictionary in source.cells:
		var original: ArrayMesh = load(entry.fixed).meshes[0]
		var expanded := Coastal.expand(original)
		_check(checker._same_corners(expanded, original), "ordered native normals positions colors survive expansion")
	for entry: Dictionary in source.cells:
		var mesh: ArrayMesh = load(entry.levels[4].path).meshes[0]
		if mesh.surface_get_array_len(0) > 65535 and mesh.surface_get_array_index_len(0) > 0:
			_check(checker._same_corners(Coastal.expand(mesh), mesh), "large real building package exercises 32 bit raw expansion")
			break
	_check(checker._index_widths.has(2) and checker._index_widths.has(4), "both real native index widths exercised")
	var path := "res://resources/maps/tokyo_volume_preview/r34_cells/index.res"
	if ResourceLoader.exists(path):
		var target: Resource = load(path)
		_check(target.valid() and target.source_count == source.source_count and target.coverage_rects == source.coverage_rects \
			and target.shadow_cells == source.shadow_cells and target.joined_sources == source.joined_sources, "source ownership and shadow depth unchanged")
		_check(target.source_hash == (source.source_hash + ":" + Coastal.SOURCE_HASH).sha256_text(), "addendum provenance enters native index digest")
		var additions := 0
		var added_bytes := 0
		for id in 16:
			var old: Dictionary = source.cells[id]
			var entry: Dictionary = target.cells[id]
			var normalized := entry.duplicate(true)
			for field: String in ["fixed", "fixed_bytes", "fixed_triangles"]:
				normalized[field] = old[field]
			_check(normalized == old, "all seven building paths heights and bounds untouched")
			var before: Resource = load(old.fixed)
			var after: Resource = load(entry.fixed)
			_check(after.valid() and after.bounds == before.bounds and after.source_ids == before.source_ids \
				and after.height_hash == before.height_hash, "fixed package identity retained")
			_check(raw_prefix(before.meshes[0], after.meshes[0]), "old ordered raw vertex normal color bytes unchanged")
			_check(Indexed.triangles(after.meshes[0]) == after.triangles and after.triangles == entry.fixed_triangles \
				and Builder.mesh_bytes(after.meshes[0]) == after.geometry_bytes and after.geometry_bytes == entry.fixed_bytes, "actual indexed bytes and triangles recorded")
			additions += after.triangles - before.triangles
			added_bytes += after.geometry_bytes - before.geometry_bytes
		_check(additions >= 309 and additions < 400 and added_bytes > 0, "new source surfaces present and counted")
		print("[Tokyo coastal test] additions=", additions, " added_bytes=", added_bytes)
	print("[Tokyo coastal test] pass=", _pass, " fail=", _fail)


static func raw_prefix(before: ArrayMesh, after: ArrayMesh) -> bool:
	var a: Dictionary = Coastal.expand(before).get("_surfaces")[0]
	var b: Dictionary = Coastal.expand(after).get("_surfaces")[0]
	var n := int(a.vertex_count)
	var count := int(b.vertex_count)
	if count < n or a.format != b.format:
		return false
	var ps := RenderingServer.mesh_surface_get_format_vertex_stride(int(a.format), n)
	var ns := RenderingServer.mesh_surface_get_format_normal_tangent_stride(int(a.format), n)
	return a.vertex_data.slice(0, n * ps) == b.vertex_data.slice(0, n * ps) \
		and a.vertex_data.slice(n * ps) == b.vertex_data.slice(count * ps, count * ps + n * ns) \
		and a.attribute_data == b.attribute_data.slice(0, a.attribute_data.size())


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Tokyo coastal test] " + message)
