class_name TrailRibbon
extends Node2D

## 飞行轨迹丝带效果
## 作为子节点挂载到 Aircraft 或 Missile 上

@export var ribbon_color: Color = Color(0.3, 0.5, 1.0, 0.6)
@export var ribbon_width: float = 8.0
@export var max_points: int = 150
@export var sample_interval: float = 0.05  ## 采样间隔（秒）

var _trail_data: Array = []  ## Array of { pos: Vector2, heading: float, bank: float }
var _sample_timer: float = 0.0

func add_point(pos: Vector2, heading: float, bank: float) -> void:
	_trail_data.append({ "pos": pos, "heading": heading, "bank": bank })
	if _trail_data.size() > max_points:
		_trail_data.remove_at(0)

func _process(delta: float) -> void:
	_sample_timer += delta
	if _sample_timer >= sample_interval:
		_sample_timer -= sample_interval
		var parent := get_parent()
		if parent:
			var bank: float = parent.bank_angle if "bank_angle" in parent else 0.0
			var hdg: float = parent.heading if "heading" in parent else parent.rotation
			add_point(parent.global_position, hdg, bank)
	queue_redraw()

func _draw() -> void:
	var count := _trail_data.size()
	if count < 2:
		return

	for i in range(count - 1):
		var d0: Dictionary = _trail_data[i]
		var d1: Dictionary = _trail_data[i + 1]

		var p0: Vector2 = to_local(d0["pos"])
		var p1: Vector2 = to_local(d1["pos"])

		# 飞行方向
		var dir := (p1 - p0)
		if dir.length_squared() < 0.01:
			continue
		dir = dir.normalized()

		# 垂直于飞行方向（右侧）
		var perp := Vector2(-dir.y, dir.x)

		# 进度比 (0=最旧, 1=最新)
		var t0 := float(i) / float(count - 1)
		var t1 := float(i + 1) / float(count - 1)

		# Alpha 渐变：尾部淡出
		var alpha0 := t0 * ribbon_color.a
		var alpha1 := t1 * ribbon_color.a

		# 丝带宽度随 bank_angle 变化模拟 3D 翻转
		var bank0: float = d0["bank"]
		var bank1: float = d1["bank"]
		var w0 := ribbon_width * cos(bank0)
		var w1 := ribbon_width * cos(bank1)

		# 中心偏移模拟侧翻
		var offset0 := perp * ribbon_width * sin(bank0) * 0.3
		var offset1 := perp * ribbon_width * sin(bank1) * 0.3

		# 四个顶点（四边形条带）
		var v0 := p0 + offset0 + perp * w0 * 0.5
		var v1 := p0 + offset0 - perp * w0 * 0.5
		var v2 := p1 + offset1 - perp * w1 * 0.5
		var v3 := p1 + offset1 + perp * w1 * 0.5

		var c0 := Color(ribbon_color.r, ribbon_color.g, ribbon_color.b, alpha0)
		var c1 := Color(ribbon_color.r, ribbon_color.g, ribbon_color.b, alpha1)

		var verts := PackedVector2Array([v0, v3, v2, v1])
		var colors := PackedColorArray([c0, c1, c1, c0])
		draw_polygon(verts, colors)
