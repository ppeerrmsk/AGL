extends RefCounted
const Page := preload("res://scripts/rendering/tokyo_spatial_lod_page.gd")
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")
const Spatial := preload("res://scripts/tests/build_tokyo_spatial_pages.gd")
const Owner := preload("res://scripts/experiments/tokyo_surface_owner.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_test_identity()
	_test_saved()
	print("[Tokyo LOD spatial test] pass=", _pass, " fail=", _fail)


func _test_identity() -> void:
	var page := Page.new()
	_check(not page.valid(), "uninitialized LOD page rejected")
	page.schema_version = 3
	page.level = 4
	page.package_variant = "mid"
	page.parent_id = 8
	page.cell_id = 32
	page.height_hash = "a".repeat(64)
	page.source_hash = "b".repeat(64)
	page.meshes.assign([ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()])
	_check(page.valid(), "LOD4 intermediate child has a valid source root")
	page.ancestor_id = 32
	page.cell_id = 192
	_check(page.valid(), "LOD4 grandchild preserves hierarchy identity")
	page.level = 5
	_check(not page.valid(), "middle package cannot masquerade as near LOD")
	page.level = 4
	page.cell_id = 196
	_check(not page.valid(), "wrong ancestor leaf rejected")
	page.cell_id = 192
	var stream := Stream.new()
	stream._descriptors["page"] = {"id": page.cell_id, "level": 4, "bytes": 0,
		"height_hash": page.height_hash, "source_hash": page.source_hash, "package_variant": "full"}
	_check(not stream._matches(page, "page"), "same ID height and byte count cannot replace full with mid")
	stream._descriptors.page.package_variant = "mid"
	_check(stream._matches(page, "page"), "real stream validates matching independent package")
	stream.free()
	_check(load("res://scripts/rendering/tokyo_lod_hierarchical_overlay.gd").can_instantiate(), "runtime LOD overlay compiles")
	_check(load("res://scripts/tests/tokyo_lod_spatial_review.gd").can_instantiate(), "same-camera native reference fixture compiles")


func _test_saved() -> void:
	var original: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	var layout: Resource = load("res://resources/maps/tokyo_volume_preview/r40_pages/index.res")
	for variant: String in ["full", "mid"]:
		var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r42_lod_pages/" + variant + "/index.res")
		_check(catalog.valid() and catalog.source_hash == original.source_hash and catalog.source_count == original.source_count, "saved catalog retains all source authority")
		var paths: Dictionary = {}
		for id in 16:
			var parent: Dictionary = catalog.parents[id]
			var cell: Dictionary = original.cells[id]
			var target: Dictionary = cell.mid if variant == "mid" else cell.levels[4]
			var source: Resource = ResourceLoader.load(target.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var root: Resource = ResourceLoader.load(parent.building, "", ResourceLoader.CACHE_MODE_IGNORE)
			var fixed: Resource = ResourceLoader.load(parent.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
			var resolved := Owner.resolve(source.meshes[0], source.meshes[1], true)
			_check(root.valid() and root.level == 4 and root.height_hash == source.height_hash and root.source_ids == source.source_ids and root.detail_counts == source.detail_counts, "canonical root retains original LOD4 IDs height and detail counts")
			_check(parent.original_building == target.path and parent.fixed == cell.fixed and parent.cuts == layout.parents[id].cuts, "source paths and stable spatial boundaries retained")
			var meshes: Array[ArrayMesh] = [root.meshes[0], root.meshes[1], fixed.meshes[0]]
			var descriptor := Spatial.descriptor(meshes)
			_check(parent.boxes == descriptor.boxes and parent.triangles == descriptor.triangles and int(parent.bytes) == int(descriptor.bytes)
				and int(root.geometry_bytes) + int(fixed.geometry_bytes) == int(parent.bytes), "saved root actual native bytes faces and boxes match")
			var low: Array[ArrayMesh] = [root.meshes[0]]
			_check(Spatial.conserved(resolved.mesh, low) and parent.removed_faces == resolved.removed, "only independently verified complete low-wall coverage changes")
			_check(root.meshes[1].get("_surfaces") == source.meshes[1].get("_surfaces"), "all marked-height native buffers remain exact")
			var hash_value := (FileAccess.get_sha256(cell.fixed) + ":" + FileAccess.get_sha256(parent.building)).sha256_text()
			var children: Array[Resource] = []
			for entry: Dictionary in parent.children:
				_check(not paths.has(entry.path), "each child path is unique")
				paths[entry.path] = true
				var child := _verify_page(entry, id, variant, hash_value, source.height_hash)
				children.append(child)
				if id >= 8:
					_check(entry.cuts == layout.parents[id].children[int(entry.cell_id) % 4].cuts, "second-level cut stays aligned with near layout")
					var leaves: Array[Resource] = []
					for leaf_entry: Dictionary in entry.children:
						_check(not paths.has(leaf_entry.path), "each leaf path is unique")
						paths[leaf_entry.path] = true
						leaves.append(_verify_page(leaf_entry, id, variant, hash_value, source.height_hash))
					for kind in 3:
						_check(_conserved(child.meshes[kind], leaves, kind), "saved grandchildren preserve every oriented native corner")
			for kind in 3:
				_check(_conserved(meshes[kind], children, kind), "saved children preserve every parent position normal and color")
		_check(paths.size() == 192, "each independent LOD has 64 children and 128 leaves")
		var broken: Resource = catalog.duplicate(true)
		broken.parents[8].children[0].children[0].package_variant = "mid" if variant == "full" else "full"
		_check(not broken.valid(), "foreign middle/full leaf invalidates the catalog")


func _verify_page(entry: Dictionary, root_id: int, variant: String, source_hash: String, height_hash: String) -> Resource:
	var page: Resource = ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(page.valid() and page.cell_id == entry.cell_id and page.ancestor_id == entry.ancestor_id and page.parent_id == root_id and page.package_variant == variant, "saved native identity and independent LOD variant match")
	_check(page.height_hash == height_hash and page.source_hash == source_hash and entry.source_hash == source_hash, "saved child lineage and source heights match canonical root")
	var descriptor := Spatial.descriptor(page.meshes)
	_check(descriptor.boxes == entry.boxes and descriptor.triangles == entry.triangles
		and int(descriptor.bytes) == int(entry.bytes) and page.geometry_bytes == int(entry.bytes), "saved native buffers match actual declared footprint and bytes")
	var triangles := 0
	for count: int in descriptor.triangles:
		triangles += count
	_check(page.triangles == triangles, "declared submitted count uses actual indices")
	return page


func _conserved(original: ArrayMesh, pages: Array[Resource], kind: int) -> bool:
	var pieces: Array[ArrayMesh] = []
	for page: Resource in pages:
		pieces.append(page.meshes[kind])
	return Spatial.conserved(original, pieces)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo LOD spatial: " + label)
