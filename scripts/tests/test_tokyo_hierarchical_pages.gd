extends RefCounted
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const Spatial := preload("res://scripts/tests/build_tokyo_spatial_pages.gd")
const Leaf := preload("res://scripts/rendering/tokyo_spatial_leaf.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_test_solver()
	_test_combine_equivalence()
	_test_visible_equivalence()
	_test_saved()
	print("[Tokyo hierarchy test] pass=", _pass, " fail=", _fail)


func _test_solver() -> void:
	var root := {"key": "root", "boxes": [AABB(Vector3(-100, 0, -100), Vector3(200, 10, 200)), AABB(), AABB()],
		"triangles": PackedInt32Array([400, 0, 0]), "bytes": 4000, "children": []}
	var middle := root.duplicate(true)
	middle.key = "middle"
	for x in [-80.0, 60.0]:
		for z in [-80.0, 60.0]:
			middle.children.append({"key": "%s,%s" % [x, z], "boxes": [AABB(Vector3(x, 0, z), Vector3(20, 10, 20)), AABB(), AABB()],
				"triangles": PackedInt32Array([100, 0, 0]), "bytes": 1000})
	root.children.append(middle)
	var roots: Array[Dictionary] = [root]
	var view := Rect2(-85, -85, 30, 30)
	var canvas := Transform2D(0, Vector2(85, 85))
	var old := Select.choose(roots, view, canvas, Vector2(30, 30), Vector2.ZERO, Vector2.ZERO, 1)
	var current := Cut.choose(roots, view, canvas, Vector2(30, 30), Vector2.ZERO, Vector2.ZERO, 1)
	_check(old.triangles == 400 and current.triangles == 100 and current.active == 1, "zero immediate gain must not block profitable grandchildren")
	_check(current.entries.size() == 1 and current.entries[0].key == middle.children[0].key, "complete visible leaf replaces ancestors without overlap")
	var explicit_leaf: Dictionary = middle.children[0].duplicate(true)
	explicit_leaf["children"] = []
	var leaf_roots: Array[Dictionary] = [explicit_leaf]
	# 画外分支的零切面是组合单位元；根层/子层跳过它仍须逐项保留完整候选。
	var empty_leaf := explicit_leaf.duplicate(true)
	empty_leaf.boxes[0]=AABB(Vector3(500,0,500),Vector3(20,10,20))
	var sparse_roots: Array[Dictionary]=[empty_leaf,explicit_leaf,empty_leaf]
	var leaf_solution := Cut.solve(leaf_roots,view,canvas,Vector2(30,30),Vector2.ZERO,Vector2.ZERO,1)
	var sparse_solution := Cut.solve(sparse_roots,view,canvas,Vector2(30,30),Vector2.ZERO,Vector2.ZERO,1)
	_check(sparse_solution.frontier==leaf_solution.frontier,"empty root combinations preserve exact frontier")
	var sparse_parent := explicit_leaf.duplicate(true)
	sparse_parent.triangles=PackedInt32Array([200,0,0]);sparse_parent.bytes=2000
	sparse_parent.children=[empty_leaf,explicit_leaf,empty_leaf]
	var sparse_parent_roots: Array[Dictionary]=[sparse_parent]
	var sparse_parent_solution := Cut.solve(sparse_parent_roots,view,canvas,Vector2(30,30),Vector2.ZERO,Vector2.ZERO,1)
	_check(sparse_parent_solution.frontier==leaf_solution.frontier,"empty child combinations preserve exact frontier")
	for solver: Script in [Cut, Select]:
		var selected: Dictionary = solver.choose(leaf_roots,view,canvas,Vector2(30,30),Vector2.ZERO,Vector2.ZERO,1)
		_check(selected.active==1 and selected.triangles==100 and selected.bytes==1000, "explicit empty children preserves visible leaf")
		selected=solver.choose(leaf_roots,Rect2(500,500,30,30),Transform2D(0,Vector2(-500,-500)),Vector2(30,30),Vector2.ZERO,Vector2.ZERO,1)
		_check(selected.active==0 and selected.triangles==0, "explicit leaf outside view is still culled")
	var nested := root.duplicate(true)
	for child: Dictionary in nested.children[0].children: child["children"]=[]
	var nested_roots: Array[Dictionary] = [nested]
	var nested_cut := Cut.choose(nested_roots,view,canvas,Vector2(30,30),Vector2.ZERO,Vector2.ZERO,1)
	_check(nested_cut.active==1 and nested_cut.triangles==100, "nested explicit leaves cannot manufacture an empty cheap cut")
	current = Cut.choose(roots, Rect2(-150, -150, 300, 300), Transform2D(0, Vector2(150, 150)), Vector2(300, 300), Vector2.ZERO, Vector2.ZERO, 1)
	_check(current.active == 1 and current.triangles == 400, "full view preserves complete parent under a one-node cap")
	current = Cut.choose(roots, Rect2(500, 500, 30, 30), Transform2D(0, Vector2(-500, -500)), Vector2(30, 30), Vector2.ZERO, Vector2.ZERO)
	_check(current.active == 0 and current.triangles == 0 and current.bytes == 0, "empty hierarchy view is truly empty")
	root.bytes = 90 * 1024 * 1024
	middle.bytes = root.bytes
	middle.children[0].bytes = 110 * 1024 * 1024
	current = Cut.choose(roots, view, canvas, Vector2(30, 30), Vector2.ZERO, Vector2.ZERO, 1)
	_check(current.triangles == 400 and current.within_budget, "memory-feasible complete parent survives a cheaper-face oversized leaf")
	root.bytes = 120 * 1024 * 1024
	middle.bytes = root.bytes
	current = Cut.choose(roots, view, canvas, Vector2(30, 30), Vector2.ZERO, Vector2.ZERO, 1)
	_check(current.triangles == 100 and not current.within_budget, "no feasible memory cut reports failure without hiding the visible leaf")
	var frontier: Array[Dictionary] = []
	for candidate: Dictionary in [{"active": 1, "faces": 100, "bytes": 200}, {"active": 1, "faces": 200, "bytes": 100},
		{"active": 2, "faces": 150, "bytes": 250}, {"active": 1, "faces": 100, "bytes": 200}]:
		Cut._insert(frontier, candidate)
	_check(frontier.size() == 2, "Pareto frontier preserves memory-face tradeoffs and rejects dominated duplicates")
	var leaf := Leaf.new()
	_check(not leaf.valid(), "uninitialized leaf fails closed")
	leaf.schema_version = 2
	leaf.ancestor_id = 32
	leaf.parent_id = 8
	leaf.cell_id = 192
	leaf.height_hash = "a".repeat(64)
	leaf.source_hash = "b".repeat(64)
	leaf.meshes.assign([ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()])
	_check(leaf.valid(), "second-level leaf identity has a unique ancestor and source root")
	leaf.cell_id = 196
	_check(not leaf.valid(), "sibling ancestor cannot claim this leaf")
	leaf.cell_id = 192
	leaf.parent_id = 9
	_check(not leaf.valid(), "foreign source root is rejected")


func _test_combine_equivalence() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 253
	for trial in 512:
		var left: Array[Dictionary] = []
		var right: Array[Dictionary] = []
		for side: Array[Dictionary] in [left, right]:
			for n in rng.randi_range(0, 32):
				side.append({"entries": [{"id": n, "trial": trial}], "active": rng.randi_range(0, 16),
					"faces": rng.randi_range(0, 6) * 100, "bytes": rng.randi_range(0, 6) * 1024})
		var before := [left.duplicate(true), right.duplicate(true)]
		var cap := rng.randi_range(1, 32)
		var expected: Array[Dictionary] = []
		# 原始实现作差分基准；比较完整entries及顺序，不只比较成本。
		for a: Dictionary in left:
			for b: Dictionary in right:
				if int(a.active) + int(b.active) <= cap:
					Cut._insert(expected, {"entries": a.entries + b.entries, "active": int(a.active) + int(b.active),
						"faces": int(a.faces) + int(b.faces), "bytes": int(a.bytes) + int(b.bytes)})
		_check(Cut._combine(left, right, cap) == expected, "lazy combination preserves complete ordered frontier")
		_check([left, right] == before, "combination does not mutate inputs")


func _test_visible_equivalence() -> void:
	var overlay: Script = preload("res://scripts/rendering/tokyo_cells_overlay.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 254
	for trial in 256:
		var boxes: Array[AABB] = []
		var triangles := PackedInt32Array()
		for kind in 3:
			boxes.append(AABB(Vector3(rng.randf_range(-200, 200), 0, rng.randf_range(-200, 200)),
				Vector3(rng.randf_range(0, 150), rng.randf_range(0, 80), rng.randf_range(0, 150))))
			triangles.append(100 if (trial & (1 << kind)) != 0 else 0)
		var entry := {"boxes": boxes, "triangles": triangles, "bytes": 1234, "key": str(trial)}
		var before := entry.duplicate(true)
		var canvas := Transform2D(rng.randf_range(-PI, PI), Vector2(100, 100))
		canvas = canvas.scaled(Vector2.ONE * rng.randf_range(0.1, 8.0))
		if trial % 16 == 0:
			canvas = Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		var view := Rect2(-120, -120, 240, 240)
		var logical := Vector2(200, 200)
		var roof := Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		var shadow := -roof * 2.0
		var expected := entry.duplicate()
		var mask: Array[bool] = []
		var faces := 0
		for kind in 3:
			var bounds: Rect2 = overlay.projected_layer_bounds(boxes[kind], roof, shadow)
			# 原遍历实现作精确基准，覆盖负地表高度与不同方向投影。
			var box := boxes[kind]
			box.position.y = float(trial - 128)
			var footprint := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
			var original := footprint
			for shift: Vector2 in [roof, shadow]:
				for height: float in [box.position.y, box.end.y]:
					original = original.merge(Rect2(footprint.position + shift * height, footprint.size))
			_check(overlay.projected_layer_bounds(box, roof, shadow) == original.grow(8.0), "unrolled projection exactly preserves bounds")
			var seen: bool = triangles[kind] > 0 and overlay.intersects_view(bounds, view, canvas, logical)
			mask.append(seen)
			faces += triangles[kind] if seen else 0
		expected.mask = mask
		expected.faces = faces
		_check(Select.visible(entry, view, canvas, logical, roof, shadow) == expected,
			"empty layer fast path preserves masks and complete descriptor")
		_check(entry == before, "visibility preserves source metadata")


func _test_saved() -> void:
	var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r40_pages/index.res")
	var old: Resource = load("res://resources/maps/tokyo_volume_preview/r39_pages/index.res")
	_check(catalog.valid() and catalog.source_hash == old.source_hash and catalog.source_count == old.source_count, "hierarchy preserves R39 source authority")
	var leaf_count := 0
	var total := 0
	for id in 16:
		var parent: Dictionary = catalog.parents[id]
		var previous: Dictionary = old.parents[id]
		for key: String in ["building", "fixed", "original_building", "boxes", "triangles", "bytes", "cuts", "removed_faces"]:
			_check(parent[key] == previous[key], "root metadata and R39 ownership remain unchanged")
		for n in 4:
			var entry: Dictionary = parent.children[n]
			var prior: Dictionary = previous.children[n]
			for key: String in prior:
				_check(entry[key] == prior[key], "first-level native paths and metadata are reused unchanged")
			if id < 8:
				_check(not entry.has("children"), "Yokohama partition is not rebuilt")
				continue
			var source: Resource = ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var pieces: Array = [[], [], []]
			var retained: Array[Resource] = []
			var sum_faces := 0
			for descriptor: Dictionary in entry.children:
				var leaf: Resource = ResourceLoader.load(descriptor.path, "", ResourceLoader.CACHE_MODE_IGNORE)
				retained.append(leaf)
				var actual := Spatial.descriptor(leaf.meshes)
				_check(leaf.valid() and leaf.ancestor_id == entry.cell_id and leaf.parent_id == id and leaf.cell_id == descriptor.cell_id
					and leaf.source_hash == FileAccess.get_sha256(entry.path) and leaf.height_hash == source.height_hash,
					"saved leaf identity height and immediate-source hash are exact")
				_check(actual.bytes == leaf.geometry_bytes and actual.bytes == descriptor.bytes and actual.boxes == descriptor.boxes
					and actual.triangles == descriptor.triangles, "saved leaf actual native geometry matches index")
				var faces := 0
				for kind in 3:
					pieces[kind].append(leaf.meshes[kind])
					faces += int(actual.triangles[kind])
				_check(faces == leaf.triangles, "leaf face count reflects native indices")
				sum_faces += faces
				leaf_count += 1
			for kind in 3:
				var typed: Array[ArrayMesh] = []
				typed.assign(pieces[kind])
				_check(Spatial.conserved(source.meshes[kind], typed), "all descendant layer triangles preserve native positions normals colors and multiplicities")
			_check(sum_faces == source.triangles, "complete leaf set preserves its ancestor geometry")
			total += sum_faces
	_check(leaf_count == 128 and total > 0, "all 128 intended north-coast leaves were audited")
	var invalid: Resource = catalog.duplicate(true)
	invalid.parents[8].children[0].children[0].ancestor_id = 31
	_check(not invalid.valid() and catalog.valid(), "invalid ancestor is rejected without mutating original catalog")


func _check(ok: bool, reason: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo hierarchy: " + reason)
