extends Node2D

const OverlayScript := preload("res://scripts/survivor/brake_steering_overlay.gd")


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	TranslationServer.set_locale("zh")
	var background := ColorRect.new()
	background.color = Color("101820")
	background.size = Vector2(1280.0, 720.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_add_brake_aircraft()

	# 三个 production 控件同屏覆盖：按住、有效拖拽、失速锁定。
	_add_sample(Vector2(250.0, 360.0), 0.0, false)
	_add_sample(Vector2(640.0, 360.0), 0.72, false)
	_add_sample(Vector2(1030.0, 360.0), -0.88, true)

	# Visual bench 首帧可能恰逢 DisplayServer resize 的空交换帧；等待 8 帧再抓稳定画面。
	for _frame in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://bench/results/brake_steering_overlay_visual.png"
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("[brake_steering_overlay_visual] screenshot=%s err=%d" % [path, err])
	get_tree().quit(0 if err == OK else 1)


func _add_brake_aircraft() -> void:
	var ac := Aircraft.new()
	ac.params = (load("res://resources/player/player_f16.tres") as AircraftParams).duplicate(true)
	ac.team = CombatUnit.TEAM_PLAYER
	ac.callsign = "BRAKE-GUN-QA"
	ac.initial_heading_deg = 0.0
	ac.hard_brake = true
	ac.set_physics_process(false)
	AircraftRenderer.player_ref = ac
	add_child(ac)
	ac.global_position = Vector2(640.0, 680.0)
	ac.heading = 0.0
	ac.rotation = 0.0
	ac.speed = 438.0 / 3.6
	ac.queue_redraw()


func _add_sample(anchor: Vector2, steer: float, stall_locked: bool) -> void:
	var overlay = OverlayScript.new()
	overlay.position = Vector2.ZERO
	overlay.size = Vector2(1280.0, 720.0)
	add_child(overlay)
	overlay.begin(anchor)
	overlay.update_steer(anchor + Vector2(steer * 110.0, 0.0), steer)
	overlay.set_stall_locked(stall_locked)
	overlay.set_flight_data(438.0 - steer * 65.0, 1200.0,
		220 - roundi(absf(steer) * 70.0), 320, false)
