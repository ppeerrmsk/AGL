class_name MapFeatureRenderer
extends Node2D

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

## 可选真实底图（OSM no-labels 瓦片拼成的 PNG）
## 如果两个文件都存在，底图会作为最底层渲染，覆盖游戏世界内 bbox 对应区域
## 图像 + 元数据由 scripts/tools/download_basemap.py 生成
const BASEMAP_PNG_PATH := "res://resources/maps/tokyo_bay_bg.png"
const BASEMAP_META_PATH := "res://resources/maps/tokyo_bay_bg.json"

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
## CRT 颗粒噪点强度
@export_range(0.0, 0.3, 0.01) var basemap_noise: float = 0.03
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

func _draw() -> void:
	if not _camera:
		return
	MapGeography.ensure_ready()
	_ensure_manual_loaded()
	_ensure_basemap_loaded()
	# 底图存在时跳过 sea 色铺底 —— basemap 本身含海面颜色，再盖一层会遮住
	if _basemap_sprite == null:
		_draw_sea()
	# 底图由 Sprite2D + ShaderMaterial 自行渲染（见 _ensure_basemap_loaded）
	if _basemap_sprite == null or not basemap_covers_vectors:
		_draw_land_mask()
		_draw_urban_districts()
		_draw_highways()
	_draw_manual_overlays()        # 手画 Polygon2D 叠加层
	_draw_aqualine()
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
	if _basemap_loaded:
		return
	_basemap_loaded = true
	if not ResourceLoader.exists(BASEMAP_PNG_PATH):
		print("[MapFeatureRenderer] no basemap at %s — skip" % BASEMAP_PNG_PATH)
		return
	var meta_file := FileAccess.open(BASEMAP_META_PATH, FileAccess.READ)
	if meta_file == null:
		push_warning("[MapFeatureRenderer] basemap PNG exists but no meta JSON — skip")
		return
	var meta = JSON.parse_string(meta_file.get_as_text())
	meta_file.close()
	if meta == null:
		push_warning("[MapFeatureRenderer] basemap meta JSON parse failed — skip")
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

	var tex := load(BASEMAP_PNG_PATH) as Texture2D
	if tex == null:
		push_warning("[MapFeatureRenderer] failed to load basemap texture")
		return

	# 创建 Sprite2D + ShaderMaterial
	_basemap_sprite = Sprite2D.new()
	_basemap_sprite.texture = tex
	_basemap_sprite.centered = false
	# 缩放匹配 bbox rect
	var tex_size := tex.get_size()
	var rect_size := Vector2(x1 - x0, y1 - y0)
	_basemap_sprite.position = Vector2(x0, y0)
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
	mat.set_shader_parameter("noise_strength", basemap_noise)

func _process(_delta: float) -> void:
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
	draw_rect(rect, MapGeography.SEA_COLOR, true)

## 陆地 mask：从 MapGeography 共享缓存读出预烘焙的 halo 多边形
## 全部实色 LAND_COLOR（alpha=1.0）；重叠无所谓，都是同一颜色
func _draw_land_mask() -> void:
	var polys := MapGeography.get_land_mask_polygons()
	for poly_any in polys:
		var poly: PackedVector2Array = poly_any
		draw_colored_polygon(poly, LAND_MASK_COLOR)
	if not _logged:
		print("[MapFeatureRenderer] land mask polygons drawn: %d" % polys.size())

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
		draw_colored_polygon(poly, BUILDING_FILL_COLOR)
		var n: int = poly.size()
		for i in range(n):
			draw_line(poly[i], poly[(i + 1) % n], BUILDING_EDGE_COLOR, BUILDING_EDGE_WIDTH)

## 道路：Tacview 战术琥珀色，发光感（宽带底 + 细亮线）
const ROAD_GLOW_COLOR := Color(1.00, 0.70, 0.25, 0.35)
const ROAD_CORE_COLOR := Color(1.00, 0.85, 0.45, 0.95)
const ROAD_GLOW_WIDTH := 4.5
const ROAD_CORE_WIDTH := 1.4
func _draw_highways() -> void:
	# Pass 1：橘色光晕（粗带半透）
	for hw_any in MapGeography.HIGHWAYS:
		var hw: Dictionary = hw_any
		var pts: PackedVector2Array = hw.get("pts", PackedVector2Array())
		if pts.size() < 2:
			continue
		draw_polyline(pts, ROAD_GLOW_COLOR, ROAD_GLOW_WIDTH, true)
	# Pass 2：亮核心（细线实色）
	for hw_any in MapGeography.HIGHWAYS:
		var hw: Dictionary = hw_any
		var pts: PackedVector2Array = hw.get("pts", PackedVector2Array())
		if pts.size() < 2:
			continue
		draw_polyline(pts, ROAD_CORE_COLOR, ROAD_CORE_WIDTH, true)
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
	var x := snappedf(rect.position.x, TACVIEW_SPACING)
	while x < rect.position.x + rect.size.x:
		var y := snappedf(rect.position.y, TACVIEW_SPACING)
		while y < rect.position.y + rect.size.y:
			var p := Vector2(x, y)
			if not MapGeography.is_on_land(p):
				draw_line(Vector2(p.x - TACVIEW_SIZE, p.y), Vector2(p.x + TACVIEW_SIZE, p.y), TACVIEW_COLOR, 0.8)
				draw_line(Vector2(p.x, p.y - TACVIEW_SIZE), Vector2(p.x, p.y + TACVIEW_SIZE), TACVIEW_COLOR, 0.8)
				count += 1
			y += TACVIEW_SPACING
		x += TACVIEW_SPACING
	if not _logged:
		print("[MapFeatureRenderer] tacview crosses: %d" % count)

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
