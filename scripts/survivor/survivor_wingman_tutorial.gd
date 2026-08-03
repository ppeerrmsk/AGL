class_name SurvivorWingmanTutorial
extends CanvasLayer

## 首次获得僚机时出现的一次性切控提示。
## 不跑 _process：面板只在 viewport 尺寸变化时重排，完成实际数字键切换后淡出并记入存档。

const FADE_OUT := 0.8

var target_slot: int = 2
var _panel: PanelContainer
var _completed := false


func _ready() -> void:
	layer = 21
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.92)
	sb.border_color = Color(0.45, 0.78, 1.0, 0.9)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	_panel.add_child(vb)

	var header := Label.new()
	header.text = tr("TUTORIAL_WINGMAN_HEADER")
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1.0))
	vb.add_child(header)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = tr("TUTORIAL_WINGMAN_SWITCH_FMT") % target_slot
	body.add_theme_font_size_override("normal_font_size", 14)
	body.custom_minimum_size = Vector2(440.0, 0.0)
	vb.add_child(body)


func _layout() -> void:
	if not is_instance_valid(_panel):
		return
	var vp := get_viewport().get_visible_rect().size
	_panel.size = Vector2.ZERO
	var panel_size := _panel.get_combined_minimum_size()
	_panel.position = Vector2((vp.x - panel_size.x) * 0.5, 92.0)


func complete() -> void:
	if _completed:
		return
	_completed = true
	SurvivorTutorial.mark_wingman_switch_done()
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(queue_free)
