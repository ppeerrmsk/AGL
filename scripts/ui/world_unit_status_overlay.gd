class_name WorldUnitStatusOverlay
extends Node2D

## 世界状态栏的唯一最终 Canvas 所有者。它位于独立 CanvasLayer 中，
## 因此单位与相机如何旋转都不会改变标签的屏幕方向。唯一 `_process`
## 只移动已缓存的面板 CanvasItem；文字内容或闪烁相位变化时才重建 draw command。

const TacticalCanvas := preload("res://scripts/rendering/unit_tactical_canvas.gd")
var _tactical_panels: Dictionary = {}

const Snapshot := preload("res://scripts/ui/unit_status_snapshot.gd")

const DisplayPacing := preload("res://scripts/util/display_pacing.gd")
const FearConeVisual := preload("res://scripts/ui/fear_cone_visual.gd")
var _fear_visual := FearConeVisual.new()


class StatusPanel extends Node2D:
	var entry: Dictionary = {}
	var visual_signature: Array = []
	var item_ref: WeakRef = null
	var screen_offset_px := Vector2.ZERO
	var next_content_ms: int = 0
	var content_key: Array = []

	func sync(next_entry: Dictionary, item: Node2D) -> void:
		item_ref = weakref(item)
		screen_offset_px = next_entry.get("screen_offset_px", Vector2.ZERO)
		var next_signature := AircraftRenderer.status_panel_visual_signature(
			next_entry, item)
		entry = next_entry
		if next_signature != visual_signature:
			visual_signature = next_signature
			queue_redraw()
		var alpha := clampf(item.modulate.a * item.self_modulate.a, 0.0, 1.0)
		self_modulate = Color(1.0, 1.0, 1.0, alpha)

	func update_screen_position() -> bool:
		var item_value: Variant = item_ref.get_ref() if item_ref != null else null
		if typeof(item_value) != TYPE_OBJECT or not is_instance_valid(item_value) \
				or not item_value is Node2D:
			visible = false
			return false
		var item := item_value as Node2D
		if Snapshot.mode(item).is_empty():
			visible = false
			return true
		visible = true
		# 物理插值显示态：标签与插值后的机体同相位，不在 tick 间相对机体抖动。
		screen_offset_px = Snapshot.screen_offset(item)
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
var _next_sync_ms: int = 0
var _source_revision: int = -1
var _fear_drawing := false
const CONTENT_SYNC_INTERVAL_S := 0.05


func _enter_tree() -> void:
	# 相机/导演/三维合成完成后再取同帧画布；位置同步不再受树内先后顺序影响。
	process_priority = 1100
	process_mode = Node.PROCESS_MODE_ALWAYS
	AircraftRenderer.install_status_overlay(self)


func _exit_tree() -> void:
	AircraftRenderer.uninstall_status_overlay(self)


func _process(_delta: float) -> void:
	var perf_t0 := Time.get_ticks_usec()
	_sync_tactical_canvases()
	var fear_drawing := false
	for controller in SquadFearConeController.live_controllers():
		if controller.emitter() != null:
			fear_drawing = true
			break
	if fear_drawing or _fear_drawing:
		queue_redraw()
	_fear_drawing = fear_drawing
	var now := Time.get_ticks_msec()
	if now >= _next_sync_ms or _source_revision != AircraftRenderer.status_subject_revision():
		_next_sync_ms = now + roundi(CONTENT_SYNC_INTERVAL_S * 1000.0)
		_source_revision = AircraftRenderer.status_subject_revision()
		_sync_registered_panels()
	for raw_panel: Variant in _panels.values():
		if typeof(raw_panel) == TYPE_OBJECT and is_instance_valid(raw_panel):
			(raw_panel as StatusPanel).update_screen_position()
	PerfBuckets.tick("unit_status_overlay", Time.get_ticks_usec() - perf_t0)


func _sync_registered_panels() -> void:
	var live_ids: Dictionary = {}
	var now := Time.get_ticks_msec()
	for raw_id: Variant in AircraftRenderer.status_subject_ids():
		var entry_id := int(raw_id)
		var item := AircraftRenderer.status_subject(entry_id)
		if item == null or not item.is_inside_tree() or item.is_queued_for_deletion():
			AircraftRenderer.forget_status_subject(entry_id)
			continue
		var display_mode := Snapshot.mode(item)
		if display_mode.is_empty():
			AircraftRenderer.publish_status_snapshot(entry_id, {})
			continue
		live_ids[entry_id] = true
		var panel: StatusPanel = _panels.get(entry_id)
		var first := panel == null
		if first:
			panel = StatusPanel.new()
			panel.name = "StatusPanel_%d" % entry_id
			_panels[entry_id] = panel
			add_child(panel)
		var key := Snapshot.event_key(item, display_mode)
		# 普通信息2Hz，结构/切控/密度档变化立即刷新；首次采样后错峰，不形成整批文字尖峰。
		if first or now >= panel.next_content_ms or key != panel.content_key:
			var entry := Snapshot.build(item, display_mode)
			AircraftRenderer.publish_status_snapshot(entry_id, entry)
			panel.content_key = key
			panel.next_content_ms = now + (50 * (1 + entry_id % 10) if first else 500)
		panel.sync(AircraftRenderer.status_panel_entry(entry_id), item)
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
		_fear_visual.draw(self, world_to_screen * Transform2D(ac_heading, ac_origin), cfg,
			controller.phase == SquadFearConeController.Phase.EMISSION, controller.remaining)
		for id: Variant in controller.exposure:
			var target := FearResponse.aircraft(instance_from_id(int(id)))
			if target == null or not target.is_inside_tree():
				continue
			var screen := DisplayPacing.display_screen_origin(target) + Vector2(-20.0, -35.0)
			draw_rect(Rect2(screen, Vector2(40, 5)), Color(0, 0, 0, 0.9))
			draw_rect(Rect2(screen, Vector2(40.0 * float(controller.exposure[id]) / cfg.exposure_s, 5)), cfg.color)
	if started > 0:
		PerfBuckets.finish_extended_cpu("status_mask_draw", started, shared)


func has_tactical_canvas(ac: Node2D) -> bool:
	return _tactical_panels.has(ac.get_instance_id())


## 单次 O(N) 同步；机体缓存不随渲染帧率重画，只重画当前活跃的跨对象标记。
func _sync_tactical_canvases() -> void:
	for source_list: Array in [CombatUnit.all_units, Missile.active_missiles]:
		for value: Variant in source_list:
			var ac := TacticalCanvas.visible_subject(value)
			if ac == null or ac.get_viewport() != get_viewport() or not TacticalCanvas.needs_subject(ac):
				continue
			var id := ac.get_instance_id()
			if not _tactical_panels.has(id):
				var panel := TacticalCanvas.new()
				panel.bind(ac)
				_tactical_panels[id] = panel
				add_child(panel)
				move_child(panel, 0)
				ac.queue_redraw() # 清掉机体缓存里的旧标记，只在所有权交接时触发。
	for id: int in _tactical_panels.keys():
		var panel: Node2D = _tactical_panels[id]
		if not panel.present():
			var ac := TacticalCanvas.visible_subject(panel.subject.get_ref())
			_tactical_panels.erase(id)
			panel.queue_free()
			if ac != null:
				ac.queue_redraw()
