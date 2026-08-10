class_name MainMenuCrtShell
extends Control

## 入口主菜单的静态 Y2K 军用显示器机壳。
## 只绘制一次；屏幕内容与 CRT 滤镜由 main_menu.gd 独立叠放。

const SHELL_SIZE := Vector2(1280.0, 820.0)
const SCREEN_RECT := Rect2(Vector2(140.0, 70.0), Vector2(1000.0, 576.0))


func _init() -> void:
	custom_minimum_size = SHELL_SIZE
	size = SHELL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var body_points := PackedVector2Array([
		Vector2(44.0, 0.0),
		Vector2(SHELL_SIZE.x - 44.0, 0.0),
		Vector2(SHELL_SIZE.x, 52.0),
		Vector2(SHELL_SIZE.x - 28.0, SHELL_SIZE.y),
		Vector2(28.0, SHELL_SIZE.y),
		Vector2(0.0, 52.0),
	])
	var shadow_points := PackedVector2Array()
	for point in body_points:
		shadow_points.append(point + Vector2(0.0, 18.0))
	draw_colored_polygon(shadow_points, Color(0.0, 0.0, 0.0, 0.78))
	draw_colored_polygon(body_points, Color("161b19"))
	draw_polyline(body_points + PackedVector2Array([body_points[0]]), Color("343c38"), 3.0, true)

	# 上沿与两侧厚壳。
	draw_rect(Rect2(62.0, 22.0, SHELL_SIZE.x - 124.0, 20.0), Color("252c29"), true)
	draw_line(Vector2(76.0, 24.0), Vector2(SHELL_SIZE.x - 76.0, 24.0),
		Color(0.55, 0.62, 0.57, 0.22), 2.0)
	draw_rect(SCREEN_RECT.grow(44.0), Color("0b0e0d"), true)
	draw_rect(SCREEN_RECT.grow(44.0), Color("3b4440"), false, 3.0)
	draw_rect(SCREEN_RECT.grow(23.0), Color("050706"), true)
	draw_rect(SCREEN_RECT.grow(23.0), Color("202622"), false, 4.0)
	draw_rect(SCREEN_RECT.grow(6.0), Color("000000"), true)
	draw_rect(SCREEN_RECT.grow(6.0), Color(0.35, 0.43, 0.38, 0.28), false, 2.0)

	# 屏幕下方控制台甲板和压边。
	var deck_rect := Rect2(72.0, 700.0, SHELL_SIZE.x - 144.0, 82.0)
	draw_rect(deck_rect, Color("101412"), true)
	draw_rect(deck_rect, Color("343c38"), false, 2.0)
	draw_line(Vector2(deck_rect.position.x, deck_rect.position.y + 14.0),
		Vector2(deck_rect.end.x, deck_rect.position.y + 14.0), Color(0.62, 0.70, 0.65, 0.16), 1.0)

	# 通风槽使用一次 draw_multiline 提交。
	var vent_segments := PackedVector2Array()
	for side_x in [104.0, SHELL_SIZE.x - 356.0]:
		for index in range(12):
			var x: float = float(side_x) + float(index) * 20.0
			vent_segments.append(Vector2(x, 728.0))
			vent_segments.append(Vector2(x + 9.0, 762.0))
	draw_multiline(vent_segments, Color(0.38, 0.44, 0.40, 0.32), 2.0, true)

	# 物理紧固件、维护口与电源灯。
	for screw_position in [
		Vector2(66.0, 48.0),
		Vector2(SHELL_SIZE.x - 66.0, 48.0),
		Vector2(54.0, SHELL_SIZE.y - 44.0),
		Vector2(SHELL_SIZE.x - 54.0, SHELL_SIZE.y - 44.0),
	]:
		draw_circle(screw_position, 7.0, Color("070908"))
		draw_circle(screw_position, 7.0, Color("4b5550"), false, 1.5, true)
		draw_line(screw_position - Vector2(4.0, 0.0), screw_position + Vector2(4.0, 0.0),
			Color("202622"), 1.5)
	draw_rect(Rect2(SHELL_SIZE.x * 0.5 - 92.0, 724.0, 184.0, 42.0), Color("070908"), true)
	draw_rect(Rect2(SHELL_SIZE.x * 0.5 - 92.0, 724.0, 184.0, 42.0), Color("2d3531"), false, 2.0)
	draw_circle(Vector2(SHELL_SIZE.x * 0.5 + 68.0, 745.0), 5.0,
		Color(0.0, 1.0, 0.255, 0.86))
	draw_circle(Vector2(SHELL_SIZE.x * 0.5 + 68.0, 745.0), 11.0,
		Color(0.0, 1.0, 0.255, 0.08))
