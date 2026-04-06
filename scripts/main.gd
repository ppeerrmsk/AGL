extends Node2D

const ZOOM_MIN := 0.1
const ZOOM_MAX := 5.0
const ZOOM_STEP := 0.1
const GRID_SIZE := 200.0  ## 网格间距（像素）
const GRID_COLOR := Color(0.55, 0.55, 0.52, 0.25)

## 地形类型枚举
enum TerrainType { DEEP_OCEAN, OCEAN, COAST, LOWLAND, PLAINS, HILLS, HIGHLANDS, MOUNTAINS }

## 地形颜色 - 纸质航图风格，低对比度，米白/淡绿基调
const TERRAIN_COLORS := {
	TerrainType.DEEP_OCEAN: Color(0.76, 0.80, 0.78, 1.0),    # 深水
	TerrainType.OCEAN: Color(0.78, 0.82, 0.80, 1.0),          # 浅水
	TerrainType.COAST: Color(0.80, 0.83, 0.78, 1.0),          # 海岸
	TerrainType.LOWLAND: Color(0.82, 0.84, 0.77, 1.0),        # 低地
	TerrainType.PLAINS: Color(0.84, 0.85, 0.78, 1.0),         # 平原
	TerrainType.HILLS: Color(0.83, 0.82, 0.75, 1.0),          # 丘陵
	TerrainType.HIGHLANDS: Color(0.80, 0.78, 0.72, 1.0),      # 高地
	TerrainType.MOUNTAINS: Color(0.77, 0.75, 0.70, 1.0),      # 山脉
}

## 地形单元格大小（像素）
const TERRAIN_CELL := 400.0

## 噪声种子，用于生成可复现的地形
var terrain_seed: int = 42
var _noise: FastNoiseLite
var _cloud_noise: FastNoiseLite

@onready var camera: Camera2D = $Camera2D

var selected_aircraft: Array[Aircraft] = []
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var target_zoom: float = 1.0

var _hovered_aircraft: Aircraft = null
const HOVER_RADIUS := 30.0  ## 鼠标悬停判定半径（像素）

func _ready() -> void:
	target_zoom = camera.zoom.x
	_init_noise()
	_auto_select_player_aircraft()

func _init_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0006  # 低频率 → 大片连续的生态区域
	_noise.fractal_octaves = 2  # 少分形层 → 更平滑的过渡
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.3

	_cloud_noise = FastNoiseLite.new()
	_cloud_noise.seed = terrain_seed + 100
	_cloud_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cloud_noise.frequency = 0.0008
	_cloud_noise.fractal_octaves = 2

func _auto_select_player_aircraft() -> void:
	for child in get_children():
		if child is Aircraft and child.team == 0:
			child.selected = true
			selected_aircraft.append(child)
			break

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				target_zoom = clampf(target_zoom * (1.0 + ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				target_zoom = clampf(target_zoom * (1.0 - ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_click(event.global_position)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_on_right_click()
		MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed
			if event.pressed:
				drag_start = event.global_position

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if is_dragging:
		var delta := event.relative / camera.zoom
		camera.global_position -= delta
	_update_hover(event.global_position)

func _on_left_click(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	for ac in selected_aircraft:
		if is_instance_valid(ac):
			ac.target_position = world_pos

func _on_right_click() -> void:
	for ac in selected_aircraft:
		if is_instance_valid(ac):
			ac.target_position = Vector2.INF

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var viewport := get_viewport()
	var canvas_transform := viewport.get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos

func _process(delta: float) -> void:
	var current_zoom := camera.zoom.x
	var new_zoom := lerpf(current_zoom, target_zoom, delta * 10.0)
	camera.zoom = Vector2(new_zoom, new_zoom)
	_update_radar_locks(delta)
	queue_redraw()

func _update_hover(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	# 清除旧悬停
	if _hovered_aircraft and is_instance_valid(_hovered_aircraft):
		_hovered_aircraft.is_hovered = false
	_hovered_aircraft = null

	var best_dist := HOVER_RADIUS
	for child in get_children():
		if child is Aircraft:
			var d := world_pos.distance_to(child.global_position)
			if d < best_dist:
				best_dist = d
				_hovered_aircraft = child

	if _hovered_aircraft:
		_hovered_aircraft.is_hovered = true

func _update_radar_locks(delta: float) -> void:
	# 收集所有飞机
	var all_aircraft: Array[Aircraft] = []
	for child in get_children():
		if child is Aircraft:
			all_aircraft.append(child)

	# 重置锁定状态
	for ac in all_aircraft:
		ac.is_locked = false
		ac.locked_by.clear()

	# 对每架飞机，检查其雷达锥内的敌机
	for ac in all_aircraft:
		# 清理无效目标
		var keys_to_remove: Array = []
		for key in ac.radar_targets:
			if not is_instance_valid(key):
				keys_to_remove.append(key)
		for key in keys_to_remove:
			ac.radar_targets.erase(key)

		for other in all_aircraft:
			if other == ac or other.team == ac.team:
				continue

			if ac.is_in_radar_cone(other.global_position):
				# 在锥内：累加照射时间
				var prev: float = ac.radar_targets.get(other, 0.0)
				ac.radar_targets[other] = prev + delta
			else:
				# 不在锥内：清零
				ac.radar_targets.erase(other)

	# 根据累计时间判定锁定
	for ac in all_aircraft:
		var lock_time_val: float = ac.params.lock_time if ac.params else 3.0
		for target in ac.radar_targets:
			if ac.radar_targets[target] >= lock_time_val:
				var t: Aircraft = target
				t.is_locked = true
				t.locked_by.append(ac)

func _draw() -> void:
	_draw_terrain()
	_draw_grid()

## 根据噪声值映射地形类型
func _get_terrain_type(noise_val: float) -> TerrainType:
	if noise_val < -0.30:
		return TerrainType.DEEP_OCEAN
	elif noise_val < -0.12:
		return TerrainType.OCEAN
	elif noise_val < -0.02:
		return TerrainType.COAST
	elif noise_val < 0.10:
		return TerrainType.LOWLAND
	elif noise_val < 0.22:
		return TerrainType.PLAINS
	elif noise_val < 0.34:
		return TerrainType.HILLS
	elif noise_val < 0.46:
		return TerrainType.HIGHLANDS
	else:
		return TerrainType.MOUNTAINS

func _draw_terrain() -> void:
	var viewport_size := get_viewport_rect().size / camera.zoom
	var cam_pos := camera.global_position
	var half := viewport_size / 2.0

	var left := cam_pos.x - half.x
	var right := cam_pos.x + half.x
	var top := cam_pos.y - half.y
	var bottom := cam_pos.y + half.y

	# 按地形单元格绘制
	var start_x := snappedf(left, TERRAIN_CELL) - TERRAIN_CELL
	var start_y := snappedf(top, TERRAIN_CELL) - TERRAIN_CELL

	var cx := start_x
	while cx <= right + TERRAIN_CELL:
		var cy := start_y
		while cy <= bottom + TERRAIN_CELL:
			# 取单元格中心点的噪声值
			var center_x := cx + TERRAIN_CELL * 0.5
			var center_y := cy + TERRAIN_CELL * 0.5
			var noise_val := _noise.get_noise_2d(center_x, center_y)

			var terrain := _get_terrain_type(noise_val)
			var base_color: Color = TERRAIN_COLORS[terrain]

			# 用噪声微调颜色，增加自然感
			var variation := _noise.get_noise_2d(center_x * 2.3, center_y * 2.3) * 0.04
			var cell_color := Color(
				clampf(base_color.r + variation, 0.0, 1.0),
				clampf(base_color.g + variation, 0.0, 1.0),
				clampf(base_color.b + variation, 0.0, 1.0),
				base_color.a
			)

			draw_rect(Rect2(cx, cy, TERRAIN_CELL, TERRAIN_CELL), cell_color)

			# 薄雾叠加 - 极淡
			var cloud_val := _cloud_noise.get_noise_2d(center_x, center_y)
			if cloud_val > 0.25:
				var cloud_alpha := remap(cloud_val, 0.25, 0.7, 0.0, 0.08)
				cloud_alpha = clampf(cloud_alpha, 0.0, 0.08)
				draw_rect(Rect2(cx, cy, TERRAIN_CELL, TERRAIN_CELL), Color(1.0, 1.0, 0.98, cloud_alpha))

			cy += TERRAIN_CELL
		cx += TERRAIN_CELL

func _draw_grid() -> void:
	var viewport_size := get_viewport_rect().size / camera.zoom
	var cam_pos := camera.global_position
	var half := viewport_size / 2.0

	var left := cam_pos.x - half.x
	var right := cam_pos.x + half.x
	var top := cam_pos.y - half.y
	var bottom := cam_pos.y + half.y

	var start_x := snappedf(left, GRID_SIZE) - GRID_SIZE
	var start_y := snappedf(top, GRID_SIZE) - GRID_SIZE

	var x := start_x
	while x <= right + GRID_SIZE:
		draw_line(Vector2(x, top - GRID_SIZE), Vector2(x, bottom + GRID_SIZE), GRID_COLOR, 1.0)
		x += GRID_SIZE

	var y := start_y
	while y <= bottom + GRID_SIZE:
		draw_line(Vector2(left - GRID_SIZE, y), Vector2(right + GRID_SIZE, y), GRID_COLOR, 1.0)
		y += GRID_SIZE
