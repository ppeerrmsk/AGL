extends RefCounted
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
var _fail := 0
var _pass := 0


func run() -> void:
	var builder := Geometry.new()
	var triangles: Array = []
	for quad: Array in [[[0, 0], [10, 0], [7, 3], [3, 3]], [[10, 0], [10, 10], [7, 7], [7, 3]], [[10, 10], [0, 10], [3, 7], [7, 7]], [[0, 10], [0, 0], [3, 3], [3, 7]]]:
		triangles.append_array([quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]])
	var hole := PackedVector2Array([Vector2(3, 3), Vector2(7, 3), Vector2(7, 7), Vector2(3, 7)])
	Factory._add_ring_building(builder, {"kind": "urban", "height_source": "height", "min_height_m": 1.5,
		"rings": [{"outer": [[0, 0], [10, 0], [10, 10], [0, 10]], "holes": [[[3, 3], [7, 3], [7, 7], [3, 7]]], "triangles": triangles}]}, 5.0)
	var mesh: ArrayMesh = builder.mesh()
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var roof_area := 0.0
	var inner_faces := 0
	for index in range(0, points.size(), 3):
		var midpoint := (points[index] + points[index + 1] + points[index + 2]) / 3.0
		if normals[index].y > 0.9:
			_check(not Geometry2D.is_point_in_polygon(Vector2(midpoint.x, midpoint.z), hole), "roof leaves courtyard open")
			roof_area += (points[index + 1] - points[index]).cross(points[index + 2] - points[index]).length() * 0.5
		elif midpoint.x >= 3 and midpoint.x <= 7 and midpoint.z >= 3 and midpoint.z <= 7:
			var toward_hole := Vector3(5 - midpoint.x, 0, 5 - midpoint.z)
			_check(normals[index].dot(toward_hole) > 0, "inner wall faces courtyard")
			inner_faces += 1
	_check(is_equal_approx(roof_area, 84), "roof area conserves outer minus hole")
	_check(inner_faces == 8, "all four inner walls exist")
	_check(is_equal_approx(mesh.get_aabb().position.y, 0.75), "source minimum height respected")
	_check(is_equal_approx(mesh.get_aabb().end.y, 5.0), "roof does not exceed source top height")
	# 屋盖三档保持同一顶面，不把layer当高度；普通平顶房仍保留围墙。
	for tags: Dictionary in [{"building": "roof", "layer": "1"}, {"building:part": "roof"}, {"building": "residential", "roof:shape": "flat"}]:
		var open_roof: bool = tags.get("building", "") == "roof" or tags.get("building:part", "") == "roof"
		for detail in 3:
			var roof_builder := Geometry.new()
			var raw := {"source_tags": tags, "height_source": "levels", "min_height_m": 0.0,
				"rings": [{"outer": [[0, 0], [10, 0], [10, 10], [0, 10]], "holes": [[[3, 3], [7, 3], [7, 7], [3, 7]]], "triangles": triangles}]}
			var source_copy := raw.duplicate(true)
			Factory._add_ring_building(roof_builder, raw, 4.8, detail)
			var roof_mesh: ArrayMesh = roof_builder.mesh()
			var roof_arrays := roof_mesh.surface_get_arrays(0)
			var roof_points: PackedVector3Array = roof_arrays[Mesh.ARRAY_VERTEX]
			var roof_normals: PackedVector3Array = roof_arrays[Mesh.ARRAY_NORMAL]
			_check(raw == source_copy, "source payload unchanged")
			_check(roof_points.size() == (24 if open_roof or detail == 2 else 72), "open roof omits exterior and courtyard walls only")
			if open_roof:
				var area := 0.0
				for i in range(0, roof_points.size(), 3):
					_check(is_equal_approx(roof_points[i].y, 4.8) and roof_normals[i].y > 0.9, "open roof source top and upward normals preserved")
					area += (roof_points[i + 1] - roof_points[i]).cross(roof_points[i + 2] - roof_points[i]).length() * 0.5
				_check(is_equal_approx(area, 84.0), "open roof area and courtyard preserved at every detail")
	var prepared_builder := Geometry.new()
	Factory._add_ring_building(prepared_builder, {"source_tags": {"building": "roof"},
		"roof_volume": {"walls": [[0, 0, 0], [0, 4, 0], [2, 4, 0]],
		"roof": [[0, 4, 0], [2, 5, 0], [0, 4, 2]]}}, 5.0)
	var prepared_mesh: ArrayMesh = prepared_builder.mesh()
	_check(prepared_mesh.surface_get_array_len(0) == 3, "prepared roof keeps roof without automatic walls")
	_check(is_equal_approx(prepared_mesh.get_aabb().position.y, 4.0) and is_equal_approx(prepared_mesh.get_aabb().end.y, 5.0), "prepared roof slope heights remain unchanged")
	var source_path := OS.get_environment("AGL_TOKYO_OPEN_ROOF_SOURCE")
	if not source_path.is_empty():
		var expected := "4925e05d7ed2d2dcb9755eed20035416105d0da654401680e7494c6af6e87bae"
		var source_ok := FileAccess.get_sha256(source_path) == expected
		_check(source_ok, "northwest real source identity")
		if source_ok:
			var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
			var actual_count := 0
			var actual_triangles := 0
			for record: Dictionary in source.buildings:
				var tags: Dictionary = record.get("source_tags", {})
				if tags.get("building", "") != "roof" and tags.get("building:part", "") != "roof":
					continue
				actual_count += 1
				var before := record.duplicate(true)
				var top := float(record.height_m) * CombatUnit.PIXELS_PER_METER
				for detail in 3:
					var actual_builder := Geometry.new()
					Factory._add_ring_building(actual_builder, record, top, detail)
					var actual: ArrayMesh = actual_builder.mesh()
					var actual_arrays := actual.surface_get_arrays(0)
					var actual_points: PackedVector3Array = actual_arrays[Mesh.ARRAY_VERTEX]
					var actual_normals: PackedVector3Array = actual_arrays[Mesh.ARRAY_NORMAL]
					for i in actual_points.size():
						_check(is_equal_approx(actual_points[i].y, top) and actual_normals[i].y > 0.9, "actual roof source top and no vertical wall")
					actual_triangles += actual_points.size() / 3
				_check(record == before, "actual roof source unchanged")
			_check(actual_count == 17, "all seventeen source roofs exercised")
			_check(FileAccess.get_sha256(source_path) == expected, "actual source bytes unchanged")
			print("[Tokyo real roofs] count=", actual_count, " detail_levels=3 triangles_total=", actual_triangles)
	var legacy := Factory.build()
	_check(legacy.ok and legacy.source_buildings == 8683 and legacy.triangles == 130849, "R4 frozen geometry stays unchanged")
	var candidate: Resource = load("res://resources/maps/tokyo_volume_preview/region_r5b.res")
	_check(candidate != null and candidate.valid(), "compiled regional candidate loads without source JSON")
	if candidate != null:
		var packet: Dictionary = candidate.packet()
		_check(packet.source_buildings == 17077 and packet.deferred_buildings == 1 and packet.part_assembly_outlines == 31, "source records and assembly decisions survive native archive")
		_check(packet.triangles == 265848 and candidate.meshes.size() == 5, "baked mesh counts survive native archive")
	print("[Tokyo rings] pass=", _pass, " fail=", _fail)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo rings: " + label)
