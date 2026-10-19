extends RefCounted
const MapFactory := preload("res://scripts/experiments/volume_map_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Buildings := preload("res://scripts/experiments/volume_building_factory.gd")
var _pass := 0
var _fail := 0


func run() -> bool:
	# 在有界focused中先发现正式Visual入口解析错误，避免等截图进程超时才暴露。
	var formal_entry_script := load("res://scripts/tests/desert_formal_entry_runner.gd") as Script
	_check(formal_entry_script != null and formal_entry_script.can_instantiate(), "formal desert visual entry compiles before launching its scene")
	var doc := MapDocument.load_from("res://resources/maps/desert_railway_preview.aglmap")
	var before := JSON.stringify(doc.to_json_dict())
	var packet := MapFactory.build(doc)
	_check(packet.get("ok", false), "desert builds within triangle budget")
	_check(JSON.stringify(doc.to_json_dict()) == before, "map factory never mutates geography")
	var mesh: ArrayMesh = packet.mesh
	_check(mesh.get_surface_count() == 1, "one static surface/material")
	_check(packet.structure_meshes.size() == 7, "industrial, three airports and three districts are separate static casting regions")
	_check(load("res://scripts/tests/test_volume_district_layout.gd").new().run(doc, packet.districts, MapFactory.ROAD_WIDTHS), "district source and clearance contract")
	var split_vertices: int = packet.ground_mesh.surface_get_array_len(0) \
		+ packet.line_mesh.surface_get_array_len(0)
	var tight_regions := true
	for part: ArrayMesh in packet.structure_meshes:
		split_vertices += part.surface_get_array_len(0)
		var bounds := part.get_aabb()
		tight_regions = tight_regions and maxf(bounds.size.x, bounds.size.z) < 2000.0
	_check(split_vertices == mesh.surface_get_array_len(0), "split rendering neither loses nor doubles geometry")
	_check(tight_regions, "shadow casters do not inherit the full map bounding box")
	var ground_arrays: Array = packet.ground_mesh.surface_get_arrays(0)
	var terrain_vertices: PackedVector3Array = ground_arrays[Mesh.ARRAY_VERTEX]
	var mountain_height_seen := false
	var urban_height_seen := false
	for point in terrain_vertices:
		mountain_height_seen = mountain_height_seen or is_equal_approx(point.y, 0.02)
		urban_height_seen = urban_height_seen or is_equal_approx(point.y, 0.10)
	_check(mountain_height_seen and urban_height_seen
		and MapFactory.TERRAIN_ELEVATIONS.urban > MapFactory.TERRAIN_ELEVATIONS.mountain,
		"actual overlapping terrain layers have distinct depths below roads and building pads")
	var map_instance := MeshInstance3D.new()
	var shared_material := Geometry.material()
	MapFactory.configure_instance(map_instance, packet, shared_material)
	_check(map_instance.mesh == packet.ground_mesh
		and map_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"ground only receives shadows and does not bind merged export geometry")
	var shared := map_instance.get_child_count() == 8
	for child: MeshInstance3D in map_instance.get_children():
		if child.name == "CrispRouteNetwork":
			shared = shared and child.material_override is ShaderMaterial \
				and (child.material_override as ShaderMaterial).shader == MapFactory.LINE_SHADER \
				and child.material_override.get_shader_parameter("vertex_color_enabled") \
				and child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			shared = shared and child.material_override == shared_material \
				and child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
				and is_equal_approx(child.scale.y, MapFactory.STRUCTURE_HEIGHT_SCALE)
		shared = shared and not child.is_processing() and not child.is_physics_processing()
	_check(shared, "one crisp route surface and seven vertically legible casting regions have no ticks")
	map_instance.free()
	var sun := DirectionalLight3D.new()
	MapFactory.configure_sun(sun)
	_check(sun.rotation_degrees.is_equal_approx(MapFactory.SUN_ROTATION_DEGREES)
		and sun.shadow_enabled and sun.directional_shadow_fade_start == 1.0
		and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL,
		"lab and gameplay share shadow direction without far-ground fading")
	sun.free()
	# 铁路有正式界外进场段；整包 AABB 会大于地表，不能用它断言地图被放大。
	_check(packet.extent_px == doc.world_size_m * CombatUnit.PIXELS_PER_METER,
		"ground extent reads document metres and shared conversion")
	_check(packet.buildings == doc.buildings.size() and packet.airports == 3 and packet.roads == 12,
		"all source buildings airports and roads included")
	_check(packet.airport_details == 21, "three airports each contain seven designed structures")
	_check(MapFactory.build(doc, false).triangles < packet.triangles, "batch A geometry retained for paired comparison")
	var arrays := mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ground_extent := doc.world_size_m * CombatUnit.PIXELS_PER_METER * 0.5
	_check(vertices[0].y == -1.0 and absf(vertices[0].x) == ground_extent
		and absf(vertices[0].z) == ground_extent, "actual ground vertex uses document boundary")
	var valid := true
	for i in range(0, vertices.size(), 3):
		var cross := (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i])
		valid = valid and vertices[i].is_finite() and cross.length_squared() > 0.000001
		valid = valid and cross.dot(normals[i]) < 0.0
	_check(valid, "finite nondegenerate geometry and outward clockwise normals")
	var source_max_height := 0.0
	for building: Dictionary in doc.buildings:
		source_max_height = maxf(source_max_height, float(building.h_m) * CombatUnit.PIXELS_PER_METER)
	_check(mesh.get_aabb().end.y <= maxf(source_max_height, MapFactory.DETAIL_MAX_HEIGHT) + 0.1,
		"source buildings and designed refining/control towers obey separate height ceilings")
	var old_heights_preserved := true
	for building: Dictionary in doc.buildings:
		var building_source := Geometry.new()
		var footprint := Geometry.points_from(building.footprint)
		var height := float(building.h_m) * CombatUnit.PIXELS_PER_METER
		var kind := "tank" if footprint.size() == 8 else ("tower" if float(Buildings.frame(footprint).length) < 70 else "warehouse")
		Buildings.add(building_source, footprint, height, kind, Color.WHITE, Color.WHITE)
		var bounds := building_source.mesh().get_aabb()
		old_heights_preserved = old_heights_preserved and absf(bounds.end.y - height) < 0.01 and bounds.position.y == 0
	_check(old_heights_preserved, "each original building independently retains its source height")
	var points := Geometry.points_from(doc.railways[0].points)
	_test_industrial_clearance(doc, points)
	_check(points == ArmoredTrainBoss.train_route(), "railway uses actual train route without offset")
	var edges := MapFactory.stroke_edges(points, 10.0)
	var centered := edges[0].size() == points.size()
	for i in points.size():
		centered = centered and ((edges[0][i] + edges[1][i]) * 0.5).distance_to(points[i]) < 0.01
	_check(centered, "every shared rail joint remains centred on source route")
	var line_arrays: Array = packet.line_mesh.surface_get_arrays(0)
	_test_line_submission_order(line_arrays)
	_test_rail_lod(doc)
	_test_road_joins(doc)
	_check(load("res://scripts/tests/test_volume_rail_crossings.gd").new().run(doc), "reviewed ground crossings preserve the original route batch")
	_check(line_arrays[Mesh.ARRAY_TEX_UV].size() == line_arrays[Mesh.ARRAY_VERTEX].size()
		and line_arrays[Mesh.ARRAY_TEX_UV][0].y == 0.0
		and line_arrays[Mesh.ARRAY_TEX_UV][1].y == 1.0,
		"route mesh carries continuous cross-line UV for shader antialiasing")
	var bend := PackedVector2Array([Vector2(0, 0), Vector2(60, 0), Vector2(60, 60)])
	var bent_edges := MapFactory.stroke_edges(bend, 10.0)
	_check(bent_edges[0][1].distance_to(Vector2(55, 5)) < 0.001, "90 degree rail joint has exact continuous miter")
	var sleepers := MapFactory.sleeper_poses(bend, 24.0)
	_check(sleepers.size() == 5 and sleepers[3].distance_to(Vector3(60, 24, PI * 0.5)) < 0.001,
		"sleepers retain cumulative spacing across segment boundaries")
	_check(MapFactory.stroke_edges(PackedVector2Array([Vector2.ZERO, Vector2.ZERO]), 10).is_empty(),
		"degenerate route safely skipped")
	var square := PackedVector2Array([Vector2.ZERO, Vector2(60, 0), Vector2(60, 60), Vector2(0, 60), Vector2.ZERO])
	var closed_edges := Geometry.stroke_edges(square, 10, true)
	_check(closed_edges[0].size() == 5 and closed_edges[0][0] == Vector2(5, 5)
		and closed_edges[1][0] == Vector2(-5, -5) and closed_edges[0][-1] == closed_edges[0][0]
		and closed_edges[1][-1] == closed_edges[1][0], "closed stroke shares cyclic first/last miter without a cap seam")
	var duplicates := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2(60, 0), Vector2(60, 60), Vector2(0, 60), Vector2.ZERO])
	_check(Geometry.stroke_edges(duplicates, 10, true) == closed_edges
		and Geometry.stroke_edges(PackedVector2Array([Vector2.ZERO, Vector2.ONE, Vector2.ZERO]), 10, true).is_empty()
		and Geometry.stroke_edges(square, 0, true).is_empty(), "closed stroke removes duplicate endpoints and rejects insufficient paths or zero width")
	var hairpin := PackedVector2Array([Vector2.ZERO, Vector2(60, 0), Vector2.ZERO, Vector2(0, 60)])
	var hairpin_edges := Geometry.stroke_edges(hairpin, 10, true)
	var bounded := true
	for side: PackedVector2Array in hairpin_edges:
		for i in hairpin.size():
			bounded = bounded and side[i].is_finite() and side[i].distance_to(hairpin[i]) <= 20.001
	_check(bounded, "reversal and acute closed joins remain finite within the existing miter limit")
	for airport: Dictionary in doc.airports:
		_check(MapFactory.airport_polygon(airport) == Geometry.points_from(airport.polygon),
			"airport exact footprint preserved")
		var runway := MapFactory.airport_polygon(airport)
		var clear := true
		for detail: Dictionary in Buildings.airport_details(runway):
			clear = clear and Geometry2D.intersect_polygons(runway, detail.footprint).is_empty()
		_check(clear, "all airport structures stay clear of actual runway")
		_test_airport_services(runway, packet.ground_mesh)
	var rectangle := MapFactory.airport_polygon({"center": [100, 200], "size": [20, 100], "rotation_deg": 90})
	_check(rectangle[0].distance_to(Vector2(150, 190)) < 0.001, "UGC rectangle conversion rotates about actual centre")
	_check(MapFactory.palette(doc, "land") == Color(0.48, 0.31, 0.16, 1), "desert source palette preserved")
	doc.layer_mode["land"] = "even_odd"
	_check(not MapFactory.build(doc).ok, "unimplemented polygon holes fail closed")
	print("[Volume map] pass=%d fail=%d triangles=%d" % [_pass, _fail, packet.triangles])
	return _fail == 0


func _test_line_submission_order(actual: Array) -> void:
	var vertices: PackedVector3Array = actual[Mesh.ARRAY_VERTEX]
	var ordered := true
	for i in range(1, vertices.size()):
		ordered = ordered and vertices[i].y >= vertices[i - 1].y
	_check(ordered, "actual transparent route batch submits shoulders before cores and sleepers before rails")
	var records: Array[Dictionary] = []
	for i in 6:
		records.append({"points": PackedVector2Array([Vector2(-20, i), Vector2(20, i)]),
			"width": 3.0 + i, "height": [0.55, 0.45, 0.30, 0.20, 0.15, 0.20][i],
			"color": Color(float(i) / 6.0, 0.3, 0.4), "rail_lod": float(i % 3)})
	var before := JSON.stringify(records)
	var built := MapFactory._line_mesh(records).surface_get_arrays(0)
	var expected_vertices := PackedVector3Array()
	var expected_uvs := PackedVector2Array()
	var expected_colors := PackedColorArray()
	var expected_features := PackedVector2Array()
	for index in [4, 3, 5, 2, 1, 0]:
		var one: Array[Dictionary] = [records[index]]
		var source := MapFactory._line_mesh(one).surface_get_arrays(0)
		expected_vertices.append_array(source[Mesh.ARRAY_VERTEX])
		expected_uvs.append_array(source[Mesh.ARRAY_TEX_UV])
		expected_colors.append_array(source[Mesh.ARRAY_COLOR])
		expected_features.append_array(source[Mesh.ARRAY_TEX_UV2])
	_check(built[Mesh.ARRAY_VERTEX] == expected_vertices and built[Mesh.ARRAY_TEX_UV] == expected_uvs
		and built[Mesh.ARRAY_COLOR] == expected_colors and built[Mesh.ARRAY_TEX_UV2] == expected_features,
		"layer ordering preserves every packed vertex UV feature and colour with stable equal-height ordering")
	_check(JSON.stringify(records) == before, "line ordering never mutates caller records")


func _test_rail_lod(doc: MapDocument) -> void:
	var packet := MapFactory.build(doc, true, true)
	var arrays: Array = packet.line_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var features: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var counts := {0: 0, 1: 0, 2: 0}
	var valid := features.size() == vertices.size()
	for i in features.size():
		var feature := int(features[i].x)
		valid = valid and counts.has(feature) and features[i].y == 0.0
		counts[feature] = int(counts.get(feature, 0)) + 1
		if feature == 1:
			valid = valid and is_equal_approx(vertices[i].y, 0.30)
		elif feature == 2:
			valid = valid and (is_equal_approx(vertices[i].y, 0.45) or is_equal_approx(vertices[i].y, 0.55))
	var base_vertices := 0
	var detail_vertices := 0
	for railway: Dictionary in doc.railways:
		var points := Geometry.points_from(railway.points)
		base_vertices += (points.size() - 1) * 6
		detail_vertices += ((points.size() - 1) * 2 + MapFactory.sleeper_poses(points).size()) * 6
	_check(valid and counts[0] > 0 and counts[1] == base_vertices and counts[2] == detail_vertices,
		"rail LOD tags cover every base rail and sleeper vertex without tagging ordinary routes")
	for tactical in [false, true]:
		packet.tactical_style = tactical
		var instance := MeshInstance3D.new()
		MapFactory.configure_instance(instance, packet, Geometry.material())
		var material := instance.get_node("CrispRouteNetwork").material_override as ShaderMaterial
		_check(material.get_shader_parameter("rail_lod_enabled") == tactical,
			"rail LOD follows the actual tactical material and source fallback")
		_check(material.get_shader_parameter("route_coverage_enabled") == tactical,
			"rotation-neutral route coverage follows tactical style and keeps source fallback unchanged")
		instance.free()
	packet.satellite_ground = false
	var flat_instance := MeshInstance3D.new()
	MapFactory.configure_instance(flat_instance, packet, Geometry.material())
	_check(flat_instance.get_node("CrispRouteNetwork").material_override.get_shader_parameter("route_coverage_enabled") == false,
		"non-satellite map keeps original coverage even with a tactical packet tag")
	flat_instance.free()


func _test_industrial_clearance(doc: MapDocument, railway: PackedVector2Array) -> void:
	var corridors: Array[PackedVector2Array] = []
	var sides := MapFactory.stroke_edges(railway, 44.0)
	for i in range(railway.size() - 1):
		corridors.append(PackedVector2Array([sides[0][i], sides[0][i + 1], sides[1][i + 1], sides[1][i]]))
	var clear := true
	for building: Dictionary in doc.buildings:
		var pad := Buildings.scaled_polygon(Geometry.points_from(building.footprint), 1.14)
		for corridor in corridors:
			clear = clear and Geometry2D.intersect_polygons(pad, corridor).is_empty()
	_check(clear, "all 15 source buildings and pads clear the rail bed plus 12px margin")
	var moved := Geometry.points_from(doc.buildings[10].footprint)
	_check(Buildings.frame(moved).center.distance_to(Vector2(5100, 20)) < 0.001,
		"only approved source tower anchor moves 220px west; renderer reads this source")
	var site_clear := true
	var moved_pad := Buildings.scaled_polygon(moved, 1.14)
	for index in doc.buildings.size():
		if index != 10:
			var other := Buildings.scaled_polygon(Geometry.points_from(doc.buildings[index].footprint), 1.14)
			site_clear = site_clear and Geometry2D.intersect_polygons(moved_pad, other).is_empty()
	for airport: Dictionary in doc.airports:
		site_clear = site_clear and Geometry2D.intersect_polygons(moved_pad, MapFactory.airport_polygon(airport)).is_empty()
	for road: Dictionary in doc.roads:
		var road_points := Geometry.points_from(road.points)
		var margin: float = 67.0 + float(MapFactory.ROAD_WIDTHS[road.width_class]) * 0.5
		for i in range(road_points.size() - 1):
			var closest := Geometry2D.get_closest_point_to_segment(Vector2(5100, 20), road_points[i], road_points[i + 1])
			site_clear = site_clear and closest.distance_to(Vector2(5100, 20)) > margin
	_check(site_clear, "relocated pad avoids all source roads airports and other building pads")
	var old := PackedVector2Array()
	for point in moved:
		old.append(point + Vector2(220, 0))
	var old_collides := false
	for corridor in corridors:
		old_collides = old_collides or not Geometry2D.intersect_polygons(old, corridor).is_empty()
	_check(old_collides, "counterexample catches original tower intersecting the actual railway")
	var relief: RefCounted = load("res://scripts/experiments/volume_desert_relief.gd").new()
	var flat: bool = relief.archive != null and relief.archive.is_current()
	# 整片新底座采样，不只测中心；已有大范围铁路平区覆盖该小幅迁移。
	for x in range(5060, 5141, 4):
		for y in range(-20, 61, 4):
			flat = flat and absf(relief.height_at(Vector2(x, y))) < 0.01
	_check(flat, "existing prebuilt terrain is flat across the whole relocated pad")
	var decoration_clear := true
	for outcrop: Array in relief.data.outcrops:
		decoration_clear = decoration_clear and Vector2(outcrop[0], outcrop[1]).distance_to(Vector2(5100, 20)) \
			> maxf(float(outcrop[3]), float(outcrop[4])) * 2.0 + 55.0
	for plant: Array in relief.data.vegetation:
		decoration_clear = decoration_clear and Vector2(plant[0], plant[1]).distance_to(Vector2(5100, 20)) \
			> float(plant[3]) * 52.0 + 55.0
	_check(decoration_clear, "relocated source pad stays outside cached rock and scrub bounds")
	for index in 3:
		var building: Dictionary = doc.buildings[index]
		var footprint := Geometry.points_from(building.footprint)
		var height := float(building.h_m) * CombatUnit.PIXELS_PER_METER
		var fixtures := Geometry.new()
		Buildings.industrial_roof_details(fixtures, footprint, height)
		var f := Buildings.frame(footprint)
		var panel_count := clampi(roundi(float(f.length) / 18.0), 6, 12)
		var valid := fixtures._vertices.size() == 3 * (98 + panel_count * 4)
		valid = valid and fixtures._vertices.size() <= 438
		for point: Vector3 in fixtures._vertices:
			var local := Vector2(point.x, point.z) - Vector2(f.center)
			if point.y > 2.0:
				var in_roof := absf(local.dot(f.direction)) <= float(f.length) * 0.5 + 0.001 \
					and absf(local.dot(f.side)) <= float(f.width) * 0.5 + 0.001
				var in_dock := absf(local.dot(f.direction)) <= float(f.length) * 0.15 + 0.001 \
					and local.dot(f.side) >= float(f.width) * 0.5 - 0.001 \
					and local.dot(f.side) <= float(f.width) * 0.5 + 14.001 \
					and point.y <= height * 0.55 + 0.001
				valid = valid and (in_roof or in_dock)
		_check(valid, "warehouse %d: roof equipment follows its own footprint and keeps fixed geometry budget" % index)
		var on_surface := true
		for vertex in panel_count * 12:
			var point: Vector3 = fixtures._vertices[vertex]
			var across := (Vector2(point.x, point.z) - Vector2(f.center)).dot(f.side)
			var expected := height * (1.0 - 0.56 * absf(across) / float(f.width)) + 0.02
			on_surface = on_surface and absf(point.y - expected) < 0.001
		_check(on_surface, "warehouse %d: every panel vertex follows the actual roof slope without floating" % index)
		var repeat := Geometry.new()
		Buildings.industrial_roof_details(repeat, footprint, height)
		_check(fixtures._vertices == repeat._vertices and fixtures._colors == repeat._colors,
			"warehouse %d: panel tones and fittings are deterministic without combat RNG" % index)


func _test_airport_services(runway: PackedVector2Array, actual_mesh: ArrayMesh) -> void:
	var surfaces := MapFactory.airport_service_surfaces(runway)
	var linked := {0: true}
	for _step in surfaces.size():
		for a in surfaces.size():
			for b in surfaces.size():
				if linked.has(a) and not Geometry2D.intersect_polygons(surfaces[a].footprint, surfaces[b].footprint).is_empty():
					linked[b] = true
	_check(surfaces.size() == 5 and linked.size() == surfaces.size(), "airport service pads and T-junction all connect to original apron")
	var supported := true
	var road_clear := true
	for detail: Dictionary in Buildings.airport_details(runway):
		road_clear = road_clear and Geometry2D.intersect_polygons(surfaces[-1].footprint, detail.footprint).is_empty()
		for point: Vector2 in detail.footprint:
			var on_pad := false
			for surface: Dictionary in surfaces:
				on_pad = on_pad or Geometry2D.is_point_in_polygon(point, surface.footprint)
			supported = supported and on_pad
	_check(supported and road_clear, "all seven airport structures have full pad support and the service road crosses none")
	var actual := {}
	for point: Vector3 in actual_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		actual[point] = true
	var sample := Geometry.new()
	var clear := true
	var terrain_clear := true
	var relief := preload("res://scripts/experiments/volume_desert_relief.gd").new()
	for surface: Dictionary in surfaces:
		MapFactory.face(sample, surface.footprint, surface.height, Color.WHITE)
		clear = clear and Geometry2D.intersect_polygons(runway, surface.footprint).is_empty()
		var points: PackedVector2Array = surface.footprint
		for i in points.size():
			for step in 17:
				var point := points[i].lerp(points[(i + 1) % points.size()], step / 16.0)
				terrain_clear = terrain_clear and relief.height_at(point) - 0.6 < float(surface.height)
	var submitted := true
	for point: Vector3 in sample._vertices:
		submitted = submitted and actual.has(point)
	_check(clear and terrain_clear, "actual airport services clear the runway and cached native terrain along every edge")
	_check(sample._vertices.size() == 42 and submitted, "all 14 airport surface triangles are present in the actual static map mesh")


func _test_road_joins(doc: MapDocument) -> void:
	var previous_style := OS.get_environment("AGL_DESERT_STYLE")
	OS.set_environment("AGL_DESERT_STYLE", "tactical")
	var before := JSON.stringify(doc.to_json_dict())
	var joined := MapFactory.build(doc, true, true)
	var original := MapFactory.build(doc, true, true, false)
	var valid: bool = joined.road_join_count == 2 and original.road_join_count == 0
	var surface_clear := true
	var covered := 0
	var relief := preload("res://scripts/experiments/volume_desert_relief.gd").new()
	var vertices: PackedVector3Array = joined.line_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var old_vertices: PackedVector3Array = original.line_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var original_gap_covered := false
	for index: int in [2, 9]:
		var points := MapFactory.road_presentation_points(doc, index)
		var source := Geometry.points_from(doc.roads[index].points)
		var target := Geometry.points_from(doc.roads[0 if index == 2 else 2].points)
		valid = valid and points.size() == source.size() + 1 and points.slice(1) == source
		valid = valid and points[0].distance_to(Geometry2D.get_closest_point_to_segment(points[0], target[0], target[1])) < 0.005
		valid = valid and points[0].distance_to(source[0]) < 160.0
		valid = valid and (source[0] - source[1]).normalized().dot((points[0] - source[0]).normalized()) > 0.99999
		var midpoint := points[0].lerp(source[0], 0.5)
		for j in range(0, old_vertices.size(), 3):
			if absf(old_vertices[j].y - 0.2) < 0.001:
				var triangle := PackedVector2Array([Vector2(old_vertices[j].x, old_vertices[j].z), Vector2(old_vertices[j+1].x, old_vertices[j+1].z), Vector2(old_vertices[j+2].x, old_vertices[j+2].z)])
				original_gap_covered = original_gap_covered or Geometry2D.is_point_in_polygon(midpoint, triangle)
		print("[Road display join] index=", index, " length=", points[0].distance_to(source[0]), " point=", points[0])
		for i in 21:
			var p := points[0].lerp(source[0], float(i) / 20.0)
			surface_clear = surface_clear and absf(relief.height_at(p)) < 0.01
			var found := false
			for j in range(0, vertices.size(), 3):
				if absf(vertices[j].y - 0.2) > 0.001:
					continue
				var triangle := PackedVector2Array([Vector2(vertices[j].x, vertices[j].z), Vector2(vertices[j+1].x, vertices[j+1].z), Vector2(vertices[j+2].x, vertices[j+2].z)])
				if Geometry2D.is_point_in_polygon(p, triangle):
					found = true
					break
			covered += int(found)
	_check(valid and joined.triangles == original.triangles + 8 and joined.ok, "two reviewed display gaps extend tangentially without moving any source point; eight triangles only")
	_check(surface_clear and covered == 42, "all 42 short-join center samples are flat and covered by actual road core geometry")
	_check(not original_gap_covered, "negative control: original packed road mesh leaves both gap midpoints uncovered")
	_check(JSON.stringify(doc.to_json_dict()) == before, "display joins never modify authoritative geography")
	var changed := MapDocument.load_from("res://resources/maps/desert_railway_preview.aglmap")
	changed.roads[2].points[0][0] += 1
	_check(MapFactory.road_presentation_points(changed, 2).size() == changed.roads[2].points.size(), "changed source anchor fails closed instead of applying stale display correction")
	OS.set_environment("AGL_DESERT_STYLE", "source")
	_check(MapFactory.road_presentation_points(doc, 2) == Geometry.points_from(doc.roads[2].points), "explicit source presentation keeps original road ends")
	OS.set_environment("AGL_DESERT_STYLE", previous_style)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Volume map: " + label)
