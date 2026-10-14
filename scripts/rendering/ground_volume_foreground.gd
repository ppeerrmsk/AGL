extends Node2D
## 整个共享合成层仅一个前景批次；_draw 不访问实体或做全场扫描。
var points := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()


func sync(presenter: RefCounted, naval: RefCounted = null) -> void:
	if points.is_empty() and presenter.marker_points.is_empty() and (naval == null or naval.marker_points.is_empty()):
		return
	points = presenter.marker_points.duplicate()
	colors = presenter.marker_colors.duplicate()
	if naval != null:
		points.append_array(naval.marker_points)
		colors.append_array(naval.marker_colors)
	if indices.size() != points.size():
		indices = CanvasTrianglePacket.sequential_indices(points.size())
	queue_redraw()


func _draw() -> void:
	CanvasTrianglePacket.submit_arrays(get_canvas_item(), indices, points, colors)
