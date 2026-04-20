extends CanvasLayer
class_name AudioSettingsPanel

## 音频设置面板（纯程序化 UI，不依赖 .tscn）
##
## 用法：
##   var panel = preload("res://scripts/audio/audio_settings_panel.gd").new()
##   add_child(panel)
##   panel.open()
##   panel.closed.connect(...)  # 可选

signal closed

const BUSES := ["Master", "Music", "SFX", "UI"]
const BUS_LABEL_KEYS := {
	"Master": "AUDIO_BUS_MASTER",
	"Music": "AUDIO_BUS_MUSIC",
	"SFX": "AUDIO_BUS_SFX",
	"UI": "AUDIO_BUS_UI",
}

const PANEL_BG := Color(0.05, 0.08, 0.05, 0.94)
const OVERLAY_BG := Color(0, 0, 0, 0.55)
const BORDER_COLOR := Color(0.4, 0.8, 0.4, 0.6)
const TEXT_COLOR := Color(0.7, 1.0, 0.7)
const VALUE_COLOR := Color(0.5, 0.9, 0.5)
const SECONDARY_COLOR := Color(0.5, 0.7, 0.5, 0.85)

var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _mute_buttons: Dictionary = {}

func _ready() -> void:
	layer = 100
	# 战术面板/升级界面打开时也可以用（树被暂停时仍响应输入）
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false

func open() -> void:
	_refresh_from_bus()
	visible = true

func close_panel() -> void:
	visible = false
	closed.emit()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_panel()

# ═══════════════════════════════════════════════════
#  UI 构建
# ═══════════════════════════════════════════════════

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = OVERLAY_BG
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(520, 0)
	# 居中
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.position = -root.custom_minimum_size * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = BORDER_COLOR
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(22)
	root.add_theme_stylebox_override("panel", sb)
	add_child(root)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	root.add_child(vb)

	# 标题行
	var title_row := HBoxContainer.new()
	vb.add_child(title_row)
	var title := Label.new()
	title.text = tr("AUDIO_SETTINGS_TITLE")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(close_panel)
	title_row.add_child(close_btn)

	vb.add_child(HSeparator.new())

	# 每条 Bus 一行
	for bus in BUSES:
		vb.add_child(_build_slider_row(bus))

	vb.add_child(HSeparator.new())

	# 底部按钮
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)
	vb.add_child(btn_row)

	var reset_btn := Button.new()
	reset_btn.text = tr("AUDIO_SETTINGS_RESET")
	reset_btn.custom_minimum_size = Vector2(100, 32)
	reset_btn.pressed.connect(_on_reset)
	btn_row.add_child(reset_btn)

	var save_btn := Button.new()
	save_btn.text = tr("AUDIO_SETTINGS_SAVE")
	save_btn.custom_minimum_size = Vector2(100, 32)
	save_btn.pressed.connect(_on_save)
	btn_row.add_child(save_btn)

func _build_slider_row(bus: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = tr(BUS_LABEL_KEYS[bus])
	label.custom_minimum_size = Vector2(80, 0)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(260, 0)
	slider.value_changed.connect(func(v: float): _on_slider_changed(bus, v))
	row.add_child(slider)
	_sliders[bus] = slider

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_color_override("font_color", VALUE_COLOR)
	row.add_child(val_lbl)
	_value_labels[bus] = val_lbl

	var mute_btn := CheckButton.new()
	mute_btn.text = tr("AUDIO_SETTINGS_MUTE")
	mute_btn.add_theme_color_override("font_color", SECONDARY_COLOR)
	mute_btn.toggled.connect(func(p: bool): AudioManager.set_bus_mute(bus, p))
	row.add_child(mute_btn)
	_mute_buttons[bus] = mute_btn

	return row

# ═══════════════════════════════════════════════════
#  事件
# ═══════════════════════════════════════════════════

func _refresh_from_bus() -> void:
	for bus in BUSES:
		var v := AudioManager.get_bus_volume_linear(bus)
		(_sliders[bus] as HSlider).set_value_no_signal(v)
		(_value_labels[bus] as Label).text = "%d%%" % int(round(v * 100.0))
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			(_mute_buttons[bus] as CheckButton).set_pressed_no_signal(AudioServer.is_bus_mute(idx))

func _on_slider_changed(bus: String, v: float) -> void:
	AudioManager.set_bus_volume_linear(bus, v)
	(_value_labels[bus] as Label).text = "%d%%" % int(round(v * 100.0))

func _on_reset() -> void:
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var default_db: float = 0.0
		if AudioManager.DEFAULT_BUS_DB.has(bus):
			default_db = AudioManager.DEFAULT_BUS_DB[bus]
		AudioServer.set_bus_volume_db(idx, default_db)
		AudioServer.set_bus_mute(idx, false)
	_refresh_from_bus()

func _on_save() -> void:
	AudioManager.save_settings()
	close_panel()
