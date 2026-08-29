extends RefCounted

## 预测轨迹分帧构建必须与原先一次性 360 步结果逐点一致。

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 预测轨迹分帧构建测试 ════════")
	var params: AircraftParams = load("res://resources/playable_f14_base.tres")
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	ac.params = params
	ac.heading = 0.0
	ac.bank_angle = 0.0
	ac.altitude = 5000.0
	ac.target_altitude = 10000.0
	ac.speed = params.cruise_speed / 3.6
	ac.target_speed_kmh = params.cruise_speed
	ac.g_load = 1.0
	ac.tactical_aggression = 1.0
	ac.position = Vector2.ZERO
	ac.target_position = Vector2(3000.0, -3000.0)

	var expected := AircraftPhysics.predict_player_path(ac, Aircraft.PRED_MAX_STEPS)
	var work := AircraftPhysics.begin_player_path_prediction(ac, Aircraft.PRED_MAX_STEPS)
	var early_complete := false
	for chunk_index in range(14):
		early_complete = early_complete or AircraftPhysics.advance_player_path_prediction(
			work, Aircraft.PRED_STEPS_PER_FRAME)
	var final_complete := AircraftPhysics.advance_player_path_prediction(
		work, Aircraft.PRED_STEPS_PER_FRAME)
	var actual := AircraftPhysics.player_path_prediction_result(work)

	_check("前十四帧不提前提交，第十五帧恰好完成",
		not early_complete and final_complete)
	_check("分帧点列与一次性预测逐点一致",
		actual.get("points", PackedVector2Array()) == expected.get(
			"points", PackedVector2Array()))
	_check("分帧能量曲线与一次性预测逐点一致",
		actual.get("healths", PackedFloat32Array()) == expected.get(
			"healths", PackedFloat32Array()))
	var display := AircraftRenderer.prediction_display_result(
		actual.get("points", PackedVector2Array()),
		actual.get("healths", PackedFloat32Array()),
		Aircraft.PRED_DISPLAY_STRIDE)
	var display_points: PackedVector2Array = display["points"]
	var expected_points: PackedVector2Array = expected["points"]
	_check("360 步物理结果抽样为不超过 91 个显示点", display_points.size() <= 91)
	_check("显示抽样始终保留物理预测终点",
		display_points[display_points.size() - 1] == expected_points[expected_points.size() - 1])

	# update_speed 与 step_speed 只允许是不同状态容器的薄壳；共享公式后逐帧必须完全一致。
	ac.target_speed_kmh = params.max_speed * 0.82
	ac.speed = params.cruise_speed / 3.6
	ac.vertical_speed = 80.0
	ac.g_load = 5.5
	var st := FlightState.from_aircraft(ac, true)
	for _i in range(180):
		AircraftPhysics.update_speed(ac, AircraftPhysics.PHYSICS_DT)
		AircraftPhysics.step_speed(st, AircraftPhysics.PHYSICS_DT)
	_check("实飞与预测速度薄壳 180 步同值", is_equal_approx(ac.speed, st.speed))

	ac.hard_brake = true
	ac.speed = params.cruise_speed / 3.6
	ac.vertical_speed = -45.0
	ac.g_load = 3.0
	st = FlightState.from_aircraft(ac, true)
	for _i in range(120):
		AircraftPhysics.update_speed(ac, AircraftPhysics.PHYSICS_DT)
		AircraftPhysics.step_speed(st, AircraftPhysics.PHYSICS_DT)
	_check("急刹实飞与预测速度薄壳同值", is_equal_approx(ac.speed, st.speed))

	ac.hard_brake = false
	ac.position = Vector2(120.0, -80.0)
	ac.target_position = Vector2(2400.0, -3100.0)
	ac.speed = 210.0
	ac._evasion_override = true
	st = FlightState.from_aircraft(ac, true)
	AircraftPhysics.update_target_heading(ac)
	AircraftPhysics.step_target_heading(st)
	_check("目标航向实飞与预测薄壳同值",
		is_equal_approx(ac._cached_target_heading, st.cached_target_heading)
		and is_equal_approx(ac._proximity_damping, st.proximity_damping))

	ac.target_position = ac.position + Vector2(1.0, 0.0)
	ac._evasion_override = true
	st = FlightState.from_aircraft(ac, true)
	AircraftPhysics.update_target_heading(ac)
	AircraftPhysics.step_target_heading(st)
	_check("到达清理实飞与预测薄壳同值",
		ac.target_position == Vector2.INF and st.target_position == Vector2.INF
		and not ac._evasion_override and not st.evasion_override)

	ac.heading = 2.8
	ac.bank_angle = deg_to_rad(67.0)
	ac.speed = 55.0
	ac.g_load = 6.0
	st = FlightState.from_aircraft(ac, true)
	for _i in range(240):
		AircraftPhysics.update_heading(ac, AircraftPhysics.PHYSICS_DT)
		AircraftPhysics.step_heading(st, AircraftPhysics.PHYSICS_DT)
	_check("低速航向积分实飞与预测薄壳同值", is_equal_approx(ac.heading, st.heading))

	ac.sig_typhoon_active = true
	ac.is_stalled = false
	ac.altitude = 3200.0
	ac.target_altitude = 9800.0
	ac.vertical_speed = 35.0
	ac.speed = 290.0
	ac.g_load = 2.0
	st = FlightState.from_aircraft(ac, true)
	for _i in range(180):
		AircraftPhysics.update_altitude(ac, AircraftPhysics.PHYSICS_DT)
		AircraftPhysics.step_altitude(st, AircraftPhysics.PHYSICS_DT)
	_check("超巡爬升高度积分实飞与预测薄壳同值",
		is_equal_approx(ac.altitude, st.altitude)
		and is_equal_approx(ac.vertical_speed, st.vertical_speed))

	ac.sig_typhoon_active = false
	ac.is_stalled = true
	ac.altitude = 180.0
	ac.vertical_speed = -95.0
	st = FlightState.from_aircraft(ac, true)
	for _i in range(90):
		AircraftPhysics.update_altitude(ac, AircraftPhysics.PHYSICS_DT)
		AircraftPhysics.step_altitude(st, AircraftPhysics.PHYSICS_DT)
	_check("失速高度积分实飞与预测薄壳同值",
		is_equal_approx(ac.altitude, st.altitude)
		and is_equal_approx(ac.vertical_speed, st.vertical_speed))

	# bank 的方向锁、坡度帽、滚转权限与 EMA 也必须来自同一套纯函数。
	ac.is_stalled = false
	ac._stall_recovery_timer = 0.0
	ac.heading = 0.0
	ac._cached_target_heading = 2.9
	ac.target_position = Vector2(3000.0, 800.0)
	ac.bank_angle = deg_to_rad(-12.0)
	ac.speed = 245.0
	ac.g_load = 3.2
	ac.altitude = 7200.0
	ac._committed_turn_sign = 0.0
	ac._turn_rate_filt = 0.04
	ac._bank_rate_rad_s = -0.08
	ac._prev_bank_for_rate = ac.bank_angle - 0.01
	ac.use_tactical_preference = false
	st = FlightState.from_aircraft(ac, true)
	for _i in range(240):
		AircraftPhysics.update_bank(ac, AircraftPhysics.PHYSICS_DT)
		AircraftPhysics.step_bank(st, AircraftPhysics.PHYSICS_DT)
	_check("滚转实飞与预测薄壳 240 步同值",
		is_equal_approx(ac.bank_angle, st.bank_angle)
		and is_equal_approx(ac._committed_turn_sign, st.committed_turn_sign)
		and is_equal_approx(ac._turn_rate_filt, st.turn_rate_filt)
		and is_equal_approx(ac._bank_rate_rad_s, st.bank_rate_rad_s)
		and is_equal_approx(ac._prev_bank_for_rate, st.prev_bank_for_rate))

	ac.free()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
