class_name HudFirstRevealSequencer
extends RefCounted

## 玩家 HUD 框板的本局首次显现调度器。
## 可见框板按屏幕坐标从上到下、同一行从左到右快速错峰启动；
## 每块框板独立在 0.50 秒内完成两闪，后续框板无需等待前一块完成。

const BLINK_COUNT := 2
const BLINK_TOTAL_DURATION := 0.50
const BLINK_HALF_PERIOD := BLINK_TOTAL_DURATION / float(BLINK_COUNT * 2)
const PANEL_STAGGER := 0.02
const ROW_EPSILON := 1.0

var _entries: Array[Dictionary] = []
var _queue: Array[int] = []
var _active_indices: Array[int] = []
var _launch_elapsed := 0.0
var _start_history: Array[StringName] = []


func register_panel(id: StringName, controls: Array, sort_position: Vector2,
		available := true, visibility_controls: Array = [], inverted := false) -> void:
	if _find_entry(id) >= 0:
		push_warning("HUD reveal panel already registered: %s" % id)
		return
	var valid_controls: Array[Control] = []
	var base_modulates: Array[Color] = []
	for raw: Variant in controls:
		if raw is Control:
			var control := raw as Control
			valid_controls.append(control)
			base_modulates.append(control.modulate)
	if valid_controls.is_empty():
		push_warning("HUD reveal panel has no Control: %s" % id)
		return
	var valid_visibility_controls: Array[Control] = []
	for raw: Variant in visibility_controls:
		if raw is Control:
			valid_visibility_controls.append(raw as Control)
	_entries.append({
		"id": id,
		"controls": valid_controls,
		"visibility_controls": valid_visibility_controls,
		"base_modulates": base_modulates,
		"sort_position": sort_position,
		"available": available,
		"inverted": inverted,
		"queued": false,
		"completed": false,
		"start_count": 0,
		"elapsed": 0.0,
	})


func register_callback_panel(id: StringName, alpha_setter: Callable,
		visibility_getter: Callable, sort_position: Vector2, available := true) -> void:
	if _find_entry(id) >= 0:
		push_warning("HUD reveal panel already registered: %s" % id)
		return
	if not alpha_setter.is_valid() or not visibility_getter.is_valid():
		push_warning("HUD reveal callback panel has invalid callable: %s" % id)
		return
	_entries.append({
		"id": id,
		"controls": [],
		"visibility_controls": [],
		"base_modulates": [],
		"alpha_setter": alpha_setter,
		"visibility_getter": visibility_getter,
		"sort_position": sort_position,
		"available": available,
		"inverted": false,
		"queued": false,
		"completed": false,
		"start_count": 0,
		"elapsed": 0.0,
	})


func set_panel_available(id: StringName, available: bool) -> void:
	var index := _find_entry(id)
	if index < 0:
		return
	var entry := _entries[index]
	entry["available"] = available
	_entries[index] = entry
	if not available:
		_cancel_entry(index)


func set_panel_sort_position(id: StringName, sort_position: Vector2) -> void:
	var index := _find_entry(id)
	if index < 0:
		return
	var entry := _entries[index]
	entry["sort_position"] = sort_position
	_entries[index] = entry
	if bool(entry.get("queued", false)):
		_sort_queue()


func update(delta: float) -> void:
	_refresh_waiting_entries()
	_cancel_hidden_entries()
	_launch_queued_panels(maxf(delta, 0.0))
	_update_active_panels(maxf(delta, 0.0))


func active_panel_id() -> StringName:
	if _active_indices.is_empty():
		return &""
	return StringName(_entries[_active_indices[0]].get("id", &""))


func active_panel_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for index in _active_indices:
		if index >= 0 and index < _entries.size():
			result.append(StringName(_entries[index].get("id", &"")))
	return result


func queued_panel_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for index in _queue:
		if index >= 0 and index < _entries.size():
			result.append(StringName(_entries[index].get("id", &"")))
	return result


func start_history() -> Array[StringName]:
	return _start_history.duplicate()


func panel_completed(id: StringName) -> bool:
	var index := _find_entry(id)
	return index >= 0 and bool(_entries[index].get("completed", false))


func panel_start_count(id: StringName) -> int:
	var index := _find_entry(id)
	return int(_entries[index].get("start_count", 0)) if index >= 0 else 0


func _refresh_waiting_entries() -> void:
	var queue_changed := false
	for index in range(_entries.size()):
		var entry := _entries[index]
		if bool(entry.get("completed", false)) or bool(entry.get("queued", false)) \
				or _active_indices.has(index) or not bool(entry.get("available", true)):
			continue
		if not _entry_is_visible(index):
			continue
		entry["queued"] = true
		_entries[index] = entry
		_set_entry_reveal_alpha(index, 0.0)
		_queue.append(index)
		queue_changed = true
	if queue_changed:
		_sort_queue()


func _sort_queue() -> void:
	_queue.sort_custom(func(a: int, b: int) -> bool:
		var a_position: Vector2 = _entries[a].get("sort_position", Vector2.ZERO)
		var b_position: Vector2 = _entries[b].get("sort_position", Vector2.ZERO)
		if absf(a_position.y - b_position.y) > ROW_EPSILON:
			return a_position.y < b_position.y
		if not is_equal_approx(a_position.x, b_position.x):
			return a_position.x < b_position.x
		return a < b)


func _cancel_hidden_entries() -> void:
	for queue_index in range(_queue.size() - 1, -1, -1):
		var entry_index := _queue[queue_index]
		if _entry_is_visible(entry_index):
			continue
		_queue.remove_at(queue_index)
		var entry := _entries[entry_index]
		entry["queued"] = false
		_entries[entry_index] = entry
		_restore_entry(entry_index)
	for active_index in _active_indices.duplicate():
		if not _entry_is_visible(active_index):
			_cancel_entry(active_index)


func _launch_queued_panels(delta: float) -> void:
	if _queue.is_empty():
		_launch_elapsed = 0.0
		return
	if _active_indices.is_empty() and _launch_elapsed <= 0.0:
		_start_next()
		_launch_elapsed = PANEL_STAGGER
	_launch_elapsed -= delta
	while _launch_elapsed <= 0.0 and not _queue.is_empty():
		_start_next()
		_launch_elapsed += PANEL_STAGGER


func _start_next() -> void:
	while not _queue.is_empty():
		var index: int = int(_queue.pop_front())
		var entry := _entries[index]
		entry["queued"] = false
		_entries[index] = entry
		if not _entry_is_visible(index):
			_restore_entry(index)
			continue
		entry = _entries[index]
		entry["elapsed"] = 0.0
		entry["start_count"] = int(entry.get("start_count", 0)) + 1
		_entries[index] = entry
		_active_indices.append(index)
		_start_history.append(StringName(entry.get("id", &"")))
		_set_entry_reveal_alpha(index, 1.0)
		return


func _update_active_panels(delta: float) -> void:
	for index in _active_indices.duplicate():
		if not _active_indices.has(index):
			continue
		var entry := _entries[index]
		var elapsed := float(entry.get("elapsed", 0.0)) + delta
		entry["elapsed"] = elapsed
		_entries[index] = entry
		if elapsed + 0.000001 >= BLINK_TOTAL_DURATION:
			_finish_entry(index)
			continue
		var phase := floori(elapsed / BLINK_HALF_PERIOD)
		_set_entry_reveal_alpha(index, 1.0 if phase % 2 == 0 else 0.0)


func _finish_entry(index: int) -> void:
	_restore_entry(index)
	var entry := _entries[index]
	entry["completed"] = true
	entry["elapsed"] = 0.0
	_entries[index] = entry
	_active_indices.erase(index)


func _cancel_entry(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	for queue_index in range(_queue.size() - 1, -1, -1):
		if _queue[queue_index] == index:
			_queue.remove_at(queue_index)
	_active_indices.erase(index)
	var entry := _entries[index]
	entry["queued"] = false
	entry["elapsed"] = 0.0
	_entries[index] = entry
	_restore_entry(index)


func _entry_is_visible(index: int) -> bool:
	if index < 0 or index >= _entries.size():
		return false
	var entry := _entries[index]
	if not bool(entry.get("available", true)):
		return false
	var visibility_getter: Callable = entry.get("visibility_getter", Callable())
	if visibility_getter.is_valid():
		return bool(visibility_getter.call())
	var controls: Array = entry.get("visibility_controls", [])
	if controls.is_empty():
		controls = entry.get("controls", [])
	for raw: Variant in controls:
		if not is_instance_valid(raw) or not (raw is Control):
			continue
		var control := raw as Control
		if control.is_inside_tree():
			if control.is_visible_in_tree():
				return true
		elif control.visible:
			return true
	return false


func _set_entry_reveal_alpha(index: int, reveal_alpha: float) -> void:
	if index < 0 or index >= _entries.size():
		return
	var entry := _entries[index]
	var alpha_setter: Callable = entry.get("alpha_setter", Callable())
	if alpha_setter.is_valid():
		alpha_setter.call(clampf(reveal_alpha, 0.0, 1.0))
		return
	var controls: Array = entry.get("controls", [])
	var bases: Array = entry.get("base_modulates", [])
	var alpha := clampf(reveal_alpha, 0.0, 1.0)
	if bool(entry.get("inverted", false)):
		alpha = 1.0 - alpha
	for control_index in range(mini(controls.size(), bases.size())):
		var raw: Variant = controls[control_index]
		if not is_instance_valid(raw) or not (raw is Control):
			continue
		var control := raw as Control
		var base: Color = bases[control_index]
		control.modulate = Color(base.r, base.g, base.b, base.a * alpha)


func _restore_entry(index: int) -> void:
	_set_entry_reveal_alpha(index, 1.0)


func _find_entry(id: StringName) -> int:
	for index in range(_entries.size()):
		if _entries[index].get("id", &"") == id:
			return index
	return -1
