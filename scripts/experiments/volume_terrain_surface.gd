extends RefCounted
## 固定三角曲面：各档瓦片只裁剪同一曲面，不重新拟合高度。
var rect: Rect2
var grid_size: int
var step: Vector2
var heights: PackedFloat32Array
var cover: PackedFloat32Array
var _normals := PackedVector3Array()
var _side: int
var _refinement: Dictionary = {}
var _adaptive_heights: Dictionary = {}
var _adaptive_normals: Dictionary = {}


func _init(bounds: Rect2, size: int, source_heights: PackedFloat32Array, source_cover: PackedFloat32Array, regions: Array = []) -> void:
	rect = bounds
	grid_size = size
	heights = source_heights
	cover = source_cover
	_side = (size - 1) / 2 + 1
	step = rect.size / float(_side - 1)
	_normals.resize(_side * _side)
	for z in _side:
		for x in _side:
			var lo_x := maxi(0, x - 1)
			var hi_x := mini(_side - 1, x + 1)
			var lo_z := maxi(0, z - 1)
			var hi_z := mini(_side - 1, z + 1)
			var dx := (_value(heights, hi_x, z) - _value(heights, lo_x, z)) / ((hi_x - lo_x) * step.x)
			var dz := (_value(heights, x, hi_z) - _value(heights, x, lo_z)) / ((hi_z - lo_z) * step.y)
			_normals[z * _side + x] = Vector3(-dx, 1, -dz).normalized()
	if not regions.is_empty():
		_build_refinement(regions)


func _world_node(node: Vector2i) -> Vector2:
	return rect.position + Vector2(node) * 0.5 * step


func _insert_node(node: Vector2i, raw: bool) -> Vector2:
	var point := _world_node(node)
	var height := heights[node.y * grid_size + node.x] if raw else _sample_scalar(point, heights)
	if _adaptive_heights.has(point):
		assert(absf(_adaptive_heights[point] - height) < 0.01, "shared refinement node disagrees")
	_adaptive_heights[point] = height
	return point


func _build_refinement(regions: Array) -> void:
	var fine := {}
	var affected := {}
	var offsets := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for region: Rect2i in regions:
		for z in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				assert(x >= 0 and z >= 0 and x < _side - 1 and z < _side - 1)
				var cell := Vector2i(x, z)
				fine[cell] = true
				affected[cell] = true
				for offset: Vector2i in offsets:
					var neighbor := cell + offset
					if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < _side - 1 and neighbor.y < _side - 1:
						affected[neighbor] = true
	for cell: Vector2i in affected:
		var origin := cell * 2
		var triangles: Array[PackedVector2Array] = []
		if fine.has(cell):
			for z in 2:
				for x in 2:
					var a := _insert_node(origin + Vector2i(x, z), true)
					var b := _insert_node(origin + Vector2i(x + 1, z), true)
					var c := _insert_node(origin + Vector2i(x + 1, z + 1), true)
					var d := _insert_node(origin + Vector2i(x, z + 1), true)
					triangles.append(PackedVector2Array([a, b, c]))
					triangles.append(PackedVector2Array([a, c, d]))
		else:
			var corners := [origin, origin + Vector2i(2, 0), origin + Vector2i(2, 2), origin + Vector2i(0, 2)]
			var ring := PackedVector2Array()
			for side in 4:
				ring.append(_insert_node(corners[side], true))
				if fine.has(cell + offsets[side]):
					var midpoint: Vector2i = (corners[side] + corners[(side + 1) % 4]) / 2
					ring.append(_insert_node(midpoint, true))
			var center := _insert_node(origin + Vector2i.ONE, false)
			for i in ring.size():
				triangles.append(PackedVector2Array([center, ring[i], ring[(i + 1) % ring.size()]]))
		_refinement[cell] = triangles
	# 用同一新高度面估计共享顶点法线；普通格边也读此覆盖，避免接缝两侧不同光照。
	for point: Vector2 in _adaptive_heights:
		var dx := (height_at(point + Vector2(step.x * 0.5, 0)) - height_at(point - Vector2(step.x * 0.5, 0))) / step.x
		var dz := (height_at(point + Vector2(0, step.y * 0.5)) - height_at(point - Vector2(0, step.y * 0.5))) / step.y
		_adaptive_normals[point] = Vector3(-dx, 1, -dz).normalized()


func cell_triangles(x: int, z: int) -> Array[PackedVector2Array]:
	var key := Vector2i(x, z)
	if _refinement.has(key):
		return _refinement[key]
	var a := _world_node(key * 2)
	var b := _world_node((key + Vector2i.RIGHT) * 2)
	var c := _world_node((key + Vector2i.ONE) * 2)
	var d := _world_node((key + Vector2i.DOWN) * 2)
	return [PackedVector2Array([a, b, c]), PackedVector2Array([a, c, d])]


static func triangle_weights(point: Vector2, triangle: PackedVector2Array) -> Vector3:
	var ab := triangle[1] - triangle[0]
	var ac := triangle[2] - triangle[0]
	var ap := point - triangle[0]
	var divisor := ab.cross(ac)
	var b := ap.cross(ac) / divisor
	var c := ab.cross(ap) / divisor
	return Vector3(1.0 - b - c, b, c)


func _coordinates(point: Vector2) -> Vector4:
	var uv := ((point - rect.position) / step).clamp(Vector2.ZERO, Vector2.ONE * (_side - 1))
	var x := mini(int(uv.x), _side - 2)
	var z := mini(int(uv.y), _side - 2)
	return Vector4(x, z, uv.x - x, uv.y - z)


func _value(values: PackedFloat32Array, x: int, z: int) -> float:
	return values[z * 2 * grid_size + x * 2]


func _sample_scalar(point: Vector2, values: PackedFloat32Array) -> float:
	var c := _coordinates(point)
	var x := int(c.x)
	var z := int(c.y)
	var a := _value(values, x, z)
	var d := _value(values, x + 1, z + 1)
	if c.z >= c.w:
		return a * (1 - c.z) + _value(values, x + 1, z) * (c.z - c.w) + d * c.w
	return a * (1 - c.w) + d * c.z + _value(values, x, z + 1) * (c.w - c.z)


func height_at(point: Vector2) -> float:
	var at := _coordinates(point)
	var key := Vector2i(int(at.x), int(at.y))
	if _refinement.has(key):
		for triangle: PackedVector2Array in _refinement[key]:
			var w := triangle_weights(point, triangle)
			if minf(w.x, minf(w.y, w.z)) >= -0.00001:
				return _adaptive_heights[triangle[0]] * w.x + _adaptive_heights[triangle[1]] * w.y + _adaptive_heights[triangle[2]] * w.z
	return _sample_scalar(point, heights)


func normal_at(point: Vector2) -> Vector3:
	# 保留线性插值，不在裁边顶点提前归一化，避免改变片元内插曲面。
	var c := _coordinates(point)
	var key := Vector2i(int(c.x), int(c.y))
	if _refinement.has(key):
		for triangle: PackedVector2Array in _refinement[key]:
			var w := triangle_weights(point, triangle)
			if minf(w.x, minf(w.y, w.z)) >= -0.00001:
				return _adaptive_normals[triangle[0]] * w.x + _adaptive_normals[triangle[1]] * w.y + _adaptive_normals[triangle[2]] * w.z
	var a := _node_normal(key)
	var d := _node_normal(key + Vector2i.ONE)
	if c.z >= c.w:
		return a * (1 - c.z) + _node_normal(key + Vector2i.RIGHT) * (c.z - c.w) + d * c.w
	return a * (1 - c.w) + d * c.z + _node_normal(key + Vector2i.DOWN) * (c.w - c.z)


func _node_normal(node: Vector2i) -> Vector3:
	return _adaptive_normals.get(_world_node(node * 2), _normals[node.y * _side + node.x])


static func clip_to_triangle(polygon: Array[Vector2], triangle: PackedVector2Array) -> Array[Vector2]:
	var result := polygon
	for edge in 3:
		if result.is_empty():
			break
		var a := triangle[edge]
		var direction := triangle[(edge + 1) % 3] - a
		var output: Array[Vector2] = []
		var previous := result[-1]
		var previous_side := direction.cross(previous - a)
		for point: Vector2 in result:
			var side := direction.cross(point - a)
			if (side >= 0) != (previous_side >= 0):
				output.append(previous.lerp(point, previous_side / (previous_side - side)))
			if side >= 0:
				output.append(point)
			previous = point
			previous_side = side
		result = output
	return result


static func _clip_polygon(polygon: Array[Vector2], bounds: Rect2) -> Array[Vector2]:
	var result := polygon
	for plane in 4:
		if result.is_empty():
			break
		var axis := plane / 2
		var lower := plane % 2 == 0
		var boundary: float = bounds.position[axis] if lower else bounds.end[axis]
		var output: Array[Vector2] = []
		var a: Vector2 = result[-1]
		var inside_a := a[axis] >= boundary if lower else a[axis] <= boundary
		for b: Vector2 in result:
			var inside_b := b[axis] >= boundary if lower else b[axis] <= boundary
			if inside_a != inside_b:
				# 两侧裁剪统一按小坐标到大坐标求交，避免反向 lerp 的末位差。
				var start := a if a[axis] < b[axis] else b
				var finish := b if a[axis] < b[axis] else a
				var point := start.lerp(finish, (boundary - start[axis]) / (finish[axis] - start[axis]))
				point[axis] = boundary
				output.append(point)
			if inside_b:
				output.append(b)
			a = b
			inside_a = inside_b
		result = output
	return result


func plane_mesh(bounds: Rect2, uv: Rect2, base_y: float, texture_bounds: Rect2 = Rect2()) -> ArrayMesh:
	if not texture_bounds.has_area():
		texture_bounds = bounds
	var first := Vector2i(((bounds.position - rect.position) / step).floor()).clamp(Vector2i.ZERO, Vector2i.ONE * (_side - 2))
	var last := Vector2i(((bounds.end - rect.position) / step).ceil()).clamp(Vector2i.ONE, Vector2i.ONE * (_side - 1))
	# 普通 Array 采用引用语义，避免 Packed 数组经参数传递时逐顶点触发 copy-on-write。
	var channels := {"vertices": [], "normals": [], "uvs": [], "colors": [], "surface": []}
	var lookup := {}
	var indices := PackedInt32Array()
	for z in range(first.y, last.y):
		for x in range(first.x, last.x):
			var a := rect.position + Vector2(x, z) * step
			var c := rect.position + Vector2(x + 1, z + 1) * step
			var whole := a.x >= bounds.position.x and a.y >= bounds.position.y and c.x <= bounds.end.x and c.y <= bounds.end.y
			for source_triangle: PackedVector2Array in cell_triangles(x, z):
				var source: Array[Vector2] = []
				source.assign(source_triangle)
				var polygon := source if whole else _clip_polygon(source, bounds)
				for i in range(1, polygon.size() - 1):
					var ab := polygon[i] - polygon[0]
					var ac := polygon[i + 1] - polygon[0]
					var signed_area: float = float(ab.x) * float(ac.y) - float(ab.y) * float(ac.x)
					# 保留共边角点处的合法微小三角形；面积阈值会把瓦片角落剪出缺口。
					if signed_area <= 0.0:
						continue
					for point: Vector2 in [polygon[0], polygon[i], polygon[i + 1]]:
						if not lookup.has(point):
							lookup[point] = channels.vertices.size()
							channels.vertices.append(Vector3(point.x, base_y + height_at(point), point.y))
							var normal := normal_at(point)
							channels.normals.append(normal.normalized())
							channels.uvs.append(uv.position + (point - texture_bounds.position) / texture_bounds.size * uv.size)
							channels.colors.append(Color(_sample_scalar(point, cover), 0, 0))
							channels.surface.append_array([normal.x, normal.y, normal.z, _sample_scalar(point, cover)])
						indices.append(lookup[point])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(channels.vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(channels.normals)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(channels.uvs)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(channels.colors)
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_CUSTOM0] = PackedFloat32Array(channels.surface)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return mesh
