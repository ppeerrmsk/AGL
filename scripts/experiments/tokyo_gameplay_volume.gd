extends RefCounted
## 原生游戏街区候选：只消费已接受的碰撞轮廓/米高，不修改静态权威缓存。
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Difference := preload("res://scripts/experiments/tokyo_roof_difference.gd")


static func build(entry: Dictionary, cutters: Array = []) -> ArrayMesh:
	var result := Geometry.new()
	var points: PackedVector2Array = entry.footprint
	var indices: PackedInt32Array = entry.tri_indices
	var height := float(entry.max_real_h) * CombatUnit.PIXELS_PER_METER
	assert(height > 0.0 and is_finite(height) and indices.size() % 3 == 0)
	var color := Color.html("b0b1a9")
	for n in range(0, indices.size(), 3):
		var roof := PackedVector2Array([points[indices[n]], points[indices[n + 1]], points[indices[n + 2]]])
		for piece: PackedVector2Array in Difference.subtract_all(roof, cutters):
			for j in range(1, piece.size() - 1):
				var a := Vector3(piece[0].x, height, piece[0].y)
				var b := Vector3(piece[j].x, height, piece[j].y)
				var c := Vector3(piece[j + 1].x, height, piece[j + 1].y)
				var cross_value := (b - a).cross(c - a)
				if cross_value.length_squared() == 0.0:
					continue
				if cross_value.y > 0.0:
					result.triangle(a, b, c, color)
				else:
					result.triangle(a, c, b, color)
	var clockwise := Geometry2D.is_polygon_clockwise(points)
	for n in points.size():
		var p := points[n]
		var q := points[(n + 1) % points.size()]
		if p == q:
			continue
		var a := Vector3(p.x, 0, p.y)
		var b := Vector3(q.x, 0, q.y)
		var up := Vector3.UP * height
		if clockwise:
			result.quad(a, b, b + up, a + up, color.darkened(0.08))
		else:
			result.quad(b, a, a + up, b + up, color.darkened(0.08))
	return result.mesh()


static func joined(original: ArrayMesh, addition: ArrayMesh) -> ArrayMesh:
	# 两surface复用既有MeshInstance及材质；显式统计原包仍驻留和候选额外字节。
	var combined := ArrayMesh.new()
	var surfaces: Array = original.get("_surfaces").duplicate()
	surfaces.append_array(addition.get("_surfaces"))
	combined.set("_surfaces", surfaces)
	return combined


static func build_many(entries: Array, roofs_by_height: Dictionary = {}) -> ArrayMesh:
	var builder := Geometry.new()
	for entry: Dictionary in entries:
		var height_key := roundi(float(entry.max_real_h) * CombatUnit.PIXELS_PER_METER * 1000.0)
		var mesh := build(entry, roofs_by_height.get(height_key, []))
		var arrays := mesh.surface_get_arrays(0)
		builder._vertices.append_array(arrays[Mesh.ARRAY_VERTEX])
		builder._normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		builder._colors.append_array(arrays[Mesh.ARRAY_COLOR])
	return builder.mesh()


static func geometry_bytes(mesh: ArrayMesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		for channel: Variant in mesh.surface_get_arrays(surface):
			if channel != null:
				total += channel.to_byte_array().size()
	return total


static func triangles(mesh: ArrayMesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var indices := mesh.surface_get_array_index_len(surface)
		total += (indices if indices > 0 else mesh.surface_get_array_len(surface)) / 3
	return total
