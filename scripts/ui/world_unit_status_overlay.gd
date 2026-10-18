class_name WorldUnitStatusOverlay
extends Node2D

## 世界状态栏的唯一最终 Canvas 所有者。它位于独立 CanvasLayer 中，
## 因此单位与相机如何旋转都不会改变标签的屏幕方向。唯一 `_process`
## 只移动已缓存的面板 CanvasItem；文字内容或闪烁相位变化时才重建 draw command。

const DisplayPacing := preload("res://scripts/util/display_pacing.gd")


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
		# 物理插值显示态：标签与插值后的机体同相位，不在 tick 间相对机体抖动。
		var screen_origin := DisplayPacing.display_screen_origin(item)
		transform = AircraftRenderer.status_panel_overlay_transform_for(
			screen_origin, screen_offset_px)
		var alpha := clampf(item.modulate.a * item.self_modulate.a, 0.0, 1.0)
		self_modulate = Color(1.0, 1.0, 1.0, alpha)
		return true

	func _draw() -> void:
		var started := Time.get_ticks_usec() if PerfBuckets.extended_cpu_trace_enabled else 0
		var shared := PerfBuckets.extended_cpu_shared_usec
		AircraftRenderer.draw_status_panel_entry(self, entry)
		if started > 0:
			PerfBuckets.finish_extended_cpu("status_panel_draw", started, shared)


var _panels: Dictionary = {}
var _content_sync_accum := 1.0
var _fear_drawing := false
const CONTENT_SYNC_INTERVAL_S := 0.05


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AircraftRenderer.install_status_overlay(self)


func _exit_tree() -> void:
	AircraftRenderer.uninstall_status_overlay(self)


func _process(delta: float) -> void:
	var perf_t0 := Time.get_ticks_usec()
	var fear_drawing := false
	for controller in SquadFearConeController.live_controllers():
		if controller.emitter() != null:
			fear_drawing = true
			break
	if fear_drawing or _fear_drawing:
		queue_redraw()
	_fear_drawing = fear_drawing
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


## 单一屏幕层批绘真实世界锥体，既兼容 2D 又不被正式 3D 地表盖住。
func _draw() -> void:
	var started := Time.get_ticks_usec() if PerfBuckets.extended_cpu_trace_enabled else 0
	var shared := PerfBuckets.extended_cpu_shared_usec
	for controller in SquadFearConeController.live_controllers():
		var ac := controller.emitter()
		if ac == null or ac.is_destroyed or not ac.is_inside_tree():
			continue
		var cfg := controller.config
		var world_to_screen := ac.get_canvas_transform()
		var ac_display := DisplayPacing.display_global_transform(ac)
		var ac_origin := ac_display.origin
		var ac_heading := ac.heading + DisplayPacing.rotation_offset_from(ac, ac_display)
		var polygon := PackedVector2Array([world_to_screen * ac_origin])
		for i in range(25):
			var angle := ac_heading + deg_to_rad(cfg.angle_deg * (float(i) / 24.0 - 0.5))
			polygon.append(world_to_screen * (ac_origin + Vector2(sin(angle), -cos(angle)) * cfg.range_m * CombatUnit.PIXELS_PER_METER))
		var fill := cfg.color
		fill.a = 0.16 if controller.phase == SquadFearConeController.Phase.EMISSION else 0.05
		draw_colored_polygon(polygon, fill)
		polygon.append(polygon[0])
		draw_polyline(polygon, cfg.color, 2.0, true)
		for id: Variant in controller.exposure:
			var target := FearResponse.aircraft(instance_from_id(int(id)))
			if target == null or not target.is_inside_tree():
				continue
			var screen := DisplayPacing.display_screen_origin(target) + Vector2(-20.0, -35.0)
			draw_rect(Rect2(screen, Vector2(40, 5)), Color(0, 0, 0, 0.9))
			draw_rect(Rect2(screen, Vector2(40.0 * float(controller.exposure[id]) / cfg.exposure_s, 5)), cfg.color)
	if started > 0:
		PerfBuckets.finish_extended_cpu("status_mask_draw", started, shared)
