class_name MapFeatureRenderer
extends Node2D

const VectorPreviewRenderer = preload("res://scripts/survivor/map_vector_preview_renderer.gd")
const DetailTileCache = preload("res://scripts/survivor/map_detail_tile_cache.gd")
const RasterBasemapRendererScript = preload("res://scripts/survivor/raster_basemap_renderer.gd")

## 正式地图底图加载失败时通知场景主控；UGC 纯矢量模式不会尝试加载，也不会发出此信号。
signal basemap_load_failed(reason_key: String)

## 世界空间地图特征绘制（生存模式）
##
## 分层（从底到顶）：
##   1. 海面底色（相机视野覆盖矩形）
##   2. 浅海渐变带（3 层外扩多边形，深→浅）
##   3. 海岸外光晕（淡青色）
##   4. 陆地填充 + 内陆高光
##   5. 海岸线（亮青白描边）
##   6. 城区（暖色半透填充 + 描边）
##   7. 城区街区网格（细灰白线，裁剪到城区多边形内）
##   8. 程序化次级路网（县道 / 乡道，MapGeography.get_secondary_roads）
##   9. 高速公路折线（粗暖色）
##  10. Aqua-Line 跨湾虚线（亮青）
##  11. TacView "+" 装饰（海面稀疏网格）

var _camera: Camera2D
var _world_rect: Rect2

func setup(camera: Camera2D, world_rect: Rect2) -> void:
	_camera = camera
	_world_rect = world_rect
	# 纯矢量只在显式诊断参数下预热，常规 PNG/栅格路径不支付百万三角形构图成本。
	if OS.is_debug_build() and not ugc_vector_only \
			and OS.get_cmdline_user_args().has("--vector-map-preview"):
		_prepare_vector_preview()
	if use_basemap:
		_ensure_basemap_loaded()
	queue_redraw()  # setup 后触发一次绘制；之后地图静态不需要再重绘

func _ready() -> void:
	z_index = -50
	# 注：地图特征（海岸线、城区、高速、Aqua-Line）完全静态 + Node2D 在原点
	# CanvasItem 会缓存绘制命令，相机移动/缩放由 Godot 渲染器处理，无需每帧重绘
	# 原本 _process 每帧 queue_redraw 是性能主瓶颈（多边形 + draw_line 全部重算）

## TacView 风格的十字装饰
const TACVIEW_SPACING := 800.0
const TACVIEW_SIZE := 4.0
const TACVIEW_COLOR := Color(0.55, 0.75, 0.82, 0.30)

## === Tacview 示意层色调（全部实色 alpha=1.0）===
## 陆地 mask：OSM 城区+道路的外扩并集作为陆地，画 LAND_COLOR 实色
const LAND_MASK_COLOR := Color(0.32, 0.35, 0.27, 1.0)
## 城区叠加（在陆地上，颜色稍暗偏暖，代表"市区")
const OSM_URBAN_FILL := Color(0.42, 0.38, 0.28, 1.0)
## 道路 — 米黄实色
const OSM_ROAD_COLOR := Color(0.88, 0.80, 0.56, 1.0)
const OSM_ROAD_HALF_WIDTH := 2.2

## 可选手画地块（用户在 Godot 编辑器里 Polygon2D 画）
## 如果存在 res://scenes/map_manual.tscn，其中所有 Polygon2D 节点会被叠加到地图上
## 每个 Polygon2D 的 polygon + color 独立读取，可各自定制
const MANUAL_MAP_PATH := "res://scenes/map_manual.tscn"

## 正式底图直接消费 lossless WebP 金字塔；JSON 只保留 bbox → 世界坐标元数据。
## png_path 仅为外部 UGC 的兼容入口，官方三图不再携带整图 PNG。
const BASEMAP_META_PATH := "res://resources/maps/tokyo_bay_bg.json"
var basemap_map_key := "tokyo"
var basemap_png_path := ""
var basemap_meta_path: String = BASEMAP_META_PATH
var use_basemap := true

## 底图渲染参数（全部 @export — Inspector 里实时调）
@export_group("Basemap")
## 整体色调叠加（multiply）。默认中性偏冷灰 —— 保持海面蓝、陆地不偏色
@export var basemap_tint: Color = Color(0.78, 0.82, 0.80, 1.0)
## 饱和度：0 = 完全灰度，1 = 原色
@export_range(0.0, 2.0, 0.05) var basemap_saturation: float = 0.40
## 亮度：1 = 原亮度，<1 变暗
@export_range(0.0, 2.0, 0.05) var basemap_brightness: float = 0.70
## 对比度：>1 加强明暗差异
@export_range(0.5, 2.0, 0.05) var basemap_contrast: float = 1.25
## 边缘检测强度：>0 则在色彩转换处画描边（海岸/道路/建筑边界）
@export_range(0.0, 3.0, 0.1) var basemap_edge_strength: float = 1.2
@export var basemap_edge_color: Color = Color(0.10, 0.12, 0.10, 1.0)
## 与 streamed 路径共用的世界空间静态蓝噪声；禁止 TIME 动态颗粒。
@export_range(0.0, 0.05, 0.001) var basemap_noise: float = 0.014
@export_range(1.0, 128.0, 1.0) var basemap_grain_repeat: float = 64.0
## 底图存在时覆盖 OSM 矢量层（不再重绘建筑/道路，纯底图 + 边缘描边）
@export var basemap_covers_vectors: bool = true

## 边界外 vignette：3 圈逐层加深的暗色，制造软边
const VIGNETTE_RINGS := [
	{"outer": 280.0, "color": Color(0.04, 0.05, 0.07, 0.30)},
	{"outer": 700.0, "color": Color(0.04, 0.05, 0.07, 0.55)},
	{"outer": 2000.0,"color": Color(0.03, 0.04, 0.06, 0.90)},
]

var _logged := false
var _manual_polys: Array = []  # Array[{"pts": PackedVector2Array, "color": Color}]
var _manual_loaded := false

## 底图缓存
const BASEMAP_SHADER_PATH := "res://resources/shaders/basemap_tacview.gdshader"
var _basemap_sprite: Sprite2D = null
var _basemap_loaded := false
var _legacy_basemap_attempted := false  ## 仅外部 UGC PNG 兼容路径
var _basemap_world_rect := Rect2()
var _basemap_grain_texture: Texture2D = null

## 正式栅格金字塔；官方三图始终启用，LOD 淡变属于生产渲染链。
var tile_basemap_enabled := true
var _raster_basemap: Node2D = null
var _streamed_ready_logged := false

## 开发期 A/B：默认仍走正式 PNG；Shift+F10 才启用 V36 纯矢量候选。
var vector_preview_enabled := false
var _vector_preview: Node2D = null
var _detail_tile_preview: Node2D = null

## UGC 纯矢量模式（survivor_mode 在 UGC 试飞时置 true）：
## 跳过官方底图 PNG 与手画覆盖层（都是官方东京湾专属素材），只走矢量渲染路径
var ugc_vector_only := false

## UGC/内置预览图调色板；空字典保持东京湾历史常量逐字节不变。
var ugc_palette: Dictionary = {}

## UGC 地形覆盖层（山地/森林/农田/沙滩，UgcLoader.overlay_layers_from 生成）
## 元素 {color: Color, polys: Array[PackedVector2Array]}；空 = 官方图零影响
var ugc_overlay_layers: Array = []

func _prepare_vector_preview() -> bool:
	if _vector_preview != null:
		return true
	if _camera == null or _world_rect.size.x <= 0.0 or not VectorPreviewRenderer.preview_available():
		return false
	_vector_preview = VectorPreviewRenderer.new()
	_vector_preview.name = "VectorMapPreview"
	_vector_preview.visible = false
	add_child(_vector_preview)
	if not _vector_preview.setup(_camera, _world_rect):
		_vector_preview.queue_free()
		_vector_preview = null
		return false
	attach_cached_detail()
	return true


func attach_cached_detail() -> bool:
	if _detail_tile_preview != null:
		return true
	if not DetailTileCache.cache_ready() or _camera == null:
		return false
	_detail_tile_preview = DetailTileCache.new()
	_detail_tile_preview.name = "VectorMapDetailTile"
	add_child(_detail_tile_preview)
	_detail_tile_preview.setup_camera(_camera)
	var detail_result: Dictionary = _detail_tile_preview.attach_cached()
	if not bool(detail_result.get("ok", false)):
		push_warning("Vector detail tile unavailable: %s" % detail_result.get("error", "unknown"))
		_detail_tile_preview.queue_free()
		_detail_tile_preview = null
		return false
	_detail_tile_preview.set_detail_zoom(_camera.zoom.x, vector_preview_enabled)
	return true


func prewarm_detail_region(region: Rect2, priority_points: Array = []) -> Dictionary:
	if not vector_preview_enabled:
		return {"ok": false, "error": "vector preview disabled"}
	if _detail_tile_preview == null and not attach_cached_detail():
		return {"ok": false, "error": "detail cache unavailable"}
	var result: Dictionary = await _detail_tile_preview.bake_region(region, priority_points)
	if not bool(result.get("ok", false)):
		return result
	# bake_region 更新共享 LRU；把新驻留纹理绑定到当前正式 renderer。
	var attached: Dictionary = _detail_tile_preview.attach_cached()
	if not bool(attached.get("ok", false)):
		return attached
	_detail_tile_preview.set_detail_zoom(_camera.zoom.x, true)
	return result


func prewarm_detail_regions(regions: Array) -> Dictionary:
	if not vector_preview_enabled:
		return {"ok": false, "error": "vector preview disabled"}
	if _detail_tile_preview == null and not attach_cached_detail():
		return {"ok": false, "error": "detail cache unavailable"}
	var result: Dictionary = await _detail_tile_preview.bake_regions(regions)
	if not bool(result.get("ok", false)):
		return result
	if bool(result.get("empty", false)):
		# 纯海域没有 Detail 内容：明确隐藏旧缓存，继续使用完整 Operational。
		_detail_tile_preview.set_detail_zoom(_camera.zoom.x, false)
		return result
	var attached: Dictionary = _detail_tile_preview.attach_cached()
	if not bool(attached.get("ok", false)):
		return attached
	_detail_tile_preview.set_detail_zoom(_camera.zoom.x, true)
	return result

func set_vector_preview_enabled(enabled: bool) -> bool:
	if enabled and ugc_vector_only:
		return false
	if enabled:
		if _camera == null or _world_rect.size.x <= 0.0:
			return false
		if not _prepare_vector_preview():
			return false
		_vector_preview.visible = true
		_vector_preview.update_lod()
		if _detail_tile_preview != null:
			_detail_tile_preview.set_detail_zoom(_camera.zoom.x, true)
		if _raster_basemap != null:
			_raster_basemap.set_active(false)
		if _basemap_sprite != null:
			_basemap_sprite.visible = false
		vector_preview_enabled = true
	else:
		vector_preview_enabled = false
		if _vector_preview != null:
			_vector_preview.visible = false
		if _detail_tile_preview != null:
			_detail_tile_preview.set_detail_zoom(_camera.zoom.x if _camera != null else 0.0, false)
		_ensure_basemap_loaded()
		if _raster_basemap != null:
			_raster_basemap.set_active(true)
		if _basemap_sprite != null:
			_basemap_sprite.visible = true
	queue_redraw()  # 仅切换时清一次父 CanvasItem 的静态命令缓存。
	return true


func _prepare_raster_basemap() -> bool:
	if _raster_basemap != null:
		return true
	if _camera == null or _basemap_world_rect.size.x <= 0.0:
		return false
	var map_key := basemap_map_key
	if map_key.is_empty():
		return false
	_raster_basemap = RasterBasemapRendererScript.new()
	_raster_basemap.name = "RasterBasemap"
	_raster_basemap.z_index = -1
	add_child(_raster_basemap)
	if not _raster_basemap.setup(_camera, _basemap_world_rect, map_key):
		_raster_basemap.queue_free()
		_raster_basemap = null
		return false
	_raster_basemap.set_active(tile_basemap_enabled)
	return true

func _draw() -> void:
	if not _camera:
		return
	if vector_preview_enabled:
		return
	MapGeography.ensure_ready()
	if not ugc_vector_only:
		_ensure_manual_loaded()
	if use_basemap:
		_ensure_basemap_loaded()
	# 底图存在时跳过 sea 色铺底 —— basemap 本身含海面颜色，再盖一层会遮住
	var has_basemap := (_basemap_sprite != null and _basemap_sprite.visible) \
		or (tile_basemap_enabled and _raster_basemap != null)
	if not has_basemap:
		_draw_sea()
	# 底图由 Sprite2D + ShaderMaterial 自行渲染（见 _ensure_basemap_loaded）
	if not has_basemap or not basemap_covers_vectors:
		_draw_land_mask()
		_draw_ugc_overlays()
		_draw_urban_districts()
		_draw_highways()
	_draw_manual_overlays()        # 手画 Polygon2D 叠加层
	_draw_haneda_airport()         # 港湾正式图：按冻结 OSM 中线补画羽田四条跑道
	_draw_ugc_airports()           # 预览图跑道必须压在底图上方；正式东京湾不重复描画
	# Aqua-Line 虚线不再绘制：正式底图已包含真实桥体，再画手画路径会双线对不齐
	# （曾做过 z_index=-5 的 MapBridgeLayer 实色覆盖，同样对不齐，已移除）
	# 解决"船穿桥"的方案改为：BOSS 刷新位置强制在桥南（见 ZoneData.BOSS_NORTH_CENTER）
	_draw_tacview_crosses()
	_draw_edge_vignette()          # 边界外逐层暗化
	if not _logged:
		_logged = true
		print("[MapFeatureRenderer] first _draw complete — all layers baked to canvas cache")

## 读取底图 + 元数据 → 创建带 Shader 的 Sprite2D
## 为什么用 Sprite2D 而不是 draw_texture_rect：Sprite2D 挂 ShaderMaterial 后
## Inspector 里修改 @export 变量能通过 _process 实时更新 shader uniform，
## 玩家看到立即生效（draw_texture_rect 的材质系统做不到这么灵活）
func _ensure_basemap_loaded() -> void:
	if not _basemap_loaded:
		_basemap_loaded = true
		if not use_basemap or basemap_meta_path == "" \
				or (basemap_map_key.is_empty() and basemap_png_path.is_empty()):
			return
		var meta_file := FileAccess.open(basemap_meta_path, FileAccess.READ)
		if meta_file == null:
			_report_basemap_error(
				"MAP_BASEMAP_ERROR_REASON_MISSING_METADATA",
				"basemap metadata missing: %s" % basemap_meta_path)
			return
		var meta = JSON.parse_string(meta_file.get_as_text())
		meta_file.close()
		if meta == null:
			_report_basemap_error(
				"MAP_BASEMAP_ERROR_REASON_INVALID_METADATA",
				"basemap metadata parse failed: %s" % basemap_meta_path)
			return
		# bbox 经纬度 → 游戏世界 Rect
		var bbox: Dictionary = meta.get("bbox_ll", {})
		var center_ll: Array = meta.get("game_world_center_latlon", [35.44, 139.76])
		var m_per_lat: float = float(meta.get("game_world_meters_per_degree_lat", 111000.0))
		var m_per_lon: float = float(meta.get("game_world_meters_per_degree_lon_at_center", 111000.0 * cos(deg_to_rad(35.44))))
		var px_per_m: float = float(meta.get("game_world_px_per_meter", 0.5))
		var lat_min: float = float(bbox.get("lat_min", 0))
		var lat_max: float = float(bbox.get("lat_max", 0))
		var lon_min: float = float(bbox.get("lon_min", 0))
		var lon_max: float = float(bbox.get("lon_max", 0))
		var cx: float = float(center_ll[1])
		var cy: float = float(center_ll[0])
		var x0 := (lon_min - cx) * m_per_lon * px_per_m
		var x1 := (lon_max - cx) * m_per_lon * px_per_m
		var y0 := -(lat_max - cy) * m_per_lat * px_per_m
		var y1 := -(lat_min - cy) * m_per_lat * px_per_m
		_basemap_world_rect = Rect2(Vector2(x0, y0), Vector2(x1 - x0, y1 - y0))

	if _basemap_world_rect.size.x <= 0.0:
		return
	if not basemap_map_key.is_empty():
		if tile_basemap_enabled:
			if _prepare_raster_basemap():
				_raster_basemap.set_active(true)
				if _basemap_sprite == null and not _streamed_ready_logged:
					_streamed_ready_logged = true
					print("[MapFeatureRenderer] tiled raster basemap ready: %s" % basemap_map_key)
				return
			tile_basemap_enabled = false
			_report_basemap_error(
				"MAP_BASEMAP_ERROR_REASON_MISSING_TEXTURE",
				"tiled basemap unavailable: %s" % basemap_map_key)
		return
	_ensure_legacy_basemap_loaded()


func _ensure_legacy_basemap_loaded() -> void:
	if _legacy_basemap_attempted or _basemap_sprite != null:
		return
	_legacy_basemap_attempted = true
	if not ResourceLoader.exists(basemap_png_path) and not FileAccess.file_exists(basemap_png_path):
		_report_basemap_error(
			"MAP_BASEMAP_ERROR_REASON_MISSING_TEXTURE",
			"basemap texture missing or not imported: %s" % basemap_png_path)
		return
	var tex := load(basemap_png_path) as Texture2D if ResourceLoader.exists(basemap_png_path) else null
	# 新 PNG 尚未生成 .import 时（例如干净 Shadow）仍可直接解码；正式包优先走导入纹理。
	if tex == null and FileAccess.file_exists(basemap_png_path):
		var image := Image.load_from_file(basemap_png_path)
		if image != null and not image.is_empty():
			tex = ImageTexture.create_from_image(image)
	if tex == null:
		_report_basemap_error(
			"MAP_BASEMAP_ERROR_REASON_TEXTURE_LOAD_FAILED",
			"failed to load basemap texture: %s" % basemap_png_path)
		return

	# 创建 Sprite2D + ShaderMaterial
	_basemap_sprite = Sprite2D.new()
	_basemap_sprite.texture = tex
	_basemap_sprite.centered = false
	# 缩放匹配 bbox rect
	var tex_size := tex.get_size()
	var rect_size := _basemap_world_rect.size
	_basemap_sprite.position = _basemap_world_rect.position
	_basemap_sprite.scale = Vector2(rect_size.x / tex_size.x, rect_size.y / tex_size.y)
	_basemap_sprite.z_index = -1  # 在自身 _draw 之下
	add_child(_basemap_sprite)

	var shader := load(BASEMAP_SHADER_PATH) as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_basemap_sprite.material = mat
		_apply_basemap_shader_params()
	print("[MapFeatureRenderer] basemap sprite ready: tex=%s rect=%s" % [tex_size, rect_size])

## 官方底图失败后仍允许旧矢量层兜底，但必须同时留下开发日志并告知玩家当前已降级。
func _report_basemap_error(reason_key: String, developer_detail: String) -> void:
	push_error("[MapFeatureRenderer] %s; legacy vector fallback active" % developer_detail)
	basemap_load_failed.emit(reason_key)

## 把 @export 参数同步到 shader uniform（每帧 _process 都调一次保证 Inspector 改动实时生效）
func _apply_basemap_shader_params() -> void:
	if _basemap_sprite == null or _basemap_sprite.material == null:
		return
	var mat := _basemap_sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("tint", basemap_tint)
	mat.set_shader_parameter("saturation", basemap_saturation)
	mat.set_shader_parameter("brightness", basemap_brightness)
	mat.set_shader_parameter("contrast", basemap_contrast)
	mat.set_shader_parameter("edge_strength", basemap_edge_strength)
	mat.set_shader_parameter("edge_color", basemap_edge_color)
	mat.set_shader_parameter("grain_strength", basemap_noise)
	mat.set_shader_parameter("grain_repeat", basemap_grain_repeat)
	if basemap_noise > 0.0001:
		if _basemap_grain_texture == null:
			_basemap_grain_texture = load(RasterBasemapRendererScript.GRAIN_TEXTURE_PATH) as Texture2D
		mat.set_shader_parameter("grain_texture", _basemap_grain_texture)

func _process(_delta: float) -> void:
	if vector_preview_enabled:
		if _vector_preview != null:
			_vector_preview.update_lod(_delta)
		if _detail_tile_preview != null:
			_detail_tile_preview.set_detail_zoom(_camera.zoom.x, true, _delta)
		return
	# 轻量：每帧同步 Inspector 的 basemap 参数到 shader
	# 只有 ~4 个 set_shader_parameter 调用，可忽略开销
	if _basemap_sprite != null:
		_apply_basemap_shader_params()

## 加载手画覆盖层：一次性扫描 map_manual.tscn 的 Polygon2D 子节点
func _ensure_manual_loaded() -> void:
	if _manual_loaded:
		return
	_manual_loaded = true
	if not ResourceLoader.exists(MANUAL_MAP_PATH):
		print("[MapFeatureRenderer] no manual overlay (%s) — skip" % MANUAL_MAP_PATH)
		return
	var scene := load(MANUAL_MAP_PATH) as PackedScene
	if scene == null:
		push_warning("[MapFeatureRenderer] failed to load %s" % MANUAL_MAP_PATH)
		return
	var inst: Node = scene.instantiate()
	_collect_polygon2d(inst, _manual_polys)
	inst.queue_free()
	print("[MapFeatureRenderer] manual overlay polygons loaded: %d" % _manual_polys.size())

## 递归收集 Polygon2D 节点
func _collect_polygon2d(node: Node, out: Array) -> void:
	if node is Polygon2D:
		var p2d: Polygon2D = node
		if p2d.polygon.size() >= 3:
			out.append({
				"pts": p2d.polygon,
				"color": p2d.color,
				"pos": p2d.global_position,
			})
	for child in node.get_children():
		_collect_polygon2d(child, out)

func _draw_manual_overlays() -> void:
	for m in _manual_polys:
		var pts: PackedVector2Array = m.pts
		var offset: Vector2 = m.get("pos", Vector2.ZERO)
		var col: Color = m.color
		# 如果 Polygon2D 在编辑器里有 position 偏移，平移一下
		if offset != Vector2.ZERO:
			var shifted := PackedVector2Array()
			for p in pts:
				shifted.append(p + offset)
			pts = shifted
		draw_colored_polygon(pts, col)

func _draw_sea() -> void:
	# 一次性画满整个世界矩形（加大余量），静态不再重绘
	# 相机如何移动/缩放都能看到海面，无需每帧跟随
	var rect := _world_rect.grow(8000.0)
	draw_rect(rect, _ugc_color("sea", MapGeography.SEA_COLOR), true)

## 陆地 mask：从 MapGeography 共享缓存读出预烘焙的 halo 多边形
## 全部实色 LAND_COLOR（alpha=1.0）；重叠无所谓，都是同一颜色
func _draw_land_mask() -> void:
	var polys := MapGeography.get_land_mask_polygons()
	for poly_any in polys:
		var poly: PackedVector2Array = poly_any
		draw_colored_polygon(poly, _ugc_color("land", LAND_MASK_COLOR))
	if not _logged:
		print("[MapFeatureRenderer] land mask polygons drawn: %d" % polys.size())


const UGC_RUNWAY_FILL := Color(0.20, 0.23, 0.22, 0.94)
const UGC_RUNWAY_EDGE := Color(0.68, 0.75, 0.70, 0.90)
const UGC_RUNWAY_CENTER := Color(0.86, 0.90, 0.82, 0.78)
const HANEDA_RUNWAY_FILL := Color(0.17, 0.20, 0.19, 0.92)
const HANEDA_RUNWAY_EDGE := Color(0.57, 0.63, 0.60, 0.88)
const HANEDA_RUNWAY_CENTER := Color(0.82, 0.85, 0.79, 0.76)

## 正式港湾图上的羽田跑道。四条中线与长度来自冻结 OSM 数据，已和 PNG 像素叠图核对。
## 所有命令只在地图 setup/切图时进入 CanvasItem 缓存，不逐帧重绘。
func _draw_haneda_airport() -> void:
	if MapGeography.ugc_mode:
		return
	for runway_any in MapGeography.HANEDA_RUNWAYS:
		var runway: Dictionary = runway_any
		var start: Vector2 = runway.get("start", Vector2.ZERO)
		var finish: Vector2 = runway.get("end", Vector2.ZERO)
		var width: float = float(runway.get("width", 30.0))
		var direction := start.direction_to(finish)
		var side := direction.orthogonal()
		draw_line(start, finish, HANEDA_RUNWAY_EDGE, width + 7.0, true)
		draw_line(start, finish, HANEDA_RUNWAY_FILL, width, true)
		draw_dashed_line(start, finish, HANEDA_RUNWAY_CENTER, 2.0, 42.0, true)
		for threshold in [start + direction * 18.0, finish - direction * 18.0]:
			draw_line(threshold - side * width * 0.31, threshold + side * width * 0.31,
				HANEDA_RUNWAY_CENTER, 2.0, true)

## PNG 底图会覆盖机场矢量，因此仅为 UGC/内置预览图静态补画跑道。
## 没有 _process；地图 setup 时进入 CanvasItem 缓存一次。
func _draw_ugc_airports() -> void:
	if not MapGeography.ugc_mode:
		return
	for poly_any in MapGeography.OSM_AERODROMES:
		var poly: PackedVector2Array = poly_any
		if poly.size() < 3:
			continue
		draw_colored_polygon(poly, UGC_RUNWAY_FILL)
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, UGC_RUNWAY_EDGE, 4.0, true)
		if poly.size() == 4:
			var start := (poly[0] + poly[3]) * 0.5
			var finish := (poly[1] + poly[2]) * 0.5
			draw_dashed_line(start, finish, UGC_RUNWAY_CENTER, 3.0, 36.0, true)

## 城区填充：立体化效果（阴影偏移 + 暗填充 + 亮描边 = 伪 3D 建筑）
const BUILDING_SHADOW_OFFSET := Vector2(3, 4)
const BUILDING_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const BUILDING_FILL_COLOR := Color(0.18, 0.22, 0.20, 0.85)
const BUILDING_EDGE_COLOR := Color(0.55, 0.75, 0.55, 0.85)
const BUILDING_EDGE_WIDTH := 1.0
func _draw_urban_districts() -> void:
	# Pass 1：阴影 —— 所有建筑偏移位置画一次暗色
	for poly_any in MapGeography.URBAN_DISTRICTS:
		var poly: PackedVector2Array = poly_any
		if poly.size() < 3:
			continue
		var shadow := PackedVector2Array()
		for p in poly:
			shadow.append(p + BUILDING_SHADOW_OFFSET)
		draw_colored_polygon(shadow, BUILDING_SHADOW_COLOR)
	# Pass 2：填充 + 描边
	for poly_any in MapGeography.URBAN_DISTRICTS:
		var poly: PackedVector2Array = poly_any
		if poly.size() < 3:
			continue
		draw_colored_polygon(poly, _ugc_color("urban", BUILDING_FILL_COLOR))
		var n: int = poly.size()
		for i in range(n):
			draw_line(poly[i], poly[(i + 1) % n], BUILDING_EDGE_COLOR, BUILDING_EDGE_WIDTH)

## UGC 地形覆盖层（叠在陆地 mask 上、城区之下；官方图此数组为空 → 零开销）
func _draw_ugc_overlays() -> void:
	for entry in ugc_overlay_layers:
		var col: Color = entry.get("color", Color.GRAY)
		for poly in entry.get("polys", []):
			if (poly as PackedVector2Array).size() >= 3:
				draw_colored_polygon(poly, col)


## 道路：Tacview 战术琥珀色，发光感（宽带底 + 细亮线）
const ROAD_GLOW_COLOR := Color(1.00, 0.70, 0.25, 0.35)
const ROAD_CORE_COLOR := Color(1.00, 0.85, 0.45, 0.95)
const ROAD_GLOW_WIDTH := 4.5
const ROAD_CORE_WIDTH := 1.4
func _draw_highways() -> void:
	var glow_color := _ugc_color("road_glow", ROAD_GLOW_COLOR)
	var core_color := _ugc_color("road_core", ROAD_CORE_COLOR)
	# Pass 1：橘色光晕（粗带半透）
	for hw_any in MapGeography.HIGHWAYS:
		var hw: Dictionary = hw_any
		var pts: PackedVector2Array = hw.get("pts", PackedVector2Array())
		if pts.size() < 2:
			continue
		draw_polyline(pts, glow_color, ROAD_GLOW_WIDTH, true)
	# Pass 2：亮核心（细线实色）
	for hw_any in MapGeography.HIGHWAYS:
		var hw: Dictionary = hw_any
		var pts: PackedVector2Array = hw.get("pts", PackedVector2Array())
		if pts.size() < 2:
			continue
		draw_polyline(pts, core_color, ROAD_CORE_WIDTH, true)
	if not _logged:
		print("[MapFeatureRenderer] stylized roads drawn: %d" % MapGeography.HIGHWAYS.size())

## 边界外 vignette：在 _world_rect 外面画 3 圈逐渐加深的暗色
## 让 OSM 数据延伸出界的部分自然淡入黑暗，不再硬切到海色
## 每圈用 4 个长方形覆盖外围 4 边
func _draw_edge_vignette() -> void:
	var prev_outer := 0.0
	for ring_def in VIGNETTE_RINGS:
		var outer: float = ring_def.outer
		var color: Color = ring_def.color
		_draw_ring_frame(prev_outer, outer, color)
		prev_outer = outer
	if not _logged:
		print("[MapFeatureRenderer] vignette rings: %d" % VIGNETTE_RINGS.size())

## 画一圈 "环形" 的 4 个边矩形：外层距 world_rect 外缘 outer，内层距 inner
func _draw_ring_frame(inner: float, outer: float, color: Color) -> void:
	var wr := _world_rect
	var inner_rect := wr.grow(inner)
	var outer_rect := wr.grow(outer)
	# 顶 / 底 / 左 / 右 四块，共同覆盖 outer_rect 减去 inner_rect
	# 顶
	draw_rect(Rect2(
		outer_rect.position,
		Vector2(outer_rect.size.x, inner_rect.position.y - outer_rect.position.y)
	), color, true)
	# 底
	draw_rect(Rect2(
		Vector2(outer_rect.position.x, inner_rect.position.y + inner_rect.size.y),
		Vector2(outer_rect.size.x, outer_rect.position.y + outer_rect.size.y - (inner_rect.position.y + inner_rect.size.y))
	), color, true)
	# 左
	draw_rect(Rect2(
		Vector2(outer_rect.position.x, inner_rect.position.y),
		Vector2(inner_rect.position.x - outer_rect.position.x, inner_rect.size.y)
	), color, true)
	# 右
	draw_rect(Rect2(
		Vector2(inner_rect.position.x + inner_rect.size.x, inner_rect.position.y),
		Vector2(outer_rect.position.x + outer_rect.size.x - (inner_rect.position.x + inner_rect.size.x), inner_rect.size.y)
	), color, true)

## 跨湾通道：虚线
func _draw_aqualine() -> void:
	var pts: PackedVector2Array = MapGeography.AQUALINE_PATH
	if pts.size() < 2:
		return
	const DASH := 120.0
	const GAP := 60.0
	for i in range(pts.size() - 1):
		_draw_dashed_segment(pts[i], pts[i + 1], DASH, GAP, MapGeography.AQUALINE_COLOR, 1.8)

func _draw_dashed_segment(a: Vector2, b: Vector2, dash: float, gap: float, color: Color, width: float) -> void:
	var total := a.distance_to(b)
	if total <= 0.0:
		return
	var dir := (b - a).normalized()
	var pos := 0.0
	while pos < total:
		var seg_end := minf(pos + dash, total)
		draw_line(a + dir * pos, a + dir * seg_end, color, width)
		pos = seg_end + gap

## TacView 风格十字标记：海面上稀疏规则网格
func _draw_tacview_crosses() -> void:
	var rect := _world_rect.grow(500.0)
	var count := 0
	var cross_color := _ugc_color("tacview_cross", TACVIEW_COLOR)
	var x := snappedf(rect.position.x, TACVIEW_SPACING)
	while x < rect.position.x + rect.size.x:
		var y := snappedf(rect.position.y, TACVIEW_SPACING)
		while y < rect.position.y + rect.size.y:
			var p := Vector2(x, y)
			if not MapGeography.is_on_land(p):
				draw_line(Vector2(p.x - TACVIEW_SIZE, p.y), Vector2(p.x + TACVIEW_SIZE, p.y), cross_color, 0.8)
				draw_line(Vector2(p.x, p.y - TACVIEW_SIZE), Vector2(p.x, p.y + TACVIEW_SIZE), cross_color, 0.8)
				count += 1
			y += TACVIEW_SPACING
		x += TACVIEW_SPACING
	if not _logged:
		print("[MapFeatureRenderer] tacview crosses: %d" % count)


func _ugc_color(key: String, fallback: Color) -> Color:
	var raw = ugc_palette.get(key, null)
	if raw is Array and raw.size() >= 3:
		return Color(float(raw[0]), float(raw[1]), float(raw[2]),
			float(raw[3]) if raw.size() >= 4 else 1.0)
	return fallback

func _polygon_aabb(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var mn: Vector2 = poly[0]
	var mx: Vector2 = poly[0]
	for p in poly:
		mn.x = minf(mn.x, p.x)
		mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x)
		mx.y = maxf(mx.y, p.y)
	return Rect2(mn, mx - mn)
