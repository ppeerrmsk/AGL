extends RefCounted
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Spatial := preload("res://scripts/tests/build_tokyo_spatial_pages.gd")
const Owner := preload("res://scripts/experiments/tokyo_surface_owner.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Page := preload("res://scripts/rendering/tokyo_spatial_lod_page.gd")
const Catalog := preload("res://scripts/rendering/tokyo_spatial_lod_index.gd")
const OUT := "res://bench/results/tokyo_r42_lod_pages"
const DEST := "res://resources/maps/tokyo_volume_preview/r42_lod_pages"
var _fail := 0


func run() -> void:
	assert(not DirAccess.dir_exists_absolute(OUT), "LOD output cannot overwrite an earlier candidate")
	var original: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	var layout: Resource = load("res://resources/maps/tokyo_volume_preview/r40_pages/index.res")
	assert(original.valid() and layout.valid() and original.source_hash == layout.source_hash)
	DirAccess.make_dir_recursive_absolute(OUT)
	var report := {"source_index_sha256": FileAccess.get_sha256(layout.original_index), "packages": [], "fail": 0}
	for variant: String in ["full", "mid"]:
		var out := OUT.path_join(variant)
		var destination := DEST.path_join(variant)
		DirAccess.make_dir_recursive_absolute(out)
		var catalog := Catalog.new()
		catalog.package_variant = variant
		catalog.source_hash = original.source_hash
		catalog.source_count = original.source_count
		for id in 16:
			var cell: Dictionary = original.cells[id]
			var entry: Dictionary = cell.mid if variant == "mid" else cell.levels[4]
			var building: Resource = ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var near: Resource = ResourceLoader.load(cell.levels[5].path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var fixed: Resource = ResourceLoader.load(cell.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
			assert(building.valid() and building.level == 4 and building.precision_original == null and building.height_hash == near.height_hash)
			var equal_near: Array[bool] = []
			for kind in 2:
				equal_near.append(building.meshes[kind].get("_surfaces") == near.meshes[kind].get("_surfaces"))
			var resolved := Owner.resolve(building.meshes[0], building.meshes[1], true)
			var meshes: Array[ArrayMesh] = [resolved.mesh, building.meshes[1], fixed.meshes[0]]
			var parent := Spatial.descriptor(meshes)
			var canonical: Resource = building.duplicate(false)
			var canonical_meshes: Array[ArrayMesh] = [meshes[0], meshes[1]]
			canonical.meshes = canonical_meshes
			canonical.triangles = building.triangles - resolved.removed.size()
			canonical.geometry_bytes = int(parent.bytes) - int(fixed.geometry_bytes)
			assert(canonical.valid() and canonical.source_ids == building.source_ids and canonical.height_hash == building.height_hash)
			var root_name := "parent_%02d_lod_4.res" % id
			_fail += int(ResourceSaver.save(canonical, out.path_join(root_name), ResourceSaver.FLAG_COMPRESS) != OK)
			var context := {"out": out, "destination": destination, "variant": variant, "parent_id": id,
				"height_hash": building.height_hash, "source_hash": (FileAccess.get_sha256(cell.fixed) + ":" + FileAccess.get_sha256(out.path_join(root_name))).sha256_text()}
			var root_layout: Dictionary = layout.parents[id]
			var pieces := _split_layers(meshes, root_layout.cuts)
			parent.merge({"parent_id": id, "cell_id": -1, "key": "%s_parent_%02d" % [variant, id],
				"fixed": cell.fixed, "building": destination.path_join(root_name), "original_building": entry.path,
				"original_boxes": Spatial.descriptor([building.meshes[0], building.meshes[1], fixed.meshes[0]]).boxes,
				"original_triangles": [Indexed.triangles(building.meshes[0]), Indexed.triangles(building.meshes[1]), fixed.triangles],
				"children": [], "cuts": root_layout.cuts, "removed_faces": resolved.removed,
				"package_variant": variant, "level": 4})
			var child_bytes := 0
			var leaf_bytes := 0
			for n in 4:
				var child_meshes: Array[ArrayMesh] = [pieces[0][n], pieces[1][n], pieces[2][n]]
				var child := _save_page(child_meshes, id * 4 + n, -1, context)
				child_bytes += int(child.bytes)
				if id >= 8:
					var cut: PackedFloat32Array = root_layout.children[n].cuts
					child["cuts"] = cut
					child["children"] = []
					var leaves := _split_layers(child_meshes, cut)
					for slot in 4:
						var leaf_meshes: Array[ArrayMesh] = [leaves[0][slot], leaves[1][slot], leaves[2][slot]]
						var leaf := _save_page(leaf_meshes, 64 + int(child.cell_id) * 4 + slot, child.cell_id, context)
						child.children.append(leaf)
						leaf_bytes += int(leaf.bytes)
				parent.children.append(child)
			catalog.parents.append(parent)
			report.packages.append({"variant": variant, "parent_id": id, "level4_triangles": building.triangles, "level5_triangles": near.triangles,
				"equal_near_buffers": equal_near, "removed_faces": resolved.removed.size(), "parent_bytes": parent.bytes,
				"child_bytes": child_bytes, "leaf_bytes": leaf_bytes})
			print("[Tokyo LOD spatial build] variant=", variant, " parent=", id, " faces=", canonical.triangles + fixed.triangles, " equal_near=", equal_near)
		assert(catalog.valid())
		_fail += int(ResourceSaver.save(catalog, out.path_join("index.res"), ResourceSaver.FLAG_COMPRESS) != OK)
	report.fail = _fail
	var file := FileAccess.open(OUT.path_join("build_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[Tokyo LOD spatial build] files=418 fail=", _fail)


func _split_layers(meshes: Array[ArrayMesh], cut: PackedFloat32Array) -> Array:
	var result: Array = []
	for mesh: ArrayMesh in meshes:
		var pieces := Split.split(mesh, cut)
		assert(Spatial.conserved(mesh, pieces), "all original LOD positions normals colors and oriented triangles are conserved")
		result.append(pieces)
	return result


func _save_page(meshes: Array[ArrayMesh], id: int, ancestor: int, context: Dictionary) -> Dictionary:
	var page := Page.new()
	page.schema_version = 3
	page.level = 4
	page.package_variant = context.variant
	page.parent_id = context.parent_id
	page.cell_id = id
	page.ancestor_id = ancestor
	page.height_hash = context.height_hash
	page.source_hash = context.source_hash
	page.meshes = meshes
	var entry := Spatial.descriptor(meshes)
	page.geometry_bytes = entry.bytes
	for faces: int in entry.triangles:
		page.triangles += faces
	assert(page.valid())
	var name_value := ("page_%02d.res" if ancestor < 0 else "leaf_%03d.res") % id
	_fail += int(ResourceSaver.save(page, String(context.out).path_join(name_value), ResourceSaver.FLAG_COMPRESS) != OK)
	entry.merge({"cell_id": id, "ancestor_id": ancestor, "parent_id": page.parent_id, "level": 4,
		"package_variant": page.package_variant, "key": page.package_variant + "_" + name_value.get_basename(),
		"path": String(context.destination).path_join(name_value), "height_hash": page.height_hash, "source_hash": page.source_hash})
	return entry
