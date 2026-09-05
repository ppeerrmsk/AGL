class_name AceBattleBar
extends PanelContainer

## 常规王牌中队分段命条的唯一视觉实现。
## 旅途王牌与 The Crucible 的活跃中队都必须复用本控件。

const SEGMENT_WIDTH := 26.0
const SEGMENT_HEIGHT := 9.0
const DEAD_COLOR := Color(0.22, 0.20, 0.22)

var title_label: Label
var emblem: AceEmblemIcon
var segment_box: HBoxContainer
var segments: Array[Panel] = []


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BOSS_PANEL_BG
	style.border_color = ThemeColors.BOSS_PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 5
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 6)
	vbox.add_child(title_row)
	emblem = AceEmblemIcon.new("", Color.WHITE, 7.0)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(emblem)
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 11)
	title_row.add_child(title_label)
	segment_box = HBoxContainer.new()
	segment_box.add_theme_constant_override("separation", 3)
	segment_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(segment_box)


func set_info(info: Dictionary) -> void:
	if info.is_empty():
		visible = false
		return
	visible = true
	var alive: Array = info.get("alive", [])
	var color: Color = info.get("color", Color(1.0, 0.3, 0.3))
	title_label.text = String(info.get("codename", ""))
	title_label.add_theme_color_override("font_color", color.lightened(0.25))
	emblem.set_emblem(String(info.get("id", "")), color.lightened(0.15))
	if segments.size() != alive.size():
		for segment in segments:
			segment.queue_free()
		segments.clear()
		for _i in range(alive.size()):
			var segment := Panel.new()
			segment.custom_minimum_size = Vector2(SEGMENT_WIDTH, SEGMENT_HEIGHT)
			segment_box.add_child(segment)
			segments.append(segment)
	for i in range(segments.size()):
		var segment_style := StyleBoxFlat.new()
		segment_style.bg_color = color if bool(alive[i]) else DEAD_COLOR
		segment_style.set_corner_radius_all(1)
		if i == 0:
			segment_style.border_width_top = 2
			segment_style.border_color = color.lightened(0.55) if bool(alive[i]) \
				else Color(0.45, 0.42, 0.45)
		segments[i].add_theme_stylebox_override("panel", segment_style)
