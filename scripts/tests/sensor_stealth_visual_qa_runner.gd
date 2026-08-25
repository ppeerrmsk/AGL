extends Node2D

var _target: Aircraft
var _player: Aircraft
var _hint_target: Aircraft
var _phase_label: Label


class RadarHudStub extends SurvivorHUD:
	var player_ref: Aircraft

	func _ready() -> void:
		set_process(false)

	func _safe_player_aircraft() -> Aircraft:
		return player_ref

	func hud_viewport_size() -> Vector2:
		return Vector2(1280.0, 720.0)


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	RenderingServer.set_default_clear_color(Color("182126"))
	var camera := Camera2D.new()
	camera.zoom = Vector2(2.2, 2.2)
	add_child(camera)
	camera.make_current()
	_add_background()
	_add_overlay()
	_player = Aircraft.new()
	_player.team = CombatUnit.TEAM_PLAYER
	_player.params = AircraftParams.new()
	_player.global_position = Vector2.ZERO
	_player.visible = false
	add_child(_player)

	_target = Aircraft.new()
	_target.params = (load("res://resources/enemy_f22.tres") as AircraftParams).duplicate(true)
	_target.team = CombatUnit.TEAM_HOSTILE
	_target.callsign = "RAPTOR-01"
	_target.altitude = 5500.0
	_target.speed = 300.0
	_target.heading = 0.25
	_target.is_mission_target = true
	_target.global_position = Vector2(900.0, -500.0)
	add_child(_target)
	_target.set_physics_process(false)
	_target.set_process(false)
	for i in range(10):
		_target._trail_ribbon.add_point(Vector2(-150.0 + i * 15.0, 75.0), 0.25, 0.0)
	_hint_target = Aircraft.new()
	_hint_target.params = (load("res://resources/enemy_yf23.tres") as AircraftParams).duplicate(true)
	_hint_target.team = CombatUnit.TEAM_HOSTILE
	_hint_target.callsign = "BLACKWIDOW-01"
	_hint_target.global_position = Vector2(-1300.0, 700.0)
	add_child(_hint_target)
	_hint_target.set_physics_process(false)
	_hint_target.set_process(false)
	_hint_target.set_sensor_contact_hidden(true, 0.0)
	_add_radar()

	await get_tree().process_frame
	_phase_label.text = "VISIBLE CONTACT — icon, trail, TGT and precise data"
	var visible_err := await _save("res://bench/results/sensor_stealth_visible.png")

	_target.set_sensor_contact_hidden(true)
	await get_tree().create_timer(0.10).timeout
	var first_tween := _target._sensor_contact_tween
	_target.set_sensor_contact_hidden(true)
	var repeated_state_kept_tween := _target._sensor_contact_tween == first_tween \
		and first_tween != null and first_tween.is_valid() and first_tween.is_running()
	await get_tree().create_timer(0.15).timeout
	var mid_alpha := _target._sensor_contact_visual_alpha
	_phase_label.text = "FADE OUT 0.25s — body fades; precise overlays already gone"
	var mid_err := await _save("res://bench/results/sensor_stealth_fade_mid.png")

	await get_tree().create_timer(0.35).timeout
	var hidden_ok := _target.is_hidden_from_player_sensors() \
		and _target._sensor_contact_visual_alpha <= 0.01 \
		and not _target._trail_ribbon.is_processing() \
		and not _target._trail_ribbon.visible
	_phase_label.text = "CONTACT LOST — TGT + ??? in world; anonymous hints remain on radar"
	var hidden_err := await _save("res://bench/results/sensor_stealth_hidden_tgt.png")

	_target.set_sensor_contact_hidden(false)
	await get_tree().create_timer(0.18).timeout
	var reversal_ok := _target._sensor_contact_visual_alpha > 0.0 \
		and _target._trail_ribbon.is_processing() and _target._trail_ribbon.visible
	print("[sensor_stealth_visual] mid_alpha=%.3f hidden=%s reversal=%s idempotent=%s errors=%s" % [
		mid_alpha, str(hidden_ok), str(reversal_ok), str(repeated_state_kept_tween),
		str([visible_err, mid_err, hidden_err])])
	AircraftRenderer.player_ref = null
	get_tree().quit(0 if visible_err == OK and mid_err == OK and hidden_err == OK \
		and mid_alpha > 0.05 and mid_alpha < 0.95 and hidden_ok and reversal_ok \
		and repeated_state_kept_tween else 1)


func _add_background() -> void:
	for i in range(-8, 9):
		var line := Line2D.new()
		line.width = 1.0
		line.default_color = Color(0.2, 0.32, 0.34, 0.55)
		line.points = PackedVector2Array([Vector2(i * 40.0, -220.0), Vector2(i * 40.0, 220.0)])
		add_child(line)
	for i in range(-5, 6):
		var line := Line2D.new()
		line.width = 1.0
		line.default_color = Color(0.2, 0.32, 0.34, 0.55)
		line.points = PackedVector2Array([Vector2(-360.0, i * 40.0), Vector2(360.0, i * 40.0)])
		add_child(line)


func _add_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "ENEMY SENSOR STEALTH — VISUAL QA"
	title.position = Vector2(28.0, 24.0)
	title.add_theme_font_size_override("font_size", 24)
	layer.add_child(title)
	_phase_label = Label.new()
	_phase_label.position = Vector2(28.0, 58.0)
	_phase_label.add_theme_font_size_override("font_size", 16)
	_phase_label.add_theme_color_override("font_color", Color("ffd759"))
	layer.add_child(_phase_label)


func _add_radar() -> void:
	var hud := RadarHudStub.new()
	hud.player_ref = _player
	hud.game_scene = self
	hud.survivor_player = SurvivorPlayer.new()
	add_child(hud)
	var radar := SurvivorHUD.RadarDisplay.new()
	radar.hud = hud
	hud.add_child(radar)
	radar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _save(path: String) -> int:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image().save_png(path)
