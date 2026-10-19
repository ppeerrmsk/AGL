extends RefCounted
const Pair := preload("res://scripts/experiments/tokyo_cluster_cut.gd")
const Hierarchy := preload("res://scripts/rendering/tokyo_hierarchical_overlay.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_check(load("res://scripts/rendering/tokyo_cluster_overlay.gd").can_instantiate(), "cluster controller compiles")
	_check(load("res://scripts/tests/tokyo_cluster_runtime_review.gd").can_instantiate(), "continuous native review compiles")
	_check(load("res://scripts/tests/tokyo_cluster_lifecycle_case.gd").can_instantiate(), "cluster lifecycle compiles")
	var reference := {"key": "fine", "parent_id": 0, "cell_id": -1, "building": "fine", "fixed": "fixed",
		"boxes": [AABB(Vector3(-4, 0, -4), Vector3(8, 7, 8)), AABB(), AABB()], "triangles": [10, 0, 0], "bytes": 70}
	var candidate := {"key": "coarse", "parent_id": 0, "cell_id": -1, "building": "coarse", "fixed": "fixed",
		"boxes": [AABB(Vector3.ZERO, Vector3.ONE), AABB(), AABB()], "triangles": [4, 0, 0], "bytes": 40}
	var descriptors := {"coarse": {"bytes": 30}, "fine": {"bytes": 60}, "fixed": {"bytes": 10}}
	var decorated := Pair.decorate(candidate, reference, descriptors)
	_check(decorated.bytes == 100 and candidate.bytes == 40, "fallback counted exactly once without mutating source catalog")
	_check(decorated.boxes[0] == reference.boxes[0] and candidate.boxes[0] != reference.boxes[0], "culling includes complete original roof and shadow envelope")
	var entries: Array[Dictionary] = [decorated]
	var paths := Pair.paths(entries)
	_check(paths == PackedStringArray(["fixed", "coarse", "fine"]), "visible candidate and original fallback share unique stream paths")
	_check(Pair.original_cut(entries) == [reference], "fallback restores complete native source entry")
	_check(Hierarchy.union_bytes(paths, PackedStringArray(["fine"]), descriptors) == 100, "already pinned original not double counted")
	entries.append(decorated)
	_check(Pair.paths(entries) == paths, "duplicate packages do not inflate ownership")
	_check(not candidate.has("fallback") and not reference.has("fallback"), "source metadata stays immutable")
	descriptors.erase("fine")
	_check(Pair.decorate(candidate, reference, descriptors).bytes > 96 * 1024 * 1024, "missing fallback descriptor cannot pass admission")
	reference.triangles[1] = 3
	reference.boxes[1] = AABB(Vector3.ZERO, Vector3(3, 9, 3))
	var guarded := Pair.decorate(candidate, reference, descriptors)
	_check(guarded.triangles[1] > 0 and guarded.boxes[1] == reference.boxes[1], "fine-only marked building cannot disappear from paired culling")
	_check(Pair.fallback_visible(guarded, Rect2(-20, -20, 40, 40), Transform2D.IDENTITY, Vector2(40, 40), Vector2.ZERO, Vector2.ZERO), "in-view fallback prevents retirement even if candidate is not visible")
	_check(not Pair.fallback_visible(guarded, Rect2(100, 100, 10, 10), Transform2D.IDENTITY, Vector2(40, 40), Vector2.ZERO, Vector2.ZERO), "fully offscreen fallback may retire with the old cut")
	print("[Tokyo cluster stream test] pass=", _pass, " fail=", _fail)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo cluster stream: " + label)
