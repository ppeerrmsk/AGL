class_name EvolutionUI
extends CanvasLayer

## 机场停靠规划站：当前机体签名技与进化严格二选一。
##
## 左栏 = 进化树；中栏 = 当前/目标机详情；右栏 = 明确的地勤决策台。
## 专属技能不再进入等级三轴抽选。许可已购且本局尚未取得时，选择保留当前机体会
## 立即装备当前机体专属技能；选择任一可用进化则放弃本次停靠的专属装备机会。

signal evolution_chosen(node_id: StringName)
signal signature_chosen(upgrade: Dictionary)
signal closed()

const DECISION_WIDTH := 380.0
const DETAIL_WIDTH := 440.0
const SCREEN_MARGIN := 32.0
const SIGNATURE_COLOR := Color(1.00, 0.25, 0.75)
const TERMINAL_COLOR := ThemeColors.UI_TERMINAL_WHITE

var _panel: PanelContainer
var _root: VBoxContainer
var _evo_pane: VBoxContainer
var _detail_pane: VBoxContainer
var _decision_pane: VBoxContainer
var _tree: EvolutionTreeView
var _detail: EvolutionDetailPanel
var _evo_confirm: Button
var _signature_confirm: Button
var _evo_target_label: Label
var _subtitle: Label
var _done_button: Button
var _evo_selected: StringName = &""
var _current_id: StringName = &""
var _team_level: int = 1
var _axis_points: Dictionary = {}
var _decision_committed: bool = false
var _signature_ready: bool = false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_style(TERMINAL_COLOR, 1, 18.0))
	add_child(_panel)
	# 锚死四边；大树只能在 ScrollContainer 内增长，不能再次用内容尺寸手动居中。
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = SCREEN_MARGIN
	_panel.offset_top = SCREEN_MARGIN
	_panel.offset_right = -SCREEN_MARGIN
	_panel.offset_bottom = -SCREEN_MARGIN
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	_panel.add_child(_root)


## current = 当前节点；exits = 进化出口；signature = 当前机体专属技能。
## signature_license_owned 只表示局外许可；signature_equipped 表示本局玩家层账本已持有。
func show_offer(current: Dictionary, exits: Array, team_level: int, signature: Dictionary,
		signature_license_owned: bool, signature_equipped: bool, history: Array = [],
		axis_points: Dictionary = {}, milestone_bonus: Dictionary = {}) -> void:
	_decision_committed = false
	_evo_selected = &""
	_subtitle = null
	_current_id = StringName(current.get("id", ""))
	_team_level = team_level
	_axis_points = axis_points
	_signature_ready = not signature.is_empty() \
		and not SurvivorData.is_signature_placeholder(signature) \
		and signature_license_owned and not signature_equipped
	for c in _root.get_children():
		c.queue_free()
		_root.remove_child(c)

	_build_title(current)
	_build_decision_banner()

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(cols)
	_evo_pane = _make_pane(cols, tr("SETTLEMENT_EVO_HEADER"), 0.0)
	_evo_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_pane = _make_pane(cols, tr("SETTLEMENT_DETAIL_HEADER"), DETAIL_WIDTH)
	_decision_pane = _make_pane(cols, tr("SETTLEMENT_DECISION_HEADER"), DECISION_WIDTH)

	_build_tree(exits, history, team_level, axis_points)
	_build_detail(team_level, axis_points)
	_build_decision_console(current, signature, signature_license_owned, signature_equipped,
		milestone_bonus)

	_done_button = Button.new()
	_done_button.custom_minimum_size = Vector2(260, 42)
	_done_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_button(_done_button, TERMINAL_COLOR)
	if _signature_ready:
		# “继续出击”不能成为空手跳过奖励的第三条路；有待领取技能时，
		# 底部主按钮就是方案 A 的快捷入口，并走同一权威授予信号。
		_done_button.text = tr("SETTLEMENT_RETAIN_CONFIRM")
		var signature_copy: Dictionary = signature.duplicate(true)
		_done_button.pressed.connect(
			func() -> void: _confirm_signature(signature_copy))
	else:
		_done_button.text = tr("SETTLEMENT_CONTINUE")
		_done_button.pressed.connect(_close)
	_root.add_child(_done_button)


func _build_title(current: Dictionary) -> void:
	var title := Label.new()
	title.text = tr("SETTLEMENT_TITLE")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TERMINAL_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)
	if current.is_empty():
		return
	_subtitle = Label.new()
	_subtitle.text = tr("EVOLUTION_SUBTITLE_FMT") % tr(String(current.get("name_key", "")))
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_subtitle)


func _build_decision_banner() -> void:
	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", _panel_style(TERMINAL_COLOR, 1, 8.0))
	var label := Label.new()
	label.text = tr("SETTLEMENT_DECISION_BANNER")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", TERMINAL_COLOR)
	banner.add_child(label)
	_root.add_child(banner)


func _build_tree(exits: Array, history: Array, team_level: int, axis_points: Dictionary) -> void:
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
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_evo_pane.add_child(hint)


func _build_detail(team_level: int, axis_points: Dictionary) -> void:
	_detail = EvolutionDetailPanel.new()
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.add_child(_detail)
	_detail_pane.add_child(detail_scroll)
	if _current_id != &"":
		_detail.show_node(_current_id, _current_id, team_level, axis_points)


func _build_decision_console(current: Dictionary, signature: Dictionary,
		signature_license_owned: bool, signature_equipped: bool,
		milestone_bonus: Dictionary) -> void:
	var bars := AxisBarsPanel.new()
	bars.show_state(_axis_points, null, milestone_bonus)
	bars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_decision_pane.add_child(bars)

	_build_signature_card(current, signature, signature_license_owned, signature_equipped)
	var or_label := Label.new()
	or_label.text = tr("SETTLEMENT_DECISION_OR")
	or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	or_label.add_theme_font_size_override("font_size", 12)
	or_label.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_decision_pane.add_child(or_label)
	_build_evolution_card()


func _build_signature_card(current: Dictionary, signature: Dictionary,
		signature_license_owned: bool, signature_equipped: bool) -> void:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 6)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel_style(
		SIGNATURE_COLOR if _signature_ready else ThemeColors.TEXT_LOCKED, 2, 10.0,
		Color(SIGNATURE_COLOR, 0.10) if _signature_ready else ThemeColors.UI_BLOCK_BACKGROUND))
	frame.add_child(card)
	_decision_pane.add_child(frame)

	card.add_child(_label(tr("SETTLEMENT_RETAIN_OPTION"), 11,
		SIGNATURE_COLOR if _signature_ready else ThemeColors.TEXT_MUTED))
	card.add_child(_label(tr(String(current.get("name_key", ""))), 16, TERMINAL_COLOR, true))
	if signature.is_empty():
		card.add_child(_label(tr("SETTLEMENT_SIGNATURE_MISSING"), 11, ThemeColors.UI_DANGER_RED, true))
	else:
		card.add_child(_label(tr(String(signature.get("name", ""))), 15, SIGNATURE_COLOR, true))
		card.add_child(_label(tr(String(signature.get("desc", ""))), 11,
			ThemeColors.TEXT_DESC_UNLOCKED, true))
	var status_key := "SETTLEMENT_SIGNATURE_READY"
	var status_color := SIGNATURE_COLOR
	if signature.is_empty():
		status_key = "SETTLEMENT_SIGNATURE_MISSING"
		status_color = ThemeColors.UI_DANGER_RED
	elif SurvivorData.is_signature_placeholder(signature):
		status_key = "SETTLEMENT_SIGNATURE_RESERVED"
		status_color = ThemeColors.TEXT_MUTED
	elif signature_equipped:
		status_key = "SETTLEMENT_SIGNATURE_EQUIPPED"
		status_color = ThemeColors.HP_OK
	elif not signature_license_owned:
		status_key = "SETTLEMENT_SIGNATURE_LICENSE_REQUIRED"
		status_color = ThemeColors.UI_WARNING_YELLOW
	card.add_child(_label(tr(status_key), 11, status_color, true))

	_signature_confirm = Button.new()
	_signature_confirm.text = tr("SETTLEMENT_RETAIN_CONFIRM")
	_signature_confirm.custom_minimum_size = Vector2(DECISION_WIDTH - 42.0, 42)
	_signature_confirm.disabled = not _signature_ready
	_style_button(_signature_confirm, SIGNATURE_COLOR)
	if _signature_ready:
		var signature_copy: Dictionary = signature.duplicate(true)
		_signature_confirm.pressed.connect(
			func() -> void: _confirm_signature(signature_copy))
	card.add_child(_signature_confirm)


func _build_evolution_card() -> void:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 6)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel_style(TERMINAL_COLOR, 1, 10.0))
	frame.add_child(card)
	_decision_pane.add_child(frame)
	card.add_child(_label(tr("SETTLEMENT_EVOLVE_OPTION"), 11, TERMINAL_COLOR))
	_evo_target_label = _label(tr("SETTLEMENT_EVOLVE_SELECT_TARGET"), 12,
		ThemeColors.TEXT_MUTED, true)
	card.add_child(_evo_target_label)
	_evo_confirm = Button.new()
	_evo_confirm.text = tr("EVOLUTION_CONFIRM")
	_evo_confirm.disabled = true
	_evo_confirm.custom_minimum_size = Vector2(DECISION_WIDTH - 42.0, 42)
	_style_button(_evo_confirm, TERMINAL_COLOR)
	_evo_confirm.pressed.connect(_confirm_evolution)
	card.add_child(_evo_confirm)


func _make_pane(parent: HBoxContainer, header_text: String, min_w: float) -> VBoxContainer:
	var pane := VBoxContainer.new()
	pane.add_theme_constant_override("separation", 6)
	if min_w > 0.0:
		pane.custom_minimum_size = Vector2(min_w, 0)
	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", TERMINAL_COLOR)
	pane.add_child(header)
	pane.add_child(HSeparator.new())
	parent.add_child(pane)
	return pane


func _on_tree_node_selected(node_id: StringName) -> void:
	if _decision_committed:
		return
	_detail.show_node(node_id, _current_id, _team_level, _axis_points)
	if _tree.can_evolve(node_id):
		_evo_selected = node_id
		_evo_confirm.disabled = false
		var nd := EvolutionSystem.node_of(node_id)
		_evo_target_label.text = tr("SETTLEMENT_EVOLVE_TARGET_FMT") % tr(
			String(nd.get("name_key", "")))
		_evo_target_label.add_theme_color_override("font_color", TERMINAL_COLOR)
	else:
		_evo_selected = &""
		_evo_confirm.disabled = true
		_evo_target_label.text = tr("SETTLEMENT_EVOLVE_SELECT_TARGET")
		_evo_target_label.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)


func _confirm_evolution() -> void:
	if _decision_committed or _evo_selected == &"":
		return
	_decision_committed = true
	_lock_decision_controls()
	evolution_chosen.emit(_evo_selected)


func _confirm_signature(signature: Dictionary) -> void:
	if _decision_committed or not _signature_ready or signature.is_empty():
		return
	_decision_committed = true
	_lock_decision_controls()
	signature_chosen.emit(signature)


func _lock_decision_controls() -> void:
	if _tree:
		_tree.interactive = false
	if _evo_confirm:
		_evo_confirm.disabled = true
	if _signature_confirm:
		_signature_confirm.disabled = true
	if _done_button:
		_done_button.disabled = true


## 权威层拒绝了已提交的选择时恢复输入，避免防御性校验失败后把停靠面板锁死。
func reject_decision() -> void:
	_decision_committed = false
	if _tree:
		_tree.interactive = true
	if _signature_confirm:
		_signature_confirm.disabled = not _signature_ready
	if _done_button:
		_done_button.disabled = false
	_evo_selected = &""
	if _evo_confirm:
		_evo_confirm.disabled = true
	if _evo_target_label:
		_evo_target_label.text = tr("SETTLEMENT_EVOLVE_SELECT_TARGET")
		_evo_target_label.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)


func _style_button(button: Button, accent: Color) -> void:
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", ThemeColors.UI_TERMINAL_INVERSE)
	button.add_theme_color_override("font_pressed_color", ThemeColors.UI_TERMINAL_INVERSE)
	button.add_theme_color_override("font_disabled_color", ThemeColors.TEXT_LOCKED)
	button.add_theme_stylebox_override("normal", _panel_style(accent, 1, 8.0))
	button.add_theme_stylebox_override("hover", _panel_style(accent, 1, 8.0, Color(accent, 0.92)))
	button.add_theme_stylebox_override("pressed", _panel_style(accent, 1, 8.0, Color(accent, 0.72)))
	button.add_theme_stylebox_override("disabled", _panel_style(ThemeColors.TEXT_LOCKED, 1, 8.0))


func _panel_style(border: Color, width: int, margin: float,
		background: Color = ThemeColors.UI_BLOCK_BACKGROUND) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_content_margin_all(margin)
	return style


func _label(text_: String, size: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text_
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _close() -> void:
	closed.emit()


func get_transition_elements() -> Array[Control]:
	var out: Array[Control] = []
	if _root:
		out.append(_root)
	return out
