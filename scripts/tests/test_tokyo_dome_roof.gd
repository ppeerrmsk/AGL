extends RefCounted
const Dome := preload("res://scripts/experiments/tokyo_dome_roof.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var points: Array = []
	for i in 19:
		points.append([-5316.0 + cos(TAU * i / 19.0) * 1.3, -509.0 + sin(TAU * i / 19.0) * 1.3])
	var raw := {"height_source": "height", "height_m": 51.0, "min_height_m": 6.0,
		"source_tags": {"roof:shape": "dome", "roof:height": "5 m"}, "rings": [{"outer": points, "holes": []}]}
	var source := JSON.stringify(raw)
	var previous := 0
	for scale_value: float in [0.1, 0.2, 0.4, 0.8, 1.6, 3.2, 12.0]:
		var result := Dome.build(raw, scale_value)
		_check(result.status == "ready", "valid dome at scale %.1f" % scale_value)
		if result.status != "ready":
			continue
		_check(result.error_px <= 0.350001 and result.bands >= previous, "bounded arc error and monotonic detail")
		previous = result.bands
		_check(result.top == 25.5 and result.eave == 23.0 and result.bottom == 3.0, "total/eave/min height conserved")
		var area := 0.0
		var top := -INF
		var outward := true
		var contained := true
		for index in range(0, result.volume.roof.size(), 3):
			var a := _vector(result.volume.roof[index])
			var b := _vector(result.volume.roof[index + 1])
			var c := _vector(result.volume.roof[index + 2])
			var normal := (b - a).cross(c - a)
			outward = outward and normal.y > 0
			area += normal.y * 0.5
			for p: Vector3 in [a, b, c]:
				top = maxf(top, p.y)
				contained = contained and p.y >= 23.0 and p.y <= 25.5
				for edge in points.size():
					var u := Vector2(points[edge][0], points[edge][1])
					var v := Vector2(points[(edge + 1) % points.size()][0], points[(edge + 1) % points.size()][1])
					contained = contained and (v - u).cross(Vector2(p.x, p.z) - u) >= -0.002
		_check(outward and contained and top == 25.5, "upward nondegenerate roof stays inside source and reaches exact top")
		var polygon_area := 0.0
		for i in points.size():
			var p := Vector2(points[i][0] + 5316.0, points[i][1] + 509.0)
			var q := Vector2(points[(i + 1) % points.size()][0] + 5316.0, points[(i + 1) % points.size()][1] + 509.0)
			polygon_area += p.cross(q) * 0.5
		_check(absf(area - polygon_area) < 0.004, "roof projection covers original footprint without hole/overlap")
		for index in range(0, result.volume.walls.size(), 3):
			var a := _vector(result.volume.walls[index])
			var b := _vector(result.volume.walls[index + 1])
			var c := _vector(result.volume.walls[index + 2])
			_check((b - a).cross(c - a).dot((a + b + c) / 3.0 - Vector3(-5316, 0, -509)) > 0, "wall faces outward")
	var reversed := raw.duplicate(true)
	reversed.rings[0].outer.reverse()
	_check(Dome.build(reversed, 12.0).status == "ready", "reversed ring accepted without source normalization")
	var broken := raw.duplicate(true)
	broken.rings[0].holes = [[[0, 0], [1, 0], [0, 1]]]
	_check(Dome.build(broken, 1.0).status == "unsupported_topology", "courtyard is never filled")
	broken = raw.duplicate(true)
	broken.rings[0].outer = [[0, 0], [4, 0], [1, 1], [4, 4], [0, 4]]
	_check(Dome.build(broken, 1.0).status == "nonconvex_polygon", "concavity explicitly deferred")
	broken = raw.duplicate(true)
	broken.rings[0].outer = [[0, 0], [4, 0], [4, 4], [0, 4]]
	_check(Dome.build(broken, 1.0).status == "dome_base_unresolved", "rectangular building is not assumed to locate a round dome")
	_check(Dome.build(broken, 1.0, false).status == "ready", "R17 first prototype remains reproducible")
	for bad in ["", "NaN", "Infinity", "5 ft", "-1", "60"]:
		broken = raw.duplicate(true)
		broken.source_tags["roof:height"] = bad
		_check(Dome.build(broken, 1.0).status != "ready", "invalid roof height rejected: " + bad)
	_check(Dome.build(raw, 1000000.0).status == "error_budget_exceeded", "excess detail request fails rather than hiding error")
	_check(JSON.stringify(raw) == source, "all source records remain immutable")
	print("[Tokyo dome test] pass=", _pass, " fail=", _fail)


func _vector(raw: Array) -> Vector3:
	return Vector3(raw[0], raw[1], raw[2])


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL dome: ", message)
