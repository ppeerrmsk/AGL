class_name MilestoneAxisCounter
extends Control

const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")
const INFO_FONT_SOURCE := preload("res://resources/fonts/Silkscreen-Regular.ttf")

const U_HEIGHT := 18.0
const COUNTER_SIZE := Vector2(408.0, U_HEIGHT * 2.0)
const AXIS_WIDTH := 136.0
const NAME_WIDTH := 64.0
const POINT_CELL_WIDTH := 9.0
const POINT_CELL_COUNT := 8
const FONT_SIZE := 15

var _values: Array[int] = [0, 0, 0]
var _info_font: Font
var _localized_font: Font
var _redraw_revision := 0
var _accent := Color.TRANSPARENT
var _grid_overlay


func _init() -> void:
	custom_minimum_size = COUNTER_SIZE
	size = COUNTER_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	_accent = HudPreferencesScript.hud_color()
	_info_font = INFO_FONT_SOURCE.duplicate() as Font
	if _info_font is FontFile:
		(_info_font as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_NONE
		(_info_font as FontFile).subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_info_font.fallbacks.append(ThemeDB.fallback_font)
	_localized_font = get_theme_default_font()
	if _localized_font == null:
		_localized_font = ThemeDB.fallback_font
	_grid_overlay = TerminalGridOverlayScript.new()
	_grid_overlay.size = COUNTER_SIZE
	_grid_overlay.regions = grid_regions()
	_grid_overlay.line_color = _accent
	add_child(_grid_overlay)
	set_process(false)


func update_display(player: SurvivorPlayer) -> void:
	var next_values := snapshot_for(player)
	var next_accent: Color = HudPreferencesScript.hud_color()
	if next_values == _values and _accent.is_equal_approx(next_accent):
		return
	_values = next_values
	_accent = next_accent
	if _grid_overlay != null:
		_grid_overlay.line_color = _accent
	_redraw_revision += 1
	queue_redraw()


func _draw() -> void:
	var accent: Color = _accent if _accent.a > 0.0 else HudPreferencesScript.hud_color()
	for axis_index in range(SurvivorData.AXES.size()):
		var axis: StringName = SurvivorData.AXES[axis_index]
		var axis_color: Color = SurvivorData.AXIS_COLORS[axis]
		draw_rect(name_rect(axis_index), axis_color, true)
		for point_index in range(POINT_CELL_COUNT):
			var lit := point_index < clampi(_values[axis_index], 0, POINT_CELL_COUNT)
			draw_rect(point_rect(axis_index, point_index),
				axis_color if lit else ThemeColors.UI_BLOCK_BACKGROUND, true)
		_draw_axis_name(axis, axis_index, ThemeColors.UI_TERMINAL_INVERSE)
		_draw_axis_value(axis_index, ThemeColors.UI_TERMINAL_INVERSE)
	if _grid_overlay != null:
		_grid_overlay.line_color = accent


func _draw_axis_name(axis: StringName, index: int, color: Color) -> void:
	var text := axis_label(axis)
	var rect := axis_title_rect(index)
	var font := _localized_font if uses_theme_font_for_locale(
		TranslationServer.get_locale()) else _info_font
	_draw_axis_text(text, rect, font, color)


func _draw_axis_value(index: int, color: Color) -> void:
	var value := clampi(_values[index], 0, POINT_CELL_COUNT)
	_draw_axis_text("%d/%d" % [value, POINT_CELL_COUNT], axis_value_rect(index),
		_info_font, color)


func _draw_axis_text(text: String, rect: Rect2, font: Font, color: Color) -> void:
	var font_size := FONT_SIZE
	var height := font.get_height(font_size)
	var baseline_y := rect.position.y + (rect.size.y - height) * 0.5 \
		+ font.get_ascent(font_size)
	draw_string(font, Vector2(rect.position.x, baseline_y), text,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)


func axis_label(axis: StringName) -> String:
	if TranslationServer.get_locale().to_lower().begins_with("en"):
		return english_axis_label(axis)
	return tr(str(SurvivorData.AXIS_I18N_KEY[axis]))


static func english_axis_label(axis: StringName) -> String:
	match axis:
		SurvivorData.AXIS_GLADIATOR:
			return "GLAD."
		SurvivorData.AXIS_KNIGHT:
			return "KNIGHT"
		SurvivorData.AXIS_SCHEMER:
			return "SCHEM."
		_:
			return ""


static func uses_theme_font_for_locale(locale: String) -> bool:
	var normalized := locale.to_lower()
	return normalized.begins_with("zh") or normalized.begins_with("ja") \
		or normalized.begins_with("ko")


static func cell_rect(index: int) -> Rect2:
	return Rect2(float(index) * AXIS_WIDTH, 0.0, AXIS_WIDTH, COUNTER_SIZE.y)


static func name_rect(index: int) -> Rect2:
	return Rect2(float(index) * AXIS_WIDTH, 0.0, NAME_WIDTH, COUNTER_SIZE.y)


static func axis_title_rect(index: int) -> Rect2:
	return Rect2(float(index) * AXIS_WIDTH, 0.0, NAME_WIDTH, U_HEIGHT)


static func axis_value_rect(index: int) -> Rect2:
	return Rect2(float(index) * AXIS_WIDTH, U_HEIGHT, NAME_WIDTH, U_HEIGHT)


static func point_rect(axis_index: int, point_index: int) -> Rect2:
	return Rect2(float(axis_index) * AXIS_WIDTH + NAME_WIDTH
		+ float(point_index) * POINT_CELL_WIDTH,
		0.0, POINT_CELL_WIDTH, COUNTER_SIZE.y)


static func grid_regions() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for axis_index in range(SurvivorData.AXES.size()):
		result.append(axis_title_rect(axis_index))
		result.append(axis_value_rect(axis_index))
		for point_index in range(POINT_CELL_COUNT):
			result.append(point_rect(axis_index, point_index))
	return result


static func snapshot_for(player: SurvivorPlayer) -> Array[int]:
	var result: Array[int] = []
	for axis in SurvivorData.AXES:
		result.append(player.get_axis_points(axis) if player != null else 0)
	return result
