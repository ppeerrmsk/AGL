extends RefCounted
const Palette := preload("res://scripts/experiments/tokyo_palette.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_check(Palette.recolor(ArrayMesh.new()).get_surface_count() == 0, "empty remains empty")
	var geometry := Geometry.new()
	var colors := Palette.PAIRS.keys()
	colors.append_array(["919a98", "747c79", "ffffff", "010203"])
	for index in colors.size():
		var color := Color(String(colors[index]))
		color.a = 0.0 if index % 2 == 0 else 1.0
		geometry.quad(Vector3(index * 2, 0, 0), Vector3(index * 2 + 1, 0, 0), Vector3(index * 2 + 1, 0, 1), Vector3(index * 2, 0, 1), color)
	var mesh: ArrayMesh = geometry.mesh()
	var untouched: Array = mesh.get("_surfaces").duplicate(true)
	_check(_same_geometry_and_palette(mesh, Palette.recolor(mesh)), "unindexed palette and alpha preserved")
	_check(mesh.get("_surfaces") == untouched, "source mesh is never mutated")
	var packed := Indexed.pack(mesh)
	var north_builder := preload("res://scripts/tests/build_tokyo_north_palette.gd")
	_check(north_builder.geometry_equal(packed,Palette.recolor(packed)), "north geometry guard permits RGB only")
	var damaged: Dictionary = packed.get("_surfaces")[0].duplicate(true)
	var attributes: PackedByteArray = damaged.attribute_data
	attributes[3]=255-attributes[3]
	damaged.attribute_data=attributes
	var changed_alpha := ArrayMesh.new()
	changed_alpha.set("_surfaces",[damaged])
	_check(not north_builder.geometry_equal(packed,changed_alpha), "north geometry guard rejects alpha drift")
	_check(_same_geometry_and_palette(packed, Palette.recolor(packed)), "indexed palette and all raw geometry preserved")
	_check(not _same_geometry_and_palette(packed, packed), "unconverted palette is rejected by independent audit")
	var path := "res://resources/maps/tokyo_volume_preview/r32_cells/index.res"
	if ResourceLoader.exists(path):
		var before: Resource = load("res://resources/maps/tokyo_volume_preview/r30_cells/index.res")
		var after: Resource = load(path)
		_check(after.valid() and after.source_count == before.source_count and after.source_hash == before.source_hash \
			and after.bounds == before.bounds and after.shadow_cells == before.shadow_cells, "same full source and shadow envelope")
		var restored: Array = after.cells.duplicate(true)
		for entry: Dictionary in restored:
			entry.fixed = String(entry.fixed).replace("r32_cells", "r30_cells")
			for descriptor: Dictionary in entry.levels:
				descriptor.path = String(descriptor.path).replace("r32_cells", "r30_cells")
			entry.mid.path = String(entry.mid.path).replace("r32_cells", "r30_cells")
		_check(restored == before.cells and after.coverage_rects == before.coverage_rects \
			and after.joined_sources == before.joined_sources, "complete index metadata differs only by candidate resource paths")
		for id in 16:
			for slot in range(-1, 7):
				var a: Dictionary = before.cells[id]
				var b: Dictionary = after.cells[id]
				var ap: String = a.fixed if slot == -1 else (a.mid.path if slot == 6 else a.levels[slot].path)
				var bp: String = b.fixed if slot == -1 else (b.mid.path if slot == 6 else b.levels[slot].path)
				var old: Resource = ResourceLoader.load(ap, "", ResourceLoader.CACHE_MODE_IGNORE)
				var candidate: Resource = ResourceLoader.load(bp, "", ResourceLoader.CACHE_MODE_IGNORE)
				_check(candidate.valid() and candidate.source_ids == old.source_ids and candidate.height_hash == old.height_hash \
					and candidate.detail_counts == old.detail_counts and candidate.bounds == old.bounds, "source heights identities detail and bounds unchanged")
				var bytes := 0
				var triangles := 0
				for kind in old.meshes.size():
					_check(_same_geometry_and_palette(old.meshes[kind], candidate.meshes[kind]), "native raw geometry exact; decoded colors match independent rule")
					bytes += Builder.mesh_bytes(candidate.meshes[kind])
					triangles += Indexed.triangles(candidate.meshes[kind])
				if old.precision_original != null:
					_check(candidate.precision_original != null and _same_geometry_and_palette(old.precision_original, candidate.precision_original), "precision fallback uses same palette without geometry loss")
					bytes += Builder.mesh_bytes(candidate.precision_original)
				_check(bytes == old.geometry_bytes and candidate.geometry_bytes == bytes and triangles == old.triangles \
					and candidate.triangles == triangles and candidate.precision_triangles == old.precision_triangles \
					and candidate.precision_max_scale == old.precision_max_scale, "all LOD triangle/byte budgets including fallback exactly unchanged")
	print("[Tokyo palette test] pass=", _pass, " fail=", _fail)


func _same_geometry_and_palette(before: ArrayMesh, after: ArrayMesh) -> bool:
	if before.get_surface_count() == 0:
		return after.get_surface_count() == 0
	if after.get_surface_count() != 1:
		return false
	var a: Dictionary = before.get("_surfaces")[0]
	var b: Dictionary = after.get("_surfaces")[0].duplicate()
	b.attribute_data = a.attribute_data
	if a != b:
		return false
	var ac: PackedColorArray = before.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var bc: PackedColorArray = after.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	if ac.size() != bc.size():
		return false
	for index in ac.size():
		var expected := ac[index]
		var key := expected.to_html(false)
		if Palette.PAIRS.has(key):
			expected = Color(String(Palette.PAIRS[key]))
			expected.a = ac[index].a
		if bc[index] != expected:
			return false
	return true


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL palette: ", message)
