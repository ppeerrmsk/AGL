class_name TerminalUiStyle
extends RefCounted

## 规范后局外页面与小型弹层的共享终端样式。
## 业务页面只声明内容与尺寸，不再各自复制绿色圆角皮肤。

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")

const PAGE_BG := Color(0.0, 0.0, 0.0, 0.82)
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.70)
const DIM_TEXT := Color("727872")
const LOCKED_TEXT := Color("4a4f4a")
const DANGER := Color("ff493d")
const WARNING := Color("f2d34f")
const INVERSE := Color("000000")


static func accent() -> Color:
	return HudPreferencesScript.hud_color()


static func panel_style(color: Color = Color.WHITE, background: Color = PANEL_BG,
		margin: float = 10.0, border_width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = color
	style.set_border_width_all(border_width)
	style.set_content_margin_all(margin)
	return style


static func apply_panel(panel: PanelContainer, color: Color = Color.WHITE,
		background: Color = PANEL_BG, margin: float = 10.0,
		border_width: int = 1) -> void:
	panel.add_theme_stylebox_override(
		"panel", panel_style(color, background, margin, border_width))


static func apply_label(label: Label, font_size: int = 13,
		color: Color = Color.WHITE, bold: bool = false) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override(
		"font", TerminalTextScript.CHAKRA_PETCH_BOLD if bold \
		else TerminalTextScript.CHAKRA_PETCH_MEDIUM)


static func apply_terminal_label(label: Label, font_size: int = 15,
		color: Color = Color.WHITE) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", TerminalTextScript.SILKSCREEN_FONT_SOURCE)


static func apply_button(button: Button, color: Color = Color.WHITE,
		danger: bool = false, selected: bool = false) -> void:
	var active_color := DANGER if danger else color
	var normal_bg := active_color if selected else Color(0.0, 0.0, 0.0, 0.78)
	var normal := panel_style(active_color, normal_bg, 6.0, 1)
	var hover := panel_style(active_color, active_color, 6.0, 1)
	var pressed := panel_style(active_color, active_color.darkened(0.15), 6.0, 1)
	var disabled := panel_style(Color(active_color, 0.22),
		Color(0.0, 0.0, 0.0, 0.45), 6.0, 1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", INVERSE if selected else active_color)
	button.add_theme_color_override("font_hover_color", INVERSE)
	button.add_theme_color_override("font_focus_color", INVERSE)
	button.add_theme_color_override("font_pressed_color", INVERSE)
	button.add_theme_color_override("font_disabled_color", LOCKED_TEXT)
	button.add_theme_font_override("font", TerminalTextScript.SILKSCREEN_FONT_SOURCE)
	button.add_theme_font_size_override("font_size", 15)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func apply_tab_container(tabs: TabContainer, color: Color = Color.WHITE) -> void:
	var empty := StyleBoxEmpty.new()
	var panel := panel_style(color, PAGE_BG, 0.0, 1)
	var unselected := panel_style(color, Color(0.0, 0.0, 0.0, 0.78), 6.0, 1)
	var selected := panel_style(color, color, 6.0, 1)
	tabs.add_theme_stylebox_override("panel", panel)
	tabs.add_theme_stylebox_override("tabbar_background", empty)
	tabs.add_theme_stylebox_override("tab_unselected", unselected)
	tabs.add_theme_stylebox_override("tab_selected", selected)
	tabs.add_theme_stylebox_override("tab_hovered", selected)
	tabs.add_theme_color_override("font_unselected_color", color)
	tabs.add_theme_color_override("font_selected_color", INVERSE)
	tabs.add_theme_color_override("font_hovered_color", INVERSE)
	tabs.add_theme_font_override("font", TerminalTextScript.SILKSCREEN_FONT_SOURCE)
	tabs.add_theme_font_size_override("font_size", 15)


## 创建固定 23u × 30u 页框。返回 root/header/body/footer，供页面填充业务内容。
static func build_page(parent: Control, title_text: String, subtitle_text: String,
		page_code: String) -> Dictionary:
	var root := VBoxContainer.new()
	root.name = "TerminalPageLayout"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	parent.add_child(root)

	var header := PanelContainer.new()
	header.name = "TerminalPageHeader"
	header.custom_minimum_size = Vector2(0.0, 72.0)
	apply_panel(header, accent(), PAGE_BG, 8.0)
	root.add_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	header.add_child(header_row)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_box)
	var title := Label.new()
	title.name = "TerminalPageTitle"
	title.text = title_text
	apply_label(title, 29, accent(), true)
	title_box.add_child(title)
	var subtitle := Label.new()
	subtitle.name = "TerminalPageSubtitle"
	subtitle.text = subtitle_text
	apply_terminal_label(subtitle, 12, Color(accent(), 0.62))
	title_box.add_child(subtitle)
	var code := Label.new()
	code.name = "TerminalPageCode"
	code.text = page_code
	code.custom_minimum_size = Vector2(150.0, 0.0)
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	apply_terminal_label(code, 15, accent())
	header_row.add_child(code)

	var body := PanelContainer.new()
	body.name = "TerminalPageBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	apply_panel(body, accent(), PAGE_BG, 8.0)
	root.add_child(body)

	var footer := HBoxContainer.new()
	footer.name = "TerminalPageFooter"
	footer.custom_minimum_size = Vector2(0.0, 54.0)
	footer.add_theme_constant_override("separation", 0)
	root.add_child(footer)

	return {"root": root, "header": header, "body": body, "footer": footer}


static func build_footer_hint(footer: HBoxContainer, text: String) -> Label:
	var hint_panel := PanelContainer.new()
	hint_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_panel(hint_panel, accent(), PAGE_BG, 8.0)
	footer.add_child(hint_panel)
	var hint := Label.new()
	hint.text = text
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	apply_terminal_label(hint, 12, Color(accent(), 0.62))
	hint_panel.add_child(hint)
	return hint


static func build_footer_button(footer: HBoxContainer, text: String,
		callback: Callable, width: float = 200.0, danger: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 54.0)
	apply_button(button, accent(), danger)
	if callback.is_valid():
		button.pressed.connect(callback)
	footer.add_child(button)
	return button
