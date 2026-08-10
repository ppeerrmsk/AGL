class_name MilestoneAxisCounter
extends Control

## 经验条上方的三轴里程碑摘要。固定占位、纯显示，只在读数变化时重绘。
const COUNTER_SIZE := Vector2(400.0, 18.0)
const CELL_WIDTH := COUNTER_SIZE.x / 3.0
const FONT_SIZE := 11
const BACKGROUND_COLOR := Color(0.0, 0.0, 0.0, 0.46)
const SEPARATOR_COLOR := Color(1.0, 1.0, 1.0, 0.10)
const TEXT_ALPHA := 0.78

var _values: Array[int] = [0, 0, 0]
var _localized_font: Font
var _redraw_revision: int = 0


func _ready() -> void:
	custom_minimum_size = COUNTER_SIZE
	size = COUNTER_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_localized_font = get_theme_default_font()
	if _localized_font == null:
		_localized_font = ThemeDB.fallback_font
	set_process(false)


func update_display(player: SurvivorPlayer) -> void:
	var next_values := snapshot_for(player)
	if next_values == _values:
		return
	_values = next_values
	_redraw_revision += 1
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, COUNTER_SIZE), BACKGROUND_COLOR, true)
	var font_height := _localized_font.get_height(FONT_SIZE)
	var baseline_y := (COUNTER_SIZE.y - font_height) * 0.5 \
		+ _localized_font.get_ascent(FONT_SIZE)
	for index in range(SurvivorData.AXES.size()):
		var axis: StringName = SurvivorData.AXES[index]
		var cell := Rect2(float(index) * CELL_WIDTH, 0.0, CELL_WIDTH, COUNTER_SIZE.y)
		if index > 0:
			draw_line(Vector2(cell.position.x, 3.0),
				Vector2(cell.position.x, COUNTER_SIZE.y - 3.0), SEPARATOR_COLOR, 1.0)
		var axis_color: Color = SurvivorData.AXIS_COLORS.get(axis, Color.WHITE)
		axis_color.a = TEXT_ALPHA
		var text := "%s  %d" % [tr(str(SurvivorData.AXIS_I18N_KEY[axis])), _values[index]]
		draw_string(_localized_font, Vector2(cell.position.x, baseline_y), text,
			HORIZONTAL_ALIGNMENT_CENTER, cell.size.x, FONT_SIZE, axis_color)


static func snapshot_for(player: SurvivorPlayer) -> Array[int]:
	var result: Array[int] = []
	for axis in SurvivorData.AXES:
		result.append(player.get_milestone_progress(axis) if player != null else 0)
	return result
