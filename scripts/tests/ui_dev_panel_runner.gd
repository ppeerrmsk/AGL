extends Node2D

## UI Dev 覆盖层的固定画面回归场景；正式游戏内入口是 F7。
## 紫色编号只表示自动排版区域的位置和包含层级，不表示功能。

const PlayerInstrumentPanelScript := preload("res://scripts/survivor/player_instrument_panel.gd")
const WingmanInstrumentPanelScript := preload("res://scripts/survivor/wingman_instrument_panel.gd")
const MilestoneAxisCounterScript := preload("res://scripts/survivor/milestone_axis_counter.gd")
const BottomExperiencePanelScript := preload("res://scripts/survivor/bottom_experience_panel.gd")
const WarzoneTimePanelScript := preload("res://scripts/survivor/warzone_time_panel.gd")
const UiDevOutlineOverlayScript := preload("res://scripts/ui/ui_dev_outline_overlay.gd")
const SurvivorHUDScript := preload("res://scripts/survivor/survivor_hud.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")
const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")
const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")
const ZoneHintScript := preload("res://scripts/survivor/zone_hint.gd")

const CANVAS_SIZE := Vector2(1920.0, 1080.0)
const PLAYER_RIGHT := 1582.0
const PLAYER_Y := 448.0
const BOTTOM_BAR_RECT := Rect2(0.0, 1026.0, 1920.0, 54.0)
const BOTTOM_PROGRESS_POSITION := Vector2(618.0, 1026.0)
const AXIS_POSITION := Vector2(756.0, 1026.0)

var _sample_aircraft: Aircraft


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(CANVAS_SIZE))
	TranslationServer.set_locale("zh")
	var bench_scenario := String(get_tree().get_meta("bench_scenario", ""))
	var preview_scale := 0.5 if bench_scenario == "ui_dev_panel_scale_visual" \
		else SurvivorHUDScript.PLAYER_HUD_SCALE_DEFAULT

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
	_add_ui_scale_control(preview_scale)
	var wingman_panel = _add_wingman_panel(player_panel)
	_add_bottom_bar()
	var axis_counter = _add_axis_counter()
	_add_bottom_experience_panel()
	var player_right: float = CANVAS_SIZE.x \
		if bench_scenario == "ui_dev_panel_scale_visual" else PLAYER_RIGHT
	var player_bottom: float = CANVAS_SIZE.y - SurvivorHUDScript.PLAYER_HUD_BOTTOM_MARGIN \
		if bench_scenario == "ui_dev_panel_scale_visual" \
		else PLAYER_Y + player_panel.size.y
	_apply_player_scale_preview(player_panel, preview_scale,
		player_right, player_bottom)
	if bench_scenario == "ui_dev_panel_scale_visual":
		# 非玩家 UI 保持生产布局的 1.0x 尺寸与基准位置。
		wingman_panel.position = Vector2(
			CANVAS_SIZE.x - wingman_panel.size.x,
			CANVAS_SIZE.y - SurvivorHUDScript.PLAYER_HUD_BOTTOM_MARGIN
				- player_panel.size.y - wingman_panel.size.y)

	await get_tree().process_frame
	if bench_scenario == "ui_dev_panel_manual_flare_visual":
		_activate_manual_flare_debug(player_panel, manual_flare_button)
		await get_tree().process_frame
	if bench_scenario == "ui_notification_bars_visual":
		_add_time_preview()
		_add_notification_preview()
		await get_tree().create_timer(0.35).timeout
	if bench_scenario != "ui_dev_panel_clean_visual" \
			and bench_scenario != "ui_dev_panel_manual_flare_visual" \
			and bench_scenario != "ui_dev_panel_scale_visual" \
			and bench_scenario != "ui_notification_bars_visual":
		_add_dev_overlay(player_panel, wingman_panel, axis_counter)

	if bench_scenario == "ui_dev_panel_visual" \
			or bench_scenario == "ui_dev_panel_clean_visual" \
			or bench_scenario == "ui_dev_panel_manual_flare_visual" \
			or bench_scenario == "ui_dev_panel_scale_visual" \
			or bench_scenario == "ui_notification_bars_visual":
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
	result.ammo = 81
	result._gun_reload_active = true
	result.gun_reload_progress = 0.28
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
	panel.update_status(true, 7)
	return panel


func _add_manual_flare_debug_button(player_panel: Control) -> Button:
	var button := Button.new()
	button.text = "DEV  + MANUAL FLR [R]"
	button.position = Vector2(24.0, 52.0)
	button.size = Vector2(220.0, 34.0)
	button.pressed.connect(_activate_manual_flare_debug.bind(player_panel, button))
	add_child(button)
	return button


func _add_ui_scale_control(value: float) -> void:
	var label := Label.new()
	label.text = "PLAYER HUD SCALE  %.1fx" % value
	label.position = Vector2(24.0, 94.0)
	label.size = Vector2(260.0, 22.0)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiDevOutlineOverlayScript.OUTLINE_COLOR)
	add_child(label)
	var slider := HSlider.new()
	slider.position = Vector2(24.0, 118.0)
	slider.size = Vector2(220.0, 28.0)
	slider.min_value = SurvivorHUDScript.PLAYER_HUD_SCALE_MIN
	slider.max_value = SurvivorHUDScript.PLAYER_HUD_SCALE_MAX
	slider.step = SurvivorHUDScript.PLAYER_HUD_SCALE_STEP
	slider.value = value
	slider.tick_count = 6
	slider.ticks_on_borders = true
	slider.scrollable = false
	add_child(slider)


func _apply_player_scale_preview(player_panel: Control, value: float,
		right_edge: float, bottom_edge: float) -> void:
	var preview_scale := Vector2.ONE * value
	player_panel.scale = preview_scale
	player_panel.position = Vector2(
		right_edge - player_panel.size.x * value,
		bottom_edge - player_panel.size.y * value)


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


func _add_bottom_bar() -> void:
	var background := ColorRect.new()
	background.color = ThemeColors.UI_BLOCK_BACKGROUND
	background.position = BOTTOM_BAR_RECT.position
	background.size = BOTTOM_BAR_RECT.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var grid = TerminalGridOverlayScript.new()
	grid.size = BOTTOM_BAR_RECT.size
	grid.edge_insets = Vector4(0.5, 0.0, 0.5, 0.5)
	grid.line_color = HudPreferencesScript.hud_color()
	var regions: Array[Rect2] = [Rect2(Vector2.ZERO, BOTTOM_BAR_RECT.size)]
	grid.regions = regions
	background.add_child(grid)


func _add_notification_preview() -> void:
	var hint = ZoneHintScript.new()
	add_child(hint)
	hint.show_persistent("⚠ 敌王牌中队 [GIMMICK] 进入战区，全部击坠可延长战区时间 +1:00")
	hint.show_temp("✓ TIP  PRIORITY TARGET UPDATED", 5.0)

	# 复用正式王牌条构造器，直观看清顶部通知通道与 BOSS / 王牌共用通道的间距。
	var preview_hud = SurvivorHUDScript.new()
	preview_hud._build_ace_panel()
	var encounter_panel: PanelContainer = preview_hud._ace_panel
	preview_hud._ui_root.remove_child(encounter_panel)
	preview_hud._ace_title_label.text = "♛ GIMMICK"
	var accent := Color("de45ed")
	preview_hud._ace_title_label.add_theme_color_override(
		"font_color", accent.lightened(0.25))
	preview_hud._ace_emblem.set_emblem("gimmick", accent.lightened(0.15))
	for alive in [true, true, true, false]:
		var segment := Panel.new()
		segment.custom_minimum_size = Vector2(
			SurvivorHUDScript.ACE_SEG_W, SurvivorHUDScript.ACE_SEG_H)
		var segment_style := StyleBoxFlat.new()
		segment_style.bg_color = accent if alive else SurvivorHUDScript.ACE_SEG_DEAD
		segment_style.set_corner_radius_all(1)
		segment.add_theme_stylebox_override("panel", segment_style)
		preview_hud._ace_seg_box.add_child(segment)
	encounter_panel.visible = true
	encounter_panel.position = Vector2(
		CANVAS_SIZE.x * 0.5 - 100.0, SurvivorHUDScript.TOP_ENCOUNTER_Y)
	var encounter_layer := CanvasLayer.new()
	encounter_layer.layer = SurvivorHUDScript.PERSISTENT_HUD_LAYER
	add_child(encounter_layer)
	encounter_layer.add_child(encounter_panel)
	preview_hud.free()


func _add_time_preview() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = SurvivorHUDScript.PERSISTENT_HUD_LAYER
	add_child(hud_layer)
	var panel := ColorRect.new()
	panel.color = ThemeColors.UI_BLOCK_BACKGROUND
	panel.position = SurvivorHUDScript.top_time_rect(CANVAS_SIZE).position
	panel.size = SurvivorHUDScript.TIME_PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(panel)
	var grid = TerminalGridOverlayScript.new()
	grid.size = panel.size
	grid.edge_insets = Vector4(0.0, 0.5, 0.0, 0.0)
	grid.line_color = HudPreferencesScript.hud_color()
	var regions: Array[Rect2] = [Rect2(Vector2.ZERO, panel.size)]
	grid.regions = regions
	panel.add_child(grid)
	var time_text = TerminalTextScript.new()
	time_text.size = panel.size
	time_text.font_face = TerminalTextScript.FontFace.CHAKRA_PETCH_BOLD
	time_text.size_rule = TerminalTextScript.SizeRule.ONE_U_FIXED_15
	time_text.layout_text = "TIME  99:59"
	time_text.text = "TIME  06:20"
	time_text.font_color = HudPreferencesScript.hud_color()
	panel.add_child(time_text)
	var remaining = WarzoneTimePanelScript.new()
	remaining.position = SurvivorHUDScript.warzone_time_rect(CANVAS_SIZE).position
	hud_layer.add_child(remaining)
	remaining.update_display(859.0, false)


func _add_bottom_experience_panel() -> void:
	var progression_player := SurvivorPlayer.new()
	progression_player.level = 12
	progression_player.xp = 84
	progression_player.xp_to_next = 160
	var panel = BottomExperiencePanelScript.new()
	panel.position = BOTTOM_PROGRESS_POSITION
	add_child(panel)
	panel.update_display(progression_player, true)
	progression_player.free()


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

	_append_component_regions(regions, axis_counter.position,
		Rect2(Vector2.ZERO, axis_counter.size), MilestoneAxisCounterScript.grid_regions())
	_append_component_regions(regions, BOTTOM_PROGRESS_POSITION,
		Rect2(Vector2.ZERO, BottomExperiencePanelScript.TOTAL_SIZE),
		BottomExperiencePanelScript.grid_regions())
	regions.append(BOTTOM_BAR_RECT)

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
