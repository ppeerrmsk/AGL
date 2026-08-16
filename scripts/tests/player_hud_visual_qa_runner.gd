extends Node2D

## 仅供 bench Visual：用真实 Godot 字体/CanvasItem 渲染固定玩家仪表样张。

const PlayerInstrumentPanelScript := preload("res://scripts/survivor/player_instrument_panel.gd")
const WingmanInstrumentPanelScript := preload("res://scripts/survivor/wingman_instrument_panel.gd")
const MilestoneAxisCounterScript := preload("res://scripts/survivor/milestone_axis_counter.gd")
const HudBoardVisibilityScript := preload("res://scripts/ui/hud_board_visibility.gd")
const DamageVignetteScript := preload("res://scripts/survivor/damage_vignette.gd")
const BottomExperiencePanelScript := preload("res://scripts/survivor/bottom_experience_panel.gd")
const SurvivorHUDScript := preload("res://scripts/survivor/survivor_hud.gd")
const TerminalGridOverlayScript := preload("res://scripts/ui/terminal_grid_overlay.gd")

var _sample_aircraft: Aircraft


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	TranslationServer.set_locale("zh")
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.size = Vector2(1920.0, 1080.0)
	background.z_index = -2
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
	_sample_aircraft.altitude = 5500.0
	_sample_aircraft.altitude_preference = Aircraft.AltitudePreference.PREFER_LOW
	_sample_aircraft.g_load = 4.5
	_sample_aircraft.auto_engage_enabled = false
	_sample_aircraft.missile_auto_fire = false
	_sample_aircraft.weapon_preference = Aircraft.WeaponPreference.PREFER_MISSILE
	_sample_aircraft.flares_remaining = 1
	_sample_aircraft._flare_cooldown = 1.0
	_sample_aircraft.flare_visual_burst_emitted = 4
	_sample_aircraft.displacement_roll_active = true
	_sample_aircraft._active_special_local_cooldown_s = 9.7
	_sample_aircraft.missiles_remaining = 2
	_sample_aircraft._missile_reload_active = true
	_sample_aircraft._missile_reload_timer = 12.4
	_sample_aircraft.missile_reload_progress = 0.62
	_sample_aircraft.params.secondary_missile = (
		load("res://resources/qmaam_missile.tres") as MissileParams).duplicate(true)
	_sample_aircraft.secondary_missile_enabled = true
	_sample_aircraft.secondary_missiles_remaining = 2
	_sample_aircraft._secondary_cooldown = 1.8
	_sample_aircraft.params.rocket = RocketParams.new()
	_sample_aircraft.params.rocket.max_ammo = 24
	_sample_aircraft.params.rocket.burst_cooldown = 4.0
	_sample_aircraft.rockets_remaining = 12
	_sample_aircraft._rocket_burst_cooldown = 2.4
	_sample_aircraft.ammo = 0
	_sample_aircraft._gun_reload_active = true
	_sample_aircraft.gun_reload_progress = 0.28

	var charge := AfterburnerCharge.new()
	charge.active = true
	charge.charge = AfterburnerCharge.CHARGE_MAX * 0.64

	var panel = PlayerInstrumentPanelScript.new()
	panel.weapon_animation_time_override_ms = 1000
	add_child(panel)
	panel.position = SurvivorHUDScript.right_anchored_player_rect(
		Vector2(1920.0, 1080.0), panel.size, 1.0).position
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

	# 先在非黑背景上关闭全部复合框板，确认没有遮罩黑底或残留边线。
	var player_visibility = HudBoardVisibilityScript.new(panel)
	var player_regions: Array[Dictionary] = panel.reveal_panel_regions(true, false)
	player_visibility.sync_regions(player_regions)
	var wingman_visibility = HudBoardVisibilityScript.new(wingman_panel)
	var wingman_regions: Array[Dictionary] = wingman_panel.reveal_panel_regions()
	wingman_visibility.sync_regions(wingman_regions)
	var axis_regions: Array[Dictionary] = []
	for axis_index in range(SurvivorData.AXES.size()):
		axis_regions.append({
			"id": StringName("milestone_axis_%d" % axis_index),
			"rect": MilestoneAxisCounterScript.cell_rect(axis_index),
		})
	var axis_visibility = HudBoardVisibilityScript.new(axis_counter)
	axis_visibility.sync_regions(axis_regions)
	# 新框板必须依靠控制器的默认关闭态消失，避免测试掩盖首帧初始化回归。
	background.color = Color("263043")
	for _frame in range(2):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var hidden_path := "res://bench/results/player_hud_reveal_hidden.png"
	var hidden_err := get_viewport().get_texture().get_image().save_png(hidden_path)
	print("[player_hud_visual] hidden_screenshot=%s err=%d" % [hidden_path, hidden_err])
	# 最终样张同时覆盖真实外圈受伤反馈；其 z=-1，低于 HUD 框板、高于背景。
	var damage_vignette = DamageVignetteScript.new()
	damage_vignette.size = Vector2(1920.0, 1080.0)
	add_child(damage_vignette)
	_sample_aircraft.set_meta(&"hud_last_damage_at", EventLogger.get_game_time())
	damage_vignette.set_player(_sample_aircraft)
	damage_vignette._process(0.1)
	for descriptor in player_regions:
		player_visibility.set_reveal_alpha(1.0, StringName(descriptor["id"]))
	for descriptor in wingman_regions:
		wingman_visibility.set_reveal_alpha(1.0, StringName(descriptor["id"]))
	for descriptor in axis_regions:
		axis_visibility.set_reveal_alpha(1.0, StringName(descriptor["id"]))
	background.color = Color.BLACK

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
	damage_vignette.queue_free()
	progression_player.free()
	bottom_bar.queue_free()
	background.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if err == OK and hidden_err == OK else 1)
