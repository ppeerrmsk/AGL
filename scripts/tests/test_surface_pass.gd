extends RefCounted

## 无头行为验收：对面攻击 pass 循环（spec: docs/specs/systems/surface-attack-pass.md §5）
##
## 真实步进（同 test_joust）：物理 60Hz + planner 每 3 帧一次，驱动真实 TacticalPlanner 路径
## （Situation.from_aircraft → TacticalPlanner.plan → _apply_tactical_plan → _resolve_intents）。
## 目标 = 静止 CombatUnit（非 Aircraft → tgt_is_surface=true → 走 ground_strafe）。
##
## A. 绕圈根治（本 spec 主验收）：机炮 vs 贴脸 SAM（500m，钻进转弯圆）——
##    不再原地绕圈：≥3 次完整通场（EGRESS 进入）+ 距离大幅震荡（飞出再回，非定半径绕圈）+
##    真实机炮对准窗（对准 + 进射程）+ 俯冲（掉高扫射后拉起）
## B. STANDOFF 保持距离：导弹 vs SAM —— 全程 MISSILE + 不俯冲进 AA（保持高空 + 最近距离守住 standoff）
## D. 命令轮盘姿态强制（spec command-wheel phase 4）：attack_posture 经 Situation 门控透传——
##    强制 STANDOFF = 不随武器竞选摇摆、守住距离不俯冲；强制 ASSAULT = 导弹机也俯冲进机炮 pass；
##    无 commanded_target 时姿态字段不透传（恒 AUTO，防残留污染自主交战）
##
## 运行：godot --headless --path . -- --bench=surface_pass（或 --bench=all）

const DT := 1.0 / 60.0
const AI_PERIOD := 3

var _pass := 0
var _fail := 0
var _root: Node2D = null


func run() -> void:
	print("\n════════ 对面攻击 pass 验收（SETUP/RUN/EGRESS 循环） ════════")
	_root = Node2D.new()
	_test_orbit_broken_assault()
	_test_standoff_keeps_distance()
	_test_standoff_longrange_offaxis_ship()
	_test_wheel_posture_override()
	_root.free()
	_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 绕圈根治 + 俯冲（ASSAULT 机炮）──
func _test_orbit_broken_assault() -> void:
	print("── A. 机炮 vs 贴脸 SAM：绕圈根治 + 俯冲通场 ──")
	var p := _fighter_params(1200.0, false)   # 机炮机，无导弹 → ASSAULT
	var ac = _make_ac(p, Vector2.ZERO, 0.0)   # 朝北
	var tgt = _make_ground_target(Vector2(250.0, 0.0))  # 正东 500m —— 钻进最小转弯圆
	ac.combat_target = tgt

	var gun_range_px: float = p.gun.max_range * CombatUnit.PIXELS_PER_METER
	var phase_seq: Array = []
	var min_dist := INF
	var max_dist := 0.0
	var min_alt := INF
	var max_alt := 0.0
	var gun_window := false
	var max_setup_streak := 0.0   # 连续处在 SETUP（未 EGRESS/未开火）的最长时间 → 绕圈检测
	var setup_streak := 0.0

	for i in range(70 * 60):
		if i % AI_PERIOD == 0:
			ac._run_tactical_planner_if_enabled()
			if ac._last_plan != null:
				var ph: int = ac._last_plan.strafe_pass_phase
				if phase_seq.is_empty() or phase_seq[-1] != ph:
					phase_seq.append(ph)
		ac._resolve_intents(DT)
		_step(ac)

		var dist: float = ac.global_position.distance_to(tgt.global_position)
		min_dist = minf(min_dist, dist)
		max_dist = maxf(max_dist, dist)
		min_alt = minf(min_alt, ac.altitude)
		max_alt = maxf(max_alt, ac.altitude)
		var nose_off: float = _nose_off_deg(ac, tgt)
		if nose_off <= 10.0 and dist <= gun_range_px:
			gun_window = true
		# 绕圈检测：SETUP 相位持续累计；一旦 RUN/EGRESS 就清零
		var cur_ph: int = ac._last_plan.strafe_pass_phase if ac._last_plan != null else 0
		if cur_ph == TacticalPlan.SurfacePhase.SETUP:
			setup_streak += DT
			max_setup_streak = maxf(max_setup_streak, setup_streak)
		else:
			setup_streak = 0.0
		if i % 900 == 0:
			print("    [%5.1fs] dist=%5.0f alt=%5.0f nose=%5.1f° ph=%s" % [
				float(i) * DT, dist, ac.altitude, nose_off,
				TacticalPlan.surface_phase_name(cur_ph)])

	var egress_passes := _count_phase(phase_seq, TacticalPlan.SurfacePhase.EGRESS)
	print("    phase_seq=%s" % [_seq_names(phase_seq)])
	_check("完整通场 ≥3（EGRESS 进入次数，70s）", egress_passes >= 3, "通场=%d" % egress_passes)
	_check("不绕圈：距离大幅震荡（飞出再回）", (max_dist - min_dist) > 800.0,
		"dist 幅度 %.0fpx（min=%.0f max=%.0f）" % [max_dist - min_dist, min_dist, max_dist])
	# 对照 bug=47s 无限绕圈；健康 pass 之间的折返 U 转弯是合法的（corner speed 180° 需 ~10s）
	_check("不卡 SETUP 死锁（U 转弯预算 15s，对照 bug 47s）", max_setup_streak < 15.0,
		"最长连续 SETUP %.1fs" % max_setup_streak)
	_check("真实机炮对准窗（对准 + 进射程）", gun_window, "出现 nose≤10°∧dist≤gun_range")
	_check("俯冲扫射（掉到低空）", min_alt < 2500.0, "最低高度 %.0fm" % min_alt)
	_check("俯冲后拉起（高度有幅度）", (max_alt - min_alt) > 1500.0,
		"高度幅度 %.0fm" % (max_alt - min_alt))
	_free_pair(ac, tgt)


# ── B. STANDOFF 保持距离（导弹）──
func _test_standoff_keeps_distance() -> void:
	print("── B. 导弹 vs SAM：保持距离 + 不俯冲进 AA ──")
	var p := _fighter_params(1200.0, true)    # 带导弹 → STANDOFF
	var ac = _make_ac(p, Vector2.ZERO, 0.0)
	ac.missiles_remaining = 6
	# 前方 ~7000m、略偏 11°（真实交战从不是完美正对；完美对称会让连续 crank 不产生偏置 = 退化 head-on）
	var tgt = _make_ground_target(Vector2(1400.0, -3430.0))
	ac.combat_target = tgt

	var min_dist_m := INF
	var min_alt := INF
	var missile_ticks := 0
	var total_ticks := 0
	var lock_t := 0.0   # 雷达锁积分模拟（同 test_joust）：喂 crank 几何保持 standoff

	for i in range(45 * 60):
		var dist_m: float = ac.global_position.distance_to(tgt.global_position) / CombatUnit.PIXELS_PER_METER
		# 雷达锁：机头 ±radar_half_angle 且在雷达距离内 → 累积；否则 2× 衰减
		var nose_off: float = _nose_off_deg(ac, tgt)
		if nose_off <= p.radar_half_angle and dist_m <= p.radar_range:
			lock_t = minf(lock_t + DT, p.lock_time + 1.0)
		else:
			lock_t = maxf(lock_t - DT * 2.0, 0.0)
		ac.radar_targets[tgt] = lock_t
		if i % AI_PERIOD == 0:
			ac._run_tactical_planner_if_enabled()
			if ac._last_plan != null:
				total_ticks += 1
				if ac._last_plan.weapon_mode == TacticalPlan.WeaponMode.MISSILE:
					missile_ticks += 1
		ac._resolve_intents(DT)
		_step(ac)
		min_dist_m = minf(min_dist_m, dist_m)
		min_alt = minf(min_alt, ac.altitude)
		if i % 120 == 0:
			print("    [%5.1fs] dist=%5.0fm nose=%5.1f° ph=%s wpn=%s" % [
				float(i) * DT, dist_m, _nose_off_deg(ac, tgt),
				TacticalPlan.surface_phase_name(ac._last_plan.strafe_pass_phase) if ac._last_plan else "-",
				TacticalPlan.weapon_mode_name(ac._last_plan.weapon_mode) if ac._last_plan else "-"])

	var msl_ratio: float = float(missile_ticks) / float(maxi(total_ticks, 1))
	_check("全程用导弹（STANDOFF）", msl_ratio > 0.9, "MISSILE 占比 %.0f%%" % (msl_ratio * 100.0))
	_check("不俯冲进近距 AA（守住 standoff）", min_dist_m >= 900.0, "最近 %.0fm" % min_dist_m)
	_check("不掉低空（保持高位发射）", min_alt >= 3000.0, "最低高度 %.0fm" % min_alt)
	_free_pair(ac, tgt)


# ── C. 远距 off-axis STANDOFF 对舰（病例2 复现，log 20260711_205142）──
func _test_standoff_longrange_offaxis_ship() -> void:
	print("── C. 导弹 vs 6.2km 对舰、初始背对（off≈163°）：远距 SETUP 必须收敛 ──")
	var p := _fighter_params(1200.0, true)
	p.missile.max_range_rear = 16000.0   # 远程反舰弹 → standoff 环 inner=8000m > 起始 6200m（起手就在环内）
	var ac = _make_ac(p, Vector2.ZERO, PI)   # 朝南（heading=PI），目标在北 → 初始 off≈180°
	ac.use_tactical_preference = true        # 玩家机（病例2 是 Ultra 本机）
	ac.missiles_remaining = 6
	var tgt = _make_ground_target(Vector2(0.0, -3100.0))  # 正北 6200m（对舰）
	ac.combat_target = tgt

	var reached_run := -1.0
	var min_dist_m := INF
	var max_dist_m := 0.0
	var min_nose := 999.0
	var egress_ticks := 0
	var total_ticks := 0
	var lock_t := 0.0
	var start_dist := 6200.0

	for i in range(40 * 60):
		var dist_m: float = ac.global_position.distance_to(tgt.global_position) / CombatUnit.PIXELS_PER_METER
		var nose_off: float = _nose_off_deg(ac, tgt)
		if nose_off <= p.radar_half_angle and dist_m <= p.radar_range:
			lock_t = minf(lock_t + DT, p.lock_time + 1.0)
		else:
			lock_t = maxf(lock_t - DT * 2.0, 0.0)
		ac.radar_targets[tgt] = lock_t
		if i % AI_PERIOD == 0:
			ac._run_tactical_planner_if_enabled()
			if ac._last_plan != null:
				total_ticks += 1
				if ac._last_plan.strafe_pass_phase == TacticalPlan.SurfacePhase.RUN and reached_run < 0.0:
					reached_run = float(i) * DT
				if ac._last_plan.strafe_pass_phase == TacticalPlan.SurfacePhase.EGRESS:
					egress_ticks += 1
		ac._resolve_intents(DT)
		_step(ac)
		min_dist_m = minf(min_dist_m, dist_m)
		max_dist_m = maxf(max_dist_m, dist_m)
		min_nose = minf(min_nose, nose_off)
		if i % 120 == 0:
			print("    [%5.1fs] dist=%5.0fm nose=%5.1f° ph=%s" % [
				float(i) * DT, dist_m, nose_off,
				TacticalPlan.surface_phase_name(ac._last_plan.strafe_pass_phase) if ac._last_plan else "-"])

	var egress_ratio: float = float(egress_ticks) / float(maxi(total_ticks, 1))
	_check("远距 off-axis 收敛到 RUN（对照 bug: 40s 卡 SETUP）", reached_run >= 0.0 and reached_run < 20.0,
		"进入 RUN @%.1fs" % reached_run if reached_run >= 0.0 else "40s 未进入 RUN（绕圈）")
	_check("对准过目标（nose 收敛到 ≤30°）", min_nose <= 30.0, "最小 nose %.1f°" % min_nose)
	# 病例2 核心：命令打 6km 环内目标，飞机必须**压入开火**，不能背身外逃到 9km
	_check("不背身外逃（max dist 不超起始 +1.5km）", max_dist_m < start_dist + 1500.0,
		"最远 %.0fm（起始 %.0f）" % [max_dist_m, start_dist])
	_check("压入到发射/脱离距（min dist ≤ 3.5km）", min_dist_m <= 3500.0, "最近 %.0fm" % min_dist_m)
	_check("不长时间背飞 EGRESS（占比 < 40%）", egress_ratio < 0.4, "EGRESS 占比 %.0f%%" % (egress_ratio * 100.0))
	_free_pair(ac, tgt)


# ── D. 命令轮盘姿态强制（spec command-wheel phase 4：attack_posture 透传/门控）──
func _test_wheel_posture_override() -> void:
	print("── D. 轮盘姿态强制：无命令不透传 / STANDOFF 守距 / ASSAULT 俯冲 ──")
	# D0：Situation 门控——姿态字段只在带 commanded_target 时透传（防残留污染自主交战）
	var p0 := _fighter_params(1200.0, true)
	var ac0 = _make_ac(p0, Vector2.ZERO, 0.0)
	var tgt0 = _make_ground_target(Vector2(0.0, -2000.0))
	ac0.attack_posture = Situation.POSTURE_STANDOFF     # 残留姿态、无命令
	var s0: Situation = Situation.from_aircraft(ac0)
	_check("无命令时姿态不透传（恒 AUTO）", s0.attack_posture == Situation.POSTURE_AUTO,
		"posture=%d" % s0.attack_posture)
	ac0.commanded_target = tgt0
	var s1: Situation = Situation.from_aircraft(ac0)
	_check("带命令时姿态透传", s1.attack_posture == Situation.POSTURE_STANDOFF,
		"posture=%d" % s1.attack_posture)
	_free_pair(ac0, tgt0)

	# D1：强制 STANDOFF——导弹机不随武器竞选摇摆、守住距离不俯冲（对照 B 段 AUTO 的近距塌陷）
	_run_posture_case("强制 STANDOFF", Situation.POSTURE_STANDOFF, true)
	# D2：强制 ASSAULT——导弹机也压进机炮 pass 俯冲扫射
	_run_posture_case("强制 ASSAULT", Situation.POSTURE_ASSAULT, false)


func _run_posture_case(label: String, posture: int, expect_standoff: bool) -> void:
	var p := _fighter_params(1200.0, true)
	var ac = _make_ac(p, Vector2.ZERO, 0.0)
	ac.missiles_remaining = 6
	# 与 B 段同几何约定：略偏 11°（完美正对是文档化的退化 crank 边界，非本段测的对象——
	# 本段测姿态强制：竞选摇摆下 STANDOFF 不塌、ASSAULT 导弹机也俯冲）
	var tgt = _make_ground_target(Vector2(1400.0, -3430.0))
	ac.combat_target = tgt
	ac.commanded_target = tgt          # 轮盘命令：铁律目标 + 姿态
	ac.attack_posture = posture
	var min_dist_m := INF
	var min_alt := INF
	var lock_t := 0.0
	for i in range(45 * 60):
		var dist_m: float = ac.global_position.distance_to(tgt.global_position) / CombatUnit.PIXELS_PER_METER
		var nose_off: float = _nose_off_deg(ac, tgt)
		if nose_off <= p.radar_half_angle and dist_m <= p.radar_range:
			lock_t = minf(lock_t + DT, p.lock_time + 1.0)
		else:
			lock_t = maxf(lock_t - DT * 2.0, 0.0)
		ac.radar_targets[tgt] = lock_t
		if i % AI_PERIOD == 0:
			ac._run_tactical_planner_if_enabled()
		ac._resolve_intents(DT)
		_step(ac)
		min_dist_m = minf(min_dist_m, dist_m)
		min_alt = minf(min_alt, ac.altitude)
		if i % 180 == 0:
			print("    [%5.1fs] dist=%5.0fm nose=%5.1f° ph=%s wpn=%s" % [
				float(i) * DT, dist_m, _nose_off_deg(ac, tgt),
				TacticalPlan.surface_phase_name(ac._last_plan.strafe_pass_phase) if ac._last_plan else "-",
				TacticalPlan.weapon_mode_name(ac._last_plan.weapon_mode) if ac._last_plan else "-"])
	if expect_standoff:
		_check("%s：守住距离（min ≥ 900m，与 B 段同标准）" % label, min_dist_m >= 900.0,
			"最近 %.0fm" % min_dist_m)
		_check("%s：不俯冲（min alt ≥ 3000m）" % label, min_alt >= 3000.0, "最低 %.0fm" % min_alt)
	else:
		_check("%s：压进机炮距（min ≤ 900m）" % label, min_dist_m <= 900.0, "最近 %.0fm" % min_dist_m)
		_check("%s：俯冲扫射（min alt < 2500m）" % label, min_alt < 2500.0, "最低 %.0fm" % min_alt)
	_free_pair(ac, tgt)


# ── 工具 ──

func _fighter_params(gun_range_m: float, with_missile: bool) -> AircraftParams:
	var p := AircraftParams.new()
	p.max_speed = 2100.0
	p.cruise_speed = 900.0
	p.radar_half_angle = 30.0
	p.radar_range = 8000.0
	p.lock_time = 3.0
	var gun := GunParams.new()
	gun.max_range = gun_range_m
	p.gun = gun
	if with_missile:
		var m := MissileParams.new()
		m.max_range_rear = 8000.0
		m.min_range = 500.0
		p.missile = m
	return p


func _make_ac(params: AircraftParams, pos: Vector2, hdg: float):
	var ac = load("res://scripts/aircraft.gd").new()
	ac.params = params
	ac.heading = hdg
	ac.bank_angle = 0.0
	ac.altitude = 5000.0
	ac.target_altitude = 5000.0
	ac.speed = params.cruise_speed / 3.6
	ac.target_speed_kmh = params.cruise_speed
	ac.g_load = 1.0
	ac.tactical_aggression = 1.0
	ac.use_tactical_planner = true   # 走 planner 路径
	ac.target_position = Vector2.INF
	ac.position = pos
	_root.add_child(ac)
	return ac


## 静止面目标：裸 CombatUnit（非 Aircraft → tgt_is_surface=true）
func _make_ground_target(pos: Vector2) -> CombatUnit:
	var t := CombatUnit.new()
	t.team = 1
	t.speed = 0.0
	t.altitude = 0.0
	t.position = pos
	_root.add_child(t)
	return t


func _step(ac) -> void:
	AircraftPhysics.update_target_heading(ac)
	AircraftPhysics.update_bank(ac, DT)
	AircraftPhysics.update_heading(ac, DT)
	AircraftPhysics.update_speed(ac, DT)
	AircraftPhysics.update_g_load(ac)
	AircraftPhysics.update_altitude(ac, DT)
	AircraftPhysics.apply_movement(ac, DT)


func _nose_off_deg(ac, tgt) -> float:
	var to_tgt: Vector2 = tgt.global_position - ac.global_position
	var brg := atan2(to_tgt.x, -to_tgt.y)
	var diff := wrapf(brg - ac.heading, -PI, PI)
	return absf(rad_to_deg(diff))


func _count_phase(seq: Array, phase: int) -> int:
	var n := 0
	for ph in seq:
		if ph == phase:
			n += 1
	return n


func _seq_names(seq: Array) -> String:
	var parts: Array = []
	for ph in seq:
		parts.append(TacticalPlan.surface_phase_name(ph))
	return "→".join(parts)


func _free_pair(ac, tgt) -> void:
	_root.remove_child(ac)
	_root.remove_child(tgt)
	ac.free()
	tgt.free()


func _check(name: String, ok: bool, note: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s — %s" % [name, note])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [name, note])
