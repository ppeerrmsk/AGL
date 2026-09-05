extends RefCounted
## 隔离实验低模源：一次生成 ArrayMesh，运行时共享；不是最终机型资产。

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	# Godot 正面采用顺时针顶点序；法线仍按向外叉积计算。
	for point in [a, c, b]:
		_vertices.append(point)
		_normals.append(normal)
		_colors.append(color)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	triangle(a, b, c, color)
	triangle(a, c, d, color)


func prism(points: PackedVector2Array, bottom: float, top: float, color: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	for i in range(0, indices.size(), 3):
		var a := Vector3(points[indices[i]].x, top, points[indices[i]].y)
		var b := Vector3(points[indices[i + 1]].x, top, points[indices[i + 1]].y)
		var c := Vector3(points[indices[i + 2]].x, top, points[indices[i + 2]].y)
		if (b - a).cross(c - a).y < 0.0:
			triangle(a, c, b, color)
		else:
			triangle(a, b, c, color)
		a.y = bottom
		b.y = bottom
		c.y = bottom
		if (b - a).cross(c - a).y > 0.0:
			triangle(a, c, b, color.darkened(0.15))
		else:
			triangle(a, b, c, color.darkened(0.15))
	for i in points.size():
		var a := Vector3(points[i].x, bottom, points[i].y)
		var b := Vector3(points[(i + 1) % points.size()].x, bottom, points[(i + 1) % points.size()].y)
		var up := Vector3.UP * (top - bottom)
		if Geometry2D.is_polygon_clockwise(points):
			quad(a, b, b + up, a + up, color.darkened(0.08))
		else:
			quad(b, a, a + up, b + up, color.darkened(0.08))


func box(center: Vector3, size: Vector3, color: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	prism(PackedVector2Array([
		Vector2(center.x - hx, center.z - hz), Vector2(center.x + hx, center.z - hz),
		Vector2(center.x + hx, center.z + hz), Vector2(center.x - hx, center.z + hz)]),
		center.y - size.y * 0.5, center.y + size.y * 0.5, color)


## 八棱截面机身，rings = (纵向 z, 横半径, 高半径)；每段独立法线保留 low-poly 折面。
func loft(center: Vector3, rings: Array, color: Color) -> void:
	for i in range(rings.size() - 1):
		for j in 8:
			var angle := TAU * float(j) / 8.0
			var next := TAU * float(j + 1) / 8.0
			var a := center + Vector3(cos(angle) * rings[i].y, sin(angle) * rings[i].z, rings[i].x)
			var b := center + Vector3(cos(next) * rings[i].y, sin(next) * rings[i].z, rings[i].x)
			var c := center + Vector3(cos(next) * rings[i + 1].y, sin(next) * rings[i + 1].z, rings[i + 1].x)
			var d := center + Vector3(cos(angle) * rings[i + 1].y, sin(angle) * rings[i + 1].z, rings[i + 1].x)
			quad(a, b, c, d, color)


func mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	var result := ArrayMesh.new()
	if not _vertices.is_empty():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


static func material() -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.vertex_color_use_as_albedo = true
	result.vertex_color_is_srgb = true
	result.roughness = 0.82
	result.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	result.cull_mode = BaseMaterial3D.CULL_BACK
	return result


static func aircraft(kind: String) -> ArrayMesh:
	var builder: RefCounted = (load("res://scripts/experiments/volume_mesh_factory.gd") as GDScript).new()
	var white := Color.WHITE
	if kind == "mother_goose":
		var wing := PackedVector2Array([
			Vector2(0, -0.45), Vector2(0.20, -0.35), Vector2(1.40, 0.05), Vector2(1.55, 0.22),
			Vector2(1.20, 0.30), Vector2(0.55, 0.28), Vector2(0.30, 0.50), Vector2(0.10, 0.55),
			Vector2(0, 0.45), Vector2(-0.10, 0.55), Vector2(-0.30, 0.50), Vector2(-0.55, 0.28),
			Vector2(-1.20, 0.30), Vector2(-1.55, 0.22), Vector2(-1.40, 0.05), Vector2(-0.20, -0.35)])
		for i in wing.size():
			wing[i] *= 144.0
		builder.prism(wing, -4.0, 4.0, white)
		builder.loft(Vector3(0, 5, 0), [Vector3(-64, 0.2, 0.2), Vector3(-35, 30, 10),
			Vector3(5, 34, 17), Vector3(62, 20, 5), Vector3(76, 0.1, 0.1)], white)
		builder.loft(Vector3(0, 21, -14), [Vector3(-20, 0.2, 0.2), Vector3(-7, 17, 7),
			Vector3(14, 14, 6), Vector3(24, 0.1, 0.1)], Color(0.33, 0.43, 0.48))
		for x in [-172.8, -108.0, -43.2, 43.2, 108.0, 172.8]:
			builder.loft(Vector3(x, 6, -7), [Vector3(-25, 0.1, 0.1), Vector3(-16, 10, 7),
				Vector3(17, 10, 7), Vector3(27, 0.1, 0.1)], Color(0.64, 0.70, 0.72))
		for x in [-30.0, 30.0]:
			builder.box(Vector3(x, 16, 47), Vector3(2.5, 24, 28), Color(0.76, 0.80, 0.82))
	elif kind == "prop":
		builder.loft(Vector3.ZERO, [Vector3(-10, 0.1, 0.1), Vector3(-6, 4, 4),
			Vector3(7, 4, 4), Vector3(10, 0.1, 0.1)], Color(0.56, 0.64, 0.70))
		builder.box(Vector3(0, 0, 8), Vector3(21, 1.8, 2.4), white)
		builder.box(Vector3(0, 0, 8), Vector3(1.8, 21, 2.4), white)
	elif kind == "vls":
		builder.box(Vector3(0, 3, 0), Vector3(12, 6, 22), Color(0.44, 0.52, 0.58))
		for x in [-3.0, 3.0]:
			for z in [-7.0, 0.0, 7.0]:
				builder.box(Vector3(x, 6.5, z), Vector3(4, 1, 5), white)
	else:
		builder.loft(Vector3.ZERO, [Vector3(-18, 0.15, 0.15), Vector3(-9, 2.0, 2.5),
			Vector3(2, 3.0, 3.0), Vector3(12, 2.5, 2.0), Vector3(16, 0.1, 0.1)], white)
		builder.loft(Vector3(0, 2.0, -7), [Vector3(-5, 0.1, 0.1), Vector3(-2, 1.6, 1.7),
			Vector3(4, 1.4, 1.5), Vector3(6, 0.1, 0.1)], Color(0.22, 0.36, 0.46))
		for side in [-1.0, 1.0]:
			var wing: PackedVector2Array
			if kind == "a10":
				wing = PackedVector2Array([Vector2(2, -2), Vector2(18, -1), Vector2(18, 4), Vector2(2, 5)])
			else:
				wing = PackedVector2Array([Vector2(2, -5), Vector2(17, 7), Vector2(16, 11), Vector2(2, 5)])
			for i in wing.size():
				wing[i].x *= side
			builder.prism(wing, -0.6, 0.6, white)
			builder.prism(PackedVector2Array([Vector2(2 * side, 9), Vector2(8 * side, 13),
				Vector2(8 * side, 16), Vector2(2 * side, 14)]), 0.0, 0.6, white)
			builder.box(Vector3(3 * side, 3.2, 11), Vector3(0.7, 6, 7), white)
			builder.loft(Vector3(3 * side, 0.2, 8), [Vector3(-5, 0.1, 0.1), Vector3(-3, 1.7, 1.7),
				Vector3(6, 1.7, 1.7), Vector3(7, 0.1, 0.1)], Color(0.66, 0.70, 0.73))
	return builder.mesh()


static func map_mesh(doc: MapDocument) -> ArrayMesh:
	var builder: RefCounted = (load("res://scripts/experiments/volume_mesh_factory.gd") as GDScript).new()
	builder.box(Vector3(0, -3, 0), Vector3(64000, 2, 64000), Color("777a67"))
	for raw in doc.buildings:
		var points := points_from(raw.get("footprint", []))
		if points.size() >= 3:
			builder.prism(points, 0.0, float(raw.get("h_m", 20.0)) * CombatUnit.PIXELS_PER_METER, Color("bdc6c5"))
	for raw in doc.roads:
		builder.ribbon(points_from(raw.get("points", [])), 25.0, 0.2, Color("505853"))
	for raw in doc.railways:
		var points := points_from(raw.get("points", []))
		builder.ribbon(points, 18.0, 0.4, Color("8d8979"))
		for i in range(points.size() - 1):
			var direction := (points[i + 1] - points[i]).normalized()
			var sideways := Vector2(-direction.y, direction.x)
			for sign_value in [-1.0, 1.0]:
				builder.ribbon(PackedVector2Array([points[i] + sideways * sign_value * 5.0,
					points[i + 1] + sideways * sign_value * 5.0]), 1.6, 1.0, Color("d1d8d3"))
			var distance := 0.0
			while distance < points[i].distance_to(points[i + 1]):
				var center := points[i] + direction * distance
				builder.ribbon(PackedVector2Array([center - sideways * 8, center + sideways * 8]), 3.0, 0.7, Color("4c554f"))
				distance += 24.0
	return builder.mesh()


func ribbon(points: PackedVector2Array, width: float, height: float, color: Color) -> void:
	for i in range(points.size() - 1):
		var delta := points[i + 1] - points[i]
		var normal := Vector2(-delta.y, delta.x).normalized() * width * 0.5
		prism(PackedVector2Array([points[i] - normal, points[i + 1] - normal,
			points[i + 1] + normal, points[i] + normal]), height - 0.1, height, color)


static func points_from(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in raw:
		result.append(Vector2(float(point[0]), float(point[1])))
	return result
