extends RefCounted

## 无头验收：隐形对"玩家点名 combat target"的铁律让位（spec ace-squadron-tier §3.5）
##
## 覆盖三处改动：
##   A. 命令铁律隐形挂起 —— _enforce_commanded_target 在目标 is_cloaked 时主动以 TS_COMMANDED
##      交出目标持有权（破优先级死锁）、不清 commanded_target 指针；解除隐形自动重接 ENGAGE；
##      挂起期反复调用零抖动。
##   B. 姿态门收紧 —— Situation 姿态透传要求 combat_target == commanded_target，
##      让位期临时交战别的目标时点名姿态/包围方位不泄漏。
##   C. planner 隐形失效 —— Situation 目标段对 is_cloaked 的 combat_target 置 has_target=false，
##      堵玩家亲控机（planner 路径）对隐形目标零误差跟踪的真空区。
##
## 运行：godot --headless --path . -- --bench=cmd_cloak（或 --bench=all）
##
## 只认 is_cloaked（真隐形），不认整个 is_lock_immune()：弹射/出场免疫窗与 MountTarget 不丢命令。

const FLARE_TRES := "res://resources/default_flare.tres"

var _pass := 0
var _fail := 0
var _root: Node2D = null
var _mm: MissileManager = null


func run() -> void:
	print("\n════════ 隐形 × 命令铁律让位验收（ace-squadron-tier §3.5） ════════")
	_test_iron_rule_cloak_yield()
	_test_posture_gate()
	_test_planner_cloak_invalidation()
	if _root:
		_root.free()
		_root = null
		_mm = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 命令铁律隐形挂起 ──
func _test_iron_rule_cloak_yield() -> void:
	print("── A. 隐形挂起：交出持有权 / 保留指针 / 解除自动重接 / 零抖动 ──")
	var ai := _make_ai_aircraft()
	var cmd := _make_enemy_target()
	ai.aircraft.commanded_target = cmd
	ai._state = AIController.AIState.ENGAGE

	# 建立命令交战
	_check("ENGAGE 中铁律接管", ai._enforce_commanded_target(), true, "命令照常执行")
	_check("接管后 combat_target=命令", ai.aircraft.combat_target == cmd, true, "")
	_check("接管后 _current_target=命令", ai._current_target == cmd, true, "")

	# 目标隐形 → 铁律让位：release + 不清指针
	cmd.is_cloaked = true
	_check("隐形中铁律让位（返回 false）", ai._enforce_commanded_target(), false,
			"落回 match 分发，归队/临时交战")
	_check("让位交出 combat_target", ai.aircraft.combat_target == null, true,
			"TS_COMMANDED release 破优先级死锁")
	_check("让位交出 _current_target", ai._current_target == null, true, "")
	_check("让位【不清】命令指针", ai.aircraft.commanded_target == cmd, true,
			"挂起而非硬清，解除隐形重接")

	# 隐形期反复调用：零抖动（始终让位、始终不咬回、指针恒保留）
	var churn := 0
	for _i in range(30):
		if ai._enforce_commanded_target():
			churn += 1  # 隐形中不应咬回
		if ai.aircraft.combat_target != null or ai.aircraft.commanded_target != cmd:
			churn += 1
	_check("隐形期 30 tick 零抖动", churn == 0, true, "不得 acquire↔disengage 空转")

	# 解除隐形 → 下一 tick 自动重接 ENGAGE，无需重新点名
	cmd.is_cloaked = false
	_check("解除隐形铁律重接（返回 true）", ai._enforce_commanded_target(), true,
			"acquire_target(TS_COMMANDED) 无条件抢回")
	_check("重接后 combat_target=命令", ai.aircraft.combat_target == cmd, true, "玩家无需重新点名")
	_check("重接后 _current_target=命令", ai._current_target == cmd, true, "")

	cmd.free()
	_free_ai_aircraft(ai)


# ── B. 姿态门收紧 ──
func _test_posture_gate() -> void:
	print("── B. 姿态门：仅 combat_target==commanded_target 时透传点名姿态 ──")
	var ai := _make_ai_aircraft()
	var ac: Aircraft = ai.aircraft
	var cmd := _make_enemy_target()
	var other := _make_enemy_target()
	ac.commanded_target = cmd
	ac.attack_posture = Situation.POSTURE_ASSAULT
	ac.surround_bearing_rad = 1.23

	# 正在打命令目标本身 → 姿态照常透传
	ac.combat_target = cmd
	var s1 := Situation.from_aircraft(ac)
	_check("打命令目标时透传姿态", s1.attack_posture == Situation.POSTURE_ASSAULT, true, "")
	_check("打命令目标时透传包围方位", is_equal_approx(s1.surround_bearing, 1.23), true, "")

	# 让位期临时交战别的目标 → 点名姿态不泄漏（回落默认 AUTO/INF）
	ac.combat_target = other
	var s2 := Situation.from_aircraft(ac)
	_check("临时目标不泄漏姿态", s2.attack_posture == Situation.POSTURE_AUTO, true,
			"combat_target != commanded_target 门挡住")
	_check("临时目标不泄漏包围方位", s2.surround_bearing == INF, true, "")

	cmd.free()
	other.free()
	_free_ai_aircraft(ai)


# ── C. planner 隐形失效 ──
func _test_planner_cloak_invalidation() -> void:
	print("── C. planner 目标段：隐形 combat_target 置 has_target=false ──")
	var ai := _make_ai_aircraft()
	var ac: Aircraft = ai.aircraft
	ac.use_tactical_planner = true   # 玩家亲控机走 planner 路径
	var cmd := _make_enemy_target()
	ac.combat_target = cmd

	# 可见 → 正常获取目标
	var s_vis := Situation.from_aircraft(ac)
	_check("可见目标 has_target=true", s_vis.has_target, true, "")

	# 隐形 → 目标段拦截，has_target=false（不再获得精确位置）
	cmd.is_cloaked = true
	var s_cloak := Situation.from_aircraft(ac)
	_check("隐形目标 has_target=false", s_cloak.has_target, false,
			"堵零误差跟踪：扳机哑火 + 不精确指向")

	# 恢复可见 → 目标段恢复
	cmd.is_cloaked = false
	var s_back := Situation.from_aircraft(ac)
	_check("解除隐形 has_target 恢复", s_back.has_target, true, "")

	cmd.free()
	_free_ai_aircraft(ai)


# ══════════════ 构造辅助 ══════════════

func _make_ai_aircraft() -> AIController:
	if _root == null:
		_root = Node2D.new()
		_mm = MissileManager.new()
		_root.add_child(_mm)
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0
	ac.speed = 250.0
	ac.team = 0
	var p = AircraftParams.new()
	p.flare = load(FLARE_TRES)
	ac.params = p
	ac.missile_manager = _mm
	_root.add_child(ac)
	var ai: AIController = load("res://scripts/ai_controller.gd").new()
	ai.aircraft = ac
	ac._ai_ref = ai
	ac.add_child(ai)
	return ai


func _free_ai_aircraft(ai: AIController) -> void:
	var ac: Aircraft = ai.aircraft
	_root.remove_child(ac)
	ac.free()


func _make_enemy_target() -> Aircraft:
	var t: Aircraft = load("res://scripts/aircraft.gd").new()
	t.global_position = Vector2(2000, -2000)
	t.heading = 0.0
	t.speed = 250.0
	t.team = 1
	return t


# ══════════════ 断言 ══════════════

func _check(name: String, got: bool, expect: bool, note: String) -> void:
	var ok := got == expect
	if ok: _pass += 1
	else: _fail += 1
	print("  %s %-30s 期望=%s 实际=%s — %s" % [
		"✓" if ok else "✗", name, str(expect), str(got), note])
