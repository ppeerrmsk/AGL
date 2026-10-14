extends RefCounted
## 独立离线烘焙；三角分区必须已通过Python门，只重建指定屋顶，保留其它面。
const Bundle := preload("res://scripts/experiments/tokyo_shared_roof_bundle.gd")
const Factory := preload("res://scripts/experiments/tokyo_gameplay_volume.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")


static func run(input: String, output: String) -> int:
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input))
	if not plan.get("passed", false) or FileAccess.file_exists(output):
		push_error("Shared roof bake: failed plan or output already exists")
		return 1
	var bundle := Bundle.new()
	bundle.pose = int(plan.pose)
	bundle.plan_sha256 = FileAccess.get_sha256(input)
	bundle.collision_sha256 = str(plan.collision_sha256)
	var removes: Dictionary = {}
	var additions: Dictionary = {}
	for source: Dictionary in plan.native_sources:
		var key := "%d/%d" % [int(source.mesh), int(source.surface)]
		if not removes.has(key):
			removes[key] = {}
		removes[key][int(source.triangle)] = true
	for triangle: Dictionary in plan.triangles:
		if triangle.layer != "native":
			continue
		var source: Dictionary = plan.native_sources[int(triangle.owner)]
		var key := "%d/%d" % [int(source.mesh), int(source.surface)]
		if not additions.has(key):
			additions[key] = []
		var attributed := triangle.duplicate()
		attributed["source_triangle"] = int(source.triangle)
		additions[key].append(attributed)
	for descriptor: Dictionary in plan.meshes:
		var touched := false
		for surface in descriptor.surfaces.size():
			touched = touched or removes.has("%d/%d" % [int(descriptor.id), surface])
		if not touched:
			continue
		if FileAccess.get_sha256(str(descriptor.path)) != str(descriptor.source_sha256):
			push_error("Shared roof bake: source resource drift")
			return 1
		var resource: Resource = ResourceLoader.load(str(descriptor.path))
		var original: ArrayMesh = resource.precision_original if bool(descriptor.precision_guarded) and int(descriptor.kind) == 0 else resource.meshes[int(descriptor.kind)]
		var rebuilt := ArrayMesh.new()
		for surface in original.get_surface_count():
			var arrays := original.surface_get_arrays(surface)
			if var_to_bytes(arrays).hex_encode().sha256_text() != str(descriptor.surfaces[surface]):
				push_error("Shared roof bake: bound source array drift")
				return 1
			var key := "%d/%d" % [int(descriptor.id), surface]
			if removes.has(key):
				arrays = _replace(arrays, removes[key], additions.get(key, []))
				if arrays.is_empty():
					return 1
				bundle.removed_faces += removes[key].size()
				bundle.replacement_faces += additions.get(key, []).size()
			rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			_retain_material(rebuilt, original, surface)
			if not _preserve_packed(rebuilt, original, surface, additions.get(key, [])):
				return 1
		bundle.meshes.append(rebuilt)
		bundle.descriptors.append(descriptor)
		bundle.decoded_bytes += Factory.geometry_bytes(rebuilt)
	bundle.addition = _addition(plan)
	bundle.decoded_bytes += Factory.geometry_bytes(bundle.addition)
	if ResourceSaver.save(bundle, output) != OK:
		return 1
	var saved: Resource = ResourceLoader.load(output, "", ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null or saved.meshes.size() != bundle.meshes.size():
		return 1
	# 保存后逐通道校验，不能只验证内存中的制作结果。
	for index in bundle.meshes.size():
		if not _same_arrays(bundle.meshes[index], saved.meshes[index]):
			push_error("Shared roof bake: saved arrays differ")
			return 1
	if not _same_arrays(bundle.addition, saved.addition):
		return 1
	print("[Tokyo shared bake] pose=", bundle.pose, " meshes=", bundle.meshes.size(), " removed=", bundle.removed_faces,
		" rebuilt_roofs=", bundle.replacement_faces, " addition_faces=", Factory.triangles(bundle.addition), " bytes=", bundle.decoded_bytes, " reload=PASS")
	return 0


static func _replace(arrays: Array, removed: Dictionary, triangles: Array) -> Array:
	# Godot原包含自动切线；保留旧切线并沿相同平面来源延续，未知通道拒绝丢弃。
	for channel in arrays.size():
		if channel not in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX] and arrays[channel] != null:
			if arrays[channel].size() > 0:
				push_error("Shared roof bake: unsupported source channel %d size=%d vertices=%d" % [channel, arrays[channel].size(), arrays[Mesh.ARRAY_VERTEX].size()])
				return []
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var original_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := original_indices.size() if not original_indices.is_empty() else vertices.size()
	var indices := PackedInt32Array()
	for offset in range(0, count, 3):
		if removed.has(offset / 3):
			continue
		for n in 3:
			indices.append(original_indices[offset+n] if not original_indices.is_empty() else offset+n)
	for triangle: Dictionary in triangles:
		var points := _points(triangle)
		var tangent := PackedFloat32Array()
		if not tangents.is_empty():
			for n in 3:
				var offset := int(triangle.source_triangle) * 3 + n
				var source_index := original_indices[offset] if not original_indices.is_empty() else offset
				var part := tangents.slice(source_index * 4, source_index * 4 + 4)
				if n == 0:
					tangent = part
				elif part != tangent:
					push_error("Shared roof bake: non-flat source tangent")
					return []
		var normal := Vector3(triangle.normal[0], triangle.normal[1], triangle.normal[2])
		var color := Color(triangle.color[0], triangle.color[1], triangle.color[2], triangle.color[3])
		for point: Vector3 in points:
			indices.append(vertices.size())
			vertices.append(point)
			normals.append(normal)
			colors.append(color)
			if not tangent.is_empty():
				tangents.append_array(tangent)
	var result := arrays.duplicate()
	result[Mesh.ARRAY_VERTEX] = vertices
	result[Mesh.ARRAY_NORMAL] = normals
	result[Mesh.ARRAY_COLOR] = colors
	if not tangents.is_empty():
		result[Mesh.ARRAY_TANGENT] = tangents
	result[Mesh.ARRAY_INDEX] = indices
	return result


static func _points(triangle: Dictionary) -> PackedVector3Array:
	var result := PackedVector3Array()
	for point: Array in triangle.points:
		result.append(Vector3(point[0], triangle.height, point[1]))
	if (result[1] - result[0]).cross(result[2] - result[0]).y > 0:
		var swap := result[1]
		result[1] = result[2]
		result[2] = swap
	return result


static func _addition(plan: Dictionary) -> ArrayMesh:
	var builder := Geometry.new()
	for entry: Dictionary in plan.expected:
		var points := PackedVector2Array()
		for point: Array in entry.points:
			points.append(Vector2(point[0], point[1]))
		var clockwise := Geometry2D.is_polygon_clockwise(points)
		for n in points.size():
			var p := points[n]
			var q := points[(n+1) % points.size()]
			if p == q:
				continue
			var a := Vector3(p.x, 0, p.y)
			var b := Vector3(q.x, 0, q.y)
			var up := Vector3.UP * float(entry.height)
			var tint := Color.html("b0b1a9").darkened(0.08)
			if clockwise:
				builder.quad(a, b, b+up, a+up, tint)
			else:
				builder.quad(b, a, a+up, b+up, tint)
	for triangle: Dictionary in plan.triangles:
		if triangle.layer != "candidate":
			continue
		var color := Color(triangle.color[0], triangle.color[1], triangle.color[2], triangle.color[3])
		for point: Vector3 in _points(triangle):
			builder._vertices.append(point)
			builder._normals.append(Vector3.UP)
			builder._colors.append(color)
	return builder.mesh()


static func _same_arrays(a: ArrayMesh, b: ArrayMesh) -> bool:
	if a.get_surface_count() != b.get_surface_count():
		return false
	for surface in a.get_surface_count():
		if var_to_bytes(a.surface_get_arrays(surface)) != var_to_bytes(b.surface_get_arrays(surface)):
			return false
	return true


static func _retain_material(rebuilt: ArrayMesh, original: ArrayMesh, surface: int) -> void:
	rebuilt.surface_set_material(surface, original.surface_get_material(surface))


static func _preserve_packed(rebuilt: ArrayMesh, original: ArrayMesh, surface: int, triangles: Array) -> bool:
	# 避免把解码后的法线再量化；旧面逐字节保留，新面继承同一平面来源的属性块。
	var before: Dictionary = original.get("_surfaces")[surface]
	var surfaces: Array = rebuilt.get("_surfaces")
	var after: Dictionary = surfaces[surface]
	var old_count := int(before.vertex_count)
	var new_count := int(after.vertex_count)
	var old_format := int(before.format)
	var new_format := int(after.format)
	if (old_format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0 or new_count != old_count + triangles.size() * 3:
		return false
	var position_stride := RenderingServer.mesh_surface_get_format_vertex_stride(old_format, old_count)
	var normal_stride := RenderingServer.mesh_surface_get_format_normal_tangent_stride(old_format, old_count)
	var attribute_stride := RenderingServer.mesh_surface_get_format_attribute_stride(old_format, old_count)
	if position_stride != RenderingServer.mesh_surface_get_format_vertex_stride(new_format, new_count) or normal_stride != RenderingServer.mesh_surface_get_format_normal_tangent_stride(new_format, new_count) or attribute_stride != RenderingServer.mesh_surface_get_format_attribute_stride(new_format, new_count):
		return false
	var old_data: PackedByteArray = before.vertex_data
	var new_data: PackedByteArray = after.vertex_data
	var old_attributes: PackedByteArray = before.attribute_data
	var normals := old_data.slice(old_count * position_stride)
	var attributes := old_attributes.duplicate()
	var arrays := original.surface_get_arrays(surface)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	for triangle: Dictionary in triangles:
		var offset := int(triangle.source_triangle) * 3
		var id := indices[offset] if not indices.is_empty() else offset
		var source_normal := old_data.slice(old_count * position_stride + id * normal_stride, old_count * position_stride + (id+1) * normal_stride)
		var source_attribute := old_attributes.slice(id * attribute_stride, (id+1) * attribute_stride)
		for n in 3:
			normals.append_array(source_normal)
			attributes.append_array(source_attribute)
	var positions := new_data.slice(0, new_count * position_stride)
	positions.append_array(normals)
	after.vertex_data = positions
	after.attribute_data = attributes
	surfaces[surface] = after
	rebuilt.set("_surfaces", surfaces)
	return true
