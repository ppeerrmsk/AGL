extends RefCounted
const Shared := preload("res://scripts/rendering/tokyo_shared_page.gd")
const Canonical := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var item := Shared.new()
	item.source_hash = "s".repeat(64)
	item.meshes.assign([ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()])
	item.mesh_bytes = PackedInt32Array([0, 0, 0, 0])
	var source := Canonical.new()
	source.level = 2
	source.parent_id = 8
	source.source_hash = "a".repeat(64)
	source.owners_sha256 = "b".repeat(64)
	source.collision_sha256 = "c".repeat(64)
	for name_value: String in ["lod2_full", "lod2_guarded"]:
		source.configuration = name_value
		item.variants[name_value] = {"path": name_value + ".res", "sha256": "d".repeat(64),
			"identity": source.stream_identity(), "slots": PackedInt32Array([0 if name_value.ends_with("full") else 3, 1, 2])}
	_check(item.valid(), "complete shared pair")
	var full: Array[ArrayMesh] = item.variant_meshes("lod2_full")
	var guarded: Array[ArrayMesh] = item.variant_meshes("lod2_guarded")
	_check(full[0] != guarded[0] and full[1] == guarded[1] and full[2] == guarded[2], "actual shared mesh identities")
	_check(item.variant_meshes("foreign").is_empty(), "unknown logical page rejected")
	var stream := Stream.new()
	stream._descriptors["pair"] = {"bytes": 0, "canonical_identity": item.stream_identity()}
	_check(stream._matches(item, "pair"), "native shared format accepted with its own identity")
	stream._descriptors.pair.canonical_identity = source.stream_identity()
	_check(not stream._matches(item, "pair"), "shared bundle cannot masquerade as original canonical page")
	stream._descriptors.pair.canonical_identity = item.stream_identity()
	stream._descriptors.pair.bytes = 1
	_check(not stream._matches(item, "pair"), "incorrect actual storage budget rejected")
	stream.free()
	item.geometry_bytes = 1
	_check(not item.valid(), "cost sum mismatch rejected")
	item.geometry_bytes = 0
	item.mesh_bytes[0] = -1
	_check(not item.valid(), "negative mesh cost rejected")
	item.mesh_bytes[0] = 0
	item.variants.lod2_guarded.slots[0] = 99
	_check(not item.valid(), "invalid mesh slot rejected")
	item.variants.lod2_guarded.slots[0] = 0
	_check(not item.valid(), "unreferenced stored mesh rejected")
	item.variants.lod2_guarded.slots[0] = 3
	var old := item.meshes[3]
	item.meshes[3] = item.meshes[0]
	_check(not item.valid(), "same instance cannot be accounted twice")
	item.meshes[3] = old
	for key: String in ["parent", "cell", "ancestor", "level", "collision", "owners", "game_sources"]:
		var original: Variant = item.variants.lod2_guarded.identity[key]
		item.variants.lod2_guarded.identity[key] = "foreign"
		_check(not item.valid(), "foreign source domain rejected: " + key)
		item.variants.lod2_guarded.identity[key] = original
	item.variants.lod2_full.identity.parent = 20
	item.variants.lod2_guarded.identity.parent = 20
	_check(not item.valid(), "equally invalid spatial identities rejected")
	item.variants.lod2_full.identity.parent = 8
	item.variants.lod2_guarded.identity.parent = 8
	item.variants.lod2_guarded = 7
	_check(not item.valid(), "invalid metadata type rejected safely")
	_check(load("res://scripts/tests/build_tokyo_shared_pages.gd").can_instantiate(), "builder compiles")
	_check(load("res://scripts/tests/tokyo_shared_stream_case.gd").can_instantiate(), "native lifecycle fixture compiles")
	print("[R68 shared test] pass=", _pass, " fail=", _fail)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] R68 shared: " + label)
