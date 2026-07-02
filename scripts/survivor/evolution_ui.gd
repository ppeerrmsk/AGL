class_name EvolutionUI
extends CanvasLayer

## 战区结算规划站（Phase 2，spec ace-system §2.4 + 用户反馈 2026-07-02）
## 双栏一体：左 = 机体进化（ACE 手动三选，僚机跟随）；右 = 强化当前机体（三选一升级）。
## 每栏各限选一次；"继续出击"关闭。锁定的进化出口灰显门槛（可视化练级目标）。
## 信号即时回传（选了立刻生效），closed 时 survivor_mode 恢复游戏。

signal evolution_chosen(node_id: StringName)
signal upgrade_chosen(upgrade: Dictionary)
signal closed()

const PANE_WIDTH := 340.0

var _panel: PanelContainer
var _root: VBoxContainer
var _evo_pane: VBoxContainer
var _up_pane: VBoxContainer
var _evo_picked: bool = false
var _up_picked: bool = false
var _evo_buttons: Array = []
var _up_buttons: Array = []

## 进化种类 → 主题色（左栏卡片染色）
const EVO_CAT_COLORS := {
	"air": ThemeColors.CATEGORY_MOBILITY,
	"ew": ThemeColors.CATEGORY_SYSTEM,
	"range": ThemeColors.CATEGORY_DEFENSE,
	"attack": ThemeColors.CATEGORY_WEAPON,
	"omni": ThemeColors.TEXT_ACCENT,
}
## 升级 category → 主题色（右栏卡片染色，对齐 HUD 战术按钮的分类色）
const UP_CAT_COLORS := {
	"survival": ThemeColors.CATEGORY_DEFENSE,
	"mobility": ThemeColors.CATEGORY_MOBILITY,
	"electronic_warfare": ThemeColors.CATEGORY_SYSTEM,
	"missile": ThemeColors.CATEGORY_WEAPON,
	"secondary": ThemeColors.CATEGORY_WEAPON,
	"weapon": ThemeColors.CATEGORY_WEAPON,
}

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停期间可交互
	visible = false
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.PANEL_BG_SOLID
	style.border_color = ThemeColors.PANEL_BORDER_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	_panel.add_child(_root)

## current = 当前节点（可为空 Dictionary）；exits = 进化出口；choices = 升级三选一（可为空）
func show_offer(current: Dictionary, exits: Array, team_level: int, choices: Array) -> void:
	_evo_picked = false
	_up_picked = false
	_evo_buttons.clear()
	_up_buttons.clear()
	for c in _root.get_children():
		c.queue_free()

	# ── 标题区 ──
	var title := Label.new()
	title.text = tr("SETTLEMENT_TITLE")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ThemeColors.TEXT_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)
	if not current.is_empty():
		var sub := Label.new()
		sub.text = tr("EVOLUTION_SUBTITLE_FMT") % tr(String(current.get("name_key", "")))
		sub.add_theme_font_size_override("font_size", 12)
		sub.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_root.add_child(sub)

	# ── 双栏 ──
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	_root.add_child(cols)
	_evo_pane = _make_pane(cols, tr("SETTLEMENT_EVO_HEADER"))
	_up_pane = _make_pane(cols, tr("SETTLEMENT_UPGRADE_HEADER"))

	# 左：进化出口（含锁定灰卡 = 练级目标可视化）
	if exits.is_empty():
		_add_empty_hint(_evo_pane, tr("SETTLEMENT_NO_EVO"))
	else:
		for nd in exits:
			var need: int = EvolutionSystem.min_level_of(nd)
			var col: Color = EVO_CAT_COLORS.get(nd.get("category", ""), ThemeColors.TEXT_PRIMARY)
			var head := "%s ｜ %s · T%d" % [
				tr(String(nd.get("name_key", ""))),
				tr(EvolutionSystem.category_key_of(nd)),
				int(nd.get("tier", 0))]
			var btn := _make_card_button(head, col)
			if team_level < need:
				btn.disabled = true
				btn.text += "\n" + tr("EVOLUTION_LOCKED_FMT") % need
			else:
				var nid := StringName(nd.get("id", ""))
				btn.pressed.connect(func() -> void: _pick_evo(nid, btn))
			_evo_pane.add_child(btn)
			_evo_buttons.append(btn)

	# 右：强化当前机体（升级三选一 + 描述）
	if choices.is_empty():
		_add_empty_hint(_up_pane, tr("SETTLEMENT_NO_UPGRADE"))
	else:
		for u in choices:
			var col: Color = UP_CAT_COLORS.get(String(u.get("category", "")), ThemeColors.TEXT_PRIMARY)
			var btn := _make_card_button(tr(String(u.get("name", ""))), col)
			var desc := Label.new()
			desc.text = tr(String(u.get("desc", "")))
			desc.add_theme_font_size_override("font_size", 11)
			desc.add_theme_color_override("font_color", ThemeColors.TEXT_DESC_UNLOCKED)
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.custom_minimum_size = Vector2(PANE_WIDTH - 16, 0)
			var up_copy: Dictionary = u
			btn.pressed.connect(func() -> void: _pick_upgrade(up_copy, btn))
			_up_pane.add_child(btn)
			_up_pane.add_child(desc)
			_up_buttons.append(btn)

	# ── 底部：继续出击 ──
	var done := Button.new()
	done.text = tr("SETTLEMENT_CONTINUE")
	done.add_theme_font_size_override("font_size", 15)
	done.custom_minimum_size = Vector2(220, 40)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(_close)
	_root.add_child(done)

	visible = true
	_center.call_deferred()

func _make_pane(parent: HBoxContainer, header_text: String) -> VBoxContainer:
	var pane := VBoxContainer.new()
	pane.add_theme_constant_override("separation", 6)
	pane.custom_minimum_size = Vector2(PANE_WIDTH, 0)
	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", ThemeColors.TEXT_TITLE_GREEN)
	pane.add_child(header)
	var sep := HSeparator.new()
	pane.add_child(sep)
	parent.add_child(pane)
	return pane

func _make_card_button(text_: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text_
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", accent)
	btn.add_theme_color_override("font_hover_color", accent.lightened(0.3))
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(PANE_WIDTH - 8, 40)
	btn.clip_text = false
	return btn

func _add_empty_hint(pane: VBoxContainer, text_: String) -> void:
	var lbl := Label.new()
	lbl.text = text_
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_LOCKED)
	pane.add_child(lbl)

func _pick_evo(node_id: StringName, btn: Button) -> void:
	if _evo_picked:
		return
	_evo_picked = true
	for b in _evo_buttons:
		b.disabled = true
	btn.text = tr("SETTLEMENT_PICKED_FMT") % btn.text
	evolution_chosen.emit(node_id)

func _pick_upgrade(upgrade: Dictionary, btn: Button) -> void:
	if _up_picked:
		return
	_up_picked = true
	for b in _up_buttons:
		b.disabled = true
	btn.text = tr("SETTLEMENT_PICKED_FMT") % btn.text
	upgrade_chosen.emit(upgrade)

func _center() -> void:
	var vp := _panel.get_viewport_rect().size
	_panel.position = (vp - _panel.size) * 0.5

func _close() -> void:
	visible = false
	closed.emit()
