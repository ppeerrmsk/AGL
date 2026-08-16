class_name BottomExperiencePanel
extends Control

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const PlayerInstrumentPanelScript := preload("res://scripts/survivor/player_instrument_panel.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")
const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")
const INFO_FONT_SOURCE := preload("res://resources/fonts/Silkscreen-Regular.ttf")
const DISPLAY_FONT_SOURCE := preload("res://resources/fonts/ChakraPetch-Bold.ttf")

const U_HEIGHT := 18.0
const LEVEL_LABEL_WIDTH := 40.0
const LEVEL_DIGIT_WIDTH := PlayerInstrumentPanelScript.THREE_U_DIGIT_WIDTH
const LEVEL_DIGIT_COUNT := 2
const SIDE_WIDTH := LEVEL_LABEL_WIDTH + LEVEL_DIGIT_WIDTH * LEVEL_DIGIT_COUNT
const CENTER_WIDTH := 408.0
const TOTAL_SIZE := Vector2(SIDE_WIDTH * 2.0 + CENTER_WIDTH, U_HEIGHT * 3.0)
const FLASH_PANEL_DURATION := 0.14
const FLASH_PANEL_COUNT := 3
const FLASH_DURATION := FLASH_PANEL_DURATION * FLASH_PANEL_COUNT

var _level := 1
var _xp := 0
var _xp_to_next := 1
var _flash_elapsed := -1.0
var _accent := Color.TRANSPARENT
var _info_font: Font
var _display_font: Font
var _grid_overlay


func _init() -> void:
	custom_minimum_size = TOTAL_SIZE
	size = TOTAL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true


func _ready() -> void:
	_accent = HudPreferencesScript.hud_color()
	_info_font = INFO_FONT_SOURCE.duplicate() as Font
	_display_font = DISPLAY_FONT_SOURCE.duplicate() as Font
	if _info_font is FontFile:
		(_info_font as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_NONE
		(_info_font as FontFile).subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_info_font.fallbacks.append(ThemeDB.fallback_font)
	_display_font.fallbacks.append(ThemeDB.fallback_font)
	_grid_overlay = TerminalGridOverlayScript.new()
	_grid_overlay.size = TOTAL_SIZE
	_grid_overlay.regions = grid_regions()
	_grid_overlay.edge_insets = TerminalGridOverlayScript.CONTROL_EDGE_INSETS
	_grid_overlay.line_color = _accent
	add_child(_grid_overlay)
	set_process(false)


func update_display(player: SurvivorPlayer) -> void:
	if player == null:
		return
	var next_level := player.level
	var next_xp := player.xp
	var next_xp_to_next := maxi(player.xp_to_next, 1)
	var next_accent: Color = HudPreferencesScript.hud_color()
	if _level == next_level and _xp == next_xp and _xp_to_next == next_xp_to_next \
			and _accent.is_equal_approx(next_accent):
		return
	_level = next_level
	_xp = next_xp
	_xp_to_next = next_xp_to_next
	_accent = next_accent
	if _grid_overlay != null:
		_grid_overlay.line_color = _accent
	queue_redraw()


func flash_level_up() -> void:
	_flash_elapsed = 0.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_flash_elapsed += delta
	if _flash_elapsed >= FLASH_DURATION:
		_flash_elapsed = -1.0
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var accent: Color = _accent if _accent.a > 0.0 else HudPreferencesScript.hud_color()
	var flash_index := flash_index_at(_flash_elapsed)
	# Draw the adjacent experience regions first and the complete LV panel last.
	# This keeps both level glyphs authoritative even on a shared raster boundary.
	_draw_xp_bar(accent, flash_index == 1)
	_draw_right_panel(accent, flash_index == 2)
	_draw_left_panel(accent, flash_index == 0)
	if _grid_overlay != null:
		_grid_overlay.line_color = accent
		_grid_overlay.override_color = ThemeColors.UI_TERMINAL_INVERSE
		_grid_overlay.override_regions = flash_regions(flash_index)


func _draw_left_panel(accent: Color, inverted: bool) -> void:
	var background := accent if inverted else ThemeColors.UI_BLOCK_BACKGROUND
	var text_color := ThemeColors.UI_TERMINAL_INVERSE if inverted else accent
	draw_rect(left_panel_rect(), background, true)
	_draw_text("LV", level_label_rect(), text_color, "LV", true, 0)
	var digits := formatted_level_digits(_level)
	for index in range(LEVEL_DIGIT_COUNT):
		var digit_color := level_digit_color(digits, index, accent, inverted)
		_draw_text(digits.substr(index, 1), level_digit_rect(index), digit_color,
			"0", true, 0)


func _draw_xp_bar(accent: Color, inverted: bool) -> void:
	var rect := xp_rect()
	var background := accent if inverted else ThemeColors.UI_BLOCK_BACKGROUND
	draw_rect(rect, background, true)
	if inverted:
		return
	var ratio := clampf(float(_xp) / float(maxi(_xp_to_next, 1)), 0.0, 1.0)
	var inner := rect.grow(-1.0)
	inner.size.x *= ratio
	if inner.size.x > 0.0:
		draw_rect(inner, accent, true)


func _draw_right_panel(accent: Color, inverted: bool) -> void:
	var background := accent if inverted else ThemeColors.UI_BLOCK_BACKGROUND
	var text_color := ThemeColors.UI_TERMINAL_INVERSE if inverted else accent
	draw_rect(right_panel_rect(), background, true)
	_draw_text(str(_xp), current_xp_rect(), text_color, "9999", true, 0)
	_draw_text("MAX %d" % _xp_to_next, max_xp_rect(), text_color,
		"MAX 9999", false, 15)


func _draw_text(text: String, rect: Rect2, color: Color, layout_text: String,
		use_display_font: bool, fixed_size: int) -> void:
	var font := _display_font if use_display_font else _info_font
	if font == null or text.is_empty():
		return
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


static func flash_index_at(elapsed: float) -> int:
	if elapsed < 0.0 or elapsed >= FLASH_DURATION:
		return -1
	return clampi(floori(elapsed / FLASH_PANEL_DURATION), 0, FLASH_PANEL_COUNT - 1)


static func formatted_level_digits(level: int) -> String:
	return "%02d" % clampi(level, 0, 99)


static func level_digit_is_padding(digits: String, index: int) -> bool:
	var first_significant := -1
	for digit_index in range(digits.length()):
		if digits.substr(digit_index, 1) != "0":
			first_significant = digit_index
			break
	if first_significant < 0:
		first_significant = digits.length() - 1
	return index < first_significant


static func level_digit_color(digits: String, index: int, accent: Color,
		inverted: bool) -> Color:
	if inverted:
		return ThemeColors.UI_TERMINAL_INVERSE
	return ThemeColors.UI_INACTIVE_DIGIT if level_digit_is_padding(digits, index) \
		else accent


static func left_panel_rect() -> Rect2:
	return Rect2(0.0, 0.0, SIDE_WIDTH, TOTAL_SIZE.y)


static func center_rect() -> Rect2:
	return Rect2(SIDE_WIDTH, 0.0, CENTER_WIDTH, TOTAL_SIZE.y)


static func right_panel_rect() -> Rect2:
	return Rect2(SIDE_WIDTH + CENTER_WIDTH, 0.0, SIDE_WIDTH, TOTAL_SIZE.y)


static func level_blank_rect() -> Rect2:
	return Rect2(0.0, 0.0, LEVEL_LABEL_WIDTH, U_HEIGHT)


static func level_label_rect() -> Rect2:
	return Rect2(0.0, U_HEIGHT, LEVEL_LABEL_WIDTH, U_HEIGHT * 2.0)


static func level_digit_rect(index: int) -> Rect2:
	return Rect2(LEVEL_LABEL_WIDTH + float(index) * LEVEL_DIGIT_WIDTH,
		0.0, LEVEL_DIGIT_WIDTH, TOTAL_SIZE.y)


static func xp_rect() -> Rect2:
	return Rect2(SIDE_WIDTH, U_HEIGHT * 2.0, CENTER_WIDTH, U_HEIGHT)


static func current_xp_rect() -> Rect2:
	return Rect2(SIDE_WIDTH + CENTER_WIDTH, 0.0, SIDE_WIDTH, U_HEIGHT * 2.0)


static func max_xp_rect() -> Rect2:
	return Rect2(SIDE_WIDTH + CENTER_WIDTH, U_HEIGHT * 2.0,
		SIDE_WIDTH, U_HEIGHT)


static func grid_regions() -> Array[Rect2]:
	return [
		level_blank_rect(), level_label_rect(),
		level_digit_rect(0), level_digit_rect(1),
		xp_rect(), current_xp_rect(), max_xp_rect(),
	]


static func flash_regions(index: int) -> Array[Rect2]:
	match index:
		0:
			return [level_blank_rect(), level_label_rect(),
				level_digit_rect(0), level_digit_rect(1)]
		1:
			return [xp_rect()]
		2:
			return [current_xp_rect(), max_xp_rect()]
		_:
			return []
