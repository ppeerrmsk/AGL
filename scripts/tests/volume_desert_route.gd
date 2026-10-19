extends "res://scripts/tests/volume_combat_smoke.gd"
## 只发送真实 UI 输入的路线诊断；不提升玩家、不改任务、不作为 L1/FPS 验收。
var _mode_ref: WeakRef
var _target_zone: StringName = &""
var _navigation_stage := 0
var _selected: Array[String] = []
var _triggered: Array[String] = []
var _completed: Array[String] = []
var _failed: Array[Dictionary] = []
var _samples: Array[Dictionary] = []
var _upgrade_clicks := 0


static func is_isolated_profile(executable: String, user_dir: String) -> bool:
	var directory := executable.replace("\\", "/").simplify_path().get_base_dir().to_lower()
	var actual := user_dir.replace("\\", "/").simplify_path().to_lower().trim_suffix("/")
	return directory.ends_with("/tmp/desert-volume/route-engine") \
		and actual == directory.path_join("profile/godot/app_userdata/agl")


func run_route(mode: Node, duration: float) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mode_ref = weakref(mode)
	mode._zone_mission.mission_triggered.connect(_on_triggered)
	mode._zone_mission.mission_completed.connect(_on_completed)
	mode._zone_mission.mission_failed.connect(_on_failed)
	_check(not mode._bench_mode and not mode._boss_debug_mode and not mode._map_preview_only,
		"route uses real manual Survivor authority")
	_check(is_isolated_profile(OS.get_executable_path(), OS.get_user_data_dir()),
		"route rewards cannot touch the regular player profile")
	var started := Time.get_ticks_msec()
	var limit := started + int(clampf(duration, 30.0, 1200.0) * 1000.0)
	var next_sample := started
	var reason := "duration"
	while Time.get_ticks_msec() < limit:
		await get_tree().create_timer(0.5, true, false, true).timeout
		var current := _live_mode()
		if current == null:
			reason = "scene_released"
			break
		if Time.get_ticks_msec() >= next_sample:
			_samples.append(_snapshot(current))
			print("[Volume route sample] ", JSON.stringify(_samples.back()))
			next_sample = Time.get_ticks_msec() + 10000
		if current.is_game_over:
			reason = "victory" if current._is_victory else "game_over"
			break
		_drive_inputs(current)
	var current := _live_mode()
	if current != null:
		_samples.append(_snapshot(current))
		await RenderingServer.frame_post_draw
		_check(get_viewport().get_texture().get_image().save_png(
			"res://bench/results/volume_desert_route.png") == OK, "natural route battle captured")
	_check(not _selected.is_empty(), "actual tactical map click selects an available zone")
	var selected_triggered := false
	for zone_id in _selected:
		selected_triggered = selected_triggered or _triggered.has(zone_id)
	_check(selected_triggered, "naturally reaches a selected zone and triggers its real mission")
	var report := {"scope": "natural_route_diagnostic", "full_run_accepted": false,
		"fps_accepted": false, "elapsed_wall_s": (Time.get_ticks_msec() - started) / 1000.0,
		"reason": reason, "user_dir": OS.get_user_data_dir(), "selected": _selected,
		"triggered": _triggered, "completed": _completed, "failed": _failed,
		"upgrade_clicks": _upgrade_clicks, "samples": _samples}
	current = _live_mode()
	if current != null:
		var released: WeakRef = weakref(current)
		current._quit_to_main_menu()
		_check(await _wait_for_scene_release(released), "route exit releases actual Survivor and map")
		await get_tree().process_frame
		_check(get_tree().current_scene != null
			and get_tree().current_scene.scene_file_path == "res://scenes/main_menu.tscn"
			and not get_tree().paused, "route exit returns to unpaused main menu")
	report["pass"] = _pass
	report["fail"] = _fail
	var file := FileAccess.open("res://bench/results/volume_desert_route.json", FileAccess.WRITE)
	if file == null:
		_check(false, "route report is writable")
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("[Volume route] pass=%d fail=%d selected=%s triggered=%s completed=%s reason=%s; NOT L1 or FPS acceptance" % [
		_pass, _fail, _selected, _triggered, _completed, reason])
	get_tree().quit(0 if _fail == 0 else 1)


func _live_mode() -> Node:
	var value: Variant = _mode_ref.get_ref() if _mode_ref != null else null
	if typeof(value) == TYPE_OBJECT and is_instance_valid(value) and value is Node:
		return value as Node
	return null


func _drive_inputs(mode: Node) -> void:
	if mode.upgrade_ui.visible:
		for button: Button in mode.upgrade_ui._buttons:
			if button.is_visible_in_tree() and not button.disabled:
				var center := button.get_global_rect().get_center()
				_mouse(MOUSE_BUTTON_LEFT, center, true)
				_mouse(MOUSE_BUTTON_LEFT, center, false)
				_upgrade_clicks += 1
				return
		return
	var tactical: Node = mode._tactical_map
	if _navigation_stage == 1 and tactical.is_open():
		var point: Vector2 = tactical._world_to_map(mode._zone_data.get_zone_center(_target_zone),
			tactical._map_panel.size)
		if tactical._zone_id_at(point) != _target_zone:
			return  # 不绕过隐藏/重叠/命中门，保留失败证据。
		var screen: Vector2 = tactical._map_panel.get_global_transform_with_canvas() * point
		_mouse(MOUSE_BUTTON_LEFT, screen, true)
		_mouse(MOUSE_BUTTON_LEFT, screen, false)
		if mode._zone_data.selected_id == _target_zone:
			_selected.append(String(_target_zone))
			_navigation_stage = 2
		return
	if _navigation_stage == 2 and tactical.is_open() and not tactical._detail_prepare_in_progress:
		_key(KEY_TAB)
		_navigation_stage = 3
		return
	if get_tree().paused or tactical.is_open():
		return
	if _navigation_stage == 3:
		var state: int = mode._zone_data.get_state(_target_zone)
		if state != ZoneData.State.CLEARED and state != ZoneData.State.FAILED:
			return
		_navigation_stage = 0
	if _navigation_stage == 0:
		var player: Variant = mode.player_aircraft
		if typeof(player) != TYPE_OBJECT or not is_instance_valid(player) or not player is Aircraft:
			return
		var nearest := INF
		for zone: Dictionary in mode._zone_data.get_zone_definitions():
			var zone_id := StringName(zone.id)
			if mode._zone_data.get_state(zone_id) != ZoneData.State.AVAILABLE or mode._zone_data.is_airfield(zone_id):
				continue
			var distance: float = player.global_position.distance_squared_to(mode._zone_data.get_zone_center(zone_id))
			if distance < nearest:
				nearest = distance
				_target_zone = zone_id
		if nearest < INF:
			_key(KEY_TAB)
			_navigation_stage = 1


func _snapshot(mode: Node) -> Dictionary:
	var player: Variant = mode.player_aircraft
	var player_state := {}
	if typeof(player) == TYPE_OBJECT and is_instance_valid(player) and player is Aircraft:
		player_state = {"position": str(player.global_position), "hp": player.hp,
			"target_position": str(player.target_position)}
	return {"game_time": mode.game_time, "paused": get_tree().paused,
		"navigation_stage": _navigation_stage, "zone": String(_target_zone),
		"zone_state": mode._zone_data.get_state(_target_zone), "player": player_state,
		"kills": mode._spawner.kill_count, "units": CombatUnit.all_units.size(),
		"projection_error_px": mode.volume_probe.max_projection_error_px,
		"terrain": mode.volume_probe._satellite_ground.debug_state()}


func _on_triggered(zone_id: StringName) -> void:
	_triggered.append(String(zone_id))


func _on_completed(zone_id: StringName) -> void:
	_completed.append(String(zone_id))


func _on_failed(zone_id: StringName, reason: String) -> void:
	_failed.append({"zone": String(zone_id), "reason": reason})
