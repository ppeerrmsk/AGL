class_name EvolutionUI
extends CanvasLayer

## 战区结算规划站（Phase 2/3，spec ace-system §2.4 + 用户反馈 2026-07-03）
## 左栏 = 机体进化树（EvolutionTreeView，皇牌空战式自下而上：亮色可进化/灰色未解锁/金色爬线历史），
## 点击亮色机体 → 底部显示 机型·种类·档位·LV·武器清单 → [进化] 确认。
## 右栏 = 强化当前机体（三选一升级）。各限一次；"继续出击"关闭。

signal evolution_chosen(node_id: StringName)
signal upgrade_chosen(upgrade: Dictionary)
signal closed()

const PANE_WIDTH := 340.0

var _panel: PanelContainer
var _root: VBoxContainer
var _evo_pane: VBoxContainer
var _up_pane: VBoxContainer
var _tree: EvolutionTreeView
var _evo_info: Label
var _evo_confirm: Button
var _evo_selected: StringName = &""
var _evo_picked: bool = false
var _up_picked: bool = false
var _up_buttons: Array = []

## 进化种类 → 主题色（详情行染色）
const EVO_CAT_COLORS := {
	"air": ThemeColors.CATEGORY_MOBILITY,
	"ew": ThemeColors.CATEGORY_SYSTEM,
	"range": ThemeColors.CATEGORY_DEFENSE,
	"attack": ThemeColors.CATEGORY_WEAPON,
	"omni": ThemeColors.TEXT_ACCENT,
}
## 升级 category → 主题色（右栏卡片，对齐 HUD 分类色）
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

## current = 当前节点（可空）；exits = 出口；choices = 升级三选一；history = 爬线历史（节点 id 序列）；
## axis_points = 三轴属性点（属性门槛缺口显示，spec evolution-attribute-gates）
func show_offer(current: Dictionary, exits: Array, team_level: int, choices: Array, history: Array = [], axis_points: Dictionary = {}) -> void:
	_evo_picked = false
	_up_picked = false
	_evo_selected = &""
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
	_evo_pane = _make_pane(cols, tr("SETTLEMENT_EVO_HEADER"), 0.0)  # 宽度随树自适应
	_up_pane = _make_pane(cols, tr("SETTLEMENT_UPGRADE_HEADER"), PANE_WIDTH)

	# 左：进化树视图（皇牌空战式，自下而上）
	_tree = EvolutionTreeView.new()
	_tree.setup(EvolutionSystem.all_nodes(), StringName(current.get("id", "")), history, team_level, axis_points)
	_tree.node_selected.connect(_on_tree_node_selected)
	_evo_pane.add_child(_tree)
	var hint := Label.new()
	hint.text = tr("EVOLUTION_TREE_HINT") if not exits.is_empty() else tr("SETTLEMENT_NO_EVO")
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_evo_pane.add_child(hint)
	_evo_info = Label.new()
	_evo_info.text = ""
	_evo_info.add_theme_font_size_override("font_size", 12)
	_evo_info.add_theme_color_override("font_color", ThemeColors.TEXT_PRIMARY)
	_evo_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_evo_pane.add_child(_evo_info)
	_evo_confirm = Button.new()
	_evo_confirm.text = tr("EVOLUTION_CONFIRM")
	_evo_confirm.disabled = true
	_evo_confirm.add_theme_font_size_override("font_size", 14)
	_evo_confirm.custom_minimum_size = Vector2(180, 34)
	_evo_confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_evo_confirm.pressed.connect(_confirm_evolution)
	_evo_pane.add_child(_evo_confirm)

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

func _make_pane(parent: HBoxContainer, header_text: String, min_w: float) -> VBoxContainer:
	var pane := VBoxContainer.new()
	pane.add_theme_constant_override("separation", 6)
	if min_w > 0.0:
		pane.custom_minimum_size = Vector2(min_w, 0)
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

## 树上点了亮色机体 → 底部详情 + 解锁确认按钮
func _on_tree_node_selected(node_id: StringName) -> void:
	if _evo_picked:
		return
	_evo_selected = node_id
	var nd := EvolutionSystem.node_of(node_id)
	var prof := AircraftDB.get_profile(StringName(nd.get("profile", "")))
	var wpn := AircraftDB.weapons_summary(prof)
	_evo_info.text = "%s ｜ %s · T%d ｜ LV %d\n%s" % [
		tr(String(nd.get("name_key", ""))),
		tr(EvolutionSystem.category_key_of(nd)),
		int(nd.get("tier", 0)),
		EvolutionSystem.min_level_of(nd),
		wpn]
	_evo_info.add_theme_color_override("font_color",
		EVO_CAT_COLORS.get(nd.get("category", ""), ThemeColors.TEXT_PRIMARY))
	_evo_confirm.disabled = false

func _confirm_evolution() -> void:
	if _evo_picked or _evo_selected == &"":
		return
	_evo_picked = true
	_tree.interactive = false
	_evo_confirm.disabled = true
	_evo_confirm.text = tr("SETTLEMENT_PICKED_FMT") % _evo_confirm.text
	evolution_chosen.emit(_evo_selected)

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
