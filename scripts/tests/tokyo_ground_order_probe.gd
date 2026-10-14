extends RefCounted
## R56控制变量：只改变地表提交顺序，不重编码属性或改变任何有向三角。


static func move_to_end(mesh: ArrayMesh, removed: Array) -> ArrayMesh:
	if mesh.get_surface_count() != 1 or mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return null
	var surface: Dictionary = mesh.get("_surfaces")[0].duplicate()
	var arrays := mesh.surface_get_arrays(0)
	var old: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := old.size() if not old.is_empty() else int(surface.vertex_count)
	var selected: Dictionary = {}
	for value: Variant in removed:
		var id := int(value)
		if float(value) != float(id) or id < 0 or id >= count / 3 or selected.has(id):
			return null
		selected[id] = true
	var indices := PackedInt32Array()
	for moved: bool in [false, true]:
		for face in count / 3:
			if selected.has(face) != moved:
				continue
			for corner in 3:
				var offset := face * 3 + corner
				indices.append(old[offset] if not old.is_empty() else offset)
	var format := int(surface.format) | Mesh.ARRAY_FORMAT_INDEX
	var stride := RenderingServer.mesh_surface_get_format_index_stride(format, surface.vertex_count)
	var data := PackedByteArray()
	data.resize(indices.size() * stride)
	for n in indices.size():
		if stride == 2:
			data.encode_u16(n * stride, indices[n])
		else:
			data.encode_u32(n * stride, indices[n])
	surface.format = format
	surface.index_data = data
	surface.index_count = indices.size()
	var result := ArrayMesh.new()
	result.set("_surfaces", [surface])
	return result
