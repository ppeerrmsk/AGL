extends RefCounted
const Page := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var page := Page.new()
	page.configuration = "lod5_full"
	page.level = 5
	page.parent_id = 8
	page.cell_id = 192
	page.ancestor_id = 32
	page.source_hash = "a".repeat(64)
	page.owners_sha256 = "b".repeat(64)
	page.collision_sha256 = "c".repeat(64)
	page.game_sources = PackedInt32Array([1, 4, 19])
	page.meshes.assign([ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()])
	var identity := page.stream_identity()
	var stream := Stream.new()
	stream._descriptors["page"] = {"bytes": 0, "canonical_identity": identity.duplicate()}
	_check(stream._matches(page, "page"), "canonical independent identity without old height hash")
	stream._descriptors["legacy"] = {"id": 192, "level": 5, "bytes": 0, "height_hash": page.source_hash}
	_check(not stream._matches(page, "legacy"), "new archive cannot masquerade as a legacy height-hash package")
	for key: String in identity:
		stream._descriptors.page.canonical_identity[key] = "foreign"
		_check(not stream._matches(page, "page"), "foreign identity rejected: " + key)
		stream._descriptors.page.canonical_identity = identity.duplicate()
	stream._descriptors.page.bytes = 1
	_check(not stream._matches(page, "page"), "wrong decoded byte reservation rejected")
	stream._descriptors.page.bytes = 0
	page.game_sources.append(999)
	_check(not stream._matches(page, "page"), "game source ownership drift rejected")
	page.game_sources = PackedInt32Array([1, 4, 19])
	page.schema_version = 99
	_check(not stream._matches(page, "page"), "invalid archive rejected before identity")
	page.schema_version = 1
	stream.free()
	var catalog := Catalog.new()
	catalog.owners_sha256 = page.owners_sha256
	catalog.collision_sha256 = page.collision_sha256
	catalog.descriptors["page"] = {"bytes": 0, "canonical_identity": identity}
	var leaf := {"path": "page", "parent_id": 8, "cell_id": 192, "ancestor_id": 32, "level": 5, "bytes": 0,
		"boxes": [AABB(), AABB(), AABB()], "triangles": PackedInt32Array([0, 0, 0])}
	_check(catalog._entry_valid(leaf, "lod5_full", 8, 192, 32, {}), "valid empty coastal leaf metadata")
	_check(not catalog._entry_valid(leaf, "lod4_full", 8, 192, 32, {}), "catalog cross configuration rejected")
	_check(not catalog._entry_valid(leaf, "lod5_full", 8, 192, 32, {"page": true}), "duplicate page rejected")
	leaf.boxes[0] = AABB(Vector3(INF, 0, 0), Vector3.ONE)
	_check(not catalog._entry_valid(leaf, "lod5_full", 8, 192, 32, {}), "nonfinite page bounds rejected")
	_check(not catalog.valid(), "partial catalog cannot pass as eleven full configurations")
	_check(load("res://scripts/tests/build_tokyo_canonical_catalog.gd").can_instantiate(), "catalog builder compiles")
	_check(load("res://scripts/tests/tokyo_canonical_stream_case.gd").can_instantiate(), "native stream lifecycle compiles")
	_check(load("res://scripts/tests/tokyo_canonical_cut_probe.gd").can_instantiate(), "read-only cut budget probe compiles")
	var coverage: RefCounted = load("res://scripts/tests/test_tokyo_source_coverage.gd").new()
	coverage.run()
	_pass += coverage._pass
	_fail += coverage._fail
	var shared: RefCounted = load("res://scripts/tests/test_tokyo_shared_page.gd").new()
	shared.run()
	_pass += shared._pass
	_fail += shared._fail
	var components: RefCounted = load("res://scripts/tests/test_tokyo_components.gd").new()
	components.run()
	_pass += components._pass
	_fail += components._fail
	var ground: RefCounted = load("res://scripts/tests/test_tokyo_tile_ground.gd").new()
	ground.run()
	_pass += ground._pass
	_fail += ground._fail
	print("[Tokyo canonical stream test] pass=", _pass, " fail=", _fail)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] Tokyo canonical stream: " + label)
