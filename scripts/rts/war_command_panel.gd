extends TacticalMap
## Tab 实时指挥。复用正式地图绘制；不调用会暂停全场的 panel_in / panel_out。
var selected_sector := 1
var _ledger_text: TerminalText
var _status_text: TerminalText
var _queue_text: TerminalText
var _ribbon: Control
var _ally_bar: ProgressBar
var _enemy_bar: ProgressBar
var _sector_buttons: Array[Button] = []
var _order_buttons: Dictionary = {}
var _result_text: TerminalText
var _actions: Control
var _cancel_button: Button
var _card: Control
var _pilot_text: TerminalText
var _ace_button: Button

func _build_ui() -> void:
	_ribbon = Control.new()
	_ribbon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ribbon)
	var strip := Panel.new()
	strip.position = Vector2(-280, 18)
	strip.size = Vector2(560, 54)
	strip.anchor_left = 0.5
	strip.anchor_right = 0.5
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ribbon.add_child(strip)
	_ledger_text = _text(strip, "", Rect2(0, 0, 560, 18))
	_ally_bar = _bar(strip, Rect2(0, 27, 270, 9), Color(0.3, 0.65, 1.0))
	_enemy_bar = _bar(strip, Rect2(290, 27, 270, 9), Color(1.0, 0.3, 0.3))
	_text(strip, tr("WAR_TAB"), Rect2(0, 36, 560, 18))
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.02, 0.025, 0.91)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_card = Control.new()
	_card.size = Vector2(1120, 648)
	_card.anchor_left = 0.5
	_card.anchor_top = 0.5
	_card.position = Vector2(-560, -324)
	_root.add_child(_card)
	_text(_card, tr("WAR_TITLE"), Rect2(0, 0, 760, 36))
	_button(_card, tr("WAR_CLOSE"), Rect2(920, 0, 200, 36), close)
	_map_panel = Control.new()
	_map_panel.position = Vector2(0, 54)
	_map_panel.size = Vector2(560, 540)
	_map_panel.clip_contents = true
	_map_panel.draw.connect(_on_map_draw)
	_map_panel.gui_input.connect(_on_map_gui_input)
	_card.add_child(_map_panel)
	_status_text = _text(_card, "", Rect2(600, 54, 520, 36))
	_pilot_text = _text(_card, "", Rect2(600, 90, 520, 18))
	_text(_card, tr("WAR_SECTOR_PICK"), Rect2(600, 108, 520, 18))
	for i in range(3):
		var button := _button(_card, tr("WAR_SECTOR_%d" % i), Rect2(600 + i * 180, 144, 160, 36),
			func(): selected_sector = i; refresh())
		_sector_buttons.append(button)
	_actions = Control.new()
	_card.add_child(_actions)
	var row := 0
	for kind: String in ["fighter", "strike", "frigate"]:
		var button := _button(_actions, "", Rect2(600, 216 + row * 54, 520, 36),
			func(): _game_scene.war.request(kind, selected_sector); refresh())
		_order_buttons[kind] = button
		row += 1
	_queue_text = _text(_card, "", Rect2(600, 378, 520, 36))
	_cancel_button = _button(_actions, tr("WAR_CANCEL"), Rect2(600, 432, 520, 36), _cancel_first)
	_button(_actions, tr("WAR_ACE_A"), Rect2(600, 504, 240, 36), func(): _game_scene.switch_ace(0); refresh())
	_ace_button = _button(_actions, tr("WAR_ACE_DEPLOY"), Rect2(880, 504, 240, 36), _ace_order)
	_text(_card, tr("WAR_RULE"), Rect2(0, 612, 1120, 18))
	_result_text = _text(_card, "", Rect2(600, 180, 520, 90))
	_result_text.hide()
	_button(_card, tr("WAR_RETRY"), Rect2(600, 558, 240, 36), _retry)
	_button(_card, tr("WAR_MENU"), Rect2(880, 558, 240, 36), _menu)
	move_child(_ribbon, get_child_count() - 1)

func _text(parent: Node, value: String, rect: Rect2) -> TerminalText:
	var label := TerminalText.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.size_rule = TerminalText.SizeRule.ONE_U_FIXED_15
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(label)
	return label

func _button(parent: Node, value: String, rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	_text(button, value, Rect2(0, 0, rect.size.x, rect.size.y))
	button.pressed.connect(action)
	return button

func _bar(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = rect.position
	bar.size = rect.size
	bar.max_value = 240
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	bar.add_theme_stylebox_override("fill", style)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.1, 0.13, 0.15)
	bar.add_theme_stylebox_override("background", background)
	parent.add_child(bar)
	bar.size = rect.size # 覆盖主题初始化时施加的默认最小高度。
	return bar

func open() -> void:
	_is_open = true
	_root.show()
	_ribbon.show()
	refresh()

func close() -> void:
	if _game_scene != null and not _game_scene.war.active:
		return
	_is_open = false
	_root.hide()
	_ribbon.show()

func refresh() -> void:
	if _game_scene == null:
		return
	var ledger = _game_scene.war
	_ledger_text.text = tr("WAR_POINTS") % [int(ledger.points[0]), int(ledger.points[1]), int(ledger.supply)]
	_ally_bar.value = ledger.points[0]
	_enemy_bar.value = ledger.points[1]
	_status_text.text = tr("WAR_STATUS") % [int(ledger.supply), int(ledger.elapsed), _game_scene.active_ace + 1]
	var pilot: Variant = _game_scene.player_aircraft
	if typeof(pilot) == TYPE_OBJECT and is_instance_valid(pilot) and pilot is Aircraft:
		_pilot_text.text = tr("WAR_PILOT") % [int(pilot.hp), int(pilot.params.max_hp), tr("WAR_LOCKED" if pilot.is_locked else "WAR_LIVE")]
		_pilot_text.font_color = Color(1, 0.35, 0.3) if pilot.is_locked else Color.WHITE
	for i in range(3):
		_sector_buttons[i].modulate = Color(1.0, 0.8, 0.3) if i == selected_sector else Color.WHITE
	for kind: String in _order_buttons:
		var package: Dictionary = ledger.PACKAGES[kind]
		var button: Button = _order_buttons[kind]
		var label := button.get_child(0) as TerminalText
		label.text = tr("WAR_ORDER_%s" % kind.to_upper()) % [int(package.cost), int(ledger.stock[kind])]
		button.disabled = not ledger.active or ledger.supply < package.cost or ledger.stock[kind] <= 0 or ledger.orders.size() >= 2
	var lines := PackedStringArray()
	for order: Dictionary in ledger.orders:
		lines.append(tr("WAR_WAIT_CAP") if float(order.remaining) <= 0.0 else
			tr("WAR_ETA") % [tr("WAR_KIND_%s" % String(order.kind).to_upper()), int(ceil(float(order.remaining)))])
	_queue_text.text = " / ".join(lines) if not lines.is_empty() else tr("WAR_QUEUE_EMPTY")
	_cancel_button.disabled = ledger.orders.is_empty()
	var reserve: bool = _game_scene.ace_squads[1] == null
	(_ace_button.get_child(0) as TerminalText).text = tr("WAR_ACE_DEPLOY" if reserve else "WAR_ACE_B")
	_ace_button.disabled = not ledger.active or (reserve and (ledger.stock.ace <= 0 or ledger.supply < 60 or ledger.orders.size() >= 2))
	if _is_open:
		_map_panel.queue_redraw()

func _on_map_draw() -> void:
	super._on_map_draw()
	if _game_scene == null or _world_rect.size.x <= 0.0:
		return
	for i in range(3):
		var p := _world_to_map(_game_scene.SECTORS[i], _map_panel.size)
		var owner: int = _game_scene.control[i]
		var color := Color(0.4, 0.7, 1.0) if owner == 0 else (Color(1, 0.3, 0.3) if owner == 1 else Color(0.9, 0.9, 0.9))
		var radius: float = _game_scene.SECTOR_RADIUS / _world_rect.size.x * _map_panel.size.x
		_map_panel.draw_arc(p, radius, 0, TAU, 48, color, 2.0)
		if i == selected_sector:
			_map_panel.draw_arc(p, radius + 5.0, 0, TAU, 48, Color(1, 0.8, 0.3), 2.0)
	for marker: Dictionary in _game_scene.markers:
		var p := _world_to_map(marker.pos, _map_panel.size)
		if Rect2(Vector2.ZERO, _map_panel.size).has_point(p):
			_map_panel.draw_circle(p, 3.0, Color(0.3, 0.7, 1.0) if marker.side == 0 else Color(1, 0.3, 0.3))

func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var best := INF
		for i in range(3):
			var d: float = event.position.distance_squared_to(_world_to_map(_game_scene.SECTORS[i], _map_panel.size))
			if d < best:
				best = d
				selected_sector = i
		refresh()

func _cancel_first() -> void:
	if not _game_scene.war.orders.is_empty():
		_game_scene.war.cancel(int(_game_scene.war.orders[0].id))
	refresh()

func _ace_order() -> void:
	if _game_scene.ace_squads[1] == null:
		_game_scene.war.request("ace", selected_sector)
	else:
		_game_scene.switch_ace(1)
	refresh()

func show_result(won: bool) -> void:
	open()
	_actions.hide()
	_result_text.text = tr("WAR_WIN" if won else "WAR_LOSE")
	_result_text.show()
	refresh()

func _retry() -> void:
	Presentation.clear_all()
	get_tree().change_scene_to_file("res://scenes/full_war_test.tscn")

func _menu() -> void:
	_game_scene._quit_to_main_menu()
