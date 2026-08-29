extends RefCounted

## 敌我共享火箭涟发与延迟散开纯函数验收。
## 运行：bench/run.cmd rocket_trajectory 1 120 Shadow

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 火箭涟发 / 延迟散开验收 ════════")
	_test_default_distances()
	_test_spread_curve()
	_test_incremental_rotation()
	_test_homing_straight_gate()
	_test_burst_plan()
	_test_shared_launch_path()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════\n")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		printerr("  ✗ FAIL: %s" % label)


func _near(actual: float, expected: float, eps: float, label: String) -> void:
	_check(absf(actual - expected) <= eps,
		"%s actual=%.6f expected=%.6f" % [label, actual, expected])


func _heading_of(velocity: Vector2) -> float:
	return atan2(velocity.x, -velocity.y)


func _test_default_distances() -> void:
	print("── A. RocketParams 统一默认距离 ──")
	var rk := RocketParams.new()
	_near(rk.straight_flight_distance, 180.0, 0.001, "直飞距离 180m")
	_near(rk.spread_transition_distance, 320.0, 0.001, "展开距离 320m")


func _test_spread_curve() -> void:
	print("── B. 180m 直飞 + 320m smoothstep ──")
	_near(BulletManager.rocket_spread_progress(0.0, 180.0, 320.0), 0.0, 0.0001,
		"出膛无散布")
	_near(BulletManager.rocket_spread_progress(180.0, 180.0, 320.0), 0.0, 0.0001,
		"180m 边界仍直飞")
	var partial := BulletManager.rocket_spread_progress(250.0, 180.0, 320.0)
	_check(partial > 0.0 and partial < 0.5, "250m 只完成早段部分展开")
	_near(BulletManager.rocket_spread_progress(340.0, 180.0, 320.0), 0.5, 0.0001,
		"过渡中点完成一半角度")
	_near(BulletManager.rocket_spread_progress(500.0, 180.0, 320.0), 1.0, 0.0001,
		"500m 达到完整散布")
	_near(BulletManager.rocket_spread_progress(900.0, 180.0, 320.0), 1.0, 0.0001,
		"远段不继续扩大")
	_near(BulletManager.rocket_spread_progress(181.0, 180.0, 0.0), 1.0, 0.0001,
		"零过渡距离安全退化为阈值后立即完成")


func _test_incremental_rotation() -> void:
	print("── C. 增量偏转保留中途追踪修正 ──")
	var spread := deg_to_rad(10.0)
	var b: Dictionary = {
		"vel": Vector2(0.0, -160.0),
		"rocket_travel_m": 0.0,
		"rocket_spread_offset_rad": spread,
		"rocket_spread_applied_rad": 0.0,
		"rocket_straight_distance_m": 180.0,
		"rocket_spread_transition_distance_m": 320.0,
	}
	BulletManager.apply_rocket_spread_step(b, 180.0)
	_near(_heading_of(b["vel"]), 0.0, 0.0001, "180m 内航向严格不偏")
	BulletManager.apply_rocket_spread_step(b, 160.0)
	_near(_heading_of(b["vel"]), spread * 0.5, 0.0001, "340m 航向偏转一半")
	var tracked_velocity: Vector2 = b["vel"]
	var speed_before: float = tracked_velocity.length()
	b["vel"] = tracked_velocity.rotated(deg_to_rad(20.0))
	BulletManager.apply_rocket_spread_step(b, 160.0)
	_near(_heading_of(b["vel"]), deg_to_rad(30.0), 0.0001,
		"追踪额外转 20° 后仍只补剩余 5°散布")
	var final_velocity: Vector2 = b["vel"]
	_near(final_velocity.length(), speed_before, 0.0001, "展开不改变弹速")
	_near(float(b["rocket_spread_applied_rad"]), spread, 0.0001, "累计散布封顶原角度")


func _test_homing_straight_gate() -> void:
	print("── D. 追踪强化尊重近机直飞段 ──")
	var b := {
		"rocket_travel_m": 180.0,
		"rocket_straight_distance_m": 180.0,
	}
	_check(not BulletManager.rocket_straight_phase_complete(b), "180m 边界不追踪")
	b["rocket_travel_m"] = 180.01
	_check(BulletManager.rocket_straight_phase_complete(b), "越过 180m 后允许追踪")


func _test_burst_plan() -> void:
	print("── E. 左右逐发涟发计划 ──")
	var spread := deg_to_rad(14.0)
	var plan := AircraftWeapons.rocket_burst_plan(8, spread, 0.04)
	_check(plan.size() == 8, "8 发计划数量")
	for i in range(plan.size()):
		_near(float(plan[i]["delay"]), float(i) * 0.04, 0.0001,
			"第 %d 发独立 delay" % (i + 1))
		_check(int(plan[i]["pylon"]) == (-1 if i % 2 == 0 else 1),
			"第 %d 发左右交替" % (i + 1))
	_near(float(plan[0]["spread_offset"]), -spread, 0.0001, "首发占扇面左缘")
	_near(float(plan[7]["spread_offset"]), spread, 0.0001, "末发占扇面右缘")
	var single := AircraftWeapons.rocket_burst_plan(1, spread, 0.08)
	_near(float(single[0]["spread_offset"]), 0.0, 0.0001, "单发沿中线")


func _test_shared_launch_path() -> void:
	print("── F. PLAYER / HOSTILE 共用实际出膛入口 + 发射机速度继承 ──")
	var player := _launch_one(CombatUnit.TEAM_PLAYER, 300.0)
	var hostile := _launch_one(CombatUnit.TEAM_HOSTILE, 180.0)
	var stationary := _launch_one(CombatUnit.TEAM_PLAYER, 0.0)
	var player_bullet: Dictionary = player["bullet"]
	var hostile_bullet: Dictionary = hostile["bullet"]
	_check(player_bullet["source_team"] == CombatUnit.TEAM_PLAYER, "PLAYER IFF 快照保留")
	_check(hostile_bullet["source_team"] == CombatUnit.TEAM_HOSTILE, "HOSTILE IFF 快照保留")
	_near(float(player_bullet["rocket_straight_distance_m"]), 180.0, 0.001,
		"PLAYER 走 180m 直飞")
	_near(float(hostile_bullet["rocket_straight_distance_m"]), 180.0, 0.001,
		"HOSTILE 走 180m 直飞")
	_near(float(player_bullet["rocket_spread_transition_distance_m"]), 320.0, 0.001,
		"PLAYER 走 320m 展开")
	_near(float(hostile_bullet["rocket_spread_transition_distance_m"]), 320.0, 0.001,
		"HOSTILE 走 320m 展开")
	_near(float(player_bullet["rocket_spread_offset_rad"]), deg_to_rad(8.0), 0.0001,
		"PLAYER 最终偏角传入 BulletManager")
	_near(float(hostile_bullet["rocket_spread_offset_rad"]), deg_to_rad(8.0), 0.0001,
		"HOSTILE 最终偏角传入 BulletManager")
	var player_velocity: Vector2 = player_bullet["vel"]
	var hostile_velocity: Vector2 = hostile_bullet["vel"]
	_near(_heading_of(player_velocity), 0.0, 0.0001, "PLAYER 出膛先沿机头直飞")
	_near(_heading_of(hostile_velocity), 0.0, 0.0001, "HOSTILE 出膛先沿机头直飞")
	_near(player_velocity.length() / CombatUnit.PIXELS_PER_METER, 620.0, 0.001,
		"PLAYER 320m/s 火箭继承 300m/s 发射机速度")
	_near(hostile_velocity.length() / CombatUnit.PIXELS_PER_METER, 500.0, 0.001,
		"HOSTILE 共用全量速度继承")
	var stationary_bullet: Dictionary = stationary["bullet"]
	var stationary_velocity: Vector2 = stationary_bullet["vel"]
	_near(stationary_velocity.length() / CombatUnit.PIXELS_PER_METER, 320.0, 0.001,
		"静止发射机保留资源自身初速")
	_near(player_velocity.length() / CombatUnit.PIXELS_PER_METER
		- hostile_velocity.length() / CombatUnit.PIXELS_PER_METER, 120.0, 0.001,
		"发射机快 120m/s 时火箭地速同步快 120m/s")
	(player["manager"] as BulletManager).free()
	(player["aircraft"] as Aircraft).free()
	(hostile["manager"] as BulletManager).free()
	(hostile["aircraft"] as Aircraft).free()
	(stationary["manager"] as BulletManager).free()
	(stationary["aircraft"] as Aircraft).free()


func _launch_one(team: int, aircraft_speed_ms: float) -> Dictionary:
	var ac := Aircraft.new()
	ac.team = team
	ac.altitude = 5000.0
	ac.heading = 0.0
	ac.speed = aircraft_speed_ms
	ac.params = AircraftParams.new()
	ac.params.rocket = RocketParams.new()
	ac.rockets_remaining = 10
	var manager := BulletManager.new()
	ac.bullet_manager = manager
	AircraftWeapons._launch_rocket(ac, deg_to_rad(8.0), -1)
	return {
		"aircraft": ac,
		"manager": manager,
		"bullet": manager._bullets[0].duplicate(true),
	}
