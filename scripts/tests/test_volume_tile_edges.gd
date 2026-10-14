extends RefCounted
## 全部实际网格共边与源UV合同；不以屏幕截图替代几何证明。
const Archive := preload("res://scripts/experiments/volume_terrain_archive.gd")
const Relief := preload("res://scripts/experiments/volume_desert_relief.gd")
var _pass := 0
var _fail := 0


func run() -> bool:
	var relief := Relief.new()
	_check(relief.archive != null, "canonical offline archive is current")
	if relief.archive == null:
		return false
	var layouts := Archive.tile_layouts()
	var max_shift := 0.0
	var uv_error := 0.0
	var source_guard := true
	for key: String in layouts:
		var entry: Dictionary = layouts[key]
		var source: Rect2 = entry.bounds
		var rendered: Rect2 = entry.render_bounds
		var start_delta := (rendered.position - source.position).abs()
		var end_delta := (rendered.end - source.end).abs()
		max_shift = maxf(max_shift, maxf(maxf(start_delta.x, start_delta.y), maxf(end_delta.x, end_delta.y)))
		source_guard = source_guard and relief.presentation_bounds(key, source, entry.uv, entry.base_y) == rendered
		source_guard = source_guard and relief.presentation_bounds(key, source.grow(1), entry.uv, entry.base_y) == source.grow(1)
		source_guard = source_guard and relief.presentation_bounds(key, source, Rect2(), entry.base_y) == source
		var arrays: Array = relief.archive.entries[key].mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i in vertices.size():
			var world := Vector2(vertices[i].x, vertices[i].z)
			var expected: Vector2 = entry.uv.position + (world - source.position) / source.size * entry.uv.size
			uv_error = maxf(uv_error, uvs[i].distance_to(expected))
	_check(max_shift <= 0.004, "canonical clipping stays within 0.004 world pixels of original source")
	_check(uv_error == 0.0, "every archived vertex preserves original world-to-texture mapping exactly")
	_check(source_guard, "mismatched coordinates or gutter cannot adopt same-name canonical bounds")
	var pairs := 0
	var rect_mismatches := 0
	var mesh_mismatches := 0
	var compared_vertices := 0
	var examples: Array[String] = []
	for key: String in layouts:
		if key == "StrategicBasemap":
			continue
		var parts := key.split("_")
		var row := int(parts[1].substr(1))
		var column := int(parts[2].substr(1))
		for axis in 2:
			var other := "%s_r%02d_c%02d" % [parts[0], row + int(axis == 1), column + int(axis == 0)]
			if not layouts.has(other):
				continue
			pairs += 1
			var a: Rect2 = layouts[key].render_bounds
			var b: Rect2 = layouts[other].render_bounds
			if a.end[axis] != b.position[axis]:
				rect_mismatches += 1
			var edge_a := _mesh_edge(relief.archive.entries[key].mesh, axis, a.end[axis])
			var edge_b := _mesh_edge(relief.archive.entries[other].mesh, axis, b.position[axis])
			if edge_a.is_empty() or edge_a.size() != edge_b.size():
				mesh_mismatches += 1
				if examples.size() < 8:
					examples.append("%s -> %s size %d/%d" % [key, other, edge_a.size(), edge_b.size()])
			for coordinate: float in edge_a:
				compared_vertices += 1
				if not edge_b.has(coordinate) or edge_a[coordinate] != edge_b[coordinate]:
					mesh_mismatches += 1
					if examples.size() < 8:
						var nearest := INF
						var delta_y := INF
						for candidate: float in edge_b:
							if absf(candidate - coordinate) < nearest:
								nearest = absf(candidate - coordinate)
								delta_y = absf(float(edge_a[coordinate]) - float(edge_b[candidate]))
						examples.append("%s -> %s along=%.9f nearest_delta=%.9f height_delta=%.9f" % [key, other, coordinate, nearest, delta_y])
	_check(pairs == 256 and rect_mismatches == 0, "all 256 adjacent tile rectangles share exact boundaries")
	_check(compared_vertices > 1000 and mesh_mismatches == 0, "actual shared-edge vertices and heights match exactly on every adjacency")
	print("[Tile edges] pass=%d fail=%d pairs=%d vertices=%d rect_mismatches=%d mesh_mismatches=%d max_shift=%.9f uv_error=%.9f" % [
		_pass, _fail, pairs, compared_vertices, rect_mismatches, mesh_mismatches, max_shift, uv_error])
	for example: String in examples:
		print("[Tile edge mismatch] ", example)
	return _fail == 0


func _mesh_edge(mesh: ArrayMesh, axis: int, boundary: float) -> Dictionary:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var edge := {}
	for point: Vector3 in vertices:
		if (point.x if axis == 0 else point.z) == boundary:
			edge[point.z if axis == 0 else point.x] = point.y
	return edge


func _check(value: bool, label: String) -> void:
	if value:
		_pass += 1
	else:
		_fail += 1
		push_error("Tile edges: " + label)
