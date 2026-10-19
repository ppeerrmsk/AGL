extends RefCounted
## 离线来源圆顶：凸轮廓内收的椭圆弧截环；不猜高度，不改现有源记录。
const ERROR_PX := 0.35


static func build(raw: Dictionary, output_scale: float, round_only: bool = true) -> Dictionary:
	var tags: Dictionary = raw.get("source_tags", {})
	if tags.get("roof:shape", "") != "dome":
		return {"status": "not_dome"}
	var value := String(tags.get("roof:height", "")).strip_edges().trim_suffix("m").strip_edges()
	if not value.is_valid_float() or raw.get("height_source", "fallback") == "fallback":
		return {"status": "missing_height"}
	var roof_height := value.to_float() * 0.5
	var top := float(raw.get("height_m", 0.0)) * 0.5
	var bottom := maxf(0.12, float(raw.get("min_height_m", 0.0)) * 0.5)
	var eave := top - roof_height
	if not is_finite(roof_height) or roof_height <= 0 or not is_finite(top) or not is_finite(bottom) or eave <= bottom or not is_finite(output_scale) or output_scale <= 0:
		return {"status": "invalid_height_or_scale"}
	var rings: Array = raw.get("rings", [])
	if rings.size() != 1 or not (rings[0].get("holes", []) as Array).is_empty():
		return {"status": "unsupported_topology"}
	var points := PackedVector2Array()
	for point: Array in rings[0].outer:
		points.append(Vector2(point[0], point[1]))
	if points.size() < 3 or Geometry2D.triangulate_polygon(points).is_empty():
		return {"status": "invalid_polygon"}
	var center := Vector2.ZERO
	for point: Vector2 in points:
		center += point - points[0]
	center = points[0] + center / points.size()
	var orientation := 0.0
	var radius := roof_height
	var footprint_radius := 0.0
	var minimum_radius := INF
	for i in points.size():
		var cross_value := (points[(i + 1) % points.size()] - points[i]).cross(points[(i + 2) % points.size()] - points[(i + 1) % points.size()])
		if absf(cross_value) > 0.00001:
			if orientation != 0 and signf(cross_value) != orientation:
				return {"status": "nonconvex_polygon"}
			orientation = signf(cross_value)
		radius = maxf(radius, (points[i] - center).length())
		footprint_radius = maxf(footprint_radius, (points[i] - center).length())
		minimum_radius = minf(minimum_radius, (points[i] - center).length())
	if orientation == 0:
		return {"status": "invalid_polygon"}
	# 仅有方形建筑轮廓不足以定位真正圆顶，不能把它自动变成曲面金字塔。
	if round_only and (points.size() < 8 or minimum_radius <= 0 or footprint_radius / minimum_radius > 1.5):
		return {"status": "dome_base_unresolved"}
	var angle := acos(clampf(1.0 - ERROR_PX / (radius * output_scale), -1.0, 1.0))
	var bands := maxi(2, ceili(PI / (4.0 * maxf(angle, 0.000001))))
	if bands > 32:
		return {"status": "error_budget_exceeded"}
	var roof: Array = []
	var walls: Array = []
	for i in points.size():
		var p := points[i]
		var q := points[(i + 1) % points.size()]
		var a := Vector3(p.x, bottom, p.y)
		var b := Vector3(q.x, bottom, q.y)
		var c := Vector3(q.x, eave, q.y)
		var d := Vector3(p.x, eave, p.y)
		var outward := Vector3((p + q).x * 0.5 - center.x, 0, (p + q).y * 0.5 - center.y)
		_face(walls, a, b, c, outward)
		_face(walls, a, c, d, outward)
		for band in bands:
			var t0 := float(band) / bands * PI * 0.5
			var t1 := float(band + 1) / bands * PI * 0.5
			a = _point(p, center, eave, roof_height, t0)
			b = _point(q, center, eave, roof_height, t0)
			if band == bands - 1:
				_face(roof, a, b, Vector3(center.x, top, center.y), Vector3.UP)
			else:
				c = _point(q, center, eave, roof_height, t1)
				d = _point(p, center, eave, roof_height, t1)
				_face(roof, a, b, c, Vector3.UP)
				_face(roof, a, c, d, Vector3.UP)
	return {"status": "ready", "volume": {"roof": roof, "walls": walls}, "bands": bands,
		"error_px": radius * (1.0 - cos(PI / (4.0 * bands))) * output_scale,
		"top": top, "bottom": bottom, "eave": eave}


static func _point(p: Vector2, center: Vector2, eave: float, height: float, angle: float) -> Vector3:
	var xy := center + (p - center) * cos(angle)
	return Vector3(xy.x, eave + height * sin(angle), xy.y)


static func _face(output: Array, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if (b - a).cross(c - a).dot(outward) < 0:
		var swap := b
		b = c
		c = swap
	output.append_array([[a.x, a.y, a.z], [b.x, b.y, b.z], [c.x, c.y, c.z]])
