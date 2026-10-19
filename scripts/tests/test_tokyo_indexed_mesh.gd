extends RefCounted
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
var _pass := 0
var _fail := 0
var _index_widths: Dictionary = {}


func run() -> void:
	_check(Indexed.triangles(Indexed.pack(ArrayMesh.new())) == 0, "empty mesh remains empty")
	var geometry := Geometry.new()
	geometry.quad(Vector3.ZERO, Vector3.RIGHT, Vector3(1, 0, 1), Vector3.BACK, Color.RED)
	geometry.quad(Vector3.ZERO, Vector3.UP, Vector3(1, 1, 0), Vector3.RIGHT, Color.BLUE)
	var original: ArrayMesh = geometry.mesh()
	var packed := Indexed.pack(original)
	_check(packed.surface_get_array_len(0) < original.surface_get_array_len(0), "shared triangle vertices are reused")
	_check(Indexed.triangles(packed) == 4 and packed.surface_get_array_index_len(0) == 12,
		"triangle telemetry uses index corners rather than unique vertices")
	_check(_same_corners(original, packed), "position normal and color survive exact indexed expansion")
	var single := Geometry.new()
	single.triangle(Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, Color.RED)
	var single_mesh: ArrayMesh = single.mesh()
	_check(Indexed.pack(single_mesh) == single_mesh, "unshared tiny mesh avoids index overhead")
	var path := "res://resources/maps/tokyo_volume_preview/r28_cells/index.res"
	if ResourceLoader.exists(path):
		var source: Resource = load("res://resources/maps/tokyo_volume_preview/r26b_cells/index.res")
		var target: Resource = load(path)
		_check(target.valid() and target.source_count == source.source_count and target.source_hash == source.source_hash,
			"indexed archive retains source identity")
		for id in 16:
			var old: Dictionary = source.cells[id]
			var entry: Dictionary = target.cells[id]
			for slot in range(-1, 7):
				var before_path: String = old.fixed if slot == -1 else (old.mid.path if slot == 6 else old.levels[slot].path)
				var after_path: String = entry.fixed if slot == -1 else (entry.mid.path if slot == 6 else entry.levels[slot].path)
				var before: Resource = ResourceLoader.load(before_path, "", ResourceLoader.CACHE_MODE_IGNORE)
				var after: Resource = ResourceLoader.load(after_path, "", ResourceLoader.CACHE_MODE_IGNORE)
				_check(after.valid() and after.source_ids == before.source_ids and after.height_hash == before.height_hash \
					and after.detail_counts == before.detail_counts and after.bounds == before.bounds,
					"all seven packages preserve source heights and detail classifications")
				var byte_count := 0
				var triangle_count := 0
				for kind in before.meshes.size():
					_check(_same_corners(before.meshes[kind], after.meshes[kind]), "native ordered corners exactly preserved")
					byte_count += Builder.mesh_bytes(after.meshes[kind])
					triangle_count += Indexed.triangles(after.meshes[kind])
				if before.precision_original != null:
					_check(after.precision_original != null and _same_corners(before.precision_original, after.precision_original),
						"resident original fallback retains exact corners")
					byte_count += Builder.mesh_bytes(after.precision_original)
					_check(Indexed.triangles(after.precision_original) == before.precision_triangles, "fallback counts actual indexed triangles")
				_check(triangle_count == before.triangles and after.triangles == before.triangles,
					"compression does not disguise unchanged submitted triangles")
				_check(byte_count == after.geometry_bytes and byte_count <= before.geometry_bytes,
					"byte accounting includes indices and original fallback")
		_check(_index_widths.has(2) and _index_widths.has(4), "native packages exercise both 16 and 32 bit indices")
	print("[Tokyo indexed test] pass=", _pass, " fail=", _fail, " index_widths=", _index_widths)


func _same_corners(original: ArrayMesh, packed: ArrayMesh) -> bool:
	if original.get_surface_count() == 0:
		return packed.get_surface_count() == 0
	if packed.get_surface_count() != 1 or original.get_aabb() != packed.get_aabb():
		return false
	var a := original.surface_get_arrays(0)
	var b := packed.surface_get_arrays(0)
	var indices := PackedInt32Array()
	if b[Mesh.ARRAY_INDEX] != null:
		indices = b[Mesh.ARRAY_INDEX]
	if not indices.is_empty():
		var data: Dictionary = packed.get("_surfaces")[0]
		var width: int = data.index_data.size() / indices.size()
		_index_widths[width] = int(_index_widths.get(width, 0)) + 1
	var count: int = indices.size() if not indices.is_empty() else b[Mesh.ARRAY_VERTEX].size()
	if count != a[Mesh.ARRAY_VERTEX].size():
		return false
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
		for corner in count:
			var index: int = indices[corner] if not indices.is_empty() else corner
			if index < 0 or index >= b[channel].size() or a[channel][corner] != b[channel][index]:
				return false
	return true


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL indexed mesh: ", message)
