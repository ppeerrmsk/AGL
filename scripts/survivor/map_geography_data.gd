class_name MapGeographyData
extends RefCounted

## 地图数据加载器（从 resources/maps/tokyo_bay.json 读取）
##
## 之前直接把 1000+ 个 PackedVector2Array 写成 GDScript static var 文件（8000+ 行），
## Godot 的 GDScript 解析器在 @tool 编辑器上下文里有时不触发 static var 初始化，
## 导致 class member 被判断为空。改用 JSON 后：
## - Godot 只需要解析一个小 JSON（原生支持，快）
## - 数据保证在编辑器和游戏运行时都能读到
##
## 所有访问点必须先调用 ensure_loaded()，然后直接读 static var。
## 首次加载 ~20ms，之后零成本。

const DATA_JSON_PATH := "res://resources/maps/tokyo_bay.json"

static var COASTLINE_LINES: Array = []
static var URBAN_POLYGONS: Array = []
static var AERODROME_POLYGONS: Array = []
static var ROADS_MOTORWAY: Array = []
static var ROADS_TRUNK: Array = []
static var ROADS_PRIMARY: Array = []
static var ROADS_SECONDARY: Array = []
static var ROADS_TERTIARY: Array = []
static var LAND_MASK_POLYGONS: Array = []

static var _loaded: bool = false

## 强制加载 JSON 数据
## 所有访问点（MapGeography / MapManualBackground / MapFeatureRenderer）
## 在使用任何静态字段前都应先调这个
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var t0 := Time.get_ticks_msec()
	var file := FileAccess.open(DATA_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("MapGeographyData: cannot open " + DATA_JSON_PATH + " (run scripts/tools/bake_tokyo_bay.py)")
		return
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("MapGeographyData: JSON parse failed")
		return
	COASTLINE_LINES = _unpack(parsed.get("coastline", []))
	URBAN_POLYGONS = _unpack(parsed.get("urban", []))
	AERODROME_POLYGONS = _unpack(parsed.get("aero", []))
	ROADS_MOTORWAY = _unpack(parsed.get("roads_motorway", []))
	ROADS_TRUNK = _unpack(parsed.get("roads_trunk", []))
	ROADS_PRIMARY = _unpack(parsed.get("roads_primary", []))
	ROADS_SECONDARY = _unpack(parsed.get("roads_secondary", []))
	ROADS_TERTIARY = _unpack(parsed.get("roads_tertiary", []))
	LAND_MASK_POLYGONS = _unpack(parsed.get("land_mask", []))
	var t1 := Time.get_ticks_msec()
	print("[MapGeographyData] JSON loaded in %dms — urban=%d roads=%d+%d+%d+%d land_mask=%d coastline=%d" % [
		t1 - t0,
		URBAN_POLYGONS.size(),
		ROADS_MOTORWAY.size(), ROADS_TRUNK.size(),
		ROADS_PRIMARY.size(), ROADS_SECONDARY.size(),
		LAND_MASK_POLYGONS.size(),
		COASTLINE_LINES.size(),
	])

## 把扁平 [x1, y1, x2, y2, ...] 列表转成 Array[PackedVector2Array]
## 同时做清洗：去连续重复顶点、丢面积过小的退化多边形
## 避免 Godot 的 draw_colored_polygon 三角剖分在退化数据上狂报错
const DEDUP_EPS_SQ := 0.01     # 顶点间距 < 0.1px 视为重复
const MIN_POLYGON_AREA := 1.0  # 小于 1 sq-px 丢弃

static func _unpack(flat_list: Array) -> Array:
	var out: Array = []
	var dropped := 0
	for flat_any in flat_list:
		var flat: Array = flat_any
		if flat.size() < 4:
			dropped += 1
			continue
		var pts := PackedVector2Array()
		var i := 0
		var last := Vector2(INF, INF)
		while i + 1 < flat.size():
			var p := Vector2(flat[i], flat[i + 1])
			if p.distance_squared_to(last) > DEDUP_EPS_SQ:
				pts.append(p)
				last = p
			i += 2
		# 去首尾闭合重复
		if pts.size() >= 2 and pts[0].distance_squared_to(pts[pts.size() - 1]) < DEDUP_EPS_SQ:
			pts.remove_at(pts.size() - 1)
		if pts.size() < 3:
			dropped += 1
			continue
		# 面积过滤（简单 shoelace）
		var area := 0.0
		var n := pts.size()
		for k in range(n):
			var a := pts[k]
			var b := pts[(k + 1) % n]
			area += a.x * b.y - b.x * a.y
		if absf(area) * 0.5 < MIN_POLYGON_AREA:
			dropped += 1
			continue
		out.append(pts)
	if dropped > 0:
		print("[MapGeographyData] _unpack dropped %d degenerate polygons" % dropped)
	return out
