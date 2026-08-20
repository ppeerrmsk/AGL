extends Node2D

## 同一采样相位的导弹尾迹共用一个 retained CanvasItem。
## 尾迹几何仍由各 TrailRibbon 维护；本节点只负责把缓存拼成一次 triangle-array 提交。

var manager: Node = null
var phase_slot: int = 0


func setup(owner_manager: Node, slot: int) -> void:
	manager = owner_manager
	phase_slot = slot
	top_level = true
	global_transform = Transform2D.IDENTITY


func _draw() -> void:
	var perf_detail := PerfBuckets.detail_capture_enabled()
	var perf_t0 := Time.get_ticks_usec() if perf_detail else 0
	_draw_impl()
	if perf_detail:
		PerfBuckets.tick("missile_trail_draw", Time.get_ticks_usec() - perf_t0)


func _draw_impl() -> void:
	if manager == null or not is_instance_valid(manager):
		return
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for child in manager.get_children():
		if child == null or not ("_trail_ribbon" in child):
			continue
		var trail = child.get("_trail_ribbon")
		if trail == null or not trail.has_method("missile_batch_phase_slot") \
				or trail.missile_batch_phase_slot() != phase_slot:
			continue
		trail.append_to_missile_batch(verts, colors, indices)
	PerfBuckets.set_value("missile_trail_batch_%d_verts" % phase_slot, verts.size())
	if indices.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), indices, verts, colors)
