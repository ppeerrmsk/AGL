class_name WarzoneTimePanel
extends Control

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")
const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")
const DISPLAY_FONT_SOURCE := preload("res://resources/fonts/ChakraPetch-Bold.ttf")

const U_HEIGHT := 18.0
const DIGIT_WIDTH := 40.0
const SEPARATOR_WIDTH := 18.0
const DIGIT_HEIGHT := U_HEIGHT * 2.0
const PANEL_SIZE := Vector2(DIGIT_WIDTH * 4.0 + SEPARATOR_WIDTH,
	DIGIT_HEIGHT + U_HEIGHT)
const WARNING_YELLOW := Color("f2d34f")
const DANGER_RED := Color("ff493d")

var _seconds := 0.0
var _boss_phase := false
var _display_font: Font
var _localized_font: Font
var _grid_overlay


func _init() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true


func _ready() -> void:
	_display_font = DISPLAY_FONT_SOURCE.duplicate() as Font
	_display_font.fallbacks.append(ThemeDB.fallback_font)
	_localized_font = get_theme_default_font()
	if _localized_font == null:
		_localized_font = ThemeDB.fallback_font
	_grid_overlay = TerminalGridOverlayScript.new()
	_grid_overlay.size = PANEL_SIZE
	_grid_overlay.regions = grid_regions()
	_grid_overlay.edge_insets = TerminalGridOverlayScript.CONTROL_EDGE_INSETS
	add_child(_grid_overlay)
	set_process(false)


func update_display(seconds: float, boss_phase: bool) -> void:
	_seconds = maxf(seconds, 0.0)
	_boss_phase = boss_phase
	queue_redraw()


func _draw() -> void:
	var accent: Color = HudPreferencesScript.hud_color()
	var value_color := timer_color(_seconds, _boss_phase, accent)
	for region in grid_regions():
		draw_rect(region, ThemeColors.UI_BLOCK_BACKGROUND, true)
	var time_text := "--:--" if _boss_phase else formatted_remaining_time(_seconds)
	for index in range(4):
		var source_index := index if index < 2 else index + 1
		_draw_text(time_text.substr(source_index, 1), digit_rect(index), value_color,
			"9", true)
	_draw_text(":", separator_rect(), value_color, ":", true)
	var label := tr("HUD_BOSS_PHASE") if _boss_phase else localized_remaining_label()
	_draw_text(label, label_rect(), accent, label, false)
	if _grid_overlay != null:
		_grid_overlay.line_color = accent


func _draw_text(text: String, rect: Rect2, color: Color, layout_text: String,
		use_display_font: bool) -> void:
	var font := _display_font if use_display_font else _localized_font
	if font == null or text.is_empty():
		return
	var fixed_size := 0 if use_display_font else 15
	var layout := TerminalTextScript.resolve_font_layout(
		font, layout_text, rect.size, fixed_size)
	var font_size := int(layout.x)
	var ink := TerminalTextScript.measure_ink_bounds(font, text, font_size)
	var ink_top := ink.x if TerminalTextScript.has_visible_ink(ink) else layout.y
	var ink_bottom := ink.y if TerminalTextScript.has_visible_ink(ink) else layout.z
	var baseline_y := rect.position.y \
		+ (rect.size.y - (ink_bottom - ink_top)) * 0.5 - ink_top
	draw_string(font, Vector2(rect.position.x, baseline_y), text,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)


func localized_remaining_label() -> String:
	return tr("HUD_WARZONE_TIMER_FMT").replace("%02d:%02d", "").strip_edges()


static func formatted_remaining_time(seconds: float) -> String:
	var total_seconds := floori(maxf(seconds, 0.0))
	var minutes := mini(total_seconds / 60, 99)
	return "%02d:%02d" % [minutes, total_seconds % 60]


static func timer_color(seconds: float, boss_phase: bool, accent: Color) -> Color:
	if boss_phase or seconds <= 60.0:
		return DANGER_RED
	if seconds <= 120.0:
		return WARNING_YELLOW
	return accent


static func digit_rect(index: int) -> Rect2:
	var x := float(index) * DIGIT_WIDTH
	if index >= 2:
		x += SEPARATOR_WIDTH
	return Rect2(x, 0.0, DIGIT_WIDTH, DIGIT_HEIGHT)


static func separator_rect() -> Rect2:
	return Rect2(DIGIT_WIDTH * 2.0, 0.0, SEPARATOR_WIDTH, DIGIT_HEIGHT)


static func label_rect() -> Rect2:
	return Rect2(0.0, DIGIT_HEIGHT, PANEL_SIZE.x, U_HEIGHT)


static func grid_regions() -> Array[Rect2]:
	return [
		digit_rect(0), digit_rect(1), separator_rect(),
		digit_rect(2), digit_rect(3), label_rect(),
	]
