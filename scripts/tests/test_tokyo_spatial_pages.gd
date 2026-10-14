extends RefCounted
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const Build := preload("res://scripts/tests/build_tokyo_spatial_pages.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const SurfaceOwner := preload("res://scripts/experiments/tokyo_surface_owner.gd")
const Signature := preload("res://scripts/tests/tokyo_mesh_signature.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var review: Script = load("res://scripts/tests/tokyo_spatial_review.gd")
	_check(review != null and review.can_instantiate(), "native visual diagnostic compiles before launch")
	var ordered := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var points := PackedVector3Array()
	for x in [-10.0, 10.0]:
		for z in [100.0, -100.0, 0.0, 200.0]:
			points.append_array(PackedVector3Array([Vector3(x - 1, 0, z), Vector3(x + 1, 0, z), Vector3(x, 1, z)]))
	arrays[Mesh.ARRAY_VERTEX] = points
	ordered.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var median_sources: Array[ArrayMesh] = [ordered]
	_check(Split.cuts(median_sources) == PackedFloat32Array([10, 100, 100]), "both side medians are sorted independently of source face order")
	var geometry := Geometry.new()
	for x in [-10.0, 10.0]:
		for z in [-10.0, 10.0]:
			geometry.box(Vector3(x, 5, z), Vector3(4, 10, 4), Color(0.5, 0.7, 0.2))
	var raw: ArrayMesh = geometry.mesh()
	var sources: Array[ArrayMesh] = [raw]
	var cut := Split.cuts(sources)
	_check(cut.size() == 3 and cut == Split.cuts(sources), "deterministic source-only cuts")
	for mesh: ArrayMesh in [raw, Indexed.pack(raw), ArrayMesh.new()]:
		var pieces := Split.split(mesh, cut)
		_check(pieces.size() == 4 and Build.conserved(mesh, pieces), "indexed unindexed and empty oriented triangles are preserved")
		for piece: ArrayMesh in pieces:
			if piece.get_surface_count() == 0:
				continue
			var valid := true
			for point: Vector3 in piece.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var box := piece.get_aabb()
				valid = valid and point.x >= box.position.x and point.y >= box.position.y and point.z >= box.position.z \
					and point.x <= box.end.x and point.y <= box.end.y and point.z <= box.end.z
			_check(valid, "native child bounds include every original vertex")
	var native: Resource = load("res://resources/maps/tokyo_volume_preview/r32_cells/cell_08_lod_5.res")
	var mesh: ArrayMesh = native.meshes[0]
	var surface: Dictionary = mesh.get("_surfaces")[0]
	_check(RenderingServer.mesh_surface_get_format_index_stride(int(surface.format), int(surface.vertex_count)) == 4, "real city exercises 32-bit source indices")
	sources.assign([mesh])
	_check(Build.conserved(mesh, Split.split(mesh, Split.cuts(sources))), "large native source survives spatial repacking")
	_test_selection()
	_test_saved()
	_test_surface_owner()
	_test_covered_walls()
	_test_owned_saved()
	print("[Tokyo spatial pages test] pass=", _pass, " fail=", _fail)


func _test_saved() -> void:
	var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r38_pages/index.res")
	_check(catalog.valid(), "saved spatial catalog is valid")
	var original: Resource = load(catalog.original_index)
	_check(original.source_hash == catalog.source_hash and original.source_count == catalog.source_count,
		"saved pages retain original source authority")
	var total := 0
	for parent: Dictionary in catalog.parents:
		var fixed: Resource = ResourceLoader.load(parent.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
		var building: Resource = ResourceLoader.load(parent.building, "", ResourceLoader.CACHE_MODE_IGNORE)
		var original_meshes: Array[ArrayMesh] = [building.meshes[0], building.meshes[1], fixed.meshes[0]]
		var expected_hash := (FileAccess.get_sha256(parent.fixed) + ":" + FileAccess.get_sha256(parent.building)).sha256_text()
		var pieces: Array = [[], [], []]
		var pages: Array[Resource] = []
		for child: Dictionary in parent.children:
			var page: Resource = ResourceLoader.load(child.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			pages.append(page)
			_check(page.valid() and page.cell_id == child.cell_id and page.parent_id == parent.parent_id
				and page.height_hash == building.height_hash and page.source_hash == expected_hash,
				"saved child identity height and source hashes match original parent")
			var actual := Build.descriptor(page.meshes)
			_check(actual.bytes == child.bytes and actual.bytes == page.geometry_bytes
				and actual.boxes == child.boxes and actual.triangles == child.triangles,
				"saved child actual native bounds triangles and bytes match catalog")
			var faces := 0
			for kind in 3:
				pieces[kind].append(page.meshes[kind])
				faces += int(actual.triangles[kind])
			_check(faces == page.triangles, "saved child total triangles are exact")
			total += faces
		for kind in 3:
			var typed: Array[ArrayMesh] = []
			typed.assign(pieces[kind])
			_check(Build.conserved(original_meshes[kind], typed), "saved native layer preserves every oriented colored triangle exactly once")
	_check(total == 1128472, "all saved near pages retain the complete R34 geometry")


func _test_surface_owner() -> void:
	var geometry := Geometry.new()
	geometry.box(Vector3(0, 5, 0), Vector3(4, 10, 4), Color(0.4, 0.5, 0.4))
	geometry.box(Vector3(10, 5, 0), Vector3(4, 10, 4), Color(0.4, 0.5, 0.4))
	var low := geometry.mesh()
	geometry = Geometry.new()
	geometry.box(Vector3(0, 5, 0), Vector3(4, 10, 4), Color(0.7, 0.8, 0.7))
	var known := geometry.mesh()
	var known_before := Signature.of_mesh(known)
	geometry = Geometry.new()
	geometry.box(Vector3(10, 5, 0), Vector3(4, 10, 4), Color(0.4, 0.5, 0.4))
	var remaining := geometry.mesh()
	for source: ArrayMesh in [low, Indexed.pack(low)]:
		var result := SurfaceOwner.resolve(source, known)
		_check(result.changed and result.removed.size() == 12, "only exact known-owned triangles are removed from low layer")
		_check(Build.conserved(remaining, [result.mesh]), "unrelated low geometry normals and colors survive exact ownership")
		_check(result.mesh.get("_surfaces")[0].vertex_data == source.get("_surfaces")[0].vertex_data
			and result.mesh.get("_surfaces")[0].attribute_data == source.get("_surfaces")[0].attribute_data,
			"ownership does not move or recolor original buffers")
	_check(Signature.of_mesh(known) == known_before, "known owner mesh is immutable")
	var arrays := known.surface_get_arrays(0)
	var count := known.surface_get_array_len(0)
	for reverse_order in [false, true]:
		var indices := PackedInt32Array()
		for start in range(0, count, 3):
			indices.append_array(PackedInt32Array([start + 1, start, start + 2] if reverse_order else [start + 1, start + 2, start]))
		arrays[Mesh.ARRAY_INDEX] = indices
		var shuffled := ArrayMesh.new()
		shuffled.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var result := SurfaceOwner.resolve(known, shuffled)
		_check((not result.changed) if reverse_order else result.removed.size() == 12,
			"cyclic order matches but reversed faces retain their own ownership")
	geometry = Geometry.new()
	geometry.box(Vector3(0.001, 5, 0), Vector3(4, 10, 4), Color(0.7, 0.8, 0.7))
	_check(not SurfaceOwner.resolve(low, geometry.mesh()).changed, "nearby surfaces are not fuzzy merged")
	_check(not SurfaceOwner.resolve(low, ArrayMesh.new()).changed, "missing known geometry cannot claim low surfaces")


func _test_covered_walls() -> void:
	var geometry := Geometry.new()
	geometry.box(Vector3(0, 5, 0), Vector3(4, 10, 4), Color(0.4, 0.5, 0.4))
	var low := geometry.mesh()
	geometry = Geometry.new()
	geometry.box(Vector3(0, 10, 0), Vector3(4, 20, 4), Color(0.7, 0.8, 0.7))
	var known := geometry.mesh()
	_check(SurfaceOwner.wall_rectangles(known).size() == 4, "complete known box proves four vertical rectangles")
	for mesh: ArrayMesh in [low, Indexed.pack(low)]:
		var exact := SurfaceOwner.resolve(mesh, known)
		var covered := SurfaceOwner.resolve(mesh, known, true)
		_check(covered.removed.size() == exact.removed.size() + 8, "taller known walls fully cover all eight low wall triangles without changing known height")
		_check(Indexed.triangles(covered.mesh) == 2, "low roof survives wall-only ownership")
	var arrays := known.surface_get_arrays(0)
	var indices := PackedInt32Array()
	for start in range(0, known.surface_get_array_len(0), 6):
		indices.append_array(PackedInt32Array([start, start + 1, start + 2]))
	arrays[Mesh.ARRAY_INDEX] = indices
	var half := ArrayMesh.new()
	half.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_check(SurfaceOwner.wall_rectangles(half).is_empty(), "one triangle does not prove a complete known wall")
	_check(SurfaceOwner.resolve(low, half, true).removed == SurfaceOwner.resolve(low, half).removed,
		"half walls cannot claim uncovered low geometry")
	geometry = Geometry.new()
	geometry.box(Vector3(0, 11, 0), Vector3(4, 20, 4), Color(0.7, 0.8, 0.7))
	_check(not SurfaceOwner.resolve(low, geometry.mesh(), true).changed, "known wall with a lower gap cannot claim the full low wall")
	geometry = Geometry.new()
	geometry.box(Vector3(0.001, 10, 0), Vector3(4, 20, 4), Color(0.7, 0.8, 0.7))
	_check(not SurfaceOwner.resolve(low, geometry.mesh(), true).changed, "nearby endpoint does not create a shared wall")


func _test_owned_saved() -> void:
	var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r39_pages/index.res")
	_check(catalog.valid(), "saved owned catalog is valid")
	var total := 0
	var removed := 0
	for parent: Dictionary in catalog.parents:
		var old: Resource = ResourceLoader.load(parent.original_building, "", ResourceLoader.CACHE_MODE_IGNORE)
		var root: Resource = ResourceLoader.load(parent.building, "", ResourceLoader.CACHE_MODE_IGNORE)
		var fixed: Resource = ResourceLoader.load(parent.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
		var expected := SurfaceOwner.resolve(old.meshes[0], old.meshes[1], true)
		_check(root.valid() and root.source_ids == old.source_ids and root.height_hash == old.height_hash
			and root.bounds == old.bounds and root.detail_counts == old.detail_counts, "saved canonical parent retains source identity heights bounds and building counts")
		_check(root.triangles + expected.removed.size() == old.triangles and expected.removed == parent.removed_faces,
			"saved parent only removes fully claimed native faces")
		_check(Build.conserved(expected.mesh, [root.meshes[0]]) and Build.conserved(old.meshes[1], [root.meshes[1]]),
			"saved parent reproduces canonical low geometry and immutable known geometry")
		var sources: Array[ArrayMesh] = [root.meshes[0], root.meshes[1], fixed.meshes[0]]
		var root_info := Build.descriptor(sources)
		_check(root_info.bytes == parent.bytes and root.geometry_bytes + fixed.geometry_bytes == parent.bytes
			and root_info.boxes == parent.boxes and root_info.triangles == parent.triangles, "saved parent native byte and bounds metadata is exact")
		var pieces: Array = [[], [], []]
		var retained: Array[Resource] = []
		var expected_hash := (FileAccess.get_sha256(parent.fixed) + ":" + FileAccess.get_sha256(parent.building)).sha256_text()
		for child: Dictionary in parent.children:
			var page: Resource = ResourceLoader.load(child.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			retained.append(page)
			var actual := Build.descriptor(page.meshes)
			_check(page.valid() and page.source_hash == expected_hash and page.source_hash == child.source_hash
				and page.height_hash == root.height_hash and page.cell_id == child.cell_id and page.parent_id == parent.parent_id,
				"saved owned child uses its canonical parent hash without changing height authority")
			_check(actual.bytes == child.bytes and page.geometry_bytes == child.bytes
				and actual.boxes == child.boxes and actual.triangles == child.triangles, "owned child actual geometry matches disk catalog")
			var faces := 0
			for kind in 3:
				pieces[kind].append(page.meshes[kind])
				faces += int(actual.triangles[kind])
			_check(faces == page.triangles, "owned child submitted count matches native index count")
			total += faces
		for kind in 3:
			var typed: Array[ArrayMesh] = []
			typed.assign(pieces[kind])
			_check(Build.conserved(sources[kind], typed), "canonical parent layer equals all four saved children exactly once")
		removed += expected.removed.size()
	_check(total == 1128272 and removed == 200 and total + removed == 1128472, "R39 entire region differs only by 200 fully covered low faces")


func _test_selection() -> void:
	var roots: Array[Dictionary] = []
	var parent := {"boxes": [AABB(Vector3(-100, 0, -100), Vector3(200, 10, 200)), AABB(), AABB()],
		"triangles": PackedInt32Array([400, 0, 0]), "bytes": 4000, "children": []}
	for x in [-80.0, 60.0]:
		for z in [-80.0, 60.0]:
			parent.children.append({"boxes": [AABB(Vector3(x, 0, z), Vector3(20, 10, 20)), AABB(), AABB()],
				"triangles": PackedInt32Array([100, 0, 0]), "bytes": 1000})
	roots.append(parent)
	var view := Rect2(-85, -85, 30, 30)
	var canvas := Transform2D(0, Vector2(85, 85))
	var picked := Select.choose(roots, view, canvas, Vector2(30, 30), Vector2.ZERO, Vector2.ZERO, 1)
	_check(picked.active == 1 and picked.triangles == 100 and picked.bytes == 1000, "one visible child replaces full root without dropping a visible fragment")
	picked = Select.choose(roots, Rect2(-150, -150, 300, 300), Transform2D(0, Vector2(150, 150)), Vector2(300, 300), Vector2.ZERO, Vector2.ZERO, 1)
	_check(picked.active == 1 and picked.triangles == 400, "cap keeps complete parent rather than dropping child geometry")
	picked = Select.choose(roots, Rect2(500, 500, 30, 30), Transform2D(0, Vector2(-500, -500)), Vector2(30, 30), Vector2.ZERO, Vector2.ZERO)
	_check(picked.active == 0 and picked.triangles == 0, "empty view is empty without fake geometry")
	parent.bytes = 1000000000
	picked = Select.choose(roots, Rect2(-150, -150, 300, 300), Transform2D(0, Vector2(150, 150)), Vector2(300, 300), Vector2.ZERO, Vector2.ZERO, 1)
	_check(not picked.within_budget and picked.triangles == 400, "over-budget complete cut is rejected instead of silently dropping triangles")


func _check(ok: bool, reason: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo spatial: " + reason)
