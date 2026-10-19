extends RefCounted
## 逐三角形包含证明：每个瓦片面必须落在同一个全图面中，不能只抽查顶点高度。
const Surface := preload("res://scripts/experiments/volume_terrain_surface.gd")
var _full: Array
var _buckets: Dictionary = {}
var _origin: Vector2
var _step: Vector2
var _max_height := 0.0
var _max_normal := 0.0
var _checked := 0
var _missing := 0


func run(archive: Resource, surface: RefCounted) -> bool:
	_full = archive.entries.StrategicBasemap.mesh.surface_get_arrays(0)
	_origin = surface.rect.position
	_step = surface.step
	var vertices: PackedVector3Array = _full[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = _full[Mesh.ARRAY_INDEX]
	for i in range(0, indices.size(), 3):
		var a := Vector2(vertices[indices[i]].x, vertices[indices[i]].z)
		var b := Vector2(vertices[indices[i + 1]].x, vertices[indices[i + 1]].z)
		var c := Vector2(vertices[indices[i + 2]].x, vertices[indices[i + 2]].z)
		var first := Vector2i(((a.min(b).min(c) - _origin) / _step).floor())
		var last := Vector2i(((a.max(b).max(c) - _origin) / _step).floor())
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var key := Vector2i(x, z)
				if not _buckets.has(key):
					_buckets[key] = []
				_buckets[key].append(i)
	var tiles := 0
	for key: String in archive.entries:
		if key == "StrategicBasemap":
			continue
		tiles += 1
		var entry: Dictionary = archive.entries[key]
		var arrays: Array = entry.mesh.surface_get_arrays(0)
		var tile_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var tile_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var attributes: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
		for i in range(0, tile_indices.size(), 3):
			var points := PackedVector3Array([tile_vertices[tile_indices[i]],
				tile_vertices[tile_indices[i + 1]], tile_vertices[tile_indices[i + 2]]])
			var center := (points[0] + points[1] + points[2]) / 3.0
			var cell := Vector2i(((Vector2(center.x, center.z) - _origin) / _step).floor())
			var found := false
			for candidate: int in _buckets.get(cell, []):
				if _compare_triangle(points, attributes, tile_indices, i, candidate,
					float(entry.base_y) - float(archive.entries.StrategicBasemap.base_y)):
					found = true
					break
			_checked += 1
			if not found:
				_missing += 1
				if _missing <= 4:
					print("[Native surface missing] ", key, " triangle=", i / 3, " at=", center)
	var ok := tiles == 145 and _checked == 81748 and _missing == 0 and _max_height < 0.002 and _max_normal < 0.00002
	ok = _negative_controls() and ok
	print("[Native surface] tiles=%d triangles=%d unmatched=%d height_error=%.9f custom_normal_error=%.9f pass=%s" % [
		tiles, _checked, _missing, _max_height, _max_normal, ok])
	return ok


func _compare_triangle(points: PackedVector3Array, attributes: PackedFloat32Array,
		tile_indices: PackedInt32Array, offset: int, candidate: int, base_delta: float) -> bool:
	var full_vertices: PackedVector3Array = _full[Mesh.ARRAY_VERTEX]
	var full_indices: PackedInt32Array = _full[Mesh.ARRAY_INDEX]
	var full_attributes: PackedFloat32Array = _full[Mesh.ARRAY_CUSTOM0]
	var triangle := PackedVector2Array()
	for j in 3:
		var point := full_vertices[full_indices[candidate + j]]
		triangle.append(Vector2(point.x, point.z))
	var weights: Array[Vector3] = []
	for point: Vector3 in points:
		var w := Surface.triangle_weights(Vector2(point.x, point.z), triangle)
		if minf(w.x, minf(w.y, w.z)) < -0.00001:
			return false
		weights.append(w)
	# 凸三角形的三个顶点均在同一个父面中，因此整个面均在内；高度及 CUSTOM0 均为线性插值。
	for j in 3:
		var height := base_delta
		var normal := Vector3.ZERO
		for k in 3:
			var index := full_indices[candidate + k]
			height += full_vertices[index].y * weights[j][k]
			normal += Vector3(full_attributes[index * 4], full_attributes[index * 4 + 1], full_attributes[index * 4 + 2]) * weights[j][k]
		var tile_index := tile_indices[offset + j] * 4
		var actual := Vector3(attributes[tile_index], attributes[tile_index + 1], attributes[tile_index + 2])
		_max_height = maxf(_max_height, absf(height - points[j].y))
		_max_normal = maxf(_max_normal, normal.distance_to(actual))
	return true


func _negative_controls() -> bool:
	var saved := _full
	var height_error := _max_height
	var normal_error := _max_normal
	var indices: PackedInt32Array = saved[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = saved[Mesh.ARRAY_VERTEX]
	var custom: PackedFloat32Array = saved[Mesh.ARRAY_CUSTOM0]
	var points := PackedVector3Array()
	var attributes := PackedFloat32Array()
	for j in 3:
		points.append(vertices[indices[j]])
		for k in 4:
			attributes.append(custom[indices[j] * 4 + k])
	_full = saved.duplicate()
	vertices[indices[0]].y += 1.0
	_full[Mesh.ARRAY_VERTEX] = vertices
	_max_height = 0.0
	_compare_triangle(points, attributes, PackedInt32Array([0, 1, 2]), 0, 0, 0.0)
	var rejected_height := _max_height > 0.99
	_full[Mesh.ARRAY_VERTEX] = saved[Mesh.ARRAY_VERTEX]
	custom[indices[0] * 4] += 0.2
	_full[Mesh.ARRAY_CUSTOM0] = custom
	_max_normal = 0.0
	_compare_triangle(points, attributes, PackedInt32Array([0, 1, 2]), 0, 0, 0.0)
	var rejected_normal := _max_normal > 0.19
	points[0].x += 100000.0
	var rejected_outside := not _compare_triangle(points, attributes, PackedInt32Array([0, 1, 2]), 0, 0, 0.0)
	_full = saved
	_max_height = height_error
	_max_normal = normal_error
	print("[Native surface negative controls] height=%s normal=%s outside=%s" % [rejected_height, rejected_normal, rejected_outside])
	return rejected_height and rejected_normal and rejected_outside
