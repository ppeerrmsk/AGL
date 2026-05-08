extends CanvasLayer

## 运行时参数调试器（autoload 注入，不被游戏代码引用）
## 注：不写 class_name —— autoload 已经提供 RuntimeTuner 全局名，二者冲突会报错。
##
## 用法：F10 切换显示。Hover 玩家飞机时滑条调 .tres 字段或 Aircraft 实例字段，
## 现场看效果。改的是运行时实例（params 是 .tres 但 Godot 默认不写盘 Resource），
## 所以这次会话改了什么、退出就消失。"Print Current Values" 把当前值导出到 EventLogger，
## 满意时手动复制回 .tres 文件。
##
## 隔离原则（plan §美术工作流轨道）：游戏运行时代码不引用本文件。
## 通过 project.godot autoload 注入；想关掉就把 autoload 条目删了，工具消失，游戏不受影响。
##
## 字段表 FIELDS 是手挑的"最常调的 12 项"，要加新字段直接编辑 FIELDS 常量。

## 字段 spec：
##   path:  "params:X" → ac.params.X；"self:X" → ac.X
##   label: 显示标签
##   min/max/step: 滑条范围
##   int_field: 可选，true 时显示为整数
const FIELDS: Array = [
	{"path": "params:max_g", "label": "Max G", "min": 1.0, "max": 15.0, "step": 0.1},
	{"path": "params:max_speed_kmh", "label": "Max Speed (km/h)", "min": 200.0, "max": 3500.0, "step": 10.0},
	{"path": "params:cruise_speed_kmh", "label": "Cruise Speed (km/h)", "min": 200.0, "max": 2500.0, "step": 10.0},
	{"path": "params:stall_speed_base", "label": "Stall Base (km/h)", "min": 100.0, "max": 600.0, "step": 5.0},
	{"path": "params:max_hp", "label": "Max HP", "min": 50.0, "max": 500.0, "step": 5.0, "int_field": true},
	{"path": "params:radar_range_m", "label": "Radar Range (m)", "min": 1000.0, "max": 30000.0, "step": 100.0},
	{"path": "params:radar_half_angle", "label": "Radar Half Angle (deg)", "min": 5.0, "max": 90.0, "step": 1.0},
	{"path": "params:lock_time", "label": "Lock Time (s)", "min": 0.5, "max": 8.0, "step": 0.1},
	{"path": "self:fear_on_lock_threshold", "label": "Gaze Press Threshold (s)", "min": 0.0, "max": 30.0, "step": 0.5},
	{"path": "self:jam_aura_radius_px", "label": "JAM Aura Radius (px)", "min": 0.0, "max": 3000.0, "step": 50.0},
	{"path": "self:rear_aura_slow_radius_px", "label": "Rear SLOW Aura (px)", "min": 0.0, "max": 3000.0, "step": 50.0},
	{"path": "self:bullet_dodge_chance", "label": "Bullet Dodge Chance", "min": 0.0, "max": 0.85, "step": 0.01},
]

const HOTKEY := KEY_F10
const PANEL_WIDTH := 380
const PANEL_HEIGHT := 540

var _target: Aircraft = null
var _spawn_values: Dictionary = {}    # path → 第一次 show 时的值（reset 用）
var _slider_refs: Dictionary = {}     # path → HSlider 节点
var _value_label_refs: Dictionary = {} # path → Label 节点
var _root: Panel = null
var _target_label: Label = null


func _ready() -> void:
	layer = 100   # 在游戏 UI 之上
	visible = false
	_build_ui()
	# 高 process priority 让 _input 在游戏前处理（避免被游戏吞）
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == HOTKEY:
			_toggle()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	visible = not visible
	if visible:
		_refresh_target()


func _process(_delta: float) -> void:
	# 实时同步显示值（其它系统改 params 时滑条也跟着）—— 仅可见时跑
	if not visible or _target == null or not is_instance_valid(_target):
		return
	for field in FIELDS:
		var path: String = field["path"]
		var v: float = float(_read_field(path))
		var slider: HSlider = _slider_refs.get(path)
		if slider and absf(slider.value - v) > 0.001:
			# 只在外部值变了才更新滑条（避免拖动时反复跳）
			slider.set_block_signals(true)
			slider.value = v
			slider.set_block_signals(false)
		_update_value_label(path, v, field.get("int_field", false))


func _refresh_target() -> void:
	# safe_player_ref 是静态方法，自动清理 freed 引用
	_target = AircraftRenderer.safe_player_ref()
	if _target == null or not is_instance_valid(_target):
		_target_label.text = "Target: (none)"
		return
	_target_label.text = "Target: %s [%s]" % [_target.callsign, _target.params.display_name if _target.params else "?"]
	# 第一次见到这个 target 实例 → 快照所有字段（reset 用）
	var inst_id := _target.get_instance_id()
	if not _spawn_values.has(inst_id):
		var snap := {}
		for field in FIELDS:
			snap[field["path"]] = _read_field(field["path"])
		_spawn_values[inst_id] = snap
	# 同步滑条到当前值
	for field in FIELDS:
		var path: String = field["path"]
		var v: float = float(_read_field(path))
		var slider: HSlider = _slider_refs.get(path)
		if slider:
			slider.set_block_signals(true)
			slider.value = v
			slider.set_block_signals(false)
		_update_value_label(path, v, field.get("int_field", false))


func _build_ui() -> void:
	_root = Panel.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_root.position = Vector2(-PANEL_WIDTH - 16, 80)
	_root.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	_root.modulate = Color(1, 1, 1, 0.94)
	add_child(_root)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 4)
	vb.offset_left = 8
	vb.offset_top = 8
	vb.offset_right = -8
	vb.offset_bottom = -8
	_root.add_child(vb)

	# 标题
	var title := Label.new()
	title.text = "Runtime Tuner — F10 toggle"
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	vb.add_child(title)

	# Target 提示
	_target_label = Label.new()
	_target_label.text = "Target: (none)"
	_target_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vb.add_child(_target_label)

	# 分隔
	var sep1 := HSeparator.new()
	vb.add_child(sep1)

	# 字段表（包在 ScrollContainer 里防溢出）
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)

	var fields_vb := VBoxContainer.new()
	fields_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields_vb.add_theme_constant_override("separation", 2)
	scroll.add_child(fields_vb)

	for field in FIELDS:
		var path: String = field["path"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# label（含字段名 + 当前值）
		var name_lbl := Label.new()
		name_lbl.text = field["label"]
		name_lbl.custom_minimum_size.x = 150
		name_lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(name_lbl)

		var val_lbl := Label.new()
		val_lbl.custom_minimum_size.x = 50
		val_lbl.add_theme_font_size_override("font_size", 11)
		val_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.5))
		row.add_child(val_lbl)
		_value_label_refs[path] = val_lbl

		# slider
		var slider := HSlider.new()
		slider.min_value = field["min"]
		slider.max_value = field["max"]
		slider.step = field["step"]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.x = 100
		slider.value_changed.connect(_on_slider_changed.bind(path))
		row.add_child(slider)
		_slider_refs[path] = slider

		# reset
		var reset_btn := Button.new()
		reset_btn.text = "↺"
		reset_btn.custom_minimum_size = Vector2(24, 24)
		reset_btn.pressed.connect(_on_reset.bind(path))
		row.add_child(reset_btn)

		fields_vb.add_child(row)

	# 分隔
	var sep2 := HSeparator.new()
	vb.add_child(sep2)

	# 操作按钮行
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	vb.add_child(actions)

	var print_btn := Button.new()
	print_btn.text = "Print to EventLogger"
	print_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	print_btn.pressed.connect(_on_print)
	actions.add_child(print_btn)

	var reset_all_btn := Button.new()
	reset_all_btn.text = "Reset All"
	reset_all_btn.pressed.connect(_on_reset_all)
	actions.add_child(reset_all_btn)


func _on_slider_changed(value: float, path: String) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	_write_field(path, value)
	var int_field := false
	for f in FIELDS:
		if f["path"] == path:
			int_field = f.get("int_field", false)
			break
	_update_value_label(path, value, int_field)


func _on_reset(path: String) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var inst_id := _target.get_instance_id()
	if not _spawn_values.has(inst_id):
		return
	var snap: Dictionary = _spawn_values[inst_id]
	if not snap.has(path):
		return
	var v: float = float(snap[path])
	_write_field(path, v)
	var slider: HSlider = _slider_refs.get(path)
	if slider:
		slider.set_block_signals(true)
		slider.value = v
		slider.set_block_signals(false)


func _on_reset_all() -> void:
	for field in FIELDS:
		_on_reset(field["path"])


func _on_print() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var lines: Array[String] = []
	for field in FIELDS:
		var path: String = field["path"]
		var v = _read_field(path)
		var spawn_v = _spawn_values.get(_target.get_instance_id(), {}).get(path, v)
		var marker := "  *" if absf(float(v) - float(spawn_v)) > 0.001 else "   "
		lines.append("%s%s = %s (spawn: %s)" % [marker, path, str(v), str(spawn_v)])
	var msg := "Tuner snapshot for %s:\n%s" % [_target.callsign, "\n".join(lines)]
	EventLogger.log_event("TUNER", _target.callsign, msg)
	print(msg)


func _read_field(path: String):
	if _target == null or not is_instance_valid(_target):
		return 0.0
	var parts := path.split(":")
	if parts.size() != 2:
		return 0.0
	var owner_kind := parts[0]
	var field := parts[1]
	if owner_kind == "params":
		if _target.params == null:
			return 0.0
		return _target.params.get(field)
	elif owner_kind == "self":
		return _target.get(field)
	return 0.0


func _write_field(path: String, value: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var parts := path.split(":")
	if parts.size() != 2:
		return
	var owner_kind := parts[0]
	var field := parts[1]
	if owner_kind == "params":
		if _target.params == null:
			return
		_target.params.set(field, value)
	elif owner_kind == "self":
		_target.set(field, value)


func _update_value_label(path: String, value: float, is_int: bool) -> void:
	var lbl: Label = _value_label_refs.get(path)
	if lbl == null:
		return
	if is_int:
		lbl.text = "%d" % roundi(value)
	elif absf(value) < 1.0:
		lbl.text = "%.2f" % value
	elif absf(value) < 100.0:
		lbl.text = "%.1f" % value
	else:
		lbl.text = "%.0f" % value
