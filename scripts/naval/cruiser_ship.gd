class_name CruiserShip
extends NavalUnit

## CG 导弹巡洋舰 —— Aegis 防空核心（Ticonderoga 风格）
##
## 4 挂点：前 VLS（+75,0 HP150）+ 后 VLS（-75,0 HP150）
##        + 前 CIWS（+45,0 HP30）+ 后 CIWS（-45,0 HP30）
## 弱点阈值 2 / HP 60，总血 720
## VLS 齐射 8 枚远距 SAM（9000m 射程）
##
## 视觉特征（俯视）：
##   - 比 DDG 更大更宽，船体轮廓更方正
##   - 船头和船尾都有巨大 VLS 甲板阵列（与 Ticonderoga 标志性的前后甲板对应）
##   - 中央主桅 + SPY 相控阵雷达（大方块 4 面）
##   - 船尾无直升机甲板（巡洋舰优先火力而非航空支援）

func _draw_hull_placeholder() -> void:
	if params == null:
		return
	var L: float = params.hull_length
	var W: float = params.hull_width
	var color: Color = GameConstants.team_color(team)
	var outline_color: Color = color.darkened(0.35)
	var half_L: float = L * 0.5
	var half_W: float = W * 0.5

	# 船体：更方正的轮廓（前后更宽，中段微收）
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -half_L),
		Vector2(half_W * 0.8, -half_L * 0.92),
		Vector2(half_W, -half_L * 0.6),
		Vector2(half_W * 0.95, 0.0),               # 中段微收
		Vector2(half_W, half_L * 0.6),
		Vector2(half_W * 0.88, half_L * 0.95),
		Vector2(half_W * 0.7, half_L),
		Vector2(-half_W * 0.7, half_L),
		Vector2(-half_W * 0.88, half_L * 0.95),
		Vector2(-half_W, half_L * 0.6),
		Vector2(-half_W * 0.95, 0.0),
		Vector2(-half_W, -half_L * 0.6),
		Vector2(-half_W * 0.8, -half_L * 0.92),
	])
	draw_colored_polygon(body, color)
	for i in range(body.size()):
		draw_line(body[i], body[(i + 1) % body.size()], outline_color, 1.5)

	# 前后 VLS 甲板（Aegis 巡洋舰标志性的大型垂直发射阵列）
	var vls_color: Color = outline_color.lightened(0.15)
	var vls_f := Rect2(-half_W * 0.55, -half_L * 0.7, half_W * 1.1, half_L * 0.25)
	var vls_a := Rect2(-half_W * 0.55, half_L * 0.45, half_W * 1.1, half_L * 0.25)
	draw_rect(vls_f, vls_color, false, 1.2)
	draw_rect(vls_a, vls_color, false, 1.2)
	# VLS 内部网格（模拟单元格）
	for k in range(1, 4):
		var fx: float = lerpf(-half_W * 0.55, half_W * 0.55, float(k) / 4.0)
		draw_line(Vector2(fx, -half_L * 0.7), Vector2(fx, -half_L * 0.45), vls_color, 0.8)
		draw_line(Vector2(fx, half_L * 0.45), Vector2(fx, half_L * 0.7), vls_color, 0.8)

	# 中央舰桥 + SPY 相控阵雷达（大方块，比 DDG 的桥楼更大）
	var bridge_color: Color = outline_color.darkened(0.15)
	var bridge_rect := Rect2(-half_W * 0.45, -half_L * 0.2, half_W * 0.9, half_L * 0.35)
	draw_rect(bridge_rect, bridge_color)
	draw_rect(bridge_rect, color.lightened(0.1), false, 1.2)
	# SPY 雷达面（船桥顶部两个小矩形）
	var radar_color: Color = color.lightened(0.3)
	draw_rect(Rect2(-half_W * 0.35, -half_L * 0.1, half_W * 0.2, half_L * 0.08), radar_color)
	draw_rect(Rect2(half_W * 0.15, -half_L * 0.1, half_W * 0.2, half_L * 0.08), radar_color)
