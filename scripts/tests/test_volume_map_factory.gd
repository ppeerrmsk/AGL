extends RefCounted
const MapFactory := preload("res://scripts/experiments/volume_map_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
var _pass := 0
var _fail := 0


func run() -> bool:
	var doc := MapDocument.load_from("res://resources/maps/desert_railway_preview.aglmap")
	var before := JSON.stringify(doc.to_json_dict())
	var packet := MapFactory.build(doc)
	_check(packet.get("ok", false), "desert builds within triangle budget")
	_check(JSON.stringify(doc.to_json_dict()) == before, "map factory never mutates geography")
	var mesh: ArrayMesh = packet.mesh
	_check(mesh.get_surface_count() == 1, "one static surface/material")
	# 铁路有正式界外进场段；整包 AABB 会大于地表，不能用它断言地图被放大。
	_check(packet.extent_px == doc.world_size_m * CombatUnit.PIXELS_PER_METER,
		"ground extent reads document metres and shared conversion")
	_check(packet.buildings == doc.buildings.size() and packet.airports == 3 and packet.roads == 12,
		"all source buildings airports and roads included")
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
	_check(mesh.get_aabb().end.y <= source_max_height + 0.1, "roof shapes preserve source height ceiling")
	var points := Geometry.points_from(doc.railways[0].points)
	_check(points == ArmoredTrainBoss.train_route(), "railway uses actual train route without offset")
	var edges := MapFactory.stroke_edges(points, 10.0)
	var centered := edges[0].size() == points.size()
	for i in points.size():
		centered = centered and ((edges[0][i] + edges[1][i]) * 0.5).distance_to(points[i]) < 0.01
	_check(centered, "every shared rail joint remains centred on source route")
	var bend := PackedVector2Array([Vector2(0, 0), Vector2(60, 0), Vector2(60, 60)])
	var bent_edges := MapFactory.stroke_edges(bend, 10.0)
	_check(bent_edges[0][1].distance_to(Vector2(55, 5)) < 0.001, "90 degree rail joint has exact continuous miter")
	var sleepers := MapFactory.sleeper_poses(bend, 24.0)
	_check(sleepers.size() == 5 and sleepers[3].distance_to(Vector3(60, 24, PI * 0.5)) < 0.001,
		"sleepers retain cumulative spacing across segment boundaries")
	_check(MapFactory.stroke_edges(PackedVector2Array([Vector2.ZERO, Vector2.ZERO]), 10).is_empty(),
		"degenerate route safely skipped")
	for airport: Dictionary in doc.airports:
		_check(MapFactory.airport_polygon(airport) == Geometry.points_from(airport.polygon),
			"airport exact footprint preserved")
	var rectangle := MapFactory.airport_polygon({"center": [100, 200], "size": [20, 100], "rotation_deg": 90})
	_check(rectangle[0].distance_to(Vector2(150, 190)) < 0.001, "UGC rectangle conversion rotates about actual centre")
	_check(MapFactory.palette(doc, "land") == Color(0.48, 0.31, 0.16, 1), "desert source palette preserved")
	doc.layer_mode["land"] = "even_odd"
	_check(not MapFactory.build(doc).ok, "unimplemented polygon holes fail closed")
	print("[Volume map] pass=%d fail=%d triangles=%d" % [_pass, _fail, packet.triangles])
	return _fail == 0


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Volume map: " + label)
