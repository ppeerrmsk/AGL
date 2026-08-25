extends Node2D

## 正式 AircraftRenderer 热诱弹样张：敌我双方、两种航向、完整十枚双侧抛射。

const SAMPLE_TIME_S := 1.05


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	RenderingServer.set_default_clear_color(Color("0d1218"))

	var background := ColorRect.new()
	background.color = Color("0d1218")
	background.size = Vector2(1280.0, 720.0)
	add_child(background)

	var title := Label.new()
	title.text = "FLARE VISUAL QA — 10 POINTS / 6 WAVES / 0.90s / DUAL-SIDE EJECTION"
	title.position = Vector2(42.0, 28.0)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("e8eef5"))
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "PARTICLE LIFE 3.0–4.8s   |   SNAPSHOT AGE %.2fs" % SAMPLE_TIME_S
	subtitle.position = Vector2(44.0, 62.0)
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("92a2b2"))
	add_child(subtitle)

	var player := _make_aircraft(CombatUnit.TEAM_PLAYER, Vector2(350.0, 380.0),
		0.0, "PLAYER / NORTH")
	var enemy := _make_aircraft(CombatUnit.TEAM_HOSTILE, Vector2(920.0, 380.0),
		PI * 0.5, "ENEMY / EAST")

	for ac in [player, enemy]:
		AircraftFlares._queue_visual_burst(ac)
		var elapsed := 0.0
		while elapsed < SAMPLE_TIME_S:
			var step := minf(0.05, SAMPLE_TIME_S - elapsed)
			AircraftFlares._update_particles(ac, step)
			elapsed += step
		ac.queue_redraw()
		if ac.flare_visual_burst_emitted != 10 or ac._flare_particles.size() != 10:
			push_error("flare visual setup incomplete for %s" % ac.callsign)
			get_tree().quit(1)
			return

	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := "res://bench/results/flare_visual.png"
	var error := get_viewport().get_texture().get_image().save_png(output)
	print("[flare_visual] player=%d enemy=%d screenshot=%s err=%d" % [
		player._flare_particles.size(), enemy._flare_particles.size(), output, error])
	get_tree().quit(0 if error == OK else 1)


func _make_aircraft(team: int, pos: Vector2, heading: float, label_text: String) -> Aircraft:
	var ac := Aircraft.new()
	var params_path := "res://resources/player/player_f16.tres" \
		if team == CombatUnit.TEAM_PLAYER else "res://resources/enemy_f16.tres"
	ac.params = load(params_path).duplicate(true)
	ac.team = team
	ac.callsign = label_text
	ac.initial_heading_deg = rad_to_deg(heading)
	ac.set_physics_process(false)
	add_child(ac)
	ac.global_position = pos
	ac.heading = heading
	ac.rotation = heading
	ac.altitude = 5000.0
	ac.speed = 280.0

	var label := Label.new()
	label.text = label_text
	label.position = pos + Vector2(-84.0, 185.0)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color",
		Color("6cc7ff") if team == CombatUnit.TEAM_PLAYER else Color("ff8a62"))
	add_child(label)
	return ac
