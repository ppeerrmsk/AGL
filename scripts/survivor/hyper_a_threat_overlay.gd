class_name HyperAThreatOverlay
extends Node2D

## Black Star 的有界战场提示层。只绘制 encounter 已锁存的几何快照；
## 不选目标、不推进计时、不拥有伤害，保证视觉与判定同源。

const AOE_FILL := Color(1.0, 0.14, 0.08, 0.10)
const AOE_EDGE := Color(1.0, 0.30, 0.16, 0.88)
const DASH_FILL := Color(1.0, 0.24, 0.10, 0.10)
const DASH_EDGE := Color(1.0, 0.52, 0.20, 0.92)
const IMPACT_COLOR := Color(1.0, 0.78, 0.30, 0.95)

var _aoes: Array = []
var _dash_lines: Array = []
var _flashes: Array = []


func sync(aoes: Array, dash_lines: Array, flashes: Array) -> void:
	_aoes = aoes
	_dash_lines = dash_lines
	_flashes = flashes
	visible = not _aoes.is_empty() or not _dash_lines.is_empty() or not _flashes.is_empty()
	if visible:
		queue_redraw()


func _draw() -> void:
	for warning in _aoes:
		_draw_aoe(warning as Dictionary)
	for warning in _dash_lines:
		_draw_dash(warning as Dictionary)
	for flash in _flashes:
		_draw_flash(flash as Dictionary)


func _draw_aoe(warning: Dictionary) -> void:
	var center: Vector2 = warning.get("center", Vector2.ZERO)
	var radius: float = float(warning.get("radius_px", 0.0))
	if radius <= 0.0:
		return
	var ratio: float = clampf(float(warning.get("ratio", 0.0)), 0.0, 1.0)
	var pulse: float = 0.82 + 0.18 * sin(ratio * TAU * 5.0)
	draw_circle(center, radius, AOE_FILL)
	draw_arc(center, radius, 0.0, TAU, 96, AOE_EDGE, 3.0, true)
	draw_arc(center, radius * (0.35 + ratio * 0.65), 0.0, TAU, 72,
		Color(AOE_EDGE.r, AOE_EDGE.g, AOE_EDGE.b, AOE_EDGE.a * pulse), 2.0, true)
	draw_line(center + Vector2(-18, 0), center + Vector2(18, 0), AOE_EDGE, 2.0)
	draw_line(center + Vector2(0, -18), center + Vector2(0, 18), AOE_EDGE, 2.0)


func _draw_dash(warning: Dictionary) -> void:
	var from: Vector2 = warning.get("from", Vector2.ZERO)
	var to: Vector2 = warning.get("to", Vector2.ZERO)
	var full_width: float = float(warning.get("width_px", 0.0))
	var delta: Vector2 = to - from
	if delta.length_squared() <= 1.0 or full_width <= 0.0:
		return
	var dir := delta.normalized()
	var side := Vector2(-dir.y, dir.x) * full_width * 0.5
	var band := PackedVector2Array([from + side, to + side, to - side, from - side])
	draw_colored_polygon(band, DASH_FILL)
	draw_line(from + side, to + side, DASH_EDGE, 2.0)
	draw_line(from - side, to - side, DASH_EDGE, 2.0)
	draw_dashed_line(from, to, Color(DASH_EDGE, 0.75), 2.0, 18.0, true)
	for i in range(1, 5):
		var p := from.lerp(to, float(i) / 5.0)
		draw_line(p - dir * 14.0 + side * 0.28, p + dir * 14.0, DASH_EDGE, 2.0)
		draw_line(p - dir * 14.0 - side * 0.28, p + dir * 14.0, DASH_EDGE, 2.0)


func _draw_flash(flash: Dictionary) -> void:
	var center: Vector2 = flash.get("center", Vector2.ZERO)
	var radius: float = float(flash.get("radius_px", 0.0))
	var ratio: float = clampf(float(flash.get("ratio", 0.0)), 0.0, 1.0)
	if radius <= 0.0:
		return
	var alpha: float = 1.0 - ratio
	draw_circle(center, radius * (0.08 + ratio * 0.16),
		Color(IMPACT_COLOR.r, IMPACT_COLOR.g, IMPACT_COLOR.b, 0.20 * alpha))
	draw_arc(center, radius * ratio, 0.0, TAU, 96,
		Color(IMPACT_COLOR.r, IMPACT_COLOR.g, IMPACT_COLOR.b, alpha),
		4.0 * alpha + 1.0, true)
