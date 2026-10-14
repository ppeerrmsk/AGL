extends RefCounted

const Rules = preload("res://scripts/survivor/orion_fire_control.gd")
const Config = preload("res://scripts/survivor/orion_airframe_config.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_check("9 次不解锁 / 10 次解锁", not Rules.eligible(9) and Rules.eligible(10))
	_check("第 15 队不提前乱入", not Rules.should_arrive(true, false, 15, 100.0, 0))
	_check("第 16 队等待 8s", not Rules.should_arrive(true, false, 16, 7.99, 1)
		and Rules.should_arrive(true, false, 16, 8.0, 1))
	_check("清场提前入场且不可重复", Rules.should_arrive(true, false, 16, 0.0, 0)
		and not Rules.should_arrive(true, true, 18, 100.0, 0))
	_check("无人可锁不空造导弹", Rules.allocate_salvo([]).is_empty())
	var one: Array[Dictionary] = [{"id": 101, "priority": 2, "distance": 1.0}]
	var single := Rules.allocate_salvo(one)
	_check("仅一架敌机分配十发", single.size() == 10 and single.count(101) == 10)
	_check("重复锁定完整 6.05s", is_equal_approx(Rules.lock_duration(single), 6.05))
	var schedule := Rules.launch_schedule(single)
	_check("同目标末发最早在 6.75s", is_equal_approx(schedule.back()["time"], 6.75))
	var crowded: Array[Dictionary] = []
	for i in range(20):
		crowded.append({"id": i + 1, "priority": 0, "distance": float(20 - i)})
	crowded.append({"id": 100, "priority": 2, "distance": 2.0})
	crowded.append({"id": 101, "priority": 2, "distance": 1.0})
	var plan := Rules.allocate_salvo(crowded)
	_check("十六发上限与两个玩家压力槽", plan.size() == 16 and plan.has(100) and plan.has(101))
	_check("ACE 优先且组内按距离", plan[0] == 20 and plan[13] == 7)
	var mixed: Array[int] = [1, 2, 1, 3, 2, 1, 3, 1, 2, 1]
	var last_by_id: Dictionary = {}
	var last_time := -INF
	for shot in Rules.launch_schedule(mixed):
		var time := float(shot["time"])
		var uid := int(shot["id"])
		_check("全局发射节拍", time - last_time >= Rules.LAUNCH_INTERVAL - 0.00001)
		_check("同目标发射节拍", time - float(last_by_id.get(uid, -INF)) >= Rules.SAME_TARGET_INTERVAL - 0.00001)
		last_time = time
		last_by_id[uid] = time
	var a := Vector2.ZERO
	var b := Vector2(0, -1400)
	_check("快速弹穿剑不会漏检", Rules.swept_beam_hit(Vector2(-50, -700), Vector2(50, -700), a, b, a, b, 6.0))
	_check("剑外弹不误拦", not Rules.swept_beam_hit(Vector2(50, -700), Vector2(80, -700), a, b, a, b, 6.0))
	_check("旋转剑扫过静止目标", Rules.swept_beam_hit(Vector2(40, -700), Vector2(40, -700), a, b, a, Vector2(140, -1400), 6.0))
	var body := Aircraft.new()
	body.params = Config.make_airframe()
	_check("物理和战术读取 18G", is_equal_approx(AircraftPhysics.effective_max_g(body), 18.0))
	_check("24G 结构极限与快速滚转", is_equal_approx(AircraftPhysics.effective_max_g_instant(body), 24.0)
		and body.params.roll_rate == 6.0)
	_check("不附赠技能武器", body.params.equipment.is_empty() and body.params.gun == null
		and body.params.missile == null and body.params.max_hp == 600.0)
	var normal := Aircraft.new()
	normal.params = preload("res://resources/default_fighter.tres").duplicate(true)
	var boss_turn := _measure_turn(body)
	var normal_turn := _measure_turn(normal)
	_check("相同 900km/h 正式积分：ORION 转弯更紧", boss_turn.radius < normal_turn.radius * 0.7)
	_check("相同航向阶跃：ORION 更快滚入 60 度坡度", boss_turn.roll_time < normal_turn.roll_time)
	_check("常态高 G 且高于载荷失速边界", boss_turn.g > 17.0 and AircraftPhysics.stall_speed(body) < 900.0)
	print("[ORION physics] 900km/h boss=%s normal=%s" % [boss_turn, normal_turn])
	normal.free()
	body.free()
	var fang := Config.make_airframe(true)
	_check("FANG 独立 250HP 且无诱饵", fang.max_hp == 250.0 and fang.flare == null)
	var admm := Config.make_admm()
	_check("主动雷达保持诱饵分支", admm.active_radar_guidance and not admm.fire_and_forget)
	_check("垂发与近炸阶段分离", admm.airborne_vertical_launch and admm.is_vls_salvo)
	print("──────── ORION 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _measure_turn(ac: Aircraft) -> Dictionary:
	ac.speed = 900.0 / 3.6
	ac.altitude = 5500.0
	ac.target_position = Vector2(10000, 0)
	var roll_time := 10.0
	var measured_rate := 0.0
	for tick in range(120):
		ac._cached_target_heading = ac.heading + PI / 2.0
		AircraftPhysics.update_bank(ac, 1.0 / 60.0)
		AircraftPhysics.update_g_load(ac)
		var before := ac.heading
		AircraftPhysics.update_heading(ac, 1.0 / 60.0)
		measured_rate = absf(wrapf(ac.heading - before, -PI, PI)) * 60.0
		if roll_time == 10.0 and absf(ac.bank_angle) >= PI / 3.0:
			roll_time = float(tick + 1) / 60.0
	return {"g": ac.g_load, "radius": ac.speed / maxf(measured_rate, 0.001), "roll_time": roll_time}


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
