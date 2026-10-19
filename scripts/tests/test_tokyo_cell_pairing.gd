extends RefCounted
const Pairing := preload("res://scripts/experiments/tokyo_cell_pairing.gd")
const Merger := preload("res://scripts/tests/build_tokyo_joined_cells.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Audit := preload("res://scripts/tests/test_tokyo_indexed_mesh.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var costs := [[0., 1., 2., 9.], [0., 0., 9., 2.], [0., 0., 0., 100.], [0., 0., 0., 0.]]
	_check(Pairing.solve(costs) == [Vector2i(0, 2), Vector2i(1, 3)], "global matching avoids greedy cheapest-edge trap")
	_check(Pairing.solve([[0., 0., 0., 0.], [0., 0., 0., 0.], [0., 0., 0., 0.], [0., 0., 0., 0.]]) == [Vector2i(0, 1), Vector2i(2, 3)], "tie order is deterministic")
	var path := "res://resources/maps/tokyo_volume_preview/r29_cells/index.res"
	if ResourceLoader.exists(path):
		var current: Resource = load(path)
		var control: Resource = load("res://resources/maps/tokyo_volume_preview/r26b_cells/index.res")
		_check(current.valid() and current.source_hash == control.source_hash and current.coverage_rects == control.coverage_rects,
			"spatial candidate preserves complete source and L-shaped coverage")
		_check(current.shadow_cells == control.cells, "shadow source envelopes remain identical despite draw regrouping")
		var malformed: Resource = current.duplicate(false)
		malformed.shadow_cells = current.shadow_cells.duplicate()
		malformed.shadow_cells.pop_back()
		_check(not malformed.valid(), "partial shadow source coverage is rejected")
		var consumed: Dictionary = {}
		var identities: Dictionary = {}
		var audit := Audit.new()
		for entry: Dictionary in current.cells:
			var original: Resource = load(current.joined_sources[entry.region].index)
			var parts: Array = []
			for id: int in entry.part_ids:
				var key := "%s/%d" % [entry.region, id]
				_check(not consumed.has(key), "each original package consumed once")
				consumed[key] = true
				parts.append(original.cells[id])
			var expected_ids := PackedStringArray()
			for part: Dictionary in parts:
				for identity: String in load(part.levels[0].path).source_ids:
					if identity not in original.regional_nonowner_ids:
						expected_ids.append(identity)
						_check(not identities.has(identity), "unique owner identity retained")
						identities[identity] = true
			expected_ids.sort()
			var height_hash := ""
			for slot in range(-1, 7):
				var next_path: String = entry.fixed if slot < 0 else (entry.mid.path if slot == 6 else entry.levels[slot].path)
				var target: Resource = ResourceLoader.load(next_path, "", ResourceLoader.CACHE_MODE_IGNORE)
				var sources: Array = []
				for part: Dictionary in parts:
					var source_path: String = part.fixed if slot < 0 else (part.mid.path if slot == 6 else part.levels[slot].path)
					sources.append(ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE))
				_check(target.valid(), "native target structurally valid")
				if slot >= 0:
					if slot == 0:
						height_hash = target.height_hash
					_check(target.source_ids == expected_ids and target.height_hash == height_hash, "seven levels preserve owner IDs and heights")
				var byte_count := 0
				var triangles := 0
				for kind in target.meshes.size():
					var mesh: ArrayMesh = target.meshes[kind]
					var expected := Merger.merge_meshes([sources[0].meshes[kind], sources[1].meshes[kind]])
					_check(audit._same_corners(expected, mesh), "ordered corners normals colors and AABB unchanged")
					byte_count += Builder.mesh_bytes(mesh)
					triangles += Indexed.triangles(mesh)
				if sources[0].precision_original != null or sources[1].precision_original != null:
					var guards: Array = []
					for source: Resource in sources:
						guards.append(source.precision_original if source.precision_original != null else source.meshes[0])
					_check(target.precision_original != null and audit._same_corners(Merger.merge_meshes(guards), target.precision_original), "complete original precision fallback preserved")
					byte_count += Builder.mesh_bytes(target.precision_original)
					_check(Indexed.triangles(target.precision_original) == target.precision_triangles, "fallback actual triangle accounting")
				_check(triangles == target.triangles and byte_count == target.geometry_bytes, "actual indices and all resident bytes counted")
		_check(consumed.size() == 32 and identities.size() == 69775, "all source cells and unique identities retained")
	print("[Tokyo spatial test] pass=", _pass, " fail=", _fail)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Tokyo spatial test] " + label)
