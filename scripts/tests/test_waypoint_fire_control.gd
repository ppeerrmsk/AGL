extends RefCounted

## 点地移动火控解耦阶段一回归门（spec: waypoint-fire-control）。
## 只验证沿用现有严格门槛；本测试不得为了“更容易发射”修改任何质量阈值。

var _pass: int = 0
var _fail: int = 0
var _root: Node2D = null


func run() -> void:
	print("\n════════ 点地移动火控阶段一验收 ════════")
	_root = Node2D.new()
	_test_player_waypoint_keeps_auto_fire()
	_test_formation_fire_without_navigation_takeover()
	_test_existing_quality_thresholds()
	_test_waste_prevention_gates()
	_root.free()
	_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════\n")


func _test_player_waypoint_keeps_auto_fire() -> void:
	print("── A. 玩家点地：移动与现有 auto-fire 并行 ──")
	var s := Situation.new()
	s.my_pos = Vector2.ZERO
	s.my_heading = 0.0
	s.my_speed_ms = 240.0
	s.max_speed_kmh = 1800.0
	s.cruise_speed_kmh = 900.0
	s.corner_speed_kmh = 650.0
	s.missile_auto_fire = true
	s.missiles = 2
	s.has_radar_lock = true
	var waypoint := Vector2(800.0, -1200.0)
	var plan := BfmIntent.waypoint_move(s, waypoint)
	_check("航点仍是导航输出", plan.pursuit_pos == waypoint, "没有被火控目标替换")
	_check("已有满锁时航点移动仍允许导弹", plan.allow_missile_fire \
			and plan.weapon_mode == TacticalPlan.WeaponMode.MISSILE, "沿用既有玩家路径")


func _test_formation_fire_without_navigation_takeover() -> void:
	print("── B. 编队僚机：无 combat_target 也可严格机会射击 ──")
	var c := _make_case(0.0, 3.0, false)
	var ac: Aircraft = c.ac
	var tgt: CombatUnit = c.target
	var mm: MissileManager = c.manager
	var old_waypoint: Vector2 = ac.target_position
	var old_mode: int = ac.weapon_mode
	AircraftWeapons.update_formation_passive_missile(ac, 0.05)
	_check("合法正前方满锁窗口发射一枚", mm.get_child_count() == 1 \
			and ac.missiles_remaining == 1, "20Hz 火控调用成功")
	_check("发射目标来自雷达锁而非 combat_target", mm.get_child(0).target == tgt \
			and ac.combat_target == null and ac.commanded_target == null, "火控目标短命、不写导航状态")
	_check("航点和编队状态不变", ac.target_position == old_waypoint and ac.formation_mode,
			"仍由 AircraftFormation 驾驶")
	_check("临时武器模式已恢复", ac.weapon_mode == old_mode, "不泄漏 MISSILE 模式")
	_free_case(c)


func _test_existing_quality_thresholds() -> void:
	print("── C. 原发射质量阈值逐边界锁死（未放宽） ──")
	var c := _make_case(0.0, 3.0, false)
	var ac: Aircraft = c.ac
	var tgt: CombatUnit = c.target
	ac.bank_angle = deg_to_rad(35.0)
	_check("SARH bank=35° 仍可", AircraftWeapons._has_stable_launch_window(ac, tgt), "原边界")
	ac.bank_angle = deg_to_rad(35.01)
	_check("SARH bank>35° 拒发", not AircraftWeapons._has_stable_launch_window(ac, tgt), "原边界")
	ac.bank_angle = 0.0
	ac._bank_rate_rad_s = deg_to_rad(30.0)
	_check("SARH roll=30°/s 仍可", AircraftWeapons._has_stable_launch_window(ac, tgt), "原边界")
	ac._bank_rate_rad_s = deg_to_rad(30.01)
	_check("SARH roll>30°/s 拒发", not AircraftWeapons._has_stable_launch_window(ac, tgt), "原边界")
	ac._bank_rate_rad_s = 0.0
	_set_target_bearing(tgt, 20.0)
	_check("SARH off-axis=0.50×40° 仍可", AircraftWeapons._has_stable_launch_window(ac, tgt), "20°")
	_set_target_bearing(tgt, 20.01)
	_check("SARH off-axis>0.50×40° 拒发", not AircraftWeapons._has_stable_launch_window(ac, tgt), ">20°")
	_free_case(c)

	c = _make_case(0.0, 3.0, true)
	ac = c.ac
	tgt = c.target
	ac.bank_angle = deg_to_rad(60.0)
	_check("FAF bank=60° 仍可", AircraftWeapons._has_stable_launch_window(ac, tgt), "原边界")
	ac.bank_angle = deg_to_rad(60.01)
	_check("FAF bank>60° 拒发", not AircraftWeapons._has_stable_launch_window(ac, tgt), "原边界")
	ac.bank_angle = 0.0
	ac._bank_rate_rad_s = deg_to_rad(180.0)
	_check("FAF 仍不受 roll 门限制", AircraftWeapons._has_stable_launch_window(ac, tgt), "原语义")
	ac._bank_rate_rad_s = 0.0
	_set_target_bearing(tgt, 22.0)
	_check("FAF off-axis=0.55×40° 仍可", AircraftWeapons._has_stable_launch_window(ac, tgt), "22°")
	_set_target_bearing(tgt, 22.01)
	_check("FAF off-axis>0.55×40° 拒发", not AircraftWeapons._has_stable_launch_window(ac, tgt), ">22°")
	_free_case(c)


func _test_waste_prevention_gates() -> void:
	print("── D. 浪费弹药防线：不满足原条件就不发 ──")
	_assert_no_fire("未满锁不发", _make_case(0.0, 2.99, false))
	_assert_no_fire("雷达锥外不发", _make_case(40.01, 3.0, false))
	var c := _make_case(0.0, 3.0, false, 200.0)
	_assert_no_fire("低于最小射程不发", c)

	c = _make_case(0.0, 3.0, false)
	c.ac.missile_auto_fire = false
	_assert_no_fire("auto-fire 关闭不发", c)
	c = _make_case(0.0, 3.0, false)
	c.ac.evasion_mode = true
	_assert_no_fire("规避中不发", c)
	c = _make_case(0.0, 3.0, false)
	c.ac.afterburner_window_active = true
	_assert_no_fire("加力窗口不发", c)
	c = _make_case(0.0, 3.0, false)
	c.ac.team = CombatUnit.TEAM_HOSTILE
	_assert_no_fire("敌方单位不走新增编队机会射击", c)

	# 旧协同齐射只查包络+雷达锥；编队机会火控必须绕开它，不能拿未满锁临时目标盲发。
	c = _make_case(0.0, 0.0, false)
	c.ac.combat_target = c.target
	var ai := AIController.new()
	ai.aircraft = c.ac
	ai._salvo_pending = true
	ai._salvo_delay = 0.0
	c.ac._ai_ref = ai
	c.ac.add_child(ai)
	AircraftWeapons.update_formation_passive_missile(c.ac, 0.05)
	_check("编队机会火控不走旧协同齐射简化门", c.manager.get_child_count() == 0 \
			and c.ac.missiles_remaining == 2 and not ai._salvo_pending, "未满锁不发；信号到期后只消费不强射")
	_free_case(c)

	# 自己已有一枚有效在飞弹：保持 has_active_missile_at 的原防连射语义。
	c = _make_case(0.0, 3.0, false)
	var active := Missile.new()
	active.params = c.ac.params.missile
	active.source = c.ac
	active.target = c.target
	active.is_active = true
	active.has_guidance = true
	c.manager.add_child(active)
	var before: int = c.manager.get_child_count()
	AircraftWeapons.update_formation_passive_missile(c.ac, 0.05)
	_check("已有在飞弹不重复补射", c.manager.get_child_count() == before \
			and c.ac.missiles_remaining == 2, "ACTIVE_MSL 门保留")
	_free_case(c)

	# 队友的有效在飞伤害已覆盖目标 HP：保持 TEAM_OVERKILL 节弹门。
	c = _make_case(0.0, 3.0, false)
	var mate := CombatUnit.new()
	mate.team = CombatUnit.TEAM_PLAYER
	_root.add_child(mate)
	var inbound := Missile.new()
	inbound.params = c.ac.params.missile
	inbound.source = mate
	inbound.target = c.target
	inbound.team = CombatUnit.TEAM_PLAYER
	inbound.is_active = true
	inbound.has_guidance = true
	c.target.hp = inbound.params.damage
	c.manager.add_child(inbound)
	before = c.manager.get_child_count()
	AircraftWeapons.update_formation_passive_missile(c.ac, 0.05)
	_check("队友伤害已足不再浪费弹药", c.manager.get_child_count() == before \
			and c.ac.missiles_remaining == 2, "TEAM_OVERKILL 门保留")
	mate.queue_free()
	_free_case(c)


func _make_case(bearing_deg: float, lock_progress: float, fire_and_forget: bool,
		distance_m: float = 3000.0) -> Dictionary:
	var mm := MissileManager.new()
	_root.add_child(mm)
	var ac := Aircraft.new()
	var p := AircraftParams.new()
	var msl: MissileParams = load("res://resources/default_missile.tres").duplicate(true)
	msl.fire_and_forget = fire_and_forget
	p.radar_range = 5000.0
	p.radar_half_angle = 40.0
	p.lock_time = 3.0
	p.missile = msl
	ac.params = p
	ac.team = CombatUnit.TEAM_PLAYER
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0
	ac.speed = 250.0
	ac.altitude = 5000.0
	ac.flat_altitude = true
	ac.formation_mode = true
	ac.use_tactical_planner = true
	ac.missile_auto_fire = true
	ac.weapon_mode = Aircraft.WeaponMode.GUN
	ac.missiles_remaining = 2
	ac.target_position = Vector2(777.0, -333.0)
	ac.missile_manager = mm
	_root.add_child(ac)
	var tgt := CombatUnit.new()
	tgt.team = CombatUnit.TEAM_HOSTILE
	tgt.heading = 0.0
	tgt.altitude = 5000.0
	_root.add_child(tgt)
	_set_target_bearing(tgt, bearing_deg, distance_m)
	ac.radar_targets[tgt] = lock_progress
	return {"ac": ac, "target": tgt, "manager": mm}


func _set_target_bearing(target: CombatUnit, bearing_deg: float, distance_m: float = 3000.0) -> void:
	var r: float = distance_m * CombatUnit.PIXELS_PER_METER
	var a: float = deg_to_rad(bearing_deg)
	target.global_position = Vector2(sin(a), -cos(a)) * r


func _assert_no_fire(label: String, c: Dictionary) -> void:
	var before: int = c.manager.get_child_count()
	AircraftWeapons.update_formation_passive_missile(c.ac, 0.05)
	_check(label, c.manager.get_child_count() == before and c.ac.missiles_remaining == 2,
			"弹数与 MissileManager 子节点均不变")
	_free_case(c)


func _free_case(c: Dictionary) -> void:
	(c.ac as Aircraft).queue_free()
	(c.target as CombatUnit).queue_free()
	(c.manager as MissileManager).queue_free()


func _check(name: String, ok: bool, note: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s — %s" % [name, note])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [name, note])
