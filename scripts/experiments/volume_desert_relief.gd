extends RefCounted
## 表现层 DEM 与水岸；不向 MapGeography / 物理消费者暴露高度。
const DATA_PATH := "res://resources/maps/desert_volume_relief.json"
const HYDROGRAPHY_PATH := "res://resources/maps/desert_volume_hydrography.json"
const Watercourses := preload("res://scripts/experiments/volume_watercourse.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const LINE_SHADER := preload("res://resources/shaders/volume_map_line.gdshader")
const WATER_SHADER := preload("res://resources/shaders/volume_map_water.gdshader")
const Surface := preload("res://scripts/experiments/volume_terrain_surface.gd")
const Archive := preload("res://scripts/experiments/volume_terrain_archive.gd")
const COVER_LOD_LIFT := 0.20
# 源数据上界0.493，留出float32打包余量；不是光照误差保证。
const COVER_LOD_ERROR := 0.50
const RIDGE_REGIONS := [Rect2i(44, 51, 3, 3), Rect2i(15, 42, 3, 3), Rect2i(68, 18, 3, 3)]
var archive: Resource
var archive_hits := 0
var archive_misses := 0
var surface: RefCounted
var data: Dictionary
var hydrography: Dictionary
var rect: Rect2
var grid_size: int
var heights: PackedFloat32Array
var cover: PackedFloat32Array
var grid_step: Vector2
var _layouts: Dictionary


func _init(use_archive: bool = true) -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	hydrography = JSON.parse_string(FileAccess.get_file_as_string(HYDROGRAPHY_PATH))
	var r: Array = data.world_rect
	rect = Rect2(r[0], r[1], r[2], r[3])
	grid_size = int(data.grid_size)
	heights = PackedFloat32Array(data.heights)
	cover = PackedFloat32Array(data.cover)
	grid_step = rect.size / float(grid_size - 1)
	assert(heights.size() == grid_size * grid_size)
	surface = Surface.new(rect, grid_size, heights, cover, RIDGE_REGIONS)
	_layouts = Archive.tile_layouts()
	if use_archive:
		bind_archive(false)


func bind_archive(tactical: bool) -> void:
	# 真实风格在ground.setup才明确；数值查询和enable_relief不预读另一档。
	archive = null
	var path := Archive.TACTICAL_PATH if tactical else Archive.PATH
	if ResourceLoader.exists(path):
		var candidate: Resource = load(path)
		if candidate is Archive and candidate.is_current(tactical):
			archive = candidate
	_layouts = archive.entries if archive != null else Archive.tile_layouts()


func height_at(point: Vector2) -> float:
	return surface.height_at(point)


func normal_at(point: Vector2) -> Vector3:
	return surface.normal_at(point)


func plane_mesh(bounds: Rect2, uv: Rect2, base_y: float, texture_bounds: Rect2 = Rect2()) -> ArrayMesh:
	return surface.plane_mesh(bounds, uv, base_y, texture_bounds)


func presentation_mesh(key: String, bounds: Rect2, uv: Rect2, base_y: float) -> ArrayMesh:
	if archive != null:
		var mesh: ArrayMesh = archive.matching_mesh(key, bounds, uv, base_y)
		if mesh != null:
			archive_hits += 1
			return mesh
	archive_misses += 1
	return plane_mesh(presentation_bounds(key, bounds, uv, base_y), uv, base_y, bounds)


func presentation_bounds(key: String, bounds: Rect2, uv: Rect2, base_y: float) -> Rect2:
	var entry: Dictionary = _layouts.get(key, {})
	if entry.is_empty() or entry.bounds != bounds or entry.uv != uv or entry.base_y != base_y:
		return bounds
	return entry.render_bounds


func make_details(tactical: bool = false) -> Node3D:
	if archive != null and archive.tactical_profile == tactical:
		return archive.details.instantiate() as Node3D
	var root := Node3D.new()
	root.name = "Relief_Water_Vegetation"
	var water_builder := Geometry.new()
	for polygon: Array in hydrography.water_quads:
		var points: Array[Vector3] = []
		for point: Array in polygon:
			var p := Vector2(point[0], point[1])
			points.append(Vector3(p.x, 0.6, p.y))
		for triangle: Vector3i in [Vector3i(0, 1, 2), Vector3i(0, 2, 3)]:
			var a := points[triangle.x]
			var b := points[triangle.y]
			var c := points[triangle.z]
			if (b - a).cross(c - a).length_squared() > 0.0001:
				water_builder.triangle(a, b, c, Color.WHITE)
	var water := MeshInstance3D.new()
	water.name = "Source_Water_EvenOdd_Fill"
	water.mesh = water_builder.mesh()
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var water_material := ShaderMaterial.new()
	water_material.shader = WATER_SHADER
	water_material.render_priority = -70
	water.material_override = water_material
	root.add_child(water)
	var line_vertices := PackedVector3Array()
	var line_uvs := PackedVector2Array()
	for contour_index: int in hydrography.retained_contours:
		var contour: Array = data.water_contours[contour_index]
		var edges := Geometry.stroke_edges(Geometry.points_from(contour), 4.8, true)
		if edges.is_empty():
			continue
		for i in range(edges[0].size() - 1):
			var points := [edges[0][i], edges[0][i + 1], edges[1][i + 1], edges[1][i]]
			for k in [0, 1, 2, 0, 2, 3]:
				var p: Vector2 = points[k]
				# 水面固定0.6；轮廓必须同高，不能独自爬坡形成干地浮线。
				line_vertices.append(Vector3(p.x, 0.8, p.y))
				line_uvs.append(Vector2(0, 0 if k < 2 else 1))
	var rivers := Watercourses.build(surface, hydrography)
	line_vertices.append_array(rivers.vertices)
	line_uvs.append_array(rivers.uvs)
	# 只给季节河道保留共享接头横向向量，旧岸线不参与最小屏幕覆盖。
	var line_across := PackedVector2Array()
	line_across.resize(line_vertices.size() - rivers.vertices.size())
	line_across.append_array(rivers.across)
	root.set_meta("retained_shorelines", hydrography.retained_contours.size())
	root.set_meta("watercourse_count", hydrography.rivers.size())
	root.set_meta("watercourse_segments", rivers.segments.size())
	root.set_meta("watercourse_triangles", rivers.vertices.size() / 3)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = line_vertices
	arrays[Mesh.ARRAY_TEX_UV] = line_uvs
	arrays[Mesh.ARRAY_TEX_UV2] = line_across
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var line := MeshInstance3D.new()
	line.name = "Source_Water_Contours"
	line.mesh = mesh
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var line_material := ShaderMaterial.new()
	line_material.shader = LINE_SHADER
	line_material.set_shader_parameter("pixel_width_enabled", tactical)
	line_material.render_priority = -60
	line.material_override = line_material
	root.add_child(line)
	# 16 个固定地域批次，最多 1200 灌丛簇；无逐株节点、tick、透明叶片或风动画。
	var clusters := {}
	var scrub_vertices := {}
	for plant: Array in data.vegetation:
		var p := Vector2(plant[0], plant[1])
		var cell := Vector2i(((p - rect.position) / rect.size * 4).floor())
		if not clusters.has(cell):
			clusters[cell] = Geometry.new()
		var builder: RefCounted = clusters[cell]
		var size := float(plant[3])
		var offsets := [Vector2(-48, -6), Vector2(-28, 9), Vector2(-11, -10), Vector2(8, 8), Vector2(26, -7), Vector2(45, 4), Vector2(2, 27)]
		var scales := [0.70, 0.95, 1.10, 0.85, 1.0, 0.65, 0.75]
		for index in offsets.size():
			var center: Vector2 = p + offsets[index].rotated(float(plant[4])) * size
			var crown_size: float = size * scales[index]
			# 低矮旱生草灌；按本地曲面计高度，不放大成远景树冠。
			var crown := Vector3(center.x, height_at(center) + 0.45 * crown_size, center.y)
			var base_points := PackedVector3Array()
			for j in 3:
				var angle := TAU * float(j) / 3
				var pa := center + Vector2(cos(angle), sin(angle)) * 1.4 * crown_size
				var a := Vector3(pa.x, height_at(pa), pa.y)
				base_points.append(a)
			for j in 3:
				builder.triangle(base_points[j], crown, base_points[(j + 1) % 3], Color("77704e") if j % 2 == 0 else Color("8a805a"))
		scrub_vertices[cell] = int(scrub_vertices.get(cell, 0)) + 63
	for outcrop: Array in data.outcrops:
		if tactical:
			break # 原始记录及source完整保留；军事风格不叠加散落装饰岩体。
		var p := Vector2(outcrop[0], outcrop[1])
		var cell := Vector2i(((p - rect.position) / rect.size * 4).floor())
		if not clusters.has(cell):
			clusters[cell] = Geometry.new()
		_add_outcrop(clusters[cell], outcrop)
	var material := Geometry.material()
	for cell: Vector2i in clusters:
		var part := MeshInstance3D.new()
		part.name = "Scrub_%d_%d" % [cell.x, cell.y]
		part.mesh = clusters[cell].mesh()
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.set_meta("scrub_vertices", int(scrub_vertices.get(cell, 0)))
		part.set_meta("cover_near_mesh", part.mesh)
		part.set_meta("cover_far_mesh", make_cover_lod(clusters[cell], int(scrub_vertices.get(cell, 0))))
		root.add_child(part)
	root.set_meta("vegetation_count", data.vegetation.size())
	root.set_meta("water_contours", data.water_contours.size())
	root.set_meta("outcrop_count", 0 if tactical else data.outcrops.size())
	return root


static func make_cover_lod(near_builder: RefCounted, scrub_vertices: int) -> ArrayMesh:
	# 离线构建和失效回退共用；原9顶点小冠体降为3顶点，岩体通道逐项保留。
	# 两档都由同一原始数组打包一次，不能将已量化的法线解码后再次量化。
	var points: PackedVector3Array = near_builder._vertices
	var normals: PackedVector3Array = near_builder._normals
	var colors: PackedColorArray = near_builder._colors
	assert(scrub_vertices % 9 == 0)
	var builder := Geometry.new()
	for i in range(0, scrub_vertices, 9):
		var normal := Vector3.ZERO
		var color := Color(0, 0, 0, 0)
		var total_area := 0.0
		for face in 3:
			var j := i + face * 3
			var area := (points[j + 1] - points[j]).cross(points[j + 2] - points[j]).length()
			normal += normals[j] * area
			color += colors[j] * area
			total_area += area
		# 平均原面属性；不借助新透明材质或重复叠绘来掩盖切档。
		normal = normal.normalized()
		color /= total_area
		for offset in [0, 1, 4]:
			builder._vertices.append(points[i + offset] + Vector3.UP * COVER_LOD_LIFT)
			builder._normals.append(normal)
			builder._colors.append(color)
	builder._vertices.append_array(points.slice(scrub_vertices))
	builder._normals.append_array(normals.slice(scrub_vertices))
	builder._colors.append_array(colors.slice(scrub_vertices))
	return builder.mesh()


func _add_outcrop(builder: RefCounted, record: Array) -> void:
	var first_vertex: int = builder._vertices.size()
	# 五个不对称截面形成钝端岩层；全部保持原保护椭圆与连续贴坡。
	var center := Vector2(record[0], record[1])
	var rotation := float(record[2])
	var points := outcrop_profile(record)
	for i in points.size():
		var point := points[i]
		var p := center + Vector2(point.x * float(record[3]), point.z * float(record[4])).rotated(rotation)
		points[i] = Vector3(p.x, point.y * float(record[5]), p.y)
	var colors := [Color("5b523d"), Color("65513d"), Color("5b523d")]
	for i in 4:
		for j in 3:
			var at := i * 4 + j
			_add_surface_triangle(builder, points[at], points[at + 1], points[at + 5], colors[j])
			_add_surface_triangle(builder, points[at], points[at + 5], points[at + 4], colors[j])
	# COLOR.a 是不透明装饰材质的岩面混合权重，几何与法线完全不变。
	for i in range(first_vertex, builder._vertices.size()):
		var vertex: Vector3 = builder._vertices[i]
		var rise := vertex.y - height_at(Vector2(vertex.x, vertex.z))
		var color: Color = builder._colors[i]
		color.a = 1.0 - 0.70 * smoothstep(0.0, float(record[5]) * 0.35, rise)
		builder._colors[i] = color


static func outcrop_profile(record: Array) -> PackedVector3Array:
	# 归一化局部坐标：XZ在单位圆内，Y为相对原H。位置相位不触碰全局随机状态。
	var phase := float(record[0]) * 0.017 + float(record[1]) * 0.023 + float(record[2]) * 3.0
	var result := PackedVector3Array()
	var stations := [-0.86, -0.43, 0.0, 0.44, 0.85]
	for i in 5:
		var x: float = stations[i]
		var envelope := sqrt(1.0 - x * x)
		var left := -envelope * (0.72 + 0.24 * (0.5 + 0.5 * sin(phase + i * 1.71)))
		var right := envelope * (0.68 + 0.26 * (0.5 + 0.5 * cos(phase + i * 2.13)))
		var first := 0.30 + 0.08 * sin(phase + i)
		var second := 0.67 + 0.07 * cos(phase + i)
		var first_height := 0.32 + 0.44 * (0.5 + 0.5 * sin(phase * 0.7 + i * 1.9))
		var second_height := 0.26 + 0.42 * (0.5 + 0.5 * cos(phase * 0.9 + i * 1.4))
		if i == 0 or i == 4:
			first_height = 0.0
			second_height = 0.0
		result.append(Vector3(x, 0, left))
		result.append(Vector3(x, first_height, lerpf(left, right, first)))
		result.append(Vector3(x, second_height, lerpf(left, right, second)))
		result.append(Vector3(x, 0, right))
	return result


func _add_surface_triangle(builder: RefCounted, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# 输入 Y 是局部增高。沿唯一地表的格边/对角切开后相加，面内也不会穿坡。
	var pa := Vector2(a.x, a.z)
	var pb := Vector2(b.x, b.z)
	var pc := Vector2(c.x, c.z)
	var bounds := Rect2(pa, Vector2.ZERO).expand(pb).expand(pc)
	var step: Vector2 = surface.step
	var first := Vector2i(((bounds.position - rect.position) / step).floor())
	var last := Vector2i(((bounds.end - rect.position) / step).floor())
	var denominator := (pb - pa).cross(pc - pa)
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var origin := rect.position + Vector2(x, z) * step
			var source: Array[Vector2] = [pa, pb, pc]
			var clipped := Surface._clip_polygon(source, Rect2(origin, step))
			if clipped.size() < 3:
				continue
			for triangle: PackedVector2Array in surface.cell_triangles(x, z):
				var polygon := Surface.clip_to_triangle(clipped, triangle)
				for i in range(1, polygon.size() - 1):
					# 小于 0.01 px² 的裁边碎片在世界浮点精度下不稳定；覆盖误差另有严格回归。
					if (polygon[i] - polygon[0]).cross(polygon[i + 1] - polygon[0]) >= -0.02:
						continue
					var vertices: Array[Vector3] = []
					for p: Vector2 in [polygon[0], polygon[i], polygon[i + 1]]:
						var wb := (p - pa).cross(pc - pa) / denominator
						var wc := (pb - pa).cross(p - pa) / denominator
						var rise := maxf(0, a.y * (1 - wb - wc) + b.y * wb + c.y * wc)
						vertices.append(Vector3(p.x, height_at(p) + rise, p.y))
					builder.triangle(vertices[0], vertices[1], vertices[2], color)
