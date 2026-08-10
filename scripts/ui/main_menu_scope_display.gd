class_name MainMenuScopeDisplay
extends Control

## 主菜单右侧的静态航路/雷达示意图，不承载游戏状态。

var accent: Color = ThemeColors.UI_TERMINAL_GREEN:
	set(value):
		if accent.is_equal_approx(value):
			return
		accent = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var dim := accent
	dim.a = 0.18
	var mid := accent
	mid.a = 0.42
	var strong := accent
	strong.a = 0.82

	var grid_segments := PackedVector2Array()
	for x in range(40, int(size.x), 40):
		grid_segments.append(Vector2(float(x), 0.0))
		grid_segments.append(Vector2(float(x), size.y))
	for y in range(36, int(size.y), 36):
		grid_segments.append(Vector2(0.0, float(y)))
		grid_segments.append(Vector2(size.x, float(y)))
	draw_multiline(grid_segments, dim, 1.0, false)

	var scope_center := Vector2(size.x + 24.0, size.y + 18.0)
	for radius in [150.0, 210.0, 270.0, 330.0]:
		draw_arc(scope_center, radius, PI, PI * 1.5, 72, mid, 1.0, true)

	var route := PackedVector2Array([
		Vector2(44.0, size.y - 34.0),
		Vector2(70.0, size.y - 82.0),
		Vector2(58.0, size.y - 126.0),
		Vector2(110.0, size.y - 154.0),
		Vector2(144.0, size.y - 118.0),
		Vector2(132.0, size.y - 72.0),
		Vector2(192.0, size.y - 54.0),
		Vector2(236.0, size.y - 92.0),
	])
	draw_polyline(route, strong, 2.0, true)
	for point in route:
		draw_rect(Rect2(point - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), strong, false, 1.0)

	var aircraft_center := Vector2(238.0, size.y - 92.0)
	var aircraft := PackedVector2Array([
		aircraft_center + Vector2(18.0, 0.0),
		aircraft_center + Vector2(-10.0, -8.0),
		aircraft_center + Vector2(-4.0, 0.0),
		aircraft_center + Vector2(-10.0, 8.0),
	])
	draw_colored_polygon(aircraft, accent)

	var corner_marks := PackedVector2Array([
		Vector2(12.0, 26.0), Vector2(28.0, 26.0),
		Vector2(20.0, 18.0), Vector2(20.0, 34.0),
		Vector2(size.x - 28.0, 26.0), Vector2(size.x - 12.0, 26.0),
		Vector2(size.x - 20.0, 18.0), Vector2(size.x - 20.0, 34.0),
		Vector2(12.0, size.y - 26.0), Vector2(28.0, size.y - 26.0),
		Vector2(20.0, size.y - 34.0), Vector2(20.0, size.y - 18.0),
		Vector2(size.x - 28.0, size.y - 26.0), Vector2(size.x - 12.0, size.y - 26.0),
		Vector2(size.x - 20.0, size.y - 34.0), Vector2(size.x - 20.0, size.y - 18.0),
	])
	draw_multiline(corner_marks, strong, 1.0, false)
