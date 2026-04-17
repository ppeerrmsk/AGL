class_name MapFeatureRenderer
extends Node2D

## 世界空间地图特征绘制（生存模式）
##
## 分层（从底到顶）：
##   1. 海面底色（相机视野覆盖矩形）
##   2. 海岸外光晕（淡青色）
##   3. 陆地填充 + 内陆高光
##   4. 海岸线（亮青白描边）
##   5. 城区（暖色半透填充 + 描边）
##   6. 高速公路折线（粗暖色）
##   7. Aqua-Line 跨湾虚线（亮青）

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

func _draw() -> void:
	if not _camera:
		return
	_draw_sea()
	_draw_coast_glow()
	_draw_land_fills()
	_draw_coast_outlines()
	_draw_urban_districts()
	_draw_highways()
	_draw_aqualine()

func _draw_sea() -> void:
	# 一次性画满整个世界矩形（加大余量），静态不再重绘
	# 相机如何移动/缩放都能看到海面，无需每帧跟随
	var rect := _world_rect.grow(8000.0)
	draw_rect(rect, MapGeography.SEA_COLOR, true)

## 海岸外侧淡色光晕，让海岸线更醒目
func _draw_coast_glow() -> void:
	for poly_any in MapGeography.get_land_polygons():
		var poly: PackedVector2Array = poly_any
		# 向质心反方向外扩 80 px 的多边形
		var centroid := _polygon_centroid(poly)
		var outer := PackedVector2Array()
		for p in poly:
			var dir := (p - centroid).normalized()
			outer.append(p + dir * 80.0)
		draw_colored_polygon(outer, MapGeography.COAST_GLOW)

func _draw_land_fills() -> void:
	for poly_any in MapGeography.get_land_polygons():
		var poly: PackedVector2Array = poly_any
		draw_colored_polygon(poly, MapGeography.LAND_COLOR)
		_draw_land_inner_shading(poly)

func _draw_land_inner_shading(poly: PackedVector2Array) -> void:
	var centroid := _polygon_centroid(poly)
	var inner := PackedVector2Array()
	for p in poly:
		inner.append(p.lerp(centroid, 0.30))
	draw_colored_polygon(inner, MapGeography.LAND_INNER)

func _polygon_centroid(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var s := Vector2.ZERO
	for p in poly:
		s += p
	return s / poly.size()

## 海岸线描边
##   LAND_WEST / LAND_EAST：首尾贴地图边界，跳过首段和闭合段
##   HANEDA_AIRPORT：独立岛屿，全部闭合描边
func _draw_coast_outlines() -> void:
	var land_list := MapGeography.get_land_polygons()
	# 前两个是大块陆地（跳首尾贴边段）
	for i in range(2):
		var poly: PackedVector2Array = land_list[i]
		var n: int = poly.size()
		if n < 4:
			continue
		for j in range(1, n - 1):
			draw_line(poly[j], poly[j + 1], MapGeography.COAST_COLOR, 2.4)
	# 羽田独立岛：闭合
	if land_list.size() >= 3:
		var hp: PackedVector2Array = land_list[2]
		var hn: int = hp.size()
		for k in range(hn):
			draw_line(hp[k], hp[(k + 1) % hn], MapGeography.COAST_COLOR, 2.0)

func _draw_urban_districts() -> void:
	for poly_any in MapGeography.URBAN_DISTRICTS:
		var poly: PackedVector2Array = poly_any
		if poly.size() < 3:
			continue
		draw_colored_polygon(poly, MapGeography.URBAN_FILL)
		var n: int = poly.size()
		for i in range(n):
			draw_line(poly[i], poly[(i + 1) % n], MapGeography.URBAN_LINE, 1.2)

func _draw_highways() -> void:
	for hw_any in MapGeography.HIGHWAYS:
		var hw: Dictionary = hw_any
		var pts: PackedVector2Array = hw.get("pts", PackedVector2Array())
		var color: Color = hw.get("color", MapGeography.HIGHWAY_SUB)
		var width: float = float(hw.get("width", 1.5))
		if pts.size() < 2:
			continue
		for i in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], color, width)

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
