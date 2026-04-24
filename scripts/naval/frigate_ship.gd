class_name FrigateShip
extends NavalUnit

## FFG 护卫舰 —— 海上 "UAV" / Adds 级
##
## 2 挂点：近程 SAM（+33,0 HP50）+ CIWS（-33,0 HP30）
## 无弱点，挂点全清即沉；总血 120
## 航速最快，火力最弱，船型最小
##
## 视觉特征（俯视）：
##   - 细长流线型，长宽比 ~5:1
##   - 无明显舰岛，只有船中小型桥楼
##   - 船头尖（Knox / Perry 类护卫舰的特征）
##   - 船尾短台（直升机甲板）

## 本地绘制坐标系：船头朝 -Y，+X = 右舷
func _draw_hull_placeholder() -> void:
	if params == null:
		return
	var L: float = params.hull_length
	var W: float = params.hull_width
	var color: Color = GameConstants.team_color(team)
	var outline_color: Color = color.darkened(0.35)
	var half_L: float = L * 0.5
	var half_W: float = W * 0.5

	# 流线型船体（9 点多边形，船头收窄，船尾平）
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -half_L),                       # 船头尖
		Vector2(half_W * 0.55, -half_L * 0.88),
		Vector2(half_W, -half_L * 0.3),
		Vector2(half_W, half_L * 0.5),
		Vector2(half_W * 0.92, half_L * 0.9),
		Vector2(half_W * 0.6, half_L),             # 船尾右
		Vector2(-half_W * 0.6, half_L),            # 船尾左
		Vector2(-half_W * 0.92, half_L * 0.9),
		Vector2(-half_W, half_L * 0.5),
		Vector2(-half_W, -half_L * 0.3),
		Vector2(-half_W * 0.55, -half_L * 0.88),
	])
	draw_colored_polygon(body, color)
	for i in range(body.size()):
		draw_line(body[i], body[(i + 1) % body.size()], outline_color, 1.5)

	# 小桥楼（船中深色小矩形）
	var bridge_color: Color = outline_color.darkened(0.15)
	var bridge_rect := Rect2(-half_W * 0.25, -half_L * 0.1, half_W * 0.5, half_L * 0.2)
	draw_rect(bridge_rect, bridge_color)
	draw_rect(bridge_rect, color.lightened(0.1), false, 1.0)

	# 船尾直升机甲板纹理线（白色短线）
	var line_color: Color = outline_color.lightened(0.35)
	draw_line(Vector2(0, half_L * 0.65), Vector2(0, half_L * 0.95), line_color, 1.0)
