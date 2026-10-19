extends RefCounted
const Gate := preload("res://scripts/experiments/tokyo_regional_ownership.gd")
const Index := preload("res://scripts/rendering/tokyo_cell_index.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var digest := "a".repeat(64)
	var original := {"rect": [0, 0, 10, 10], "buildings": [{"id": "w1", "height_m": 90.0, "rings": [{"holes": []}]}]}
	var data := original.duplicate(true)
	data["regional_ownership"] = {"schema_version": 1, "joined_only": true, "region_id": "north", "registry_sha256": digest}
	data.buildings[0]["regional_draw_owner"] = "south"
	var registry := {"schema_version": 1, "joined_only": true, "regions": ["north", "south"],
		"assignments": {"w1": {"owner": "south", "regions": ["north", "south"]}}}
	var before := JSON.stringify([data, original, registry])
	var accepted := Gate.validate(data, original, registry, "north", digest)
	_check(accepted.get("nonowner_ids", []) == PackedStringArray(["w1"]), "matching source yields only explicit nonowner")
	_check(not Gate.validate(JSON.parse_string(JSON.stringify(data)), JSON.parse_string(JSON.stringify(original)),
		JSON.parse_string(JSON.stringify(registry)), "north", digest).is_empty(), "JSON numeric schema survives native parsing")
	_check(JSON.stringify([data, original, registry]) == before, "gate does not mutate source data")
	for fault: String in ["height", "hole", "owner", "hash", "region", "missing_source", "duplicate", "header", "missing_copy", "extra_assignment", "fractional_schema", "text_schema"]:
		var changed := data.duplicate(true)
		var altered_registry := registry.duplicate(true)
		match fault:
			"height": changed.buildings[0].height_m = 89.0
			"hole": changed.buildings[0].rings[0].holes = [[[1, 1], [2, 1], [1, 2]]]
			"owner": changed.buildings[0].regional_draw_owner = "north"
			"hash": changed.regional_ownership.registry_sha256 = "b".repeat(64)
			"region": changed.regional_ownership.region_id = "south"
			"missing_source": changed.buildings.clear()
			"duplicate": changed.buildings.append(changed.buildings[0])
			"header": changed.rect[0] = -1
			"missing_copy": altered_registry.assignments.w1.regions = ["north"]
			"extra_assignment": altered_registry.assignments.w2 = {"owner": "north", "regions": ["north"]}
			"fractional_schema": changed.regional_ownership.schema_version = 1.5
			"text_schema": changed.regional_ownership.schema_version = "1"
		_check(Gate.validate(changed, original, altered_registry, "north", digest).is_empty(), "gate rejects " + fault)
	var index: Resource = load(Index.PATH).duplicate(true)
	_check(index.valid(), "legacy index accepted without joined context")
	index.regional_id = "north"
	_check(not index.valid(digest), "partial joined metadata rejected")
	index.regional_registry_hash = digest
	index.regional_nonowner_ids = PackedStringArray(["w1"])
	_check(not index.valid(), "joined-only archive rejected by ordinary overlay validation")
	_check(not index.valid("b".repeat(64)), "wrong registry context rejected")
	_check(index.valid(digest), "matching digest permits offline structural validation only")
	print("[Tokyo regional gate] pass=", _pass, " fail=", _fail)


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL regional: ", message)
