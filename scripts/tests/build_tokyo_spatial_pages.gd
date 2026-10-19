extends RefCounted
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Page := preload("res://scripts/rendering/tokyo_spatial_page.gd")
const Catalog := preload("res://scripts/rendering/tokyo_spatial_index.gd")
const Signature := preload("res://scripts/tests/tokyo_mesh_signature.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const OUT := "res://bench/results/tokyo_r38_pages"
const DEST := "res://resources/maps/tokyo_volume_preview/r38_pages"
var _fail := 0


func run() -> void:
	assert(not DirAccess.dir_exists_absolute(OUT), "spatial output cannot overwrite a previous candidate")
	var index := Catalog.new()
	var source: Resource = load(index.original_index)
	assert(source.valid())
	index.source_count = source.source_count
	index.source_hash = source.source_hash
	DirAccess.make_dir_recursive_absolute(OUT)
	var report := {"source_count": source.source_count, "source_index_sha256": FileAccess.get_sha256(index.original_index), "parents": [], "fail": 0}
	for id in 16:
		var old: Dictionary = source.cells[id]
		var fixed: Resource = ResourceLoader.load(old.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
		var building: Resource = ResourceLoader.load(old.levels[5].path, "", ResourceLoader.CACHE_MODE_IGNORE)
		assert(fixed.valid() and building.valid() and building.precision_original == null)
		var meshes: Array[ArrayMesh] = [building.meshes[0], building.meshes[1], fixed.meshes[0]]
		var geometry: Array[ArrayMesh] = [meshes[0], meshes[1]]
		if Indexed.triangles(meshes[0]) + Indexed.triangles(meshes[1]) == 0:
			geometry.append(meshes[2])
		var cut := Split.cuts(geometry)
		var pieces: Array = []
		for mesh: ArrayMesh in meshes:
			var split := Split.split(mesh, cut)
			assert(conserved(mesh, split), "every oriented native triangle must occur exactly once after subdivision")
			pieces.append(split)
		var parent := descriptor(meshes)
		parent.merge({"parent_id": id, "cell_id": -1, "key": "parent_%02d" % id,
			"fixed": old.fixed, "building": old.levels[5].path, "children": [], "cuts": cut})
		var child_bytes := 0
		var child_faces := 0
		for n in 4:
			var page := Page.new()
			page.cell_id = id * 4 + n
			page.parent_id = id
			page.height_hash = building.height_hash
			page.source_hash = (FileAccess.get_sha256(old.fixed) + ":" + FileAccess.get_sha256(old.levels[5].path)).sha256_text()
			page.meshes.assign([pieces[0][n], pieces[1][n], pieces[2][n]])
			var entry := descriptor(page.meshes)
			page.geometry_bytes = entry.bytes
			for faces: int in entry.triangles:
				page.triangles += faces
			assert(page.valid())
			var name_value := "page_%02d.res" % page.cell_id
			_fail += int(ResourceSaver.save(page, OUT.path_join(name_value), ResourceSaver.FLAG_COMPRESS) != OK)
			entry.merge({"parent_id": id, "cell_id": page.cell_id, "key": name_value.get_basename(), "path": DEST.path_join(name_value),
				"height_hash": page.height_hash, "source_hash": page.source_hash})
			parent.children.append(entry)
			child_bytes += page.geometry_bytes
			child_faces += page.triangles
		assert(child_faces == building.triangles + fixed.triangles)
		index.parents.append(parent)
		report.parents.append({"id": id, "before_bytes": parent.bytes, "after_bytes": child_bytes, "triangles": child_faces, "cuts": cut})
		print("[Tokyo spatial build] parent=", id, " faces=", child_faces, " bytes=", parent.bytes, "->", child_bytes)
	assert(index.valid())
	_fail += int(ResourceSaver.save(index, OUT.path_join("index.res"), ResourceSaver.FLAG_COMPRESS) != OK)
	report.fail = _fail
	var file := FileAccess.open(OUT.path_join("build_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[Tokyo spatial build] pages=64 fail=", _fail)


static func descriptor(meshes: Array[ArrayMesh]) -> Dictionary:
	var boxes: Array[AABB] = []
	var faces := PackedInt32Array()
	var bytes := 0
	for mesh: ArrayMesh in meshes:
		boxes.append(mesh.get_aabb())
		faces.append(Indexed.triangles(mesh))
		bytes += Builder.mesh_bytes(mesh)
	return {"boxes": boxes, "triangles": faces, "bytes": bytes}


static func conserved(original: ArrayMesh, pieces: Array[ArrayMesh]) -> bool:
	var remaining := Signature.of_mesh(original)
	for mesh: ArrayMesh in pieces:
		var signatures := Signature.of_mesh(mesh)
		for key: PackedByteArray in signatures:
			var count := int(remaining.get(key, 0)) - int(signatures[key])
			if count < 0:
				return false
			if count == 0:
				remaining.erase(key)
			else:
				remaining[key] = count
	return remaining.is_empty()
