extends RefCounted
## 仅在机型预热时求真实表面；返回纯值，运行帧不扫描三角形。

static func closest(mesh: ArrayMesh, desired: Vector2, upper: bool) -> Vector3:
	var faces := mesh.get_faces()
	var best := Vector3.INF
	var best_distance := INF
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var av := Vector2(a.x, a.z)
		var bv := Vector2(b.x, b.z)
		var cv := Vector2(c.x, c.z)
		var denominator := (bv - av).cross(cv - av)
		if absf(denominator) < 0.00001:
			continue
		var p := desired
		var weights := _weights(p, av, bv, cv, denominator)
		if weights.x < 0.0 or weights.y < 0.0 or weights.z < 0.0:
			var ab := Geometry2D.get_closest_point_to_segment(p, av, bv)
			var bc := Geometry2D.get_closest_point_to_segment(p, bv, cv)
			var ca := Geometry2D.get_closest_point_to_segment(p, cv, av)
			p = ab
			if bc.distance_squared_to(desired) < p.distance_squared_to(desired):
				p = bc
			if ca.distance_squared_to(desired) < p.distance_squared_to(desired):
				p = ca
			# 从外轮廓内收，避免支座只挂在零厚度尖端。
			p = p.move_toward((av + bv + cv) / 3.0, 0.22)
			weights = _weights(p, av, bv, cv, denominator)
		# 接合中心必须落在面内部，不把有面积的支座中心压在外边或左右拼缝上。
		if minf(weights.x, minf(weights.y, weights.z)) < 0.003:
			p = p.lerp((av + bv + cv) / 3.0, 0.009)
			weights = _weights(p, av, bv, cv, denominator)
		var point := a * weights.x + b * weights.y + c * weights.z
		var distance := p.distance_squared_to(desired)
		var outer := best == Vector3.INF or (point.y > best.y if upper else point.y < best.y)
		if distance < best_distance - 0.00001 or (absf(distance - best_distance) <= 0.00001 and outer):
			best_distance = distance
			best = point
	return best


static func _weights(p: Vector2, a: Vector2, b: Vector2, c: Vector2, denominator: float) -> Vector3:
	var v := (p - a).cross(c - a) / denominator
	var w := (b - a).cross(p - a) / denominator
	return Vector3(1.0 - v - w, v, w)
