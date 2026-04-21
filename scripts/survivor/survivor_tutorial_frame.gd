class_name SurvivorTutorialFrame
extends Control

## Tacview 风格的"点击攻击"标定框。
## 自绘：深绿底 + amber 四角括号 + 虚线引线 + 菱形目标标记 + 慢脉冲。
## 外部只需设 `text` / `header` 并把节点放到对应屏幕位置，目标菱形出现在框右侧 BOX_W+GAP 处。

const BOX_W := 170.0
const BOX_H := 42.0
const GAP := 44.0
const BRACKET := 9.0
const MARKER_R := 6.0
const DASH := 6.0
const DASH_GAP := 5.0

const COL_FILL := Color(0.02, 0.05, 0.03, 0.55)
const COL_FILL_INNER := Color(0.05, 0.12, 0.06, 0.35)
const COL_ACCENT := Color(1.0, 0.82, 0.35, 0.92)
const COL_ACCENT_DIM := Color(0.85, 0.68, 0.25, 0.65)
const COL_HEADER := Color(0.6, 0.85, 0.55, 0.75)

var text: String = ""
var header: String = "TGT"
var _pulse_t: float = 0.0

func _ready() -> void:
	var total := Vector2(BOX_W + GAP + MARKER_R + 2.0, BOX_H)
	custom_minimum_size = total
	size = total
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_pulse_t += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(BOX_W, BOX_H)), COL_FILL, true)
	draw_rect(Rect2(Vector2(0, 0), Vector2(BOX_W, 12)), COL_FILL_INNER, true)

	_draw_bracket(Vector2(0, 0), 1, 1)
	_draw_bracket(Vector2(BOX_W, 0), -1, 1)
	_draw_bracket(Vector2(0, BOX_H), 1, -1)
	_draw_bracket(Vector2(BOX_W, BOX_H), -1, -1)

	draw_line(Vector2(6, 12), Vector2(BOX_W - 6, 12), COL_ACCENT_DIM, 1.0)

	var font: Font = ThemeDB.fallback_font
	if font == null:
		font = get_theme_default_font()
	if font:
		draw_string(font, Vector2(6, 10), header,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_HEADER)
		var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var text_y: float = 12.0 + (BOX_H - 12.0) * 0.5 + text_size.y * 0.3
		draw_string(font, Vector2((BOX_W - text_size.x) * 0.5, text_y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_ACCENT)

	var pulse: float = 0.65 + 0.35 * sin(_pulse_t * 3.5)
	var lead_col := Color(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, COL_ACCENT.a * pulse)

	var lead_a := Vector2(BOX_W, BOX_H * 0.5)
	var lead_b := Vector2(BOX_W + GAP, BOX_H * 0.5)
	_draw_dashed(lead_a, lead_b, lead_col)

	var m := lead_b
	var pts := PackedVector2Array([
		m + Vector2(-MARKER_R, 0),
		m + Vector2(0, -MARKER_R),
		m + Vector2(MARKER_R, 0),
		m + Vector2(0, MARKER_R),
		m + Vector2(-MARKER_R, 0),
	])
	draw_polyline(pts, lead_col, 1.4, true)
	draw_circle(m, 1.5, lead_col)

func _draw_bracket(origin: Vector2, sx: float, sy: float) -> void:
	draw_line(origin, origin + Vector2(BRACKET * sx, 0), COL_ACCENT, 1.6, true)
	draw_line(origin, origin + Vector2(0, BRACKET * sy), COL_ACCENT, 1.6, true)

func _draw_dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var dir := (b - a).normalized()
	var dist := a.distance_to(b)
	var step := DASH + DASH_GAP
	var t := 0.0
	while t < dist:
		var p1: Vector2 = a + dir * t
		var p2: Vector2 = a + dir * minf(t + DASH, dist)
		draw_line(p1, p2, col, 1.3, true)
		t += step
