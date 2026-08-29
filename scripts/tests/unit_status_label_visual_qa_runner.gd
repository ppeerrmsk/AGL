extends Node2D

## 跨兵种状态栏 Visual QA：真实 Aircraft/Ground/SAM/Radar/Naval/超级巨炮绘制入口，
## 叠加旋转父节点、非均匀 scale、单位转向和亚像素位置，证明面板仍锁定屏幕。

const PreviewAircraft := preload("res://scripts/tests/aircraft_silhouette_preview.gd")
const PlayableSetup := preload("res://scripts/survivor/survivor_playable_setup.gd")
const Tier3SuperCannon := preload("res://scripts/survivor/tier3_super_cannon_part.gd")


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	RenderingServer.set_default_clear_color(Color("d7dcda"))

	var camera := Camera2D.new()
	camera.position = Vector2(960.0, 540.0)
	camera.zoom = Vector2.ONE
	add_child(camera)
	camera.make_current()

	var stage := Node2D.new()
	stage.position = camera.position + Vector2(0.37, -0.43)
	stage.rotation = 0.17
	stage.scale = Vector2(1.18, 0.82)
	add_child(stage)

	var aircraft := _spawn_aircraft(stage, Vector2(-520.0, -190.0), "Ultra", true)
	aircraft.set_afterburner_mode_active(true)
	var wingman := _spawn_aircraft(stage, Vector2(-520.0, 10.0), "LONE", false)
	var ground := _spawn_ground(stage, Vector2(-130.0, -190.0))
	var sam := _spawn_sam(stage, Vector2(260.0, -190.0))
	var drone := _spawn_drone(stage, Vector2(610.0, -190.0))
	var radar := _spawn_radar(stage, Vector2(-520.0, 210.0))
	var naval := _spawn_naval(stage, Vector2(-130.0, 210.0))
	var cannon := _spawn_super_cannon(stage, Vector2(260.0, 210.0))
	var missile := _spawn_missile(stage, Vector2(610.0, 210.0), aircraft)
	var units: Array[Node2D] = [aircraft, wingman, ground, sam, drone, radar, naval, missile]

	var overlay := CanvasLayer.new()
	add_child(overlay)
	var title := Label.new()
	title.text = "UNIT STATUS LABEL QA — SHARED SCREEN-SPACE VECTOR PANEL"
	title.position = Vector2(42.0, 30.0)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("182026"))
	overlay.add_child(title)
	var note := Label.new()
	note.text = "AIRCRAFT / UAV / GROUND / SAM / RADAR / NAVAL / MISSILE / AURORA — ENGLISH DATA CONTRACT"
	note.position = Vector2(42.0, 62.0)
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color("3c4a52"))
	overlay.add_child(note)

	for frame in range(8):
		for i in range(units.size()):
			units[i].rotation += 0.035 * float(i + 1)
			units[i].queue_redraw()
		# 走生产炮管朝向入口；它必须同步刷新缓存的屏幕空间状态栏矩阵。
		cannon._set_body_heading(cannon.heading - 0.20)
		await get_tree().process_frame
	_prime_damage_flash([aircraft, wingman])
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := "res://bench/results/unit_status_label_visual.png"
	var error := get_viewport().get_texture().get_image().save_png(output)
	print("[unit_status_label_visual] screenshot=%s err=%d" % [output, error])
	_prime_damage_flash([aircraft, wingman], 1)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var white_output := "res://bench/results/unit_status_label_visual_damage_white.png"
	var white_error := get_viewport().get_texture().get_image().save_png(white_output)
	print("[unit_status_label_visual] screenshot=%s err=%d" % [white_output, white_error])
	# 同一批真实单位切到战略缩放；位置按倒数扩开，使画面构图保持可比。
	camera.zoom = Vector2(0.30, 0.30)
	note.text = "COMPACT 0.30x — identity-first rows; zoom in above 0.40x restores details"
	for unit in units + [cannon]:
		unit.position *= 3.0
		unit.queue_redraw()
	_prime_damage_flash([aircraft, wingman])
	for _frame in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var compact_output := "res://bench/results/unit_status_label_visual_compact.png"
	var compact_error := get_viewport().get_texture().get_image().save_png(compact_output)
	print("[unit_status_label_visual] screenshot=%s err=%d" % [compact_output,
		compact_error])
	AircraftRenderer.player_ref = null
	get_tree().quit(0 if error == OK and white_error == OK and compact_error == OK else 1)


func _spawn_aircraft(parent: Node2D, pos: Vector2, callsign: String,
		controlled: bool) -> Aircraft:
	var aircraft := PreviewAircraft.new()
	var params := load("res://resources/player/player_f14.tres") as AircraftParams
	var profile := load("res://resources/playable_f14.tres") as PlayableAircraft
	aircraft.params = params.duplicate(true)
	PlayableSetup.deep_dup_weapons(aircraft.params)
	PlayableSetup.apply(aircraft, profile)
	aircraft.callsign = callsign
	aircraft.team = CombatUnit.TEAM_PLAYER
	aircraft.altitude = 10000.0
	aircraft.flat_altitude = true
	aircraft.speed = 310.0
	aircraft.g_load = 6.4
	aircraft.hide_data_label = true
	aircraft.draw_runtime_label = true
	aircraft.position = pos
	parent.add_child(aircraft)
	if controlled:
		AircraftRenderer.player_ref = aircraft
	return aircraft


func _prime_damage_flash(aircraft: Array, phase: int = 0) -> void:
	var now := EventLogger.get_game_time()
	var phase_offset := AircraftRenderer.STATUS_DAMAGE_FLASH_STEP_S * 1.1 \
		if phase == 1 else 0.0
	for ac: Aircraft in aircraft:
		ac.set_meta(AircraftRenderer.STATUS_DAMAGE_STARTED_META, now - phase_offset)
		ac.set_meta(AircraftRenderer.STATUS_DAMAGE_LAST_META, now)
		ac.queue_redraw()


func _spawn_ground(parent: Node2D, pos: Vector2) -> GroundUnit:
	var unit := GroundUnit.new()
	unit.params = (load("res://resources/aa_gun_params.tres") as AircraftParams).duplicate(true)
	unit.position = pos
	parent.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _spawn_drone(parent: Node2D, pos: Vector2) -> Aircraft:
	var unit := PreviewAircraft.new()
	unit.params = (load("res://resources/enemy_uav.tres") as AircraftParams).duplicate(true)
	unit.position = pos
	unit.team = CombatUnit.TEAM_ALLY
	unit.is_drone = true
	unit.speed = 220.0
	unit.altitude = 3500.0
	unit.draw_runtime_label = true
	parent.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _spawn_sam(parent: Node2D, pos: Vector2) -> SAMUnit:
	var unit := SAMUnit.new()
	unit.params = (load("res://resources/sam_params.tres") as AircraftParams).duplicate(true)
	unit.position = pos
	parent.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _spawn_radar(parent: Node2D, pos: Vector2) -> RadarStation:
	var unit := RadarStation.new()
	unit.params = (load("res://resources/radar_station_params.tres") as AircraftParams).duplicate(true)
	unit.position = pos
	parent.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _spawn_naval(parent: Node2D, pos: Vector2) -> NavalUnit:
	var unit := NavalUnit.new()
	unit.params = (load("res://resources/naval/frigate_ffg.tres") as NavalParams).duplicate(true)
	unit.position = pos
	parent.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _spawn_super_cannon(parent: Node2D, pos: Vector2) -> Tier3SuperCannonPart:
	var unit := Tier3SuperCannon.new() as Tier3SuperCannonPart
	unit.params = (load("res://resources/aa_gun_params.tres") as AircraftParams).duplicate(true)
	unit.params.display_name = Tier3SuperCannon.DISPLAY_NAME
	unit.params.gun = null
	unit.params.missile = null
	unit.position = pos
	unit.team = CombatUnit.TEAM_HOSTILE
	unit.configure(&"VISUAL_QA")
	parent.add_child(unit)
	unit.set_physics_process(false)
	return unit


func _spawn_missile(parent: Node2D, pos: Vector2, target: CombatUnit) -> Missile:
	var unit := Missile.new()
	unit.params = (load("res://resources/default_missile.tres") as MissileParams).duplicate(true)
	unit.position = pos
	unit.heading = deg_to_rad(359.6)
	unit.rotation = unit.heading
	unit.speed = 850.0
	unit.altitude = 6200.0
	unit.target = target
	unit.team = CombatUnit.TEAM_HOSTILE
	parent.add_child(unit)
	unit.set_physics_process(false)
	return unit
