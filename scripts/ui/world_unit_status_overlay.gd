class_name WorldUnitStatusOverlay
extends Node2D

## 世界状态栏的唯一最终 Canvas 所有者。它位于独立 CanvasLayer 中，
## 因此单位与相机如何旋转都不会改变标签的屏幕方向。唯一 `_process`
## 只移动已缓存的面板 CanvasItem；文字内容或闪烁相位变化时才重建 draw command。

class StatusPanel extends Node2D:
	var entry: Dictionary = {}
	var visual_signature: Array = []
	var item_ref: WeakRef = null
	var screen_offset_px := Vector2.ZERO

	func sync(next_entry: Dictionary, item: Node2D) -> void:
		item_ref = weakref(item)
		screen_offset_px = next_entry.get("screen_offset_px", Vector2.ZERO)
		var next_signature := AircraftRenderer.status_panel_visual_signature(
			next_entry, item)
		if next_signature != visual_signature:
			entry = next_entry
			visual_signature = next_signature
			queue_redraw()
		var alpha := clampf(item.modulate.a * item.self_modulate.a, 0.0, 1.0)
		self_modulate = Color(1.0, 1.0, 1.0, alpha)

	func update_screen_position() -> bool:
		var item_value: Variant = item_ref.get_ref() if item_ref != null else null
		if typeof(item_value) != TYPE_OBJECT or not is_instance_valid(item_value) \
				or not item_value is Node2D:
			return false
		var item := item_value as Node2D
		if not item.is_inside_tree() or not item.is_visible_in_tree():
			visible = false
			return true
		visible = true
		var screen_origin := item.get_global_transform_with_canvas().origin
		transform = AircraftRenderer.status_panel_overlay_transform_for(
			screen_origin, screen_offset_px)
		var alpha := clampf(item.modulate.a * item.self_modulate.a, 0.0, 1.0)
		self_modulate = Color(1.0, 1.0, 1.0, alpha)
		return true

	func _draw() -> void:
		AircraftRenderer.draw_status_panel_entry(self, entry)


var _panels: Dictionary = {}
var _content_sync_accum := 1.0
const CONTENT_SYNC_INTERVAL_S := 0.05


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AircraftRenderer.install_status_overlay(self)


func _exit_tree() -> void:
	AircraftRenderer.uninstall_status_overlay(self)


func _process(delta: float) -> void:
	var perf_t0 := Time.get_ticks_usec()
	_content_sync_accum += delta
	if _content_sync_accum >= CONTENT_SYNC_INTERVAL_S:
		_content_sync_accum = fmod(_content_sync_accum, CONTENT_SYNC_INTERVAL_S)
		_sync_registered_panels()
	for raw_panel: Variant in _panels.values():
		if typeof(raw_panel) == TYPE_OBJECT and is_instance_valid(raw_panel):
			(raw_panel as StatusPanel).update_screen_position()
	PerfBuckets.tick("unit_status_overlay", Time.get_ticks_usec() - perf_t0)


func _sync_registered_panels() -> void:
	var live_ids: Dictionary = {}
	for raw_id: Variant in AircraftRenderer.status_panel_entry_ids():
		var entry_id := int(raw_id)
		var entry := AircraftRenderer.status_panel_entry(entry_id)
		var item := AircraftRenderer.status_panel_item(entry)
		if item == null:
			continue
		if not item.is_inside_tree() or not item.is_visible_in_tree():
			continue
		live_ids[entry_id] = true
		var panel: StatusPanel = _panels.get(entry_id)
		if panel == null:
			panel = StatusPanel.new()
			panel.name = "StatusPanel_%d" % entry_id
			_panels[entry_id] = panel
			add_child(panel)
		panel.sync(entry, item)
	for raw_id: Variant in _panels.keys():
		var entry_id := int(raw_id)
		if live_ids.has(entry_id):
			continue
		var stale_panel: Variant = _panels.get(entry_id)
		if typeof(stale_panel) == TYPE_OBJECT and is_instance_valid(stale_panel):
			(stale_panel as Node).queue_free()
		_panels.erase(entry_id)
