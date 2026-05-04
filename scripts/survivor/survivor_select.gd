extends Node2D

## 生存模式 — 机型选择界面
## 选中飞机后进入 survivor_mode 场景

# 视觉参数（与 main_menu 一致）
const GRID_SPACING := 80.0
const GRID_COLOR := ThemeColors.GRID_COLOR
const LINE_COLOR := ThemeColors.GRID_LINE
const BG_COLOR := ThemeColors.SCENE_BG

var _time := 0.0
var _canvas: CanvasLayer
var _cards_container: HBoxContainer
var _selected_index: int = -1

# ── 可选主角档案 ──
# 每个条目对应一个 PlayableAircraft 资源（res://resources/playable_*.tres）
# locked = true 时显示为占位符，无法点击
# 加新主角的工作流程见 docs/reference/playable-aircraft-workflow.md
const PLAYABLE_LIST: Array[Dictionary] = [
	{
		"resource": "res://resources/playable_f16.tres",
		"locked": false,
	},
	{
		"resource": "res://resources/playable_f14.tres",
		"locked": false,
	},
	{
		"resource": "res://resources/playable_x02.tres",
		"locked": false,
	},
	{
		"resource": "res://resources/playable_a10.tres",
		"locked": false,
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
		# Boss Debug 模式：返回到 boss 选择界面而不是普通地图选择
		if get_tree().has_meta("boss_debug_mode"):
			get_tree().change_scene_to_file("res://scenes/boss_debug_select.tscn")
		else:
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
	# 四角装饰
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
	spacer_top.size_flags_stretch_ratio = 0.25
	root.add_child(spacer_top)

	# 标题
	var title := Label.new()
	title.text = tr("AIRCRAFT_SELECT_TITLE")
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", ThemeColors.TEXT_TITLE_GREEN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.text = tr("AIRCRAFT_SELECT_SUBTITLE")
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", ThemeColors.TEXT_SUBTITLE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(subtitle)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 30)
	root.add_child(sep)

	# 机型卡片容器
	_cards_container = HBoxContainer.new()
	_cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_container.add_theme_constant_override("separation", 16)
	_cards_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_cards_container)

	for i in range(PLAYABLE_LIST.size()):
		_build_aircraft_card(i)

	# 下方提示
	var sep2 := Control.new()
	sep2.custom_minimum_size = Vector2(0, 24)
	root.add_child(sep2)

	var hint := Label.new()
	hint.text = tr("AIRCRAFT_SELECT_HINT_ESC")
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.4, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)

	# 下部空白
	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer_bottom.size_flags_stretch_ratio = 0.4
	root.add_child(spacer_bottom)

func _build_aircraft_card(index: int) -> void:
	var data: Dictionary = PLAYABLE_LIST[index]
	var locked: bool = data.get("locked", false)

	# 加载档案（仅未锁定项）
	var profile: PlayableAircraft = null
	if not locked:
		profile = load(data["resource"])

	# 卡片面板背景
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
	panel.custom_minimum_size = Vector2(260, 340)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	panel.add_child(inner)

	# 序号
	var idx_label := Label.new()
	idx_label.text = tr("SLOT_PILOT_INDEX_FMT") % (index + 1)
	idx_label.add_theme_font_size_override("font_size", 11)
	idx_label.add_theme_color_override("font_color",
		ThemeColors.TEXT_UNLOCKED_INDEX if not locked else ThemeColors.TEXT_LOCKED_INDEX)
	idx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(idx_label)

	# 机型名称
	var name_label := Label.new()
	if locked:
		name_label.text = tr(data.get("slot_name", "SLOT_TBA_NAME"))
		name_label.add_theme_color_override("font_color", ThemeColors.TEXT_LOCKED)
	else:
		name_label.text = tr(profile.display_name) if profile else tr("SLOT_NAME_UNKNOWN")
		name_label.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(220, 0)
	inner.add_child(name_label)

	# 副名（codename）
	if not locked and profile and profile.codename != "":
		var sub := Label.new()
		sub.text = "「%s」" % profile.codename
		sub.add_theme_font_size_override("font_size", 12)
		sub.add_theme_color_override("font_color", ThemeColors.TEXT_CODENAME)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(sub)

	# 分隔线
	var sep_line := ColorRect.new()
	sep_line.color = ThemeColors.CARD_SEPARATOR_UNLOCKED if not locked else ThemeColors.CARD_SEPARATOR_LOCKED
	sep_line.custom_minimum_size = Vector2(0, 1)
	inner.add_child(sep_line)

	# 特性标签
	var tags_box := HBoxContainer.new()
	tags_box.alignment = BoxContainer.ALIGNMENT_CENTER
	tags_box.add_theme_constant_override("separation", 6)
	inner.add_child(tags_box)

	var tag_list: Array = []
	if locked:
		tag_list = ["TAG_LOCKED"]
	elif profile:
		for t in profile.card_tags:
			tag_list.append(t)
	for tag_text in tag_list:
		var tag := Label.new()
		tag.text = tr("SLOT_TAG_WRAP_FMT") % tr(tag_text)
		tag.add_theme_font_size_override("font_size", 10)
		if locked:
			tag.add_theme_color_override("font_color", ThemeColors.TEXT_LOCKED)
		else:
			tag.add_theme_color_override("font_color", ThemeColors.TEXT_TAG_UNLOCKED)
		tags_box.add_child(tag)

	# 起始僚机标记（仅小队主控显示）
	if not locked and profile and profile.wingman_count > 0:
		var squad_label := Label.new()
		squad_label.text = tr("SLOT_STARTING_SQUAD_FMT") % profile.wingman_count
		squad_label.add_theme_font_size_override("font_size", 11)
		squad_label.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6, 0.8))
		squad_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(squad_label)

	# 描述
	var desc_label := Label.new()
	if locked:
		desc_label.text = tr(data.get("slot_desc", "SLOT_AIRCRAFT_DESC"))
		desc_label.add_theme_color_override("font_color", ThemeColors.TEXT_LOCKED)
	else:
		desc_label.text = tr(profile.card_desc) if profile else ""
		desc_label.add_theme_color_override("font_color", ThemeColors.TEXT_DESC_UNLOCKED)
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(220, 0)
	inner.add_child(desc_label)

	# 弹性空间
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(spacer)

	# 简要参数（仅未锁定）
	if not locked and profile and profile.base_params:
		var bp: AircraftParams = profile.base_params
		var stats := Label.new()
		stats.text = tr("AIRCRAFT_STATS_FMT") % [
			int(bp.max_hp),
			int(bp.max_speed),
			bp.max_g,
			bp.missile.max_count if bp.missile else 0,
		]
		stats.add_theme_font_size_override("font_size", 10)
		stats.add_theme_color_override("font_color", ThemeColors.TEXT_STATS)
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(stats)

	# 出击/未解锁按钮
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(220, 40)
	btn.add_theme_font_size_override("font_size", 16)

	var dev_locked: bool = data.get("dev_locked", false)
	if locked or dev_locked:
		btn.text = tr("SLOT_DEV_LOCKED_BUTTON") if dev_locked else tr("SLOT_LOCKED_BUTTON")
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
		btn.text = tr("AIRCRAFT_SELECT_LAUNCH_BUTTON")
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
		btn.pressed.connect(func(): _on_aircraft_selected(idx))

	inner.add_child(btn)

	_cards_container.add_child(panel)

# ══════════════════════════════════════════════
#  选择 & 进入游戏
# ══════════════════════════════════════════════

func _on_aircraft_selected(index: int) -> void:
	var data: Dictionary = PLAYABLE_LIST[index]
	if data.get("locked", false) or data.get("dev_locked", false):
		return
	# 通过 scene tree meta 传递选择的 PlayableAircraft 资源路径
	get_tree().set_meta("survivor_aircraft_resource", data["resource"])
	# 进配件机库；机库的"出击"按钮会接力到 building_preloader → survivor_mode
	# Boss Debug 模式跳过机库（直接出击，配件预设由 BossDebugBuilds 管）
	if get_tree().has_meta("boss_debug_mode"):
		get_tree().change_scene_to_file("res://scenes/building_preloader.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/survivor_loadout.tscn")
