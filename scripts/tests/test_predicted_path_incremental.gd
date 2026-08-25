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

	ac.free()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
