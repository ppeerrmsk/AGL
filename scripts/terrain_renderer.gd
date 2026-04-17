class_name TerrainRenderer
extends Node2D

## 地形/网格/云层绘制（沙盒和生存模式共享）
## 作为子节点添加到场景中，自动绘制地形。
## 用法：
##   var terrain := TerrainRenderer.new()
##   add_child(terrain)
##   terrain.setup(camera)

## 地形类型枚举
enum TerrainType { DEEP_OCEAN, OCEAN, COAST, LOWLAND, PLAINS, HILLS, HIGHLANDS, MOUNTAINS }

## 地形颜色 - 纸质航图风格，低对比度，米白/淡绿基调
const TERRAIN_COLORS := {
	TerrainType.DEEP_OCEAN: Color(0.86, 0.90, 0.91, 1.0),    # 深水（淡蓝灰）
	TerrainType.OCEAN: Color(0.89, 0.92, 0.92, 1.0),          # 浅水
	TerrainType.COAST: Color(0.84, 0.88, 0.78, 1.0),          # 海岸（青绿过渡）
	TerrainType.LOWLAND: Color(0.78, 0.85, 0.70, 1.0),        # 低地（淡鼠尾草绿）
	TerrainType.PLAINS: Color(0.75, 0.82, 0.66, 1.0),         # 平原（柔和草绿）
	TerrainType.HILLS: Color(0.72, 0.78, 0.62, 1.0),          # 丘陵（橄榄绿）
	TerrainType.HIGHLANDS: Color(0.70, 0.73, 0.58, 1.0),      # 高地（暗橄榄）
	TerrainType.MOUNTAINS: Color(0.68, 0.68, 0.55, 1.0),      # 山脉（橄榄褐）
}

## 地形档位分界阈值（与 _get_terrain_type 保持一致）
const TIER_THRESHOLDS := [-0.30, -0.12, -0.02, 0.10, 0.22, 0.34, 0.46]
const TIER_ORDER := [
	TerrainType.DEEP_OCEAN, TerrainType.OCEAN, TerrainType.COAST,
	TerrainType.LOWLAND, TerrainType.PLAINS, TerrainType.HILLS,
	TerrainType.HIGHLANDS, TerrainType.MOUNTAINS,
]
## 分界两侧混色半宽；在海/岸分界用更宽的过渡，避免硬边
const BLEND_WIDTH := 0.035
const COAST_BLEND_WIDTH := 0.07

## 地形单元格大小（像素）
const TERRAIN_CELL := 400.0

## 网格常量
const GRID_SIZE := 200.0
const GRID_COLOR := Color(0.55, 0.55, 0.52, 0.25)

## 由父场景注入的相机引用
var camera: Camera2D

## 噪声配置（可在 setup 前覆盖以实现不同地图风格）
var terrain_seed: int = 42
var cloud_seed: int = 142
var terrain_frequency: float = 0.0006
var cloud_frequency: float = 0.0008

var _noise: FastNoiseLite
var _cloud_noise: FastNoiseLite

## 初始化：注入相机并生成噪声
func setup(p_camera: Camera2D) -> void:
	camera = p_camera
	_init_noise()

func _init_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = terrain_frequency
	_noise.fractal_octaves = 2
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.3

	_cloud_noise = FastNoiseLite.new()
	_cloud_noise.seed = cloud_seed
	_cloud_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cloud_noise.frequency = cloud_frequency
	_cloud_noise.fractal_octaves = 2

func _draw() -> void:
	if not camera:
		return
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

## 根据噪声值返回分档间平滑混合后的颜色（让海陆边界有渐变过渡）
func _get_blended_color(noise_val: float) -> Color:
	for i in range(TIER_THRESHOLDS.size()):
		var b: float = TIER_THRESHOLDS[i]
		# 海/岸分界（i==2，即 -0.02）用更宽的过渡带
		var w: float = COAST_BLEND_WIDTH if i == 2 else BLEND_WIDTH
		if noise_val < b - w:
			return TERRAIN_COLORS[TIER_ORDER[i]]
		if noise_val < b + w:
			var t: float = (noise_val - (b - w)) / (w * 2.0)
			# 用 smoothstep 让过渡更柔和
			t = t * t * (3.0 - 2.0 * t)
			return TERRAIN_COLORS[TIER_ORDER[i]].lerp(TERRAIN_COLORS[TIER_ORDER[i + 1]], t)
	return TERRAIN_COLORS[TIER_ORDER[-1]]

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

			var base_color: Color = _get_blended_color(noise_val)

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
