class_name UpgradeMediaSurface
extends Control

## 技能卡的物理介质底板。只在 populate / hover 状态改变时重绘，禁止逐帧刷新。

var rarity: int = 0
var accent: Color = Color.WHITE
var is_signature: bool = false
var selected: bool = false
var optical: bool = false
var label_is_dark: bool = true


func configure(value_rarity: int, value_accent: Color, value_signature: bool) -> void:
	rarity = value_rarity
	accent = value_accent
	is_signature = value_signature
	optical = value_signature or value_rarity >= SurvivorData.Rarity.CLASSIFIED
	label_is_dark = optical
	queue_redraw()


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	if optical:
		_draw_optical_media()
	else:
		_draw_floppy_media()


func _draw_floppy_media() -> void:
	var w := size.x
	var h := size.y
	var base := Color(0.12, 0.13, 0.15).lerp(accent, 0.06 + 0.025 * float(rarity))
	var edge := accent if selected else Color(accent, 0.70)
	var body := PackedVector2Array([
		Vector2(7, 19), Vector2(19, 7), Vector2(w - 27, 7), Vector2(w - 7, 27),
		Vector2(w - 7, h - 18), Vector2(w - 18, h - 7), Vector2(18, h - 7),
		Vector2(7, h - 18),
	])
	draw_colored_polygon(body, base)
	var outline := body.duplicate()
	outline.append(body[0])
	draw_polyline(outline, edge, 3.0 if selected else 1.5, true)

	# 注塑外壳高光与阴影，制造轻微厚度。
	draw_line(Vector2(19, 10), Vector2(w - 29, 10), Color(1, 1, 1, 0.18), 2.0)
	draw_line(Vector2(w - 10, 29), Vector2(w - 10, h - 20), Color(0, 0, 0, 0.62), 4.0)
	draw_line(Vector2(19, h - 10), Vector2(w - 20, h - 10), Color(0, 0, 0, 0.72), 4.0)

	# 金属滑片与读写窗口。
	var shutter := Rect2(44, 16, w - 76, 58)
	draw_rect(shutter, Color(0.49, 0.52, 0.55, 0.96), true)
	draw_rect(shutter, Color(0.86, 0.89, 0.91, 0.70), false, 1.0)
	draw_rect(Rect2(shutter.position + Vector2(10, 7), Vector2(18, 44)), Color(0.11, 0.12, 0.13, 0.88), true)
	for x in range(int(shutter.position.x) + 35, int(shutter.end.x) - 6, 10):
		draw_line(Vector2(x, shutter.position.y + 6), Vector2(x, shutter.end.y - 6), Color(1, 1, 1, 0.09), 1.0)

	_draw_label_plate(false)

	# 底部只保留写保护口与插入导轨；移除会被误读为按钮的圆形轴孔。
	draw_rect(Rect2(18, h - 52, 17, 18), Color(0.025, 0.03, 0.035), true)
	draw_rect(Rect2(w - 36, h - 54, 19, 28), Color(0.025, 0.03, 0.035), true)
	draw_line(Vector2(50, h - 16), Vector2(w - 50, h - 16), Color(accent, 0.38), 2.0)

	_draw_screw(Vector2(17, 24))
	_draw_screw(Vector2(w - 21, 35))
	_draw_screw(Vector2(18, h - 21))
	_draw_screw(Vector2(w - 22, h - 22))


func _draw_optical_media() -> void:
	var w := size.x
	var h := size.y
	var edge := accent if selected else Color(accent, 0.78)
	var shell := PackedVector2Array([
		Vector2(9, 23), Vector2(23, 9), Vector2(w - 23, 9), Vector2(w - 9, 23),
		Vector2(w - 9, h - 68), Vector2(w - 22, h - 55), Vector2(22, h - 55),
		Vector2(9, h - 68),
	])
	draw_colored_polygon(shell, Color(0.045, 0.055, 0.075, 0.90))
	var outline := shell.duplicate()
	outline.append(shell[0])
	draw_polyline(outline, edge, 4.0 if selected else 2.0, true)

	# 透明盒中的光盘：同一介质内叠加冷银环与轴色虹彩切片。
	var center := Vector2(w * 0.5, 124)
	draw_circle(center, 103.0, Color(0.03, 0.035, 0.05, 0.96))
	draw_circle(center, 96.0, Color(0.52, 0.57, 0.65, 0.18))
	draw_circle(center, 73.0, Color(0.01, 0.015, 0.025, 0.92))
	for i in range(12):
		var a0 := TAU * float(i) / 12.0 + 0.07
		var a1 := a0 + 0.23
		var hue_color := accent.lerp(Color.from_hsv(fmod(float(i) / 12.0 + 0.48, 1.0), 0.58, 1.0), 0.45)
		draw_arc(center, 88.0, a0, a1, 10, Color(hue_color, 0.38), 7.0, true)
	var hub := Color(0.58, 0.62, 0.68)
	draw_circle(center, 29.0, Color(0.01, 0.015, 0.025), true)
	draw_circle(center, 21.0, hub, false, 4.0, true)
	draw_circle(center, 6.0, Color(0.02, 0.025, 0.04), true)

	# 透明注塑结构与铆钉。
	for x in [26.0, w - 26.0]:
		draw_line(Vector2(x, 22), Vector2(x, h - 75), Color(1, 1, 1, 0.10), 1.0)
	for y in [36.0, h - 82.0]:
		draw_line(Vector2(21, y), Vector2(w - 21, y), Color(1, 1, 1, 0.10), 1.0)

	_draw_label_plate(true)

	# 光盘盒下方做成可插入机器的接口，而不是普通矩形卡脚。
	var dock := Rect2(22, h - 49, w - 44, 35)
	draw_rect(dock, Color(0.025, 0.03, 0.045, 0.96), true)
	draw_rect(dock, Color(edge, 0.70), false, 1.5)
	for x in range(int(dock.position.x) + 12, int(dock.end.x) - 8, 13):
		draw_rect(Rect2(x, dock.position.y + 22, 7, 7), Color(accent, 0.44), true)

	_draw_screw(Vector2(21, 25))
	_draw_screw(Vector2(w - 21, 25))
	_draw_screw(Vector2(21, h - 71))
	_draw_screw(Vector2(w - 21, h - 71))


func _draw_label_plate(is_optical: bool) -> void:
	var label_rect := Rect2(15, 82, size.x - 30, 163)
	var label_color := Color(0.025, 0.032, 0.048, 0.91) if is_optical \
		else Color(0.80, 0.80, 0.74, 0.97)
	var line_color := Color(accent, 0.42) if is_optical else Color(0.08, 0.09, 0.10, 0.25)
	draw_rect(label_rect, label_color, true)
	draw_rect(label_rect, Color(accent, 0.84 if selected else 0.55), false, 2.0 if selected else 1.0)
	for y in [112.0, 145.0, 215.0]:
		draw_line(Vector2(label_rect.position.x + 7, y), Vector2(label_rect.end.x - 7, y), line_color, 1.0)
	# 标签左侧的小型磁道/索引码，加强 Y2K 介质感。
	for y in range(123, 207, 8):
		draw_rect(Rect2(label_rect.position.x + 7, y, 9 + (y % 3) * 3, 2), line_color, true)


func _draw_screw(center: Vector2) -> void:
	draw_circle(center, 4.5, Color(0.55, 0.58, 0.62, 0.72))
	draw_circle(center, 2.3, Color(0.055, 0.06, 0.07, 0.95))
	draw_line(center - Vector2(2, 0), center + Vector2(2, 0), Color(0.75, 0.78, 0.82, 0.65), 1.0)
