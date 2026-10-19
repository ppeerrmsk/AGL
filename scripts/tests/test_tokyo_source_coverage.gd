extends RefCounted
const Coverage := preload("res://scripts/experiments/tokyo_source_coverage.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_check(preload("res://scripts/tests/test_tokyo_grid_coverage.gd").checks()==0,"grid commit dependency counterexamples")
	var data := {"schema": 1, "verified": true, "configuration": "lod5_full", "collision_sha256": "collision", "catalog_sha256": "catalog",
		"sources": {131: PackedStringArray(["a:1", "b:0"]), 132: PackedStringArray(["a:1"])}, "pages": {}}
	data.pages.root = {"identity": {"id": "root"}, "leaves": PackedStringArray(["a", "b"]), "tokens": [PackedStringArray(["b:0"]), PackedStringArray(["a:1"])]}
	data.pages.a = {"identity": {"id": "a"}, "leaves": PackedStringArray(["a"]), "tokens": [PackedStringArray(), PackedStringArray(["a:1"])]}
	data.pages.b = {"identity": {"id": "b"}, "leaves": PackedStringArray(["b"]), "tokens": [PackedStringArray(["b:0"]), PackedStringArray()]}
	var root := {"root": {"identity": {"id": "root"}, "layers": 3}}
	var a := {"a": {"identity": {"id": "a"}, "layers": 2}}
	var both := a.duplicate(true)
	both.b = {"identity": {"id": "b"}, "layers": 1}
	_check(_covered(data, {}).is_empty(), "cached/requested pages are not committed")
	_check(_covered(data, root) == PackedInt32Array([131, 132]), "ancestor substitutes all required leaves")
	_check(_covered(data, a) == PackedInt32Array([132]), "missing shared roof fragment keeps the partial old building")
	_check(_covered(data, both) == PackedInt32Array([131, 132]), "cross-page and cross-layer dependency")
	both.b.layers = 2
	_check(_covered(data, both) == PackedInt32Array([132]), "resident page with wrong visible layer is insufficient")
	both.b.layers = 1
	var overlap := both.duplicate(true)
	overlap.merge(root)
	_check(_covered(data, overlap).is_empty(), "overlapping ancestor/child cut rejected")
	var bad := root.duplicate(true)
	bad.root.identity.id = "foreign"
	_check(_covered(data, bad).is_empty(), "wrong actual page identity")
	_check(_covered(data, {"unknown": root.root}).is_empty(), "unknown page rejected")
	for value: Variant in [null, "3", -1, 8]:
		bad = root.duplicate(true)
		bad.root.layers = value
		_check(_covered(data, bad).is_empty(), "malformed visible layer mask")
	for field: String in ["schema", "verified", "configuration", "collision_sha256", "catalog_sha256", "pages", "sources"]:
		var altered := data.duplicate(true)
		altered.erase(field)
		_check(_covered(altered, root).is_empty(), "missing sidecar identity: " + field)
	_check(Coverage.covered_sources(data, root, "lod4_full", "collision", "catalog").is_empty(), "wrong LOD configuration")
	_check(Coverage.covered_sources(data, root, "lod5_full", "foreign", "catalog").is_empty(), "wrong collision authority")
	_check(Coverage.covered_sources(data, root, "lod5_full", "collision", "foreign").is_empty(), "wrong catalog provenance")
	data.sources[133] = PackedStringArray()
	_check(not _covered(data, root).has(133), "empty requirement cannot vacuously hide an old building")
	_check(load("res://scripts/tests/build_tokyo_source_coverage.gd").can_instantiate(), "offline face coverage builder compiles")
	_test_faces()
	_check(load("res://scripts/rendering/tokyo_canonical_overlay.gd").can_instantiate(), "complete canonical renderer compiles")
	_check(load("res://scripts/tests/tokyo_canonical_review.gd").can_instantiate(), "actual Survivor canonical review compiles")
	print("[Tokyo source coverage test] pass=", _pass, " fail=", _fail)


static func _covered(data: Dictionary, cut: Dictionary) -> PackedInt32Array:
	return Coverage.covered_sources(data, cut, "lod5_full", "collision", "catalog")


func _test_faces() -> void:
	var builder: Script = load("res://scripts/tests/build_tokyo_source_coverage.gd")
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array([Vector3(-5000, 8, -300), Vector3(-4990, 8, -300), Vector3(-5000, 8, -290)])
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 1, 2, 0, 2, 1])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var faces: Array = builder._faces(mesh)
	_check(faces.size() == 3 and faces[0] == vertices.to_byte_array(), "actual indexed packed float32 face")
	_check(faces[0] == faces[1] and faces[0] != faces[2], "multiplicity retained and reverse winding not equivalent")
	var expected: Dictionary = {}
	builder._add(expected, 3, 1, faces[0], PackedInt32Array([131]))
	builder._add(expected, 3, 1, faces[1], PackedInt32Array([132]))
	_check(expected[3][1][faces[0]].count == 2 and expected[3][1][faces[0]].sources == PackedInt32Array([131, 132]), "coincident faces retain count and both source dependencies")
	vertices[0].x += 0.001
	_check(vertices.to_byte_array() != faces[0], "millimeter float32 displacement does not pass geometric equality")


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] Tokyo source coverage test: " + label)
