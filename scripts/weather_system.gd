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

const CLOUD_TINT := Color(0.94, 0.96, 1.0)

var camera: Camera2D
var _noise: FastNoiseLite
var _time: float = 0.0
var _redraw_accum: float = REDRAW_INTERVAL

var _sprites: Array = []  ## Array[ImageTexture] — 烘焙好的云贴图

## 初始化：注入相机、生成噪声、烘焙贴图
func setup(p_camera: Camera2D) -> void:
	camera = p_camera
	var rng := RandomNumberGenerator.new()
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
	var val := _noise.get_noise_2d(cx, cy)
	var base := 0.0
	if val > cloud_coverage:
		base = clampf((val - cloud_coverage) / 0.35, 0.0, 1.0)
	if ugc_mask.is_empty():
		return base
	return clampf(base * _sample_mask(cx, cy), 0.0, 1.0)


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
	var dir_rad := deg_to_rad(float(cloud.get("wind_dir_deg", 0.0)))
	wind_direction = Vector2(sin(dir_rad), -cos(dir_rad))  # 0°=北（屏幕上方），顺时针，与 heading 约定一致
	wind_speed = float(cloud.get("wind_speed_ms", wind_speed))
	var mask = cloud.get("mask", PackedByteArray())
	ugc_mask = mask if mask is PackedByteArray and mask.size() == UGC_MASK_GRID * UGC_MASK_GRID else PackedByteArray()
	_init_noise()

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
			var val: float = _noise.get_noise_2d(cx, cy)
			if val > cloud_coverage:
				var density: float = clampf((val - cloud_coverage) / 0.35, 0.0, 1.0)
				if density > MIN_DENSITY:
					_draw_sprite_at(Vector2(cx, cy), offset, density)
			cy += SPRITE_SPACING
		cx += SPRITE_SPACING

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
