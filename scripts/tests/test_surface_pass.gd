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
##    + **必须真出弹**（log 20260726_165536 回归）：复刻实机发射门序列（包络→锥→锁→发射窗质量），
##    旧 crank 版把机头稳态钉在离轴 radar_half×0.5 = 发射门外沿 → UNSTABLE_WIN 永拒 → 40s 0 发
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
	_test_aa_fire_awareness()
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
	var fired := 0
	var first_fire_t := -1.0
	var fire_cd := 0.0

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
		fire_cd = maxf(fire_cd - DT, 0.0)
		if fire_cd <= 0.0 and _launch_gate_open(ac, tgt, lock_t):
			fired += 1
			fire_cd = p.missile.cooldown
			if first_fire_t < 0.0:
				first_fire_t = float(i) * DT
		min_dist_m = minf(min_dist_m, dist_m)
		min_alt = minf(min_alt, ac.altitude)
		if i % 120 == 0:
			print("    [%5.1fs] dist=%5.0fm nose=%5.1f° ph=%s wpn=%s fired=%d" % [
				float(i) * DT, dist_m, _nose_off_deg(ac, tgt),
				TacticalPlan.surface_phase_name(ac._last_plan.strafe_pass_phase) if ac._last_plan else "-",
				TacticalPlan.weapon_mode_name(ac._last_plan.weapon_mode) if ac._last_plan else "-",
				fired])

	var msl_ratio: float = float(missile_ticks) / float(maxi(total_ticks, 1))
	_check("全程用导弹（STANDOFF）", msl_ratio > 0.9, "MISSILE 占比 %.0f%%" % (msl_ratio * 100.0))
	_check("不俯冲进近距 AA（守住 standoff）", min_dist_m >= 900.0, "最近 %.0fm" % min_dist_m)
	_check("不掉低空（保持高位发射）", min_alt >= 3000.0, "最低高度 %.0fm" % min_alt)
	# log 20260726_165536 回归核心：旧 crank 版此计数恒 0（离轴钉在发射门外沿 UNSTABLE_WIN 永拒）
	_check("必须真出弹（发射门通过 ≥2 次）", fired >= 2, "fired=%d" % fired)
	_check("首发不拖沓（< 30s）", first_fire_t >= 0.0 and first_fire_t < 30.0,
		("首发 @%.1fs" % first_fire_t) if first_fire_t >= 0.0 else "45s 未开火")
	_free_pair(ac, tgt)


# ── C. 远距 off-axis STANDOFF 对舰（病例2 复现，log 20260711_205142）──
func _test_standoff_longrange_offaxis_ship() -> void:
	print("── C. 导弹 vs 6.2km 对舰、初始背对（off≈163°）：远距 SETUP 必须收敛 ──")
	var p := _fighter_params(1200.0, true)
	p.missile.max_range_rear = 16000.0   # 远程反舰弹 → standoff 环 inner=8000m > 起始 6200m（起手就在环内）
	var ac = _make_ac(p, Vector2.ZERO, PI)   # 朝南（heading=PI），目标在北 → 初始 off≈180°
	ac.use_tactical_preference = true        # 玩家机（病例2 是 Ultra 本机）
	ac.gun_aim_error_enabled = true          # 玩家侧瞄准误差（2026-07-22 从上一行拆出）
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
	var fired := 0
	var fire_cd := 0.0

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
		fire_cd = maxf(fire_cd - DT, 0.0)
		if fire_cd <= 0.0 and _launch_gate_open(ac, tgt, lock_t):
			fired += 1
			fire_cd = p.missile.cooldown
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
	# 玩家长机（use_tactical_preference）同病回归：对舰 STANDOFF 也必须真出弹
	_check("玩家长机必须真出弹（≥1 次）", fired >= 1, "fired=%d" % fired)
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
	# 门收紧（ace-squadron-tier §3.5）：正打命令目标本身才透传
	ac0.commanded_target = tgt0
	ac0.combat_target = tgt0
	var s1: Situation = Situation.from_aircraft(ac0)
	_check("带命令且正打它时姿态透传", s1.attack_posture == Situation.POSTURE_STANDOFF,
		"posture=%d" % s1.attack_posture)
	# 让位期（命令目标隐形）临时交战别的目标：点名姿态不泄漏到临时目标
	ac0.combat_target = null
	var s2: Situation = Situation.from_aircraft(ac0)
	_check("有命令但未打它时不透传（AUTO）", s2.attack_posture == Situation.POSTURE_AUTO,
		"posture=%d" % s2.attack_posture)
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

# ── E. AA 火力警觉（spec aa-fire-awareness）——planner 纯函数断言 ──
# 直接构造 Situation 调 BfmIntent.ground_strafe，逐条验证四个新行为：
# inner 环随目标对空火力半径抬升 / F-Pole 弹在飞不压入 / 中弹强转 EGRESS / EGRESS 转出后 AB
func _test_aa_fire_awareness() -> void:
	print("── E. AA 火力警觉（inner 抬升 / F-Pole / 中弹脱离 / EGRESS AB）──")
	# 共用底座：STANDOFF 姿态、机头正对北方目标（对准 → RUN 维持）
	var base := {
		"has_target": true, "tgt_is_surface": true,
		"my_pos": Vector2.ZERO, "my_heading": 0.0,
		"attack_posture": Situation.POSTURE_STANDOFF,
		"missiles": 4,
		"missile_max_range_m": 16000.0, "missile_min_range_m": 500.0,
		"max_speed_kmh": 2100.0, "cruise_speed_kmh": 900.0,
		"corner_speed_kmh": 700.0, "stall_speed_kmh": 200.0,
		"strafe_pass_phase": TacticalPlan.SurfacePhase.RUN,
	}

	# E1: CIWS 舰（对空 2000m）→ inner 抬到 2500：dist=2400m 的 RUN 应触发 EGRESS
	var d1 := base.duplicate()
	d1["tgt_pos"] = Vector2(0, -2400.0 * CombatUnit.PIXELS_PER_METER)
	d1["target_aa_range_m"] = 2000.0
	var p1 := BfmIntent.ground_strafe(Situation.new_for_test(d1))
	_check("E1 CIWS 舰 inner=2500：dist 2400m RUN→EGRESS",
		p1.strafe_pass_phase == TacticalPlan.SurfacePhase.EGRESS, p1.rationale)

	# E1b 对照：无对空火力（aa=0）→ inner 仍 2200：dist 2400m 维持 RUN 压入
	var d1b := base.duplicate()
	d1b["tgt_pos"] = Vector2(0, -2400.0 * CombatUnit.PIXELS_PER_METER)
	var p1b := BfmIntent.ground_strafe(Situation.new_for_test(d1b))
	_check("E1b 无 AA 目标对照：dist 2400m 维持 RUN（inner 2200 不变）",
		p1b.strafe_pass_phase == TacticalPlan.SurfacePhase.RUN, p1b.rationale)

	# E2: F-Pole——弹在飞（fpole_hold）→ RUN 不压入，环外等待（pursuit 距目标 ≥ inner）
	var d2 := base.duplicate()
	d2["tgt_pos"] = Vector2(0, -5000.0 * CombatUnit.PIXELS_PER_METER)
	d2["target_aa_range_m"] = 2000.0
	d2["fpole_hold"] = true
	var s2 := Situation.new_for_test(d2)
	var p2 := BfmIntent.ground_strafe(s2)
	var hold_dist_m: float = p2.pursuit_pos.distance_to(s2.tgt_pos) / CombatUnit.PIXELS_PER_METER
	_check("E2 F-Pole：弹在飞不压入（rationale 标记）", "F-Pole" in p2.rationale, p2.rationale)
	_check("E2b F-Pole：等待点在 inner 环外", hold_dist_m >= 2500.0,
		"pursuit 距目标 %.0fm（inner=2500）" % hold_dist_m)

	# E3: 中弹强转脱离——aa_fire_active 时 RUN（dist 5000m，远在 inner 外）强转 EGRESS
	var d3 := base.duplicate()
	d3["tgt_pos"] = Vector2(0, -5000.0 * CombatUnit.PIXELS_PER_METER)
	d3["aa_fire_active"] = true
	var p3 := BfmIntent.ground_strafe(Situation.new_for_test(d3))
	_check("E3 中弹：RUN 强转 EGRESS（dist 5000m 仍脱离）",
		p3.strafe_pass_phase == TacticalPlan.SurfacePhase.EGRESS, p3.rationale)

	# E3b 玩家自治对照：is_tactical_preference_user 不强转
	var d3b := d3.duplicate()
	d3b["is_tactical_preference_user"] = true
	var p3b := BfmIntent.ground_strafe(Situation.new_for_test(d3b))
	_check("E3b 玩家自治：中弹不强转（维持 RUN）",
		p3b.strafe_pass_phase == TacticalPlan.SurfacePhase.RUN, p3b.rationale)

	# E4: EGRESS 加速——ASSAULT 姿态（egress_dir=径向背离），机头已背对目标 → AB 全速
	var d4 := {
		"has_target": true, "tgt_is_surface": true,
		"my_pos": Vector2.ZERO, "my_heading": PI,   # 机头朝南
		"tgt_pos": Vector2(0, -800.0 * CombatUnit.PIXELS_PER_METER),  # 目标在北 → 背离方向=南
		"attack_posture": Situation.POSTURE_ASSAULT,
		"gun_range_m": 1200.0,
		"max_speed_kmh": 2100.0, "cruise_speed_kmh": 900.0,
		"corner_speed_kmh": 700.0, "stall_speed_kmh": 200.0,
		"strafe_pass_phase": TacticalPlan.SurfacePhase.EGRESS,
	}
	var p4 := BfmIntent.ground_strafe(Situation.new_for_test(d4))
	_check("E4 EGRESS 机头已转出 → AB 全速",
		p4.afterburner and p4.target_speed_kmh >= 2100.0 - 1.0,
		"ab=%s spd=%dkmh" % [p4.afterburner, int(p4.target_speed_kmh)])

	# E4b 对照：机头仍朝目标（转向段）→ corner 硬 break、无 AB
	var d4b := d4.duplicate()
	d4b["my_heading"] = 0.0   # 机头朝北 = 朝目标
	var p4b := BfmIntent.ground_strafe(Situation.new_for_test(d4b))
	_check("E4b EGRESS 转向段 → corner 无 AB",
		(not p4b.afterburner) and absf(p4b.target_speed_kmh - 700.0) < 1.0,
		"ab=%s spd=%dkmh" % [p4b.afterburner, int(p4b.target_speed_kmh)])


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
		# 对齐生存模式主角机现实（survivor_playable_setup 全员 f&f + F-15C cooldown=2.0）——
		# log 20260726_165536 的病例就是 f&f MRM 被 UNSTABLE_WIN 卡死
		m.fire_and_forget = true
		m.cooldown = 2.0
		p.missile = m
	return p


## 复刻实机单发路径的发射门尾段（aircraft_weapons.try_fire 同序：包络 → 雷达锥 → 锁满 →
## 发射窗口质量）。planner 机不加 LOCK_STABLE_BUFFER（与实机 lock_threshold 逻辑一致）。
## 冷却由调用方模拟。旧 crank bug 下此门在 STANDOFF RUN 全程打不开（离轴 21~31° > radar_half×0.55）。
func _launch_gate_open(ac, tgt, lock_t: float) -> bool:
	if not ac._is_in_missile_envelope(tgt, ac.params.missile):
		return false
	if not ac.is_in_radar_cone(tgt.global_position):
		return false
	if lock_t < ac.params.lock_time:
		return false
	if not AircraftWeapons._has_stable_launch_window(ac, tgt):
		return false
	return true


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
