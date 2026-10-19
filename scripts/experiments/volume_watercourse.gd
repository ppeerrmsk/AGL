extends RefCounted
## 季节河道表现线沿唯一地形逐面裁分；不生成湖泊、不修改高程。
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Surface := preload("res://scripts/experiments/volume_terrain_surface.gd")
const WIDTH := 4.8
const LIFT := 0.12


static func build(surface: RefCounted, hydrography: Dictionary) -> Dictionary:
	var output := {"vertices": PackedVector3Array(), "uvs": PackedVector2Array(), "segments": [], "across": PackedVector2Array()}
	for river: Dictionary in hydrography.rivers:
		for path: Array in river.paths:
			var points := Geometry.points_from(path)
			var edges := Geometry.stroke_edges(points, WIDTH)
			if edges.is_empty():
				continue
			for i in range(edges[0].size() - 1):
				var d0: Vector2 = edges[1][i] - edges[0][i]
				var d1: Vector2 = edges[1][i+1] - edges[0][i+1]
				var start: int = output.vertices.size()
				_append_triangle(surface, PackedVector2Array([edges[0][i], edges[0][i+1], edges[1][i+1]]),
					Vector3(0, 0, 1), output, PackedVector2Array([d0,d1,d1]))
				_append_triangle(surface, PackedVector2Array([edges[0][i], edges[1][i+1], edges[1][i]]),
					Vector3(0, 1, 1), output, PackedVector2Array([d0,d1,d0]))
				output.segments.append({"way_id": river.way_id, "start": start,
					"count": output.vertices.size() - start, "a": points[i], "b": points[i+1]})
	return output


static func _append_triangle(surface: RefCounted, source: PackedVector2Array, source_uv: Vector3,
		output: Dictionary, across: PackedVector2Array) -> void:
	if absf((source[1] - source[0]).cross(source[2] - source[0])) < 0.0001:
		return
	var bounds := Rect2(source[0], Vector2.ZERO).expand(source[1]).expand(source[2])
	var rect: Rect2 = surface.rect
	var step: Vector2 = surface.step
	var side := Vector2i((rect.size / step).round()) - Vector2i.ONE
	var first := Vector2i(((bounds.position - rect.position) / step).floor()).clamp(Vector2i.ZERO, side)
	var last := Vector2i(((bounds.end - rect.position) / step).floor()).clamp(Vector2i.ZERO, side)
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var original: Array[Vector2] = [source[0], source[1], source[2]]
			var clipped := Surface._clip_polygon(original, Rect2(rect.position + Vector2(x, z) * step, step))
			if clipped.size() < 3:
				continue
			for terrain: PackedVector2Array in surface.cell_triangles(x, z):
				var polygon := Surface.clip_to_triangle(clipped, terrain)
				for i in range(1, polygon.size() - 1):
					if absf((polygon[i] - polygon[0]).cross(polygon[i+1] - polygon[0])) < 0.0001:
						continue
					for p: Vector2 in [polygon[0], polygon[i], polygon[i+1]]:
						var weights := Surface.triangle_weights(p, source)
						output.vertices.append(Vector3(p.x, surface.height_at(p) + LIFT, p.y))
						# UV.x仅标识河道墨色；UV.y仍是完整横向抗锯齿坐标。
						output.uvs.append(Vector2(1, clampf(weights.dot(source_uv), 0, 1)))
						output.across.append(across[0]*weights.x + across[1]*weights.y + across[2]*weights.z)
