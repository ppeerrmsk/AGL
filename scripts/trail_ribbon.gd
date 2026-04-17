class_name TrailRibbon
extends Node2D

## 飞行轨迹丝带效果
## 作为子节点挂载到 Aircraft 或 Missile 上

@export var ribbon_color: Color = Color(0.3, 0.5, 1.0, 0.6)
@export var ribbon_width: float = 8.0
@export var max_points: int = 80   ## 性能敏感：300→80，视觉上尾迹稍短但密度不变
@export var sample_interval: float = 0.05  ## 采样间隔（秒）= 采样率 20Hz

var _trail_data: Array = []  ## Array of { pos: Vector2, heading: float, bank: float }
var _sample_timer: float = 0.0

func add_point(pos: Vector2, heading: float, bank: float) -> void:
	_trail_data.append({ "pos": pos, "heading": heading, "bank": bank })
	if _trail_data.size() > max_points:
		_trail_data.remove_at(0)

## 清空轨迹（用于传送/重生等场景，避免跨越的丝带）
func clear_trail() -> void:
	_trail_data.clear()
	_sample_timer = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	_sample_timer += delta
	if _sample_timer >= sample_interval:
		_sample_timer -= sample_interval
		var parent := get_parent()
		if parent:
			var bank: float = parent.bank_angle if "bank_angle" in parent else 0.0
			var hdg: float = parent.heading if "heading" in parent else parent.rotation
			add_point(parent.global_position, hdg, bank)
	# 每帧必须重绘：trail 点存世界坐标，_draw 里通过 to_local 换算到父节点局部坐标，
	# 父节点（Aircraft）在飞，transform 一直变，canvas 命令不每帧刷新会导致尾迹跟飞机抖
	queue_redraw()

## 用 RenderingServer 的三角形索引数组一次性提交整条丝带（GPU 命令 N→1）
## 原：max_points=300 × 60Hz × 22架 ≈ 40 万次 draw_polygon/秒（GPU 命令爆炸）
## 新：1 次/帧 × 20Hz × 22架 ≈ 440 次/秒
func _draw() -> void:
	var count := _trail_data.size()
	if count < 2:
		return

	# 每个采样点产生上/下两个顶点 = 2*count 个顶点
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	verts.resize(count * 2)
	colors.resize(count * 2)

	var inv_last := 1.0 / float(count - 1)
	var prev_local := to_local(_trail_data[0]["pos"])

	for i in range(count):
		var d: Dictionary = _trail_data[i]
		var p_local: Vector2 = to_local(d["pos"])

		var fwd: Vector2
		if i == 0:
			fwd = to_local(_trail_data[1]["pos"]) - p_local
		elif i == count - 1:
			fwd = p_local - prev_local
		else:
			fwd = to_local(_trail_data[i + 1]["pos"]) - prev_local
		if fwd.length_squared() < 0.01:
			fwd = Vector2.UP
		else:
			fwd = fwd.normalized()
		var perp := Vector2(-fwd.y, fwd.x)

		var bank: float = d["bank"]
		var w := ribbon_width * cos(bank) * 0.5
		var off := perp * ribbon_width * sin(bank) * 0.3

		var alpha := float(i) * inv_last * ribbon_color.a
		var c := Color(ribbon_color.r, ribbon_color.g, ribbon_color.b, alpha)

		verts[i * 2] = p_local + off + perp * w
		verts[i * 2 + 1] = p_local + off - perp * w
		colors[i * 2] = c
		colors[i * 2 + 1] = c

		prev_local = p_local

	# 索引构造三角形（2×(count-1) 个三角形 = 丝带状）
	var indices := PackedInt32Array()
	indices.resize((count - 1) * 6)
	for i in range(count - 1):
		var base := i * 2
		var idx := i * 6
		indices[idx] = base
		indices[idx + 1] = base + 1
		indices[idx + 2] = base + 2
		indices[idx + 3] = base + 1
		indices[idx + 4] = base + 3
		indices[idx + 5] = base + 2

	# RenderingServer 层一次性提交（比 N 次 draw_polygon 快一个数量级）
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), indices, verts, colors
	)
