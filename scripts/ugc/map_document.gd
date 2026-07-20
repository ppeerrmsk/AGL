class_name MapDocument
extends RefCounted

## UGC 地图文档：schema 读写 + 校验钳制 + layer_dirty + 撤销栈（map-editor spec §2.3/§2.4/§3.4）
## 纯数据层，不做渲染；编辑器与 UgcLoader 共用。
## 安全红线（ugc-editor spec §2）：只收 JSON 纯数据；坏字段跳过 + 警告，不崩。

const SCHEMA_VERSION := 1

## 编辑网格（spec §2.1）。世界尺寸从 MapBoundary 单常量主开关派生（map-expansion 契约）：
## 60km 图 → ±15000px → 300×300 格；改 WORLD_SIZE_M 编辑器自动跟随。
const CELL_SIZE_PX := 100.0
const WORLD_HALF_PX := MapBoundary.WORLD_HALF_PX
const GRID_W := int(WORLD_HALF_PX * 2.0 / CELL_SIZE_PX)
const GRID_H := GRID_W
const CLOUD_GRID := 64
const UNDO_DEPTH := 50

## 数值围栏（spec §2.3）
const MAX_TOTAL_VERTS := 20000
const MAX_BUILDINGS := 500
const MAX_ZONES := 12

## 涂格图层名（素材库分类中走笔刷的部分，spec §2.2）
const CELL_LAYERS: Array[String] = ["land", "mountain", "forest", "farmland", "beach", "urban"]

## 调色板默认值 = 官方现值（spec §2.5，权威表）
const DEFAULT_STYLE := {
	"palette": {
		"sea": [0.16, 0.24, 0.32, 1.0],
		"land": [0.32, 0.35, 0.27, 1.0],
		"urban": [0.42, 0.38, 0.28, 1.0],
		"road": [0.88, 0.80, 0.56, 1.0],
		"road_glow": [1.00, 0.70, 0.25, 0.35],
		"road_core": [1.00, 0.85, 0.45, 0.95],
		"tacview_cross": [0.55, 0.75, 0.82, 0.30],
		"building_roof": [0.62, 0.59, 0.53, 1.0],
		"building_wall_lit": [0.52, 0.49, 0.43, 1.0],
		"building_wall_shade": [0.26, 0.25, 0.23, 1.0],
		"building_shadow": [0.04, 0.05, 0.07, 0.55],
		"building_outline": [0.10, 0.10, 0.09, 0.6],
		"terrain_mountain": [0.38, 0.36, 0.32, 1.0],
		"terrain_forest": [0.24, 0.32, 0.22, 1.0],
		"terrain_farmland": [0.36, 0.36, 0.24, 1.0],
		"terrain_beach": [0.46, 0.42, 0.32, 1.0],
	},
	"post": {
		"grain": 0.03,
		"land_outline": [0.10, 0.12, 0.10, 0.6],
		"land_outline_width": 1.5,
	},
	"light_dir": [-0.707107, -0.707107],
}

# ── 文档数据 ──
var display_name := "untitled"
var world_size_m := 30000.0

## 运行时多边形（权威数据；dirty 图层由 editor_cells 重烘焙覆盖）
## key = CELL_LAYERS 图层名 → Array[PackedVector2Array]
var layer_polygons: Dictionary = {}

var airports: Array = []    # [{center:[x,y], size:[w,h], rotation_deg}] 或 {polygon:[[x,y]...]}（官方转换）
var roads: Array = []       # [{points:[[x,y]...], width_class}]
var coastlines: Array = []  # [[[x,y]...]...] 海岸线折线（官方转换保真用；编辑器新图可空）
var buildings: Array = []   # [{footprint:[[x,y]...], h_m}]
var zones: Array = []       # [{center:[x,y], radius, type}]
var spawn: Dictionary = {}  # {pos:[x,y], heading_deg}
var cloud: Dictionary = {   # mask 为空 = 全 1.0（纯噪声，官方行为）
	"seed": 0, "coverage": 0.35, "frequency": 0.00055,
	"wind_dir_deg": 0.0, "wind_speed_ms": 18.0, "mask": PackedByteArray(),
}
var style: Dictionary = {}

## 编辑器涂格原稿：图层名 → PackedByteArray(GRID_W×GRID_H)
var editor_cells: Dictionary = {}
## 图层是否被笔刷改过（spec §3.4 懒烘焙：false = layer_polygons 原始权威）
var layer_dirty: Dictionary = {}
## 图层判定/栅格化语义（spec §3.4）：
##   "even_odd" = 编辑器烘焙环组（孔洞=独立环，偶奇计数）——默认
##   "union"    = 官方转换直通多边形（可互相重叠，任一命中即算，与官方 is_on_land 一字不差）
var layer_mode: Dictionary = {}

## 加载/校验产生的警告（UI 展示 + EventLogger）
var warnings: PackedStringArray = []
## 版本过高等硬拒绝（spec §2.4：高于当前 schema → 拒绝导入并提示升级游戏）
var rejected := false

# ── 撤销栈 ──
var _undo_stack: Array = []  # [{layer, cells: PackedByteArray}]


func _init() -> void:
	style = DEFAULT_STYLE.duplicate(true)
	for layer in CELL_LAYERS:
		var empty := PackedByteArray()
		empty.resize(GRID_W * GRID_H)
		editor_cells[layer] = empty
		layer_dirty[layer] = false
		layer_mode[layer] = "even_odd"
		layer_polygons[layer] = []


static func grid_origin() -> Vector2:
	return Vector2(-WORLD_HALF_PX, -WORLD_HALF_PX)


# ══════════════════════════════════════════════
#  笔刷入口 + 烘焙 + 撤销
# ══════════════════════════════════════════════

## 笔画开始前调用：压撤销快照
func push_undo(layer: String) -> void:
	if not editor_cells.has(layer):
		return
	_undo_stack.append({"layer": layer, "cells": editor_cells[layer].duplicate()})
	while _undo_stack.size() > UNDO_DEPTH:
		_undo_stack.pop_front()


## 撤销一步；返回被恢复的图层名（"" = 栈空）
func undo() -> String:
	if _undo_stack.is_empty():
		return ""
	var snap: Dictionary = _undo_stack.pop_back()
	var layer: String = snap["layer"]
	editor_cells[layer] = snap["cells"]
	mark_dirty_and_rebake(layer)
	return layer


## 笔画结束调用：置 dirty + 从涂格重烘焙该层多边形（spec §3.1 / §3.4）
## 重烘焙产物是环组 → 该层语义切到 even_odd（官方 union 直通层被涂过即转编辑器语义）
func mark_dirty_and_rebake(layer: String) -> void:
	if not editor_cells.has(layer):
		return
	layer_dirty[layer] = true
	layer_mode[layer] = "even_odd"
	layer_polygons[layer] = ContourBaker.bake_layer(
		editor_cells[layer], GRID_W, GRID_H, CELL_SIZE_PX, grid_origin())


# ══════════════════════════════════════════════
#  序列化
# ══════════════════════════════════════════════

func to_json_dict() -> Dictionary:
	var polys_out := {}
	for layer in layer_polygons:
		var arr := []
		for poly in layer_polygons[layer]:
			arr.append(_poly_to_arr(poly))
		polys_out[layer] = arr
	var cells_out := {}
	for layer in editor_cells:
		cells_out[layer] = Marshalls.raw_to_base64(editor_cells[layer])
	var cloud_out := cloud.duplicate(true)
	cloud_out["mask"] = Marshalls.raw_to_base64(cloud["mask"]) if not (cloud["mask"] as PackedByteArray).is_empty() else ""
	return {
		"schema_version": SCHEMA_VERSION,
		"display_name": display_name,
		"world_size_m": world_size_m,
		"layer_polygons": polys_out,
		"airports": airports, "roads": roads, "coastlines": coastlines, "buildings": buildings,
		"zones": zones, "spawn": spawn,
		"cloud": cloud_out,
		"style": style,
		"editor_cells": cells_out,
		"layer_dirty": layer_dirty,
		"layer_mode": layer_mode,
	}


## 从 JSON dict 构造。任何字段缺失/类型错走默认 + 警告，绝不崩（安全红线）
static func from_json_dict(d: Dictionary) -> MapDocument:
	var doc := MapDocument.new()
	var ver := int(d.get("schema_version", -1))
	if ver > SCHEMA_VERSION:
		doc.warnings.append("schema_version %d 高于当前 %d：拒绝加载" % [ver, SCHEMA_VERSION])
		doc.rejected = true
		return doc
	if ver < 1:
		doc.warnings.append("schema_version 缺失/非法，按 1 处理")
	# （将来 ver < SCHEMA_VERSION 时在此挂逐版本迁移链，spec §2.4）
	doc.display_name = str(d.get("display_name", "untitled"))
	doc.world_size_m = clampf(float(d.get("world_size_m", 30000.0)), 1000.0, 200000.0)

	var total_verts := 0
	var polys_in: Dictionary = d.get("layer_polygons", {}) if d.get("layer_polygons") is Dictionary else {}
	for layer in CELL_LAYERS:
		var arr_in: Array = polys_in.get(layer, []) if polys_in.get(layer) is Array else []
		var polys: Array = []
		for raw in arr_in:
			var poly := _arr_to_poly(raw)
			if poly.size() < 3:
				continue
			if total_verts + poly.size() > MAX_TOTAL_VERTS:
				doc.warnings.append("图层 %s：顶点总数超 %d，截断" % [layer, MAX_TOTAL_VERTS])
				break
			total_verts += poly.size()
			polys.append(poly)
		doc.layer_polygons[layer] = polys

	doc.airports = d.get("airports", []) if d.get("airports") is Array else []
	doc.roads = d.get("roads", []) if d.get("roads") is Array else []
	doc.coastlines = d.get("coastlines", []) if d.get("coastlines") is Array else []
	doc.buildings = d.get("buildings", []) if d.get("buildings") is Array else []
	if doc.buildings.size() > MAX_BUILDINGS:
		doc.warnings.append("建筑 %d 超上限 %d，截断" % [doc.buildings.size(), MAX_BUILDINGS])
		doc.buildings = doc.buildings.slice(0, MAX_BUILDINGS)
	doc.zones = d.get("zones", []) if d.get("zones") is Array else []
	if doc.zones.size() > MAX_ZONES:
		doc.warnings.append("战区 %d 超上限 %d，截断" % [doc.zones.size(), MAX_ZONES])
		doc.zones = doc.zones.slice(0, MAX_ZONES)
	doc.spawn = d.get("spawn", {}) if d.get("spawn") is Dictionary else {}

	var cloud_in: Dictionary = d.get("cloud", {}) if d.get("cloud") is Dictionary else {}
	doc.cloud["seed"] = int(cloud_in.get("seed", 0))
	doc.cloud["coverage"] = clampf(float(cloud_in.get("coverage", 0.35)), 0.0, 1.0)
	doc.cloud["frequency"] = clampf(float(cloud_in.get("frequency", 0.00055)), 0.00005, 0.01)
	doc.cloud["wind_dir_deg"] = fposmod(float(cloud_in.get("wind_dir_deg", 0.0)), 360.0)
	doc.cloud["wind_speed_ms"] = clampf(float(cloud_in.get("wind_speed_ms", 18.0)), 0.0, 60.0)
	var mask_b64 := str(cloud_in.get("mask", ""))
	if mask_b64 != "":
		var mask := Marshalls.base64_to_raw(mask_b64)
		if mask.size() == CLOUD_GRID * CLOUD_GRID:
			doc.cloud["mask"] = mask
		else:
			doc.warnings.append("云 mask 尺寸非法（%d ≠ %d），忽略" % [mask.size(), CLOUD_GRID * CLOUD_GRID])

	# style：深合并到默认值上（缺 key = 官方色，spec 验收"旧图行为不变"）
	var style_in: Dictionary = d.get("style", {}) if d.get("style") is Dictionary else {}
	doc.style = _merge_style(DEFAULT_STYLE.duplicate(true), style_in)

	var cells_in: Dictionary = d.get("editor_cells", {}) if d.get("editor_cells") is Dictionary else {}
	for layer in CELL_LAYERS:
		var b64 := str(cells_in.get(layer, ""))
		if b64 == "":
			continue
		var cells := Marshalls.base64_to_raw(b64)
		if cells.size() == GRID_W * GRID_H:
			doc.editor_cells[layer] = cells
		else:
			doc.warnings.append("图层 %s 涂格尺寸非法，重置为空" % layer)

	var dirty_in: Dictionary = d.get("layer_dirty", {}) if d.get("layer_dirty") is Dictionary else {}
	var mode_in: Dictionary = d.get("layer_mode", {}) if d.get("layer_mode") is Dictionary else {}
	for layer in CELL_LAYERS:
		doc.layer_dirty[layer] = bool(dirty_in.get(layer, false))
		doc.layer_mode[layer] = "union" if str(mode_in.get(layer, "even_odd")) == "union" else "even_odd"
	return doc


# ── 文件 IO ──

## 保存到路径（user://ugc/maps/<name>.json 或导出 .aglmap —— 同一格式）
func save_to(path: String) -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_json_dict(), "\t"))
	return true


## 从路径加载；失败返回 null（调用方负责提示），warnings 里有细节
static func load_from(path: String) -> MapDocument:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return null
	var doc := from_json_dict(data)
	if not doc.warnings.is_empty():
		for w in doc.warnings:
			print("[MapDocument] 警告 %s: %s" % [path.get_file(), w])
	return null if doc.rejected else doc


# ── 工具 ──

static func _poly_to_arr(poly: PackedVector2Array) -> Array:
	var out := []
	for p in poly:
		out.append([p.x, p.y])
	return out


static func _arr_to_poly(raw) -> PackedVector2Array:
	var poly := PackedVector2Array()
	if not (raw is Array):
		return poly
	for pt in raw:
		if pt is Array and pt.size() >= 2:
			poly.append(Vector2(float(pt[0]), float(pt[1])))
	return poly


## style 浅递归合并：user 值覆盖默认，但只认默认里存在的 key（防垃圾字段膨胀）
static func _merge_style(base: Dictionary, user: Dictionary) -> Dictionary:
	for key in base:
		if not user.has(key):
			continue
		if base[key] is Dictionary and user[key] is Dictionary:
			base[key] = _merge_style(base[key], user[key])
		else:
			base[key] = user[key]
	return base
