extends RefCounted
## 无节点、无 tick：厂房、储罐与塔楼一次写入共享地图几何。
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const INDUSTRIAL_ROOF := Color("92958c")


static func frame(points: PackedVector2Array) -> Dictionary:
	var center := Vector2.ZERO
	for point in points:
		center += point / float(points.size())
	var direction := (points[1] - points[0]).normalized()
	if points.size() == 4 and points[0].distance_to(points[1]) < points[1].distance_to(points[2]):
		direction = (points[2] - points[1]).normalized()
	var side := Vector2(-direction.y, direction.x)
	var half_length := 0.0
	var half_width := 0.0
	for point in points:
		half_length = maxf(half_length, absf((point - center).dot(direction)))
		half_width = maxf(half_width, absf((point - center).dot(side)))
	return {"center": center, "direction": direction, "side": side, "length": half_length * 2, "width": half_width * 2}


static func rectangle(center: Vector2, direction: Vector2, size: Vector2) -> PackedVector2Array:
	var side := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		points.append(center + direction * corner.x * size.x * 0.5 + side * corner.y * size.y * 0.5)
	return points


static func scaled_polygon(points: PackedVector2Array, scale_value: float) -> PackedVector2Array:
	var center := Vector2.ZERO
	for point in points:
		center += point / float(points.size())
	var result := PackedVector2Array()
	for point in points:
		result.append(center.lerp(point, scale_value))
	return result


static func add(builder: RefCounted, points: PackedVector2Array, height: float, kind: String, wall: Color, roof: Color) -> void:
	match kind:
		"tank": _tank(builder, points, height, wall, roof)
		"tower": _tower(builder, points, height, wall, roof)
		"office": _office(builder, points, height, wall, roof)
		"industrial_warehouse": _warehouse(builder, points, height, wall, roof, true)
		_: _warehouse(builder, points, height, wall, roof)


static func industrial_roof_details(builder: RefCounted, points: PackedVector2Array, height: float) -> void:
	var f := frame(points)
	# 板缝与坡度都在建筑局部坐标中；只细化三座源厂房，不复制整场节点/材质。
	var panel_count := clampi(roundi(float(f.length) / 18.0), 6, 12)
	for panel in panel_count:
		var start := -float(f.length) * 0.5 + float(f.length) * panel / panel_count + 0.18
		var end := -float(f.length) * 0.5 + float(f.length) * (panel + 1) / panel_count - 0.18
		var panel_color := INDUSTRIAL_ROOF.darkened(float((panel * 7) % 5) * 0.015)
		for side_sign: float in [-1.0, 1.0]:
			_roof_quad(builder, warehouse_surface_point(f, height, start, 0.0),
				warehouse_surface_point(f, height, end, 0.0),
				warehouse_surface_point(f, height, end, float(f.width) * 0.5 * side_sign),
				warehouse_surface_point(f, height, start, float(f.width) * 0.5 * side_sign), panel_color)
	var vent_size := Vector2(minf(float(f.length) * 0.12, 24.0), minf(float(f.width) * 0.16, 14.0))
	for fraction: float in [-0.28, 0.0, 0.28]:
		var center: Vector2 = f.center + f.direction * float(f.length) * fraction
		# 箱底嵌入真实双坡屋面，不能浮在斜屋面上方；与厂房同一静态批次。
		builder.prism(rectangle(center, f.direction, vent_size), height * 0.94,
			height + 2.6, Color("556368"))
		var radius := minf(vent_size.x, vent_size.y) * 0.31
		for segment in 6:
			var angle := TAU * segment / 6.0
			var next_angle := TAU * (segment + 1) / 6.0
			var a: Vector2 = center + (f.direction * cos(angle) + f.side * sin(angle)) * radius
			var b: Vector2 = center + (f.direction * cos(next_angle) + f.side * sin(next_angle)) * radius
			builder.triangle(Vector3(center.x, height + 2.64, center.y),
				Vector3(b.x, height + 2.64, b.y), Vector3(a.x, height + 2.64, a.y), Color("293436"))
	for side_sign: float in [-1.0, 1.0]:
		var edge := float(f.width) * 0.5 * side_sign
		var lift := Vector3.UP * 0.02
		_roof_quad(builder, warehouse_surface_point(f, height, -float(f.length) * 0.5, edge) + lift,
			warehouse_surface_point(f, height, float(f.length) * 0.5, edge) + lift,
			warehouse_surface_point(f, height, float(f.length) * 0.5, edge - side_sign * 0.9) + lift,
			warehouse_surface_point(f, height, -float(f.length) * 0.5, edge - side_sign * 0.9) + lift, Color("5b6059"))
	var dock: Vector2 = f.center + f.side * (float(f.width) * 0.5 + 7.0)
	builder.prism(rectangle(dock, f.direction, Vector2(float(f.length) * 0.3, 14.0)),
		0.0, 1.4, Color("9d9687"))
	var canopy := rectangle(dock, f.direction, Vector2(float(f.length) * 0.3, 14.0))
	var canopy_height := height * 0.55
	_roof_quad(builder, Vector3(canopy[0].x, canopy_height, canopy[0].y),
		Vector3(canopy[1].x, canopy_height, canopy[1].y), Vector3(canopy[2].x, canopy_height, canopy[2].y),
		Vector3(canopy[3].x, canopy_height, canopy[3].y), INDUSTRIAL_ROOF.darkened(0.18))
	var lip_a := Vector3(canopy[2].x, canopy_height, canopy[2].y)
	var lip_b := Vector3(canopy[3].x, canopy_height, canopy[3].y)
	builder.quad(lip_a, lip_b, lip_b - Vector3.UP * 0.8, lip_a - Vector3.UP * 0.8, Color("65675f"))
	for fraction: float in [-0.12, 0.12]:
		var post: Vector2 = dock + f.direction * float(f.length) * fraction + f.side * 5.8
		builder.prism(rectangle(post, f.direction, Vector2.ONE * 1.2), 1.4, canopy_height, Color("545b56"))


static func warehouse_surface_point(f: Dictionary, height: float, along: float, across: float) -> Vector3:
	var point: Vector2 = f.center + f.direction * along + f.side * across
	return Vector3(point.x, height * (1.0 - 0.56 * absf(across) / float(f.width)) + 0.02, point.y)


static func _office(builder: RefCounted, points: PackedVector2Array, height: float, wall: Color, roof: Color) -> void:
	builder.prism(points, 0, height * 0.08, wall.darkened(0.3))
	builder.prism(points, height * 0.08, height * 0.76, wall)
	for fraction: float in [0.26, 0.52]:
		builder.prism(scaled_polygon(points, 1.0015), height * fraction, height * (fraction + 0.08), Color("46575d"))
	var upper := scaled_polygon(points, 0.68)
	builder.prism(upper, height * 0.76, height * 0.95, wall.lightened(0.08))
	builder.prism(upper, height * 0.95, height, roof)


static func _tower(builder: RefCounted, points: PackedVector2Array, height: float, wall: Color, roof: Color) -> void:
	builder.prism(points, 0, height * 0.12, wall.darkened(0.25))
	builder.prism(scaled_polygon(points, 0.56), height * 0.12, height * 0.73, wall)
	builder.prism(scaled_polygon(points, 0.9), height * 0.73, height * 0.94, wall.lightened(0.15))
	# 玻璃是实体观察室的嵌色层，仍共用同一不透明材质。
	builder.prism(scaled_polygon(points, 0.904), height * 0.78, height * 0.9, Color("394950"))
	builder.prism(points, height * 0.94, height, roof.lightened(0.12))


static func _tank(builder: RefCounted, points: PackedVector2Array, height: float, wall: Color, roof: Color) -> void:
	builder.prism(points, 0, height * 0.82, wall.lightened(0.15))
	var center: Vector2 = frame(points).center
	var radius := center.distance_to(points[0])
	for fraction: float in [0.25, 0.65]:
		builder.prism(scaled_polygon(points, 1.0 + 0.3 / radius), height * fraction,
			height * (fraction + 0.06), wall.darkened(0.15))
	var inner := scaled_polygon(points, 0.84)
	for i in points.size():
		var j := (i + 1) % points.size()
		var a := Vector3(points[i].x, height * 0.82, points[i].y)
		var b := Vector3(points[j].x, height * 0.82, points[j].y)
		var c := Vector3(inner[j].x, height * 0.9, inner[j].y)
		var d := Vector3(inner[i].x, height * 0.9, inner[i].y)
		_roof_quad(builder, a, b, c, d, roof)
		var peak := Vector3(center.x, height, center.y)
		if (c - d).cross(peak - d).y < 0:
			builder.triangle(d, peak, c, roof.lightened(0.07))
		else:
			builder.triangle(d, c, peak, roof.lightened(0.07))
	builder.prism(scaled_polygon(points, 0.12), height * 0.97, height, wall.darkened(0.3))


static func _warehouse(builder: RefCounted, points: PackedVector2Array, height: float, wall: Color, roof: Color, industrial: bool = false) -> void:
	if points.size() != 4:
		builder.prism(points, 0, height, wall)
		return
	var f := frame(points)
	var center: Vector2 = f.center
	var direction: Vector2 = f.direction
	var side: Vector2 = f.side
	var length: float = f.length
	var width: float = f.width
	var corners := rectangle(center, direction, Vector2(length, width))
	var eave := height * 0.72
	builder.prism(points, 0, eave, wall)
	var ridge_a := Vector3(center.x - direction.x * length * 0.5, height, center.y - direction.y * length * 0.5)
	var ridge_b := Vector3(center.x + direction.x * length * 0.5, height, center.y + direction.y * length * 0.5)
	var p: Array[Vector3] = []
	for corner in corners:
		p.append(Vector3(corner.x, eave, corner.y))
	_roof_quad(builder, p[0], p[1], ridge_b, ridge_a, roof)
	_roof_quad(builder, p[2], p[3], ridge_a, ridge_b, roof)
	# 两端真实山墙，使用中心方向确定向外法线。
	for indices in [[3, 0], [1, 2]]:
		var a: Vector3 = p[indices[0]]
		var b: Vector3 = p[indices[1]]
		var peak := ridge_a if indices[0] == 3 else ridge_b
		var outward := (a + b) * 0.5 - Vector3(center.x, eave, center.y)
		if (b - a).cross(peak - a).dot(outward) < 0:
			builder.triangle(b, a, peak, wall)
		else:
			builder.triangle(a, b, peak, wall)
	# 顺着坡面的屋面条，不用浮空横盒或铺整张纹理。
	for fraction: float in [0.2, 0.4, 0.6, 0.8]:
		var along := center + direction * length * (fraction - 0.5)
		for sign_value: float in [-1.0, 1.0]:
			var a2: Vector2 = along + side * width * 0.08 * sign_value
			var b2: Vector2 = along + side * width * 0.43 * sign_value
			var half_strip := direction * length * (0.005 if industrial else 0.009)
			var top_y := height - (height - eave) * 0.16 + 0.05
			var low_y := height - (height - eave) * 0.86 + 0.05
			_roof_quad(builder, Vector3(a2.x - half_strip.x, top_y, a2.y - half_strip.y),
				Vector3(a2.x + half_strip.x, top_y, a2.y + half_strip.y),
				Vector3(b2.x + half_strip.x, low_y, b2.y + half_strip.y),
				Vector3(b2.x - half_strip.x, low_y, b2.y - half_strip.y),
				roof.darkened(0.18) if industrial else roof.lightened(0.24))
	for sign_value: float in [-1.0, 1.0]:
		for fraction: float in [-0.3, 0.0, 0.3]:
			var door_center: Vector2 = center + direction * length * fraction + side * (width * 0.5 + 0.08) * sign_value
			var a2 := door_center - direction * length * 0.06
			var b2 := door_center + direction * length * 0.06
			var a := Vector3(a2.x, 0.1, a2.y)
			var b := Vector3(b2.x, 0.1, b2.y)
			var up := Vector3.UP * height * 0.48
			if sign_value > 0:
				builder.quad(a, b, b + up, a + up, wall.darkened(0.50))
			else:
				builder.quad(b, a, a + up, b + up, wall.darkened(0.50))


static func _roof_quad(builder: RefCounted, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).y < 0:
		builder.quad(d, c, b, a, color)
	else:
		builder.quad(a, b, c, d, color)


static func airport_details(polygon: PackedVector2Array) -> Array[Dictionary]:
	if polygon.size() != 4:
		return []
	var f := frame(polygon)
	var result: Array[Dictionary] = []
	var definitions: Array = []
	for fraction in [-0.2, 0.0, 0.2]:
		definitions.append([fraction, 115.0, 45.0, 34.0, 14.0, "warehouse"])
	definitions.append([-0.35, 115.0, 16.0, 16.0, 28.0, "tower"])
	definitions.append([0.38, 120.0, 70.0, 25.0, 8.0, "warehouse"])
	definitions.append([0.32, 175.0, 20.0, 20.0, 12.0, "tank"])
	definitions.append([0.40, 175.0, 20.0, 20.0, 12.0, "tank"])
	for definition: Array in definitions:
		var center: Vector2 = f.center + f.direction * float(f.length) * float(definition[0]) + f.side * float(definition[1])
		var footprint := rectangle(center, f.direction, Vector2(float(definition[2]), float(definition[3])))
		if definition[5] == "tank":
			footprint.clear()
			for i in 12:
				footprint.append(center + Vector2.from_angle(TAU * i / 12.0) * 10.0)
		result.append({"footprint": footprint, "height_px": float(definition[4]), "kind": String(definition[5])})
	return result
