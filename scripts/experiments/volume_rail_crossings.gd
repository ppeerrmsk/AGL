extends RefCounted
## 已审查的地面交点；只派生交叉面，不推断桥梁层级或改变交通坐标。
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const SITES := [
	{"road": 0, "segment": 5, "rail_segment": 15, "point": Vector2(539.615839,-3095.504402)},
	{"road": 1, "segment": 5, "rail_segment": 15, "point": Vector2(690.404383,-3044.169598)},
	{"road": 5, "segment": 2, "rail_segment": 13, "point": Vector2(-1508.944044,-5111.290613)},
	{"road": 6, "segment": 1, "rail_segment": 17, "point": Vector2(3410.224483,-1800.786499)},
]


static func records(doc: MapDocument, widths: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if doc.railways.size() != 1:
		return result
	var rail := Geometry.points_from(doc.railways[0].points)
	var rail_edges := Geometry.stroke_edges(rail, 20.0)
	if rail_edges.size() != 2 or rail_edges[0].size() != rail.size() or rail_edges[1].size() != rail.size():
		return result
	for site: Dictionary in SITES:
		if doc.roads.size() <= int(site.road) or rail.size() <= int(site.rail_segment) + 1:
			continue
		var road: Dictionary = doc.roads[int(site.road)]
		var points := Geometry.points_from(road.points)
		var segment := int(site.segment)
		var rail_segment := int(site.rail_segment)
		if points.size() <= segment + 1 or rail_edges.size() != 2:
			continue
		var hit: Variant = Geometry2D.segment_intersects_segment(points[segment], points[segment+1], rail[rail_segment], rail[rail_segment+1])
		if not hit is Vector2:
			continue
		var crossing: Vector2 = hit
		if crossing.distance_to(site.point) > 0.01:
			continue # 来源漂移须重新审查，不能把旧修补贴到新线路。
		var rail_polygon := PackedVector2Array([rail_edges[0][rail_segment], rail_edges[0][rail_segment+1],
			rail_edges[1][rail_segment+1], rail_edges[1][rail_segment]])
		for surface: Vector3 in [Vector3(5,0.49,0), Vector3(0,0.50,1)]:
			var edges := Geometry.stroke_edges(points, float(widths.get(road.get("width_class", "primary"), 12.0)) + surface.x)
			if edges.size() != 2 or edges[0].size() != points.size():
				continue
			var road_polygon := PackedVector2Array([edges[0][segment], edges[0][segment+1], edges[1][segment+1], edges[1][segment]])
			for polygon: PackedVector2Array in Geometry2D.intersect_polygons(road_polygon, rail_polygon):
				# 层级仍盖住枕木；实际面与路基共面，避免斜视下裁切边缘错开。
				result.append({"polygon": polygon, "height": surface.y, "surface_height": 0.30,
					"color": Color("555c59") if surface.z > 0.5 else Color("73796c"),
					"road_polygon": road_polygon, "rail_polygon": rail_polygon,
					"road_index": int(site.road), "site": crossing})
	return result
