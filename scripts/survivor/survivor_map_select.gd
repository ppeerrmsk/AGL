extends Node2D

## 生存模式 — 地图选择界面
## 选中地图后进入 survivor_select（机型选择）

# 视觉参数（与 survivor_select 一致）
const GRID_SPACING := 80.0
const GRID_COLOR := Color(0.15, 0.2, 0.15, 0.3)
const LINE_COLOR := Color(0.3, 0.7, 0.3, 0.5)
const BG_COLOR := Color(0.02, 0.03, 0.02)

var _time := 0.0
var _canvas: CanvasLayer
var _cards_container: HBoxContainer

# ── 可选地图定义 ──
# 第 0 个为之前默认的区域（已实装），其余 4 个为预留位
## 字段里的 name/desc/tags 值均为翻译 key，由消费端 tr() 翻译
const MAP_LIST: Array[Dictionary] = [
	{
		"id": "default",
		"name": "MAP_DEFAULT_NAME",
		"tags": ["TAG_PLAIN", "TAG_COAST", "TAG_HILLS"],
		"desc": "MAP_DEFAULT_DESC",
		"locked": false,
	},
	{
		"id": "tba_2",
		"name": "SLOT_TBA_NAME",
		"tags": ["TAG_LOCKED"],
		"desc": "SLOT_MAP_DESC",
		"locked": true,
	},
	{
		"id": "tba_3",
		"name": "SLOT_TBA_NAME",
		"tags": ["TAG_LOCKED"],
		"desc": "SLOT_MAP_DESC",
		"locked": true,
	},
	{
		"id": "tba_4",
		"name": "SLOT_TBA_NAME",
		"tags": ["TAG_LOCKED"],
		"desc": "SLOT_MAP_DESC",
		"locked": true,
	},
	{
		"id": "tba_5",
		"name": "SLOT_TBA_NAME",
		"tags": ["TAG_LOCKED"],
		"desc": "SLOT_MAP_DESC",
		"locked": true,
	},
]

func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_build_ui()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_grid(vp)
	_draw_corners(vp)

func _draw_grid(vp: Vector2) -> void:
	var cols := int(vp.x / GRID_SPACING) + 1
	var rows := int(vp.y / GRID_SPACING) + 1
	for i in range(cols + 1):
		var x := i * GRID_SPACING
		draw_line(Vector2(x, 0), Vector2(x, vp.y), GRID_COLOR, 1.0)
	for j in range(rows + 1):
		var y := j * GRID_SPACING
		draw_line(Vector2(0, y), Vector2(vp.x, y), GRID_COLOR, 1.0)

func _draw_corners(vp: Vector2) -> void:
	var margin := 40.0
	var corner_len := 20.0
	var c := LINE_COLOR
	draw_line(Vector2(margin, margin), Vector2(margin + corner_len, margin), c, 1.5)
	draw_line(Vector2(margin, margin), Vector2(margin, margin + corner_len), c, 1.5)
	draw_line(Vector2(vp.x - margin, margin), Vector2(vp.x - margin - corner_len, margin), c, 1.5)
	draw_line(Vector2(vp.x - margin, margin), Vector2(vp.x - margin, margin + corner_len), c, 1.5)
	draw_line(Vector2(margin, vp.y - margin), Vector2(margin + corner_len, vp.y - margin), c, 1.5)
	draw_line(Vector2(margin, vp.y - margin), Vector2(margin, vp.y - margin - corner_len), c, 1.5)
	draw_line(Vector2(vp.x - margin, vp.y - margin), Vector2(vp.x - margin - corner_len, vp.y - margin), c, 1.5)
	draw_line(Vector2(vp.x - margin, vp.y - margin), Vector2(vp.x - margin, vp.y - margin - corner_len), c, 1.5)

# ══════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 0)
	_canvas.add_child(root)

	# 上部空白
	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_top.size_flags_stretch_ratio = 0.2
	root.add_child(spacer_top)

	# 标题
	var title := Label.new()
	title.text = tr("MAP_SELECT_TITLE")
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.text = tr("MAP_SELECT_SUBTITLE")
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.3, 0.6, 0.3, 0.6))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(subtitle)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 30)
	root.add_child(sep)

	# 地图卡片容器
	_cards_container = HBoxContainer.new()
	_cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_container.add_theme_constant_override("separation", 18)
	_cards_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_cards_container)

	for i in range(MAP_LIST.size()):
		_build_map_card(i)

	# 下方提示
	var sep2 := Control.new()
	sep2.custom_minimum_size = Vector2(0, 24)
	root.add_child(sep2)

	var hint := Label.new()
	hint.text = tr("MAP_SELECT_HINT_ESC")
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.4, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)

	# 下部空白
	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_bottom.size_flags_stretch_ratio = 0.35
	root.add_child(spacer_bottom)

func _build_map_card(index: int) -> void:
	var data: Dictionary = MAP_LIST[index]
	var locked: bool = data.get("locked", false)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	if locked:
		style.bg_color = Color(0.03, 0.04, 0.03, 0.6)
		style.border_color = Color(0.2, 0.3, 0.2, 0.3)
	else:
		style.bg_color = Color(0.04, 0.07, 0.04, 0.8)
		style.border_color = Color(0.3, 0.6, 0.3, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(230, 280)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	panel.add_child(inner)

	# 序号
	var idx_label := Label.new()
	idx_label.text = tr("SLOT_MAP_INDEX_FMT") % (index + 1)
	idx_label.add_theme_font_size_override("font_size", 11)
	idx_label.add_theme_color_override("font_color", Color(0.4, 0.6, 0.4, 0.5) if not locked else Color(0.3, 0.35, 0.3, 0.5))
	idx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(idx_label)

	# 地图名称
	var name_label := Label.new()
	name_label.text = tr(data["name"])
	name_label.add_theme_font_size_override("font_size", 18)
	if locked:
		name_label.add_theme_color_override("font_color", Color(0.4, 0.45, 0.4, 0.6))
	else:
		name_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(200, 0)
	inner.add_child(name_label)

	# 分隔线
	var sep_line := ColorRect.new()
	sep_line.color = Color(0.3, 0.6, 0.3, 0.3) if not locked else Color(0.2, 0.3, 0.2, 0.3)
	sep_line.custom_minimum_size = Vector2(0, 1)
	inner.add_child(sep_line)

	# 缩略图占位（简单的着色块代替）
	var thumb := _build_map_thumb(index, locked)
	inner.add_child(thumb)

	# 标签
	var tags_box := HBoxContainer.new()
	tags_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tags_box.add_theme_constant_override("separation", 6)
	inner.add_child(tags_box)

	var tags: Array = data["tags"]
	for tag_text in tags:
		var tag := Label.new()
		tag.text = tr("SLOT_TAG_WRAP_FMT") % tr(tag_text)
		tag.add_theme_font_size_override("font_size", 10)
		if locked:
			tag.add_theme_color_override("font_color", Color(0.35, 0.4, 0.35, 0.6))
		else:
			tag.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5, 0.7))
		tags_box.add_child(tag)

	# 描述
	var desc_label := Label.new()
	desc_label.text = tr(data["desc"])
	desc_label.add_theme_font_size_override("font_size", 11)
	if locked:
		desc_label.add_theme_color_override("font_color", Color(0.4, 0.45, 0.4, 0.6))
	else:
		desc_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6, 0.8))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(200, 0)
	inner.add_child(desc_label)

	# 弹性
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(spacer)

	# 选择按钮
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(200, 38)
	btn.add_theme_font_size_override("font_size", 15)

	if locked:
		btn.text = tr("SLOT_LOCKED_BUTTON")
		btn.disabled = true
		var dis_style := StyleBoxFlat.new()
		dis_style.bg_color = Color(0.05, 0.06, 0.05, 0.5)
		dis_style.border_color = Color(0.2, 0.25, 0.2, 0.4)
		dis_style.set_border_width_all(1)
		dis_style.set_corner_radius_all(3)
		dis_style.set_content_margin_all(6)
		btn.add_theme_stylebox_override("disabled", dis_style)
		btn.add_theme_color_override("font_disabled_color", Color(0.3, 0.4, 0.3, 0.5))
	else:
		btn.text = tr("SLOT_SELECT_BUTTON")
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.08, 0.15, 0.08, 0.9)
		btn_style.border_color = Color(0.4, 0.8, 0.4, 0.5)
		btn_style.set_border_width_all(1)
		btn_style.set_corner_radius_all(3)
		btn_style.set_content_margin_all(6)
		btn.add_theme_stylebox_override("normal", btn_style)

		var btn_hover := StyleBoxFlat.new()
		btn_hover.bg_color = Color(0.12, 0.25, 0.12, 0.95)
		btn_hover.border_color = Color(0.5, 1.0, 0.5, 0.8)
		btn_hover.set_border_width_all(2)
		btn_hover.set_corner_radius_all(3)
		btn_hover.set_content_margin_all(6)
		btn.add_theme_stylebox_override("hover", btn_hover)

		var btn_pressed := StyleBoxFlat.new()
		btn_pressed.bg_color = Color(0.18, 0.35, 0.18, 1.0)
		btn_pressed.border_color = Color(0.6, 1.0, 0.6, 1.0)
		btn_pressed.set_border_width_all(2)
		btn_pressed.set_corner_radius_all(3)
		btn_pressed.set_content_margin_all(6)
		btn.add_theme_stylebox_override("pressed", btn_pressed)

		var idx := index
		btn.pressed.connect(func(): _on_map_selected(idx))

	inner.add_child(btn)

	_cards_container.add_child(panel)

# 简易缩略图（着色矩形 + 边框）— 后续替换为真实预览
func _build_map_thumb(index: int, locked: bool) -> Control:
	var thumb := PanelContainer.new()
	thumb.custom_minimum_size = Vector2(200, 80)
	var s := StyleBoxFlat.new()
	if locked:
		s.bg_color = Color(0.06, 0.08, 0.06, 0.6)
		s.border_color = Color(0.2, 0.3, 0.2, 0.4)
	else:
		# map 0 用海岸/平原配色暗示
		s.bg_color = Color(0.10, 0.18, 0.13, 0.8)
		s.border_color = Color(0.35, 0.7, 0.4, 0.5)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	thumb.add_theme_stylebox_override("panel", s)

	var label := Label.new()
	if locked:
		label.text = "?"
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", Color(0.3, 0.4, 0.3, 0.5))
	else:
		label.text = "[ PREVIEW ]"
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5, 0.5))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.add_child(label)

	return thumb

# ══════════════════════════════════════════════
#  选择 & 进入下一步
# ══════════════════════════════════════════════

func _on_map_selected(index: int) -> void:
	var data: Dictionary = MAP_LIST[index]
	# 通过 scene tree meta 传递选择的地图 id 到 survivor_mode
	get_tree().set_meta("survivor_map_id", data["id"])
	get_tree().change_scene_to_file("res://scenes/survivor_select.tscn")
