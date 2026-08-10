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
		# F-15 起手（制空/综合，路线最多；spec player-aircraft-power-curve §2 T1）——恒解锁
		"id": "f15",
		"resource": "res://resources/playable_f15.tres",
		"locked": false,
	},
	{
		# A-6E 起手（攻击/肉，轻火箭；矩阵 v7 新建，取代旧 A-10 起手位——A-10 降为 T2 进化获得）
		# ——30 地面击杀解锁（career-shop §2.1）
		"id": "a6e",
		"resource": "res://resources/player/playable_a6e.tres",
		"locked": false,
	},
	{
		# 幻影 III 起手（电战线之根，补齐四角色四选一；X-02 移入 T5 树内 LV22 进化获得）
		# ——生涯商店购买解锁（career-shop §2.1）
		"id": "mirage3",
		"resource": "res://resources/player/playable_mirage3.tres",
		"locked": false,
	},
	{
		# F-14 起手（远程/团队，开局送 1 僚机组成双机编队；全谱最弱锚点）——首败航母 BOSS 解锁（career-shop §2.1）
		"id": "f14",
		"resource": "res://resources/playable_f14.tres",
		"locked": false,
	},
]

## 本次渲染实际使用的名单（PLAYABLE_LIST 经生涯解锁门控后的副本）
var _list: Array[Dictionary] = []

## 生涯解锁门控（spec career-shop §2.1，2026-07-26 用户改版）：未解锁机型走 locked
## 占位形态——**不加载档案、不显示任何机体数据**（名字 ???、无武器/数值/描述），
## 只在按钮位显示解锁条件句。boss debug 链路全谱放行（debug 测试场必须全谱选机）。
func _effective_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var debug_bypass: bool = get_tree().has_meta("boss_debug_mode")
	for entry in PLAYABLE_LIST:
		var e: Dictionary = entry.duplicate()
		var aid := String(e.get("id", ""))
		if not debug_bypass and aid != "" and not MetaShop.is_aircraft_unlocked(aid):
			e["locked"] = true
			e["slot_desc"] = ""   # 压掉占位卡默认的"新机型开发中"文案（这不是开发中）
			e["unlock_text"] = _unlock_hint_for(aid)
		out.append(e)
	return out

## 锁定卡按钮上的解锁条件句（career-shop §2.4）
func _unlock_hint_for(aircraft_id: String) -> String:
	match aircraft_id:
		"f14":
			return tr("UNLOCK_HINT_F14")
		"a6e":
			return tr("UNLOCK_HINT_A6E_FMT") % mini(
				CareerArchive.get_ground_kills(), MetaShop.A6E_GROUND_KILLS_REQUIRED)
		"mirage3":
			return tr("UNLOCK_HINT_MIRAGE3")
		_:
			return tr("SLOT_DEV_LOCKED_BUTTON")

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

	_list = _effective_list()
	for i in range(_list.size()):
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
	var data: Dictionary = _list[index]
	var locked: bool = data.get("locked", false)
	var dev_locked: bool = data.get("dev_locked", false)

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

	# 武器清单（用户 2026-07-03：选机时要看到这架带什么武器/特色装备）
	if not locked and profile:
		var wpn_text := AircraftDB.weapons_summary(profile)
		if wpn_text != "":
			var wpn_label := Label.new()
			wpn_label.text = wpn_text
			wpn_label.add_theme_font_size_override("font_size", 11)
			wpn_label.add_theme_color_override("font_color", ThemeColors.CATEGORY_WEAPON)
			wpn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			wpn_label.custom_minimum_size = Vector2(220, 0)
			wpn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			inner.add_child(wpn_label)

	# 机体特性行（card_perks：数值级差异如强化机炮/经验加成；
	# 未解锁卡不展示——用户 2026-07-27，只给已解锁玩家看细账）
	if not locked and not dev_locked and profile:
		for perk_key in profile.card_perks:
			var perk := Label.new()
			perk.text = tr(perk_key)
			perk.add_theme_font_size_override("font_size", 11)
			perk.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6, 0.8))
			perk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			perk.custom_minimum_size = Vector2(220, 0)
			perk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			inner.add_child(perk)

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

	if locked or dev_locked:
		# 生涯门控卡（career-shop）：按钮显示解锁条件句；无条件句才落回"开发中/未解锁"
		if data.has("unlock_text"):
			btn.text = String(data["unlock_text"])
			btn.add_theme_font_size_override("font_size", 13)
		else:
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
	var data: Dictionary = _list[index] if index < _list.size() else PLAYABLE_LIST[index]
	if data.get("locked", false) or data.get("dev_locked", false):
		return
	# 通过 scene tree meta 传递选择的 PlayableAircraft 资源路径
	get_tree().set_meta("survivor_aircraft_resource", data["resource"])
	# 直接出击（配件机库已随槽位配件系统退役，spec doctrine-unlocks §3.5）
	get_tree().change_scene_to_file("res://scenes/building_preloader.tscn")
