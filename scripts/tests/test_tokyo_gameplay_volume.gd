extends RefCounted
const Factory := preload("res://scripts/experiments/tokyo_gameplay_volume.gd")
const Difference := preload("res://scripts/experiments/tokyo_roof_difference.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var packed: Dictionary = load("res://scripts/tests/test_tokyo_packed_mesh_join.gd").new().run()
	_pass += int(packed.pass)
	_fail += int(packed.fail)
	_test_difference()
	_check(load("res://scripts/tests/export_tokyo_canonical_roofs.gd").can_instantiate(), "camera independent source exporter compiles")
	_check(load("res://scripts/tests/build_tokyo_canonical_roofs.gd").can_instantiate(), "canonical native builder compiles")
	_check(load("res://scripts/tests/tokyo_gameplay_review.gd").can_instantiate(), "native regional review compiles")
	_check(load("res://scripts/tests/export_tokyo_gameplay_roofs.gd").can_instantiate(), "native source exporter compiles")
	_check(load("res://scripts/tests/bake_tokyo_shared_roofs.gd").can_instantiate(), "shared roof offline baker compiles")
	_check(load("res://scripts/tests/tokyo_shared_roof_review.gd").can_instantiate(), "saved shared roof review compiles")
	_check(load("res://scripts/tests/audit_tokyo_shared_roof_bundle.gd").can_instantiate(), "saved shared roof audit compiles")
	for points: PackedVector2Array in [PackedVector2Array([Vector2(0,0), Vector2(20,0), Vector2(20,10), Vector2(0,10)]),
		PackedVector2Array([Vector2(0,0), Vector2(0,10), Vector2(8,10), Vector2(8,4), Vector2(20,4), Vector2(20,0)]),
		PackedVector2Array([Vector2(-6000,-1100), Vector2(-6000,-1100), Vector2(-5970,-1100), Vector2(-5970,-1080), Vector2(-6000,-1080)])]:
		var raw: Array = []
		for p: Vector2 in points:
			raw.append([p.x, p.y])
		var entry: Dictionary = BuildingRenderer._build_entry_static({"footprint": raw, "max_real_h": 295.8})
		_check(not entry.is_empty(), "fixture accepted by real collision cache builder")
		var before := var_to_bytes(entry)
		var mesh := Factory.build(entry)
		_check(before == var_to_bytes(entry), "native conversion cannot mutate collision authority")
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		_check(is_equal_approx(mesh.get_aabb().end.y, 147.9), "meters use the exact gameplay world scale")
		_check(mesh.get_aabb().position.y == 0.0, "grounded at the authoritative footprint")
		var roof_area := 0.0
		for n in range(0, vertices.size(), 3):
			var normal := normals[n]
			_check(normal.is_finite() and normal.length() > 0.99, "finite nondegenerate native normal")
			if normal.y > 0.99:
				roof_area += (vertices[n + 1] - vertices[n]).cross(vertices[n + 2] - vertices[n]).length() * 0.5
			else:
				var midpoint := (vertices[n] + vertices[n + 1] + vertices[n + 2]) / 3.0
				_check(not Geometry2D.is_point_in_polygon(Vector2(midpoint.x + normal.x * 0.1, midpoint.z + normal.z * 0.1), points), "concave wall normal points outside")
		for p: Vector3 in vertices:
			_check(Vector2(p.x,p.z) in points and (p.y == 0.0 or is_equal_approx(p.y,147.9)), "no invented footprint or extra height")
		var area := 0.0
		for n in points.size():
			area += points[n].cross(points[(n + 1) % points.size()])
		_check(absf(roof_area - absf(area) * 0.5) < 0.01, "roof retains concave footprint area")
		var joined := Factory.joined(mesh, mesh)
		_check(joined.get_surface_count() == 2 and Factory.triangles(joined) == 2 * Factory.triangles(mesh), "all native surfaces are counted")
		_check(Factory.geometry_bytes(joined) == 2 * Factory.geometry_bytes(mesh), "copied source and addition both consume budget")
		var many := Factory.build_many([entry, entry])
		_check(many.get_surface_count() == 1 and Factory.triangles(many) == 2 * Factory.triangles(mesh), "districts merge into one surface rather than per-building draws")
	print("[Tokyo gameplay volume] pass=", _pass, " fail=", _fail)


func _test_difference() -> void:
	var triangle := PackedVector2Array([Vector2(0,0),Vector2(20,0),Vector2(0,20)])
	for shift: Vector2 in [Vector2.ZERO, Vector2(-6000,-1100)]:
		var source := triangle.duplicate()
		for n in source.size():
			source[n] += shift
		for cutter: PackedVector2Array in [source, PackedVector2Array([Vector2(0,0)+shift,Vector2(10,0)+shift,Vector2(0,10)+shift]),
			PackedVector2Array([Vector2(5,-10)+shift,Vector2(5,30)+shift,Vector2(30,0)+shift]),
			PackedVector2Array([Vector2(30,30)+shift,Vector2(30,40)+shift,Vector2(40,30)+shift])]:
			for reverse in [false,true]:
				var cut := cutter.duplicate()
				if reverse:
					cut.reverse()
				var pieces := Difference.subtract_all(source, [cut,cut])
				var kept := 0.0
				for piece: PackedVector2Array in pieces:
					kept += Difference.area(piece)
					for overlap: PackedVector2Array in Geometry2D.intersect_polygons(piece,cut):
						_check(Difference.area(overlap) < 0.01, "difference cannot retain positive-area coplanar overlap")
				var removed := 0.0
				for overlap: PackedVector2Array in Geometry2D.intersect_polygons(source,cut):
					removed += Difference.area(overlap)
				_check(absf(kept + removed - Difference.area(source)) < 0.02, "difference plus original native roof exactly covers source footprint")


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Tokyo gameplay volume: " + label)
