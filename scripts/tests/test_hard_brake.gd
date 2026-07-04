extends RefCounted

## 急刹手感验收（2026-07-03 用户定稿设计）
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

	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _make(decel: float) -> Aircraft:
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	var p = AircraftParams.new()
	p.cruise_speed = CRUISE_KMH
	p.stall_speed_base = STALL_KMH
	p.deceleration = decel
	p.acceleration = 50.0
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
