extends RefCounted
## 四个静态背景区域；只读地理轮廓，不创建玩法建筑或逐栋节点。
const PATH := "res://resources/maps/desert_tactical_context.json"
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const SHADER := preload("res://resources/shaders/volume_desert_tactical_structure.gdshader")
const TRIANGLE_BUDGET := 40000
# 背景聚落低于主体厂房的视觉权重；保留完整轮廓与墙高，不增噪点或抽删楼体。
# 使用明确的网格整数色板，避免浮点值写入颜色通道后发生隐式取整。
const ROOF := Color("b9b1a0")
const WALL := Color("797466")
const ROAD := Color("73786f")


static func is_enabled(map_key: String) -> bool:
	# 正常沙漠默认使用克制风格；source/off等显式值保留原图诊断回退。
	return map_key == "desert" and OS.get_environment("AGL_DESERT_STYLE") in ["", "tactical"]


static func build(relief: RefCounted) -> Array[MeshInstance3D]:
	var job := begin_build(relief)
	while not step_build(job, 1000000):
		pass
	return finish_build(job)


## 只保存资源与数值；取消分帧作业时没有未挂树节点需要额外释放。
static func begin_build(relief: RefCounted) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var counts: Dictionary = data.source.counts
	assert(int(counts.roof_triangles) + int(counts.wall_triangles) + int(counts.road_triangles) <= TRIANGLE_BUDGET)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("native_palette", true)
	return {"data": data, "cell_keys": data.cells.keys(), "index": 0, "cursor": 0,
		"near": Geometry.new(), "far": Geometry.new(), "heights": {}, "error": 0.0,
		"relief": relief, "material": material, "regions": [], "done": false}


static func step_build(job: Dictionary, budget_us: int = 4000) -> bool:
	var deadline := Time.get_ticks_usec() + budget_us
	while not job.done:
		var key: String = job.cell_keys[job.index]
		var cell: Dictionary = job.data.cells[key]
		var near: RefCounted = job.near
		var far: RefCounted = job.far
		var height_cache: Dictionary = job.heights
		var relief: RefCounted = job.relief
		if job.cursor < cell.buildings.size():
			var building: Dictionary = cell.buildings[job.cursor]
			var footprint := Geometry.points_from(building.footprint)
			var base := -INF
			var minimum := INF
			var area := 0.0
			for i in footprint.size():
				var point := footprint[i]
				var height := _height(point, relief, height_cache)
				base = maxf(base, height)
				minimum = minf(minimum, height)
				area += point.cross(footprint[(i + 1) % footprint.size()])
			var top := base + float(building.height_m) * CombatUnit.PIXELS_PER_METER
			job.error = maxf(job.error, top - minimum)
			_roofs(near, building.roof, top, ROOF)
			_roofs(far, building.roof, top, ROOF)
			if area > 0.0:
				footprint.reverse()
			for i in footprint.size():
				var a := footprint[i]
				var b := footprint[(i + 1) % footprint.size()]
				near.quad(Vector3(a.x, _height(a, relief, height_cache), a.y),
					Vector3(b.x, _height(b, relief, height_cache), b.y),
					Vector3(b.x, top, b.y), Vector3(a.x, top, a.y), WALL)
		elif (job.cursor - cell.buildings.size()) * 3 < cell.roads.size():
			var i: int = (job.cursor - cell.buildings.size()) * 3
			var points: Array[Vector3] = []
			for j in 3:
				var raw: Array = cell.roads[i + j]
				var point := Vector2(raw[0], raw[1])
				points.append(Vector3(point.x, _height(point, relief, height_cache) + 0.04, point.y))
			_up_triangle(near, points[0], points[1], points[2], ROAD)
			_up_triangle(far, points[0], points[1], points[2], ROAD)
		else:
			job.regions.append({"key": key, "near": near.mesh(), "far": far.mesh(), "error": job.error})
			job.index += 1
			job.cursor = -1
			job.near = Geometry.new()
			job.far = Geometry.new()
			job.heights = {}
			job.error = 0.0
			job.done = job.index >= job.cell_keys.size()
		job.cursor += 1
		if Time.get_ticks_usec() >= deadline:
			break
	return job.done


static func finish_build(job: Dictionary) -> Array[MeshInstance3D]:
	assert(job.done, "never expose partially built district geometry")
	var regions: Array[MeshInstance3D] = []
	for record: Dictionary in job.regions:
		var node := MeshInstance3D.new()
		node.name = "TacticalContext_" + String(record.key)
		node.mesh = record.near
		node.material_override = job.material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("context_near_mesh", node.mesh)
		node.set_meta("context_far_mesh", record.far)
		node.set_meta("context_height_error", record.error)
		node.set_meta("context_far", false)
		regions.append(node)
	return regions


static func _height(point: Vector2, relief: RefCounted, cache: Dictionary) -> float:
	if not cache.has(point):
		cache[point] = relief.height_at(point)
	return float(cache[point])


static func _roofs(builder: RefCounted, points: Array, height: float, color: Color) -> void:
	for i in range(0, points.size(), 3):
		_up_triangle(builder, Vector3(points[i][0], height, points[i][1]),
			Vector3(points[i + 1][0], height, points[i + 1][1]),
			Vector3(points[i + 2][0], height, points[i + 2][1]), color)


static func _up_triangle(builder: RefCounted, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).y < 0:
		builder.triangle(a, c, b, color)
	else:
		builder.triangle(a, b, c, color)
