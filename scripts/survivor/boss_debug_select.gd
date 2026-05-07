extends Node2D

## Boss Debug 模式 — BOSS 选择界面
## 选 boss → 跳到 survivor_select（机型选择）→ 进入 survivor_mode（boss_debug 分支）
##
## 视觉与 survivor_map_select 保持一致（同一组 ThemeColors）
## 加新 boss：在 BOSS_LIST 加一条；BossRegistry 必须已定义同名 id

const GRID_SPACING := 80.0
const GRID_COLOR := ThemeColors.GRID_COLOR
const LINE_COLOR := ThemeColors.GRID_LINE
const BG_COLOR := ThemeColors.SCENE_BG

var _time := 0.0
var _canvas: CanvasLayer
var _cards_container: HBoxContainer

## boss_id 必须与 BossRegistry.BOSS_DEFS 的 key 一致
const BOSS_LIST: Array[Dictionary] = [
	{
		"id": "WRAITH_SQUADRON",
		"name": "BOSS_DEBUG_WRAITH_NAME",
		"desc": "BOSS_DEBUG_WRAITH_DESC",
		"tags": ["TAG_AIR", "TAG_STEALTH"],
	},
	{
		"id": "CARRIER_STRIKE_GROUP",
		"name": "BOSS_DEBUG_CSG_NAME",
		"desc": "BOSS_DEBUG_CSG_DESC",
		"tags": ["TAG_NAVAL", "TAG_TWO_PHASE"],
	},
	{
		"id": "MOTHER_GOOSE",
		"name": "BOSS_DEBUG_GOOSE_NAME",
		"desc": "BOSS_DEBUG_GOOSE_DESC",
		"tags": ["TAG_AIR", "TAG_CARRIER"],
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
		# 清掉 boss debug meta，避免误漏到正常生存模式
		if get_tree().has_meta("boss_debug_mode"):
			get_tree().remove_meta("boss_debug_mode")
		if get_tree().has_meta("boss_debug_id"):
			get_tree().remove_meta("boss_debug_id")
		get_tree().change_scene_to_file("res://scenes/survivor_map_select.tscn")

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

	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_top.size_flags_stretch_ratio = 0.25
	root.add_child(spacer_top)

	var title := Label.new()
	title.text = tr("BOSS_DEBUG_TITLE")
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", ThemeColors.TEXT_TITLE_GREEN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = tr("BOSS_DEBUG_SUBTITLE")
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", ThemeColors.TEXT_SUBTITLE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(subtitle)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 30)
	root.add_child(sep)

	_cards_container = HBoxContainer.new()
	_cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_container.add_theme_constant_override("separation", 18)
	_cards_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_cards_container)

	for i in range(BOSS_LIST.size()):
		_build_boss_card(i)

	var sep2 := Control.new()
	sep2.custom_minimum_size = Vector2(0, 24)
	root.add_child(sep2)

	var hint := Label.new()
	hint.text = tr("BOSS_DEBUG_HINT_ESC")
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.4, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)

	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_bottom.size_flags_stretch_ratio = 0.35
	root.add_child(spacer_bottom)

func _build_boss_card(index: int) -> void:
	var data: Dictionary = BOSS_LIST[index]

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.CARD_UNLOCKED_BG
	style.border_color = ThemeColors.CARD_UNLOCKED_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(260, 280)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	panel.add_child(inner)

	# 序号
	var idx_label := Label.new()
	idx_label.text = "BOSS / %02d" % (index + 1)
	idx_label.add_theme_font_size_override("font_size", 11)
	idx_label.add_theme_color_override("font_color", ThemeColors.TEXT_UNLOCKED_INDEX)
	idx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(idx_label)

	# 名称
	var name_label := Label.new()
	name_label.text = tr(data["name"])
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(220, 0)
	inner.add_child(name_label)

	var sep_line := ColorRect.new()
	sep_line.color = ThemeColors.CARD_SEPARATOR_UNLOCKED
	sep_line.custom_minimum_size = Vector2(0, 1)
	inner.add_child(sep_line)

	# tags
	var tags_box := HBoxContainer.new()
	tags_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tags_box.add_theme_constant_override("separation", 6)
	inner.add_child(tags_box)
	for tag_text in (data.get("tags", []) as Array):
		var tag := Label.new()
		tag.text = tr("SLOT_TAG_WRAP_FMT") % tr(tag_text)
		tag.add_theme_font_size_override("font_size", 10)
		tag.add_theme_color_override("font_color", ThemeColors.TEXT_TAG_UNLOCKED)
		tags_box.add_child(tag)

	# 描述
	var desc_label := Label.new()
	desc_label.text = tr(data["desc"])
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", ThemeColors.TEXT_DESC_UNLOCKED)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(220, 0)
	inner.add_child(desc_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(spacer)

	# 选择按钮
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(220, 38)
	btn.add_theme_font_size_override("font_size", 15)
	btn.text = tr("BOSS_DEBUG_LAUNCH_BUTTON")

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
	btn.pressed.connect(func(): _on_boss_selected(idx))

	inner.add_child(btn)
	_cards_container.add_child(panel)

# ══════════════════════════════════════════════
#  选择 → 跳到机型选择
# ══════════════════════════════════════════════

func _on_boss_selected(index: int) -> void:
	var data: Dictionary = BOSS_LIST[index]
	# Survivor mode 用一组 meta 切换到 boss_debug 分支
	get_tree().set_meta("boss_debug_mode", true)
	get_tree().set_meta("boss_debug_id", data["id"])
	get_tree().set_meta("survivor_map_id", "boss_debug")
	get_tree().change_scene_to_file("res://scenes/survivor_select.tscn")
