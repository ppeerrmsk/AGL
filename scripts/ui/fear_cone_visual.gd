extends RefCounted

## 恐惧范围的纯表现层：复用缓冲区，一次三角形提交渐变场与传播波。
## 不保存控制器/飞机引用；范围只读取能力配置，动画只读取游戏阶段计时。
const BASE_RINGS := 9
const PULSES := 3
const PULSE_RINGS := 4
const PULSE_OFFSETS := [-0.035, -0.009, 0.005, 0.026]
var _segments := 0
var _angle := -1.0
var _rays := PackedVector2Array()
var _lateral := PackedFloat32Array()
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _outline := PackedVector2Array()


func draw(canvas: Node2D, frame: Transform2D, cfg: SquadFearConeConfig,
		emitting: bool, remaining: float) -> void:
	var radius := cfg.range_m * CombatUnit.PIXELS_PER_METER
	var screen_radius := radius * maxf(frame.x.length(), frame.y.length())
	if not canvas.get_viewport_rect().grow(screen_radius).has_point(frame.origin): return
	# 缩小后的弧线只需较少分段；不按小队数新增节点、计时器或全场扫描。
	_prepare(32 if screen_radius >= 360.0 else 16, cfg.angle_deg)
	var duration := cfg.emission_s if emitting else cfg.warning_s
	var elapsed := clampf(duration - remaining, 0.0, duration)
	var charge := clampf(elapsed / cfg.warning_s, 0.0, 1.0)
	var strength := 1.0 if emitting else lerpf(0.12, 0.30, charge)
	var fade := smoothstep(0.0, 0.3, remaining) if emitting else 1.0
	var tint := cfg.color
	var pale := tint.lerp(Color(0.92, 0.81, 1.0), 0.55)
	for ring in range(BASE_RINGS):
		var r := float(ring) / float(BASE_RINGS - 1)
		var alpha := (0.07 + 0.24 * pow(1.0 - r, 1.5)) * strength * fade
		if ring == BASE_RINGS - 1: alpha = 0.025 * strength * fade
		_write_ring(ring, r * radius, alpha, pale.lerp(tint, r), frame)
	# 三道软边波前从机鼻向外行进，外缘逐渐消散；没有范围伸缩的误导。
	for pulse in range(PULSES):
		var center := fposmod(elapsed * 0.32 + float(pulse) / PULSES, 1.0)
		var envelope := smoothstep(0.03, 0.18, center) * (1.0 - smoothstep(0.78, 1.0, center))
		for ring in range(PULSE_RINGS):
			var offset: float = PULSE_OFFSETS[ring]
			var r := clampf(center + offset, 0.0, 1.0)
			var alpha := 0.19 * envelope * strength * fade if ring == 1 or ring == 2 else 0.0
			_write_ring(BASE_RINGS + pulse * PULSE_RINGS + ring, r * radius, alpha, pale, frame)
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), _indices, _points, _colors)
	_outline[0] = frame.origin
	for i in range(_segments + 1):
		_outline[i + 1] = frame * (_rays[i] * radius)
	_outline[_segments + 2] = frame.origin
	# 真正判定边界保持固定、细而清楚；宽底线只是低透明柔光。
	var edge := Color(tint, (0.56 if emitting else lerpf(0.18, 0.42, charge)) * cfg.color.a)
	canvas.draw_polyline(_outline, Color(tint, edge.a * 0.14), 5.0, true)
	canvas.draw_polyline(_outline, edge, 1.2, true)
	canvas.draw_circle(frame.origin, 7.0, Color(tint, 0.10 * strength), true, -1.0, true)
	canvas.draw_circle(frame.origin, 2.5, Color(pale, 0.65 * strength), true, -1.0, true)


func _prepare(segments: int, angle: float) -> void:
	if segments == _segments and is_equal_approx(angle, _angle): return
	_segments = segments
	_angle = angle
	var stride := segments + 1
	_rays.resize(stride)
	_lateral.resize(stride)
	_points.resize((BASE_RINGS + PULSES * PULSE_RINGS) * stride)
	_colors.resize(_points.size())
	_outline.resize(segments + 3)
	_indices.clear()
	for i in range(stride):
		var across := float(i) / segments * 2.0 - 1.0
		var theta := deg_to_rad(angle * 0.5 * across)
		_rays[i] = Vector2(sin(theta), -cos(theta))
		_lateral[i] = pow(maxf(0.0, 1.0 - absf(across)), 0.65)
	for ring in range(BASE_RINGS + PULSES * PULSE_RINGS - 1):
		if ring >= BASE_RINGS - 1 and (ring - BASE_RINGS + 1) % PULSE_RINGS == 0: continue
		for i in range(segments):
			var a := ring * stride + i
			_indices.append_array(PackedInt32Array([a, a + 1, a + stride, a + 1, a + stride + 1, a + stride]))


func _write_ring(row: int, radius: float, alpha: float, tint: Color, frame: Transform2D) -> void:
	var start := row * (_segments + 1)
	for i in range(_segments + 1):
		_points[start + i] = frame * (_rays[i] * radius)
		_colors[start + i] = Color(tint, alpha * _lateral[i] * tint.a)
