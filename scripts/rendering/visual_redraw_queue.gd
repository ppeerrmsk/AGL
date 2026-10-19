extends RefCounted
## 物理补帧只更新状态；在本次呈现前合并Canvas命令重建，保留最终状态和原刷新请求。
## 不降物理频率、不丢更新、不改变可见性/LOD；非物理调用仍沿原立即排队路径。
static var _pending: Dictionary = {}


static func request(item: CanvasItem) -> void:
	if not Engine.is_in_physics_frame() or not item.is_inside_tree():
		item.queue_redraw()
		return
	var id := item.get_instance_id()
	if PerfBuckets.frame_trace_enabled: PerfBuckets.count("visual_redraw.requests")
	if _pending.has(id):
		if PerfBuckets.frame_trace_enabled: PerfBuckets.count("visual_redraw.coalesced")
		return
	_pending[id]=weakref(item)
	var tree := item.get_tree()
	if not tree.process_frame.is_connected(_flush):
		tree.process_frame.connect(_flush,CONNECT_ONE_SHOT)


static func _flush() -> void:
	var batch := _pending
	_pending={}
	for reference: WeakRef in batch.values():
		# 物理步内可能已经终态释放；先净化Variant，再触碰CanvasItem接口。
		var item: Variant=reference.get_ref()
		if typeof(item)!=TYPE_OBJECT or not is_instance_valid(item) or not item is CanvasItem: continue
		if not item.is_inside_tree() or item.is_queued_for_deletion(): continue
		item.queue_redraw()
		if PerfBuckets.frame_trace_enabled: PerfBuckets.count("visual_redraw.flushed")
