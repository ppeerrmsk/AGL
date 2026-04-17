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

static func get_land_polygons() -> Array:
	return [LAND_WEST, LAND_EAST, HANEDA_AIRPORT]

# ══════════════════════════════════════════════
#  城区多边形（替代之前的圆圈）
# ══════════════════════════════════════════════
## 每个城区是粗糙的多边形，对应现实中主要市区
## 显示为暖色描边 + 半透明填充
static var URBAN_DISTRICTS: Array = [
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
#  道路 / 高速公路（折线）
# ══════════════════════════════════════════════
## 每条用 PackedVector2Array + 颜色 + 线宽
## 以现实横滨/东京湾道路网为参考，但可以简化/虚构化
static var HIGHWAYS: Array = [
	# 湾岸高速（首都高湾岸线）：沿北侧西岸海岸线南下至横滨
	{
		"pts": PackedVector2Array([
			Vector2(-7500, -6400),
			Vector2(-4500, -6600),
			Vector2(-2500, -6400),
			Vector2(-800, -6000),
			Vector2(400, -5400),
			Vector2(600, -4900),
			Vector2(-300, -4200),
			Vector2(-1500, -3500),
			Vector2(-2300, -2600),
			Vector2(-2500, -1800),
			Vector2(-3000, -1000),
			Vector2(-3500, 0),
			Vector2(-3800, 900),
		]),
		"color": HIGHWAY_MAIN,
		"width": 2.2,
	},
	# 横浜横须贺道路：沿三浦半岛东岸南下
	{
		"pts": PackedVector2Array([
			Vector2(-3800, 1500),
			Vector2(-4000, 2500),
			Vector2(-4200, 3500),
			Vector2(-4400, 4500),
			Vector2(-4600, 5500),
			Vector2(-5000, 6500),
			Vector2(-5800, 7200),
		]),
		"color": HIGHWAY_MAIN,
		"width": 2.0,
	},
	# 馆山自动车道 / 館山自動車道：东岸南北干线
	{
		"pts": PackedVector2Array([
			Vector2(5200, -6800),
			Vector2(5500, -5500),
			Vector2(5600, -4200),
			Vector2(5400, -3000),
			Vector2(5200, -1500),
			Vector2(5000, 0),
			Vector2(5200, 1500),
			Vector2(5500, 3000),
			Vector2(5800, 4500),
			Vector2(6000, 6000),
			Vector2(6500, 7300),
		]),
		"color": HIGHWAY_MAIN,
		"width": 2.0,
	},
	# Route 16 / 国道 16：环湾主干（本项目用在西岸内陆一段）
	{
		"pts": PackedVector2Array([
			Vector2(-7500, -3800),
			Vector2(-5800, -3500),
			Vector2(-4200, -3200),
			Vector2(-3200, -2200),
			Vector2(-3400, -1200),
			Vector2(-4000, -200),
			Vector2(-4800, 800),
			Vector2(-5400, 2200),
		]),
		"color": HIGHWAY_SUB,
		"width": 1.6,
	},
	# 内房线/君津方向次干（东岸内陆）
	{
		"pts": PackedVector2Array([
			Vector2(4000, -6700),
			Vector2(4300, -5000),
			Vector2(4500, -3000),
			Vector2(4400, -1000),
			Vector2(4500, 1000),
			Vector2(4700, 3000),
			Vector2(5100, 5000),
			Vector2(5600, 6800),
		]),
		"color": HIGHWAY_SUB,
		"width": 1.6,
	},
]

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

## 判断某世界坐标是否在陆地上（包括羽田机场）
static func is_on_land(pos: Vector2) -> bool:
	for poly in get_land_polygons():
		if Geometry2D.is_point_in_polygon(pos, poly):
			return true
	return false
