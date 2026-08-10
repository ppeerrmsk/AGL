class_name MapGeography
extends RefCounted

## 生存模式"海岸线"大地图几何数据
##
## 原型 = 东京湾（横浜 / 川崎 / 羽田 / 三浦半岛 + 木更津 / 富津半岛），
## 但所有可见地名将替换为虚构代号（如 CITY-α）。
##
## 坐标系：原点 = 地图中心（湾心），1 px = 2 m，矩形 ±7500 px (= 30km × 30km)
## X+ 东，Y+ 南
##
## 地理参考中心约 (35.44°N, 139.76°E)。所有多边形顶点顺序为"陆地在左"
## 的连续轮廓（从贴北边的起点出发，沿海岸走到贴南边的终点，闭合回起点走北/南边界）。
## 海岸线描边时跳过首段（顶边）和最后闭合段（侧边）。

# ══════════════════════════════════════════════
#  颜色
# ══════════════════════════════════════════════

const SEA_COLOR := Color(0.16, 0.24, 0.32, 1.0)        ## 海面深蓝灰
const LAND_COLOR := Color(0.32, 0.35, 0.27, 1.0)       ## 陆地橄榄
const LAND_INNER := Color(0.37, 0.40, 0.31, 0.45)      ## 内陆高光
const COAST_COLOR := Color(0.82, 0.93, 0.96, 0.95)     ## 海岸线亮青白（调亮）
const COAST_GLOW := Color(0.55, 0.80, 0.90, 0.35)      ## 海岸外光晕
const URBAN_FILL := Color(0.85, 0.70, 0.45, 0.22)      ## 城区填充（暖色半透）
const URBAN_LINE := Color(0.95, 0.80, 0.50, 0.70)      ## 城区描边
const HIGHWAY_MAIN := Color(0.95, 0.75, 0.35, 0.85)    ## 主干高速
const HIGHWAY_SUB := Color(0.75, 0.70, 0.55, 0.60)     ## 次级道路
const AQUALINE_COLOR := Color(0.70, 0.90, 1.00, 0.65)  ## 跨湾通道（虚线）
const STREET_GRID_COLOR := Color(0.45, 0.48, 0.40, 0.55)  ## 街区细线

# ══════════════════════════════════════════════
#  陆地主多边形
# ══════════════════════════════════════════════

## 西岸：大田区 / 川崎 / 横滨 / 三浦半岛（东侧经横须贺，南端三浦）
static var LAND_WEST := PackedVector2Array([
	# NW 角，沿北边界东行至海陆分界
	Vector2(-7500, -7500),
	Vector2(-1500, -7500),
	# 大田区南海岸（羽田北部）
	Vector2(-1200, -7100),
	Vector2(-800, -6900),
	Vector2(-300, -6800),
	# 多摩川河口（一个向东的小缺口）
	Vector2(-100, -6600),
	Vector2(-400, -6400),
	# 川崎北岸起点
	Vector2(-100, -6200),
	Vector2(200, -5900),
	# 川崎工业港复杂突堤群（来回锯齿）
	Vector2(400, -5600),
	Vector2(600, -5300),
	Vector2(200, -5100),
	Vector2(500, -4800),
	Vector2(100, -4600),
	Vector2(400, -4300),
	Vector2(-200, -4100),
	Vector2(200, -3800),
	Vector2(-400, -3600),
	Vector2(-100, -3300),
	Vector2(-600, -3100),
	Vector2(-300, -2800),
	Vector2(-900, -2600),
	# 接入横滨：神奈川 / 鹤见
	Vector2(-1400, -2300),
	Vector2(-1800, -2000),
	# 横滨港 · 港未来 · 赤砖仓库（向东凸出）
	Vector2(-1900, -1700),
	Vector2(-1500, -1500),
	Vector2(-1800, -1200),
	Vector2(-2100, -900),
	# 本牧岬（明显东凸）
	Vector2(-2500, -700),
	Vector2(-2200, -400),
	Vector2(-2000, -100),
	Vector2(-2400, 200),
	Vector2(-2800, 400),
	# 磯子 / 金泽八景
	Vector2(-3100, 800),
	Vector2(-3300, 1300),
	Vector2(-3600, 1800),
	# 海岸转向三浦半岛：逗子 → 横须贺东岸（在湾内）
	Vector2(-3800, 2400),
	Vector2(-3900, 3000),
	Vector2(-3800, 3500),
	Vector2(-3600, 4000),
	# 横须贺港凹口
	Vector2(-3800, 4400),
	Vector2(-3500, 4700),
	Vector2(-3300, 5000),
	# 浦贺水道（湾口西岸）
	Vector2(-3400, 5400),
	Vector2(-3700, 5800),
	Vector2(-4200, 6200),
	# 三浦半岛南端
	Vector2(-4700, 6600),
	Vector2(-5200, 6900),
	Vector2(-5800, 7100),
	Vector2(-6400, 7300),
	# 出南边界（三浦市 / 城岛）
	Vector2(-6900, 7500),
	# SW 角闭合，沿西边界上行回到 NW
	Vector2(-7500, 7500),
])

## 东岸：市川 / 袖浦 / 木更津 + 富津半岛（向西凸出的细长沙嘴）+ 君津
static var LAND_EAST := PackedVector2Array([
	# NE 角，沿北边界西行至海陆分界
	Vector2(7500, -7500),
	Vector2(4500, -7500),
	# 市川 / 船桥南部海岸（一段平直）
	Vector2(4200, -7100),
	Vector2(3900, -6700),
	Vector2(3700, -6300),
	# 袖浦石油化学区（锯齿港）
	Vector2(3500, -5900),
	Vector2(3800, -5600),
	Vector2(3400, -5300),
	Vector2(3700, -5000),
	Vector2(3300, -4700),
	# 木更津港（向西小凸）
	Vector2(3500, -4300),
	Vector2(3100, -4000),
	Vector2(3400, -3700),
	Vector2(3000, -3400),
	Vector2(3200, -3000),
	# 木更津南海岸缓慢向西：君津方向
	Vector2(3300, -2600),
	Vector2(3100, -2200),
	Vector2(3300, -1800),
	Vector2(3000, -1400),
	Vector2(3100, -1000),
	# 君津东侧
	Vector2(3300, -600),
	Vector2(3500, -200),
	Vector2(3700, 300),
	# 富津半岛起点：从 x≈3800, y≈600 开始向西凸出
	Vector2(3900, 700),
	Vector2(3800, 1100),
	# 富津半岛"顶边"（向西）
	Vector2(3500, 1400),
	Vector2(2900, 1600),
	Vector2(2200, 1750),
	Vector2(1500, 1850),
	Vector2(1000, 1950),
	# 富津沙嘴西端（"ふっつみさき"）
	Vector2(700, 2050),
	Vector2(800, 2250),
	Vector2(1200, 2350),
	# 富津半岛"底边"（折回向东）
	Vector2(1800, 2450),
	Vector2(2500, 2550),
	Vector2(3200, 2650),
	Vector2(3800, 2800),
	# 回到南岸大陆
	Vector2(4200, 3000),
	Vector2(4500, 3400),
	Vector2(4800, 3800),
	# 富津市区南侧
	Vector2(5100, 4300),
	Vector2(5400, 4800),
	Vector2(5700, 5300),
	Vector2(6000, 5800),
	Vector2(6300, 6300),
	Vector2(6600, 6800),
	Vector2(6900, 7200),
	# 出南边界
	Vector2(7200, 7500),
	# SE 角闭合，沿东边界上行
	Vector2(7500, 7500),
])

# ══════════════════════════════════════════════
#  羽田机场（独立岛屿多边形）
# ══════════════════════════════════════════════
## 羽田机场：东京湾北侧的人工岛，视觉上是独立形状（有短桥连大陆）
## 简化为一个有 4 条跑道轮廓的多边形
static var HANEDA_AIRPORT := PackedVector2Array([
	Vector2(400, -6800),     # 西北
	Vector2(1300, -6800),    # 东北
	Vector2(1800, -6500),    # 东跑道突出
	Vector2(2000, -6100),
	Vector2(1800, -5700),
	Vector2(1400, -5500),
	Vector2(800, -5400),
	Vector2(400, -5600),
	Vector2(200, -6000),
	Vector2(200, -6400),
])

## 羽田四条正式跑道中线：来自冻结的东京湾 OSM runway 数据，并已和正式 PNG 叠图核对。
## 1 px = 2 m；width 28~30 px 对应约 56~60 m。这里只存静态视觉数据，不参与陆地/任务判定。
static var HANEDA_RUNWAYS: Array[Dictionary] = [
	{"start": Vector2(40.19, -6025.35), "end": Vector2(790.91, -7098.64), "width": 28.0},
	{"start": Vector2(1159.45, -5362.92), "end": Vector2(410.03, -6658.89), "width": 30.0},
	{"start": Vector2(2055.66, -5507.35), "end": Vector2(1186.12, -7011.18), "width": 30.0},
	{"start": Vector2(1965.63, -4661.78), "end": Vector2(2805.72, -5579.76), "width": 30.0},
]

## 陆地多边形（应用 Chaikin 平滑去锐角 — 仅平滑海岸线段，bbox 贴边顶点保留）
## LAND_WEST/LAND_EAST 首尾 2 顶点贴 bbox 作为锚点，中间的"真海岸"段才做 Chaikin
## HANEDA_AIRPORT 是完全闭合的岛，整体平滑
const LAND_SMOOTH_ITER := 2       # 2 次 Chaikin = 每段边 → 4 段
const LAND_BBOX_ANCHORS := 2      # LAND_WEST/EAST 首/尾保留顶点数

static var _land_smoothed_cache: Array = []
static var _land_smoothed_built: bool = false

static func get_land_polygons() -> Array:
	if not _land_smoothed_built:
		_land_smoothed_built = true
		_land_smoothed_cache.append(_chaikin_open(LAND_WEST, LAND_SMOOTH_ITER, LAND_BBOX_ANCHORS, LAND_BBOX_ANCHORS))
		_land_smoothed_cache.append(_chaikin_open(LAND_EAST, LAND_SMOOTH_ITER, LAND_BBOX_ANCHORS, LAND_BBOX_ANCHORS))
		_land_smoothed_cache.append(_chaikin_closed(HANEDA_AIRPORT, LAND_SMOOTH_ITER))
		print("[MapGeography] Chaikin smoothed land — WEST=%d EAST=%d HANEDA=%d verts" % [
			_land_smoothed_cache[0].size(),
			_land_smoothed_cache[1].size(),
			_land_smoothed_cache[2].size(),
		])
	return _land_smoothed_cache

## Chaikin 平滑（开放折线版）：对 poly 中间段做角切，首 keep_first 与尾 keep_last 个顶点保留
## 每次迭代：每条中间段 a→b 被替换为 (0.75a+0.25b, 0.25a+0.75b) 两点
static func _chaikin_open(poly: PackedVector2Array, iterations: int, keep_first: int, keep_last: int) -> PackedVector2Array:
	if poly.size() < keep_first + keep_last + 2:
		return poly
	var head := PackedVector2Array()
	var tail := PackedVector2Array()
	for i in range(keep_first):
		head.append(poly[i])
	for i in range(poly.size() - keep_last, poly.size()):
		tail.append(poly[i])
	var middle := PackedVector2Array()
	for i in range(keep_first, poly.size() - keep_last):
		middle.append(poly[i])
	for _iter in range(iterations):
		if middle.size() < 2:
			break
		var out := PackedVector2Array()
		out.append(middle[0])
		for i in range(middle.size() - 1):
			var a: Vector2 = middle[i]
			var b: Vector2 = middle[i + 1]
			out.append(a * 0.75 + b * 0.25)
			out.append(a * 0.25 + b * 0.75)
		out.append(middle[middle.size() - 1])
		middle = out
	var result := PackedVector2Array()
	for p in head:
		result.append(p)
	for p in middle:
		result.append(p)
	for p in tail:
		result.append(p)
	return result

## Chaikin 平滑（闭合多边形版）：所有边都参与
static func _chaikin_closed(poly: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var cur := poly
	for _iter in range(iterations):
		var out := PackedVector2Array()
		var n := cur.size()
		for i in range(n):
			var a: Vector2 = cur[i]
			var b: Vector2 = cur[(i + 1) % n]
			out.append(a * 0.75 + b * 0.25)
			out.append(a * 0.25 + b * 0.75)
		cur = out
	return cur

# ══════════════════════════════════════════════
#  城区多边形（OSM 烘焙）+ 道路 —— 懒加载
# ══════════════════════════════════════════════
## 这些数组在 ensure_ready() 之前都是 []
## 所有调用方（MapFeatureRenderer / TacticalMap / MapManualBackground）
## 必须在读取 URBAN_DISTRICTS / HIGHWAYS / COASTLINE_LINES 之前先调 ensure_ready()
##
## 不用 static var 初始化器直接赋值，因为 Godot 编辑器里 MapGeographyData 的 JSON
## 数据还没加载时就会被引用，只能拿到空数组
static var URBAN_DISTRICTS: Array = []
static var COASTLINE_LINES: Array = []
static var OSM_AERODROMES: Array = []

static var _initialized: bool = false

## 懒加载入口：首次调用 → MapGeographyData 读 JSON → 填充本类的静态字段
## 所有读取 URBAN_DISTRICTS / HIGHWAYS / COASTLINE_LINES 前都要先调这个
static func ensure_ready() -> void:
	if _initialized:
		return
	_initialized = true
	MapGeographyData.ensure_loaded()
	URBAN_DISTRICTS = MapGeographyData.URBAN_POLYGONS
	COASTLINE_LINES = MapGeographyData.COASTLINE_LINES
	OSM_AERODROMES = MapGeographyData.AERODROME_POLYGONS
	HIGHWAYS = _build_highways_from_osm()
	print("[MapGeography] ready — URBAN=%d HIGHWAYS=%d COAST=%d" % [
		URBAN_DISTRICTS.size(), HIGHWAYS.size(), COASTLINE_LINES.size(),
	])


## UGC 注入后强制重建派生缓存（UgcLoader 调用；官方路径不走这里）
static func rebuild_from_data() -> void:
	_initialized = false
	ensure_ready()

## === 以下为被 OSM 替换的旧手画数据，保留注释以便回溯历史 ===
static var _LEGACY_URBAN_DISTRICTS: Array = [
	# 川崎市区
	PackedVector2Array([
		Vector2(-2300, -5400),
		Vector2(-600, -5400),
		Vector2(-200, -5000),
		Vector2(-400, -4400),
		Vector2(-1000, -4000),
		Vector2(-1800, -3900),
		Vector2(-2300, -4400),
		Vector2(-2500, -5000),
	]),
	# 横滨核心（港未来 / 关内 / 神奈川）
	PackedVector2Array([
		Vector2(-3200, -2400),
		Vector2(-1900, -2400),
		Vector2(-1500, -1900),
		Vector2(-1700, -1200),
		Vector2(-2300, -700),
		Vector2(-3000, -700),
		Vector2(-3500, -1400),
		Vector2(-3500, -2000),
	]),
	# 横须贺 / 逗子
	PackedVector2Array([
		Vector2(-5800, 3200),
		Vector2(-3800, 3200),
		Vector2(-3400, 3700),
		Vector2(-3500, 4600),
		Vector2(-4200, 5000),
		Vector2(-5300, 5000),
		Vector2(-5900, 4500),
		Vector2(-6100, 3800),
	]),
	# 木更津 / 袖浦
	PackedVector2Array([
		Vector2(3500, -5600),
		Vector2(5200, -5600),
		Vector2(5700, -5000),
		Vector2(5800, -4100),
		Vector2(5400, -3400),
		Vector2(4500, -3000),
		Vector2(3700, -3200),
		Vector2(3300, -4000),
		Vector2(3300, -4900),
	]),
	# 君津 / 富津市区
	PackedVector2Array([
		Vector2(4200, 3000),
		Vector2(5800, 3000),
		Vector2(6400, 3600),
		Vector2(6500, 4500),
		Vector2(6000, 5200),
		Vector2(5200, 5100),
		Vector2(4500, 4500),
		Vector2(4300, 3700),
	]),
	# 大田 / 品川（北部工业带）
	PackedVector2Array([
		Vector2(-4000, -7400),
		Vector2(-1500, -7400),
		Vector2(-1000, -7100),
		Vector2(-1200, -6500),
		Vector2(-2200, -6300),
		Vector2(-3500, -6500),
		Vector2(-4200, -6900),
	]),
]

# ══════════════════════════════════════════════
#  道路（OSM 烘焙分档）
# ══════════════════════════════════════════════
## motorway / trunk / primary / secondary 四档
## 统一格式：Array[{"pts": PackedVector2Array, "color": Color, "width": float}]
## 供 MapFeatureRenderer._draw_highways 直接消费（由 ensure_ready() 填充）
static var HIGHWAYS: Array = []

static func _build_highways_from_osm() -> Array:
	var out: Array = []
	for pts in MapGeographyData.ROADS_MOTORWAY:
		out.append({"pts": pts, "color": Color(0.98, 0.75, 0.30, 0.92), "width": 2.4})
	for pts in MapGeographyData.ROADS_TRUNK:
		out.append({"pts": pts, "color": Color(0.98, 0.80, 0.40, 0.85), "width": 1.9})
	for pts in MapGeographyData.ROADS_PRIMARY:
		out.append({"pts": pts, "color": Color(0.92, 0.87, 0.70, 0.80), "width": 1.5})
	for pts in MapGeographyData.ROADS_SECONDARY:
		out.append({"pts": pts, "color": Color(0.85, 0.82, 0.70, 0.62), "width": 1.1})
	print("[MapGeography] HIGHWAYS built from OSM: %d segments (M=%d T=%d P=%d S=%d)" % [
		out.size(),
		MapGeographyData.ROADS_MOTORWAY.size(),
		MapGeographyData.ROADS_TRUNK.size(),
		MapGeographyData.ROADS_PRIMARY.size(),
		MapGeographyData.ROADS_SECONDARY.size(),
	])
	return out

## 跨湾通道（类比东京湾 Aqua-Line：川崎到木更津的海底隧道 + 海上桥）
## 在地图上显示为虚线
static var AQUALINE_PATH := PackedVector2Array([
	Vector2(500, -4700),       # 起点：川崎湾岸
	Vector2(1300, -3800),      # 海底段
	Vector2(2000, -3000),      # 海萤岛（中继换桥）
	Vector2(2700, -2200),
	Vector2(3300, -1400),      # 终点：木更津侧登陆
])

# ══════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════

## UGC 地图模式守卫（UgcLoader.apply_geography 置 true / clear 复位）
## 官方路径（ugc_mode=false）行为与历史完全一致。
static var ugc_mode := false
## UGC 陆地层判定语义（spec map-editor §3.4）：
##   true  = 偶奇计数（编辑器烘焙环组，孔洞=独立环）
##   false = union 任一命中（官方转换直通多边形，与官方判定一字不差）
static var ugc_land_even_odd := true

## 正式东京湾生产 PNG 对齐的精细水面环。它只给玩法做港池/河道排除，
## 不启用或替换纯矢量地图渲染。UGC 地图不读取这份官方蒙版。
const VISUAL_WATER_MASK_PATH := "res://resources/maps/tokyo_bay_vector_preview.json"
const GROUND_SPAWN_CLEARANCE_PX := 50.0  ## 100m；避免单位中心虽在岸上、图标却悬到水面
const GROUND_CLEARANCE_SAMPLES := 8
const GROUND_SEARCH_STEP_PX := 50.0
const GROUND_SEARCH_ANGLES := 24

static var _visual_water_masks_loaded := false
static var _visual_water_masks: Array[Dictionary] = []
static var _visual_land_inlay_masks: Array[Dictionary] = []

## 判断某世界坐标是否在陆地上（包括羽田机场）
## 同时检查 OSM 烘焙的 land mask（城区+道路外扩并集，精度高）+ 手画 LAND 轮廓（覆盖广）
## 任一命中即视为陆地
static func is_on_land(pos: Vector2) -> bool:
	ensure_ready()
	if ugc_mode:
		if ugc_land_even_odd:
			# 编辑器烘焙环组：偶奇计数（支持湖泊等孔洞）
			var hits := 0
			for poly in MapGeographyData.LAND_MASK_POLYGONS:
				if Geometry2D.is_point_in_polygon(pos, poly):
					hits += 1
			return hits % 2 == 1
		# 官方转换直通：任一命中即陆地（与官方逻辑同构）
		for poly in MapGeographyData.LAND_MASK_POLYGONS:
			if Geometry2D.is_point_in_polygon(pos, poly):
				return true
		return false
	# OSM 陆地 mask 优先（对玩家活动区精确）
	for poly in MapGeographyData.LAND_MASK_POLYGONS:
		if Geometry2D.is_point_in_polygon(pos, poly):
			return true
	# 手画 LAND 兜底（覆盖 OSM 没 landuse 标记的山林区）
	for poly in get_land_polygons():
		if Geometry2D.is_point_in_polygon(pos, poly):
			return true
	return false

## 严格陆地判定：只使用 OSM 烘焙的 LAND_MASK（城区+道路外扩并集）
## 手画 LAND 轮廓虽然覆盖广，但会把港池、码头之间的海湾也包进轮廓里，导致 is_on_land
## 误判"港内海水"为陆地（SAM/AA 因此刷到水面上）。
## 用来给地面单位选位、判定战区是否有足够陆地。
static func is_on_land_strict(pos: Vector2) -> bool:
	ensure_ready()
	if ugc_mode:
		return is_on_land(pos)  # UGC 只有一层并集后的陆地，严格/宽松同源
	for poly in MapGeographyData.LAND_MASK_POLYGONS:
		if Geometry2D.is_point_in_polygon(pos, poly):
			return true
	return false

## 实体陆地判定：地面目标/单位不得把跨海公路、桥梁的 OSM 外扩当作陆地。
## 官方图同时要求命中精细 land mask 与手画大轮廓；UGC 只有明确陆地层，沿用其判定。
static func is_on_solid_land(pos: Vector2) -> bool:
	if ugc_mode:
		return is_on_land_strict(pos)
	if not is_on_land_strict(pos):
		return false
	for poly in get_land_polygons():
		if Geometry2D.is_point_in_polygon(pos, poly):
			return true
	return false

## 正式地面单位的统一部署硬闸：
## 1. 先过实体陆地；2. 排除与生产底图对齐的港池/河道水面；
## 3. 中心周围 clearance_px 的 8 个方向仍须连续为陆地。
static func is_ground_spawn_safe(pos: Vector2,
		clearance_px: float = GROUND_SPAWN_CLEARANCE_PX) -> bool:
	if not _is_ground_surface(pos):
		return false
	if clearance_px <= 0.0:
		return true
	for i in range(GROUND_CLEARANCE_SAMPLES):
		var angle := float(i) * TAU / float(GROUND_CLEARANCE_SAMPLES)
		if not _is_ground_surface(pos + Vector2.from_angle(angle) * clearance_px):
			return false
	return true

## 固定编成偏移落在港池/岸边时，按确定性同心环寻找附近安全陆地。
## 无解返回 INF；调用方必须缩编/跳过，禁止回退到水面。
static func find_ground_spawn_near(anchor: Vector2, max_radius_px: float,
		clearance_px: float = GROUND_SPAWN_CLEARANCE_PX) -> Vector2:
	if is_ground_spawn_safe(anchor, clearance_px):
		return anchor
	var ring_count := ceili(maxf(max_radius_px, 0.0) / GROUND_SEARCH_STEP_PX)
	for ring in range(1, ring_count + 1):
		var radius := minf(float(ring) * GROUND_SEARCH_STEP_PX, max_radius_px)
		for i in range(GROUND_SEARCH_ANGLES):
			var angle := float(i) * TAU / float(GROUND_SEARCH_ANGLES)
			var candidate := anchor + Vector2.from_angle(angle) * radius
			if is_ground_spawn_safe(candidate, clearance_px):
				return candidate
	return Vector2.INF

static func _is_ground_surface(pos: Vector2) -> bool:
	if ugc_mode:
		return is_on_solid_land(pos)
	# 60km 扩图后的外圈陆地已超出旧手画 LAND_WEST/EAST；正式部署以全图 OSM land mask
	# 为正集，再减去与生产底图对齐的视觉水面。旧手画轮廓不再充当全图硬交集。
	if not is_on_land_strict(pos):
		return false
	_ensure_visual_water_masks()
	# land_inlay 是水面环内重新盖回的码头/岛屿，优先恢复为陆地。
	if _point_in_mask_entries(pos, _visual_land_inlay_masks):
		return true
	return not _point_in_mask_entries(pos, _visual_water_masks)

static func _ensure_visual_water_masks() -> void:
	if _visual_water_masks_loaded:
		return
	_visual_water_masks_loaded = true
	var file := FileAccess.open(VISUAL_WATER_MASK_PATH, FileAccess.READ)
	if file == null:
		push_warning("MapGeography: visual water mask unavailable; using solid-land fallback")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MapGeography: visual water mask JSON invalid; using solid-land fallback")
		return
	for entry_value in (parsed as Dictionary).get("water_rings", []):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var flat: Array = entry.get("points", [])
		if flat.size() < 6:
			continue
		var poly := PackedVector2Array()
		for i in range(0, flat.size() - 1, 2):
			poly.append(Vector2(float(flat[i]), float(flat[i + 1])))
		if poly.size() < 3:
			continue
		var rect := Rect2(poly[0], Vector2.ZERO)
		for point in poly:
			rect = rect.expand(point)
		var mask: Dictionary = {"rect": rect, "poly": poly}
		if str(entry.get("role", "water")) == "land_inlay":
			_visual_land_inlay_masks.append(mask)
		else:
			_visual_water_masks.append(mask)
	print("[MapGeography] visual surface masks — water=%d land_inlay=%d" % [
		_visual_water_masks.size(), _visual_land_inlay_masks.size(),
	])

static func _point_in_mask_entries(pos: Vector2, entries: Array[Dictionary]) -> bool:
	for entry in entries:
		var rect: Rect2 = entry["rect"]
		if rect.has_point(pos) \
				and Geometry2D.is_point_in_polygon(pos, entry["poly"] as PackedVector2Array):
			return true
	return false

# ══════════════════════════════════════════════
#  OSM 陆地 mask（城区外扩 + 道路外扩 → 当作地面）
# ══════════════════════════════════════════════
## 供 map_feature_renderer / tactical_map 两个渲染器共享缓存
## 首次调用计算（~500ms），之后零成本
const LAND_MASK_URBAN_EXPAND := 320.0
const LAND_MASK_ROAD_EXPAND := 160.0

static var _land_mask_cache: Array = []
static var _land_mask_built: bool = false

## 返回 Python 烘焙脚本（bake_tokyo_bay.py）用 shapely unary_union 合并后的 mask
## 由 1000+ halo 多边形合并成 ~3 个大块，大幅降低 GPU overdraw
static func get_land_mask_polygons() -> Array:
	ensure_ready()
	return MapGeographyData.LAND_MASK_POLYGONS

## 道路块状带缓存（用于主地图 _draw_highways）
## 预计算 offset_polyline 结果，防御性：即使主地图被意外重绘也不触发 1012 次重算
const ROAD_BAND_HALF_WIDTH := 2.2
static var _road_bands_cache: Array = []   # Array[PackedVector2Array]
static var _road_bands_built: bool = false

static func get_road_bands() -> Array:
	ensure_ready()
	if not _road_bands_built:
		_road_bands_built = true
		var t0 := Time.get_ticks_msec()
		for hw_any in HIGHWAYS:
			var hw: Dictionary = hw_any
			var pts: PackedVector2Array = hw.get("pts", PackedVector2Array())
			if pts.size() < 2:
				continue
			for band in Geometry2D.offset_polyline(pts, ROAD_BAND_HALF_WIDTH, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
				_road_bands_cache.append(band)
		print("[MapGeography] road bands cached: %d (%dms)" % [_road_bands_cache.size(), Time.get_ticks_msec() - t0])
	return _road_bands_cache

## 已废弃：旧的运行时 offset_polygon 路径，保留做 fallback 若 MapGeographyData 没 bake mask
static func _build_land_mask_fallback() -> void:
	var t0 := Time.get_ticks_msec()
	for urban_any in URBAN_DISTRICTS:
		var urban: PackedVector2Array = urban_any
		if urban.size() < 3:
			continue
		for op in Geometry2D.offset_polygon(urban, LAND_MASK_URBAN_EXPAND, Geometry2D.JOIN_ROUND):
			_land_mask_cache.append(op)
	for hw_any in HIGHWAYS:
		var hw: Dictionary = hw_any
		var pts: PackedVector2Array = hw.get("pts", PackedVector2Array())
		if pts.size() < 2:
			continue
		for band in Geometry2D.offset_polyline(pts, LAND_MASK_ROAD_EXPAND, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			_land_mask_cache.append(band)
	print("[MapGeography] land mask polygons: %d (%dms)" % [_land_mask_cache.size(), Time.get_ticks_msec() - t0])

# ══════════════════════════════════════════════
#  旧：程序化次级路网 — 已被 OSM 真实路网替代，此处保留空 stub 以免破坏调用点
# ══════════════════════════════════════════════
## 旧实现见 git 历史 / feedback_squad_spawner... 系列笔记；OSM 数据替代后弃用
static func get_secondary_roads() -> Array:
	return []
