extends Node2D
## 单个 BOSS 共用表现节点；绘制只消费有界纯值快照，不扫描战场。

var _locks: Array[Dictionary] = []
var _beams: Array[Dictionary] = []
var _rail: Array[Dictionary] = []
var _intercepts: Array[Dictionary] = []


func present(locks: Array[Dictionary], beams: Array[Dictionary], rail: Array[Dictionary],
		intercepts: Array[Dictionary]) -> void:
	_locks = locks
	_beams = beams
	_rail = rail
	_intercepts = intercepts
	visible = not (_locks.is_empty() and _beams.is_empty() and _rail.is_empty() and _intercepts.is_empty())
	if visible:
		queue_redraw()


func _draw() -> void:
	for flash in _intercepts:
		var alpha := clampf(float(flash["life"]) / 0.2, 0.0, 1.0)
		draw_arc(flash["position"], lerpf(20.0, 4.0, alpha), 0.0, TAU, 12,
			Color(0.7, 0.95, 1.0, alpha), 2.0, true)
	for lock in _locks:
		var point: Vector2 = lock["position"]
		var side := lerpf(44.0, 28.0, float(lock["progress"]))
		var color := Color(1.0, 0.3, 0.24, float(lock["alpha"]))
		draw_rect(Rect2(point - Vector2.ONE * side, Vector2.ONE * side * 2.0), color, false, 1.5)
		draw_string(ThemeDB.fallback_font, point + Vector2(side + 4.0, 0.0),
			str(lock["count"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, color)
	for beam in _beams:
		var start: Vector2 = beam["start"]
		var end: Vector2 = beam["end"]
		if bool(beam["active"]):
			draw_line(start, end, Color(0.3, 0.8, 1.0, 0.22), 16.0, true)
			draw_line(start, end, Color(0.65, 0.92, 1.0, 0.9), 12.0, true)
			draw_line(start, end, Color.WHITE, 2.0, true)
		else:
			draw_dashed_line(start, end, Color(1.0, 0.3, 0.24, 0.65), 1.5, 20.0, true)
	for rail in _rail:
		var alpha := clampf(float(rail["life"]) / 0.25, 0.0, 1.0)
		draw_line(rail["start"], rail["end"], Color(1.0, 0.45, 0.25, alpha), 6.0, true)
		draw_line(rail["start"], rail["end"], Color(1.0, 1.0, 0.95, alpha), 1.5, true)
