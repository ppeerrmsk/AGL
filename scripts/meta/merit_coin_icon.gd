class_name MeritCoinIcon
extends Control

## 功勋硬币图标 — 纯 _draw 绘制，无外部资源依赖。
## 双圈描边 + 12 边缘齿 + 中心十字星，与项目线框美术一致。

@export var coin_color: Color = Color(0.85, 0.75, 0.35)         ## 金色描边
@export var coin_color_dim: Color = Color(0.55, 0.45, 0.18, 0.7) ## 内部装饰更暗
@export var radius: float = 12.0
@export var line_width: float = 1.4

const TEETH := 12

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(radius * 2.0 + 4.0, radius * 2.0 + 4.0)
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := radius
	var r_in := r * 0.72

	# 边缘齿（12 段短切线，钢镚边缘的感觉）
	for i in range(TEETH):
		var a := TAU * float(i) / float(TEETH)
		var p0 := c + Vector2(cos(a), sin(a)) * (r - 1.5)
		var p1 := c + Vector2(cos(a), sin(a)) * (r + 1.5)
		draw_line(p0, p1, coin_color_dim, 1.0)

	# 外圈
	draw_arc(c, r, 0.0, TAU, 48, coin_color, line_width, true)
	# 内圈
	draw_arc(c, r_in, 0.0, TAU, 40, coin_color_dim, 1.0, true)

	# 中心十字星 —— 简洁、不依赖字体
	var s := r_in * 0.55
	draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), coin_color, line_width, true)
	draw_line(c + Vector2(0, -s), c + Vector2(0, s), coin_color, line_width, true)
	# 四个对角点缀
	var d := r_in * 0.45
	for k in [Vector2(1,1), Vector2(1,-1), Vector2(-1,1), Vector2(-1,-1)]:
		draw_circle(c + k * d * 0.5, 1.2, coin_color_dim)
