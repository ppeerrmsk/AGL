extends RefCounted
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Spatial := preload("res://scripts/tests/build_tokyo_spatial_pages.gd")
const Leaf := preload("res://scripts/rendering/tokyo_spatial_leaf.gd")
const Catalog := preload("res://scripts/rendering/tokyo_hierarchical_index.gd")
const OUT := "res://bench/results/tokyo_r40_pages"
const DEST := "res://resources/maps/tokyo_volume_preview/r40_pages"
var _fail := 0


func run() -> void:
	assert(not DirAccess.dir_exists_absolute(OUT), "hierarchical output must remain independent")
	DirAccess.make_dir_recursive_absolute(OUT)
	var old: Resource = load("res://resources/maps/tokyo_volume_preview/r39_pages/index.res")
	var catalog := Catalog.new()
	catalog.source_hash = old.source_hash
	catalog.source_count = old.source_count
	catalog.original_index = old.original_index
	catalog.parents = old.parents.duplicate(true)
	var report := {"source_sha256": FileAccess.get_sha256("res://resources/maps/tokyo_volume_preview/r39_pages/index.res"), "pages": [], "triangles": 0, "before_bytes": 0, "after_bytes": 0, "fail": 0}
	for parent: Dictionary in catalog.parents:
		if int(parent.parent_id) < 8:
			continue
		for entry: Dictionary in parent.children:
			var original: Resource = ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			assert(original.valid())
			var geometry: Array[ArrayMesh] = [original.meshes[0], original.meshes[1]]
			if int(entry.triangles[0]) + int(entry.triangles[1]) == 0:
				geometry.append(original.meshes[2])
			var cut := Split.cuts(geometry)
			var pieces: Array = []
			for mesh: ArrayMesh in original.meshes:
				var divided := Split.split(mesh, cut)
				assert(Spatial.conserved(mesh, divided), "every R39 native triangle must appear once in its descendants")
				pieces.append(divided)
			entry["children"] = []
			entry["cuts"] = cut
			var sum_faces := 0
			var sum_bytes := 0
			for n in 4:
				var leaf := Leaf.new()
				leaf.schema_version = 2
				leaf.ancestor_id = entry.cell_id
				leaf.parent_id = entry.parent_id
				leaf.cell_id = 64 + int(entry.cell_id) * 4 + n
				leaf.height_hash = original.height_hash
				leaf.source_hash = FileAccess.get_sha256(entry.path)
				leaf.meshes.assign([pieces[0][n], pieces[1][n], pieces[2][n]])
				var info := Spatial.descriptor(leaf.meshes)
				leaf.geometry_bytes = info.bytes
				for faces: int in info.triangles:
					leaf.triangles += faces
				assert(leaf.valid())
				var name_value := "leaf_%03d.res" % leaf.cell_id
				_fail += int(ResourceSaver.save(leaf, OUT.path_join(name_value), ResourceSaver.FLAG_COMPRESS) != OK)
				info.merge({"cell_id": leaf.cell_id, "ancestor_id": leaf.ancestor_id, "parent_id": leaf.parent_id,
					"key": name_value.get_basename(), "path": DEST.path_join(name_value), "height_hash": leaf.height_hash, "source_hash": leaf.source_hash})
				entry.children.append(info)
				sum_faces += leaf.triangles
				sum_bytes += leaf.geometry_bytes
			assert(sum_faces == original.triangles)
			report.pages.append({"ancestor": entry.cell_id, "triangles": sum_faces, "before_bytes": original.geometry_bytes, "after_bytes": sum_bytes})
			report.triangles += sum_faces
			report.before_bytes += original.geometry_bytes
			report.after_bytes += sum_bytes
			print("[Tokyo hierarchical build] ancestor=", entry.cell_id, " triangles=", sum_faces)
	assert(catalog.valid())
	_fail += int(ResourceSaver.save(catalog, OUT.path_join("index.res"), ResourceSaver.FLAG_COMPRESS) != OK)
	report.fail = _fail
	var file := FileAccess.open(OUT.path_join("build_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[Tokyo hierarchical build] leaves=128 fail=", _fail)
