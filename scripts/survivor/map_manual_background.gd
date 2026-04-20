@tool
class_name MapManualBackground
extends Node2D

## 手画地图的"参考底图"
##
## 用法：挂到 map_manual.tscn 根节点 / 子节点上
## @tool → Godot 编辑器里也执行 _draw()，实时显示 OSM 地面作为参考
##
## 【关键修复】用 preload() 而非 class_name 引用：
## 编辑器里 class_name MapGeographyData 的 static var 初始化有时不触发，
## 导致 LAND_MASK_POLYGONS 显示为空数组。preload() 显式加载脚本资源，
## 强制 Godot 跑一遍 static var 初始化，从而数据是完整的。

## 数据通过 MapGeographyData.ensure_loaded() 从 JSON 加载
## （class_name 引用在 @tool 编辑器里可能 static var 懒加载不触发，改用显式 JSON 加载）

@export var show_land_mask: bool = true
@export var show_urban: bool = true
@export var show_roads: bool = true
@export var show_world_border: bool = true
@export var show_grid: bool = true
@export_range(500.0, 5000.0, 100.0) var grid_step: float = 1000.0

## 编辑器色（alpha 调高，在灰色编辑器底上清晰可见）
const LAND_COLOR := Color(0.35, 0.50, 0.30, 1.0)     # 亮绿（陆地）
const URBAN_COLOR := Color(0.72, 0.55, 0.35, 1.0)    # 橙褐（城区）
const ROAD_COLOR := Color(1.00, 0.90, 0.55, 1.0)     # 亮黄（道路）
const ROAD_WIDTH := 3.0
const BORDER_COLOR := Color(0.35, 0.82, 0.90, 1.0)
const GRID_COLOR := Color(0.40, 0.40, 0.45, 0.50)
const GRID_AXIS_COLOR := Color(1.00, 0.30, 0.30, 0.90)
const GRID_AXIS_COLOR_Y := Color(0.30, 1.00, 0.30, 0.90)
const WORLD_HALF := 7500.0
const ORIGIN_MARKER_COLOR := Color(1.0, 1.0, 1.0, 1.0)

func _draw() -> void:
	MapGeographyData.ensure_loaded()
	if show_land_mask:
		_draw_land()
	if show_urban:
		_draw_urban()
	if show_roads:
		_draw_roads()
	if show_grid:
		_draw_grid()
	if show_world_border:
		_draw_border()
	_draw_origin_marker()
	_draw_info_text()

func _draw_grid() -> void:
	var step := grid_step
	var n := int(WORLD_HALF / step)
	for i in range(-n, n + 1):
		var x := i * step
		draw_line(Vector2(x, -WORLD_HALF), Vector2(x, WORLD_HALF), GRID_COLOR, 1.0)
		var y := i * step
		draw_line(Vector2(-WORLD_HALF, y), Vector2(WORLD_HALF, y), GRID_COLOR, 1.0)
	draw_line(Vector2(-WORLD_HALF, 0), Vector2(WORLD_HALF, 0), GRID_AXIS_COLOR, 2.0)
	draw_line(Vector2(0, -WORLD_HALF), Vector2(0, WORLD_HALF), GRID_AXIS_COLOR_Y, 2.0)

## 原点标记 —— 让用户一眼看到 (0, 0) 在哪
func _draw_origin_marker() -> void:
	draw_circle(Vector2.ZERO, 40.0, Color(1, 1, 1, 0.8))
	draw_circle(Vector2.ZERO, 32.0, Color(0.1, 0.1, 0.1, 1.0))
	draw_circle(Vector2.ZERO, 12.0, Color(1.0, 1.0, 1.0, 1.0))

## 地图整体提示：在上方写几个醒目的标注让用户知道是否数据已加载
func _draw_info_text() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var land_count: int = MapGeographyData.LAND_MASK_POLYGONS.size()
	var urban_count: int = MapGeographyData.URBAN_POLYGONS.size()
	var road_count: int = (MapGeographyData.ROADS_MOTORWAY.size()
		+ MapGeographyData.ROADS_TRUNK.size()
		+ MapGeographyData.ROADS_PRIMARY.size()
		+ MapGeographyData.ROADS_SECONDARY.size())
	var msg := "OSM Preview — land %d / urban %d / roads %d  (Shift+F 框选全部, F 居中到选中)" % [land_count, urban_count, road_count]
	var text_pos := Vector2(-WORLD_HALF + 100, -WORLD_HALF - 80)
	draw_string(font, text_pos, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 80, Color(1, 1, 1, 1))

func _draw_border() -> void:
	draw_rect(Rect2(-WORLD_HALF, -WORLD_HALF, WORLD_HALF * 2, WORLD_HALF * 2),
		BORDER_COLOR, false, 3.0)

func _draw_land() -> void:
	for poly_any in MapGeographyData.LAND_MASK_POLYGONS:
		var poly: PackedVector2Array = poly_any
		if poly.size() >= 3:
			draw_colored_polygon(poly, LAND_COLOR)

func _draw_urban() -> void:
	for poly_any in MapGeographyData.URBAN_POLYGONS:
		var poly: PackedVector2Array = poly_any
		if poly.size() >= 3:
			draw_colored_polygon(poly, URBAN_COLOR)

func _draw_roads() -> void:
	var tiers := [
		MapGeographyData.ROADS_MOTORWAY,
		MapGeographyData.ROADS_TRUNK,
		MapGeographyData.ROADS_PRIMARY,
		MapGeographyData.ROADS_SECONDARY,
	]
	for tier_any in tiers:
		for pts_any in tier_any:
			var pts: PackedVector2Array = pts_any
			if pts.size() >= 2:
				draw_polyline(pts, ROAD_COLOR, ROAD_WIDTH)
