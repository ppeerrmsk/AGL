extends RefCounted

## 无头验收：交战速度治理（spec bosses/wraith-squadron —— 绕圈死结修复）
##
## 背景（playtest log 20260720_172222）：王牌中队全程 ph=HI_BANK、g 钉死 max_g，
## 四架同姿态绕玩家画圆，tp_brg 长期 ±90°，机头一次没指向过目标。
## 根因是几何：711 m/s 下 12G 盘旋半径 4310m，而交战距离只有 ~2000m。
##
## A. 公式：距离单调性 / 角点速度地板 / 远距不治理
## B. **裸物理步进 sim**（本测试的核心，纯几何单测会漏物理 bug）：
##    F-47 参数逐帧跑 Situation→TacticalPlanner→AircraftPhysics，
##    对照"无治理 vs 有治理"下机头偏角能否收敛
##
## 运行：godot --headless --path . -- --bench=speed_governor（或 --bench=all）

const DT := 1.0 / 60.0
const AI_PERIOD := 3        ## AI 分频，与真实 planner tick 一致

var _pass := 0
var _fail := 0
var _root: Node2D = null
var _sum_nose := 0.0
var _sum_spd := 0.0
var _sum_bank := 0.0
var _aimed := 0.0
var _intents: Dictionary = {}


func run() -> void:
	print("\n════════ 交战速度治理（转弯半径 ≤ 交战距离） ════════")
	_root = Node2D.new()
	_test_formula()
	_test_sim_convergence()
	_root.free()
	_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


# ══════════════════════════════════════════════
#  A. 公式
# ══════════════════════════════════════════════

func _test_formula() -> void:
	print("── A. 速度上限公式 ──")
	var corner := 623.0   # F-47 角点速度 km/h
	var max_g := 12.0

	var c500 := EngagementSpeedGovernor.speed_cap_kmh(500.0, max_g, corner)
	var c2000 := EngagementSpeedGovernor.speed_cap_kmh(2000.0, max_g, corner)
	var c5000 := EngagementSpeedGovernor.speed_cap_kmh(5000.0, max_g, corner)

	_check("距离越远上限越高", c500 <= c2000 and c2000 <= c5000,
			"500m=%.0f / 2000m=%.0f / 5000m=%.0f km/h" % [c500, c2000, c5000])
	_check("角点速度地板生效", c500 >= corner,
			"近距 cap=%.0f ≥ 角点 %.0f（绝不压到失速螺旋）" % [c500, corner])

	# 2000m 处解出的速度，其盘旋半径必须 ≤ 1000m（= dist × RADIUS_RATIO）
	var v_ms := c2000 / 3.6
	var r := v_ms * v_ms / (EngagementSpeedGovernor.GRAVITY * sqrt(max_g * max_g - 1.0))
	_check("2000m 处半径 ≤ 1000m", r <= 1000.0 + 1.0,
			"cap=%.0f km/h → R=%.0fm" % [c2000, r])

	# 远距不治理
	var s := _mk_situation(8000.0, max_g, corner, 2800.0)
	var p := TacticalPlan.new()
	p.target_speed_kmh = 2800.0
	_check("超 6000m 不治理", not EngagementSpeedGovernor.apply(s, p),
			"8000m 处保持 %.0f km/h（远距接近该开快）" % p.target_speed_kmh)

	# 近距治理 + 关加力
	var s2 := _mk_situation(2000.0, max_g, corner, 2800.0)
	var p2 := TacticalPlan.new()
	p2.target_speed_kmh = 2800.0
	p2.afterburner = true
	var governed := EngagementSpeedGovernor.apply(s2, p2)
	_check("2000m 处压制生效", governed and p2.target_speed_kmh < 2800.0,
			"2800 → %.0f km/h" % p2.target_speed_kmh)
	_check("压制时关掉加力", not p2.afterburner, "否则直接抵消治理")

	# 低 G 机不该被压到离谱
	var c_lowg := EngagementSpeedGovernor.speed_cap_kmh(2000.0, 1.0, corner)
	_check("max_g≤1 退化为角点速度", is_equal_approx(c_lowg, corner),
			"cap=%.0f（无法稳定盘旋）" % c_lowg)


# ══════════════════════════════════════════════
#  B. 裸物理步进 sim —— 机头能否收敛到目标
# ══════════════════════════════════════════════

func _test_sim_convergence() -> void:
	print("── B. 物理 sim：F-47 对 2000m 外机动目标 ──")
	var ungoverned := _run_sim(false)
	var governed := _run_sim(true)

	# ⚠ 指标选择：用**平均**机头偏角与"指向占比"，不能用 min —— 绕圈时机头也会
	# 瞬间扫过 0°，min_nose_off 在两种情况下都是 0，完全无法区分（第一版就栽在这）。

	# 无治理：复现 playtest 的绕圈
	_check("无治理时机头长期偏离（复现 bug）", ungoverned["avg_nose"] > 40.0,
			"平均机头偏角 %.0f°（绕圈：机头长期指不到目标）" % ungoverned["avg_nose"])
	_check("无治理时指向占比低（复现 bug）", ungoverned["aimed_frac"] < 0.75,
			"仅 %.0f%% 的时间机头在 30° 内" % (ungoverned["aimed_frac"] * 100.0))

	# 有治理：机头稳定压在武器可用区间
	_check("治理后机头收敛", governed["avg_nose"] < 15.0,
			"平均机头偏角 %.0f°（可持续进火控锥）" % governed["avg_nose"])
	_check("治理后指向占比高", governed["aimed_frac"] > 0.90,
			"%.0f%% 的时间机头在 30° 内" % (governed["aimed_frac"] * 100.0))
	_check("治理显著改善指向", ungoverned["avg_nose"] - governed["avg_nose"] > 30.0,
			"%.0f° → %.0f°" % [ungoverned["avg_nose"], governed["avg_nose"]])
	_check("治理确实压低了速度", governed["avg_speed"] < ungoverned["avg_speed"] - 100.0,
			"%.0f → %.0f km/h" % [ungoverned["avg_speed"], governed["avg_speed"]])
	# 不得把飞机压到失速（用户硬约束：转弯不得自陷失速）
	_check("治理后不失速", governed["min_speed_kmh"] >= 600.0,
			"最低速 %.0f km/h（角点 ~623，不得掉进死亡螺旋）" % governed["min_speed_kmh"])


## 跑一次 sim，返回统计
func _run_sim(governed: bool) -> Dictionary:
	var ac = _make_f47(Vector2.ZERO, 0.0)
	# 目标在正前方 2000m（= 1000px），横向匀速机动
	var tgt = _make_target(Vector2(0, -1000.0), PI / 2.0)
	ac.combat_target = tgt
	var ai = _make_ai(ac, tgt)

	var min_nose := 999.0
	var min_spd := 99999.0
	var sum_r := 0.0
	var sum_d := 0.0
	var n := 0
	_sum_nose = 0.0
	_sum_spd = 0.0
	_sum_bank = 0.0
	_aimed = 0.0
	_intents = {}

	for i in range(45 * 60):
		if i % AI_PERIOD == 0:
			_plan_step(ac, governed)
		_step(ac)
		_move_straight(tgt)

		# 前 3 秒是建立几何的过渡期，不计入统计
		if i < 180:
			continue
		var nose := _nose_off_deg(ac, tgt)
		min_nose = minf(min_nose, nose)
		_sum_nose += nose
		_sum_spd += float(ac.speed) * 3.6
		_sum_bank += absf(rad_to_deg(ac.bank_angle))
		if nose < 30.0:
			_aimed += 1.0
		min_spd = minf(min_spd, float(ac.speed) * 3.6)
		var dist_m: float = ac.global_position.distance_to(tgt.global_position) / CombatUnit.PIXELS_PER_METER
		sum_d += dist_m
		sum_r += _turn_radius_m(ac)
		n += 1

	var out := {
		"min_nose_off": min_nose,
		"min_speed_kmh": min_spd,
		"avg_radius": sum_r / maxf(float(n), 1.0),
		"avg_dist": sum_d / maxf(float(n), 1.0),
		"avg_nose": _sum_nose / maxf(float(n), 1.0),
		"aimed_frac": _aimed / maxf(float(n), 1.0),
		"avg_speed": _sum_spd / maxf(float(n), 1.0),
		"avg_bank": _sum_bank / maxf(float(n), 1.0),
		"intents": _intents.duplicate(),
	}
	print("    [diag governed=%s] nose avg=%.0f° min=%.0f° | 指向占比=%.0f%% | spd avg=%.0f km/h | bank avg=%.0f° | dist avg=%.0fm | intents=%s" % [
		str(governed), out["avg_nose"], out["min_nose_off"], out["aimed_frac"] * 100.0,
		out["avg_speed"], out["avg_bank"], out["avg_dist"], str(out["intents"])])
	_free_pair(ac, tgt, ai)
	return out


## 复刻 aircraft.gd 的 planner 接线（只保留速度/pursuit 两个契约字段）
func _plan_step(ac, governed: bool) -> void:
	var s := Situation.from_aircraft(ac)
	var plan := TacticalPlanner.plan(s, Vector2.INF)
	if governed:
		EngagementSpeedGovernor.apply(s, plan)
	var iname := TacticalPlan.intent_name(plan.intent)
	_intents[iname] = int(_intents.get(iname, 0)) + 1
	if plan.pursuit_pos != Vector2.INF:
		ac.target_position = plan.pursuit_pos
	ac.target_speed_kmh = plan.target_speed_kmh
	ac.is_afterburner = plan.afterburner


## 当前瞬时盘旋半径（米）。bank≈0 时返回一个大数代表"几乎直飞"
func _turn_radius_m(ac) -> float:
	var g_lat: float = EngagementSpeedGovernor.GRAVITY * absf(tan(ac.bank_angle))
	if g_lat < 0.05:
		return 99999.0
	var v: float = float(ac.speed)
	return v * v / g_lat


# ══════════════════════════════════════════════
#  helpers
# ══════════════════════════════════════════════

func _mk_situation(dist_m: float, max_g: float, corner: float, max_spd: float) -> Situation:
	var s := Situation.new()
	s.has_target = true
	s.dist_m = dist_m
	s.max_g = max_g
	s.corner_speed_kmh = corner
	s.max_speed_kmh = max_spd
	return s


## F-47 王牌中队参数（resources/enemy_f47.tres 的关键值）
func _make_f47(pos: Vector2, hdg: float):
	var p := AircraftParams.new()
	p.max_speed = 2800.0
	p.cruise_speed = 1600.0
	p.stall_speed_base = 180.0
	p.max_g = 12.0
	p.max_g_structural = 15.0
	p.roll_rate = 5.0
	p.g_drag_factor = 1.5
	p.max_hp = AceTier.MAX_HP
	var ac = _make_ac(p, pos, hdg)
	AceTier.mark(ac)
	# 起手就在高速档 —— 这正是 playtest 里绕圈的初始条件
	ac.speed = 700.0
	ac.target_speed_kmh = 2520.0
	return ac


func _make_target(pos: Vector2, hdg: float):
	var p := AircraftParams.new()
	p.max_speed = 2000.0
	p.cruise_speed = 900.0
	p.stall_speed_base = 200.0
	p.max_g = 8.0
	var t = _make_ac(p, pos, hdg)
	t.speed = 250.0
	return t


func _make_ac(params: AircraftParams, pos: Vector2, hdg: float):
	var ac = load("res://scripts/aircraft.gd").new()
	ac.params = params
	ac.heading = hdg
	ac.bank_angle = 0.0
	ac.altitude = 5000.0
	ac.flat_altitude = true
	ac.speed = params.cruise_speed / 3.6
	ac.target_speed_kmh = params.cruise_speed
	ac.g_load = 1.0
	ac.tactical_aggression = 1.0
	ac.position = pos
	_root.add_child(ac)
	return ac


func _make_ai(ac, tgt) -> AIController:
	var ai: AIController = load("res://scripts/ai_controller.gd").new()
	ai.aircraft = ac
	ai._current_target = tgt
	ac._ai_ref = ai
	ac.add_child(ai)
	return ai


func _step(ac) -> void:
	AircraftPhysics.update_target_heading(ac)
	AircraftPhysics.update_bank(ac, DT)
	AircraftPhysics.update_heading(ac, DT)
	AircraftPhysics.update_speed(ac, DT)
	AircraftPhysics.update_g_load(ac)
	AircraftPhysics.apply_movement(ac, DT)


func _move_straight(tgt) -> void:
	var v: Vector2 = Vector2(sin(tgt.heading), -cos(tgt.heading)) \
			* float(tgt.speed) * CombatUnit.PIXELS_PER_METER
	tgt.position += v * DT


func _nose_off_deg(ac, tgt) -> float:
	var to_tgt: Vector2 = tgt.global_position - ac.global_position
	var brg := atan2(to_tgt.x, -to_tgt.y)
	return absf(rad_to_deg(wrapf(brg - ac.heading, -PI, PI)))


func _free_pair(ac, tgt, ai) -> void:
	ac.remove_child(ai)
	ai.free()
	_root.remove_child(ac)
	ac.free()
	_root.remove_child(tgt)
	tgt.free()


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-30s — %s" % ["✓" if got else "✗", name, note])
