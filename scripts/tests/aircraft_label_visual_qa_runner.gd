extends Node2D

## 5x 近景回归：使用真实 F-14 参数、Camera2D 与 AircraftRenderer 标签路径。

const PreviewAircraft := preload("res://scripts/tests/aircraft_silhouette_preview.gd")
const PlayableSetup := preload("res://scripts/survivor/survivor_playable_setup.gd")


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	RenderingServer.set_default_clear_color(Color("d7dcda"))

	var camera := Camera2D.new()
	camera.position = Vector2(960.0, 540.0)
	camera.zoom = Vector2(5.0, 5.0)
	add_child(camera)
	camera.make_current()

	var aircraft := PreviewAircraft.new()
	var params := load("res://resources/player/player_f14.tres") as AircraftParams
	var profile := load("res://resources/playable_f14.tres") as PlayableAircraft
	if params == null or profile == null:
		push_error("[aircraft_label_visual] F-14 runtime resources missing")
		get_tree().quit(1)
		return
	aircraft.params = params.duplicate(true)
	PlayableSetup.deep_dup_weapons(aircraft.params)
	PlayableSetup.apply(aircraft, profile)
	aircraft.callsign = "Ultra"
	aircraft.altitude = 10000.0
	aircraft.flat_altitude = true
	aircraft.speed = 310.0
	aircraft.heading = 0.18
	aircraft.rotation = aircraft.heading
	aircraft.g_load = 6.4
	aircraft.vertical_speed = -45.0
	aircraft.altitude_action = Aircraft.AltitudeAction.DIVE
	aircraft.hide_data_label = true
	aircraft._missile_reload_active = true
	aircraft.missile_reload_progress = 0.2
	# 故意放在非整数屏幕坐标，覆盖高速运动中最容易发虚的亚像素相位。
	aircraft.position = camera.position + Vector2(0.37, -0.43)
	aircraft.draw_runtime_label = true
	add_child(aircraft)
	AircraftRenderer.player_ref = aircraft
	aircraft.queue_redraw()

	var overlay := CanvasLayer.new()
	add_child(overlay)
	var title := Label.new()
	title.text = "AIRCRAFT LABEL QA — F-14 / CAMERA 5.0x / FRACTIONAL MOTION PHASE"
	title.position = Vector2(42.0, 30.0)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("182026"))
	overlay.add_child(title)
	var note := Label.new()
	note.text = "PASS TARGET: detailed ALT reads HIGH ↓ DIVE on one line; no standalone altitude-action row"
	note.position = Vector2(42.0, 62.0)
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color("3c4a52"))
	overlay.add_child(note)

	var velocity_world := Vector2(sin(aircraft.heading), -cos(aircraft.heading)) \
		* aircraft.speed * CombatUnit.PIXELS_PER_METER
	for _frame in range(6):
		aircraft.position += velocity_world / 60.0
		aircraft.heading += 0.012
		aircraft.rotation = aircraft.heading
		aircraft.queue_redraw()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := "res://bench/results/aircraft_label_visual.png"
	var error := get_viewport().get_texture().get_image().save_png(output)
	print("[aircraft_label_visual] screenshot=%s err=%d" % [output, error])
	AircraftRenderer.player_ref = null
	get_tree().quit(0 if error == OK else 1)
