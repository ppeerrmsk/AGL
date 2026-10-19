extends RefCounted
## 明确的城区美术地块；只读现有区域/道路，不生成玩法地理或随机噪点。
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Buildings := preload("res://scripts/experiments/volume_building_factory.gd")


static func layout(doc: MapDocument, road_widths: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var roads := _segments(doc.roads, road_widths, false)
	var rails := _segments(doc.railways, road_widths, true)
	var protected := _protected_rects(doc)
	for index in doc.layer_polygons.get("urban", []).size():
		var region: PackedVector2Array = doc.layer_polygons.urban[index]
		if region.size() < 3:
			continue
		var center: Vector2 = Buildings.frame(region).center
		var nearest := _nearest_road(center, roads)
		if nearest.is_empty():
			continue
		var axis: Vector2 = nearest.axis
		var side := Vector2(-axis.y, axis.x)
		var streets: Array[PackedVector2Array] = []
		var enabled_sides: Array[float] = []
		for sign_value: float in [-1.0, 1.0]:
			var middle := center + side * 230.0 * sign_value
			var lane := PackedVector2Array([middle - axis * 500.0, middle + axis * 500.0])
			var access := PackedVector2Array([middle, nearest.point])
			if _street_clear(lane, rails, protected) and _street_clear(access, rails, protected):
				streets.append(lane)
				streets.append(access)
				enabled_sides.append(sign_value)
		var all_routes: Array[Dictionary] = []
		all_routes.append_array(roads)
		all_routes.append_array(rails)
		for street in streets:
			all_routes.append({"a": street[0], "b": street[1], "clearance": 16.0})
		var plots: Array[Dictionary] = []
		# 仍沿真实道路方向组织，但用四条不等距带和错列地块打散棋盘感。
		var across_bands := [-340.0, -155.0, 145.0, 335.0]
		var along_slots := [-430.0, -265.0, -95.0, 90.0, 270.0, 440.0]
		var stagger := [0.0, 28.0, -18.0, 22.0, -30.0, 10.0]
		for row in 4:
			var across: float = across_bands[row]
			if not enabled_sides.has(signf(across)):
				continue
			for column in 6:
				var plot_center: Vector2 = center + axis * (float(along_slots[column]) + float(stagger[column]) * (1.0 if row % 2 == 0 else -1.0)) \
					+ side * (across + (-12.0 if column % 2 == 0 else 14.0))
				var outer := row in [0, 3]
				var size := Vector2(46.0 + 8.0 * (column % 3), 42.0 + 5.0 * ((column + row) % 2)) \
					if outer else Vector2(66.0 + 9.0 * (column % 3), 40.0 + 7.0 * ((column + row) % 3))
				var height := (16.0 + 7.0 * ((column + row) % 3)) if outer \
					else (14.0 + 6.0 * ((column * 2 + row) % 3))
				var footprint := Buildings.rectangle(plot_center, axis, size)
				if not Geometry2D.clip_polygons(footprint, region).is_empty():
					continue
				if not _plot_clear(footprint, all_routes, protected):
					continue
				plots.append({"footprint": footprint, "height_px": height,
					"kind": "office" if outer or (column + row) % 5 == 0 else "warehouse",
					"slot": Vector2i(column, row), "tone": (column + row * 2 + index) % 3})
		var driveways: Array[PackedVector2Array] = []
		for plot: Dictionary in plots:
			var origin: Vector2 = Buildings.frame(plot.footprint).center
			var target := origin
			var best_distance := INF
			for street: PackedVector2Array in streets:
				var point := Geometry2D.get_closest_point_to_segment(origin, street[0], street[1])
				if origin.distance_squared_to(point) < best_distance:
					best_distance = origin.distance_squared_to(point)
					target = point
			var driveway := PackedVector2Array([origin, target])
			var clear := _street_clear(driveway, rails, protected)
			for other: Dictionary in plots:
				if other.slot == plot.slot:
					continue
				var boundary: PackedVector2Array = other.footprint
				for edge in boundary.size():
					if _segment_distance(origin, target, boundary[edge], boundary[(edge + 1) % boundary.size()]) < 3.0:
						clear = false
			if clear and best_distance < INF:
				driveways.append(driveway)
		result.append({"source_urban_index": index, "center": center, "axis": axis,
			"source_road_point": nearest.point, "plots": plots, "streets": streets, "driveways": driveways})
	return result


static func _segments(routes: Array, widths: Dictionary, railway: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for route: Dictionary in routes:
		var points := Geometry.points_from(route.get("points", []))
		var clearance := 36.0 if railway else float(widths.get(route.get("width_class", "primary"), 16.0)) * 0.5 + 12.0
		for i in range(points.size() - 1):
			if points[i].distance_squared_to(points[i + 1]) > 0.001:
				result.append({"a": points[i], "b": points[i + 1], "clearance": clearance})
	return result


static func _nearest_road(point: Vector2, segments: Array[Dictionary]) -> Dictionary:
	var best := INF
	var result := {}
	for segment in segments:
		var nearest := Geometry2D.get_closest_point_to_segment(point, segment.a, segment.b)
		var distance := point.distance_squared_to(nearest)
		if distance < best:
			best = distance
			result = {"point": nearest, "axis": (Vector2(segment.b) - Vector2(segment.a)).normalized()}
	return result


static func _protected_rects(doc: MapDocument) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for feature: Dictionary in doc.buildings + doc.airports:
		var points := Geometry.points_from(feature.get("footprint", feature.get("polygon", [])))
		if points.is_empty():
			continue
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point in points:
			bounds = bounds.expand(point)
		result.append(bounds.grow(36.0))
	return result


static func _plot_clear(points: PackedVector2Array, routes: Array[Dictionary], protected: Array[Rect2]) -> bool:
	var center: Vector2 = Buildings.frame(points).center
	var radius := 0.0
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		radius = maxf(radius, center.distance_to(point))
		bounds = bounds.expand(point)
	for rect in protected:
		if rect.intersects(bounds, true):
			return false
	for segment in routes:
		if center.distance_to(Geometry2D.get_closest_point_to_segment(center, segment.a, segment.b)) < radius + float(segment.clearance):
			return false
	return true


static func _street_clear(points: PackedVector2Array, rails: Array[Dictionary], protected: Array[Rect2]) -> bool:
	if points[0].distance_squared_to(points[1]) < 0.001:
		return false
	for rail in rails:
		if _segment_distance(points[0], points[1], rail.a, rail.b) < 42.0:
			return false
	for rect in protected:
		if rect.has_point(points[0]) or rect.has_point(points[1]):
			return false
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for i in 4:
			if Geometry2D.segment_intersects_segment(points[0], points[1], corners[i], corners[(i + 1) % 4]) != null:
				return false
	return true


static func _segment_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(a.distance_to(Geometry2D.get_closest_point_to_segment(a, c, d)),
		b.distance_to(Geometry2D.get_closest_point_to_segment(b, c, d))),
		minf(c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b)),
		d.distance_to(Geometry2D.get_closest_point_to_segment(d, a, b))))
