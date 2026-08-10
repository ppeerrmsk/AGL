class_name HudColorSettingsPanel
extends CanvasLayer

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")

## 主菜单 HUD 色盘：四个预设 + 自定义色，保存到 HudPreferences。

signal closed

var _picker: ColorPicker


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func open() -> void:
	_picker.color = HudPreferencesScript.hud_color()
	visible = true


func close_panel() -> void:
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_panel()


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.58)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(520, 0)
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.position = Vector2(-260, -250)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.03, 0.05, 0.03, 0.97)
	frame.border_color = HudPreferencesScript.hud_color()
	frame.set_border_width_all(2)
	frame.set_content_margin_all(20)
	root.add_theme_stylebox_override("panel", frame)
	add_child(root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	root.add_child(column)

	var title := Label.new()
	title.text = tr("HUD_COLOR_SETTINGS_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", HudPreferencesScript.hud_color())
	column.add_child(title)

	var presets := HBoxContainer.new()
	presets.alignment = BoxContainer.ALIGNMENT_CENTER
	presets.add_theme_constant_override("separation", 8)
	column.add_child(presets)
	_add_preset(presets, tr("HUD_COLOR_PRESET_GREEN"), HudPreferencesScript.PRESET_GREEN)
	_add_preset(presets, tr("HUD_COLOR_PRESET_CYAN"), HudPreferencesScript.PRESET_CYAN)
	_add_preset(presets, tr("HUD_COLOR_PRESET_AMBER"), HudPreferencesScript.PRESET_AMBER)
	_add_preset(presets, tr("HUD_COLOR_PRESET_WHITE"), HudPreferencesScript.PRESET_WHITE)

	_picker = ColorPicker.new()
	_picker.edit_alpha = false
	_picker.color = HudPreferencesScript.hud_color()
	_picker.custom_minimum_size = Vector2(480, 330)
	column.add_child(_picker)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var cancel := Button.new()
	cancel.text = tr("HUD_COLOR_CANCEL")
	cancel.pressed.connect(close_panel)
	actions.add_child(cancel)
	var save := Button.new()
	save.text = tr("HUD_COLOR_SAVE")
	save.pressed.connect(_on_save)
	actions.add_child(save)


func _add_preset(parent: HBoxContainer, label_text: String, color: Color) -> void:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(106, 34)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(color, 0.2)
	normal.border_color = color
	normal.set_border_width_all(2)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_color_override("font_color", color)
	btn.pressed.connect(func(): _picker.color = color)
	parent.add_child(btn)


func _on_save() -> void:
	HudPreferencesScript.set_hud_color(_picker.color)
	close_panel()
