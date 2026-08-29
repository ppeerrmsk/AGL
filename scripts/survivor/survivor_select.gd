extends Node2D

const TerminalPageShellScript := preload("res://scripts/ui/terminal_page_shell.gd")
const TerminalUiStyleScript := preload("res://scripts/ui/terminal_ui_style.gd")
const AircraftHologramPreviewScript := preload(
	"res://scripts/survivor/aircraft_hologram_preview.gd")

## T0 起手机机场等价礼包的玩家可见名称。授予仍只认 profile.starting_benefit_id；
## 这里仅把正式技能 / 战区武器名称接到选机卡，避免把礼包误读成机体底线武器。
const STARTING_BENEFIT_NAME_KEYS: Dictionary = {
	&"gun_multishot": "UPGRADE_GUN_MULTISHOT_NAME",
	&"rocket_ffar": "AIRCRAFT_STARTING_BENEFIT_FFAR_NAME",
	&"qmaam": "REWARD_WEAPON_QMAAM_NAME",
	&"esm_pod": "REWARD_WEAPON_ESM_NAME",
}

## 生存模式 — 机型选择界面
## 选中飞机后进入 survivor_mode 场景

const BG_COLOR := ThemeColors.SCENE_BG

var _canvas: CanvasLayer
var _cards_container: GridContainer
var _hologram_preview: Control
var _selected_index: int = -1
var _card_panels: Array[PanelContainer] = []
var _profile_by_index: Dictionary = {}

# ── 可选主角档案 ──
# 每个条目对应一个 PlayableAircraft 资源（res://resources/playable_*.tres）
# locked = true 时显示为占位符，无法点击
# 加新主角的工作流程见 docs/reference/playable-aircraft-workflow.md
const PLAYABLE_LIST: Array[Dictionary] = [
	{
		# 既有起手 1：制空 / 综合
		"id": "f15",
		"resource": "res://resources/playable_f15.tres",
		"locked": false,
	},
	{
		# 既有起手 2：远程 / 双机编队
		"id": "f14",
		"resource": "res://resources/playable_f14.tres",
		"locked": false,
	},
	{
		# 既有起手 3：攻击 / 肉盾
		"id": "a6e",
		"resource": "res://resources/player/playable_a6e.tres",
		"locked": false,
	},
	{
		# 既有起手 4：电战 / 多用途
		"id": "mirage3",
		"resource": "res://resources/player/playable_mirage3.tres",
		"locked": false,
	},
	{
		# 局外解锁：T0 斗士，轻型高速截击
		"id": "mig21f13",
		"resource": "res://resources/player/playable_mig21f13.tres",
		"locked": false,
	},
	{
		# 局外解锁：T0 骑士，极速 / 窄锥截击
		"id": "f104c",
		"resource": "res://resources/player/playable_f104c.tres",
		"locked": false,
	},
	{
		# 局外解锁：T0 斗士，宽锥全天候截击
		"id": "j35f",
		"resource": "res://resources/player/playable_j35f.tres",
		"locked": false,
	},
	{
		# 局外解锁：T0 策士支援，A-6E 同级速度 / 本档最高感知
		"id": "ea6b",
		"resource": "res://resources/player/playable_ea6b.tres",
		"locked": false,
	},
]

## 本次渲染实际使用的名单（PLAYABLE_LIST 经生涯解锁门控后的副本）
var _list: Array[Dictionary] = []

## 生涯解锁门控（spec career-shop §2.1，2026-07-26 用户改版）：未解锁机型走 locked
## 占位形态——**不加载档案、不显示任何机体数据**（名字 ???、无武器/数值/描述），
## 只在按钮位显示解锁条件句。Boss Debug 另走正式树的 T4 参考名单，不受生涯门控。
func _effective_list() -> Array[Dictionary]:
	if get_tree().has_meta("boss_debug_mode"):
		return _boss_debug_reference_list()
	var out: Array[Dictionary] = []
	for entry in PLAYABLE_LIST:
		var e: Dictionary = entry.duplicate()
		var aid := String(e.get("id", ""))
		if aid != "" and not MetaShop.is_aircraft_unlocked(aid):
			e["locked"] = true
			e["slot_desc"] = ""   # 压掉占位卡默认的"新机型开发中"文案（这不是开发中）
			e["unlock_text"] = _unlock_hint_for(aid)
		out.append(e)
	return out


## Boss Debug 不复用正常八卡：直接列正式进化树的全部 T4（T5 前一档）参考机。
func _boss_debug_reference_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node in BossDebugBuilds.reference_nodes():
		var profile_id := StringName(String(node.get("profile", "")))
		var profile := AircraftDB.get_profile(profile_id)
		if profile == null or profile.resource_path.is_empty():
			continue
		out.append({
			"id": String(profile_id),
			"resource": profile.resource_path,
			"locked": false,
			"boss_debug_node_id": String(node.get("id", "")),
			"boss_debug_level": EvolutionSystem.min_level_of(node),
		})
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
		"mig21f13":
			return tr("UNLOCK_HINT_MIG21F13")
		"f104c":
			return tr("UNLOCK_HINT_F104C")
		"j35f":
			return tr("UNLOCK_HINT_J35F")
		"ea6b":
			return tr("UNLOCK_HINT_EA6B")
		_:
			return tr("SLOT_DEV_LOCKED_BUTTON")

func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Boss Debug 模式：返回到 boss 选择界面而不是普通地图选择
		if get_tree().has_meta("boss_debug_mode"):
			get_tree().change_scene_to_file("res://scenes/boss_debug_select.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/survivor_map_select.tscn")

# ══════════════════════════════════════════════
#  UI 构建
# ══════════════════════════════════════════════

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)
	var shell := TerminalPageShellScript.new()
	_canvas.add_child(shell)
	var boss_debug := get_tree().has_meta("boss_debug_mode")
	_list = _effective_list()
	var title_text := tr("BOSS_DEBUG_AIRCRAFT_TITLE") if boss_debug \
		else tr("AIRCRAFT_SELECT_TITLE")
	var subtitle_text := tr("BOSS_DEBUG_AIRCRAFT_SUBTITLE") if boss_debug \
		else tr("AIRCRAFT_SELECT_SUBTITLE")
	var frame := TerminalUiStyleScript.build_page(
		shell.content, title_text, subtitle_text, "AIRFRAME // %02d" % _list.size())
	var body := frame["body"] as PanelContainer
	var footer := frame["footer"] as HBoxContainer
	var body_row := HBoxContainer.new()
	body_row.name = "AircraftSelectionBody"
	body_row.add_theme_constant_override("separation", 8)
	body_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(body_row)
	_hologram_preview = AircraftHologramPreviewScript.new()
	body_row.add_child(_hologram_preview)
	var scroll := ScrollContainer.new()
	scroll.name = "AircraftCardScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_row.add_child(scroll)
	_cards_container = GridContainer.new()
	_cards_container.columns = 3
	_cards_container.add_theme_constant_override("h_separation", 0)
	_cards_container.add_theme_constant_override("v_separation", 0)
	# 固定全息窗 + 三列卡片共同落在 23u 安全区内，滚动只发生在卡片侧。
	_cards_container.custom_minimum_size = Vector2(630, 0)
	_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards_container)

	for i in range(_list.size()):
		_build_aircraft_card(i)
	_show_initial_preview()

	TerminalUiStyleScript.build_footer_hint(
		footer, "%s  //  %s" % [tr("AIRCRAFT_SELECT_HINT_ESC"), "01—%02d" % _list.size()])
	TerminalUiStyleScript.build_footer_button(
		footer, tr("LOADOUT_BACK"), _on_back_from_select, 200.0)

func _build_aircraft_card(index: int) -> void:
	var data: Dictionary = _list[index]
	var locked: bool = data.get("locked", false)
	var dev_locked: bool = data.get("dev_locked", false)

	# 加载档案（仅未锁定项）
	var profile: PlayableAircraft = null
	if not locked:
		profile = load(data["resource"])
		_profile_by_index[index] = profile

	# 卡片面板背景
	var panel := PanelContainer.new()
	TerminalUiStyleScript.apply_panel(panel,
		Color(TerminalUiStyleScript.accent(), 0.20 if locked else 0.82),
		Color(0.0, 0.0, 0.0, 0.54 if locked else 0.80), 10.0)
	panel.custom_minimum_size = Vector2(210, 340)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.mouse_entered.connect(func(): _show_aircraft_preview(index))
	_card_panels.append(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	panel.add_child(inner)

	# 序号
	var idx_label := Label.new()
	idx_label.text = tr("SLOT_PILOT_INDEX_FMT") % (index + 1)
	idx_label.add_theme_font_size_override("font_size", 11)
	TerminalUiStyleScript.apply_terminal_label(idx_label, 11,
		Color(TerminalUiStyleScript.accent(), 0.74) if not locked \
		else TerminalUiStyleScript.LOCKED_TEXT)
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
	TerminalUiStyleScript.apply_label(name_label, 20,
		TerminalUiStyleScript.LOCKED_TEXT if locked else TerminalUiStyleScript.accent(), true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(190, 0)
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
	sep_line.color = Color(TerminalUiStyleScript.accent(), 0.62 if not locked else 0.18)
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
			wpn_label.custom_minimum_size = Vector2(190, 0)
			wpn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			inner.add_child(wpn_label)

	# T0 作为本局起手机时额外获得的一次机场等价收益；不是机体底线武器。
	if not locked and not dev_locked and profile and profile.starting_benefit_id != &"":
		var benefit_name_key := String(STARTING_BENEFIT_NAME_KEYS.get(
			profile.starting_benefit_id, ""))
		var benefit := Label.new()
		benefit.name = "StartingBenefit"
		benefit.text = tr("AIRCRAFT_STARTING_BENEFIT_FMT") % tr(benefit_name_key)
		benefit.add_theme_font_size_override("font_size", 11)
		benefit.add_theme_color_override("font_color", ThemeColors.UI_WARNING_YELLOW)
		benefit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		benefit.custom_minimum_size = Vector2(190, 0)
		benefit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inner.add_child(benefit)

	# 机体特性行（card_perks：数值级差异如强化机炮/经验加成；
	# 未解锁卡不展示——用户 2026-07-27，只给已解锁玩家看细账）
	if not locked and not dev_locked and profile:
		for perk_key in profile.card_perks:
			var perk := Label.new()
			perk.text = tr(perk_key)
			perk.add_theme_font_size_override("font_size", 11)
			perk.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6, 0.8))
			perk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			perk.custom_minimum_size = Vector2(190, 0)
			perk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			inner.add_child(perk)

	# Boss Debug 参考态：把进化档位、匹配等级与门槛 build 直接写在卡上。
	if not locked and profile and data.has("boss_debug_node_id"):
		var node_id := StringName(String(data["boss_debug_node_id"]))
		var axis_points := BossDebugBuilds.target_axis_points(
			node_id, int(data.get("boss_debug_level", 1)))
		var axis_parts: PackedStringArray = []
		for axis in SurvivorData.AXES:
			var points := int(axis_points.get(axis, 0))
			if points > 0:
				axis_parts.append("%s %d" % [
					tr(String(SurvivorData.AXIS_I18N_KEY[axis])), points])
		var reference := Label.new()
		reference.text = tr("BOSS_DEBUG_REFERENCE_FMT") % [
			int(data.get("boss_debug_level", 1)), " · ".join(axis_parts)]
		reference.add_theme_font_size_override("font_size", 11)
		reference.add_theme_color_override("font_color", ThemeColors.TEXT_TAG_UNLOCKED)
		reference.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reference.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reference.custom_minimum_size = Vector2(190, 0)
		inner.add_child(reference)

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
	desc_label.custom_minimum_size = Vector2(190, 0)
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
	btn.custom_minimum_size = Vector2(190, 40)
	btn.add_theme_font_size_override("font_size", 16)

	if locked or dev_locked:
		btn.disabled = true
		# 生涯门控卡（career-shop）：按钮显示解锁条件句；无条件句才落回"开发中/未解锁"
		if data.has("unlock_text"):
			btn.text = String(data["unlock_text"])
			btn.add_theme_font_size_override("font_size", 13)
		else:
			btn.text = tr("SLOT_DEV_LOCKED_BUTTON") if dev_locked else tr("SLOT_LOCKED_BUTTON")
		btn.disabled = true
	else:
		btn.text = tr("AIRCRAFT_SELECT_LAUNCH_BUTTON")
		var idx := index
		btn.pressed.connect(func(): _on_aircraft_selected(idx))
		btn.focus_entered.connect(func(): _show_aircraft_preview(idx))
	TerminalUiStyleScript.apply_button(btn, TerminalUiStyleScript.accent())

	inner.add_child(btn)

	_cards_container.add_child(panel)

# ══════════════════════════════════════════════
#  选择 & 进入游戏
# ══════════════════════════════════════════════

func _show_initial_preview() -> void:
	for i in range(_list.size()):
		var data: Dictionary = _list[i]
		if not data.get("locked", false) and not data.get("dev_locked", false):
			_show_aircraft_preview(i)
			return
	if not _list.is_empty():
		_show_aircraft_preview(0)


func _show_aircraft_preview(index: int) -> void:
	if index < 0 or index >= _list.size() or _hologram_preview == null:
		return
	_selected_index = index
	var data: Dictionary = _list[index]
	if data.get("locked", false) or data.get("dev_locked", false):
		_hologram_preview.call("show_locked", index, _list.size())
	else:
		var profile := _profile_by_index.get(index, null) as PlayableAircraft
		_hologram_preview.call("show_profile", profile, index, _list.size())
	_refresh_card_highlights()


func _refresh_card_highlights() -> void:
	for i in range(_card_panels.size()):
		var data: Dictionary = _list[i]
		var locked: bool = data.get("locked", false) or data.get("dev_locked", false)
		var active := i == _selected_index
		var border_alpha := 0.34 if locked and active else (0.20 if locked else (1.0 if active else 0.82))
		var background_alpha := 0.60 if active and not locked else (0.54 if locked else 0.80)
		TerminalUiStyleScript.apply_panel(
			_card_panels[i], Color(TerminalUiStyleScript.accent(), border_alpha),
			Color(0.0, 0.0, 0.0, background_alpha), 10.0, 2 if active else 1)

func _on_aircraft_selected(index: int) -> void:
	var data: Dictionary = _list[index] if index < _list.size() else PLAYABLE_LIST[index]
	if data.get("locked", false) or data.get("dev_locked", false):
		return
	# 通过 scene tree meta 传递选择的 PlayableAircraft 资源路径
	get_tree().set_meta("survivor_aircraft_resource", data["resource"])
	if data.has("boss_debug_node_id"):
		get_tree().set_meta("boss_debug_node_id", data["boss_debug_node_id"])
		get_tree().set_meta("boss_debug_level", int(data.get("boss_debug_level", 1)))
	# 直接出击（配件机库已随槽位配件系统退役，spec doctrine-unlocks §3.5）
	get_tree().change_scene_to_file("res://scenes/building_preloader.tscn")


func _on_back_from_select() -> void:
	if get_tree().has_meta("boss_debug_mode"):
		get_tree().change_scene_to_file("res://scenes/boss_debug_select.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/survivor_map_select.tscn")
