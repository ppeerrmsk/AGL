extends RefCounted
## 原16栋轮廓内的海岛设施；不会调用沙漠城区/机场装饰生成器。
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Buildings := preload("res://scripts/experiments/volume_building_factory.gd")
const MapFactory := preload("res://scripts/experiments/volume_map_factory.gd")
const KINDS := ["assembly", "hangar", "hangar", "warehouse", "launch_pad", "gantry",
	"office", "warehouse", "hangar", "office", "tower", "warehouse", "tank", "tank", "tank", "tank"]
const BASE_RECT := Rect2(-11780, -7900, 2930, 2670)
const WALL := Color("737f79")
const ROOF := Color("92998e")


static func build(doc: MapDocument, detail: bool) -> ArrayMesh:
	var geometry := Geometry.new()
	for index in doc.buildings.size():
		var building: Dictionary = doc.buildings[index]
		var polygon := Geometry.points_from(building.footprint)
		var height := float(building.h_m) * 0.5
		var kind: String = KINDS[index]
		if kind == "gantry":
			_gantry(geometry, polygon, height, detail)
		elif kind == "launch_pad":
			geometry.prism(polygon, 0, height, Color("697975"))
			geometry.prism(Buildings.scaled_polygon(polygon, 0.86), height, height + 0.01, Color("899088"))
		elif kind == "assembly":
			geometry.prism(polygon, 0, height, WALL)
			MapFactory.face(geometry, Buildings.scaled_polygon(polygon, 0.98), height + 0.01, ROOF)
			if detail:
				_facade(geometry, polygon, height, true)
		elif not detail:
			geometry.prism(polygon, 0, height, WALL)
			MapFactory.face(geometry, polygon, height + 0.01, ROOF)
		else:
			Buildings.add(geometry, polygon, height,
				"warehouse" if kind in ["hangar", "warehouse"] else kind, WALL, ROOF)
			if kind == "hangar":
				_facade(geometry, polygon, height * 0.72, false)
	return geometry.mesh()


static func _gantry(builder: RefCounted, polygon: PackedVector2Array, height: float, detail: bool) -> void:
	var f := Buildings.frame(polygon)
	var posts := Buildings.scaled_polygon(polygon, 0.72)
	for point in posts:
		builder.prism(Buildings.rectangle(point, f.direction, Vector2.ONE * 5), 3, height, WALL)
	for tier in (5 if detail else 3):
		var y := 3 + (height - 3) * float(tier + 1) / (5 if detail else 3)
		for edge in posts.size():
			var a := posts[edge]
			var b := posts[(edge + 1) % posts.size()]
			builder.prism(Buildings.rectangle((a + b) * 0.5, (b - a).normalized(), Vector2(a.distance_to(b) + 5, 4)), y - 2, y, ROOF)
			if detail and tier < 4:
				var rise := (height - 3) / 5.0
				var start := Vector3(a.x, y - 1.6, a.y)
				var end := Vector3(b.x, y + rise - 1.6, b.y)
				builder.quad(start, end, end + Vector3.UP * 1.6, start + Vector3.UP * 1.6, WALL.lightened(0.1))


static func _facade(builder: RefCounted, polygon: PackedVector2Array, height: float, assembly: bool) -> void:
	var f := Buildings.frame(polygon)
	var center: Vector2 = f.center + f.side * float(f.width) * 0.5002
	var half: Vector2 = f.direction * float(f.length) * (0.30 if assembly else 0.40)
	var a := Vector3(center.x - half.x, 0.2, center.y - half.y)
	var b := Vector3(center.x + half.x, 0.2, center.y + half.y)
	# 向外两个面只加固定门板，仍在原footprint内，不生成附属占地。
	var lift := Vector3.UP * height * 0.84
	builder.quad(a, b, b + lift, a + lift, Color("455c60"))
	builder.quad(b, a, a + lift, b + lift, Color("455c60"))


static func runway(doc: MapDocument) -> ArrayMesh:
	var geometry := Geometry.new()
	for building: Dictionary in doc.buildings:
		MapFactory.face(geometry, Buildings.scaled_polygon(Geometry.points_from(building.footprint), 1.10),
			0.04, Color("78867b"))
	for band: PackedVector2Array in service_bands(doc):
		MapFactory.face(geometry, band, 0.08, Color("849083"))
	for airport: Dictionary in doc.airports:
		var polygon := MapFactory.airport_polygon(airport)
		MapFactory.face(geometry, polygon, 0.12, Color("475953"))
		var f := Buildings.frame(polygon)
		var length: float = f.length
		for side_sign: float in [-1, 1]:
			MapFactory.face(geometry, Buildings.rectangle(f.center + f.side * float(f.width) * 0.44 * side_sign,
				f.direction, Vector2(length * 0.96, 3.0)), 0.16, Color("bac2ad"))
		for index in 24:
			var center: Vector2 = f.center + f.direction * length * (float(index) / 23.0 - 0.5) * 0.9
			MapFactory.face(geometry, Buildings.rectangle(center, f.direction, Vector2(32, 3.5)), 0.17, Color("d0d3be"))
		for end_sign: float in [-1, 1]:
			for stripe in 6:
				var center: Vector2 = f.center + f.direction * length * 0.46 * end_sign + f.side * (stripe - 2.5) * 22
				MapFactory.face(geometry, Buildings.rectangle(center, f.direction, Vector2(46, 7)), 0.18, Color("c3c8b3"))
	return geometry.mesh()


static func service_bands(doc: MapDocument) -> Array[PackedVector2Array]:
	# 两侧服务道沿唯一跑道长轴布置，支路取源建筑最近边；只作静态地表标识。
	var result: Array[PackedVector2Array] = []
	var runway_frame := Buildings.frame(MapFactory.airport_polygon(doc.airports[0]))
	var direction: Vector2 = runway_frame.direction
	var side: Vector2 = runway_frame.side
	for sign_value: float in [-1, 1]:
		var center: Vector2 = runway_frame.center + side * (float(runway_frame.width) * 0.5 + 105) * sign_value
		result.append(Buildings.rectangle(center, direction, Vector2(float(runway_frame.length) * 0.90, 20)))
	for index in doc.buildings.size():
		if KINDS[index] == "gantry":
			continue
		var points := Geometry.points_from(doc.buildings[index].footprint)
		var f := Buildings.frame(points)
		var relative: Vector2 = f.center - runway_frame.center
		var sign_value := signf(relative.dot(side))
		var axis_point: Vector2 = runway_frame.center + direction * relative.dot(direction)
		var finish := axis_point + side * (float(runway_frame.width) * 0.5 + 105) * sign_value
		var nearest: Vector2 = f.center
		var best := INF
		for edge in points.size():
			var crossing: Variant = Geometry2D.segment_intersects_segment(f.center, finish,
				points[edge], points[(edge + 1) % points.size()])
			if crossing is Vector2 and f.center.distance_squared_to(crossing) < best:
				nearest = crossing
				best = f.center.distance_squared_to(crossing)
		var found := false
		for offset: float in [0, 120, -120, 240, -240, 360, -360]:
			var route := PackedVector2Array([nearest])
			if offset != 0:
				var pivot := nearest - side * sign_value * 100
				route.append(pivot)
				route.append(pivot + direction * offset)
			route.append(finish + direction * offset)
			var bands := _route_bands(route)
			if _route_clear(bands, doc, index):
				result.append_array(bands)
				found = true
				break
		assert(found, "ocean base service road must route around source structures")
	return result


static func _route_bands(route: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for index in range(route.size() - 1):
		var a := route[index]
		var b := route[index + 1]
		result.append(Buildings.rectangle((a + b) * 0.5, (b - a).normalized(), Vector2(a.distance_to(b), 18)))
	return result


static func _route_clear(bands: Array[PackedVector2Array], doc: MapDocument, owner_index: int) -> bool:
	for band in bands:
		for point in band:
			if not Geometry2D.is_point_in_polygon(point, doc.layer_polygons.land[1]):
				return false
		for index in doc.buildings.size():
			if index == owner_index:
				continue
			if not Geometry2D.intersect_polygons(band, Geometry.points_from(doc.buildings[index].footprint)).is_empty():
				return false
	return true
