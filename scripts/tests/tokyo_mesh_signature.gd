extends RefCounted
## 离线审计专用：按索引展开真实角点，比较有重数的有向三角/法线/颜色。


static func of_mesh(mesh: ArrayMesh) -> Dictionary:
	var result: Dictionary = {}
	if mesh.get_surface_count() == 0:
		return result
	assert(mesh.get_surface_count() == 1)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedByteArray = arrays[Mesh.ARRAY_VERTEX].to_byte_array()
	var normals: PackedByteArray = arrays[Mesh.ARRAY_NORMAL].to_byte_array()
	var colors: PackedByteArray = arrays[Mesh.ARRAY_COLOR].to_byte_array()
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() if not indices.is_empty() else mesh.surface_get_array_len(0)
	for start in range(0, count, 3):
		var key := PackedByteArray()
		for corner in 3:
			var id: int = indices[start + corner] if not indices.is_empty() else start + corner
			key.append_array(vertices.slice(id * 12, (id + 1) * 12))
			key.append_array(normals.slice(id * 12, (id + 1) * 12))
			key.append_array(colors.slice(id * 16, (id + 1) * 16))
		result[key] = int(result.get(key, 0)) + 1
	return result
