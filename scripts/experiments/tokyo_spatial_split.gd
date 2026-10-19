extends RefCounted
## 原生三角无损分桶：不切三角、不重算法线，子包AABB覆盖完整跨界面。


static func centers(mesh: ArrayMesh) -> PackedVector2Array:
	var result := PackedVector2Array()
	if mesh.get_surface_count() == 0:
		return result
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for offset in range(0, count, 3):
		var center := Vector3.ZERO
		for n in 3:
			center += vertices[indices[offset + n] if not indices.is_empty() else offset + n]
		result.append(Vector2(center.x, center.z) / 3.0)
	return result


static func cuts(meshes: Array[ArrayMesh]) -> PackedFloat32Array:
	var points := PackedVector2Array()
	for mesh: ArrayMesh in meshes:
		points.append_array(centers(mesh))
	if points.is_empty():
		return PackedFloat32Array([0, 0, 0])
	var xs := PackedFloat32Array()
	for p: Vector2 in points:
		xs.append(p.x)
	xs.sort()
	var x := xs[xs.size() / 2]
	var ys: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	for p: Vector2 in points:
		ys[int(p.x >= x)].append(p.y)
	for values: PackedFloat32Array in ys:
		values.sort()
	return PackedFloat32Array([x, ys[0][ys[0].size() / 2] if not ys[0].is_empty() else 0.0,
		ys[1][ys[1].size() / 2] if not ys[1].is_empty() else 0.0])


static func bucket(point: Vector2, cut: PackedFloat32Array) -> int:
	var side := int(point.x >= cut[0])
	return side * 2 + int(point.y >= cut[side + 1])


static func split(mesh: ArrayMesh, cut: PackedFloat32Array) -> Array[ArrayMesh]:
	if mesh.get_surface_count()==0:
		return partition(mesh,PackedInt32Array(),4)
	assert(cut.size()==3)
	var owners := PackedInt32Array()
	for point: Vector2 in centers(mesh):
		owners.append(bucket(point,cut))
	return partition(mesh,owners,4)


static func partition(mesh: ArrayMesh, owners: PackedInt32Array, buckets: int) -> Array[ArrayMesh]:
	var result: Array[ArrayMesh] = []
	if buckets<1 or buckets>256 or mesh==null or mesh.get_surface_count()>1:
		return result
	var faces := 0
	if mesh.get_surface_count()>0:
		var surface: Dictionary = mesh.get("_surfaces")[0]
		faces=int(surface.get("index_count",0)) if int(surface.get("index_count",0))>0 else int(surface.vertex_count)
		if faces%3!=0:
			return []
		faces/=3
	if owners.size()!=faces:
		return []
	for owner in owners:
		if owner<0 or owner>=buckets:
			return []
	for n in buckets:
		result.append(ArrayMesh.new())
	if mesh.get_surface_count() == 0:
		return result
	assert(mesh.get_surface_count() == 1 and mesh.get_blend_shape_count() == 0)
	var source: Dictionary = mesh.get("_surfaces")[0]
	var format := int(source.format)
	assert((format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0 and source.get("lods", []).is_empty() and source.get("skin_data", PackedByteArray()).is_empty())
	var count := int(source.vertex_count)
	var ps := RenderingServer.mesh_surface_get_format_vertex_stride(format, count)
	var ns := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, count)
	var cs := RenderingServer.mesh_surface_get_format_attribute_stride(format, count)
	var indexed := int(source.get("index_count", 0)) > 0
	var stride := RenderingServer.mesh_surface_get_format_index_stride(format, count) if indexed else 0
	assert(ps == 12 and (not indexed or stride in [2, 4]))
	var raw: PackedByteArray = source.vertex_data
	var attrs: PackedByteArray = source.get("attribute_data", PackedByteArray())
	var old_indices: PackedByteArray = source.get("index_data", PackedByteArray())
	var positions: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var batches: Array[Dictionary] = []
	for n in buckets:
		batches.append({"positions": PackedByteArray(), "normals": PackedByteArray(), "attrs": PackedByteArray(),
			"indices": PackedInt32Array(), "remap": {}, "box": AABB(), "started": false})
	for face in owners.size():
		var batch: Dictionary = batches[owners[face]]
		for corner in 3:
			var offset := face * 3 + corner
			var id := (old_indices.decode_u16(offset * 2) if stride == 2 else old_indices.decode_u32(offset * 4)) if indexed else offset
			if not batch.remap.has(id):
				batch.remap[id] = batch.remap.size()
				batch.positions.append_array(raw.slice(id * ps, (id + 1) * ps))
				batch.normals.append_array(raw.slice(count * ps + id * ns, count * ps + (id + 1) * ns))
				batch.attrs.append_array(attrs.slice(id * cs, (id + 1) * cs))
				batch.box = (batch.box as AABB).expand(positions[id]) if batch.started else AABB(positions[id], Vector3.ZERO)
				batch.started = true
			batch.indices.append(int(batch.remap[id]))
	for n in buckets:
		var batch: Dictionary = batches[n]
		if not batch.started:
			continue
		var packed := source.duplicate()
		packed.vertex_count = batch.remap.size()
		var data: PackedByteArray = batch.positions
		data.append_array(batch.normals)
		packed.vertex_data = data
		packed.attribute_data = batch.attrs
		packed.aabb = batch.box
		if indexed:
			var new_stride := RenderingServer.mesh_surface_get_format_index_stride(format, int(packed.vertex_count))
			var index_data := PackedByteArray()
			index_data.resize(batch.indices.size() * new_stride)
			for i in batch.indices.size():
				if new_stride == 2:
					index_data.encode_u16(i * 2, batch.indices[i])
				else:
					index_data.encode_u32(i * 4, batch.indices[i])
			packed.index_data = index_data
			packed.index_count = batch.indices.size()
		else:
			packed.index_data = PackedByteArray()
			packed.index_count = 0
		result[n].set("_surfaces", [packed])
	return result
