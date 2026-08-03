class_name EvolutionUI
extends CanvasLayer

## 战区结算规划站（Phase 2/3，spec ace-system §2.4 + 用户反馈 2026-07-03）
## 三栏布局（2026-07-20 用户反馈重排）：
##   左 = 机体进化树（EvolutionTreeView，皇牌空战式自下而上：亮色可进化/灰色未解锁/金色爬线历史），
##        套 ScrollContainer —— 树宽随节点数增长，禁止再让它撑爆面板。
##   中 = 机体详情卡（EvolutionDetailPanel）：开局摊开**当前机**，点树上任意已揭示机体即切换；
##        含 特性对比（相对当前机的属性增减）+ 进化需求（等级门 / 三轴属性门 逐条 have/need）。
##   右 = 三轴量表 + 强化当前机体（三选一升级）。
## 进化与强化各限一次；"继续出击"关闭。
## 面板本身铺满视口（PRESET_FULL_RECT + 留边），不做手动居中——旧的 _center() 在树超宽时给出负坐标，
## 导致"进化到第二架后画面整体上移"（用户 2026-07-20 反馈的 bug）。

signal evolution_chosen(node_id: StringName)
signal upgrade_chosen(upgrade: Dictionary)
signal closed()

const PANE_WIDTH := 340.0
const DETAIL_WIDTH := 440.0
const SCREEN_MARGIN := 32.0    ## 面板四边留白（面板本身铺满视口，靠内部滚动容纳大树）

var _panel: PanelContainer
var _root: VBoxContainer
var _evo_pane: VBoxContainer
var _detail_pane: VBoxContainer
var _up_pane: VBoxContainer
var _tree: EvolutionTreeView
var _detail: EvolutionDetailPanel
var _evo_confirm: Button
var _subtitle: Label
var _evo_selected: StringName = &""
var _current_id: StringName = &""
var _team_level: int = 1
var _axis_points: Dictionary = {}
var _evo_picked: bool = false
var _up_picked: bool = false
var _up_buttons: Array = []

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
	# 面板铺满视口（留边），大树靠内部 ScrollContainer 滚动。
	# ⚠ 不要退回"按 size 手动居中"：树宽随档位节点数增长（T2 已 15 格 ≈1.6k px），
	# 一旦超出视口，居中公式给出负坐标 → 画面整体上移/左移（用户 2026-07-20 反馈的 bug）
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = SCREEN_MARGIN
	_panel.offset_top = SCREEN_MARGIN
	_panel.offset_right = -SCREEN_MARGIN
	_panel.offset_bottom = -SCREEN_MARGIN
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	_panel.add_child(_root)

## current = 当前节点（可空）；exits = 出口；choices = 升级三选一；history = 爬线历史（节点 id 序列）；
## axis_points = 三轴属性点（属性门槛缺口显示，spec evolution-attribute-gates）
func show_offer(current: Dictionary, exits: Array, team_level: int, choices: Array, history: Array = [], axis_points: Dictionary = {}, milestone_bonus: Dictionary = {}) -> void:
	_evo_picked = false
	_up_picked = false
	_evo_selected = &""
	_subtitle = null
	_up_buttons.clear()
	_current_id = StringName(current.get("id", ""))
	_team_level = team_level
	_axis_points = axis_points
	for c in _root.get_children():
		c.queue_free()
		_root.remove_child(c)  # 立即摘出：queue_free 是延迟的，留着会让容器按旧内容算尺寸

	# ── 标题区 ──
	var title := Label.new()
	title.text = tr("SETTLEMENT_TITLE")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ThemeColors.TEXT_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)
	if not current.is_empty():
		_subtitle = Label.new()
		_subtitle.text = tr("EVOLUTION_SUBTITLE_FMT") % tr(String(current.get("name_key", "")))
		_subtitle.add_theme_font_size_override("font_size", 12)
		_subtitle.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_root.add_child(_subtitle)

	# ── 三栏：进化树 / 机体详情 / 强化 ──
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(cols)
	_evo_pane = _make_pane(cols, tr("SETTLEMENT_EVO_HEADER"), 0.0)  # 宽度吃剩余空间
	_evo_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_pane = _make_pane(cols, tr("SETTLEMENT_DETAIL_HEADER"), DETAIL_WIDTH)
	_up_pane = _make_pane(cols, tr("SETTLEMENT_UPGRADE_HEADER"), PANE_WIDTH)

	# 三轴量表（竖条分格 + 里程碑刻度圈，2026-07-19 用户 mockup）：
	# 强化栏迁回等级流后，右栏顶部改陈列点数分配现状——选进化目标时门槛差多少一目了然
	var bars := AxisBarsPanel.new()
	bars.show_state(axis_points, null, milestone_bonus)
	bars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_up_pane.add_child(bars)

	# 左：进化树视图（皇牌空战式，自下而上）——套 ScrollContainer，树再大也不顶飞面板
	_tree = EvolutionTreeView.new()
	_tree.setup(EvolutionSystem.all_nodes(), _current_id, history, team_level, axis_points)
	_tree.node_selected.connect(_on_tree_node_selected)
	var tree_scroll := ScrollContainer.new()
	tree_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_scroll.custom_minimum_size = Vector2(520, 340)
	tree_scroll.add_child(_tree)
	_evo_pane.add_child(tree_scroll)
	var hint := Label.new()
	hint.text = tr("EVOLUTION_TREE_HINT") if not exits.is_empty() else tr("SETTLEMENT_NO_EVO")
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_evo_pane.add_child(hint)
	_evo_confirm = Button.new()
	_evo_confirm.text = tr("EVOLUTION_CONFIRM")
	_evo_confirm.disabled = true
	_evo_confirm.add_theme_font_size_override("font_size", 14)
	_evo_confirm.custom_minimum_size = Vector2(180, 34)
	_evo_confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_evo_confirm.pressed.connect(_confirm_evolution)
	_evo_pane.add_child(_evo_confirm)

	# 中：机体详情卡（默认先摊开当前机——"我现在开的是什么、什么水平"，用户 2026-07-20）
	_detail = EvolutionDetailPanel.new()
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.add_child(_detail)
	_detail_pane.add_child(detail_scroll)
	if _current_id != &"":
		_detail.show_node(_current_id, _current_id, team_level, axis_points)

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
	# 显示与入场动画由 Presentation.present() 驱动（survivor_mode._open_evolution_offer）

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

## 树上点了任意已揭示机体 → 中栏详情卡（特性 + 需求）；只有真能进化时才放行确认按钮
func _on_tree_node_selected(node_id: StringName) -> void:
	if _evo_picked:
		return
	_detail.show_node(node_id, _current_id, _team_level, _axis_points)
	if _tree.can_evolve(node_id):
		_evo_selected = node_id
		_evo_confirm.disabled = false
	else:
		_evo_selected = &""
		_evo_confirm.disabled = true

func _confirm_evolution() -> void:
	if _evo_picked or _evo_selected == &"":
		return
	_evo_picked = true
	_tree.interactive = false
	_evo_confirm.disabled = true
	_evo_confirm.text = tr("SETTLEMENT_PICKED_FMT") % _evo_confirm.text
	evolution_chosen.emit(_evo_selected)

## 权威换型成功后同步仍打开的规划站：当前框、标题和详情一并迁到新机体。
func mark_evolution_applied(node_id: StringName, history: Array) -> void:
	_current_id = node_id
	_evo_selected = &""
	if _tree:
		_tree.set_current(node_id, history)
	var nd := EvolutionSystem.node_of(node_id)
	if _subtitle and not nd.is_empty():
		_subtitle.text = tr("EVOLUTION_SUBTITLE_FMT") % tr(String(nd.get("name_key", "")))
	if _detail:
		_detail.show_node(node_id, node_id, _team_level, _axis_points)

func _pick_upgrade(upgrade: Dictionary, btn: Button) -> void:
	if _up_picked:
		return
	_up_picked = true
	for b in _up_buttons:
		b.disabled = true
	btn.text = tr("SETTLEMENT_PICKED_FMT") % btn.text
	upgrade_chosen.emit(upgrade)

## 只发信号，【不自己隐藏】——退场由 survivor_mode 走 Presentation.dismiss() 驱动
func _close() -> void:
	closed.emit()

## 表演导演的错开出入场元素（spec ui-transition §4.3）
func get_transition_elements() -> Array[Control]:
	var out: Array[Control] = []
	if _root:
		out.append(_root)
	return out
