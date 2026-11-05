class_name EvolutionUI
extends CanvasLayer

## 停靠决策台：路线呈现位置、方向与可选状态；机体说明放入悬停浮窗。
signal evolution_chosen(node_id: StringName)
signal repair_chosen()
signal wingman_chosen()

const DECISION_WIDTH := 400.0
const DETAIL_WIDTH := 560.0
const SCREEN_MARGIN := 36.0
var _terminal_color: Color = HudPreferences.hud_color()
var _panel: PanelContainer
var _root: VBoxContainer
var _evo_pane: VBoxContainer
var _decision_pane: VBoxContainer
var _tree: EvolutionTreeView
var _tree_scroll: ScrollContainer
var _detail: EvolutionDetailPanel
var _popover: PanelContainer
var _popover_scroll: ScrollContainer
var _hover_timer: Timer
var _hover_node: StringName = &""
var _evo_confirm: Button
var _repair_confirm: Button
var _wingman_confirm: Button
var _evo_target_label: TerminalText
var _subtitle: TerminalText
var _evo_selected: StringName = &""
var _current_id: StringName = &""
var _team_level: int = 1
var _axis_points: Dictionary = {}
var _decision_committed := false
var _signature_ready := false
var _evolution_ready := false
var _wingman_ready := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_style(_terminal_color, 18.0))
	add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = SCREEN_MARGIN
	_panel.offset_top = SCREEN_MARGIN
	_panel.offset_right = -SCREEN_MARGIN
	_panel.offset_bottom = -SCREEN_MARGIN
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 18)
	_panel.add_child(_root)
	_build_detail()
	visibility_changed.connect(_hide_popover)
	_panel.resized.connect(_hide_popover)


func show_offer(current: Dictionary, exits: Array, team_level: int, signature: Dictionary,
		signature_license_owned: bool, signature_equipped: bool, history: Array = [],
		axis_points: Dictionary = {}, _milestone_bonus: Dictionary = {},
		wingman_license_owned: bool = true, wingman_has_space: bool = true) -> void:
	_hide_popover()
	_terminal_color = HudPreferences.hud_color()
	_panel.add_theme_stylebox_override("panel", _panel_style(_terminal_color, 18.0))
	_popover.add_theme_stylebox_override("panel", _panel_style(_terminal_color, 18.0, Color(0, 0, 0, 0.98)))
	_decision_committed = false
	_evo_selected = &""
	_current_id = StringName(current.get("id", ""))
	_team_level = team_level
	_axis_points = axis_points
	_evolution_ready = EvolutionSystem.has_available_exit(_current_id, team_level, axis_points)
	_wingman_ready = wingman_license_owned and wingman_has_space
	_evo_confirm = null
	_repair_confirm = null
	_wingman_confirm = null
	_evo_target_label = null
	_signature_ready = not signature.is_empty() and not SurvivorData.is_signature_placeholder(signature) \
		and signature_license_owned and not signature_equipped
	for child in _root.get_children():
		_root.remove_child(child)
		child.queue_free()
	_build_title(current)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(columns)
	_evo_pane = _make_pane(columns, tr("SETTLEMENT_EVO_HEADER"), 320.0)
	_evo_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var decisions_scroll := ScrollContainer.new()
	decisions_scroll.custom_minimum_size.x = DECISION_WIDTH + 18.0
	decisions_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(decisions_scroll)
	_decision_pane = _make_pane(decisions_scroll, tr("EVO_CHOOSE_ONE"), DECISION_WIDTH)
	_build_tree(exits, history)
	_build_decision_console(current, signature, signature_license_owned, signature_equipped,
		wingman_license_owned, wingman_has_space)
	if is_inside_tree():
		_focus_current.call_deferred()


func _build_title(current: Dictionary) -> void:
	_root.add_child(_text(tr("EVO_STATION_TITLE"), 36.0, _terminal_color))
	_subtitle = _text(tr("EVO_STATION_CONTEXT") % [
		tr(String(current.get("name_key", ""))), _team_level], 18.0, _terminal_color)
	_root.add_child(_subtitle)


func _build_tree(exits: Array, history: Array) -> void:
	var attributes := HBoxContainer.new()
	attributes.add_theme_constant_override("separation", 18)
	for axis in SurvivorData.AXES:
		var readout := _text("%s %d" % [tr(str(SurvivorData.AXIS_I18N_KEY[axis])),
			int(_axis_points.get(axis, 0))], 18.0, Color(_terminal_color, 0.65))
		readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		attributes.add_child(readout)
	_evo_pane.add_child(attributes)
	_tree = EvolutionTreeView.new()
	_tree.setup(EvolutionSystem.all_nodes(), _current_id, history, _team_level, _axis_points)
	_tree.node_selected.connect(_on_tree_node_selected)
	_tree.node_hovered.connect(_on_tree_node_hovered)
	_tree_scroll = ScrollContainer.new()
	_tree_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_scroll.custom_minimum_size = Vector2(320, 180)
	_tree_scroll.add_child(_tree)
	_tree_scroll.get_h_scroll_bar().value_changed.connect(_on_tree_scrolled)
	_tree_scroll.get_v_scroll_bar().value_changed.connect(_on_tree_scrolled)
	_evo_pane.add_child(_tree_scroll)
	_evo_pane.add_child(_text(tr("EVO_TREE_HELP") if not exits.is_empty()
		else tr("SETTLEMENT_NO_EVO"), 18.0, Color(_terminal_color, 0.65)))


func _focus_current() -> void:
	if not is_instance_valid(_tree) or not _tree._rects.has(_current_id):
		return
	var current_rect: Rect2 = _tree._rects[_current_id]
	_tree_scroll.scroll_horizontal = maxi(0, int(current_rect.get_center().x - _tree_scroll.size.x * 0.5))
	_tree_scroll.scroll_vertical = maxi(0, int(current_rect.end.y - _tree_scroll.size.y + 18.0))


func _build_decision_console(current: Dictionary, signature: Dictionary,
		signature_license_owned: bool, signature_equipped: bool,
		wingman_license_owned: bool, wingman_has_space: bool) -> void:
	if _evolution_ready:
		_build_evolution_card()
	else:
		_build_signature_card(current, signature, signature_license_owned, signature_equipped)
	_decision_pane.add_child(_text(tr("EVO_OR"), 36.0, Color(_terminal_color, 0.65)))
	_build_wingman_card(wingman_license_owned, wingman_has_space)


func _build_evolution_card() -> void:
	var card := _card(tr("EVO_REFIT"))
	card.add_child(_text(tr("EVOLUTION_TITLE"), 36.0, _terminal_color))
	card.add_child(_text(tr("EVO_FULL_REPAIR"), 18.0, _terminal_color))
	_evo_target_label = _text(tr("EVO_PICK_TARGET"), 36.0, Color(_terminal_color, 0.65))
	card.add_child(_evo_target_label)
	_evo_confirm = _button(tr("EVO_CONFIRM_TARGET"), _confirm_evolution)
	_evo_confirm.disabled = true
	card.add_child(_evo_confirm)


func _build_signature_card(current: Dictionary, signature: Dictionary,
		signature_license_owned: bool, signature_equipped: bool) -> void:
	var card := _card(tr("EVO_REFIT"))
	card.add_child(_text(tr("SETTLEMENT_REPAIR_CONFIRM"), 36.0, _terminal_color))
	card.add_child(_text(tr("EVO_KEEP_AIRFRAME"), 18.0, Color(_terminal_color, 0.65)))
	var skill_text := tr(String(signature.get("name", ""))) if _signature_ready \
		else tr(String(current.get("name_key", "")))
	card.add_child(_text(skill_text, 36.0, _terminal_color))
	var status_key := "EVO_SIGNATURE_INCLUDED"
	if signature.is_empty() or SurvivorData.is_signature_placeholder(signature):
		status_key = "EVO_SIGNATURE_UNAVAILABLE"
	elif signature_equipped:
		status_key = "EVO_SIGNATURE_OWNED"
	elif not signature_license_owned:
		status_key = "EVO_SIGNATURE_LOCKED"
	card.add_child(_text(tr(status_key), 18.0, Color(_terminal_color, 0.65)))
	card.mouse_entered.connect(func() -> void:
		_on_tree_node_hovered(_current_id, card.get_global_rect()))
	card.mouse_exited.connect(_schedule_hide_popover)
	_repair_confirm = _button(tr("EVO_CONFIRM_REPAIR"), _confirm_repair)
	card.add_child(_repair_confirm)


func _build_wingman_card(license_owned: bool, has_space: bool) -> void:
	var card := _card(tr("EVO_REINFORCE"))
	card.add_child(_text(tr("EVO_ADD_WINGMAN"), 36.0, _terminal_color))
	card.add_child(_text(tr("EVO_SAME_AIRFRAME"), 18.0, Color(_terminal_color, 0.65)))
	card.add_child(_text(tr("EVO_NO_REPAIR"), 36.0, ThemeColors.UI_WARNING_YELLOW))
	var status := "EVO_NO_EVOLUTION"
	if not license_owned:
		status = "EVO_WINGMAN_LOCKED"
	elif not has_space:
		status = "EVO_WINGMAN_FULL"
	card.add_child(_text(tr(status), 18.0, Color(_terminal_color, 0.65)))
	_wingman_confirm = _button(tr("EVO_CONFIRM_WINGMAN"), _confirm_wingman)
	_wingman_confirm.disabled = not _wingman_ready
	card.add_child(_wingman_confirm)


func _card(title: String) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel_style(_terminal_color, 0.0, Color.TRANSPARENT))
	_decision_pane.add_child(frame)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	frame.add_child(body)
	body.add_child(_text(title, 18.0, _terminal_color, true))
	return body


func _make_pane(parent: Control, title: String, min_width: float) -> VBoxContainer:
	var pane := VBoxContainer.new()
	pane.custom_minimum_size.x = min_width
	pane.add_theme_constant_override("separation", 18)
	parent.add_child(pane)
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _panel_style(_terminal_color, 0.0, Color.TRANSPARENT))
	header.add_child(_text(title, 18.0, _terminal_color, true))
	pane.add_child(header)
	return pane


func _on_tree_node_selected(node_id: StringName) -> void:
	if _decision_committed or not _evolution_ready or _evo_confirm == null:
		return
	# 浏览历史或锁定机不撤销已选的合法候选。
	if not _tree.can_evolve(node_id):
		return
	_evo_selected = node_id
	_tree.select_node(node_id)
	_evo_confirm.disabled = false
	_evo_target_label.text = tr(String(EvolutionSystem.node_of(node_id).get("name_key", "")))
	_evo_target_label.font_color = _terminal_color


func _build_detail() -> void:
	_popover = PanelContainer.new()
	_popover.visible = false
	# 悬浮阅读层遮住下方的字与反色卡片，避免说明与路线文字叠印。
	_popover.add_theme_stylebox_override("panel", _panel_style(_terminal_color, 18.0, Color(0, 0, 0, 0.98)))
	add_child(_popover)
	_popover_scroll = ScrollContainer.new()
	_popover_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_popover.add_child(_popover_scroll)
	_detail = EvolutionDetailPanel.new()
	_popover_scroll.add_child(_detail)
	_hover_timer = Timer.new()
	_hover_timer.one_shot = true
	_hover_timer.wait_time = 0.18
	_hover_timer.timeout.connect(_hide_popover)
	add_child(_hover_timer)
	_popover.mouse_entered.connect(func() -> void: _hover_timer.stop())
	_popover.mouse_exited.connect(_schedule_hide_popover)


func _on_tree_node_hovered(node_id: StringName, anchor: Rect2) -> void:
	if node_id == &"":
		_schedule_hide_popover()
		return
	if _decision_committed or not visible or not _tree._is_revealed(node_id):
		_hide_popover()
		return
	_hover_timer.stop()
	_hover_node = node_id
	_detail.show_node(node_id, _current_id, _team_level, _axis_points)
	_popover_scroll.scroll_vertical = 0
	var viewport_size := _panel.get_viewport_rect().size
	var height := minf(_detail.get_combined_minimum_size().y + 36.0, viewport_size.y - 72.0)
	_popover.custom_minimum_size = Vector2(DETAIL_WIDTH, height)
	_popover.size = _popover.custom_minimum_size
	# 靠屏幕边缘时翻到左侧；长说明只在浮窗内滚动，不推动主界面。
	var x := anchor.end.x + 18.0
	if x + DETAIL_WIDTH > viewport_size.x - 18.0:
		x = anchor.position.x - DETAIL_WIDTH - 18.0
	_popover.position = Vector2(clampf(x, 18.0, maxf(18.0, viewport_size.x - DETAIL_WIDTH - 18.0)),
		clampf(anchor.position.y, 18.0, maxf(18.0, viewport_size.y - height - 18.0)))
	_popover.visible = true


func _schedule_hide_popover() -> void:
	if is_inside_tree() and _popover.visible:
		_hover_timer.start()


func _hide_popover() -> void:
	_hover_node = &""
	if is_instance_valid(_hover_timer):
		_hover_timer.stop()
	if is_instance_valid(_popover):
		_popover.hide()
	if is_instance_valid(_tree):
		_tree.clear_hover()


func _on_tree_scrolled(_value: float) -> void:
	_hide_popover()
	_tree.clear_hover()


func _confirm_evolution() -> void:
	if _decision_committed or _evo_selected == &"":
		return
	_decision_committed = true
	_lock_decision_controls()
	evolution_chosen.emit(_evo_selected)


func _confirm_repair() -> void:
	if _decision_committed or _evolution_ready:
		return
	_decision_committed = true
	_lock_decision_controls()
	repair_chosen.emit()


func _confirm_wingman() -> void:
	if _decision_committed or not _wingman_ready:
		return
	_decision_committed = true
	_lock_decision_controls()
	wingman_chosen.emit()


func _lock_decision_controls() -> void:
	_hide_popover()
	_tree.interactive = false
	for button in [_evo_confirm, _repair_confirm, _wingman_confirm]:
		if button:
			button.disabled = true


func reject_decision() -> void:
	_decision_committed = false
	_tree.interactive = true
	_tree.select_node(&"")
	if _repair_confirm:
		_repair_confirm.disabled = _evolution_ready
	if _wingman_confirm:
		_wingman_confirm.disabled = not _wingman_ready
	_evo_selected = &""
	if _evo_confirm:
		_evo_confirm.disabled = true
	if _evo_target_label:
		_evo_target_label.text = tr("EVO_PICK_TARGET")
		_evo_target_label.font_color = Color(_terminal_color, 0.65)


func _button(title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 36.0
	button.add_theme_font_override("font", TerminalText.CHAKRA_PETCH_MEDIUM)
	button.add_theme_font_size_override("font_size", TerminalText.ONE_U_FONT_SIZE)
	button.add_theme_color_override("font_color", _terminal_color)
	button.add_theme_color_override("font_hover_color", Color.BLACK)
	button.add_theme_color_override("font_pressed_color", Color.BLACK)
	button.add_theme_color_override("font_disabled_color", ThemeColors.TEXT_LOCKED)
	button.add_theme_stylebox_override("normal", _panel_style(_terminal_color, 0.0, Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover", _panel_style(_terminal_color, 0.0, _terminal_color))
	button.add_theme_stylebox_override("pressed", _panel_style(_terminal_color, 0.0, _terminal_color))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", _panel_style(ThemeColors.TEXT_LOCKED, 0.0, Color.TRANSPARENT))
	button.pressed.connect(callback)
	return button


func _panel_style(border: Color, margin: float, background: Color = Color(0, 0, 0, 0.70)) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_content_margin_all(margin)
	return style


func _text(value: String, height: float, color: Color, header: bool = false) -> TerminalText:
	var label := TerminalText.new()
	label.text = value
	label.custom_minimum_size.y = height
	label.font_color = color
	label.font_face = TerminalText.FontFace.SILKSCREEN if height == 18.0 else TerminalText.FontFace.CHAKRA_PETCH_MEDIUM
	if height == 18.0:
		label.size_rule = TerminalText.SizeRule.ONE_U_FIXED_15
	else:
		label.layout_text = "MMMMMMMMMMMMMMMM"
	if header:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label


func get_transition_elements() -> Array[Control]:
	return [_root] if _root else []
