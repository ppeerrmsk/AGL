extends Node2D

## UI Dev 覆盖层的固定画面回归场景；正式游戏内入口是 F7。
## 紫色编号只表示自动排版区域的位置和包含层级，不表示功能。

const PlayerInstrumentPanelScript := preload("res://scripts/survivor/player_instrument_panel.gd")
const WingmanInstrumentPanelScript := preload("res://scripts/survivor/wingman_instrument_panel.gd")
const MilestoneAxisCounterScript := preload("res://scripts/survivor/milestone_axis_counter.gd")
const UiDevOutlineOverlayScript := preload("res://scripts/ui/ui_dev_outline_overlay.gd")

const CANVAS_SIZE := Vector2(1920.0, 1080.0)
const PLAYER_RIGHT := 1582.0
const PLAYER_Y := 448.0
const AXIS_POSITION := Vector2(760.0, 1018.0)
const XP_POSITION := Vector2(760.0, 1040.0)
const XP_SIZE := Vector2(400.0, 20.0)

var _sample_aircraft: Aircraft


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(CANVAS_SIZE))
	TranslationServer.set_locale("zh")

	var background := ColorRect.new()
	background.color = Color("050707")
	background.position = Vector2.ZERO
	background.size = CANVAS_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_add_header()
	_sample_aircraft = _build_sample_aircraft()
	var charge := _build_afterburner_charge()
	var player_panel = _add_player_panel(charge)
	var manual_flare_button := _add_manual_flare_debug_button(player_panel)
	var wingman_panel = _add_wingman_panel(player_panel)
	var axis_counter = _add_axis_counter()
	_add_xp_bar()

	await get_tree().process_frame
	var bench_scenario := String(get_tree().get_meta("bench_scenario", ""))
	if bench_scenario == "ui_dev_panel_manual_flare_visual":
		_activate_manual_flare_debug(player_panel, manual_flare_button)
		await get_tree().process_frame
	if bench_scenario != "ui_dev_panel_clean_visual" \
			and bench_scenario != "ui_dev_panel_manual_flare_visual":
		_add_dev_overlay(player_panel, wingman_panel, axis_counter)

	if bench_scenario == "ui_dev_panel_visual" \
			or bench_scenario == "ui_dev_panel_clean_visual" \
			or bench_scenario == "ui_dev_panel_manual_flare_visual":
		await _save_bench_screenshot(bench_scenario)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _exit_tree() -> void:
	if is_instance_valid(_sample_aircraft):
		_sample_aircraft.free()


func _add_header() -> void:
	var title := Label.new()
	title.text = "UI DEV PANEL  |  紫框编号仅表示面板位置  |  顶层 A-Z / 子层 A1 A2  |  ESC 退出"
	title.position = Vector2(24.0, 18.0)
	title.size = Vector2(940.0, 24.0)
	title.add_theme_color_override("font_color", UiDevOutlineOverlayScript.OUTLINE_COLOR)
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)


func _build_sample_aircraft() -> Aircraft:
	var result := Aircraft.new()
	result.params = (load("res://resources/player/player_f15c.tres") as AircraftParams).duplicate(true)
	result.params.max_hp = 150.0
	result.hp = 100.0
	result.speed = 945.0 / 3.6
	result.altitude = 10000.0
	result.altitude_preference = Aircraft.AltitudePreference.PREFER_LOW
	result.g_load = 11.5
	result.auto_engage_enabled = true
	result.missile_auto_fire = false
	result.weapon_preference = Aircraft.WeaponPreference.PREFER_MISSILE
	result.flares_remaining = 1
	result._flare_cooldown = 1.0
	result.flare_visual_burst_emitted = 4
	result.displacement_roll_active = true
	result._active_special_local_cooldown_s = 9.7
	result.missiles_remaining = 2
	result._missile_reload_active = true
	result.missile_reload_progress = 0.62
	return result


func _build_afterburner_charge() -> AfterburnerCharge:
	var result := AfterburnerCharge.new()
	result.active = true
	result.charge = AfterburnerCharge.CHARGE_MAX * 0.64
	return result


func _add_player_panel(charge: AfterburnerCharge):
	var panel = PlayerInstrumentPanelScript.new()
	add_child(panel)
	panel.position = Vector2(PLAYER_RIGHT - panel.size.x, PLAYER_Y)
	panel.update_display(_sample_aircraft, charge)
	return panel


func _add_manual_flare_debug_button(player_panel: Control) -> Button:
	var button := Button.new()
	button.text = "DEV  + MANUAL FLR [R]"
	button.position = Vector2(24.0, 52.0)
	button.size = Vector2(220.0, 34.0)
	button.pressed.connect(_activate_manual_flare_debug.bind(player_panel, button))
	add_child(button)
	return button


func _activate_manual_flare_debug(player_panel: Control, button: Button) -> void:
	if not player_panel.debug_grant_manual_flare_skill():
		return
	button.text = "DEV  MANUAL FLR ADDED"
	button.disabled = true


func _add_wingman_panel(player_panel: Control):
	var panel = WingmanInstrumentPanelScript.new()
	add_child(panel)
	var rows: Array = []
	var callsigns := ["LONE", "DUSK", "HAVEN", "TAIGA", "WARRANT", "REFLEX", "FINCH"]
	for index in range(callsigns.size()):
		var reloading := index == 3
		rows.append({
			"slot": index + 3,
			"callsign": callsigns[index],
			"hp": "110/110",
			"action": "编队跟随",
			"kills": 3 if index == 0 else 0,
			"is_heir": index == 0,
			"has_msl": true,
			"msl": "62%" if reloading else "2/2",
			"msl_busy": reloading,
			"has_gun": true,
			"gun": "100",
			"has_flr": true,
			"flr": "2",
		})
	panel.update_display(rows)
	panel.position = Vector2(player_panel.position.x + player_panel.size.x - panel.size.x,
		player_panel.position.y - panel.size.y)
	return panel


func _add_axis_counter():
	var progression_player := SurvivorPlayer.new()
	progression_player.level = 12
	progression_player.xp = 84
	progression_player.xp_to_next = 160
	progression_player.axis_points[SurvivorData.AXIS_GLADIATOR] = 3
	progression_player.axis_points[SurvivorData.AXIS_KNIGHT] = 2
	progression_player.axis_points[SurvivorData.AXIS_SCHEMER] = 1
	var counter = MilestoneAxisCounterScript.new()
	counter.position = AXIS_POSITION
	add_child(counter)
	counter.update_display(progression_player)
	progression_player.free()
	return counter


func _add_xp_bar() -> void:
	var background := ColorRect.new()
	background.color = ThemeColors.XP_BAR_BG
	background.position = XP_POSITION
	background.size = XP_SIZE
	add_child(background)
	var fill := ColorRect.new()
	fill.color = ThemeColors.XP_BAR_FILL
	fill.position = XP_POSITION
	fill.size = Vector2(210.0, XP_SIZE.y)
	add_child(fill)
	var label := Label.new()
	label.text = "LV 12    84 / 160"
	label.position = XP_POSITION
	label.size = XP_SIZE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", ThemeColors.TEXT_WHITE)
	add_child(label)


func _add_dev_overlay(player_panel: Control, wingman_panel: Control,
		axis_counter: Control) -> void:
	var regions: Array[Rect2] = []
	_append_component_regions(regions, player_panel.position,
		Rect2(Vector2.ZERO, player_panel.size),
		player_panel.grid_regions(true, true))

	var wing_children: Array[Rect2] = []
	for row_index in range(7):
		wing_children.append(Rect2(
			Vector2(0.0, float(row_index) * WingmanInstrumentPanelScript.ROW_STRIDE),
			Vector2(WingmanInstrumentPanelScript.PANEL_WIDTH,
				WingmanInstrumentPanelScript.ROW_BODY_HEIGHT)
		))
	wing_children.append_array(WingmanInstrumentPanelScript.grid_regions(7))
	_append_component_regions(regions, wingman_panel.position,
		Rect2(Vector2.ZERO, wingman_panel.size), wing_children)

	var axis_children: Array[Rect2] = []
	for index in range(3):
		axis_children.append(MilestoneAxisCounterScript.cell_rect(index))
	_append_component_regions(regions, axis_counter.position,
		Rect2(Vector2.ZERO, axis_counter.size), axis_children)
	regions.append(Rect2(XP_POSITION, XP_SIZE))

	var overlay = UiDevOutlineOverlayScript.new()
	overlay.position = Vector2.ZERO
	overlay.size = CANVAS_SIZE
	overlay.flatten_descendants = true
	overlay.regions = regions
	add_child(overlay)


func _append_component_regions(target: Array[Rect2], origin: Vector2,
		root_rect: Rect2, child_regions: Array[Rect2]) -> void:
	target.append(Rect2(origin + root_rect.position, root_rect.size))
	for child in child_regions:
		target.append(Rect2(origin + child.position, child.size))


func _save_bench_screenshot(scenario: String) -> void:
	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://bench/results/%s.png" % scenario
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("[%s] screenshot=%s err=%d" % [scenario, path, err])
	get_tree().quit(0 if err == OK else 1)
