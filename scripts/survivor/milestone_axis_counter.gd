class_name MilestoneAxisCounter
extends Control

## 经验条上方的三轴里程碑摘要。固定占位、纯显示，只在读数变化时重绘。
const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")
const SILKSCREEN_FONT_SOURCE := preload("res://resources/fonts/Silkscreen-Regular.ttf")
const COUNTER_SIZE := Vector2(400.0, 18.0)
const CELL_WIDTHS: PackedFloat32Array = [120.0, 120.0, 160.0]
const CELL_WIDTH := 120.0
const FONT_SIZE := 15
const BACKGROUND_COLOR := ThemeColors.UI_BLOCK_BACKGROUND

var _values: Array[int] = [0, 0, 0]
var _localized_font: Font
var _redraw_revision: int = 0
var _grid_overlay


func _ready() -> void:
	custom_minimum_size = COUNTER_SIZE
	size = COUNTER_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_localized_font = SILKSCREEN_FONT_SOURCE.duplicate() as Font
	if _localized_font is FontFile:
		(_localized_font as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_NONE
		(_localized_font as FontFile).subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_localized_font.fallbacks.append(ThemeDB.fallback_font)
	set_process(false)
	_grid_overlay = TerminalGridOverlayScript.new()
	_grid_overlay.size = COUNTER_SIZE
	var counter_regions: Array[Rect2] = [cell_rect(0), cell_rect(1), cell_rect(2)]
	_grid_overlay.regions = counter_regions
	add_child(_grid_overlay)


func update_display(player: SurvivorPlayer) -> void:
	var next_values := snapshot_for(player)
	if next_values == _values:
		return
	_values = next_values
	_redraw_revision += 1
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, COUNTER_SIZE), BACKGROUND_COLOR, true)
	var accent: Color = HudPreferencesScript.hud_color()
	_grid_overlay.line_color = accent
	var font_height := _localized_font.get_height(FONT_SIZE)
	var baseline_y := (COUNTER_SIZE.y - font_height) * 0.5 \
		+ _localized_font.get_ascent(FONT_SIZE)
	for index in range(SurvivorData.AXES.size()):
		var axis: StringName = SurvivorData.AXES[index]
		var cell := cell_rect(index)
		var axis_color := accent
		var text := "%s  %d" % [tr(str(SurvivorData.AXIS_I18N_KEY[axis])), _values[index]]
		draw_string(_localized_font, Vector2(cell.position.x, baseline_y), text,
			HORIZONTAL_ALIGNMENT_CENTER, cell.size.x, FONT_SIZE, axis_color)


static func cell_rect(index: int) -> Rect2:
	var x := 0.0
	for previous in range(index):
		x += CELL_WIDTHS[previous]
	return Rect2(x, 0.0, CELL_WIDTHS[index], COUNTER_SIZE.y)


static func snapshot_for(player: SurvivorPlayer) -> Array[int]:
	var result: Array[int] = []
	for axis in SurvivorData.AXES:
		result.append(player.get_milestone_progress(axis) if player != null else 0)
	return result
