class_name WeatherSystem
extends Node2D

## 全局天气系统：高空云层（沙盒和生存模式共享）
## 作为子节点添加到场景中，自动绘制云层。
## 其它模块通过 get_tree().get_first_node_in_group("weather") 获取引用。
## 用法：
##   var weather := WeatherSystem.new()
##   add_child(weather)
##   weather.setup(camera)
##   weather.add_to_group("weather")
##
## 渲染原理（贴图方案）：
##   1. setup() 时用噪声 + 径向衰减烘焙 N 张 RGBA 云贴图（ImageTexture），一次性 ~200ms
##   2. 运行时只在"云空间"网格上做 draw_texture 贴图，位置 = cloud_pos + wind_offset
##      → 云随风漂移是整体位移，密度/形态不变（无闪烁、无 pop）
##   3. 网格步进 < 贴图尺寸，多张云自然重叠混合，形成连绵云带
##   4. 贴图变体 + 每格哈希决定 variant/rotation/scale/jitter → 不会肉眼察觉到网格

const PIXELS_PER_METER: float = GameConstants.PIXELS_PER_METER

## ── 风 ──
var wind_direction: Vector2 = Vector2.RIGHT
var wind_speed: float = 18.0                  ## m/s

## ── 云密度场（供战斗系统查询）──
var cloud_seed: int = 0
## 0.00028：云团特征尺度 ~7km（2026-07-28 从 0.00055 减半）。
## 碎云对战术无意义 —— 要的是"大块云系飘过战场"，玩家能围绕它规划航线。
var cloud_frequency: float = 0.00028
var cloud_coverage: float = 0.35
## 第二个同尺度噪声场用于填补整张图的局部空洞；0=关闭，1=与主场等权取 max。
## 官方海岛图使用中等混合，得到更均匀但仍保持大片连通区域的云带。
var cloud_secondary_mix: float = 0.0

## ── 沙尘暴（可选地图配置；只参与 LOW 高度的战斗遮蔽）──
var sandstorm_enabled: bool = false
var sandstorm_seed: int = 0
var sandstorm_start_ratio: float = 0.5
var sandstorm_duration_s: float = 60.0
var sandstorm_band_width_px: float = 8000.0
var sandstorm_speed_kmh: float = 0.0
var sandstorm_direction: Vector2 = Vector2.RIGHT
var sandstorm_tint: Color = Color(0.95, 0.70, 0.18)
var _game_time: float = 0.0
var _phase_duration: float = 600.0
var _sandstorm_debug_progress: float = -1.0

## ── UGC 云 mask（spec map-editor §3.2）──
## 64×64 字节网格覆盖全图，值/127.5 = 密度乘数 0~2；空 = 全 1.0（官方行为不变）。
## 锚定"云空间"（采样时同噪声一起减去风偏移 → 随风整体漂移）。
var ugc_mask: PackedByteArray = PackedByteArray()
const UGC_MASK_GRID := 64
const UGC_MASK_WORLD_HALF := MapBoundary.WORLD_HALF_PX  # 随 map-expansion 主开关

## ── 贴图烘焙参数 ──
const SPRITE_SIZE: int = 256            ## 单张云贴图尺寸
const SPRITE_COUNT: int = 4             ## 变体数量（哈希选取）
const REDRAW_INTERVAL: float = 0.12     ## 重绘间隔

## ── 绘制网格参数 ──
const SPRITE_SPACING: float = 140.0     ## 网格步长（< SPRITE_SIZE 让贴图重叠）
const MIN_DENSITY: float = 0.06         ## 低于此值不画
const SPRITE_ALPHA_MAX: float = 0.42    ## 云核心贴图整体 alpha 上限（叠加不饱和）
const WORLD_SCALE: float = 1.25         ## 贴图在世界中放大系数
## 沙尘暴使用气象图式矢量纹样，不复用写实云贴图。
## 所有线段只在可见沙带内生成，并以少量 polyline / multiline 批量提交。
const STORM_STREAM_GAP: float = 210.0
const STORM_STREAM_STEP: float = 120.0
const STORM_OBSERVATION_GRID: float = 620.0
const STORM_FRONT_MARK_GAP: float = 340.0
const STORM_EDGE_FEATHER: float = 720.0
const STORM_EDGE_WAVE_MAX: float = 260.0
const STORM_FILL_ALPHA: float = 0.060
const STORM_FILL_LAYERS: int = 6

const CLOUD_TINT := Color(0.94, 0.96, 1.0)

var camera: Camera2D
var _noise: FastNoiseLite
var _noise_secondary: FastNoiseLite
var _sandstorm_noise: FastNoiseLite
var _time: float = 0.0
var _redraw_accum: float = REDRAW_INTERVAL

var _sprites: Array = []  ## Array[ImageTexture] — 烘焙好的云贴图

## 初始化：注入相机、生成噪声、烘焙贴图
func setup(p_camera: Camera2D, deterministic_seed: int = 0) -> void:
	camera = p_camera
	var rng := RandomNumberGenerator.new()
	if deterministic_seed != 0:
		rng.seed = deterministic_seed
	else:
		rng.randomize()
	var theta := rng.randf_range(0.0, TAU)
	wind_direction = Vector2(cos(theta), sin(theta))
	wind_speed = rng.randf_range(12.0, 26.0)
	cloud_seed = rng.randi()
	_init_noise()
	_bake_sprites()

func _init_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = cloud_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = cloud_frequency
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.1
	_noise.fractal_gain = 0.48
	_noise_secondary = FastNoiseLite.new()
	_noise_secondary.seed = cloud_seed ^ 0x5F356495
	_noise_secondary.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_secondary.frequency = cloud_frequency
	_noise_secondary.fractal_octaves = 4
	_noise_secondary.fractal_lacunarity = 2.1
	_noise_secondary.fractal_gain = 0.48
	_sandstorm_noise = FastNoiseLite.new()
	_sandstorm_noise.seed = sandstorm_seed
	_sandstorm_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_sandstorm_noise.frequency = 0.00042
	_sandstorm_noise.fractal_octaves = 3
	_sandstorm_noise.fractal_lacunarity = 2.0
	_sandstorm_noise.fractal_gain = 0.52

func _process(delta: float) -> void:
	_time += delta
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()

## 当前风偏移（像素）
func _wind_offset() -> Vector2:
	return wind_direction * wind_speed * PIXELS_PER_METER * _time

## 采样某世界坐标的云密度（归一化 0~1）
## UGC mask 注入点（唯一，渲染与战斗查询共用此口）：density = clamp(noise × mask, 0, 1)
func sample_density(world_pos: Vector2) -> float:
	if _noise == null:
		return 0.0
	var offset := _wind_offset()
	var cx := world_pos.x - offset.x
	var cy := world_pos.y - offset.y
	return _cloud_density_at(cx, cy)


## 云空间密度唯一计算口：主噪声保留大片，第二噪声只负责填补局部空洞。
func _cloud_density_at(cx: float, cy: float) -> float:
	var primary := _density_from_noise(_noise.get_noise_2d(cx, cy))
	var base := primary
	if cloud_secondary_mix > 0.0 and _noise_secondary != null:
		var secondary := _density_from_noise(_noise_secondary.get_noise_2d(cx, cy))
		base = maxf(primary, secondary * cloud_secondary_mix)
	if ugc_mask.is_empty():
		return base
	return clampf(base * _sample_mask(cx, cy), 0.0, 1.0)


func _density_from_noise(value: float) -> float:
	if value <= cloud_coverage:
		return 0.0
	return clampf((value - cloud_coverage) / 0.35, 0.0, 1.0)


## 生存模式每个物理帧只同步两个标量；WeatherSystem 不反向依赖模式脚本。
func set_game_time(seconds: float, phase_duration_s: float) -> void:
	_game_time = maxf(seconds, 0.0)
	_phase_duration = maxf(phase_duration_s, 0.001)


## Debug 专用：保留正式半局时间，同时把极慢的现实速度沙带定位到地图中心供直接验收。
func set_debug_midgame(seconds: float, phase_duration_s: float) -> void:
	set_game_time(seconds, phase_duration_s)
	_sandstorm_debug_progress = 0.5


func sandstorm_start_time() -> float:
	return _phase_duration * sandstorm_start_ratio


func is_sandstorm_active() -> bool:
	if not sandstorm_enabled:
		return false
	if _sandstorm_debug_progress >= 0.0:
		return true
	var start := sandstorm_start_time()
	return _game_time >= start and _game_time < start + sandstorm_duration_s


func sandstorm_progress() -> float:
	if _sandstorm_debug_progress >= 0.0:
		return _sandstorm_debug_progress
	return clampf((_game_time - sandstorm_start_time()) / sandstorm_duration_s, 0.0, 1.0)


func sandstorm_center_world() -> Vector2:
	var half_world := MapBoundary.world_half_px()
	var travel := half_world * 2.0 + sandstorm_band_width_px
	var center_axis := -half_world - sandstorm_band_width_px * 0.5 + travel * sandstorm_progress()
	return sandstorm_direction * center_axis


## 沙尘暴是一条覆盖整张地图高度的宽带：首帧前缘刚进图，末帧后缘刚离图。
func sample_sandstorm_density(world_pos: Vector2) -> float:
	if not is_sandstorm_active() or _sandstorm_noise == null:
		return 0.0
	var half_band := sandstorm_band_width_px * 0.5
	var center_world := sandstorm_center_world()
	var left_edge := center_world.x - half_band + _sandstorm_edge_wave(world_pos.y, false)
	var right_edge := center_world.x + half_band + _sandstorm_edge_wave(world_pos.y, true)
	if world_pos.x <= left_edge or world_pos.x >= right_edge:
		return 0.0
	var edge_distance := minf(world_pos.x - left_edge, right_edge - world_pos.x)
	var edge := smoothstep(0.0, STORM_EDGE_FEATHER, edge_distance)
	var noise_value := (_sandstorm_noise.get_noise_2d(world_pos.x, world_pos.y) + 1.0) * 0.5
	return clampf(edge * lerpf(0.58, 1.0, noise_value), 0.0, 1.0)


## 战斗遮蔽统一入口：普通云只在 HIGH；沙尘暴只在 LOW（<3500m）。
func sample_obscurant_density(world_pos: Vector2, altitude_m: float) -> float:
	var normal_cloud := sample_density(world_pos) if altitude_m >= 7500.0 else 0.0
	var sandstorm := sample_sandstorm_density(world_pos) if altitude_m < 3500.0 else 0.0
	return maxf(normal_cloud, sandstorm)


func is_obscured(world_pos: Vector2, altitude_m: float) -> bool:
	return sample_obscurant_density(world_pos, altitude_m) > 0.0


func is_in_sandstorm(world_pos: Vector2, altitude_m: float) -> bool:
	return altitude_m < 3500.0 and sample_sandstorm_density(world_pos) > 0.0


## 双线性采样 UGC mask（云空间坐标），越界视为 1.0（不改边缘行为）
func _sample_mask(cx: float, cy: float) -> float:
	var cell := UGC_MASK_WORLD_HALF * 2.0 / float(UGC_MASK_GRID)
	var fx := (cx + UGC_MASK_WORLD_HALF) / cell - 0.5
	var fy := (cy + UGC_MASK_WORLD_HALF) / cell - 0.5
	var x0 := int(floorf(fx))
	var y0 := int(floorf(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var v00 := _mask_at(x0, y0)
	var v10 := _mask_at(x0 + 1, y0)
	var v01 := _mask_at(x0, y0 + 1)
	var v11 := _mask_at(x0 + 1, y0 + 1)
	return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty)


func _mask_at(gx: int, gy: int) -> float:
	if gx < 0 or gy < 0 or gx >= UGC_MASK_GRID or gy >= UGC_MASK_GRID:
		return 1.0
	return float(ugc_mask[gy * UGC_MASK_GRID + gx]) / 127.5


## UGC 云配置注入（UgcLoader 调用；setup 之后调）
## 覆盖 seed/coverage/frequency/风，重建噪声；mask 空 = 保持纯噪声
func apply_ugc_config(cloud: Dictionary) -> void:
	cloud_seed = int(cloud.get("seed", cloud_seed))
	cloud_coverage = clampf(float(cloud.get("coverage", cloud_coverage)), 0.0, 1.0)
	cloud_frequency = float(cloud.get("frequency", cloud_frequency))
	cloud_secondary_mix = clampf(float(cloud.get("secondary_mix", 0.0)), 0.0, 1.0)
	var dir_rad := deg_to_rad(float(cloud.get("wind_dir_deg", 0.0)))
	wind_direction = Vector2(sin(dir_rad), -cos(dir_rad))  # 0°=北（屏幕上方），顺时针，与 heading 约定一致
	wind_speed = float(cloud.get("wind_speed_ms", wind_speed))
	var mask = cloud.get("mask", PackedByteArray())
	ugc_mask = mask if mask is PackedByteArray and mask.size() == UGC_MASK_GRID * UGC_MASK_GRID else PackedByteArray()
	var storm: Dictionary = cloud.get("sandstorm", {}) if cloud.get("sandstorm", {}) is Dictionary else {}
	sandstorm_enabled = bool(storm.get("enabled", false))
	sandstorm_seed = int(storm.get("seed", cloud_seed ^ 0x2C9277B5))
	sandstorm_start_ratio = clampf(float(storm.get("start_ratio", 0.5)), 0.0, 1.0)
	sandstorm_band_width_px = maxf(float(storm.get("band_width_px", 8000.0)), 500.0)
	sandstorm_speed_kmh = maxf(float(storm.get("speed_kmh", 0.0)), 0.0)
	if sandstorm_speed_kmh > 0.0:
		var travel_m := (MapBoundary.world_half_px() * 2.0 + sandstorm_band_width_px) \
			/ PIXELS_PER_METER
		sandstorm_duration_s = travel_m / (sandstorm_speed_kmh / 3.6)
	else:
		sandstorm_duration_s = maxf(float(storm.get("duration_s", 60.0)), 1.0)
	_sandstorm_debug_progress = -1.0
	var direction_name := String(storm.get("direction", "west_to_east"))
	sandstorm_direction = Vector2.LEFT if direction_name == "east_to_west" else Vector2.RIGHT
	var tint = storm.get("tint", [0.95, 0.70, 0.18, 1.0])
	if tint is Array and tint.size() >= 3:
		sandstorm_tint = Color(float(tint[0]), float(tint[1]), float(tint[2]),
			float(tint[3]) if tint.size() >= 4 else 1.0)
	_init_noise()
	if camera != null:
		_bake_sprites()

## 某世界坐标是否在云内
func is_in_cloud(world_pos: Vector2) -> bool:
	return sample_density(world_pos) > 0.0

# ══════════════════════════════════════════════════════════
#  贴图烘焙（setup 时跑一次）
# ══════════════════════════════════════════════════════════

func _bake_sprites() -> void:
	_sprites.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = cloud_seed
	for k in SPRITE_COUNT:
		_sprites.append(_bake_single(rng.randi()))

## 烘焙单张云贴图：低频轮廓 × 径向衰减 → 柔和 RGBA 云团
## 颜色恒为 CLOUD_TINT（不做明暗调制，避免叠加出脏斑），形态全由 alpha 承担
func _bake_single(seed: int) -> ImageTexture:
	var img := Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)

	# 主形态噪声：决定云的轮廓。频率低 → 大块、柔和
	var shape := FastNoiseLite.new()
	shape.seed = seed
	shape.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shape.frequency = 0.009
	shape.fractal_octaves = 3
	shape.fractal_gain = 0.5
	shape.fractal_lacunarity = 2.0

	var half := float(SPRITE_SIZE) * 0.5
	for y in SPRITE_SIZE:
		for x in SPRITE_SIZE:
			var dx: float = (float(x) - half) / half   # -1~1
			var dy: float = (float(y) - half) / half
			var r2: float = dx * dx + dy * dy
			if r2 >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var r: float = sqrt(r2)
			# 径向衰减：core 内几乎满透明度，从 0.55r 开始柔和过渡到 1.0r
			var radial: float = smoothstep(1.0, 0.55, r)

			# 主形态：0~1，让云内部有连绵起伏
			var s_val: float = (shape.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			# 拉高下限避免"空洞"：max(s_val, 0.45)
			s_val = maxf(s_val, 0.45)

			var density: float = s_val * radial
			if density < 0.12:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			# 柔和 alpha 曲线：smoothstep 让羽化更漂亮
			var alpha: float = smoothstep(0.12, 0.75, density)
			img.set_pixel(x, y, Color(CLOUD_TINT.r, CLOUD_TINT.g, CLOUD_TINT.b, alpha))

	return ImageTexture.create_from_image(img)

# ══════════════════════════════════════════════════════════
#  运行时渲染：贴图网格
# ══════════════════════════════════════════════════════════

func _draw() -> void:
	if not camera or _noise == null or _sprites.is_empty():
		return

	var viewport_size := get_viewport_rect().size / camera.zoom
	var cam_pos := camera.global_position
	var half := viewport_size / 2.0
	var offset := _wind_offset()

	# 在"云空间"（去风偏移的坐标系）上建网格
	# world_pos = cloud_pos + offset；云空间里密度就是 noise(cloud_pos)，不随时间变
	# 好处：一片云格始终带着稳定密度漂过屏幕，无 pop、无闪烁
	var cloud_left := cam_pos.x - half.x - offset.x
	var cloud_top := cam_pos.y - half.y - offset.y
	var cloud_right := cam_pos.x + half.x - offset.x
	var cloud_bot := cam_pos.y + half.y - offset.y

	var sprite_half_world: float = float(SPRITE_SIZE) * WORLD_SCALE * 0.5
	var margin := sprite_half_world + SPRITE_SPACING
	var start_x := snappedf(cloud_left - margin, SPRITE_SPACING)
	var start_y := snappedf(cloud_top - margin, SPRITE_SPACING)
	var end_x := cloud_right + margin
	var end_y := cloud_bot + margin

	var cx := start_x
	while cx <= end_x:
		var cy := start_y
		while cy <= end_y:
			var density := _cloud_density_at(cx, cy)
			if density > MIN_DENSITY:
				_draw_sprite_at(Vector2(cx, cy), offset, density)
			cy += SPRITE_SPACING
		cx += SPRITE_SPACING
	_draw_sandstorm(cam_pos, half)


## 沙尘暴使用现实气象观测图的抽象语法：淡色沙带 + 平行流线 + 锋面符号 + 观测点阵。
## 纹样允许稳定重复拼贴，但只构造当前相机可见范围，避免随地图面积增长。
func _draw_sandstorm(cam_pos: Vector2, half: Vector2) -> void:
	if not is_sandstorm_active():
		return
	var half_world := MapBoundary.world_half_px()
	var center_world := sandstorm_center_world()
	var storm_rect := Rect2(center_world - Vector2(sandstorm_band_width_px * 0.5, half_world),
		Vector2(sandstorm_band_width_px, half_world * 2.0))
	var visible_rect := Rect2(cam_pos - half, half * 2.0).intersection(
		storm_rect.grow(STORM_EDGE_WAVE_MAX))
	if not visible_rect.has_area():
		return
	# 六层同形曲边多边形从外向内累积 Alpha，让前后缘都自然羽化而非矩形硬切。
	_draw_sandstorm_fill(storm_rect, visible_rect)
	_draw_sandstorm_streamlines(visible_rect, storm_rect)
	_draw_sandstorm_observations(visible_rect)
	_draw_sandstorm_front(storm_rect, visible_rect)


func _sandstorm_edge_wave(world_y: float, right_edge: bool) -> float:
	var phase := 1.73 if right_edge else -0.61
	return sin(world_y * 0.0017 + phase) * 148.0 \
		+ sin(world_y * 0.00053 - phase * 0.7) * 96.0


func _sandstorm_band_polygon(storm_rect: Rect2, visible_rect: Rect2,
		inset: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var step_y := 180.0
	var start_y := maxf(storm_rect.position.y, visible_rect.position.y - step_y)
	var end_y := minf(storm_rect.end.y, visible_rect.end.y + step_y)
	var y := start_y
	while y <= end_y:
		points.append(Vector2(storm_rect.position.x + inset + _sandstorm_edge_wave(y, false), y))
		y += step_y
	points.append(Vector2(storm_rect.position.x + inset + _sandstorm_edge_wave(end_y, false), end_y))
	y = end_y
	while y >= start_y:
		points.append(Vector2(storm_rect.end.x - inset + _sandstorm_edge_wave(y, true), y))
		y -= step_y
	points.append(Vector2(storm_rect.end.x - inset + _sandstorm_edge_wave(start_y, true), start_y))
	return points


func _draw_sandstorm_fill(storm_rect: Rect2, visible_rect: Rect2) -> void:
	var layer_alpha := STORM_FILL_ALPHA / float(STORM_FILL_LAYERS)
	for layer in range(STORM_FILL_LAYERS):
		var inset := STORM_EDGE_FEATHER * float(layer) / float(STORM_FILL_LAYERS - 1)
		draw_colored_polygon(_sandstorm_band_polygon(storm_rect, visible_rect, inset),
			Color(sandstorm_tint.r, sandstorm_tint.g, sandstorm_tint.b, layer_alpha))


## 多组平行流线：两级正弦叠加形成气象图的连续弯曲，世界坐标使拼贴稳定不闪烁。
func _draw_sandstorm_streamlines(rect: Rect2, storm_rect: Rect2) -> void:
	var ink := Color(0.24, 0.17, 0.055, 0.48)
	var ink_major := Color(0.20, 0.13, 0.035, 0.62)
	var start_y := snappedf(rect.position.y - STORM_STREAM_GAP, STORM_STREAM_GAP)
	var end_y := rect.end.y + STORM_STREAM_GAP
	var start_x := maxf(rect.position.x - STORM_STREAM_STEP,
		storm_rect.position.x + STORM_EDGE_FEATHER * 0.72)
	var end_x := minf(rect.end.x + STORM_STREAM_STEP,
		storm_rect.end.x - STORM_EDGE_FEATHER * 0.72)
	if start_x >= end_x:
		return
	var row := int(round(start_y / STORM_STREAM_GAP))
	var y := start_y
	while y <= end_y:
		var points := PackedVector2Array()
		var phase := float((row * 37 + sandstorm_seed) % 127) * 0.071
		var x := start_x
		while x <= end_x:
			var bend := sin(x * 0.00135 + phase) * 92.0 \
				+ sin(x * 0.00047 - phase * 0.63) * 145.0
			points.append(Vector2(x, y + bend))
			x += STORM_STREAM_STEP
		draw_polyline(points, ink_major if posmod(row, 4) == 0 else ink,
			5.0 if posmod(row, 4) == 0 else 3.0, true)
		y += STORM_STREAM_GAP
		row += 1


## 稀疏十字观测点、短风羽和双线条带共用一次 multiline 提交，避免逐符号 draw_line。
func _draw_sandstorm_observations(rect: Rect2) -> void:
	var segments := PackedVector2Array()
	var start_x := snappedf(rect.position.x, STORM_OBSERVATION_GRID)
	var start_y := snappedf(rect.position.y, STORM_OBSERVATION_GRID)
	var x := start_x
	while x <= rect.end.x:
		var y := start_y
		while y <= rect.end.y:
			var gx := int(round(x / STORM_OBSERVATION_GRID))
			var gy := int(round(y / STORM_OBSERVATION_GRID))
			var h := absi((gx * 73856093) ^ (gy * 19349663) ^ sandstorm_seed)
			var jitter := Vector2(float((h >> 7) % 101) - 50.0,
				float((h >> 15) % 101) - 50.0) * 0.72
			var p := Vector2(x, y) + jitter
			if sample_sandstorm_density(p) < 0.20:
				y += STORM_OBSERVATION_GRID
				continue
			# 观测站十字与小菱形，以点/线替代具象云粒子。
			segments.append_array(PackedVector2Array([
				p + Vector2(-18, 0), p + Vector2(18, 0),
				p + Vector2(0, -18), p + Vector2(0, 18),
				p + Vector2(25, 0), p + Vector2(34, -9),
				p + Vector2(34, -9), p + Vector2(43, 0),
				p + Vector2(43, 0), p + Vector2(34, 9),
				p + Vector2(34, 9), p + Vector2(25, 0),
				p + Vector2(58, -6), p + Vector2(112, -28),
				p + Vector2(86, -18), p + Vector2(101, -43),
			]))
			y += STORM_OBSERVATION_GRID
		x += STORM_OBSERVATION_GRID
	if not segments.is_empty():
		draw_multiline(segments, Color(0.19, 0.12, 0.025, 0.68), 3.2, true)


## 推进侧用气象锋面三角标记强调运动方向；符号只在可见边界生成。
func _draw_sandstorm_front(storm_rect: Rect2, visible_rect: Rect2) -> void:
	var leading_base_x := storm_rect.end.x if sandstorm_direction.x > 0.0 else storm_rect.position.x
	if leading_base_x < visible_rect.position.x - STORM_EDGE_WAVE_MAX \
		or leading_base_x > visible_rect.end.x + STORM_EDGE_WAVE_MAX:
		return
	var segments := PackedVector2Array()
	var start_y := visible_rect.position.y - STORM_STREAM_STEP
	var end_y := visible_rect.end.y + STORM_STREAM_STEP
	var y := start_y
	var previous := Vector2.ZERO
	var point_index := 0
	while y <= end_y:
		var right_edge := sandstorm_direction.x > 0.0
		var current := Vector2(leading_base_x + _sandstorm_edge_wave(y, right_edge), y)
		if point_index > 0 and posmod(point_index, 2) == 0:
			segments.append_array(PackedVector2Array([previous, current]))
		previous = current
		point_index += 1
		y += STORM_STREAM_STEP
	var sign_x := 1.0 if sandstorm_direction.x > 0.0 else -1.0
	y = snappedf(visible_rect.position.y, STORM_FRONT_MARK_GAP)
	while y <= visible_rect.end.y:
		var right_edge := sandstorm_direction.x > 0.0
		var base := Vector2(leading_base_x + _sandstorm_edge_wave(y, right_edge), y)
		var tip := base + Vector2(72.0 * sign_x, 0.0)
		segments.append_array(PackedVector2Array([
			base + Vector2(0, -42), tip,
			tip, base + Vector2(0, 42),
		]))
		y += STORM_FRONT_MARK_GAP
	if not segments.is_empty():
		draw_multiline(segments, Color(0.16, 0.095, 0.015, 0.52), 3.6, true)

## 在云空间位置 cloud_pos 上画一张贴图，世界位置 = cloud_pos + offset
## 用 cloud_pos 做哈希保证变体/旋转/缩放/抖动稳定跟随云格漂移
func _draw_sprite_at(cloud_pos: Vector2, offset: Vector2, density: float) -> void:
	var hx: int = int(round(cloud_pos.x / SPRITE_SPACING))
	var hy: int = int(round(cloud_pos.y / SPRITE_SPACING))
	var h: int = (hx * 73856093) ^ (hy * 19349663) ^ cloud_seed
	if h < 0:
		h = -h

	var variant: int = h % _sprites.size()
	# 稳定伪随机：位移 8 位获得独立数列
	var rot_val: float = float(h % 1000) / 1000.0       # 0~1
	var scale_val: float = float((h >> 8) % 1000) / 1000.0
	var jitter_x: float = float((h >> 16) % 1000) / 1000.0 - 0.5
	var jitter_y: float = float((h >> 24) % 1000) / 1000.0 - 0.5

	var rotation_rad: float = rot_val * TAU
	# 密度高的云稍微大一点，有体量感
	var scale_factor: float = lerp(0.85, 1.25, scale_val) * lerp(0.85, 1.1, density) * WORLD_SCALE
	var jitter_offset := Vector2(jitter_x, jitter_y) * SPRITE_SPACING * 0.45

	var world_pos: Vector2 = cloud_pos + offset + jitter_offset

	var tex: ImageTexture = _sprites[variant]
	var tint := Color(1.0, 1.0, 1.0, clampf(density, 0.0, 1.0) * SPRITE_ALPHA_MAX)

	draw_set_transform(world_pos, rotation_rad, Vector2(scale_factor, scale_factor))
	var half_size: float = float(SPRITE_SIZE) * 0.5
	draw_texture_rect(tex, Rect2(-half_size, -half_size, SPRITE_SIZE, SPRITE_SIZE), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
