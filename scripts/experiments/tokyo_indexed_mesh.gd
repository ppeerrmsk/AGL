extends RefCounted
## 离线无损顶点复用；运行时只用O(1)的索引面数查询，不解码顶点。


static func triangles(mesh: ArrayMesh) -> int:
	if mesh.get_surface_count() == 0:
		return 0
	var indices := mesh.surface_get_array_index_len(0)
	return (indices if indices > 0 else mesh.surface_get_array_len(0)) / 3


static func pack(mesh: ArrayMesh) -> ArrayMesh:
	if mesh.get_surface_count() == 0:
		return ArrayMesh.new()
	assert(mesh.get_surface_count() == 1 and mesh.get_blend_shape_count() == 0)
	var original: Dictionary = mesh.get("_surfaces")[0]
	var format := int(original.format)
	assert((format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0)
	assert(int(original.get("index_count", 0)) == 0 and original.get("skin_data", PackedByteArray()).is_empty() and original.get("lods", []).is_empty())
	var count := int(original.vertex_count)
	var position_stride := RenderingServer.mesh_surface_get_format_vertex_stride(format, count)
	var normal_stride := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format, count)
	var attribute_stride := RenderingServer.mesh_surface_get_format_attribute_stride(format, count)
	var source: PackedByteArray = original.vertex_data
	var attributes: PackedByteArray = original.get("attribute_data", PackedByteArray())
	assert(source.size() == count * (position_stride + normal_stride) and attributes.size() == count * attribute_stride)
	var positions := PackedByteArray()
	var normals := PackedByteArray()
	var colors := PackedByteArray()
	var indices := PackedInt32Array()
	indices.resize(count)
	var unique: Dictionary = {}
	for vertex in count:
		var position := source.slice(vertex * position_stride, (vertex + 1) * position_stride)
		var normal := source.slice(count * position_stride + vertex * normal_stride, count * position_stride + (vertex + 1) * normal_stride)
		var color := attributes.slice(vertex * attribute_stride, (vertex + 1) * attribute_stride)
		var key := position.hex_encode() + normal.hex_encode() + color.hex_encode()
		if not unique.has(key):
			unique[key] = unique.size()
			positions.append_array(position)
			normals.append_array(normal)
			colors.append_array(color)
		indices[vertex] = int(unique[key])
	var original_bytes := 0
	for channel: Variant in mesh.surface_get_arrays(0):
		if channel != null:
			original_bytes += channel.to_byte_array().size()
	# 很小或不共享的几何保留原包，不能为加索引反而增加驻留账。
	if original_bytes * unique.size() / count + count * 4 >= original_bytes:
		return mesh
	format |= Mesh.ARRAY_FORMAT_INDEX
	var stride := RenderingServer.mesh_surface_get_format_index_stride(format, unique.size())
	assert(stride in [2, 4])
	var index_data := PackedByteArray()
	index_data.resize(count * stride)
	for vertex in count:
		if stride == 2:
			index_data.encode_u16(vertex * 2, indices[vertex])
		else:
			index_data.encode_u32(vertex * 4, indices[vertex])
	var packed := original.duplicate()
	positions.append_array(normals)
	packed.vertex_data = positions
	packed.attribute_data = colors
	packed.vertex_count = unique.size()
	packed.format = format
	packed.index_count = count
	packed.index_data = index_data
	var result := ArrayMesh.new()
	result.set("_surfaces", [packed])
	assert(triangles(result) == triangles(mesh))
	return result
