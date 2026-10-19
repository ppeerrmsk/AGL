extends RefCounted
const Factory := preload("res://scripts/experiments/volume_map_factory.gd")
const Relief := preload("res://scripts/experiments/volume_desert_relief.gd")
var _pass := 0
var _fail := 0


func run(doc: MapDocument) -> bool:
	var previous := OS.get_environment("AGL_DESERT_STYLE")
	OS.set_environment("AGL_DESERT_STYLE", "tactical")
	var before := JSON.stringify(doc.to_json_dict())
	var old := Factory.build(doc, true, true, true, false)
	var actual := Factory.build(doc, true, true)
	print("[Rail crossing budget] before=%d after=%d cap=%d" % [old.triangles, actual.triangles, Factory.TRIANGLE_BUDGET])
	_check(actual.ok and actual.triangles <= Factory.TRIANGLE_BUDGET and actual.triangles == old.triangles + 16,
		"sixteen crossing triangles fit the unchanged 12000 budget")
	_check(actual.crossing_surfaces.size() == 8 and old.crossing_surfaces.is_empty(), "four reviewed crossings each have shoulder and core")
	var old_arrays: Array = old.line_mesh.surface_get_arrays(0)
	var arrays: Array = actual.line_mesh.surface_get_arrays(0)
	var indices: Array[int] = [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]
	var retained := {}
	for channel in indices:
		retained[channel] = []
	var patch_vertices := 0
	var ordered := true
	var valid := true
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var previous_layer := -INF
	for i in vertices.size():
		# 补面内部UV唯一为0.5，不能再用实际高度识别提交层级。
		var patch: bool = arrays[Mesh.ARRAY_TEX_UV][i] == Vector2(0,0.5)
		var layer: float = vertices[i].y
		if patch:
			patch_vertices += 1
			valid = valid and arrays[Mesh.ARRAY_TEX_UV][i] == Vector2(0,0.5) and arrays[Mesh.ARRAY_TEX_UV2][i] == Vector2.ZERO
			var shoulder: bool = arrays[Mesh.ARRAY_COLOR][i] == Color("73796c")
			layer = 0.49 if shoulder else 0.50
			valid = valid and is_equal_approx(vertices[i].y, 0.30)
			valid = valid and (shoulder or arrays[Mesh.ARRAY_COLOR][i] == Color("555c59"))
		else:
			for channel in indices:
				retained[channel].append(arrays[channel][i])
		ordered = ordered and layer >= previous_layer
		previous_layer = layer
	_check(valid and patch_vertices == 48 and ordered, "coplanar patch colors/UVs keep separate stable submission order below rails")
	for channel in indices:
		_check(retained[channel] == Array(old_arrays[channel]), "every original route channel is unchanged: %d" % channel)
	var relief := Relief.new()
	var counts := {0:0,1:0,5:0,6:0}
	var geometry_valid := true
	var terrain_valid := true
	var projection_valid := true
	for surface: Dictionary in actual.crossing_surfaces:
		counts[int(surface.road_index)] += 1
		var mesh: ArrayMesh = Factory._line_mesh([surface])
		var points: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for point: Vector3 in points:
			# 任意斜视方向中，补面边缘与路基上的同XZ必须保持同一投影。
			for angle: float in [0.0,0.2443461,1.5707963]:
				var canvas := Transform2D(angle,Vector2.ZERO)
				var basis := preload("res://scripts/experiments/volume_projection.gd")
				var transform := basis.camera_basis(canvas,basis.DESERT_TILT).inverse() * basis.ground_basis(canvas,basis.DESERT_TILT)
				var projected: Vector3 = transform * point
				var reference: Vector3 = transform * Vector3(point.x,0.30,point.z)
				projection_valid = projection_valid and Vector2(projected.x,projected.y).distance_to(Vector2(reference.x,reference.y)) < 0.00001
		for i in range(0, points.size(), 3):
			var a := Vector2(points[i].x,points[i].z)
			var b := Vector2(points[i+1].x,points[i+1].z)
			var c := Vector2(points[i+2].x,points[i+2].z)
			geometry_valid = geometry_valid and (b-a).cross(c-a) > 0.0
			for point: Vector2 in [a,b,c,(a+b+c)/3.0]:
				geometry_valid = geometry_valid and _inside(point,surface.road_polygon) and _inside(point,surface.rail_polygon)
				terrain_valid = terrain_valid and absf(relief.height_at(point)) < 0.01
		geometry_valid = geometry_valid and not _inside(surface.site+Vector2(1000,0),surface.rail_polygon)
	_check(geometry_valid and counts == {0:2,1:2,5:2,6:2}, "every actual face remains inside both corridors; outside negative control is rejected")
	_check(terrain_valid, "crossing vertices and face interiors remain above original cached flat terrain")
	_check(projection_valid, "crossing and rail-bed boundaries stay coplanar under three view rotations")
	_check(JSON.stringify(doc.to_json_dict()) == before, "crossing generation never mutates gameplay geography")
	var changed := MapDocument.load_from("res://resources/maps/desert_railway_preview.aglmap")
	changed.roads[0].points[5][0] += 1
	_check(Factory.Crossings.records(changed,Factory.ROAD_WIDTHS).size() == 6, "changed source intersection fails closed independently of the other three sites")
	changed = MapDocument.load_from("res://resources/maps/desert_railway_preview.aglmap")
	changed.railways[0].points.insert(1, changed.railways[0].points[0].duplicate())
	_check(Factory.Crossings.records(changed,Factory.ROAD_WIDTHS).is_empty(), "duplicate source rail points fail closed before indexed corridor access")
	OS.set_environment("AGL_DESERT_STYLE", "source")
	_check(Factory.build(doc,true,true).crossing_surfaces.is_empty(), "explicit source fallback keeps original presentation")
	OS.set_environment("AGL_DESERT_STYLE", previous)
	print("[Rail crossings] pass=%d fail=%d" % [_pass,_fail])
	return _fail == 0


func _inside(point: Vector2, polygon: PackedVector2Array) -> bool:
	var positive := false
	var negative := false
	for i in polygon.size():
		var edge := polygon[(i+1)%polygon.size()]-polygon[i]
		var side := edge.cross(point-polygon[i])/maxf(edge.length(),0.00001)
		positive = positive or side > 0.002
		negative = negative or side < -0.002
	return not (positive and negative)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Rail crossing: " + label)
