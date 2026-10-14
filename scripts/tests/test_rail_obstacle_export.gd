extends RefCounted
## 当前原生铁路障碍导出反例，接入地表focused及all。


static func mesh(vertices: PackedVector3Array, indices: PackedInt32Array = PackedInt32Array()) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if not indices.is_empty():
		arrays[Mesh.ARRAY_INDEX] = indices
	var value := ArrayMesh.new()
	value.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return value


static func checks(exporter: Script) -> bool:
	if preload("res://scripts/tests/build_tokyo_boundary_catalog.gd").run("","")!=1 \
		or preload("res://scripts/tests/audit_tokyo_boundary_coverage.gd").new().run("","")!=1: return false
	if preload("res://scripts/tests/export_tokyo_boundary_layers.gd").run("","")!=1 \
		or preload("res://scripts/tests/build_tokyo_boundary_blocks.gd").run("","","","","")!=1 \
		or preload("res://scripts/tests/build_tokyo_boundary_tree.gd").run("","")!=1: return false
	if exporter.region_for_parent(11) != Rect2(-7300,-2700,1640,1000) or exporter.region_for_parent(12) != Rect2(-5660,-2700,960,1000):
		return false
	if exporter.region_for_parent(10).has_area() or exporter.region_for_parent(-1).has_area():
		return false
	var inside := PackedVector3Array([Vector3(-5200,2,-2200),Vector3(-5190,2,-2200),Vector3(-5200,2,-2190)])
	var value: Dictionary = exporter.corners(mesh(inside))
	if value.is_empty() or value.triangles != 1 or value.corners.size() != 9:
		return false
	if exporter.corners(mesh(inside),exporter.region_for_parent(11)).triangles != 0:
		return false
	var west := PackedVector3Array([Vector3(-6500,2,-2200),Vector3(-6490,2,-2200),Vector3(-6500,2,-2190)])
	if exporter.corners(mesh(west),exporter.region_for_parent(11)).triangles != 1 or exporter.corners(mesh(west)).triangles != 0:
		return false
	var indexed: Dictionary = exporter.corners(mesh(inside, PackedInt32Array([2,1,0])))
	if indexed.triangles != 1 or indexed.corners[0] != inside[2].x or indexed.corners[2] != inside[2].z:
		return false
	var outside := PackedVector3Array([Vector3(0,2,0),Vector3(10,2,0),Vector3(0,2,10)])
	if exporter.corners(mesh(outside)).triangles != 0:
		return false
	var vertical := PackedVector3Array([Vector3(-5200,0,-2200),Vector3(-5200,20,-2200),Vector3(-5190,0,-2200)])
	if exporter.corners(mesh(vertical)).triangles != 0:
		return false
	# 部分越界三角保留完整角点，下游再与区域求交，不能先按质心误删。
	var crossing := PackedVector3Array([Vector3(-5661,3,-2200),Vector3(-5659,3,-2200),Vector3(-5661,3,-2190)])
	if exporter.corners(mesh(crossing)).triangles != 1:
		return false
	if exporter.corners(ArrayMesh.new()).triangles != 0:
		return false
	var southwest := Rect2(-8290,-2690,980,980)
	var sw_points := PackedVector3Array([Vector3(-7800,3,-2200),Vector3(-7790,3,-2200),Vector3(-7800,3,-2190)])
	if exporter.corners(mesh(sw_points),southwest).triangles != 1 or exporter.corners(mesh(sw_points)).triangles != 0:
		return false
	if exporter.run("", "", 11) != 1 or exporter.run("", "", 12) != 1:
		return false
	if preload("res://scripts/tests/build_tokyo_southwest_rail_catalog.gd").new().run("", "") != 1:
		return false
	if preload("res://scripts/tests/build_tokyo_road_meshopt_catalog.gd").new().run("", "") != 1:
		return false
	if preload("res://scripts/tests/export_tokyo_batch_layers.gd").run("") != 1:
		return false
	if preload("res://scripts/tests/export_tokyo_full_tile_layers.gd").run("","","") != 1:
		return false
	if preload("res://scripts/tests/build_tokyo_batch_blocks.gd").run("") != 1:
		return false
	if preload("res://scripts/tests/build_tokyo_batch_blocks.gd").build_paths("","","","",0,{}) != 1:
		return false
	if preload("res://scripts/tests/build_tokyo_full_tile_blocks.gd").run("","","","","") != 1:
		return false
	if preload("res://scripts/tests/tokyo_residential_preview.gd").export_index("", "", 0, "") != 1:
		return false
	return true
