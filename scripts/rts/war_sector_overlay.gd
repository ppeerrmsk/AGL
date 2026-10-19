extends Node2D
## 只有控制权变化才重画；战区坐标缓存，不扫描实体。
var centers: Array[Vector2] = []
var owners: Array[int] = []
var radius := 1600.0

func set_sectors(points: Array[Vector2], control: Array[int]) -> void:
	if centers == points and owners == control:
		return
	centers = points.duplicate()
	owners = control.duplicate()
	queue_redraw()

func _draw() -> void:
	for i in range(centers.size()):
		var color := Color(0.55, 0.6, 0.65, 0.22)
		if owners[i] == 0:
			color = Color(0.3, 0.65, 1.0, 0.3)
		elif owners[i] == 1:
			color = Color(1.0, 0.3, 0.3, 0.3)
		draw_arc(centers[i], radius, 0.0, TAU, 96, color, 8.0)
		draw_line(centers[i] - Vector2(80, 0), centers[i] + Vector2(80, 0), color, 8.0)
		draw_line(centers[i] - Vector2(0, 80), centers[i] + Vector2(0, 80), color, 8.0)
