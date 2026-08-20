class_name HudColorSettingsPanel
extends CanvasLayer

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const TerminalUiStyleScript := preload("res://scripts/ui/terminal_ui_style.gd")

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
	root.name = "TerminalHudColorSettings"
	root.custom_minimum_size = Vector2(520, 0)
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.position = Vector2(-260, -250)
	TerminalUiStyleScript.apply_panel(root, HudPreferencesScript.hud_color(),
		Color(0.0, 0.0, 0.0, 0.97), 18.0, 1)
	add_child(root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	root.add_child(column)

	var title := Label.new()
	title.text = tr("HUD_COLOR_SETTINGS_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	TerminalUiStyleScript.apply_label(
		title, 24, HudPreferencesScript.hud_color(), true)
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
	TerminalUiStyleScript.apply_button(cancel, HudPreferencesScript.hud_color())
	cancel.pressed.connect(close_panel)
	actions.add_child(cancel)
	var save := Button.new()
	save.text = tr("HUD_COLOR_SAVE")
	TerminalUiStyleScript.apply_button(save, HudPreferencesScript.hud_color(), false, true)
	save.pressed.connect(_on_save)
	actions.add_child(save)


func _add_preset(parent: HBoxContainer, label_text: String, color: Color) -> void:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(106, 34)
	TerminalUiStyleScript.apply_button(btn, color)
	btn.pressed.connect(func(): _picker.color = color)
	parent.add_child(btn)


func _on_save() -> void:
	HudPreferencesScript.set_hud_color(_picker.color)
	close_panel()
