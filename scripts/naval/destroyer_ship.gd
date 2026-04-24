class_name DestroyerShip
extends NavalUnit

## DDG 导弹驱逐舰 —— 主力威胁级（Arleigh Burke 风格）
##
## 4 挂点：前 VLS（+60,0 HP100）+ 后 VLS（-60,0 HP100）+ 左 CIWS（0,-12 HP30）+ 右 CIWS（0,+12 HP30）
## 弱点阈值 2 / HP 60，总血 480
## VLS 齐射 5 枚中距 SAM
##
## 视觉特征（俯视）：
##   - 比 FFG 宽一档，船体更结实
##   - 船中央一个高大舰桥（比 FFG 的桥楼明显大）
##   - 船头船尾各一个 VLS 甲板标识（矩形阵列）
##   - 船尾有一块直升机甲板

func _draw_hull_placeholder() -> void:
	if params == null:
		return
	var L: float = params.hull_length
	var W: float = params.hull_width
	var color: Color = GameConstants.team_color(team)
	var outline_color: Color = color.darkened(0.35)
	var half_L: float = L * 0.5
	var half_W: float = W * 0.5

	# 船体：船头收窄 + 船尾平 + 中段最宽
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -half_L),                       # 船头尖
		Vector2(half_W * 0.7, -half_L * 0.88),
		Vector2(half_W, -half_L * 0.5),
		Vector2(half_W, half_L * 0.6),
		Vector2(half_W * 0.88, half_L * 0.95),
		Vector2(half_W * 0.7, half_L),
		Vector2(-half_W * 0.7, half_L),
		Vector2(-half_W * 0.88, half_L * 0.95),
		Vector2(-half_W, half_L * 0.6),
		Vector2(-half_W, -half_L * 0.5),
		Vector2(-half_W * 0.7, -half_L * 0.88),
	])
	draw_colored_polygon(body, color)
	for i in range(body.size()):
		draw_line(body[i], body[(i + 1) % body.size()], outline_color, 1.5)

	# 中央舰桥（较大，占船中偏前的位置）
	var bridge_color: Color = outline_color.darkened(0.15)
	var bridge_rect := Rect2(-half_W * 0.35, -half_L * 0.15, half_W * 0.7, half_L * 0.3)
	draw_rect(bridge_rect, bridge_color)
	draw_rect(bridge_rect, color.lightened(0.1), false, 1.0)

	# 前后 VLS 甲板标识（网格矩形）
	var vls_color: Color = outline_color.lightened(0.15)
	# 前 VLS（船头方向的甲板）
	var vls_f := Rect2(-half_W * 0.5, -half_L * 0.55, half_W * 1.0, half_L * 0.2)
	draw_rect(vls_f, vls_color, false, 1.0)
	# 后 VLS
	var vls_a := Rect2(-half_W * 0.5, half_L * 0.3, half_W * 1.0, half_L * 0.2)
	draw_rect(vls_a, vls_color, false, 1.0)

	# 船尾直升机甲板
	var heli_color: Color = outline_color.lightened(0.2)
	draw_line(Vector2(-half_W * 0.4, half_L * 0.75), Vector2(half_W * 0.4, half_L * 0.75), heli_color, 1.0)
