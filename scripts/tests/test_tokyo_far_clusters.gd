extends RefCounted
const Far := preload("res://scripts/tests/build_tokyo_far_clusters.gd")
const Archive := preload("res://scripts/rendering/tokyo_cell_archive.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_check(Far.selected_levels("")==[1,2] and Far.selected_levels("3")==[3],"near construction requires explicit LOD3; legacy stays far only")
	_check(Far.selected_levels("5")==[5] and Far.maximum_scale(5)==5.0 and Far.maximum_scale(0)==0.0,"finest explicit candidate uses full camera scale, unsupported level refuses")
	_check(Far.selected_levels("4")==[4] and is_equal_approx(Far.maximum_scale(4),1.5552),"middle candidate uses actual LOD4 upper hysteresis scale")
	_check(Far.maximum_scale(5)==preload("res://scripts/camera_controller.gd").ZOOM_MAX,"camera maximum drift requires reauthoring finest candidate contract")
	for invalid: String in ["0","6","3,3","1,garbage","3,"]:
		_check(Far.selected_levels(invalid).is_empty(),"unsupported or duplicate construction level rejected")
	var a := record("a", 0.0)
	var b := record("b", 5.2)
	var far := Far.new()
	far._records = {"a": a, "b": b}
	var geometry := Far.Geometry.new()
	Far.Factory._add_ring_building(geometry, a, 3.2, 2)
	Far.Factory._add_ring_building(geometry, b, 3.2, 2)
	var source := Archive.new()
	source.cell_id = 8
	source.level = 1
	source.bounds = Rect2(-1, -1, 15, 7)
	source.source_ids = PackedStringArray(["a", "b"])
	var low := Far.Palette.recolor(Far.Indexed.pack(geometry.mesh()))
	source.meshes = [low, ArrayMesh.new()]
	var merged := record("a", 0.0, 10.2)
	var group := {"ids": ["a", "b"], "height_m": 6.4, "outer": merged.rings[0].outer, "triangles": merged.rings[0].triangles}
	var plan := {"groups": [group]}
	var result := far._convert(source, plan)
	var uncolored: Resource = source.duplicate(false)
	var uncolored_meshes: Array[ArrayMesh] = [geometry.mesh(), ArrayMesh.new()]
	uncolored.meshes = uncolored_meshes
	var plain := far._convert(uncolored, plan, false)
	_check(not plain.is_empty() and Far.Indexed.triangles(plain.mesh) == 2, "independent raw source conversion preserves its color path")
	_check(result.groups.size() == 1 and Far.Indexed.triangles(result.mesh) == 2, "far roof count is four to two, not invented wall savings")
	_check(Far.Indexed.triangles(source.meshes[0]) == 4 and b.rings[0].outer[0][0] == 5.2, "source geometry and records unchanged")
	plan.cost_model = "native_lod"
	group.faces_saved = 2
	_check(not far._convert(source, plan).is_empty(), "actual exported roof cost agrees with native conversion")
	group.faces_saved = 3
	_check(far._convert(source, plan).is_empty(), "wrong predicted saving fails closed")
	plan.erase("cost_model")
	group.height_m = 7.0
	result = far._convert(source, plan)
	_check(result.groups.is_empty() and Far.Indexed.triangles(result.mesh) == 4, "different original heights never merge")
	var prepared := a.duplicate(true)
	prepared.area_lod = {"1": {"rings": merged.rings}}
	_check(Far.record_for(prepared, 1, 2).rings == merged.rings, "far reference uses existing area LOD")
	_check(Far.record_for(prepared, 1, 1).rings == a.rings, "walls retain original source contour")
	_check(Far.eligible(a), "ordinary ground-based low source eligible")
	for override: Dictionary in [{"source_tags": {"building": "roof"}}, {"source_tags": {"building:part": "roof"}}, {"height_source": "height"}, {"height_m": 24.1}, {"min_height_m": 1.0}, {"is_part": true}, {"parents": ["p"]}, {"roof_volume": {}}]:
		var protected := a.duplicate(true)
		protected.merge(override, true)
		_check(not Far.eligible(protected), "marked raised or structured source stays original")
	_check(load("res://scripts/tests/tokyo_far_cluster_review.gd").can_instantiate(), "far Visual compiles")
	_check(load("res://scripts/tests/export_tokyo_far_costs.gd").can_instantiate(), "native far cost exporter compiles")
	var block := {"schema":2,"strategy":"street_blocks","profile":"blocks","max_group":32,"grid":64,"max_span":80,"max_vertices":8,"occupied_error_px":3.0,"area_error":0.60,"roads":"structural"}
	_check(Far.group_limit(block)==32,"explicit approved block contract permits larger groups")
	block.max_group=64
	_check(Far.group_limit(block)==0,"unreviewed larger cap rejected")
	_check(Far.group_limit({"schema":1,"max_group":32})==0,"legacy contract cannot silently expand")
	block.max_group=32
	block.area_error=1.0
	_check(Far.group_limit(block)==0,"unreviewed block area expansion rejected")
	for profile: String in ["mid4","mid6"]:
		var error_px := 4.0 if profile=="mid4" else 6.0
		var middle := {"schema":2,"strategy":"street_blocks","profile":profile,"max_group":48,"grid":64,"max_span":80,"max_vertices":8,"occupied_error_px":error_px,"area_error":0.80,"roads":"structural","max_scale":1.5552}
		_check(Far.group_limit(middle)==48,"explicit middle contract accepted")
		for mutation: Dictionary in [{"max_scale":0.7776},{"max_scale":5.0},{"max_scale":0.3888},{"occupied_error_px":error_px+1.0},{"max_group":64},{"area_error":1.0},{"roads":"all"}]:
			var invalid := middle.duplicate()
			invalid.merge(mutation,true)
			_check(Far.group_limit(invalid)==0,"middle contract cannot drift or reach another LOD")
	var legacy_middle := block.duplicate()
	legacy_middle.area_error=0.60
	legacy_middle.max_scale=1.5552
	_check(Far.group_limit(legacy_middle)==0,"existing blocks cannot expand into middle LOD")
	for profile: String in ["district6","district8","district12","district16","district20","district24","district20wide","district24wide"]:
		var error_px: float = {"district6":6.0,"district8":8.0,"district12":12.0,"district16":16.0,"district20":20.0,"district24":24.0,"district20wide":20.0,"district24wide":24.0}[profile]
		var district := {"schema":2,"strategy":"street_blocks","profile":profile,"max_group":48,"grid":64,"max_span":80,"max_vertices":8,"occupied_error_px":error_px,"area_error":0.80,"roads":"structural","max_scale":5.0}
		if profile.ends_with("wide"):
			district.merge({"max_group":64,"grid":96,"max_span":120,"closure_steps":4},true)
			district.min_vertices = 4
			var wrong_steps := district.duplicate()
			wrong_steps.closure_steps = 1
			_check(Far.group_limit(wrong_steps)==0,"wide multi-radius contract cannot drift to single radius")
		if profile in ["district20","district24","district20wide","district24wide"]:
			district.min_vertices = 4
			var triangle := district.duplicate()
			triangle.min_vertices = 3
			_check(Far.group_limit(triangle)==0,"new near group cannot collapse to a triangle")
			var triangle_mesh := district.duplicate(true)
			triangle_mesh.groups = [{"ids":["a","b"],"height_m":6.4,"outer":[[0,0],[4,0],[0,4]],"triangles":[[0,0],[4,0],[0,4]]}]
			_check(far._convert(source,triangle_mesh).is_empty(),"native conversion rejects three-corner group even with valid profile")
		_check(Far.group_limit(district)==(64 if profile.ends_with("wide") else 48),"explicit dense district finest contract accepted")
		for mutation: Dictionary in [{"max_scale":0.1944},{"max_scale":0.3888},{"max_scale":0.7776},{"roads":"all"},{"occupied_error_px":error_px+1.0},{"max_group":128 if profile.ends_with("wide") else 64},{"area_error":1.0}]:
			var invalid := district.duplicate()
			invalid.merge(mutation,true)
			_check(Far.group_limit(invalid)==0,"district contract drift fails closed")
	var catalog: RefCounted = load("res://scripts/tests/test_tokyo_block_catalog.gd").new()
	_check(preload("res://scripts/tests/tokyo_solid_native_mesh.gd").checks(),"current solid merge preserves source and high components")
	var near_street := {"schema":2,"strategy":"street_blocks","profile":"district24street","max_group":64,"grid":96,"max_span":120,"min_vertices":4,"max_vertices":8,"closure_steps":4,"occupied_error_px":24.0,"area_error":0.80,"roads":"structural","max_scale":5.0,"grouping":"road_components","link_gap":12.0}
	_check(Far.group_limit(near_street)==64,"near street changes grouping without relaxing existing near contract")
	var solid := near_street.duplicate(true)
	solid.merge({"profile":"street_solid","max_group":256,"grid":128,"max_span":240,"occupied_error_px":80.0,"area_error":2.0},true)
	_check(Far.group_limit(JSON.parse_string(JSON.stringify(solid)))==256,"solid street explicit JSON contract accepted")
	for mutation: Dictionary in [{"max_scale":0.7776},{"roads":"none"},{"max_group":512},{"occupied_error_px":100.0}]:
		var invalid := solid.duplicate(true)
		invalid.merge(mutation,true)
		_check(Far.group_limit(invalid)==0,"solid street drift rejected")
	var shaped_street := near_street.duplicate(true)
	shaped_street.profile="district24street45"
	shaped_street.shape_policy={"min_angle_degrees":45,"max_aspect":4,"min_edge_px":0.5}
	_check(Far.group_limit(shaped_street)==64,"named near street shape contract accepted")
	_check(Far.group_limit(JSON.parse_string(JSON.stringify(shaped_street)))==64,"shape contract survives actual JSON numeric decoding")
	for mutation: Dictionary in [{"min_angle_degrees":30,"max_aspect":4,"min_edge_px":0.5},{"min_angle_degrees":45,"max_aspect":8,"min_edge_px":0.5},{"min_angle_degrees":"45","max_aspect":4,"min_edge_px":0.5},{"min_angle_degrees":true,"max_aspect":4,"min_edge_px":0.5},{"min_angle_degrees":45,"max_aspect":4,"min_edge_px":0.5,"extra":0},{}]:
		var invalid := shaped_street.duplicate(true)
		invalid.shape_policy=mutation
		_check(Far.group_limit(invalid)==0,"shape contract drift refuses native bake")
	for mutation: Dictionary in [{"max_scale":0.3888},{"max_scale":1.5552},{"link_gap":24.0},{"grouping":"grid"},{"roads":"none"},{"max_group":96},{"occupied_error_px":25.0},{"area_error":1.0},{"min_vertices":3},{"closure_steps":1}]:
		var invalid := near_street.duplicate()
		invalid.merge(mutation,true)
		_check(Far.group_limit(invalid)==0,"near street refuses changed geometry or scale contract")
	for profile: String in ["street6","street8"]:
		var street := {"schema":2,"strategy":"street_blocks","profile":profile,"max_group":96,"grid":128,"max_span":160,"min_vertices":4,"max_vertices":8,"closure_steps":4,"occupied_error_px":6.0 if profile=="street6" else 8.0,"area_error":1.0,"roads":"structural","max_scale":0.3888,"grouping":"road_components","link_gap":12.0}
		_check(Far.group_limit(street)==96,"street adjacency contract accepted without changing source heights")
		for mutation: Dictionary in [{"max_scale":0.7776},{"max_scale":5.0},{"link_gap":24.0},{"grouping":"grid"},{"roads":"none"},{"max_group":128}]:
			var invalid := street.duplicate()
			invalid.merge(mutation,true)
			_check(Far.group_limit(invalid)==0,"street contract cannot change graph, scale or structural guards")
	for profile: String in ["far8wide","far12wide"]:
		var wide := {"schema":2,"strategy":"street_blocks","profile":profile,"max_group":96,"grid":128,"max_span":160,"min_vertices":4,"max_vertices":8,"closure_steps":4,"occupied_error_px":8.0 if profile=="far8wide" else 12.0,"area_error":1.0,"roads":"structural","max_scale":0.1944}
		_check(Far.group_limit(wide)==96,"wide far LOD1 contract accepted")
		wide.max_scale=0.3888
		_check(Far.group_limit(wide)==96,"wide far LOD2 contract accepted")
		for mutation: Dictionary in [{"max_scale":0.7776},{"max_scale":1.5552},{"max_scale":5.0},{"min_vertices":3},{"closure_steps":1},{"max_group":128},{"grid":96},{"max_span":200},{"roads":"all"}]:
			var invalid := wide.duplicate()
			invalid.merge(mutation,true)
			_check(Far.group_limit(invalid)==0,"wide far contract cannot drift or extend to middle/near")
	for profile: String in ["far4","far6"]:
		var district := {"schema":2,"strategy":"street_blocks","profile":profile,"max_group":64,"grid":96,"max_span":120,"max_vertices":8,"occupied_error_px":4.0 if profile=="far4" else 6.0,"area_error":1.0,"roads":"structural","max_scale":0.1944}
		_check(Far.group_limit(district)==64,"far district LOD1 contract accepted")
		district.max_scale=0.3888
		_check(Far.group_limit(district)==64,"far district LOD2 contract accepted")
		for mutation: Dictionary in [{"max_scale":0.7776},{"max_scale":5.0},{"max_group":128},{"roads":"all"},{"area_error":2.0}]:
			var invalid := district.duplicate()
			invalid.merge(mutation,true)
			_check(Far.group_limit(invalid)==0,"far district cannot drift or reach close range")
	catalog.run()
	_pass += catalog._pass
	_fail += catalog._fail
	var street_catalog: RefCounted = load("res://scripts/tests/test_tokyo_street_catalog.gd").new()
	street_catalog.run()
	_pass += street_catalog._pass
	_fail += street_catalog._fail
	print("[R57 far test] pass=", _pass, " fail=", _fail)


static func record(identity: String, x: float, width: float = 5.0) -> Dictionary:
	var p := [[x, 0.0], [x + width, 0.0], [x + width, 5.0], [x, 5.0]]
	return {"id": identity, "height_source": "fallback", "height_m": 6.4, "kind": "urban",
		"regional_draw_owner": "north_coast", "rings": [{"outer": p, "holes": [], "triangles": [p[0], p[1], p[2], p[0], p[2], p[3]]}]}


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] R57 " + label)
