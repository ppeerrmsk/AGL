class_name TerminalMapPreview
extends Control

## 地图选择卡使用的静态终端线稿缩略图；不启用逐帧重绘。

var map_index: int = 0
var locked: bool = false
var accent: Color = Color.WHITE


func _init(index: int = 0, is_locked: bool = false,
		line_color: Color = Color.WHITE) -> void:
	map_index = index
	locked = is_locked
	accent = line_color
	custom_minimum_size = Vector2(156.0, 108.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var color := Color(accent, 0.24 if locked else 0.76)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.78), true)
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), color, false, 1.0)
	if locked:
		_draw_locked(color)
		return
	match map_index:
		0:
			_draw_coast(color)
		1:
			_draw_desert(color)
		2:
			_draw_islands(color)
		_:
			_draw_locked(color)


func _draw_coast(color: Color) -> void:
	var coast := PackedVector2Array([
		Vector2(0, 76), Vector2(24, 70), Vector2(38, 50), Vector2(67, 46),
		Vector2(82, 26), Vector2(112, 34), Vector2(132, 18), Vector2(size.x, 20)])
	draw_polyline(coast, color, 1.0)
	draw_line(Vector2(12, 88), Vector2(146, 88), Color(color, 0.38), 1.0)
	for x in [24.0, 52.0, 94.0, 126.0]:
		draw_line(Vector2(x, 58), Vector2(x + 22, 36), Color(color, 0.30), 1.0)


func _draw_desert(color: Color) -> void:
	draw_line(Vector2(8, 83), Vector2(148, 31), color, 1.0)
	draw_line(Vector2(8, 88), Vector2(148, 36), Color(color, 0.48), 1.0)
	for i in range(6):
		var t := float(i) / 5.0
		var p := Vector2(18.0 + t * 118.0, 81.0 - t * 44.0)
		draw_line(p + Vector2(-4, -5), p + Vector2(4, 5), color, 1.0)
	draw_polyline(PackedVector2Array([
		Vector2(0, 56), Vector2(32, 50), Vector2(61, 59), Vector2(96, 48),
		Vector2(128, 54), Vector2(size.x, 45)]), Color(color, 0.34), 1.0)


func _draw_islands(color: Color) -> void:
	for island in [
		Rect2(18, 20, 42, 24), Rect2(78, 50, 52, 28), Rect2(112, 14, 28, 18),
	]:
		draw_rect(island, Color(color, 0.15), true)
		draw_rect(island, color, false, 1.0)
	draw_arc(Vector2(75, 54), 44.0, -2.6, 0.2, 20, Color(color, 0.34), 1.0)
	draw_line(Vector2(8, 94), Vector2(148, 94), Color(color, 0.30), 1.0)


func _draw_locked(color: Color) -> void:
	for x in range(-80, 220, 18):
		draw_line(Vector2(x, size.y), Vector2(x + size.y, 0), Color(color, 0.28), 1.0)
	draw_line(size * 0.5 - Vector2(12, 0), size * 0.5 + Vector2(12, 0), color, 1.0)
	draw_line(size * 0.5 - Vector2(0, 12), size * 0.5 + Vector2(0, 12), color, 1.0)
