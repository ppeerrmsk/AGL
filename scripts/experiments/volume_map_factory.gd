extends RefCounted
## 批次 A 的静态三维地图：只读 MapDocument，绝不生成第二套玩法地理。
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const TRIANGLE_BUDGET := 12000
const ROAD_WIDTHS := {"motorway": 25.0, "trunk": 20.0, "primary": 16.0,
	"secondary": 12.0, "tertiary": 9.0, "residential": 7.0, "service": 6.0}


static func build(doc: MapDocument) -> Dictionary:
	# 本批仅支持独立 union 地理面；不把 even-odd 水洞错误填成陆地。
	for layer in MapDocument.CELL_LAYERS:
		if not doc.layer_polygons.get(layer, []).is_empty() and doc.layer_mode.get(layer, "even_odd") != "union":
			return {"ok": false, "reason": "unsupported polygon holes: " + layer}
	var builder := Geometry.new()
	var extent := doc.world_size_m * CombatUnit.PIXELS_PER_METER
	var land := palette(doc, "land")
	builder.box(Vector3(0, -2, 0), Vector3(extent, 2, extent), palette(doc, "sea"))
	for layer in MapDocument.CELL_LAYERS:
		var color := palette(doc, "terrain_" + layer)
		if layer in ["land", "urban"]:
			color = palette(doc, layer)
		# 粗粒度来源区域只作低对比底色，不能压过飞机、铁路和作战标记。
		if layer != "land":
			color = land.lerp(color, 0.35)
		var elevation := 0.0 if layer == "land" else 0.05
		for polygon: PackedVector2Array in doc.layer_polygons.get(layer, []):
			# 没有 DEM 的区域不凭空增加山高、阻挡或悬空道路。
			face(builder, polygon, elevation, color)
	for road: Dictionary in doc.roads:
		var points := Geometry.points_from(road.get("points", []))
		var width := float(ROAD_WIDTHS.get(road.get("width_class", "primary"), 12.0))
		stroke(builder, points, width + 5.0, 0.15, land.darkened(0.28))
		stroke(builder, points, width, 0.20, palette(doc, "road").darkened(0.40))
	for railway: Dictionary in doc.railways:
		var points := Geometry.points_from(railway.get("points", []))
		stroke(builder, points, 18.0, 0.30, land.lightened(0.13))
		var rails := stroke_edges(points, 10.0)
		if rails.size() == 2:
			for rail: PackedVector2Array in rails:
				stroke(builder, rail, 1.6, 0.55, Color("b4aa90"))
		# 沿整条路线累计弧长，不在每个折点重置枕木间距。
		for pose: Vector3 in sleeper_poses(points):
			var center := Vector2(pose.x, pose.y)
			var sideways := Vector2(-sin(pose.z), cos(pose.z)) * 7.0
			stroke(builder, PackedVector2Array([center - sideways, center + sideways]),
				2.5, 0.45, palette(doc, "building_wall_shade"))
	for airport: Dictionary in doc.airports:
		var polygon := airport_polygon(airport)
		face(builder, polygon, 0.65, land.darkened(0.48))
		_add_runway_markings(builder, polygon)
	for building: Dictionary in doc.buildings:
		var footprint := Geometry.points_from(building.get("footprint", []))
		if footprint.size() < 3:
			continue
		var height := maxf(0.1, float(building.get("h_m", 20.0)) * CombatUnit.PIXELS_PER_METER)
		var wall_height := height - minf(3.0, height * 0.20) if footprint.size() == 4 else height
		builder.prism(footprint, 0.0, wall_height, palette(doc, "building_wall_lit"))
		if footprint.size() == 4:
			_add_roof(builder, footprint, wall_height, height, palette(doc, "building_roof"))
			continue
		# 屋顶只在同一轮廓内细分，外缘与原高度完全保留。
		var inset := PackedVector2Array()
		var center := Vector2.ZERO
		for point in footprint:
			center += point / float(footprint.size())
		for point in footprint:
			inset.append(center.lerp(point, 0.975))
		face(builder, footprint, height + 0.03, palette(doc, "building_roof").lightened(0.20))
		face(builder, inset, height + 0.06, palette(doc, "building_roof"))
	var result := builder.mesh()
	var triangles := result.surface_get_array_len(0) / 3
	return {"ok": triangles <= TRIANGLE_BUDGET, "mesh": result, "triangles": triangles,
		"buildings": doc.buildings.size(), "airports": doc.airports.size(),
		"roads": doc.roads.size(), "railways": doc.railways.size(), "extent_px": extent,
		"reason": "" if triangles <= TRIANGLE_BUDGET else "map triangle budget exceeded"}


static func palette(doc: MapDocument, key: String) -> Color:
	var raw: Array = doc.style.get("palette", {}).get(key, [0.48, 0.31, 0.16, 1.0])
	return Color(float(raw[0]), float(raw[1]), float(raw[2]), 1.0)


static func face(builder: RefCounted, points: PackedVector2Array, height: float, color: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	for i in range(0, indices.size(), 3):
		var a := Vector3(points[indices[i]].x, height, points[indices[i]].y)
		var b := Vector3(points[indices[i + 1]].x, height, points[indices[i + 1]].y)
		var c := Vector3(points[indices[i + 2]].x, height, points[indices[i + 2]].y)
		if (b - a).cross(c - a).y < 0.0:
			builder.triangle(a, c, b, color)
		else:
			builder.triangle(a, b, c, color)


## 一个顶点只有一对边界；相邻段共享接头，避免逐段法向偏移留下铁路裂口。
static func stroke_edges(points: PackedVector2Array, width: float) -> Array[PackedVector2Array]:
	var clean := PackedVector2Array()
	for point in points:
		if clean.is_empty() or clean[-1].distance_squared_to(point) > 0.0001:
			clean.append(point)
	if clean.size() < 2:
		return []
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in clean.size():
		var before := (clean[i] - clean[maxi(i - 1, 0)]).normalized()
		var after := (clean[mini(i + 1, clean.size() - 1)] - clean[i]).normalized()
		if i == 0:
			before = after
		if i == clean.size() - 1:
			after = before
		var tangent := (before + after).normalized()
		if tangent.is_zero_approx():
			tangent = after
		var normal := Vector2(-tangent.y, tangent.x)
		var side := Vector2(-after.y, after.x)
		var length := minf(width * 2.0, width * 0.5 / maxf(0.25, normal.dot(side)))
		left.append(clean[i] + normal * length)
		right.append(clean[i] - normal * length)
	return [left, right]


static func stroke(builder: RefCounted, points: PackedVector2Array, width: float, height: float, color: Color) -> void:
	var edges := stroke_edges(points, width)
	if edges.is_empty():
		return
	for i in range(edges[0].size() - 1):
		face(builder, PackedVector2Array([edges[0][i], edges[1][i], edges[1][i + 1], edges[0][i + 1]]), height, color)


static func sleeper_poses(points: PackedVector2Array, spacing: float = 24.0) -> Array[Vector3]:
	var poses: Array[Vector3] = []
	if spacing <= 0.0:
		return poses
	var next_distance := spacing * 0.5
	for i in range(points.size() - 1):
		var segment := points[i + 1] - points[i]
		var length := segment.length()
		if length <= 0.001:
			continue
		while next_distance < length:
			var point := points[i] + segment * (next_distance / length)
			poses.append(Vector3(point.x, point.y, segment.angle()))
			next_distance += spacing
		next_distance -= length
	return poses


static func airport_polygon(airport: Dictionary) -> PackedVector2Array:
	if airport.has("polygon"):
		return Geometry.points_from(airport.polygon)
	var center_raw: Array = airport.get("center", [0, 0])
	var size_raw: Array = airport.get("size", [0, 0])
	var center := Vector2(float(center_raw[0]), float(center_raw[1]))
	var half_size := Vector2(float(size_raw[0]), float(size_raw[1])) * 0.5
	var angle := deg_to_rad(float(airport.get("rotation_deg", 0)))
	var result := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		result.append(center + (corner * half_size).rotated(angle))
	return result


static func _add_runway_markings(builder: RefCounted, polygon: PackedVector2Array) -> void:
	if polygon.size() != 4:
		return
	# 取真实四边形的长轴，不另写机场中心/朝向。
	var start := (polygon[0] + polygon[3]) * 0.5
	var end := (polygon[1] + polygon[2]) * 0.5
	if polygon[0].distance_to(polygon[1]) < polygon[1].distance_to(polygon[2]):
		start = (polygon[0] + polygon[1]) * 0.5
		end = (polygon[2] + polygon[3]) * 0.5
	var axis := end - start
	var direction := axis.normalized()
	var half_width := minf(polygon[0].distance_to(polygon[1]), polygon[1].distance_to(polygon[2])) * 0.5
	var side := Vector2(-direction.y, direction.x)
	var mark := Color("d3cab1")
	for sign_value in [-1.0, 1.0]:
		var offset: Vector2 = side * half_width * 0.85 * sign_value
		stroke(builder, PackedVector2Array([start + direction * 20 + offset, end - direction * 20 + offset]), 1.5, 0.75, mark)
	for threshold in [start + direction * 24, end - direction * 24]:
		for fraction in [-0.65, -0.40, -0.15, 0.15, 0.40, 0.65]:
			var center: Vector2 = threshold + side * half_width * fraction
			stroke(builder, PackedVector2Array([center - direction * 9, center + direction * 9]), 2.2, 0.75, mark)
	var distance := 50.0
	while distance < axis.length() - 50.0:
		stroke(builder, PackedVector2Array([start + direction * distance,
			start + direction * minf(distance + 25.0, axis.length() - 50.0)]), 2.0, 0.75, mark)
		distance += 55.0


## 低矮折面屋顶沿原轮廓长轴；最高处仍是源 h_m，不添加建筑或阻挡。
static func _add_roof(builder: RefCounted, polygon: PackedVector2Array, wall: float, peak: float, color: Color) -> void:
	var points := polygon.duplicate()
	if points[0].distance_to(points[1]) < points[1].distance_to(points[2]):
		points = PackedVector2Array([points[1], points[2], points[3], points[0]])
	var start := (points[0] + points[3]) * 0.5
	var end := (points[1] + points[2]) * 0.5
	var ridge_a := Vector3(start.x, peak, start.y)
	var ridge_b := Vector3(end.x, peak, end.y)
	var corners: Array[Vector3] = []
	for point in points:
		corners.append(Vector3(point.x, wall, point.y))
	for indices in [[0, 1], [2, 3]]:
		var a: Vector3 = corners[indices[0]]
		var b: Vector3 = corners[indices[1]]
		var c := ridge_b if indices[0] == 0 else ridge_a
		var d := ridge_a if indices[0] == 0 else ridge_b
		if (b - a).cross(c - a).y < 0:
			builder.quad(d, c, b, a, color)
		else:
			builder.quad(a, b, c, d, color)
	# 山墙朝向由多边形绕序决定。
	if Geometry2D.is_polygon_clockwise(points):
		builder.triangle(corners[3], corners[0], ridge_a, color.lightened(0.1))
		builder.triangle(corners[1], corners[2], ridge_b, color.lightened(0.1))
	else:
		builder.triangle(corners[0], corners[3], ridge_a, color.lightened(0.1))
		builder.triangle(corners[2], corners[1], ridge_b, color.lightened(0.1))
