extends Node
## 验证实际 F6 场景的输入与重开。仅显式 Visual smoke 创建，不加入手动战局。
var _pass := 0
var _fail := 0


func run(mode: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tree := get_tree()
	await tree.create_timer(10.0, true, false, true).timeout
	print("[Volume arrival diagnostic] paused=%s director_state=%s processing=%s seq=%s elapsed=%.3f cinematic=%s time_paused=%s" % [
		tree.paused, Presentation.state, Presentation.is_processing(), Presentation._player.seq_name,
		Presentation._player.elapsed, Presentation._cine_active, Presentation.time.is_hard_paused()])
	# 先等真实演出交还操控，禁止在尚未交还时用 Tab/Esc 意外解除它的暂停。
	var arrival_deadline := Time.get_ticks_msec() + 10000
	while tree.paused and Time.get_ticks_msec() < arrival_deadline:
		await tree.process_frame
	if tree.paused:
		_check(false, "arrival hands control back without manual unpause")
		tree.quit(1)
		return
	await tree.create_timer(0.25, true, false, true).timeout
	_check(is_instance_valid(mode), "manual scene survives without bench timeout")
	if not is_instance_valid(mode):
		tree.quit(1)
		return
	_check(mode._boss_debug_mode and not mode._bench_mode, "real manual Boss Debug, not bench AI")
	_check(not mode.archive_enabled(), "manual experiment excluded from career")
	_check(mode._boss_debug_id == "MOTHER_GOOSE", "Mother Goose selected")
	_check(mode._squad_members_alive().size() >= 4, "real reference squad created")
	_check(mode._spawner.get_boss() is MotherGooseBoss, "real Mother Goose encounter created")
	print("[Volume manual diagnostic] paused=%s mode_process=%s probe_process=%s probe_updates=%d members=%d units=%d camera_zoom=%s target_zoom=%s player_visible=%s cloak=%.5f sensor=%.5f alpha=%.5f hidden=%s\n%s" % [
		tree.paused, mode.is_processing(), mode.volume_probe.is_processing(), mode.volume_probe._updates,
		mode.volume_probe._members.size(), CombatUnit.all_units.size(), mode.camera.zoom,
		mode._camera_ctrl.target_zoom, mode.player_aircraft.is_visible_in_tree(), mode.player_aircraft._cloak_alpha,
		mode.player_aircraft._sensor_contact_visual_alpha, mode.player_aircraft.self_modulate.a,
		mode.player_aircraft.is_hidden_from_player_sensors(), mode.volume_probe.summary()])
	_check(mode.volume_probe.bodies_enabled and mode.volume_probe.max_body_count > 0,
		"3D bodies attached to actual combat actors")
	_check(mode.volume_probe.max_dedicated_bodies > 0 and mode.volume_probe.dedicated_visible_frames > 0,
		"batch A dedicated aircraft actually visible in manual battle")
	_check(mode.volume_probe.goose_seen, "actual Goose rendered through 3D adapter")
	_check(mode.volume_probe.goose_visible_frames > 0, "3D Goose visible during paused arrival camera")
	_check(mode.volume_probe._scenario == "volume_3d_manual", "no forced benchmark Boss camera")
	var screen: Vector2 = get_viewport().get_visible_rect().size * Vector2(0.22, 0.5)
	var world: Vector2 = mode._camera_ctrl.screen_to_world(screen)
	_mouse(MOUSE_BUTTON_LEFT, screen, true)
	_mouse(MOUSE_BUTTON_LEFT, screen, false)
	_check(mode.player_aircraft.target_position.distance_to(world) < 0.1,
		"real mouse press/release submits matching world move order")
	var zoom_before: float = mode._camera_ctrl.target_zoom
	_mouse(MOUSE_BUTTON_WHEEL_DOWN, screen, true)
	_mouse(MOUSE_BUTTON_WHEEL_DOWN, screen, false)
	_check(not is_equal_approx(mode._camera_ctrl.target_zoom, zoom_before), "wheel changes user zoom")
	_key(KEY_SPACE)
	_check(mode._camera_ctrl.follow_enabled and mode._camera_ctrl.follow_target == mode.player_aircraft,
		"Space follows player, not Boss")
	_key(KEY_TAB)
	await tree.create_timer(0.4, true, false, true).timeout
	_check(mode._tactical_map.is_open() and tree.paused, "Tab opens build and pauses")
	_key(KEY_TAB)
	await tree.create_timer(0.4, true, false, true).timeout
	_check(not mode._tactical_map.is_open() and not tree.paused, "Tab closes and resumes")
	_key(KEY_ESCAPE)
	await tree.create_timer(0.4, true, false, true).timeout
	_check(tree.paused, "Esc pauses manual battle")
	_key(KEY_ESCAPE)
	await tree.create_timer(0.4, true, false, true).timeout
	_check(not tree.paused, "Esc resumes manual battle")
	await tree.create_timer(3.0, true, false, true).timeout
	_check(mode.volume_probe.max_projection_error_px < 0.1, "camera/input projection remains aligned")
	await RenderingServer.frame_post_draw
	var capture_error := get_viewport().get_texture().get_image().save_png(
		"res://bench/results/volume_3d_combat_manual.png")
	_check(capture_error == OK, "manual combat screenshot saved")
	# 重开走正式 F8，而非手工再 new；验证旧场景释放与新场景仍处于三维手动模式。
	var previous: WeakRef = weakref(mode)
	_key(KEY_F8)
	if not await _wait_for_scene_release(previous):
		_check(false, "F8 scene transition finishes within six seconds")
		tree.quit(1)
		return
	await tree.process_frame
	mode = tree.current_scene
	_check(previous.get_ref() == null, "F8 frees previous combat scene")
	_check(mode.scene_file_path == "res://scenes/tests/volume_3d_combat.tscn",
		"F8 reloads experiment rather than switching to flat production scene")
	_check(mode._boss_debug_mode and not mode._bench_mode and is_instance_valid(mode.volume_probe),
		"restarted game remains manual with 3D adapter")
	# 重开会播放原 7 秒登场演出，必须等其释放全场，不能在暂停首帧误判新绑定。
	await tree.create_timer(8.0, true, false, true).timeout
	_check(mode.volume_probe.max_body_count > 0, "new actor bindings populated after restart")
	# 走原退出入口，跨下一帧验证显示层/实体释放，不修改用户局外档案。
	var restarted: WeakRef = weakref(mode)
	mode._quit_to_main_menu()
	if not await _wait_for_scene_release(restarted):
		_check(false, "quit scene transition finishes within six seconds")
		tree.quit(1)
		return
	await tree.process_frame
	_check(restarted.get_ref() == null, "real quit releases experiment and its bindings")
	_check(tree.current_scene.scene_file_path == "res://scenes/main_menu.tscn" and not tree.paused,
		"quit returns to unpaused main menu")
	print("[Volume manual smoke] pass=%d fail=%d; functional input/lifecycle only, NOT a 60 FPS gate" % [_pass, _fail])
	tree.quit(1 if _fail > 0 else 0)


func _wait_for_scene_release(previous: WeakRef) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while previous.get_ref() != null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return previous.get_ref() == null


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)


func _mouse(button: MouseButton, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.global_position = point
	event.pressed = pressed
	# 坐标已是渲染视口坐标；避免 Input.parse_input_event 再按宿主窗口拉伸一次。
	get_viewport().push_input(event, true)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("[Volume manual] PASS: " + label)
	else:
		_fail += 1
		push_error("Volume manual: " + label)
