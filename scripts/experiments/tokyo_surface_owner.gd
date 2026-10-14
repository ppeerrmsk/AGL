extends RefCounted
## 离线/显式诊断：只让明确标高层接管完全相同的有向三角，拒绝近似共面裁决。


static func keys(mesh: ArrayMesh) -> Array[PackedByteArray]:
	var result: Array[PackedByteArray] = []
	if mesh.get_surface_count() == 0:
		return result
	assert(mesh.get_surface_count() == 1 and mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedByteArray = arrays[Mesh.ARRAY_VERTEX].to_byte_array()
	var normals: PackedByteArray = arrays[Mesh.ARRAY_NORMAL].to_byte_array()
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() if not indices.is_empty() else mesh.surface_get_array_len(0)
	for offset in range(0, count, 3):
		var corners: Array[PackedByteArray] = []
		for n in 3:
			var id := indices[offset + n] if not indices.is_empty() else offset + n
			var corner := vertices.slice(id * 12, (id + 1) * 12)
			corner.append_array(normals.slice(id * 12, (id + 1) * 12))
			corners.append(corner)
		# 循环起点可不同；不允许反向绕序或异法线墙面互相替代。
		var start := 0
		for n in range(1, 3):
			if corners[n].hex_encode() < corners[start].hex_encode():
				start = n
		var key := PackedByteArray()
		for n in 3:
			key.append_array(corners[(start + n) % 3])
		result.append(key)
	return result


static func resolve(low: ArrayMesh, known: ArrayMesh, covered_walls: bool = false) -> Dictionary:
	var owners: Dictionary = {}
	for key: PackedByteArray in keys(known):
		owners[key] = true
	var low_keys := keys(low)
	var removed := PackedInt32Array()
	var claimed: Dictionary = {}
	for face in low_keys.size():
		if owners.has(low_keys[face]):
			claimed[face] = true
	if covered_walls:
		var rectangles := wall_rectangles(known)
		for wall: Dictionary in wall_records(low):
			for rectangle: Vector2 in rectangles.get(wall.key, []):
				if wall.low >= rectangle.x and wall.high <= rectangle.y:
					claimed[wall.face] = true
	for face in low_keys.size():
		if claimed.has(face):
			removed.append(face)
	if removed.is_empty():
		return {"mesh": low, "removed": removed, "changed": false}
	if removed.size() == low_keys.size():
		return {"mesh": ArrayMesh.new(), "removed": removed, "changed": true}
	var packed: Dictionary = low.get("_surfaces")[0].duplicate()
	assert((int(packed.format) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0 and packed.get("lods", []).is_empty())
	var count := int(packed.vertex_count)
	var old_stride := RenderingServer.mesh_surface_get_format_index_stride(int(packed.format), count)
	var indexed := int(packed.get("index_count", 0)) > 0
	var old: PackedByteArray = packed.get("index_data", PackedByteArray())
	packed.format = int(packed.format) | Mesh.ARRAY_FORMAT_INDEX
	var stride := RenderingServer.mesh_surface_get_format_index_stride(int(packed.format), count)
	var data := PackedByteArray()
	data.resize((low_keys.size() - removed.size()) * 3 * stride)
	var target := 0
	for face in low_keys.size():
		if claimed.has(face):
			continue
		for n in 3:
			var offset := face * 3 + n
			var id := (old.decode_u16(offset * 2) if old_stride == 2 else old.decode_u32(offset * 4)) if indexed else offset
			if stride == 2:
				data.encode_u16(target * 2, id)
			else:
				data.encode_u32(target * 4, id)
			target += 1
	# 保留原顶点/属性/包络，诊断不引入重编码或挪动；未使用顶点仍计入驻留。
	packed.index_data = data
	packed.index_count = target
	var mesh := ArrayMesh.new()
	mesh.set("_surfaces", [packed])
	return {"mesh": mesh, "removed": removed, "changed": true}


static func wall_records(mesh: ArrayMesh) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if mesh.get_surface_count() == 0:
		return result
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for offset in range(0, count, 3):
		var points: Array[Vector3] = []
		var ends: Array[Vector2] = []
		var normal := Vector3.ZERO
		var valid := true
		for n in 3:
			var id := indices[offset + n] if not indices.is_empty() else offset + n
			var p := vertices[id]
			points.append(p)
			var end := Vector2(p.x, p.z)
			if not ends.has(end):
				ends.append(end)
			if n == 0:
				normal = normals[id]
			else:
				valid = valid and normal == normals[id]
		if not valid or ends.size() != 2:
			continue
		if ends[1] < ends[0]:
			ends.reverse()
		var low := minf(points[0].y, minf(points[1].y, points[2].y))
		var high := maxf(points[0].y, maxf(points[1].y, points[2].y))
		if high <= low:
			continue
		var local: Array[Vector2] = []
		var mask := 0
		for p: Vector3 in points:
			if p.y != low and p.y != high:
				valid = false
			var side := int(Vector2(p.x, p.z) == ends[1])
			mask |= 1 << (side + 2 * int(p.y == high))
			local.append(Vector2(side, p.y))
		var direction := (local[1] - local[0]).cross(local[2] - local[0])
		if not valid or direction == 0.0:
			continue
		var key := PackedVector2Array(ends).to_byte_array().hex_encode() + PackedVector3Array([normal]).to_byte_array().hex_encode() + str(signi(int(signf(direction))))
		result.append({"face": offset / 3, "key": key, "low": low, "high": high, "mask": mask})
	return result


static func wall_rectangles(mesh: ArrayMesh) -> Dictionary:
	var groups: Dictionary = {}
	for wall: Dictionary in wall_records(mesh):
		var key: String = wall.key + PackedFloat32Array([wall.low, wall.high]).to_byte_array().hex_encode()
		if not groups.has(key):
			groups[key] = {"key": wall.key, "range": Vector2(wall.low, wall.high), "masks": {}}
		groups[key].masks[int(wall.mask)] = true
	var result: Dictionary = {}
	for group: Dictionary in groups.values():
		# 两个缺失角必须互为对角；相邻缺角会留下空洞，不能声明整矩形。
		var masks: Dictionary = group.masks
		if not ((masks.has(14) and masks.has(7)) or (masks.has(13) and masks.has(11))):
			continue
		if not result.has(group.key):
			result[group.key] = []
		result[group.key].append(group.range)
	return result
