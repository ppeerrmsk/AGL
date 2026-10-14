extends RefCounted
const Layout := preload("res://scripts/experiments/volume_district_layout.gd")
const Buildings := preload("res://scripts/experiments/volume_building_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
var _pass := 0
var _fail := 0


func run(doc: MapDocument, districts: Array[Dictionary], widths: Dictionary) -> bool:
	_check(districts.size() == 3, "all three source urban regions represented")
	_check(JSON.stringify(districts) == JSON.stringify(Layout.layout(doc, widths)), "layout deterministic without random state")
	var all_plots: Array[Dictionary] = []
	for district in districts:
		var index: int = district.source_urban_index
		var region: PackedVector2Array = doc.layer_polygons.urban[index]
		var offices := 0
		var workshops := 0
		var valid := true
		for plot: Dictionary in district.plots:
			offices += int(plot.kind == "office")
			workshops += int(plot.kind == "warehouse")
			var footprint: PackedVector2Array = plot.footprint
			valid = valid and Geometry2D.clip_polygons(footprint, region).is_empty()
			var center: Vector2 = Buildings.frame(footprint).center
			var radius := center.distance_to(footprint[0])
			for road: Dictionary in doc.roads + doc.railways:
				var points := Geometry.points_from(road.points)
				var clearance := 36.0 if not road.has("width_class") else float(widths[road.width_class]) * 0.5 + 12.0
				for i in range(points.size() - 1):
					valid = valid and center.distance_to(Geometry2D.get_closest_point_to_segment(center, points[i], points[i + 1])) >= radius + clearance - 0.01
			for street: PackedVector2Array in district.streets:
				valid = valid and center.distance_to(Geometry2D.get_closest_point_to_segment(center, street[0], street[1])) >= radius + 16.0 - 0.01
			for existing: Dictionary in doc.buildings + doc.airports:
				var existing_points := Geometry.points_from(existing.get("footprint", existing.get("polygon", [])))
				valid = valid and Geometry2D.intersect_polygons(footprint, existing_points).is_empty()
			all_plots.append(plot)
		_check(valid, "district %d: source bounds and all road/rail/airport/building clearances" % index)
		_check(offices > 0 and workshops > 0 and offices + workshops >= 8,
			"district %d: actual offices=%d workshops=%d" % [index, offices, workshops])
		var source_connection := false
		for road: Dictionary in doc.roads:
			var points := Geometry.points_from(road.points)
			for i in range(points.size() - 1):
				source_connection = source_connection or Vector2(district.source_road_point).distance_to(
					Geometry2D.get_closest_point_to_segment(district.source_road_point, points[i], points[i + 1])) < 0.01
		_check(source_connection and district.streets.size() >= 2, "district %d: access connects to actual source road" % index)
		var railway_crossing := false
		for street: PackedVector2Array in district.streets:
			for rail: Dictionary in doc.railways:
				var points := Geometry.points_from(rail.points)
				for i in range(points.size() - 1):
					railway_crossing = railway_crossing or Geometry2D.segment_intersects_segment(street[0], street[1], points[i], points[i + 1]) != null
		_check(not railway_crossing, "district %d: service roads never cross the train route" % index)
		var driveways_valid: bool = not district.driveways.is_empty()
		for driveway: PackedVector2Array in district.driveways:
			var connected := false
			for street: PackedVector2Array in district.streets:
				connected = connected or driveway[1].distance_to(Geometry2D.get_closest_point_to_segment(
					driveway[1], street[0], street[1])) < 0.01
			driveways_valid = driveways_valid and connected
			for plot: Dictionary in district.plots:
				if Geometry2D.is_point_in_polygon(driveway[0], plot.footprint):
					continue
				var outline: PackedVector2Array = plot.footprint
				for edge in outline.size():
					driveways_valid = driveways_valid and Geometry2D.segment_intersects_segment(
						driveway[0], driveway[1], outline[edge], outline[(edge + 1) % outline.size()]) == null
		_check(driveways_valid, "district %d: %d driveways connect to streets without crossing other buildings" % [index, district.driveways.size()])
	var no_overlap := true
	for i in all_plots.size():
		for j in range(i + 1, all_plots.size()):
			no_overlap = no_overlap and Geometry2D.intersect_polygons(all_plots[i].footprint, all_plots[j].footprint).is_empty()
	_check(no_overlap, "all district building footprints are mutually disjoint")
	_check(not Layout._street_clear(PackedVector2Array([Vector2(-100, 0), Vector2(100, 0)]),
		[{"a": Vector2(0, -100), "b": Vector2(0, 100), "clearance": 36.0}], []),
		"a proposed road crossing the actual reserved rail corridor is rejected")
	print("[Volume districts] pass=%d fail=%d buildings=%d" % [_pass, _fail, all_plots.size()])
	return _fail == 0


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("[District] PASS " + label)
	else:
		_fail += 1
		push_error("District: " + label)
