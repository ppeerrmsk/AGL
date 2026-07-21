extends RefCounted

## 无头行为验收：慢速空中目标（直升机）交战 pass（spec: docs/specs/systems/slow-air-target-pass.md §5）
##
## 复现基准 = log 20260720_115041（F-14 小队打 CH-47 CHK-01/02/03）：
##   136s~194s 近 60 秒内三架 F-14 反复 WIDE_TURN→LEAD_TURN→CLOSE_TAIL→overshoot→EXTEND→WIDE_TURN，
##   只在 172.5s 偶然凑出一次机炮窗（0.2s 9 发打死 CHK-03）。其余时间被三道门轮流卡住：
##   LOCK 133 次 / WEAPON_MODE 53 次 / OFF_CONE 21 次 / UNSTABLE_WIN 3 次（满锁被 off-axis 门拒发）。
##
## 本测试**同时**步进真实物理 + planner，并如实复刻游戏里的三道发射门
## （锁定积分含低空 ×0.7 惩罚与出锥 0.3s 清零 / 武器模式 min_range+滞回 / 发射窗口 off-axis 门），
## 因此"打得中"必须是三道门同时开的结果，而不是几何单测的纸面对准。
##
## A. 导弹机：必须在 30s 内打出**真实可发射窗口**（三门齐开），且不绕圈
## B. 机炮机：必须在 30s 内打出真实机炮窗（对准 + 进射程），且不绕圈
## C. 贴脸起手（目标钻进最小转弯圆内）：不得像旧补丁那样在圈内反复 extend 空转
## D. 回归守卫：快速目标不得被误判为慢速目标（不能污染正常空战缠斗）
##
## 运行：godot --headless --path . -- --bench=slow_air_pass（或 --bench=all）

const DT := 1.0 / 60.0
const AI_PERIOD := 3

# ── 复刻游戏内发射门常量（与 aircraft_weapons.gd / survivor_mode.gd 同源）──
const LOW_ALT_LOCK_RATE := 0.7          ## survivor_mode._lock_rate_for_target：LOW 档目标 ×0.7
const OUT_OF_CONE_DUMP_S := 0.3         ## survivor_mode：出锥 0.3s 清零
const LAUNCH_OFFAX_RATIO_FAF := 0.55    ## aircraft_weapons.LAUNCH_QUALITY_OFFAX_RATIO_FAF
const LAUNCH_MAX_BANK_FAF := 60.0       ## aircraft_weapons.LAUNCH_QUALITY_MAX_BANK_DEG_FAF
const WEAPON_MODE_HYSTERESIS_M := 150.0 ## aircraft_combat_tracking.WEAPON_MODE_HYSTERESIS_M
const GUN_FIRE_CONE_DEG := 5.0          ## BfmIntent.FIRE_CONE_HALF_DEG
const GUN_TARGET_AHEAD_DEG := 45.6      ## BfmIntent.GUN_TARGET_AHEAD_MIN=0.7 → acos ≈ 45.6°
const GUN_BULLET_SPEED_MS := 1050.0     ## BfmIntent._gun_lead_point 内的默认弹速

var _pass := 0
var _fail := 0
var _root: Node2D = null


func run() -> void:
	print("\n════════ 慢速空目标（直升机）交战 pass 验收 ════════")
	_root = Node2D.new()
	_test_missile_kill_window()
	_test_gun_kill_window()
	_test_point_blank_start()
	_test_fast_target_not_misclassified()
	_root.free()
	_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 导弹机：三门齐开的真实发射窗 ──
func _test_missile_kill_window() -> void:
	print("── A. 导弹 F-14 vs CH-47：30s 内必须打出真实可发射窗口 ──")
	var p := _f14_params(true)
	# 起手几何照抄 log：目标在侧后方，机头背着目标（这正是旧代码进入极限环的入口）
	var ac = _make_ac(p, Vector2.ZERO, 0.0)              # 朝北
	ac.missiles_remaining = 4
	var tgt = _make_helo(Vector2(-1400.0, 1600.0))       # 左后方 ~2.1km（heading_diff > 90°）
	ac.combat_target = tgt

	var r := _sim(ac, tgt, p, 45.0, true)
	print("    首次可发射 t=%s / 最长连续 SETUP=%.1fs / 最大锁定=%.2fs" % [
		("%.1fs" % r.first_fire_t) if r.first_fire_t >= 0.0 else "从未", r.max_setup_streak, r.max_lock])
	_check("30s 内打出真实导弹发射窗（三门齐开）", r.first_fire_t >= 0.0 and r.first_fire_t <= 30.0,
		("t=%.1fs dist=%.0fm off=%.1f°" % [r.first_fire_t, r.fire_dist_m, r.fire_off_deg]) \
			if r.first_fire_t >= 0.0 else "45s 内从未满足（对照 bug：60s 未开火）")
	_check("锁定能攒满（对照 bug：反复 0.00/1.82 清零）", r.max_lock >= p.lock_time,
		"最大累积 %.2fs / 阈值 %.2fs" % [r.max_lock, p.lock_time])
	_check("不绕圈（连续 SETUP < 15s）", r.max_setup_streak < 15.0,
		"最长 %.1fs" % r.max_setup_streak)
	_check("首发在导弹包络内（≥ min_range）", r.first_fire_t < 0.0 or r.fire_dist_m >= p.missile.min_range,
		"发射距离 %.0fm（min=%.0fm）" % [r.fire_dist_m, p.missile.min_range])
	_free_pair(ac, tgt)


# ── B. 机炮机：真实机炮窗 ──
func _test_gun_kill_window() -> void:
	print("── B. 机炮 F-14 vs CH-47：30s 内必须打出真实机炮窗 ──")
	var p := _f14_params(false)
	var ac = _make_ac(p, Vector2.ZERO, 0.0)
	var tgt = _make_helo(Vector2(-1400.0, 1600.0))
	ac.combat_target = tgt

	var r := _sim(ac, tgt, p, 45.0, false)
	print("    首次机炮窗 t=%s / 累计窗口时长=%.2fs / 最长连续 SETUP=%.1fs" % [
		("%.1fs" % r.first_gun_t) if r.first_gun_t >= 0.0 else "从未", r.gun_window_s, r.max_setup_streak])
	_check("30s 内打出机炮窗（nose≤5° ∧ 进射程）", r.first_gun_t >= 0.0 and r.first_gun_t <= 30.0,
		("t=%.1fs" % r.first_gun_t) if r.first_gun_t >= 0.0 else "45s 内从未对准进射程")
	# log 实证：CH-47 70hp / 机炮 8dmg ≈ 9 发；0.2s 窗口即足够击坠。0.3s 留余量。
	_check("窗口够长打完一个 kill burst（≥0.3s，log 实证 0.2s 打死）", r.gun_window_s >= 0.3,
		"累计 %.2fs" % r.gun_window_s)
	_check("不绕圈（连续 SETUP < 15s）", r.max_setup_streak < 15.0, "最长 %.1fs" % r.max_setup_streak)
	_free_pair(ac, tgt)


# ── C. 贴脸起手：目标钻进最小转弯圆内 ──
func _test_point_blank_start() -> void:
	print("── C. 贴脸起手（244m，log 实证的 extend 死循环入口）──")
	var p := _f14_params(true)
	var ac = _make_ac(p, Vector2.ZERO, 0.0)
	ac.missiles_remaining = 4
	var tgt = _make_helo(Vector2(122.0, 0.0))   # 正东 244m —— log 143.4s 的"绕不动：半径550m vs 距244m"
	ac.combat_target = tgt

	var r := _sim(ac, tgt, p, 45.0, true)
	print("    首次可发射 t=%s / 距离幅度 %.0fm（min=%.0f max=%.0f）" % [
		("%.1fs" % r.first_fire_t) if r.first_fire_t >= 0.0 else "从未",
		r.max_dist_m - r.min_dist_m, r.min_dist_m, r.max_dist_m])
	_check("贴脸起手也能在 30s 内开火", r.first_fire_t >= 0.0 and r.first_fire_t <= 30.0,
		("t=%.1fs" % r.first_fire_t) if r.first_fire_t >= 0.0 else "45s 未开火")
	# 旧补丁病征：1.5s extend 只拉开 ~290m，永远出不了 825m 重攻门槛 → 距离幅度很小地反复抖
	_check("真的拉开了重攻距离（幅度 > 1200m，对照旧补丁 ~290m）",
		(r.max_dist_m - r.min_dist_m) > 1200.0, "幅度 %.0fm" % (r.max_dist_m - r.min_dist_m))
	_check("不绕圈（连续 SETUP < 15s）", r.max_setup_streak < 15.0, "最长 %.1fs" % r.max_setup_streak)
	_free_pair(ac, tgt)


# ── D. 回归守卫：正常空战目标不得被误判 ──
func _test_fast_target_not_misclassified() -> void:
	print("── D. 回归守卫：快速目标不得走 pass 路径（不污染正常缠斗）──")
	var base := {
		"has_target": true, "my_pos": Vector2.ZERO, "my_heading": 0.0,
		"tgt_pos": Vector2(0, -1000.0), "corner_speed_kmh": 700.0,
	}
	# CH-47 216km/h = 60m/s → 慢（门槛 700×0.4=280km/h）
	var d_slow := base.duplicate(); d_slow["tgt_speed_ms"] = 60.0
	_check("CH-47（216km/h）判为慢速空目标", Situation.new_for_test(d_slow).tgt_is_slow_air, "60 m/s")
	# UAV 233m/s = 839km/h → 快（engagement-discipline §B 明确说它不算慢）
	var d_uav := base.duplicate(); d_uav["tgt_speed_ms"] = 233.0
	_check("UAV（839km/h）不判为慢速", not Situation.new_for_test(d_uav).tgt_is_slow_air, "233 m/s")
	# 边界：300km/h=83.3m/s 的慢速喷气机 → 门槛 280 之上，不判慢
	var d_edge := base.duplicate(); d_edge["tgt_speed_ms"] = 83.3
	_check("300km/h 慢速机不判为慢速（门槛 280km/h）", not Situation.new_for_test(d_edge).tgt_is_slow_air,
		"83.3 m/s")
	# 地面目标走自己的 surface 路径，不重复标记
	var d_gnd := base.duplicate(); d_gnd["tgt_speed_ms"] = 0.0; d_gnd["tgt_is_surface"] = true
	_check("地面目标不重复标记（走 surface 路径）", not Situation.new_for_test(d_gnd).tgt_is_slow_air,
		"tgt_is_surface=true")


# ══════════════════════════════════════════════
#  核心仿真：真实物理 + 真实 planner + 复刻的三道发射门
# ══════════════════════════════════════════════

func _sim(ac, tgt, p: AircraftParams, duration_s: float, missile_mode: bool) -> Dictionary:
	var r := {
		"first_fire_t": -1.0, "fire_dist_m": 0.0, "fire_off_deg": 0.0,
		"first_gun_t": -1.0, "gun_window_s": 0.0,
		"max_lock": 0.0, "max_setup_streak": 0.0,
		"min_dist_m": INF, "max_dist_m": 0.0,
	}
	var lock_t := 0.0
	var setup_streak := 0.0
	var weapon_mode_gun := false     # 复刻 missile_cannot_hit_but_gun_can 的滞回状态
	var steps := int(duration_s / DT)

	for i in range(steps):
		var t: float = float(i) * DT
		# 拨快 planner 时钟到仿真时间（否则 2s 的 EXTEND 会横跨整场 sim 永不到期）
		Situation.sim_time_override = t
		var dist_m: float = ac.global_position.distance_to(tgt.global_position) / CombatUnit.PIXELS_PER_METER
		var off_deg: float = _nose_off_deg(ac, tgt)

		# ── 门 1：雷达锁积分（复刻 survivor_mode.gd 的低空惩罚 + 出锥清零）──
		if off_deg <= p.radar_half_angle and dist_m <= p.radar_range:
			lock_t = minf(lock_t + DT * LOW_ALT_LOCK_RATE, p.lock_time + 0.3)
		else:
			lock_t = maxf(lock_t - DT / OUT_OF_CONE_DUMP_S, 0.0)
		r.max_lock = maxf(r.max_lock, lock_t)
		ac.radar_targets[tgt] = lock_t

		# ── 门 2：武器模式（复刻 min_range + 150m 滞回）──
		if missile_mode:
			var thr: float = p.missile.min_range + (WEAPON_MODE_HYSTERESIS_M if weapon_mode_gun else 0.0)
			weapon_mode_gun = dist_m < thr and dist_m <= p.gun.max_range

		if i % AI_PERIOD == 0:
			ac._run_tactical_planner_if_enabled()
		ac._resolve_intents(DT)
		_step(ac)
		_step_helo(tgt)

		# ── 门 3：发射窗口质量（off-axis / bank）──
		if missile_mode and r.first_fire_t < 0.0:
			var bank_deg: float = absf(rad_to_deg(ac.bank_angle))
			var can_fire: bool = (not weapon_mode_gun) \
					and lock_t >= p.lock_time \
					and dist_m >= p.missile.min_range \
					and off_deg <= p.radar_half_angle * LAUNCH_OFFAX_RATIO_FAF \
					and bank_deg <= LAUNCH_MAX_BANK_FAF
			if can_fire:
				r.first_fire_t = t
				r.fire_dist_m = dist_m
				r.fire_off_deg = off_deg

		# 机炮窗：复刻 aircraft.gd 的真实开火门 —— 判的是**提前点**在机头锥内
		# （_gun_lead_heading vs heading ≤ 5°），不是"机头正对目标本体"；
		# 外加 GUN_TARGET_AHEAD_MIN：目标本体必须在 ±45° 内，防对着空域乱喷。
		var lead_off_deg: float = _lead_off_deg(ac, tgt)
		if lead_off_deg <= GUN_FIRE_CONE_DEG and off_deg <= GUN_TARGET_AHEAD_DEG \
				and dist_m <= p.gun.max_range:
			r.gun_window_s += DT
			if r.first_gun_t < 0.0:
				r.first_gun_t = t

		# 绕圈检测：连续处在 SETUP 相位的最长时间
		var ph: int = ac._last_plan.strafe_pass_phase if ac._last_plan != null else -1
		if ph == TacticalPlan.SurfacePhase.SETUP:
			setup_streak += DT
			r.max_setup_streak = maxf(r.max_setup_streak, setup_streak)
		else:
			setup_streak = 0.0

		r.min_dist_m = minf(r.min_dist_m, dist_m)
		r.max_dist_m = maxf(r.max_dist_m, dist_m)

		if i % 300 == 0:
			print("    [%5.1fs] dist=%5.0fm nose=%5.1f° lock=%.2fs ph=%s %s | %s" % [
				t, dist_m, off_deg, lock_t,
				TacticalPlan.surface_phase_name(ph) if ph >= 0 else "-",
				("GUN" if weapon_mode_gun else "MSL") if missile_mode else "GUN",
				ac._last_plan.rationale if ac._last_plan != null else "-"])
	Situation.sim_time_override = -1.0   # 复位，别污染同一进程里的其他 bench
	return r


# ══════════════════════════════════════════════
#  夹具
# ══════════════════════════════════════════════

## 与 resources/playable_f14_base.tres + default_missile.tres + f14_gun.tres 同数值
func _f14_params(with_missile: bool) -> AircraftParams:
	var p := AircraftParams.new()
	p.max_speed = 2000.0
	p.cruise_speed = 900.0
	p.max_g = 7.5
	p.max_g_structural = 10.0
	p.radar_range = 3500.0
	p.radar_half_angle = 35.0
	p.lock_time = 3.0
	var gun := GunParams.new()
	gun.max_range = 1000.0
	p.gun = gun
	if with_missile:
		var m := MissileParams.new()
		m.max_range_rear = 15000.0
		m.front_rear_ratio = 4.0
		m.min_range = 500.0
		m.fire_and_forget = true
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
	ac.use_tactical_planner = true
	ac.target_position = Vector2.INF
	ac.position = pos
	_root.add_child(ac)
	return ac


## CH-47：真 Aircraft（tgt_is_surface=false），60 m/s 匀速直飞、LOW 档 2000m
func _make_helo(pos: Vector2):
	var hp := AircraftParams.new()
	hp.max_speed = 250.0
	hp.cruise_speed = 216.0
	var h = load("res://scripts/aircraft.gd").new()
	h.params = hp
	h.team = 1
	h.heading = deg_to_rad(-90.0)   # 向西飞（照抄 log 的 HeliFlee 航向）
	h.bank_angle = 0.0
	h.altitude = 2000.0
	h.target_altitude = 2000.0
	h.speed = 60.0
	h.position = pos
	_root.add_child(h)
	return h


## 直升机不跑 planner，只做匀速直线位移（它在 log 里就是这个行为）
func _step_helo(h) -> void:
	h.position += Vector2(sin(h.heading), -cos(h.heading)) * h.speed * CombatUnit.PIXELS_PER_METER * DT


func _step(ac) -> void:
	AircraftPhysics.update_target_heading(ac)
	AircraftPhysics.update_bank(ac, DT)
	AircraftPhysics.update_heading(ac, DT)
	AircraftPhysics.update_speed(ac, DT)
	AircraftPhysics.update_g_load(ac)
	AircraftPhysics.update_altitude(ac, DT)
	AircraftPhysics.apply_movement(ac, DT)


## 机炮提前点相对机头的偏差（复刻 BfmIntent._gun_lead_point 的两次迭代解）
func _lead_off_deg(ac, tgt) -> float:
	var bullet_px: float = GUN_BULLET_SPEED_MS * CombatUnit.PIXELS_PER_METER
	var tgt_v: Vector2 = Vector2(sin(tgt.heading), -cos(tgt.heading)) 			* tgt.speed * CombatUnit.PIXELS_PER_METER
	var d: float = ac.global_position.distance_to(tgt.global_position)
	var lead1: Vector2 = tgt.global_position + tgt_v * (d / maxf(bullet_px, 100.0))
	var t2: float = ac.global_position.distance_to(lead1) / maxf(bullet_px, 100.0)
	var lead: Vector2 = tgt.global_position + tgt_v * t2
	var brg: float = atan2(lead.x - ac.global_position.x, -(lead.y - ac.global_position.y))
	return absf(rad_to_deg(wrapf(brg - ac.heading, -PI, PI)))


func _nose_off_deg(ac, tgt) -> float:
	var to_tgt: Vector2 = tgt.global_position - ac.global_position
	var brg := atan2(to_tgt.x, -to_tgt.y)
	return absf(rad_to_deg(wrapf(brg - ac.heading, -PI, PI)))


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
