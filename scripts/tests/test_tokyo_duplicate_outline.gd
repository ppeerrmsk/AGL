extends RefCounted
const Duplicates := preload("res://scripts/experiments/tokyo_duplicate_outline.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var low := source_fixture()
	var known := low.duplicate(true)
	known.id = "known"
	known.height_source = "height"
	known.height_m = 90.0
	var original := JSON.stringify([low, known])
	_check(Duplicates.suppressed([low, known]) == {low.id: "known"}, "explicit height suppresses only matching fallback shell")
	_check(JSON.stringify([low, known]) == original, "source records including identity and name unchanged")
	_check(Duplicates.suppressed([known, low]) == {low.id: "known"}, "input order independent")
	var rotated := known.duplicate(true)
	rotated.points.reverse()
	rotated.rings[0].outer = rotated.points.slice(2) + rotated.points.slice(0, 2)
	_check(Duplicates.suppressed([low, rotated]).size() == 1, "exact ring accepts reverse winding and cyclic start")
	for field: String in ["is_part", "defer_render", "parents", "parts", "min_height_m", "roof_shape", "height_m"]:
		var altered := low.duplicate(true)
		altered[field] = {"is_part": true, "defer_render": true, "parents": ["parent"], "parts": ["child"],
			"min_height_m": 1.0, "roof_shape": "dome", "height_m": INF}[field]
		_check(Duplicates.suppressed([altered, known]).is_empty(), "unsafe source stays: " + field)
	var hole := low.duplicate(true)
	hole.rings[0].holes = [[[0, 0], [1, 0], [0, 1]]]
	_check(Duplicates.suppressed([hole, known]).is_empty(), "courtyard not merged from outer ring alone")
	var higher := low.duplicate(true)
	higher.height_m = 100.0
	_check(Duplicates.suppressed([higher, known]).is_empty(), "taller fallback is unresolved, not silently shortened")
	var conflicting := known.duplicate(true)
	conflicting.id = "other_known"
	_check(Duplicates.suppressed([low, known, conflicting]).is_empty(), "multiple explicit records remain unresolved")
	var near := known.duplicate(true)
	near.points[0][0] += 0.000001
	near.rings[0].outer = near.points.duplicate(true)
	_check(Duplicates.suppressed([low, near]).is_empty(), "sub-Vector2-precision source difference is not rounded away")
	var levels := known.duplicate(true)
	levels.height_source = "levels"
	_check(Duplicates.suppressed([low, levels]).is_empty(), "level estimate cannot replace explicit height authority")
	print("[Tokyo duplicate test] pass=", _pass, " fail=", _fail)


static func source_fixture() -> Dictionary:
	# R18已查实的原始估高外壳；精确顶点/三角顺序用于独立逐包几何差分。
	var points := [[-5399.392, -552.83], [-5366.935, -534.126], [-5358.497, -548.773], [-5390.954, -567.471]]
	return {"id": "w1533146860", "height_m": 20.8, "height_source": "fallback", "min_height_m": 0.0,
		"kind": "urban", "points": points, "rings": [{"outer": points.duplicate(true), "holes": [],
		"triangles": [points[3], points[1], points[2], points[1], points[3], points[0]]}]}


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL duplicate: ", message)
