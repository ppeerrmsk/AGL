extends RefCounted
## 离线单surface合并：只重建索引，保留位置、法线/切线和颜色的原生打包字节。


static func join(meshes: Array[ArrayMesh]) -> ArrayMesh:
	var template: Dictionary = {}
	var positions := PackedByteArray()
	var normals := PackedByteArray()
	var attributes := PackedByteArray()
	var indices := PackedInt32Array()
	var count := 0
	var bounds := AABB()
	for mesh: ArrayMesh in meshes:
		if mesh.get_surface_count() == 0:
			continue
		assert(mesh.get_surface_count() == 1 and mesh.get_blend_shape_count() == 0)
		var surface: Dictionary = mesh.get("_surfaces")[0]
		var format := int(surface.format)
		assert((format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0 and surface.get("lods", []).is_empty() and surface.get("skin_data", PackedByteArray()).is_empty())
		if template.is_empty():
			template = surface.duplicate()
			bounds = mesh.get_aabb()
		else:
			assert((format & ~Mesh.ARRAY_FORMAT_INDEX) == (int(template.format) & ~Mesh.ARRAY_FORMAT_INDEX), "packed attributes must have identical layout")
			assert(surface.get("material") == template.get("material"), "one surface cannot merge different materials")
			bounds = bounds.merge(mesh.get_aabb())
		var size := int(surface.vertex_count)
		var ps := RenderingServer.mesh_surface_get_format_vertex_stride(format, size)
		assert(ps == 12 and int(surface.primitive) == Mesh.PRIMITIVE_TRIANGLES)
		var raw: PackedByteArray = surface.vertex_data
		positions.append_array(raw.slice(0, size * ps))
		normals.append_array(raw.slice(size * ps))
		attributes.append_array(surface.get("attribute_data", PackedByteArray()))
		var arrays := mesh.surface_get_arrays(0)
		var old: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		for i in (old.size() if not old.is_empty() else size):
			indices.append(count + (old[i] if not old.is_empty() else i))
		count += size
	var result := ArrayMesh.new()
	if template.is_empty():
		return result
	positions.append_array(normals)
	template.vertex_data = positions
	template.attribute_data = attributes
	template.vertex_count = count
	template.format = int(template.format) | Mesh.ARRAY_FORMAT_INDEX
	template.index_count = indices.size()
	var stride := RenderingServer.mesh_surface_get_format_index_stride(template.format, count)
	assert(stride in [2, 4])
	var packed := PackedByteArray()
	packed.resize(indices.size() * stride)
	for i in indices.size():
		if stride == 2:
			packed.encode_u16(i * 2, indices[i])
		else:
			packed.encode_u32(i * 4, indices[i])
	template.index_data = packed
	template.aabb = bounds
	result.set("_surfaces", [template])
	return result


static func signatures(mesh: ArrayMesh) -> Dictionary:
	var result: Dictionary = {}
	if mesh.get_surface_count() == 0:
		return result
	assert(mesh.get_surface_count() == 1)
	var source: Dictionary = mesh.get("_surfaces")[0]
	var count := int(source.vertex_count)
	var ps := RenderingServer.mesh_surface_get_format_vertex_stride(source.format, count)
	var ns := RenderingServer.mesh_surface_get_format_normal_tangent_stride(source.format, count)
	var cs := RenderingServer.mesh_surface_get_format_attribute_stride(source.format, count)
	var raw: PackedByteArray = source.vertex_data
	var attrs: PackedByteArray = source.get("attribute_data", PackedByteArray())
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	for start in range(0, indices.size() if not indices.is_empty() else count, 3):
		var key := PackedByteArray()
		for n in 3:
			var id := indices[start+n] if not indices.is_empty() else start+n
			key.append_array(raw.slice(id * ps, (id+1) * ps))
			key.append_array(raw.slice(count * ps + id * ns, count * ps + (id+1) * ns))
			key.append_array(attrs.slice(id * cs, (id+1) * cs))
		result[key] = int(result.get(key, 0)) + 1
	return result


static func conserved(original: ArrayMesh, pieces: Array[ArrayMesh]) -> bool:
	var remaining := signatures(original)
	for mesh: ArrayMesh in pieces:
		var current := signatures(mesh)
		for key: PackedByteArray in current:
			var count := int(remaining.get(key, 0)) - int(current[key])
			if count < 0:
				return false
			if count == 0:
				remaining.erase(key)
			else:
				remaining[key] = count
	return remaining.is_empty()
