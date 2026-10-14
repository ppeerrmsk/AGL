extends RefCounted
const Selection := preload("res://scripts/tests/tokyo_residential_selection.gd")
const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")


static func checks() -> bool:
	var layout := preload("res://scripts/tests/export_tokyo_full_grid_layout.gd")
	var precise_values := {"margin":36.160000000000004,"integer":9007199254740993}
	if var_to_bytes(bytes_to_var(var_to_bytes(precise_values)))!=var_to_bytes(precise_values):
		return false
	var layout_cells: Array = []
	for n in 16:
		layout_cells.append({"id":n,"bounds":Rect2((n%4)*2,(n/4)*2,2,2)})
	if not layout.partition_valid(Rect2(0,0,8,8),layout_cells) or layout.partition_valid(Rect2(0,0,8,8),[]):
		return false
	var changed_layout := layout_cells.duplicate(true)
	changed_layout[1].bounds=changed_layout[0].bounds
	if layout.partition_valid(Rect2(0,0,8,8),changed_layout):
		return false
	changed_layout=layout_cells.duplicate(true)
	changed_layout[0].bounds=Rect2(-1,0,2,2)
	if layout.partition_valid(Rect2(0,0,8,8),changed_layout):
		return false
	changed_layout=layout_cells.duplicate(true)
	changed_layout[0].bounds=Rect2(0,0,1,2)
	if layout.partition_valid(Rect2(0,0,8,8),changed_layout):
		return false
	var exact_rect := Rect2(-16300.125,-15700.5,714.0625,735.03125)
	var exact_values: Array = JSON.parse_string(JSON.stringify(layout.rectangle(exact_rect),"",true,true))
	if Rect2(exact_values[0],exact_values[1],exact_values[2],exact_values[3])!=exact_rect:
		return false
	var preview := preload("res://scripts/tests/tokyo_residential_preview.gd")
	var empty_payload := preview.export_payload(ArrayMesh.new())
	var native := preload("res://scripts/tests/build_tokyo_northwest_blocks.gd")
	var passthrough := {"passthrough":true,"original_components":0,"variants":[{"blocks":[],"parts":0,"roof_triangles":0,"wall_triangles":0}]}
	if not native.valid_passthrough(passthrough,[],0,0,0) or native.valid_passthrough(passthrough,[[1]],0,0,0) or native.valid_passthrough(passthrough,[],1,0,0) or native.valid_passthrough(passthrough,[],0,1,0) or native.valid_passthrough(passthrough,[],0,0,1) or native.valid_passthrough({},[],0,0,0):
		return false
	if empty_payload.size()!=2 or not empty_payload.positions.is_empty() or not empty_payload.attributes.is_empty() or not preview.export_payload(null).is_empty():
		return false
	if preview.export_northwest("", "", -1) != 1 or preview.export_northwest("", "", 2, true) != 1:
		return false
	if preview.northwest_matrix("", "") != 1 or preload("res://scripts/tests/build_tokyo_northwest_blocks.gd").run("", "") != 1:
		return false
	var shapes: Array[PackedVector2Array] = [PackedVector2Array([Vector2(-1,-1),Vector2(3,-1),Vector2(3,3),Vector2(-1,3)])]
	var region := Rect2(-2,-2,6,6)
	var indexed_shapes: Array[PackedVector2Array] = shapes.duplicate()
	indexed_shapes.append(PackedVector2Array([Vector2(-64,-32),Vector2(-32,-32),Vector2(-32,0),Vector2(-64,0)]))
	var grid := Selection.index_shapes(indexed_shapes)
	for y in range(-65,66):
		for x in range(-80,81):
			var point := Vector2(x,y)
			if Selection.inside(point,indexed_shapes)!=Selection.indexed_inside(point,grid):
				return false
	for point: Vector2 in [Vector2(-32,0),Vector2(-32.000005,0),Vector2(-31.999995,0),Vector2(-32.0001,0),Vector2(3.000005,1)]:
		if Selection.inside(point,indexed_shapes)!=Selection.indexed_inside(point,grid):
			return false
	var builder := Factory.new()
	# 屋顶和墙面顶点索引不同，但XYZ共享；必须整组选择。
	builder.triangle(Vector3(0,3,0),Vector3(0,3,2),Vector3(2,3,0),Color.WHITE)
	builder.triangle(Vector3(0,3,0),Vector3(0,0,0),Vector3(0,3,2),Color.WHITE)
	builder.triangle(Vector3(10,3,0),Vector3(10,3,2),Vector3(12,3,0),Color.WHITE)
	var exported := preview.export_payload(builder.mesh())
	if exported.is_empty() or exported.positions.size()!=108 or exported.attributes.size()!=360:
		return false
	var arrays := builder.mesh().surface_get_arrays(0)
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([2,1,0,5,4,3,8,7,6])
	var indexed := ArrayMesh.new()
	indexed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var indexed_payload := preview.export_payload(indexed)
	if indexed_payload.is_empty() or indexed_payload.positions.to_float32_array().slice(0,3)!=PackedFloat32Array([0,3,2]) or indexed_payload.attributes.size()!=360:
		return false
	arrays[Mesh.ARRAY_NORMAL]=null
	var missing := ArrayMesh.new()
	missing.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	if not preview.export_payload(missing).is_empty():
		return false
	var result := Selection.partition(builder.mesh(),shapes,region)
	if result.is_empty() or result.groups!=2 or result.selected!=1 or result.removed_faces!=2:
		return false
	var crossing := Selection.partition(builder.mesh(),shapes,Rect2(-1,-1,2,2))
	if crossing.is_empty() or crossing.selected!=0:
		return false
	builder.triangle(Vector3(0,3,0),Vector3(0,8,0),Vector3(0,8,2),Color.WHITE)
	var high := Selection.partition(builder.mesh(),shapes,region)
	if high.is_empty() or high.selected!=0:
		return false
	var empty := Selection.partition(ArrayMesh.new(),shapes,region)
	return not empty.is_empty() and empty.groups==0 and empty.selected==0 and empty.removed_faces==0 and empty.kept.get_surface_count()==0 and empty.removed.get_surface_count()==0 and Selection.partition(builder.mesh(),[],region).is_empty() and Selection.partition(ArrayMesh.new(),[],region).is_empty()
