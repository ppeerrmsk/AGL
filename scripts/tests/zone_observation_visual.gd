extends "res://scripts/survivor/survivor_mode.gd"

class MeasuredMission extends ZoneMission:
	var sampling_us := 0
	func _spawn_ground_garrison(zone_id: StringName, zone: Dictionary) -> void:
		var started := Time.get_ticks_usec()
		super._spawn_ground_garrison(zone_id, zone)
		print("[ZoneObservation] ground_ms=%.3f" % ((Time.get_ticks_usec() - started) / 1000.0))
	func _register_zone_atmosphere(zone_id: StringName, mission_type: String, zone: Dictionary) -> void:
		var started := Time.get_ticks_usec()
		super._register_zone_atmosphere(zone_id, mission_type, zone)
		print("[ZoneObservation] atmosphere_ms=%.3f" % ((Time.get_ticks_usec() - started) / 1000.0))
	func _find_valid_spawn_pos(center: Vector2, scatter: float, placed: Array[Vector2], polys: Array = []) -> Vector2:
		var started := Time.get_ticks_usec()
		var result := super._find_valid_spawn_pos(center, scatter, placed, polys)
		sampling_us += Time.get_ticks_usec() - started
		return result
	func _spawn_zone_defenders(zone_id: StringName, zone: Dictionary, mission_type: String = "ground") -> void:
		var started := Time.get_ticks_usec()
		super._spawn_zone_defenders(zone_id, zone, mission_type)
		print("[ZoneObservation] sampling_ms=%.3f defenders_ms=%.3f" % [sampling_us / 1000.0, (Time.get_ticks_usec() - started) / 1000.0])

## 正式 Survivor 镜头 → ZoneMission → 地面工厂 → 真实绘制；不在测试中直接调用预加载。
var _observation_ready := false
var _observation_time := 0.0
var _observation_stage := 0
var _observation_ids: Array[int] = []
var _observation_fail := 0
var _observation_deltas: Array[float] = []
var _observation_last_us := 0
var _observation_report: PackedStringArray = []
var _observation_first_view_ms := 0.0

func _ready() -> void:
	super._ready()
	_zone_data = _bench_new_isolated_zone_data()
	for zone in _zone_data.get_zone_definitions():
		_zone_data.set_state(zone["id"], ZoneData.State.LOCKED)
	_zone_data.set_state(&"A", ZoneData.State.AVAILABLE)
	_zone_data._difficulties[&"A"] = 2
	_zone_data.set_mission_type(&"A", "ground")
	_zone_data._rewards[&"A"] = {"id": "view_probe"}
	_zone_mission = MeasuredMission.new()
	add_child(_zone_mission)
	_zone_mission.setup(self, _zone_data, player_aircraft,
		_sam_scene, _sam_params, _aa_scene, _aa_params, bullet_manager, missile_manager, _spawner)
	_spawner.set_zone_mission(_zone_mission)
	_camera_ctrl.follow_enabled = false
	_bench_set_camera_zoom(0.3)
	camera.position = Vector2(9000.0, 9000.0)
	player_aircraft.position = camera.position
	_observation_ready = true

func _process(delta: float) -> void:
	if not _observation_ready:
		return
	_observation_time += delta
	if _observation_time > 1.0:
		_observation_deltas.append(float(Time.get_ticks_usec() - _observation_last_us) / 1000000.0)
	_observation_last_us = Time.get_ticks_usec()
	var first_view := _observation_stage == 0 and _observation_time >= 2.0
	if first_view:
		_observation_check(_zone_mission._spawned_zones.is_empty(), "distant unseen zone stays latent")
		camera.position = _zone_data.get_zone_center(&"A")
		camera.ignore_rotation = false
		camera.rotation = deg_to_rad(30.0)
		_observation_stage = 1
	var before_process := Time.get_ticks_usec()
	super._process(delta)
	if first_view:
		_observation_first_view_ms = float(Time.get_ticks_usec() - before_process) / 1000.0
		print("[ZoneObservation] first_view_process_ms=%.3f" % _observation_first_view_ms)
		var targets: Array = _zone_mission._spawned_zones.get(&"A", [])
		_observation_check(not targets.is_empty(), "targets exist on first camera frame")
		for value: Variant in targets:
			if typeof(value) == TYPE_OBJECT and is_instance_valid(value) and value is GroundUnit:
				_observation_ids.append(value.get_instance_id())
		_observation_check(_observation_ids.size() == targets.size() and not targets.is_empty(), "real ground factory roster")
		_observation_check(_zone_mission._triggered_zones.is_empty(), "camera does not trigger mission")
		if _bench_duration <= 10.0:
			_capture_observation()
	if _observation_stage == 1 and _observation_time >= 4.0:
		_observation_check(not _zone_mission.refresh_active_zones_for_level(&"B").has(&"A"), "level refresh preserves roster")
		camera.position = Vector2(9000.0, 9000.0)
		_observation_stage = 2
	if _observation_stage == 2 and _observation_time >= 6.0:
		camera.position = _zone_data.get_zone_center(&"A")
		_bench_set_camera_zoom(0.2)
		_observation_stage = 3
	if _observation_stage == 3 and _observation_time >= 8.0:
		var current_ids: Array[int] = []
		for value: Variant in _zone_mission._spawned_zones.get(&"A", []):
			if typeof(value) == TYPE_OBJECT and is_instance_valid(value):
				current_ids.append(value.get_instance_id())
		_observation_check(current_ids == _observation_ids, "returning camera retains identical targets")
		var below := 0
		var worst := 0.0
		for frame_delta in _observation_deltas:
			worst = maxf(worst, frame_delta)
			if frame_delta > 1.0 / 60.0:
				below += 1
		print("[ZoneObservation] frames=%d below60=%d worst_ms=%.3f fail=%d" % [_observation_deltas.size(), below, worst * 1000.0, _observation_fail])
		if _bench_duration > 10.0:
			_observation_check(below == 0, "wall-clock rendered frames stay above 60 FPS")
		_observation_report.append("first_view_ms=%.3f frames=%d below60=%d worst_ms=%.3f targets=%d fail=%d" % [_observation_first_view_ms, _observation_deltas.size(), below, worst * 1000.0, _observation_ids.size(), _observation_fail])
		var output := FileAccess.open("res://bench/results/zone_observation_%d.txt" % Time.get_ticks_msec(), FileAccess.WRITE)
		if output != null:
			output.store_string("\n".join(_observation_report))
		get_tree().quit(0 if _observation_fail == 0 else 1)

func _capture_observation() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://bench/results/zone_observation_first_view.png")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://bench/results/zone_observation_second_view.png")

func _observation_check(ok: bool, label: String) -> void:
	_observation_report.append("%s %s" % ["PASS" if ok else "FAIL", label])
	print("[ZoneObservation] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_observation_fail += 1
