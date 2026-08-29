extends RefCounted

## 急刹手感 + 拖拽转向验收（2026-08-28 用户定稿设计）
## 设计四原则：
##   1. 失速软地板 —— 长按刹车减到最小可控速度（stall×1.05）为止，刹不进失速自杀
##   2. 渐进性 —— 巡航速度开刹 1 秒**不能**降到底（用户原话"不至于轻轻按下一秒就到最低"）
##   3. 阻力衰减 —— 高速段单帧减速量 > 低速段（阻力 ∝ v，低速刹车效率自然变差）
##   4. 机型差异 —— deceleration 低的机（低级机）刹得更慢
## 运行：godot --headless --path . -- --bench=hard_brake（或 --bench=all）

const DT := 1.0 / 60.0
const CRUISE_KMH := 900.0     # 250 m/s
const STALL_KMH := 220.0
## g_load=1 时的软地板（m/s）
const FLOOR_MS := STALL_KMH / 3.6 * 1.05

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 急刹手感验收（hard_brake 软地板 + 渐进减速） ════════")

	# ── 1+2. 渐进性 + 软地板 ──
	var ac := _make(80.0)
	ac.hard_brake = true
	for i in range(60):  # 1 秒
		AircraftPhysics.update_speed(ac, DT)
	_check("巡航开刹 1 秒未到底", ac.speed > FLOOR_MS * 1.3,
			"1s 后 %.0f m/s（地板 %.0f）——轻按一秒不能降到最低" % [ac.speed, FLOOR_MS])
	for i in range(1800):  # 再压 30 秒直到收敛
		AircraftPhysics.update_speed(ac, DT)
	_check("长按不进失速（软地板）", ac.speed >= FLOOR_MS - 0.5,
			"30s 后 %.1f m/s ≥ 地板 %.1f——刹不死" % [ac.speed, FLOOR_MS])
	_check("最终收敛到地板附近", ac.speed <= FLOOR_MS + 5.0,
			"刹车确实减到了最小可控速度")
	ac.free()

	# ── 3. 阻力衰减：高速段单帧减速量 > 低速段 ──
	var hi := _make(80.0); hi.hard_brake = true; hi.speed = 250.0
	AircraftPhysics.update_speed(hi, DT)
	var dv_hi := 250.0 - hi.speed
	var lo := _make(80.0); lo.hard_brake = true; lo.speed = 90.0
	AircraftPhysics.update_speed(lo, DT)
	var dv_lo := 90.0 - lo.speed
	_check("高速段减速率明显大于低速段", dv_hi > dv_lo * 1.8,
			"单帧 dv：250m/s 时 %.3f vs 90m/s 时 %.3f" % [dv_hi, dv_lo])
	hi.free(); lo.free()

	# ── 4. 机型差异化：低 deceleration 机刹得慢 ──
	var weak := _make(40.0); weak.hard_brake = true    # 低级机
	var strong := _make(120.0); strong.hard_brake = true  # 高级机
	for i in range(60):
		AircraftPhysics.update_speed(weak, DT)
		AircraftPhysics.update_speed(strong, DT)
	_check("低 decel 机 1 秒后剩余速度更高", weak.speed > strong.speed + 10.0,
			"weak(decel=40) %.0f m/s vs strong(decel=120) %.0f m/s" % [weak.speed, strong.speed])
	weak.free(); strong.free()

	# ── 5. 水平拖拽映射：死区 / 细调 / 满舵 / 左右镜像 ──
	var dead := AircraftPhysics.brake_steer_input_from_dx(11.9)
	var mid_r := AircraftPhysics.brake_steer_input_from_dx(61.0)
	var mid_l := AircraftPhysics.brake_steer_input_from_dx(-61.0)
	var full := AircraftPhysics.brake_steer_input_from_dx(140.0)
	_check("12px 内不误触转向", is_zero_approx(dead), "u=%.3f" % dead)
	_check("中段拖拽可细调且左右镜像", mid_r > 0.0 and mid_r < 1.0 \
			and is_equal_approx(mid_l, -mid_r),
		"right=%.3f left=%.3f" % [mid_r, mid_l])
	_check("110px 外钳为满舵", is_equal_approx(full, 1.0), "u=%.3f" % full)

	# ── 6. 实飞坡度：右正左负，轻拖小于满舵 ──
	var full_turn := _make(80.0)
	full_turn.hard_brake = true
	full_turn.brake_steer_input = 1.0
	full_turn.params.max_g = 9.0
	full_turn.params.max_g_structural = 12.0
	full_turn.params.roll_rate = 4.0
	var state_before := FlightState.from_aircraft(full_turn, true)
	AircraftPhysics.update_bank(full_turn, DT)
	AircraftPhysics.step_bank(state_before, DT)
	_check("急刹转向实飞/预测共享同一坡度", \
			is_equal_approx(full_turn.bank_angle, state_before.bank_angle),
		"live=%.4f predicted=%.4f" % [full_turn.bank_angle, state_before.bank_angle])
	for i in range(29):
		AircraftPhysics.update_bank(full_turn, DT)
		AircraftPhysics.update_heading(full_turn, DT)
		AircraftPhysics.update_g_load(full_turn)
	var full_bank := full_turn.bank_angle
	var full_heading := full_turn.heading

	var fine_turn := _make(80.0)
	fine_turn.hard_brake = true
	fine_turn.brake_steer_input = 0.4
	fine_turn.params.max_g = 9.0
	fine_turn.params.max_g_structural = 12.0
	fine_turn.params.roll_rate = 4.0
	for i in range(30):
		AircraftPhysics.update_bank(fine_turn, DT)
		AircraftPhysics.update_heading(fine_turn, DT)
		AircraftPhysics.update_g_load(fine_turn)
	_check("向右拖拽建立右转且轻拖小于满舵", full_bank > 0.2 \
			and full_heading > 0.0 and fine_turn.bank_angle > 0.0 \
			and fine_turn.bank_angle < full_bank,
		"fine=%.1f° full=%.1f° heading=%.1f°" % [
			rad_to_deg(fine_turn.bank_angle), rad_to_deg(full_bank), rad_to_deg(full_heading)])

	var left_turn := _make(80.0)
	left_turn.hard_brake = true
	left_turn.brake_steer_input = -1.0
	left_turn.params.max_g = 9.0
	left_turn.params.max_g_structural = 12.0
	left_turn.params.roll_rate = 4.0
	for i in range(30):
		AircraftPhysics.update_bank(left_turn, DT)
		AircraftPhysics.update_heading(left_turn, DT)
		AircraftPhysics.update_g_load(left_turn)
	_check("向左拖拽建立左转", left_turn.bank_angle < -0.2 and left_turn.heading < 0.0,
		"bank=%.1f° heading=%.1f°" % [rad_to_deg(left_turn.bank_angle), rad_to_deg(left_turn.heading)])

	# ── 7. 失速闸门：失速/恢复期不能继续拧机头，恢复后才重新取得控制 ──
	var stalled := _make(80.0)
	stalled.hard_brake = true
	stalled.brake_steer_input = 1.0
	stalled.params.max_g = 9.0
	stalled.params.max_g_structural = 12.0
	stalled.params.roll_rate = 4.0
	stalled.bank_angle = 0.6
	stalled.is_stalled = true
	AircraftPhysics.update_bank(stalled, DT)
	_check("正式失速时拖拽失效并回收坡度", stalled.bank_angle < 0.6,
		"bank %.1f° -> %.1f°" % [rad_to_deg(0.6), rad_to_deg(stalled.bank_angle)])
	stalled.is_stalled = false
	stalled.bank_angle = 0.0
	stalled._stall_recovery_timer = 0.5
	AircraftPhysics.update_bank(stalled, DT)
	_check("失速恢复保护期间仍无转向权", is_zero_approx(stalled.bank_angle),
		"bank=%.3f°" % rad_to_deg(stalled.bank_angle))
	stalled._stall_recovery_timer = 0.0
	AircraftPhysics.update_bank(stalled, DT)
	_check("恢复结束后按当前拖拽重新取得控制", stalled.bank_angle > 0.0,
		"bank=%.3f°" % rad_to_deg(stalled.bank_angle))

	# ── 8. 持续侧压不是固定角度航向：中舵可盘旋；满舵最终真实失速 ──
	var circle := _make(80.0)
	circle.hard_brake = true
	circle.brake_steer_input = 0.3
	circle.params.max_g = 9.0
	circle.params.max_g_structural = 12.0
	circle.params.roll_rate = 4.0
	var accumulated_heading := 0.0
	var stall_seen := false
	for i in range(12000):
		var before_heading := circle.heading
		AircraftPhysics.update_bank(circle, DT)
		AircraftPhysics.update_heading(circle, DT)
		AircraftPhysics.update_speed(circle, DT)
		AircraftPhysics.update_stall(circle)
		AircraftPhysics.update_g_load(circle)
		accumulated_heading += Aircraft._angle_diff(circle.heading, before_heading)
		stall_seen = stall_seen or circle.is_stalled
		if accumulated_heading >= TAU:
			break
	_check("鼠标保持侧向可连续盘旋整圈", accumulated_heading >= TAU and not stall_seen,
		"turn=%.0f° stalled=%s" % [rad_to_deg(accumulated_heading), stall_seen])

	var stall_turn := _make(80.0)
	stall_turn.hard_brake = true
	stall_turn.brake_steer_input = 1.0
	stall_turn.params.max_g = 9.0
	stall_turn.params.max_g_structural = 12.0
	stall_turn.params.roll_rate = 4.0
	var stall_turn_degrees := 0.0
	for i in range(1800):
		var before_heading := stall_turn.heading
		AircraftPhysics.update_bank(stall_turn, DT)
		AircraftPhysics.update_heading(stall_turn, DT)
		AircraftPhysics.update_speed(stall_turn, DT)
		AircraftPhysics.update_stall(stall_turn)
		AircraftPhysics.update_g_load(stall_turn)
		stall_turn_degrees += rad_to_deg(Aircraft._angle_diff(stall_turn.heading, before_heading))
		if stall_turn.is_stalled:
			break
	_check("满舵急刹持续转向直到正式失速", stall_turn.is_stalled and stall_turn_degrees > 30.0,
		"turn=%.0f° stalled=%s" % [stall_turn_degrees, stall_turn.is_stalled])

	# ── 9. 输入生命周期：按下建锚、拖动广播、松开原子清理 ──
	var mode = load("res://scripts/survivor/survivor_mode.gd").new()
	var input_ac := _make(80.0)
	mode.selected_aircraft.append(input_ac)
	mode._begin_hard_brake(Vector2(100.0, 200.0))
	mode._update_hard_brake_steer(30.0)
	mode._update_hard_brake_steer(31.0)
	_check("锁鼠标后累计相对位移广播操纵量", input_ac.hard_brake \
			and is_equal_approx(input_ac.brake_steer_input, 0.5),
		"dx=%.1f hard=%s u=%.3f" % [mode._brake_steer_accumulated_dx,
			input_ac.hard_brake, input_ac.brake_steer_input])
	mode._update_hard_brake_steer(-61.0)
	_check("反向相对移动可把摇杆拉回中心", is_zero_approx(input_ac.brake_steer_input),
		"dx=%.1f u=%.3f" % [mode._brake_steer_accumulated_dx, input_ac.brake_steer_input])
	mode._set_hard_brake(false)
	_check("松开右键原子清除急刹与转向", not input_ac.hard_brake \
			and is_zero_approx(input_ac.brake_steer_input) \
			and is_zero_approx(mode._brake_steer_accumulated_dx),
		"hard=%s u=%.3f dx=%.1f" % [input_ac.hard_brake,
			input_ac.brake_steer_input, mode._brake_steer_accumulated_dx])
	mode._begin_hard_brake(Vector2(100.0, 200.0))
	mode._open_evolution_offer()
	_check("机场规划站入口先释放急刹与鼠标捕获", not mode._brake_steer_active \
			and not input_ac.hard_brake and not mode._brake_mouse_captured,
		"active=%s hard=%s captured=%s" % [mode._brake_steer_active,
			input_ac.hard_brake, mode._brake_mouse_captured])
	mode.selected_aircraft.clear()
	mode.free()
	input_ac.free()

	full_turn.free(); fine_turn.free(); left_turn.free(); stalled.free(); circle.free(); stall_turn.free()

	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _make(decel: float) -> Aircraft:
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	var p = AircraftParams.new()
	p.cruise_speed = CRUISE_KMH
	p.stall_speed_base = STALL_KMH
	p.deceleration = decel
	p.acceleration = 50.0
	p.max_g = 9.0
	p.max_g_structural = 12.0
	p.roll_rate = 4.0
	ac.params = p
	ac.speed = CRUISE_KMH / 3.6
	ac.target_speed_kmh = CRUISE_KMH
	ac.g_load = 1.0
	ac.vertical_speed = 0.0
	ac.altitude = 5000.0
	ac.team = 0
	return ac


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-24s — %s" % ["✓" if got else "✗", name, note])
