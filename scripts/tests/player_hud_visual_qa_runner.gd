extends Node2D

## 仅供 bench Visual：用真实 Godot 字体/CanvasItem 渲染固定玩家仪表样张。

const PlayerInstrumentPanelScript := preload("res://scripts/survivor/player_instrument_panel.gd")
const WingmanInstrumentPanelScript := preload("res://scripts/survivor/wingman_instrument_panel.gd")
const MilestoneAxisCounterScript := preload("res://scripts/survivor/milestone_axis_counter.gd")
const BottomExperiencePanelScript := preload("res://scripts/survivor/bottom_experience_panel.gd")
const SurvivorHUDScript := preload("res://scripts/survivor/survivor_hud.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")

var _sample_aircraft: Aircraft


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	TranslationServer.set_locale("zh")
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var bottom_bar_rect := SurvivorHUDScript.bottom_bar_rect(Vector2(1920.0, 1080.0))
	var bottom_bar := ColorRect.new()
	bottom_bar.color = ThemeColors.UI_BLOCK_BACKGROUND
	bottom_bar.position = bottom_bar_rect.position
	bottom_bar.size = bottom_bar_rect.size
	add_child(bottom_bar)
	var bottom_grid = TerminalGridOverlayScript.new()
	bottom_grid.size = bottom_bar.size
	bottom_grid.edge_insets = Vector4(0.5, 0.0, 0.5, 0.5)
	var bottom_regions: Array[Rect2] = [Rect2(Vector2.ZERO, bottom_bar.size)]
	bottom_grid.regions = bottom_regions
	bottom_bar.add_child(bottom_grid)

	_sample_aircraft = Aircraft.new()
	_sample_aircraft.params = (load("res://resources/player/player_f15c.tres") as AircraftParams).duplicate(true)
	_sample_aircraft.params.max_hp = 150.0
	_sample_aircraft.hp = 100.0
	_sample_aircraft.speed = 500.0 * 1.852 / 3.6
	_sample_aircraft.altitude = 10000.0
	_sample_aircraft.altitude_preference = Aircraft.AltitudePreference.PREFER_LOW
	_sample_aircraft.g_load = 4.5
	_sample_aircraft.auto_engage_enabled = true
	_sample_aircraft.missile_auto_fire = false
	_sample_aircraft.weapon_preference = Aircraft.WeaponPreference.PREFER_MISSILE
	_sample_aircraft.flares_remaining = 1
	_sample_aircraft._flare_cooldown = 1.0
	_sample_aircraft.flare_visual_burst_emitted = 4
	_sample_aircraft.displacement_roll_active = true
	_sample_aircraft._active_special_local_cooldown_s = 9.7
	_sample_aircraft.missiles_remaining = 2
	_sample_aircraft._missile_reload_active = true
	_sample_aircraft.missile_reload_progress = 0.62
	_sample_aircraft.ammo = 0
	_sample_aircraft._gun_reload_active = true
	_sample_aircraft.gun_reload_progress = 0.28

	var charge := AfterburnerCharge.new()
	charge.active = true
	charge.charge = AfterburnerCharge.CHARGE_MAX * 0.64

	var panel = PlayerInstrumentPanelScript.new()
	panel.weapon_animation_time_override_ms = 1000
	add_child(panel)
	panel.position = Vector2(
		1600.0 - panel.size.x - 18.0,
		900.0 - panel.size.y - SurvivorHUDScript.PLAYER_HUD_BOTTOM_MARGIN,
	)
	panel.update_display(_sample_aircraft, charge)
	panel.update_status(true, 3)
	# Capture a deterministic 2 Hz ON phase for the reload bar and selected MSL boards.
	panel.weapon_animation_time_override_ms = 1500
	panel.queue_redraw()

	var wingman_panel = WingmanInstrumentPanelScript.new()
	add_child(wingman_panel)
	var wing_rows: Array = []
	var callsigns := ["LONE", "DUSK", "HAVEN", "TAIGA", "WARRANT", "REFLEX", "FINCH"]
	for index in range(callsigns.size()):
		var reloading := index == 3
		wing_rows.append({
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
	wingman_panel.update_display(wing_rows)
	wingman_panel.position = Vector2(
		panel.position.x,
		panel.position.y - wingman_panel.size.y,
	)

	# 底部成长摘要：Lv07 同时验证两位等级的前导零灰色规则。
	var progression_player := SurvivorPlayer.new()
	progression_player.level = 7
	progression_player.xp = 84
	progression_player.xp_to_next = 160
	progression_player.axis_points[SurvivorData.AXIS_GLADIATOR] = 3
	progression_player.axis_points[SurvivorData.AXIS_KNIGHT] = 2
	progression_player.axis_points[SurvivorData.AXIS_SCHEMER] = 1
	var axis_counter = MilestoneAxisCounterScript.new()
	axis_counter.position = SurvivorHUDScript.bottom_axis_rect(Vector2(1920.0, 1080.0)).position
	add_child(axis_counter)
	axis_counter.update_display(progression_player)
	var experience_panel = BottomExperiencePanelScript.new()
	experience_panel.position = SurvivorHUDScript.bottom_progress_rect(
		Vector2(1920.0, 1080.0)).position
	add_child(experience_panel)
	move_child(axis_counter, get_child_count() - 1)
	experience_panel.update_display(progression_player)

	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://bench/results/player_hud_visual.png"
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("[player_hud_visual] screenshot=%s err=%d" % [path, err])
	_sample_aircraft.free()
	panel.queue_free()
	wingman_panel.queue_free()
	axis_counter.queue_free()
	experience_panel.queue_free()
	progression_player.free()
	bottom_bar.queue_free()
	background.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if err == OK else 1)
