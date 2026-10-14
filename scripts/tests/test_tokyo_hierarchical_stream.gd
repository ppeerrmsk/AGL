extends RefCounted
const Overlay := preload("res://scripts/rendering/tokyo_hierarchical_overlay.gd")
const Stream := preload("res://scripts/rendering/tokyo_cell_stream.gd")
const Leaf := preload("res://scripts/rendering/tokyo_spatial_leaf.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_check(load("res://scripts/tests/tokyo_hierarchical_lifecycle_case.gd").can_instantiate(), "real lifecycle fixture compiles")
	_check(load("res://scripts/tests/tokyo_hierarchical_review.gd").can_instantiate(), "native review fixture compiles")
	var entries: Array[Dictionary] = [{"building": "old", "fixed": "shared"}, {"path": "leaf"}, {"path": "leaf"}]
	var paths := Overlay.paths_for(entries)
	_check(paths == PackedStringArray(["shared", "old", "leaf"]), "whole cut resource paths are unique")
	var descriptors := {"old": {"bytes": 30}, "new": {"bytes": 50}, "shared": {"bytes": 10}, "leaf": {"bytes": 20}}
	_check(Overlay.union_bytes(paths, PackedStringArray(["new", "shared"]), descriptors) == 110, "old new fixed and leaf bytes share one authority")
	_check(Overlay.union_bytes(PackedStringArray(["missing"]), paths, descriptors) > Stream.BUDGET, "unknown descriptor fails closed")
	descriptors.old.bytes = -1
	_check(Overlay.union_bytes(paths, PackedStringArray(), descriptors) > Stream.BUDGET, "negative byte metadata rejected")
	var item := Leaf.new()
	item.schema_version = 2
	item.cell_id = 192
	item.parent_id = 8
	item.ancestor_id = 32
	item.height_hash = "a".repeat(64)
	item.source_hash = "b".repeat(64)
	item.meshes.assign([ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()])
	var stream := Stream.new()
	stream._descriptors["leaf"] = {"id": 192, "level": 5, "bytes": 0, "height_hash": item.height_hash, "source_hash": item.source_hash}
	_check(stream._matches(item, "leaf"), "native hierarchical leaf accepted by existing stream")
	stream._descriptors.leaf.source_hash = "c".repeat(64)
	_check(not stream._matches(item, "leaf"), "same height and ID cannot disguise a foreign parent source")
	var wanted := PackedStringArray(["leaf"])
	var pins := PackedStringArray(["leaf"])
	stream.request(wanted, pins)
	stream._cache["leaf"] = item
	wanted.clear()
	pins.clear()
	_check(stream._wanted == PackedStringArray(["leaf"]) and stream._pins == PackedStringArray(["leaf"]), "caller mutations cannot erase stream ownership state")
	stream.request(wanted, pins)
	_check(stream._cache.is_empty(), "empty request after caller clear still prunes cache")
	_check(stream._audit_evictions.is_empty(), "path audit allocates no records by default")
	stream._audit_paths = true
	stream._cache["leaf"] = item
	stream._prune()
	_check(stream._audit_evictions.get("leaf", 0) == 1, "path audit counts actual eviction")
	stream._prune()
	_check(stream._audit_evictions.get("leaf", 0) == 1, "empty prune cannot duplicate eviction")
	var audit: Dictionary = stream.summary()
	audit.path_evictions.clear()
	_check(stream._audit_evictions.size() == 1, "summary cannot mutate audit ownership")
	stream._retain_unused = true
	item.geometry_bytes = 40
	stream._cache["leaf"] = item
	stream._bytes = 40
	stream._auxiliary_bytes = Stream.BUDGET - 100
	stream._prune()
	_check(stream._cache.has("leaf"), "candidate retains idle resource inside existing budget")
	stream._pins = PackedStringArray(["leaf"])
	stream._prune(80)
	_check(stream._cache.has("leaf"), "candidate never evicts pinned geometry")
	stream._pins.clear()
	stream._reserved = 30
	stream._prune(40)
	_check(stream._cache.is_empty() and stream._bytes == 0, "candidate counts pending reservations before eviction")
	stream._reserved = 0
	stream._cache["leaf"] = item
	stream._bytes = 40
	_check(stream.reserve_auxiliary(123, 80) and stream._bytes == 0, "auxiliary reservation can reclaim only idle geometry")
	_check(stream._auxiliary_bytes + stream._bytes + stream._reserved <= Stream.BUDGET, "candidate preserves shared hard budget")
	stream.free()
	print("[Tokyo hierarchical stream test] pass=", _pass, " fail=", _fail)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo hierarchical stream: " + label)
