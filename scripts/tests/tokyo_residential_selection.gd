extends RefCounted
## 原生XYZ共享角点形成组件，绝不逐面中心删除；仅离线选择。
const Read := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Subset := preload("res://scripts/tests/build_tokyo_path_lod.gd")
const Diff := preload("res://scripts/experiments/tokyo_packed_mesh_difference.gd")


static func root_of(parents: PackedInt32Array, index: int) -> int:
	while parents[index] != index:
		index=parents[index]
	return index


static func inside(point: Vector2, shapes: Array[PackedVector2Array]) -> bool:
	for shape: PackedVector2Array in shapes:
		if Geometry2D.is_point_in_polygon(point,shape):
			return true
		for i in shape.size():
			if point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point,shape[i],shape[(i+1)%shape.size()])) <= 0.0000000001:
				return true
	return false


static func partition(mesh: ArrayMesh, shapes: Array[PackedVector2Array], region: Rect2) -> Dictionary:
	# 全图海岸单元允许低层为空；空输入仍保持严格零面守恒。
	if mesh != null and mesh.get_surface_count()==0 and not shapes.is_empty():
		return {"kept":ArrayMesh.new(),"removed":ArrayMesh.new(),"groups":0,"selected":0,"removed_faces":0}
	if not Diff.supported(mesh) or mesh.get_surface_count()!=1 or shapes.is_empty():
		return {}
	var spatial := index_shapes(shapes)
	var point_cache: Dictionary = {}
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var data := Read._read(mesh)
	var count: int = data.indices.size()/3
	var parents := PackedInt32Array()
	parents.resize(count)
	for i in count:
		parents[i]=i
	var owners: Dictionary = {}
	for i in count:
		for corner in 3:
			var p := vertices[data.indices[i*3+corner]]
			if not p.is_finite():
				return {}
			if owners.has(p):
				var a := root_of(parents,i)
				var b := root_of(parents,int(owners[p]))
				parents[maxi(a,b)]=mini(a,b)
			else:
				owners[p]=i
	var groups: Dictionary = {}
	for i in count:
		var key := root_of(parents,i)
		if not groups.has(key):
			groups[key]=PackedInt32Array()
		var group: PackedInt32Array = groups[key]
		group.append_array(data.indices.slice(i*3,i*3+3))
		groups[key]=group
	var kept := PackedInt32Array()
	var removed := PackedInt32Array()
	var selected := 0
	for group: PackedInt32Array in groups.values():
		var eligible := true
		var visited: Dictionary = {}
		for index in group:
			var point := vertices[index]
			if visited.has(point):
				continue
			visited[point]=true
			var projected := Vector2(point.x,point.z)
			if not point_cache.has(projected):
				point_cache[projected]=indexed_inside(projected,spatial)
			if point.y>3.21 or not region.has_point(projected) or not point_cache[projected]:
				eligible=false
				break
		if eligible:
			selected+=1
			removed.append_array(group)
		else:
			kept.append_array(group)
	var a := Subset.subset(mesh,kept)
	var b := Subset.subset(mesh,removed)
	if not Diff.conserved(mesh,a,b):
		return {}
	return {"kept":a,"removed":b,"groups":groups.size(),"selected":selected,"removed_faces":removed.size()/3}


static func index_shapes(shapes: Array[PackedVector2Array]) -> Dictionary:
	# 仅离线宽相筛选，精判仍用inside；扩大包络保留其1e-5边缘容差。
	var grid: Dictionary = {}
	for shape: PackedVector2Array in shapes:
		if shape.is_empty():
			continue
		var bounds := Rect2(shape[0],Vector2.ZERO)
		for point: Vector2 in shape:
			bounds=bounds.expand(point)
		bounds=bounds.grow(0.00002)
		for y in range(floori(bounds.position.y/32.0),floori(bounds.end.y/32.0)+1):
			for x in range(floori(bounds.position.x/32.0),floori(bounds.end.x/32.0)+1):
				var key := Vector2i(x,y)
				if not grid.has(key):
					var bucket: Array[PackedVector2Array] = []
					grid[key]=bucket
				grid[key].append(shape)
	return grid


static func indexed_inside(point: Vector2, grid: Dictionary) -> bool:
	var key := Vector2i(floori(point.x/32.0),floori(point.y/32.0))
	return inside(point,grid[key]) if grid.has(key) else false
