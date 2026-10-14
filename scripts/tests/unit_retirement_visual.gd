extends "res://scripts/survivor/survivor_mode.gd"

## 真实 Survivor 镜头/LOD/任务失败链。48 地面 + 36 架撤离机，反复移开、返回。
var _retire_ready := false
var _retire_elapsed := 0.0
var _retire_stage := 0
var _retire_ground: Array[GroundUnit] = []
var _retire_air: Array = []
var _retire_positions: Array[Vector2] = []
var _retire_origin := Vector2(10000.0, 6000.0)
var _retire_fail := 0
var _retire_last_us := 0
var _retire_frames: Array[float] = []
var _retire_report: PackedStringArray = []

func _setup_bench_scenario() -> void:
	# 此专项固定 48+36 名演员；正常混战另跑标准 C1/C2，不继承默认 stress 的随机补员/升级。
	seed(42)
	player_aircraft.invulnerable = true
	_spawner._opening_garrison_pending = false
	_spawner._spawn_timer = 100000.0
	_bench_wall_started_msec = Time.get_ticks_msec()
	_bench_last_heartbeat_msec = _bench_wall_started_msec
	PerfBuckets.configure_frame_trace(true)

func _ready() -> void:
	super._ready()
	_zone_data = _bench_new_isolated_zone_data()
	for zone in _zone_data.get_zone_definitions():
		_zone_data.set_state(zone["id"], ZoneData.State.LOCKED)
	_zone_mission = ZoneMission.new()
	add_child(_zone_mission)
	_zone_mission.setup(self, _zone_data, player_aircraft,
		_sam_scene, _sam_params, _aa_scene, _aa_params, bullet_manager, missile_manager, _spawner)
	_spawner.set_zone_mission(_zone_mission)
	_camera_ctrl.follow_enabled = false
	_bench_set_camera_zoom(0.3)
	camera.position = _retire_origin
	player_aircraft.position = _retire_origin - Vector2(6000.0, 0.0)
	for i in range(48):
		var ground: GroundUnit = _aa_scene.instantiate()
		ground.params = _aa_params.duplicate(true)
		ground.team = CombatUnit.TEAM_HOSTILE
		ground.position = _retire_origin + Vector2((i % 8 - 4) * 180.0, (i / 8 - 3) * 180.0)
		add_child(ground)
		_retire_ground.append(ground)
	for i in range(36):
		var ac := Aircraft.new()
		ac.params = player_aircraft.params.duplicate(true)
		ac.params.display_name = "RETREAT"
		ac.team = CombatUnit.TEAM_HOSTILE
		ac.position = _retire_origin + Vector2((i % 6 - 3) * 170.0, (i / 6 - 3) * 170.0)
		ac.heading = PI / 2.0
		ac.altitude = 5500.0
		ac.speed = ac.params.cruise_speed / 3.6
		ac.set_meta("skip_far_cleanup", true)
		add_child(ac)
		var ai := AIController.new()
		ai.aircraft = ac
		ac.add_child(ai)
		_retire_air.append(ac)
		_retire_positions.append(ac.position)
	_zone_mission._spawned_zones[&"A"] = _retire_ground.duplicate()
	_zone_mission._garrison_zones[&"A"] = _retire_air.duplicate()
	_zone_mission._triggered_zones[&"A"] = true
	_zone_mission.fail_zone(&"A", "visual_retirement")
	var phases := [0, 0, 0]
	for value: Variant in _retire_air:
		phases[int(value.get_meta(&"dense_battle_sim_phase", 0)) % 3] += 1
	_retire_report.append("simulation_phases=%s" % [phases])
	_retire_last_us = Time.get_ticks_usec()
	_retire_ready = true

func _process(delta: float) -> void:
	if not _retire_ready:
		return
	_retire_elapsed += delta
	var now := Time.get_ticks_usec()
	if _retire_elapsed > 2.0:
		var frame_s := float(now - _retire_last_us) / 1000000.0
		_retire_frames.append(frame_s)
		if frame_s > 1.0 / 60.0:
			_retire_report.append("slow_frame t=%.3f stage=%d ms=%.3f" % [_retire_elapsed, _retire_stage, frame_s * 1000.0])
	_retire_last_us = now
	if _retire_stage == 0 and _retire_elapsed >= 2.0:
		camera.position = Vector2(-7000.0, -7000.0)
		_retire_stage = 1
	if _retire_stage == 1 and _retire_elapsed >= 5.0:
		camera.position = _retire_origin
		camera.ignore_rotation = false
		camera.rotation = deg_to_rad(30.0)
		_retire_stage = 2
	if _retire_stage == 2 and _retire_elapsed >= 7.0:
		_check_retained_roster()
		if _bench_duration <= 10.0:
			_capture_retired_world()
		_retire_stage = 3
	if _retire_stage == 3 and _retire_elapsed >= 8.0:
		camera.position = Vector2(-7000.0, -7000.0)
		_retire_stage = 4
	if _retire_stage == 4 and _retire_elapsed >= 10.0:
		camera.position = _retire_origin
		camera.rotation = 0.0
		_bench_set_camera_zoom(0.55)
		_retire_stage = 5
	super._process(delta)
	if _retire_stage == 5 and _retire_elapsed >= 14.0:
		_retire_stage = 6
		_check_retained_roster()
		var panel := AircraftRenderer.status_panel_entry(_retire_ground[0].get_instance_id())
		var lines: PackedStringArray = panel.get("lines", PackedStringArray())
		_retire_check(lines.size() >= 3, "retained ground refreshes detailed labels after camera zoom")
		var moved := 0
		for i in range(_retire_air.size()):
			var value: Variant = _retire_air[i]
			if is_instance_valid(value) and value.position.distance_to(_retire_positions[i]) > 400.0:
				moved += 1
		_retire_check(moved == 36, "all 36 aircraft physically move through offscreen LOD")
		if _bench_duration < 60.0:
			_finish_retirement_visual()
	if _retire_stage == 6 and _bench_duration >= 60.0 and _retire_elapsed >= _bench_duration:
		_retire_stage = 7
		var escaped := 0
		for value: Variant in _retire_air:
			if not is_instance_valid(value):
				escaped += 1
		_retire_check(escaped == 36 and _zone_mission._pending_despawn.is_empty(),
			"all 36 aircraft actually fly out and finish deferred cleanup")
		_retire_check(_retire_ground.size() == 48 and is_instance_valid(_retire_ground[0]),
			"ground remains after all aircraft physically leave")
		_finish_retirement_visual()

func _finish_retirement_visual() -> void:
	var below := 0
	var worst := 0.0
	for frame in _retire_frames:
		worst = maxf(worst, frame)
		if frame > 1.0 / 60.0:
			below += 1
	if _bench_duration > 10.0:
		_retire_check(below == 0, "rendered wall-clock frames stay above 60 FPS")
	_retire_report.append("ground=48 aircraft=36 frames=%d below60=%d worst_ms=%.3f failures=%d" % [_retire_frames.size(), below, worst * 1000.0, _retire_fail])
	print("[UnitRetirement] " + _retire_report[-1])
	var output := FileAccess.open("res://bench/results/unit_retirement_%d.txt" % Time.get_ticks_msec(), FileAccess.WRITE)
	output.store_string("\n".join(_retire_report))
	output.store_string("\n" + PerfBuckets.format_frame_trace_dump())
	output.store_string("\n" + PerfBuckets.format_full_dump())
	get_tree().quit(0 if _retire_fail == 0 else 1)

func _check_retained_roster() -> void:
	var ground_ok := _retire_ground.size() == 48
	for ground in _retire_ground:
		ground_ok = ground_ok and is_instance_valid(ground) and not ground.is_queued_for_deletion() \
			and ground.process_mode == Node.PROCESS_MODE_DISABLED
	_retire_check(ground_ok, "camera return retains all 48 original ground units without active processing")
	var air_alive := 0
	for value: Variant in _retire_air:
		if is_instance_valid(value) and not value.is_queued_for_deletion():
			air_alive += 1
	_retire_check(air_alive == 36, "camera return retains all 36 aircraft still flying inside world")

func _capture_retired_world() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://bench/results/unit_retirement_return.png")

func _retire_check(ok: bool, label: String) -> void:
	_retire_report.append("%s %s" % ["PASS" if ok else "FAIL", label])
	print("[UnitRetirement] " + _retire_report[-1])
	if not ok:
		_retire_fail += 1
