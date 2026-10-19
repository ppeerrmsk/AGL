extends RefCounted
const Owner := preload("res://scripts/experiments/tokyo_surface_owner.gd")
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Spatial := preload("res://scripts/tests/build_tokyo_spatial_pages.gd")
const Page := preload("res://scripts/rendering/tokyo_spatial_page.gd")
const Catalog := preload("res://scripts/rendering/tokyo_spatial_index.gd")
const OUT := "res://bench/results/tokyo_r39b_pages"
const DEST := "res://resources/maps/tokyo_volume_preview/r39_pages"
var _fail := 0


func run() -> void:
	assert(not DirAccess.dir_exists_absolute(OUT), "owned candidate must not overwrite previous native output")
	DirAccess.make_dir_recursive_absolute(OUT)
	var before: Resource = load("res://resources/maps/tokyo_volume_preview/r38_pages/index.res")
	var index := Catalog.new()
	index.source_hash = before.source_hash
	index.source_count = before.source_count
	index.original_index = before.original_index
	var report := {"rule": "exact_or_complete_vertical_rectangle_v1", "parents": [], "removed": 0, "triangles": 0, "fail": 0}
	for original: Dictionary in before.parents:
		var old: Resource = ResourceLoader.load(original.building, "", ResourceLoader.CACHE_MODE_IGNORE)
		var fixed: Resource = ResourceLoader.load(original.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
		var resolved := Owner.resolve(old.meshes[0], old.meshes[1], true)
		var root: Resource = old.duplicate(false)
		var root_meshes: Array[ArrayMesh] = [resolved.mesh, old.meshes[1]]
		root.meshes = root_meshes
		root.triangles = old.triangles - resolved.removed.size()
		var meshes: Array[ArrayMesh] = [resolved.mesh, old.meshes[1], fixed.meshes[0]]
		var parent := Spatial.descriptor(meshes)
		root.geometry_bytes = int(parent.bytes) - int(fixed.geometry_bytes)
		assert(root.valid() and root.height_hash == old.height_hash and root.source_ids == old.source_ids)
		var root_name := "parent_%02d_lod_5.res" % int(original.parent_id)
		_fail += int(ResourceSaver.save(root, OUT.path_join(root_name), ResourceSaver.FLAG_COMPRESS) != OK)
		var source_hash := (FileAccess.get_sha256(original.fixed) + ":" + FileAccess.get_sha256(OUT.path_join(root_name))).sha256_text()
		parent.merge({"parent_id": original.parent_id, "cell_id": -1, "key": original.key,
			"fixed": original.fixed, "building": DEST.path_join(root_name), "original_building": original.building,
			"original_boxes": original.boxes, "original_triangles": original.triangles,
			"children": [], "cuts": original.cuts, "removed_faces": resolved.removed})
		var pieces: Array = []
		for mesh: ArrayMesh in meshes:
			var split := Split.split(mesh, original.cuts)
			assert(Spatial.conserved(mesh, split), "canonical parent and children retain identical oriented native geometry")
			pieces.append(split)
		var child_faces := 0
		var child_bytes := 0
		for n in 4:
			var page := Page.new()
			page.parent_id = original.parent_id
			page.cell_id = int(original.parent_id) * 4 + n
			page.height_hash = root.height_hash
			page.source_hash = source_hash
			page.meshes.assign([pieces[0][n], pieces[1][n], pieces[2][n]])
			var entry := Spatial.descriptor(page.meshes)
			page.geometry_bytes = entry.bytes
			for faces: int in entry.triangles:
				page.triangles += faces
			var name_value := "page_%02d.res" % page.cell_id
			assert(page.valid())
			_fail += int(ResourceSaver.save(page, OUT.path_join(name_value), ResourceSaver.FLAG_COMPRESS) != OK)
			entry.merge({"parent_id": page.parent_id, "cell_id": page.cell_id, "key": name_value.get_basename(),
				"path": DEST.path_join(name_value), "height_hash": page.height_hash, "source_hash": source_hash})
			parent.children.append(entry)
			child_faces += page.triangles
			child_bytes += page.geometry_bytes
		assert(child_faces + resolved.removed.size() == old.triangles + fixed.triangles)
		index.parents.append(parent)
		report.parents.append({"id": original.parent_id, "removed": resolved.removed.size(),
			"triangles": child_faces, "parent_bytes": parent.bytes, "child_bytes": child_bytes})
		report.removed += resolved.removed.size()
		report.triangles += child_faces
		print("[Tokyo owned build] parent=", original.parent_id, " removed=", resolved.removed.size(), " triangles=", child_faces)
	assert(index.valid())
	_fail += int(ResourceSaver.save(index, OUT.path_join("index.res"), ResourceSaver.FLAG_COMPRESS) != OK)
	report.fail = _fail
	var file := FileAccess.open(OUT.path_join("build_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[Tokyo owned build] files=81 removed=", report.removed, " triangles=", report.triangles, " fail=", _fail)
