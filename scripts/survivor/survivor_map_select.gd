extends Node2D

## 生存模式 — 地图选择界面
## 选中地图后进入 survivor_select（机型选择）

# 视觉参数（与 survivor_select 一致）
const GRID_SPACING := 80.0
const GRID_COLOR := ThemeColors.GRID_COLOR
const LINE_COLOR := ThemeColors.GRID_LINE
const BG_COLOR := ThemeColors.SCENE_BG

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
		"id": "desert_railway_preview",
		"name": "MAP_DESERT_RAILWAY_NAME",
		"tags": ["TAG_DESERT", "TAG_RAILWAY", "TAG_PREVIEW"],
		"desc": "MAP_DESERT_RAILWAY_DESC",
		"map_path": "res://resources/maps/desert_railway_preview.aglmap",
		"preview_only": true,
		"locked": false,
	},
	{
		"id": "ocean_islands_preview",
		"name": "MAP_OCEAN_ISLANDS_NAME",
		"tags": ["TAG_OCEAN", "TAG_ISLANDS", "TAG_PREVIEW"],
		"desc": "MAP_OCEAN_ISLANDS_DESC",
		"map_path": "res://resources/maps/ocean_islands_preview.aglmap",
		"preview_only": true,
		"locked": false,
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
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		elif event.keycode == KEY_B:
			# Boss Debug 入口（仅开发期；正式发布前可加 OS.is_debug_build 守卫）
			get_tree().change_scene_to_file("res://scenes/boss_debug_select.tscn")

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
	title.add_theme_color_override("font_color", ThemeColors.TEXT_TITLE_GREEN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.text = tr("MAP_SELECT_SUBTITLE")
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", ThemeColors.TEXT_SUBTITLE)
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

	# Boss Debug 入口提示（按 B 进入）
	var debug_hint := Label.new()
	debug_hint.text = tr("BOSS_DEBUG_ENTRY_HINT")
	debug_hint.add_theme_font_size_override("font_size", 11)
	debug_hint.add_theme_color_override("font_color", Color(0.55, 0.45, 0.25, 0.55))
	debug_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(debug_hint)

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
		style.bg_color = ThemeColors.CARD_LOCKED_BG
		style.border_color = ThemeColors.CARD_LOCKED_BORDER
	else:
		style.bg_color = ThemeColors.CARD_UNLOCKED_BG
		style.border_color = ThemeColors.CARD_UNLOCKED_BORDER
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
	idx_label.add_theme_color_override("font_color", ThemeColors.TEXT_UNLOCKED_INDEX if not locked else ThemeColors.TEXT_LOCKED_INDEX)
	idx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(idx_label)

	# 地图名称
	var name_label := Label.new()
	name_label.text = tr(data["name"])
	name_label.add_theme_font_size_override("font_size", 18)
	if locked:
		name_label.add_theme_color_override("font_color", ThemeColors.TEXT_LOCKED)
	else:
		name_label.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(200, 0)
	inner.add_child(name_label)

	# 分隔线
	var sep_line := ColorRect.new()
	sep_line.color = ThemeColors.CARD_SEPARATOR_UNLOCKED if not locked else ThemeColors.CARD_SEPARATOR_LOCKED
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
			tag.add_theme_color_override("font_color", ThemeColors.TEXT_LOCKED)
		else:
			tag.add_theme_color_override("font_color", ThemeColors.TEXT_TAG_UNLOCKED)
		tags_box.add_child(tag)

	# 描述
	var desc_label := Label.new()
	desc_label.text = tr(data["desc"])
	desc_label.add_theme_font_size_override("font_size", 11)
	if locked:
		desc_label.add_theme_color_override("font_color", ThemeColors.TEXT_LOCKED)
	else:
		desc_label.add_theme_color_override("font_color", ThemeColors.TEXT_DESC_UNLOCKED)
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
		dis_style.bg_color = ThemeColors.SELECT_BTN_DISABLED_BG
		dis_style.border_color = ThemeColors.SELECT_BTN_DISABLED_BORDER
		dis_style.set_border_width_all(1)
		dis_style.set_corner_radius_all(3)
		dis_style.set_content_margin_all(6)
		btn.add_theme_stylebox_override("disabled", dis_style)
		btn.add_theme_color_override("font_disabled_color", ThemeColors.SELECT_BTN_DISABLED_TEXT)
	else:
		btn.text = tr("SLOT_SELECT_BUTTON")
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = ThemeColors.SELECT_BTN_NORMAL_BG
		btn_style.border_color = ThemeColors.SELECT_BTN_NORMAL_BORDER
		btn_style.set_border_width_all(1)
		btn_style.set_corner_radius_all(3)
		btn_style.set_content_margin_all(6)
		btn.add_theme_stylebox_override("normal", btn_style)

		var btn_hover := StyleBoxFlat.new()
		btn_hover.bg_color = ThemeColors.SELECT_BTN_HOVER_BG
		btn_hover.border_color = ThemeColors.SELECT_BTN_HOVER_BORDER
		btn_hover.set_border_width_all(2)
		btn_hover.set_corner_radius_all(3)
		btn_hover.set_content_margin_all(6)
		btn.add_theme_stylebox_override("hover", btn_hover)

		var btn_pressed := StyleBoxFlat.new()
		btn_pressed.bg_color = ThemeColors.SELECT_BTN_PRESSED_BG
		btn_pressed.border_color = ThemeColors.SELECT_BTN_PRESSED_BORDER
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
		s.bg_color = ThemeColors.THUMB_LOCKED_BG
		s.border_color = ThemeColors.THUMB_LOCKED_BORDER
	else:
		# map 0 用海岸/平原配色暗示
		s.bg_color = ThemeColors.THUMB_UNLOCKED_BG
		s.border_color = ThemeColors.THUMB_UNLOCKED_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	thumb.add_theme_stylebox_override("panel", s)

	var label := Label.new()
	if locked:
		label.text = "?"
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", ThemeColors.THUMB_LOCKED_TEXT)
	else:
		label.text = "[ PREVIEW ]"
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", ThemeColors.THUMB_UNLOCKED_TEXT)
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
	if data.has("map_path"):
		get_tree().set_meta("ugc_map_path", data["map_path"])
	elif get_tree().has_meta("ugc_map_path"):
		get_tree().remove_meta("ugc_map_path")
	get_tree().set_meta("map_preview_only", bool(data.get("preview_only", false)))
	get_tree().change_scene_to_file("res://scenes/survivor_select.tscn")
