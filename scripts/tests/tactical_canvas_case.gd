extends RefCounted
const Pacing := preload("res://scripts/util/display_pacing.gd")
const Overlay := preload("res://scripts/ui/world_unit_status_overlay.gd")


class MotionDriver extends Node:
	var aircraft: Aircraft
	var missile: Missile
	func _physics_process(delta: float) -> void:
		for unit: Node2D in [aircraft, missile]:
			unit.interp_prev_xform = unit.transform
			unit.interp_prev_tick = Engine.get_physics_frames()
			unit.position += Vector2(180.0, 25.0) * delta
			unit.rotation += delta * 0.4


static func run(host: Node) -> int:
	var failures := 0
	var old_units := CombatUnit.all_units.duplicate()
	var old_player := AircraftRenderer.safe_player_ref()
	var stage := Node2D.new()
	host.add_child(stage)
	var ac := Aircraft.new()
	ac.params = load("res://resources/playable_f14_base.tres").duplicate(true)
	ac.team = 0
	stage.add_child(ac)
	ac.set_physics_process(false)
	ac.position = Vector2(300, 200)
	ac.target_position = Vector2(700, 150)
	ac._predicted_path_world = PackedVector2Array([Vector2(200, 200), Vector2(500, 180), Vector2(700, 150)])
	ac._predicted_path_healths = PackedFloat32Array([1.0, 0.5, 0.8])
	AircraftRenderer.player_ref = ac
	CombatUnit.all_units.assign([ac])
	var missile := Missile.new()
	missile.params = load("res://resources/playable_f14_base.tres").missile.duplicate(true)
	missile.team = 1
	missile.target = ac
	missile.position = Vector2(100, 400)
	missile.heading = PI * 0.25
	stage.add_child(missile)
	missile.set_physics_process(false)
	var camera := Camera2D.new()
	stage.add_child(camera)
	camera.position = Vector2(400, 200)
	camera.ignore_rotation = false
	camera.make_current()
	var layer := CanvasLayer.new()
	stage.add_child(layer)
	var overlay := Overlay.new()
	layer.add_child(overlay)
	for zoom in [0.2, 0.55, 1.0, 3.0]:
		camera.zoom = Vector2.ONE * zoom
		camera.rotation += 0.1
		camera.force_update_scroll()
		AircraftRenderer.update_prediction_display(ac, 1.0 / 120.0)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		overlay._sync_tactical_canvases()
		var panel: Node2D = overlay._tactical_panels.get(ac.get_instance_id())
		var ok := panel != null
		if ok:
			var screen_from := panel.get_global_transform_with_canvas() * Vector2.ZERO
			var screen_end := panel.get_global_transform_with_canvas() * AircraftRenderer.tactical_local_point(ac, panel, ac.target_position)
			ok = screen_from.distance_to(Pacing.display_screen_origin(ac)) < 0.01 and screen_end.distance_to(ac.get_canvas_transform() * ac.target_position) < 0.01
		if not ok:
			failures += 1
		var warning: Node2D = overlay._tactical_panels.get(missile.get_instance_id())
		if warning == null:
			failures += 1
		else:
			var end := warning.get_global_transform_with_canvas() * AircraftRenderer.tactical_local_point(missile, warning, Pacing.display_origin(ac))
			if end.distance_to(Pacing.display_screen_origin(ac)) > 0.01:
				failures += 1
		print("[TacticalCanvas] zoom=%s endpoint_coherence=%s missile_warning=%s" % [zoom, ok, warning != null])
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://tmp/map_visual_qa/tactical_canvas")
			host.get_viewport().get_texture().get_image().save_png("res://tmp/map_visual_qa/tactical_canvas/zoom_%s.png" % zoom)
	var state_before := ac._predicted_path_smooth_world.duplicate()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if ac._predicted_path_smooth_world != state_before:
		failures += 1
		printerr("[TacticalCanvas] draw mutated prediction")
	# 真物理步移动 + 非整数物理相位，不能只验证静止坐标恒等式。
	var saved_fps := Engine.max_fps
	Engine.max_fps = 120
	var mover := MotionDriver.new()
	mover.aircraft = ac
	mover.missile = missile
	stage.add_child(mover)
	var max_error := 0.0
	var interpolated_frames := 0
	for frame in range(48):
		await host.get_tree().process_frame
		camera.rotation += 0.002
		camera.offset = Vector2(sin(float(frame) * 0.1) * 12.0, 6.0)
		camera.force_update_scroll()
		AircraftRenderer.update_prediction_display(ac, 1.0 / 120.0)
		overlay._sync_tactical_canvases()
		var panel: Node2D = overlay._tactical_panels.get(ac.get_instance_id())
		var warning: Node2D = overlay._tactical_panels.get(missile.get_instance_id())
		if panel == null or warning == null:
			failures += 1
			continue
		var origin := Pacing.display_screen_origin(ac)
		max_error = maxf(max_error, (panel.get_global_transform_with_canvas() * Vector2.ZERO).distance_to(origin))
		var endpoint := warning.get_global_transform_with_canvas() * AircraftRenderer.tactical_local_point(missile, warning, Pacing.display_origin(ac))
		max_error = maxf(max_error, endpoint.distance_to(origin))
		max_error = maxf(max_error, ac._predicted_path_smooth_world[0].distance_to(Pacing.display_origin(ac)))
		if Pacing.display_origin(ac).distance_to(ac.global_position) > 0.01:
			interpolated_frames += 1
	mover.set_physics_process(false)
	mover.queue_free()
	Engine.max_fps = saved_fps
	if max_error > 0.01 or interpolated_frames == 0:
		failures += 1
	print("[TacticalCanvas] moving_frames=48 interpolated=%d max_endpoint_error_px=%.5f" % [interpolated_frames, max_error])
	# 非玩家无人机也必须只因暴露环得到代理，归零后释放。
	ac.team = 1
	ac.is_drone = true
	ac.deadair_exposure_ratio = 0.5
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if not overlay.has_tactical_canvas(ac):
		failures += 1
	ac.deadair_exposure_ratio = 0.0
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if overlay.has_tactical_canvas(ac):
		failures += 1
	ac.team = 0
	ac.is_drone = false
	var ground := CombatUnit.new()
	stage.add_child(ground)
	CombatUnit.all_units.append(ground)
	ground.deadair_exposure_ratio = 0.5
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if not overlay.has_tactical_canvas(ground):
		failures += 1
	ground.take_damage(1000000.0, null, "gun")
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if overlay.has_tactical_canvas(ground):
		failures += 1
	ground.queue_free()
	ac.show_tactic_popup("TEST")
	ac.take_damage(1000000.0, null, "gun")
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if not ac.is_destroyed or not overlay.has_tactical_canvas(ac):
		failures += 1
	ac._tactic_popup_timer = 0.0
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if overlay.has_tactical_canvas(ac):
		failures += 1
	missile.queue_free()
	ac.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	overlay._sync_tactical_canvases()
	if not overlay._tactical_panels.is_empty():
		failures += 1
	stage.queue_free()
	await host.get_tree().process_frame
	CombatUnit.all_units.assign(old_units)
	AircraftRenderer.player_ref = old_player
	print("[TacticalCanvas] damage/free/exit reached end failures=%d" % failures)
	return failures
