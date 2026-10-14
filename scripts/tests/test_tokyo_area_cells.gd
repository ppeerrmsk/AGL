extends RefCounted
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Signature := preload("res://scripts/tests/tokyo_mesh_signature.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_check(load("res://scripts/tests/build_tokyo_area_cells.gd").can_instantiate(), "area source builder compiles")
	var quad := Geometry.new()
	quad.quad(Vector3.ZERO, Vector3.RIGHT, Vector3(1, 0, 1), Vector3.BACK, Color.RED)
	var mesh := quad.mesh()
	_check(Signature.of_mesh(mesh) == Signature.of_mesh(Indexed.pack(mesh)), "triangle signature expands actual index corners")
	var packed := Indexed.pack(mesh)
	_check(_same_mesh(packed, packed.duplicate()), "indexed native buffers compare equal after resource duplication")
	var blue := Geometry.new()
	blue.quad(Vector3.ZERO, Vector3.RIGHT, Vector3(1, 0, 1), Vector3.BACK, Color.BLUE)
	_check(not _same_mesh(packed, Indexed.pack(blue.mesh())), "native buffer comparison rejects changed colors")
	var path := "res://resources/maps/tokyo_volume_preview/r30_cells/index.res"
	if ResourceLoader.exists(path):
		var current: Resource = load(path)
		var control: Resource = load("res://resources/maps/tokyo_volume_preview/r29_cells/index.res")
		_check(current.valid() and current.source_count == control.source_count and current.source_hash == control.source_hash \
			and current.coverage_rects == control.coverage_rects and current.shadow_cells == control.shadow_cells,
			"all sources coverage and shadow envelopes are preserved")
		var savings := PackedInt64Array([0, 0, 0, 0])
		for id in 16:
			var entry: Dictionary = current.cells[id]
			var old: Dictionary = control.cells[id]
			_check(entry.bounds == old.bounds and entry.content_bounds == old.content_bounds and entry.max_height_px == old.max_height_px,
				"original spatial ownership and height envelope retained")
			_check(_same_mesh(load(old.fixed).meshes[0], load(entry.fixed).meshes[0]), "ground water roads rails exact")
			var previous := -1
			for slot in 7:
				var cell: Resource = ResourceLoader.load(entry.mid.path if slot == 6 else entry.levels[slot].path, "", ResourceLoader.CACHE_MODE_IGNORE)
				var before: Resource = ResourceLoader.load(old.mid.path if slot == 6 else old.levels[slot].path, "", ResourceLoader.CACHE_MODE_IGNORE)
				_check(cell.valid() and cell.source_ids == before.source_ids and cell.height_hash == before.height_hash \
					and cell.detail_counts == before.detail_counts, "native levels keep all IDs heights and detail counts")
				_check(_same_mesh(before.meshes[1], cell.meshes[1]), "tagged buildings exactly unchanged")
				if slot >= 4:
					_check(_same_mesh(before.meshes[0], cell.meshes[0]), "near and middle relief unchanged")
				else:
					var a := Signature.of_mesh(before.meshes[0])
					var b := Signature.of_mesh(cell.meshes[0])
					var roofs_only := true
					for key: PackedByteArray in a:
						if a[key] != b.get(key, 0):
							roofs_only = roofs_only and _upward(key)
					for key: PackedByteArray in b:
						if b[key] != a.get(key, 0):
							roofs_only = roofs_only and _upward(key)
					_check(roofs_only, "only flat roof triangles differ; every wall unchanged")
					savings[slot] += before.triangles - cell.triangles
				var byte_count := Builder.mesh_bytes(cell.meshes[0]) + Builder.mesh_bytes(cell.meshes[1])
				if cell.precision_original != null:
					var original: ArrayMesh = before.precision_original if before.precision_original != null else before.meshes[0]
					_check(_same_mesh(original, cell.precision_original), "full source fallback preserved exactly")
					_check(Indexed.triangles(original) == cell.precision_triangles, "fallback counts actual triangles")
					byte_count += Builder.mesh_bytes(cell.precision_original)
				_check(byte_count == cell.geometry_bytes and cell.triangles == Indexed.triangles(cell.meshes[0]) + Indexed.triangles(cell.meshes[1]),
					"resident original and actual indices fully accounted")
				if slot < 6:
					_check(cell.triangles >= previous, "far package is no heavier than nearer package")
					previous = cell.triangles
		for amount in savings:
			_check(amount > 0, "each far level has actual roof savings")
		print("[Tokyo area savings] ", savings)
	print("[Tokyo area test] pass=", _pass, " fail=", _fail)


static func _same_mesh(a: ArrayMesh, b: ArrayMesh) -> bool:
	# 两端已是原生索引格式，直接比较完整缓冲/索引/AABB，不复用仅支持未索引源的R28转换核验器。
	return a.get_surface_count() == b.get_surface_count() and a.get("_surfaces") == b.get("_surfaces")


static func _upward(key: PackedByteArray) -> bool:
	for corner in 3:
		var normal := Vector3(key.decode_float(corner * 40 + 12), key.decode_float(corner * 40 + 16), key.decode_float(corner * 40 + 20))
		if normal.distance_to(Vector3.UP) > 0.0001:
			return false
	return true


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Tokyo area test] " + label)
