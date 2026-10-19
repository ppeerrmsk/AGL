extends RefCounted
const Part := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Stream := preload("res://scripts/rendering/tokyo_component_stream.gd")
const Page := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")
const Manifest := preload("res://scripts/rendering/tokyo_component_manifest.gd")
const Cut := preload("res://scripts/rendering/tokyo_hierarchical_overlay.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var costs := {"f": {"bytes": 30, "components": {"low": {"bytes": 10}, "common": {"bytes": 20}}},
		"g": {"bytes": 50, "components": {"original": {"bytes": 30}, "common": {"bytes": 20}}}}
	_check(Cut.union_bytes(PackedStringArray(["f", "g"]), PackedStringArray(["f"]), costs) == 60, "shared cost counted once across wanted and pinned")
	_check(Cut.union_bytes(PackedStringArray(["f"]), PackedStringArray(["f"]), costs) == 30, "single view costs its actual dependencies")
	costs.g.components.common.bytes = 21
	_check(Cut.union_bytes(PackedStringArray(["f", "g"]), PackedStringArray(), costs) > Stream.BUDGET, "conflicting shared costs fail closed")
	_check(Cut.union_bytes(PackedStringArray(["missing"]), PackedStringArray(), costs) > Stream.BUDGET, "missing logical page rejected")
	var physical: Dictionary = {}
	var native: Dictionary = {}
	for name_value: String in ["low", "guard", "common"]:
		var component := Part.new()
		component.source_hash = name_value.sha256_text()
		component.meshes.assign([ArrayMesh.new(), ArrayMesh.new()] if name_value == "common" else [ArrayMesh.new()])
		component.mesh_bytes.resize(component.meshes.size())
		_check(component.valid(), "valid native component: " + name_value)
		physical[name_value] = {"path": name_value, "bytes": 0, "canonical_identity": component.stream_identity()}
		native[name_value] = component
	var descriptor := Page.new()
	descriptor.level = 2
	descriptor.parent_id = 0
	descriptor.source_hash = "a".repeat(64)
	descriptor.collision_sha256 = "b".repeat(64)
	descriptor.owners_sha256 = "c".repeat(64)
	descriptor.game_sources = PackedInt32Array([1, 4])
	var logical: Dictionary = {}
	for mode: String in ["f", "g"]:
		descriptor.configuration = "lod2_full" if mode == "f" else "lod2_guarded"
		var low := "low" if mode == "f" else "guard"
		logical[mode] = {"bytes": 0, "canonical_identity": descriptor.stream_identity(), "game_sources": descriptor.game_sources,
			"triangles": 0, "components": {low: physical[low], "common": physical.common}, "mapping": [[low, 0], ["common", 0], ["common", 1]]}
		_check(Manifest.valid_row(logical[mode], logical[mode], physical), "valid dependency mapping")
	var invalid: Dictionary = logical.f.duplicate(true)
	invalid.mapping[2][1] = 2
	_check(not Manifest.valid_row(invalid, logical.f, physical), "out of range component mesh index rejected")
	invalid = logical.f.duplicate(true)
	invalid.game_sources.append(999)
	_check(not Manifest.valid_row(invalid, logical.f, physical), "logical coverage source drift rejected")
	var owner := Node.new()
	var stream := Stream.new()
	stream.configure(owner, logical)
	stream._cache = native.duplicate()
	var full: Resource = stream.resource("f")
	var guard: Resource = stream.resource("g")
	_check(full != null and guard != null and full.stream_identity() == logical.f.canonical_identity, "logical identity preserved over physical storage")
	_check(full.meshes[1] == guard.meshes[1] and full.meshes[2] == guard.meshes[2] and full.meshes[0] != guard.meshes[0], "logical pages share actual unchanged meshes")
	stream.request(PackedStringArray(["g"]), PackedStringArray(["g"]))
	_check(not stream._cache.has("low") and stream._cache.has("common") and stream._cache.has("guard"), "fallback retires only simplified low component")
	stream._views.clear()
	stream._cache.erase("common")
	_check(stream.resource("g") == null, "partial dependency set cannot produce ready logical page")
	stream.close()
	_check(stream._views.is_empty() and stream._cache.is_empty(), "close releases views and physical references")
	stream.free()
	owner.free()
	for path: String in ["res://scripts/tests/build_tokyo_mesh_components.gd", "res://scripts/rendering/tokyo_canonical_overlay.gd", "res://scripts/rendering/tokyo_volume_preload.gd", "res://scripts/tests/tokyo_component_review.gd"]:
		_check(load(path).can_instantiate(), "candidate integration compiles: " + path)
	var cross: RefCounted = load("res://scripts/tests/test_tokyo_cross_lod_components.gd").new()
	cross.run()
	_pass += cross._pass
	_fail += cross._fail
	print("[R69 components test] pass=", _pass, " fail=", _fail)


func lifecycle(parent: Node, path: String, catalog_path: String) -> int:
	var catalog: Resource = load(catalog_path)
	var data := Manifest.read(path, catalog, FileAccess.get_sha256(catalog_path))
	if data.is_empty():
		return 1
	var wanted := PackedStringArray()
	var full := ""
	var guard := ""
	for key: String in data.pages:
		var identity: Dictionary = data.pages[key].canonical_identity
		if identity.parent == 0 and identity.cell == -1 and identity.configuration in ["lod2_full","lod2_guarded"]:
			wanted.append(key)
			if identity.configuration == "lod2_full":
				full = key
			else:
				guard = key
	if wanted.size() != 2 or full.is_empty() or guard.is_empty():
		return 1
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	stream.configure(owner, data.pages)
	stream.request(wanted, PackedStringArray())
	var deadline := Time.get_ticks_msec() + 15000
	while (stream.resource(full) == null or stream.resource(guard) == null) and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	if stream.resource(full) == null or stream.resource(guard) == null:
		owner.queue_free()
		return 1
	var full_ref: WeakRef = weakref(stream.resource(full))
	var low_ref: WeakRef = weakref(stream.resource(full).meshes[0])
	var common_ref: WeakRef = weakref(stream.resource(full).meshes[1])
	var stream_ref: WeakRef = weakref(stream)
	var before := stream.summary()
	stream.request(PackedStringArray([guard]), PackedStringArray([guard]))
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	var after := stream.summary()
	var fail := int(is_instance_valid(full_ref.get_ref()) or is_instance_valid(low_ref.get_ref()) or not is_instance_valid(common_ref.get_ref()))
	fail += int(after.bytes != data.pages[guard].bytes or after.completed != before.completed or stream.resource(guard) == null)
	stream.request(PackedStringArray([full]), PackedStringArray([guard]))
	stream._process_stream()
	var pending := not stream._pending.is_empty()
	owner.queue_free()
	deadline = Time.get_ticks_msec() + 15000
	while is_instance_valid(stream_ref.get_ref()) and Time.get_ticks_msec() < deadline:
		await parent.get_tree().process_frame
	fail += int(not pending or is_instance_valid(stream_ref.get_ref()) or is_instance_valid(common_ref.get_ref()) or not Stream._busy.is_empty())
	print("[R69 components lifecycle] before=", before, " fallback=", after, " pending_exit=", pending, " fail=", fail)
	return fail


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] R69 components: " + label)
