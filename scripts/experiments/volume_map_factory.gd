extends RefCounted
## 批次 A 的静态三维地图：只读 MapDocument，绝不生成第二套玩法地理。
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Buildings := preload("res://scripts/experiments/volume_building_factory.gd")
const Districts := preload("res://scripts/experiments/volume_district_layout.gd")
const TacticalContext := preload("res://scripts/experiments/volume_desert_tactical_context.gd")
const Crossings := preload("res://scripts/experiments/volume_rail_crossings.gd")
const LINE_SHADER := preload("res://resources/shaders/volume_map_line.gdshader")
const STRUCTURE_SHADER := preload("res://resources/shaders/volume_structure_surface.gdshader")
const TACTICAL_STRUCTURE_SHADER := preload("res://resources/shaders/volume_desert_tactical_structure.gdshader")
const ContactAO := preload("res://scripts/rendering/map_contact_ao.gd")
const AO_APRON_SHADER := preload("res://resources/shaders/desert_contact_ao_apron.gdshader")
const TRIANGLE_BUDGET := 12000
const DETAIL_MAX_HEIGHT := 42.0
const STRUCTURE_HEIGHT_SCALE := 1.35
const SUN_ROTATION_DEGREES := Vector3(-50, -35, 0)
const TERRAIN_ELEVATIONS := {"land": 0.0, "mountain": 0.02, "forest": 0.04,
	"farmland": 0.06, "beach": 0.08, "urban": 0.10}
const ROAD_WIDTHS := {"motorway": 25.0, "trunk": 20.0, "primary": 16.0,
	"secondary": 12.0, "tertiary": 9.0, "residential": 7.0, "service": 6.0}


static func build(doc: MapDocument, detailed: bool = true, satellite_ground: bool = false, road_joins: bool = true, road_crossings: bool = true) -> Dictionary:
	# 本批仅支持独立 union 地理面；不把 even-odd 水洞错误填成陆地。
	for layer in MapDocument.CELL_LAYERS:
		if not doc.layer_polygons.get(layer, []).is_empty() and doc.layer_mode.get(layer, "even_odd") != "union":
			return {"ok": false, "reason": "unsupported polygon holes: " + layer}
	var builder := Geometry.new()
	var industrial := Geometry.new()
	var structures: Array[ArrayMesh] = []
	var line_records: Array[Dictionary] = []
	var detail_count := 0
	var districts: Array[Dictionary] = []
	var extent := doc.world_size_m * CombatUnit.PIXELS_PER_METER
	var land := Color("8b8672") if satellite_ground else palette(doc, "land")
	var road_core := Color("555c59") if satellite_ground else palette(doc, "road").darkened(0.40)
	var road_shoulder := Color("73796c") if satellite_ground else land.darkened(0.28)
	builder.box(Vector3(0, -2, 0), Vector3(extent, 2, extent), palette(doc, "sea"))
	for layer in MapDocument.CELL_LAYERS:
		var color := palette(doc, "terrain_" + layer)
		if satellite_ground:
			continue # 同源瓦片承担地表，不让概括多边形覆盖已有细节。
		if layer in ["land", "urban"]:
			color = palette(doc, layer)
		# 粗粒度来源区域只作低对比底色，不能压过飞机、铁路和作战标记。
		if layer != "land":
			color = land.lerp(color, 0.35)
		var elevation := float(TERRAIN_ELEVATIONS.get(layer, 0.0))
		for polygon: PackedVector2Array in doc.layer_polygons.get(layer, []):
			# 没有 DEM 的区域不凭空增加山高、阻挡或悬空道路。
			face(builder, polygon, elevation, color)
	var road_join_count := 0
	for road_index in doc.roads.size():
		var road: Dictionary = doc.roads[road_index]
		var points := road_presentation_points(doc, road_index, road_joins and satellite_ground)
		road_join_count += int(points.size() > road.get("points", []).size())
		var width := float(ROAD_WIDTHS.get(road.get("width_class", "primary"), 12.0))
		line_records.append({"points": points, "width": width + 5.0, "height": 0.15, "color": road_shoulder})
		line_records.append({"points": points, "width": width, "height": 0.20, "color": road_core})
	for railway: Dictionary in doc.railways:
		var points := Geometry.points_from(railway.get("points", []))
		line_records.append({"points": points, "width": 20.0, "height": 0.30, "rail_lod": 1.0,
			"color": Color("aaa188") if satellite_ground else land.lightened(0.13)})
		var rails := stroke_edges(points, 10.0)
		if rails.size() == 2:
			for rail: PackedVector2Array in rails:
				line_records.append({"points": rail, "width": 2.6, "height": 0.55, "rail_lod": 2.0,
					"color": Color("293331") if satellite_ground else Color("b4aa90")})
		# 沿整条路线累计弧长，不在每个折点重置枕木间距。
		for pose: Vector3 in sleeper_poses(points):
			var center := Vector2(pose.x, pose.y)
			var sideways := Vector2(-sin(pose.z), cos(pose.z)) * 7.0
			line_records.append({"points": PackedVector2Array([center - sideways, center + sideways]),
				"width": 3.2, "height": 0.45, "rail_lod": 2.0,
				"color": Color("5b5a50") if satellite_ground else palette(doc, "building_wall_shade")})
	for airport: Dictionary in doc.airports:
		var polygon := airport_polygon(airport)
		if detailed:
			var airport_builder := Geometry.new()
			detail_count += _add_airport_details(builder, airport_builder, line_records, polygon, land)
			var airport_mesh := airport_builder.mesh()
			if airport_mesh.get_surface_count() > 0:
				structures.append(airport_mesh)
		face(builder, polygon, 0.65, land.darkened(0.48))
		_add_runway_markings(line_records, polygon)
	for building: Dictionary in doc.buildings:
		var footprint := Geometry.points_from(building.get("footprint", []))
		if footprint.size() < 3:
			continue
		var height := maxf(0.1, float(building.get("h_m", 20.0)) * CombatUnit.PIXELS_PER_METER)
		if detailed:
			var kind := "tank" if footprint.size() == 8 else ("tower" if float(Buildings.frame(footprint).length) < 70 else "warehouse")
			face(builder, Buildings.scaled_polygon(footprint, 1.06 if kind == "warehouse" else 1.14), 0.12, land.darkened(0.18))
			Buildings.add(industrial, footprint, height, "industrial_warehouse" if kind == "warehouse" else kind, Color("aa9c81"),
				Buildings.INDUSTRIAL_ROOF if kind == "warehouse" else Color("77838a"))
			if kind == "warehouse":
				Buildings.industrial_roof_details(industrial, footprint, height)
			if kind == "tank":
				var bund := Buildings.scaled_polygon(footprint, 1.24)
				for i in bund.size():
					var a := bund[i]
					var b := bund[(i + 1) % bund.size()]
					industrial.prism(Buildings.rectangle((a + b) * 0.5, (b - a).normalized(), Vector2(a.distance_to(b), 1.6)), 0.0, 0.7, land.lightened(0.15))
			continue
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
	if detailed:
		_add_industrial_details(industrial, doc)
		var industrial_mesh := industrial.mesh()
		if industrial_mesh.get_surface_count() > 0:
			structures.append(industrial_mesh)
		districts = Districts.layout(doc, ROAD_WIDTHS)
		for district in districts:
			var district_builder := Geometry.new()
			var roofs: Array[Color] = [Color("77838a"), Color("b0a18a"), Color("727f80")]
			for street: PackedVector2Array in district.streets:
				line_records.append({"points": street, "width": 12.0, "height": 0.15, "color": road_shoulder})
				line_records.append({"points": street, "width": 8.0, "height": 0.20, "color": road_core})
			for driveway: PackedVector2Array in district.driveways:
				line_records.append({"points": driveway, "width": 6.0, "height": 0.16,
					"color": Color("918572")})
			for plot: Dictionary in district.plots:
				# 小块硬地坪沿建筑自身长轴，不用世界轴方块造成底板斜错。
				var plot_frame := Buildings.frame(plot.footprint)
				var half_axis: Vector2 = plot_frame.direction * (float(plot_frame.length) + 16.0) * 0.5
				line_records.append({"points": PackedVector2Array([plot_frame.center - half_axis,
					plot_frame.center + half_axis]), "width": float(plot_frame.width) + 16.0,
					"height": 0.13, "color": Color("8e826a")})
				var roof: Color = roofs[(int(district.source_urban_index) + int(plot.tone)) % roofs.size()]
				var wall := Color("baa88d").lerp(Color("8e948e"), float(plot.tone) * 0.12)
				Buildings.add(district_builder, plot.footprint, plot.height_px, plot.kind,
					wall, roof)
			var district_mesh := district_builder.mesh()
			if district_mesh.get_surface_count() > 0:
				structures.append(district_mesh)
	var ground_mesh := builder.mesh()
	var crossing_surfaces: Array[Dictionary] = []
	if road_crossings and satellite_ground and TacticalContext.is_enabled(String(doc.basemap.get("tile_map_key", ""))):
		crossing_surfaces = Crossings.records(doc, ROAD_WIDTHS)
		line_records.append_array(crossing_surfaces)
	var line_mesh := _line_mesh(line_records)
	var parts: Array[ArrayMesh] = [ground_mesh, line_mesh]
	parts.append_array(structures)
	var result := merge_meshes(parts)
	var triangles := result.surface_get_array_len(0) / 3
	return {"ok": triangles <= TRIANGLE_BUDGET, "mesh": result, "triangles": triangles,
		"buildings": doc.buildings.size(), "airports": doc.airports.size(),
		"roads": doc.roads.size(), "railways": doc.railways.size(), "extent_px": extent,
		"road_join_count": road_join_count,
		"crossing_surfaces": crossing_surfaces,
		"airport_details": detail_count, "detailed": detailed,
		"ground_mesh": ground_mesh, "line_mesh": line_mesh, "structure_meshes": structures,
		"districts": districts,
		"satellite_ground": satellite_ground,
		"tactical_style": TacticalContext.is_enabled(String(doc.basemap.get("tile_map_key", ""))),
		"reason": "" if triangles <= TRIANGLE_BUDGET else "map triangle budget exceeded"}


static func road_presentation_points(doc: MapDocument, index: int, join_gaps: bool = true) -> PackedVector2Array:
	var points := Geometry.points_from(doc.roads[index].get("points", []))
	if not join_gaps or not TacticalContext.is_enabled(String(doc.basemap.get("tile_map_key", ""))):
		return points
	# 只补R77/R78逐区确认的两处短断口；保留源端点，沿原切向延至接收道路。
	var joins := {2: {"target": 0, "anchor": Vector2(-10100, 10100)},
		9: {"target": 2, "anchor": Vector2(-11200, 9000)}}
	if not joins.has(index) or points.size() < 2 or points[0] != joins[index].anchor:
		return points
	var target := Geometry.points_from(doc.roads[int(joins[index].target)].get("points", []))
	if target.size() < 2:
		return points
	var direction := (points[0] - points[1]).normalized()
	var crossing: Variant = Geometry2D.segment_intersects_segment(points[0], points[0] + direction * 160.0, target[0], target[1])
	if crossing is Vector2 and points[0].distance_to(crossing) > 0.01:
		points.insert(0, crossing)
	return points


static func _add_airport_details(builder: RefCounted, structures: RefCounted,
		line_records: Array[Dictionary], polygon: PackedVector2Array, land: Color) -> int:
	if polygon.size() != 4:
		return 0
	var f := Buildings.frame(polygon)
	for surface: Dictionary in airport_service_surfaces(polygon):
		face(builder, surface.footprint, surface.height, land.darkened(surface.shade))
	for fraction in [-0.24, 0.24]:
		var start: Vector2 = f.center + f.direction * float(f.length) * fraction
		var end: Vector2 = start + f.side * 85.0
		line_records.append({"points": PackedVector2Array([start, end]), "width": 16.0,
			"height": 0.30, "color": land.lightened(0.05)})
		line_records.append({"points": PackedVector2Array([start, end]), "width": 12.0,
			"height": 0.35, "color": land.darkened(0.40)})
	var details := Buildings.airport_details(polygon)
	for detail: Dictionary in details:
		Buildings.add(structures, detail.footprint, detail.height_px, detail.kind,
			Color("aa9c81"), Color("77838a"))
	return details.size()


static func airport_service_surfaces(polygon: PackedVector2Array) -> Array[Dictionary]:
	if polygon.size() != 4:
		return []
	var f := Buildings.frame(polygon)
	var length: float = f.length
	var result: Array[Dictionary] = []
	# 原主场坪与三处独立服务场坪共用机场局部坐标，不移动建筑或跑道。
	for definition: Vector4 in [Vector4(0, 110, length * 0.56, 76),
			Vector4(-length * 0.35, 115, 36, 70),
			Vector4(length * 0.38, 120, 86, 60),
			Vector4(length * 0.36, 175, length * 0.08 + 32, 32)]:
		var center: Vector2 = f.center + f.direction * definition.x + f.side * definition.y
		result.append({"footprint": Buildings.rectangle(center, f.direction, Vector2(definition.z, definition.w)),
			"height": 0.25, "shade": 0.30})
	# 一体T形路口，避免油罐支路与后侧服务路共面叠画。
	var local := PackedVector2Array([Vector2(-length * 0.35, 146), Vector2(length * 0.40, 146),
		Vector2(length * 0.40, 154), Vector2(length * 0.36 + 4, 154),
		Vector2(length * 0.36 + 4, 163), Vector2(length * 0.36 - 4, 163),
		Vector2(length * 0.36 - 4, 154), Vector2(-length * 0.35, 154)])
	var road := PackedVector2Array()
	for point: Vector2 in local:
		road.append(f.center + f.direction * point.x + f.side * point.y)
	result.append({"footprint": road, "height": 0.28, "shade": 0.40})
	return result


static func merge_meshes(meshes: Array[ArrayMesh]) -> ArrayMesh:
	# 仅构建/导出时合并，实际场景只绑定分块版，避免重复画和整图投影。
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for mesh in meshes:
		var source := mesh.surface_get_arrays(0)
		vertices.append_array(source[Mesh.ARRAY_VERTEX])
		normals.append_array(source[Mesh.ARRAY_NORMAL])
		colors.append_array(source[Mesh.ARRAY_COLOR])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


static func configure_instance(root: MeshInstance3D, packet: Dictionary, material: Material) -> void:
	# 一次接线：只有区域子节点，无逐栋节点、tick 或材质副本。
	assert(root.get_child_count() == 0, "map instance must be configured once")
	root.mesh = packet.ground_mesh
	root.material_override = material
	if packet.satellite_ground and packet.get("tactical_style", false):
		var apron := ShaderMaterial.new()
		apron.shader = AO_APRON_SHADER
		if ContactAO.bind(apron, "desert"):
			root.material_override = apron
	root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var line := MeshInstance3D.new()
	line.name = "CrispRouteNetwork"
	line.mesh = packet.line_mesh
	var line_material := ShaderMaterial.new()
	line_material.shader = LINE_SHADER
	line_material.set_shader_parameter("vertex_color_enabled", true)
	line_material.set_shader_parameter("rail_lod_enabled", packet.satellite_ground and packet.get("tactical_style", false))
	line_material.set_shader_parameter("route_coverage_enabled", packet.satellite_ground and packet.get("tactical_style", false))
	line_material.render_priority = 20
	line.material_override = line_material
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(line)
	var structure_material: Material = material
	if packet.satellite_ground:
		var surface_material := ShaderMaterial.new()
		var surface_texture: Texture2D = load("res://resources/maps/desert_rock_albedo_r40.res")
		surface_material.shader = TACTICAL_STRUCTURE_SHADER if packet.get("tactical_style", false) else STRUCTURE_SHADER
		if packet.get("tactical_style", false):
			ContactAO.bind(surface_material, "desert")
		surface_material.set_shader_parameter("surface_texture", surface_texture)
		surface_material.set_shader_parameter("surface_mean_srgb", surface_texture.get_meta("mean_srgb"))
		surface_material.set_shader_parameter("surface_mean_linear", surface_texture.get_meta("mean_linear"))
		structure_material = surface_material
	for mesh: ArrayMesh in packet.structure_meshes:
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.material_override = structure_material
		part.scale.y = STRUCTURE_HEIGHT_SCALE
		root.add_child(part)


static func configure_sun(sun: DirectionalLight3D) -> void:
	# 观察场和真实战局必须共用方向/阴影；不能靠不同灯光形成假改善。
	sun.rotation_degrees = SUN_ROTATION_DEGREES
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_fade_start = 1.0


static func _add_industrial_details(builder: RefCounted, doc: MapDocument) -> void:
	if not doc.buildings.is_empty():
		var main_points := Geometry.points_from(doc.buildings[0].get("footprint", []))
		if main_points.size() == 4:
			var f := Buildings.frame(main_points)
			var platform: Vector2 = f.center - f.side * 120.0
			builder.prism(Buildings.rectangle(platform, f.direction, Vector2(130, 10)), 14, 15, Color("6b7981"))
			for offset: float in [-60, -20, 20, 60]:
				builder.prism(Buildings.rectangle(platform + f.direction * offset, f.direction, Vector2(2, 2)), 0, 14, Color("6b7981"))
			for definition: Vector3 in [Vector3(-50, 7, 36), Vector3(0, 8, DETAIL_MAX_HEIGHT), Vector3(50, 6, 32)]:
				var center: Vector2 = platform + f.direction * definition.x
				var points := PackedVector2Array()
				for i in 12:
					points.append(center + Vector2.from_angle(TAU * i / 12.0) * definition.y)
				Buildings.add(builder, points, definition.z, "tank", Color("adb7b7"), Color("77838a"))
	var tanks: Array[Vector2] = []
	var south := -INF
	for building: Dictionary in doc.buildings:
		var points := Geometry.points_from(building.get("footprint", []))
		if points.size() != 8:
			continue
		var center: Vector2 = Buildings.frame(points).center
		tanks.append(center)
		south = maxf(south, center.y + 110.0)
	if tanks.size() < 2:
		return
	var paths: Array[PackedVector2Array] = []
	var min_x := INF
	var max_x := -INF
	for center: Vector2 in tanks:
		paths.append(PackedVector2Array([center, Vector2(center.x, south)]))
		min_x = minf(min_x, center.x)
		max_x = maxf(max_x, center.x)
	paths.append(PackedVector2Array([Vector2(min_x, south), Vector2(max_x, south)]))
	for path: PackedVector2Array in paths:
		var direction := (path[1] - path[0]).normalized()
		var length := path[0].distance_to(path[1])
		builder.prism(Buildings.rectangle((path[0] + path[1]) * 0.5, direction, Vector2(length, 2.4)),
			2.0, 2.5, Color("6b7981"))
		for fraction: float in [0.25, 0.5, 0.75]:
			builder.prism(Buildings.rectangle(path[0].lerp(path[1], fraction), direction, Vector2(2, 5)),
				0, 2.0, Color("796c58"))


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
	return Geometry.stroke_edges(points, width)


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


static func _add_runway_markings(line_records: Array[Dictionary], polygon: PackedVector2Array) -> void:
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
		line_records.append({"points": PackedVector2Array([start + direction * 20 + offset,
			end - direction * 20 + offset]), "width": 1.8, "height": 0.75, "color": mark})
	for threshold in [start + direction * 24, end - direction * 24]:
		for fraction in [-0.65, -0.40, -0.15, 0.15, 0.40, 0.65]:
			var center: Vector2 = threshold + side * half_width * fraction
			line_records.append({"points": PackedVector2Array([center - direction * 9,
				center + direction * 9]), "width": 2.4, "height": 0.75, "color": mark})
	var distance := 50.0
	while distance < axis.length() - 50.0:
		line_records.append({"points": PackedVector2Array([start + direction * distance,
			start + direction * minf(distance + 25.0, axis.length() - 50.0)]),
			"width": 2.2, "height": 0.75, "color": mark})
		distance += 55.0


## 路网独立为一个带横向UV的静态表面；所有折点仍共享同一对边界。
static func _line_mesh(records: Array[Dictionary]) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var feature_uvs := PackedVector2Array()
	# 透明线路不写深度：height是提交层级；补面可用独立surface_height保证共面。
	# 只排序索引；等高保留来源次序，输入记录和每个线段的几何/UV均不改。
	var order: Array[int] = []
	for i in records.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return a < b if records[a].height == records[b].height else records[a].height < records[b].height)
	for index: int in order:
		var record: Dictionary = records[index]
		if record.has("polygon"):
			var patch := Geometry.new()
			face(patch, record.polygon, float(record.get("surface_height", record.height)), record.color)
			vertices.append_array(patch._vertices)
			normals.append_array(patch._normals)
			colors.append_array(patch._colors)
			for _vertex in patch._vertices.size():
				# 已裁切的路面内部不再向内削边；边缘沿用视口MSAA，不改旧线UV。
				uvs.append(Vector2(0, 0.5))
				feature_uvs.append(Vector2.ZERO)
			continue
		var points: PackedVector2Array = record.points
		var edges := stroke_edges(points, float(record.width))
		if edges.is_empty():
			continue
		var along := 0.0
		for i in range(edges[0].size() - 1):
			# stroke_edges 会清除重复点；用实际边界中心求长度，避免 UV 与清理后的折线错位。
			var center_a: Vector2 = (edges[0][i] + edges[1][i]) * 0.5
			var center_b: Vector2 = (edges[0][i + 1] + edges[1][i + 1]) * 0.5
			var segment_length := center_a.distance_to(center_b)
			var quad := [
				Vector3(edges[0][i].x, float(record.height), edges[0][i].y),
				Vector3(edges[1][i].x, float(record.height), edges[1][i].y),
				Vector3(edges[1][i + 1].x, float(record.height), edges[1][i + 1].y),
				Vector3(edges[0][i + 1].x, float(record.height), edges[0][i + 1].y)]
			var quad_uv := [Vector2(along, 0), Vector2(along, 1),
				Vector2(along + segment_length, 1), Vector2(along + segment_length, 0)]
			for triangle in [[0, 1, 2], [0, 2, 3]]:
				var a: Vector3 = quad[triangle[0]]
				var b: Vector3 = quad[triangle[1]]
				var c: Vector3 = quad[triangle[2]]
				var normal := (b - a).cross(c - a).normalized()
				for corner in [triangle[0], triangle[2], triangle[1]]:
					vertices.append(quad[corner])
					normals.append(normal)
					colors.append(record.color)
					uvs.append(quad_uv[corner])
					feature_uvs.append(Vector2(float(record.get("rail_lod", 0.0)), 0))
			along += segment_length
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = feature_uvs
	var result := ArrayMesh.new()
	if not vertices.is_empty():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


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
