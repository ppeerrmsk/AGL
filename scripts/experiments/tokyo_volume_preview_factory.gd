extends RefCounted
## 东京核心小片预览：真实 OSM footprint/高度与道路只在构建时合并，不创建逐栋节点或 tick。

const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Buildings := preload("res://scripts/experiments/volume_building_factory.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const DATA_PATH := "res://resources/maps/tokyo_volume_preview/r1_tokyo_downtown.json"
const GROUND_PATH := "res://resources/maps/tokyo_volume_preview/r3_ground.json"

const LOW_WALL := Color("747c79")
const LOW_ROOF := Color("929789")
const KNOWN_WALL := Color("858d89")
const KNOWN_ROOF := Color("a09f96")
const HIGHRISE_WALL := Color("919995")
const HIGHRISE_ROOF := Color("aaa89f")
const INDUSTRIAL_WALL := Color("737b78")
const INDUSTRIAL_ROOF := Color("858b87")
const FACADE_BAND := Color("56625f")
const ROOF_RIM := Color("4d5959")
const ROAD_CASING := Color("4b5554")
const ROAD_MAJOR := Color("636d6b")
const ROAD_MINOR := Color("6e7772")
const RAIL_CASING := Color("465253")
const RAIL_CORE := Color("a4aaa2")


static func build(data_path: String = DATA_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "Tokyo preview data did not parse"}
	var data: Dictionary = parsed
	var low := Geometry.new()
	var known := Geometry.new()
	var roads := Geometry.new()
	var rails := Geometry.new()
	var built_low := 0
	var built_known := 0
	var highrises := 0
	var invalid := 0
	var deferred := 0
	var part_outlines := 0
	for raw_any in data.get("buildings", []):
		if not raw_any is Dictionary:
			continue
		var raw: Dictionary = raw_any
		if bool(raw.get("defer_render", false)):
			deferred += 1
			continue
		if not bool(raw.get("render_outline", true)):
			part_outlines += 1
			continue
		var points := _points(raw.get("points", []))
		if points.size() < 3 or Geometry2D.triangulate_polygon(points).size() < 3:
			invalid += 1
			continue
		var height_px := maxf(1.6, float(raw.get("height_m", 6.4)) * CombatUnit.PIXELS_PER_METER)
		if raw.has("rings"):
			var is_known := String(raw.get("height_source", "fallback")) != "fallback"
			_add_ring_building(known if is_known else low, raw, height_px)
			if is_known:
				built_known += 1
				highrises += int(height_px >= 40)
			else:
				built_low += 1
			continue
		if String(raw.get("height_source", "fallback")) == "fallback":
			_add_low(low, points, height_px, String(raw.get("kind", "urban")))
			built_low += 1
		else:
			_add_known(known, points, height_px, raw)
			built_known += 1
			if height_px >= 40.0:
				highrises += 1
	for raw_any in data.get("roads", []):
		if not raw_any is Dictionary:
			continue
		var raw: Dictionary = raw_any
		var points := _points(raw.get("points", []))
		if points.size() < 2:
			continue
		var width := float(raw.get("width_px", 1.0))
		var road_class := String(raw.get("class", "service"))
		var major := road_class in ["motorway", "motorway_link", "trunk", "trunk_link",
			"primary", "primary_link", "secondary", "secondary_link"]
		if major:
			_path_ribbon(roads, raw, "casing", points, width + 0.65, 0.34, ROAD_CASING)
			_path_ribbon(roads, raw, "surface", points, width, 0.43, ROAD_MAJOR)
		else:
			_path_ribbon(roads, raw, "surface", points, width, 0.38, ROAD_MINOR)
	var visible_rails := 0
	for raw_any in data.get("rails", []):
		if not raw_any is Dictionary:
			continue
		var raw: Dictionary = raw_any
		if String(raw.get("class", "")) == "subway":
			continue
		var points := _points(raw.get("points", []))
		if points.size() < 2:
			continue
		_path_ribbon(rails, raw, "casing", points, 1.35, 0.50, RAIL_CASING)
		_path_ribbon(rails, raw, "surface", points, 0.32, 0.58, RAIL_CORE)
		visible_rails += 1
	var low_mesh: ArrayMesh = low.mesh()
	var known_mesh: ArrayMesh = known.mesh()
	var road_mesh: ArrayMesh = roads.mesh()
	var rail_mesh: ArrayMesh = rails.mesh()
	var triangle_counts := {
		"fallback_buildings": _triangles(low_mesh),
		"known_height_buildings": _triangles(known_mesh),
		"roads": _triangles(road_mesh),
		"rails": _triangles(rail_mesh),
	}
	var total_triangles := 0
	for count: int in triangle_counts.values():
		total_triangles += count
	var center_values: Array = data.get("center", [0.0, 0.0])
	var rect_values: Array = data.get("rect", [0.0, 0.0, 0.0, 0.0])
	return {
		"ok": invalid == 0,
		"reason": "" if invalid == 0 else "%d invalid building outlines" % invalid,
		"center": Vector2(float(center_values[0]), float(center_values[1])),
		"rect": Rect2(float(rect_values[0]), float(rect_values[1]),
			float(rect_values[2]), float(rect_values[3])),
		"low_mesh": low_mesh,
		"known_mesh": known_mesh,
		"road_mesh": road_mesh,
		"rail_mesh": rail_mesh,
		"source_buildings": (data.get("buildings", []) as Array).size(),
		"deferred_buildings": deferred,
		"part_assembly_outlines": part_outlines,
		"fallback_buildings": built_low,
		"known_height_buildings": built_known,
		"highrises": highrises,
		"roads": (data.get("roads", []) as Array).size(),
		"rails": visible_rails,
		"invalid_buildings": invalid,
		"triangle_counts": triangle_counts,
		"triangles": total_triangles,
	}


static func _add_low(builder: RefCounted, points: PackedVector2Array,
		height: float, kind: String) -> void:
	var wall := INDUSTRIAL_WALL if kind == "industrial" else LOW_WALL
	var roof := INDUSTRIAL_ROOF if kind == "industrial" else LOW_ROOF
	_shell(builder, points, 0.12, height, wall)
	_face(builder, points, height, roof)


static func build_ground(data_path: String = GROUND_PATH) -> ArrayMesh:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	var builder := Geometry.new()
	var bounds: Array = data.bounds
	var water_color := Color(String(data.get("water_color", "4b6972")))
	_face(builder, PackedVector2Array([Vector2(bounds[0], bounds[1]), Vector2(bounds[2], bounds[1]),
		Vector2(bounds[2], bounds[3]), Vector2(bounds[0], bounds[3])]), -0.35,
		water_color if data.get("base_kind", "land") == "water" else Color("80877e"))
	var colors := {"park": Color("697d65"), "green": Color("64765f"),
		"water": water_color, "land": Color("80877e"), "paved": Color("95958a"), "rail_yard": Color("757d77")}
	var elevations := {"land": -0.33, "park": -0.28, "green": -0.23, "rail_yard": -0.18, "paved": -0.13, "water": -0.08}
	for surface: Dictionary in data.surfaces:
		var points := _points(surface.triangles)
		for index in range(0, points.size(), 3):
			_face(builder, PackedVector2Array([points[index], points[index + 1], points[index + 2]]),
				float(elevations[surface.kind]), colors[surface.kind])
	for path: Dictionary in data.paths:
		_ribbon(builder, _points(path.points), 0.8, 0.22, Color("9c9d8d"))
	return builder.mesh()


static func _add_known(builder: RefCounted, points: PackedVector2Array,
		height: float, raw: Dictionary) -> void:
	var area := float(raw.get("area_px2", 0.0))
	var industrial := String(raw.get("kind", "urban")) == "industrial"
	var wall := INDUSTRIAL_WALL if industrial else (HIGHRISE_WALL if height >= 40.0 else KNOWN_WALL)
	var roof := INDUSTRIAL_ROOF if industrial else (HIGHRISE_ROOF if height >= 40.0 else KNOWN_ROOF)
	# 全高沿真实 footprint；不凭空缩楼体、加天线或超过标注高度。
	_shell(builder, points, 0.12, height, wall)
	_face(builder, points, height - 0.03, roof)
	if height < 12.0 or area < 35.0:
		return
	# 屋顶分区仅作材质概括；凹多边形不能用质心缩放制造越界屋顶。
	var insets := Geometry2D.offset_polygon(points, -0.45)
	for inset: PackedVector2Array in insets:
		_face(builder, inset, height - 0.015, roof.darkened(0.12))
		var panels := Geometry2D.offset_polygon(inset, -1.3)
		for panel: PackedVector2Array in panels:
			_face(builder, panel, height, roof)


static func _shell(builder: RefCounted, points: PackedVector2Array,
		bottom: float, top: float, color: Color, inner: bool = false) -> void:
	var clockwise := Geometry2D.is_polygon_clockwise(points) != inner
	for index in points.size():
		var p := points[index]
		var q := points[(index + 1) % points.size()]
		var a := Vector3(p.x, bottom, p.y)
		var b := Vector3(q.x, bottom, q.y)
		var up := Vector3.UP * (top - bottom)
		if clockwise:
			builder.quad(a, b, b + up, a + up, color)
		else:
			builder.quad(b, a, a + up, b + up, color)


static func _add_ring_building(builder: RefCounted, raw: Dictionary, height: float, detail_level: int = 0) -> void:
	var tags: Dictionary = raw.get("source_tags", {})
	var open_roof := String(tags.get("building", "")) == "roof" or String(tags.get("building:part", "")) == "roof"
	var industrial := String(raw.get("kind", "urban")) == "industrial"
	var known := String(raw.get("height_source", "fallback")) != "fallback"
	var wall := INDUSTRIAL_WALL if industrial else (HIGHRISE_WALL if height >= 40 and known else (KNOWN_WALL if known else LOW_WALL))
	var roof := INDUSTRIAL_ROOF if industrial else (HIGHRISE_ROOF if height >= 40 and known else (KNOWN_ROOF if known else LOW_ROOF))
	if raw.has("roof_volume") and detail_level < 2:
		if not open_roof:
			_prepared_surface(builder, raw.roof_volume.walls, wall)
		# 顶点 alpha 只作表面分类，不写 shader ALPHA；坡顶不误画立面窗带。
		roof.a = 0.0
		_prepared_surface(builder, raw.roof_volume.roof, roof)
		return
	var bottom := maxf(0.12, float(raw.get("min_height_m", 0.0)) * 0.5)
	for ring: Dictionary in raw.rings:
		# 开放屋盖不凭空生成落地围墙；未知支柱与封闭侧不推测。
		if detail_level < 2 and not open_roof:
			_shell(builder, _points(ring.outer), bottom, height, wall)
			for hole: Array in ring.holes:
				_shell(builder, _points(hole), bottom, height, wall, true)
		_triangle_face(builder, _points(ring.triangles), height - 0.03 if known and detail_level == 0 and not open_roof else height, roof)
		if detail_level == 0 and not open_roof:
			_triangle_face(builder, _points(ring.get("inset_triangles", [])), height - 0.015, roof.darkened(0.12))
			_triangle_face(builder, _points(ring.get("panel_triangles", [])), height, roof)


static func _triangle_face(builder: RefCounted, points: PackedVector2Array, height: float, color: Color) -> void:
	for index in range(0, points.size(), 3):
		var a := Vector3(points[index].x, height, points[index].y)
		var b := Vector3(points[index + 1].x, height, points[index + 1].y)
		var c := Vector3(points[index + 2].x, height, points[index + 2].y)
		if (b - a).cross(c - a).y < 0:
			builder.triangle(a, c, b, color)
		else:
			builder.triangle(a, b, c, color)


static func _prepared_surface(builder: RefCounted, triangles: Array, color: Color) -> void:
	for index in range(0, triangles.size(), 3):
		var a: Array = triangles[index]
		var b: Array = triangles[index + 1]
		var c: Array = triangles[index + 2]
		builder.triangle(Vector3(a[0], a[1], a[2]), Vector3(b[0], b[1], b[2]), Vector3(c[0], c[1], c[2]), color)


static func _path_ribbon(builder: RefCounted, raw: Dictionary, role: String, points: PackedVector2Array,
		width: float, height: float, color: Color) -> void:
	if not raw.has("joined_strokes"):
		_ribbon(builder, points, width, height, color)
		return
	var prepared: Dictionary = raw.joined_strokes.get(role, {})
	var triangles := _points(prepared.get("triangles", []))
	assert(is_equal_approx(float(prepared.get("width", -1)), width)
		and triangles.size() >= 3 and triangles.size() % 3 == 0, "Invalid offline joined stroke")
	# 离线已解析内孔与交叠；这里保持原材质/高度，仅提交朝上的三角面。
	for index in range(0, triangles.size(), 3):
		_face(builder, triangles.slice(index, index + 3), height, color)


static func _ribbon(builder: RefCounted, points: PackedVector2Array,
		width: float, height: float, color: Color) -> void:
	# 道路只有朝上的双三角面，不为每个线段创建有底有侧的盒子。
	for index in range(points.size() - 1):
		var p := points[index]
		var q := points[index + 1]
		var side := (q - p).normalized().orthogonal() * width * 0.5
		_face(builder, PackedVector2Array([p + side, q + side, q - side, p - side]), height, color)


static func _face(builder: RefCounted, points: PackedVector2Array,
		height: float, color: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	for index in range(0, indices.size(), 3):
		var a := Vector3(points[indices[index]].x, height, points[indices[index]].y)
		var b := Vector3(points[indices[index + 1]].x, height, points[indices[index + 1]].y)
		var c := Vector3(points[indices[index + 2]].x, height, points[indices[index + 2]].y)
		if (b - a).cross(c - a).y < 0.0:
			builder.triangle(a, c, b, color)
		else:
			builder.triangle(a, b, c, color)


static func _points(values_any: Variant) -> PackedVector2Array:
	var output := PackedVector2Array()
	if not values_any is Array:
		return output
	for value_any in values_any:
		if value_any is Array and value_any.size() >= 2:
			output.append(Vector2(float(value_any[0]), float(value_any[1])))
	return output


static func _triangles(mesh: ArrayMesh) -> int:
	return Indexed.triangles(mesh)
