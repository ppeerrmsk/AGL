extends RefCounted

## 无头验收：带玩家命令的躲弹恢复 + 分层规避入口门（B1 定稿策略 2026-07-02）
## 见 docs/planning/physics-ai-control-refactor.md §3 "B1 定稿策略"。
##
## 覆盖三件事：
##   A. should_enter_evade 分层门 —— flare 能兜底不进 EVADE；无 flare 才机动；
##      打不到的慢弹不算威胁；敌方不受 flare 门约束
##   B. 命令铁律 × EVADE 仲裁 —— 躲弹中 _enforce_commanded_target 让位且不清命令
##   C. 闭环序列 —— ENGAGE(命令) → 躲弹 → 威胁消失 → 恢复 ENGAGE 同一命令目标，
##      evasion_mode 不卡 true，威胁持续期间无 ENGAGE↔EVADE 抖动（旧 bug 回归守护）
##
## 运行：godot --headless --path . -- --bench=cmd_evade（或 --bench=all）
##
## 几何约定：1 像素 = 2 米。本机在原点 heading=0（机头朝北 -y），
## 尾追导弹放 +y（正后方），heading=0 朝 -y 追上来 → closing 大、TTI 小 = 真威胁。

const FLARE_TRES := "res://resources/default_flare.tres"
const DT := 1.0 / 60.0

var _pass := 0
var _fail := 0
var _root: Node2D = null          ## 离树根：aircraft 与 missile_manager 的共同父节点
var _mm: MissileManager = null    ## 真实 MissileManager（_get_missile_manager 按类型识别）


func run() -> void:
	print("\n════════ 带命令躲弹验收（B1 分层规避 + 铁律让位） ════════")
	_test_entry_gate()
	_test_iron_rule_yield()
	_test_full_cycle()
	if _root:
		_root.free()  # 连同 MissileManager 一起释放，防 headless 退出时 ObjectDB 泄漏警告
		_root = null
		_mm = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 分层入口门 ──
func _test_entry_gate() -> void:
	print("── A. should_enter_evade：flare 优先 → 无 flare 才机动 ──")
	var ai := _make_ai_aircraft()
	var ac: Aircraft = ai.aircraft

	_check("无导弹 → 不躲", MissileEvasion.should_enter_evade(ai), false, "策略①：无威胁不脱队")

	var m := _spawn_missile(Vector2(0, 300), 1100.0, ac)
	_check("真威胁 + flare 就绪 → 不躲", MissileEvasion.should_enter_evade(ai), false,
			"策略②：flare 末段兜底，留在命令航线")

	ac.flares_remaining = 0
	_check("真威胁 + 弹尽 → 躲", MissileEvasion.should_enter_evade(ai), true,
			"策略③：无 flare 才运动学规避")
	ac.flares_remaining = 4

	ac._flare_cooldown = 3.0
	_check("真威胁 + flare CD 中 → 躲", MissileEvasion.should_enter_evade(ai), true,
			"策略③：flare 刚失手进 CD → 机动兜底")
	ac._flare_cooldown = 0.0

	ac.missile_phase_timer = 0.5
	_check("导弹穿透窗口 → 不躲", MissileEvasion.should_enter_evade(ai), false,
			"免疫窗内导弹打不中")
	ac.missile_phase_timer = 0.0

	ac._flare_ignored_missiles[m.get_instance_id()] = true
	_check("flare 已放弃该弹 → 躲", MissileEvasion.should_enter_evade(ai), true,
			"fail_chance 弃管的弹只能机动")
	ac._flare_ignored_missiles.clear()

	_despawn_missile(m)

	# 慢弹（closing < 60 m/s 追不上）：即使弹尽也不构成脱队理由
	var m_slow := _spawn_missile(Vector2(0, 400), 280.0, ac)
	ac.flares_remaining = 0
	_check("慢弹追不上 + 弹尽 → 不躲", MissileEvasion.should_enter_evade(ai), false,
			"策略①：打不到的导弹不算威胁")
	ac.flares_remaining = 4
	_despawn_missile(m_slow)

	# leash 拽回后的再入冷却：归队意志压过规避（防 EVADE↔SQUAD_FOLLOW 振荡）
	var m_cd := _spawn_missile(Vector2(0, 300), 1100.0, ac)
	ac.flares_remaining = 0
	ai._evade_reenter_cd = 2.0
	_check("leash 再入冷却中 → 不躲", MissileEvasion.should_enter_evade(ai), false,
			"拽回后先归队 2s，防振荡")
	ai._evade_reenter_cd = 0.0
	_check("冷却归零 → 恢复躲", MissileEvasion.should_enter_evade(ai), true, "")
	ac.flares_remaining = 4
	_despawn_missile(m_cd)

	# 敌方：不受 flare 门约束（维持难度）
	var ai_e := _make_ai_aircraft()
	ai_e.aircraft.team = 1
	var m_e := _spawn_missile(Vector2(0, 300), 1100.0, ai_e.aircraft)
	_check("敌方 + 真威胁 + flare 就绪 → 照躲", MissileEvasion.should_enter_evade(ai_e), true,
			"flare 门仅玩家方")
	_despawn_missile(m_e)
	_free_ai_aircraft(ai_e)
	_free_ai_aircraft(ai)


# ── B. 命令铁律 × EVADE 仲裁 ──
func _test_iron_rule_yield() -> void:
	print("── B. 铁律让位：躲弹中不强拉回 ENGAGE、不清命令 ──")
	var ai := _make_ai_aircraft()
	var cmd := _make_enemy_target()
	ai.aircraft.commanded_target = cmd

	# 正常交战：铁律照常接管
	ai._state = AIController.AIState.ENGAGE
	_check("ENGAGE 中铁律接管", ai._enforce_commanded_target(), true, "命令照常执行")
	_check("接管后 combat_target=命令", ai.aircraft.combat_target == cmd, true, "")

	# 躲弹中：铁律让位且保留命令（Phase 2：EVADE 是 _evading modifier，不占 _state 轴）
	ai._evading = true
	_check("EVADE 中铁律让位", ai._enforce_commanded_target(), false,
			"分发层短路 + _enforce 内双保险")
	ai._evading = false
	_check("让位不清命令", ai.aircraft.commanded_target == cmd, true,
			"commanded_target 保留，脱险后重接")

	cmd.free()
	_free_ai_aircraft(ai)


# ── C. 闭环序列 + 抖动回归守护 ──
func _test_full_cycle() -> void:
	print("── C. 闭环：ENGAGE(命令) → 躲弹(无抖动) → 脱险恢复同一命令目标 ──")
	var ai := _make_ai_aircraft()
	var ac: Aircraft = ai.aircraft
	ac.use_tactical_planner = true   # planner 机：evasion_mode 通路全走一遍
	var cmd := _make_enemy_target()
	ac.commanded_target = cmd

	# 1) 铁律建立交战
	ai._state = AIController.AIState.PATROL
	var enforced := ai._enforce_commanded_target()
	_check("建立命令交战", enforced and ai._state == AIController.AIState.ENGAGE, true, "")

	# 2) 真威胁 + 弹尽 → 应进躲（分层门放行）→ enter_evade
	ac.flares_remaining = 0
	var m := _spawn_missile(Vector2(0, 300), 1100.0, ac)
	_check("威胁在场应进躲", MissileEvasion.should_enter_evade(ai), true, "")
	MissileEvasion.enter_evade(ai)
	_check("进躲后 _evading=true", ai._evading, true, "Phase 2：modifier 置位")
	_check("进躲背景状态保持 ENGAGE", ai._state == AIController.AIState.ENGAGE, true,
			"EVADE 不占 _state 轴，退出即无缝回落")
	_check("进躲后 evasion_mode=true", ac.evasion_mode, true, "planner 协作通路")
	_check("进躲保留 _current_target", ai._current_target == cmd, true, "脱险无缝恢复用")

	# 3) 威胁持续 30 tick：铁律每 tick 让位、process_evade 维持 —— 不得弹回 ENGAGE
	#    （旧 bug：铁律排在 match 前，每 tick 强拉回 ENGAGE → ENGAGE↔EVADE 抖动）
	var bounced := 0
	for i in range(30):
		if ai._enforce_commanded_target():
			bounced += 1  # 旧 bug 路径：躲弹中被铁律接管
		else:
			MissileEvasion.process_evade(ai, DT)
		if not ai._evading:
			bounced += 1
	_check("威胁持续期间零弹回（30 tick）", bounced == 0, true,
			"旧 bug 实测按 tick 频率 ENGAGE↔EVADE 抖")
	_check("躲弹中命令仍保留", ac.commanded_target == cmd, true, "")

	# 4) 威胁消失（flare 干扰掉）→ 下一 tick process_evade 退出并恢复命令目标
	m.is_flare_jammed = true
	MissileEvasion.process_evade(ai, DT)
	_check("脱险恢复 ENGAGE", ai._state == AIController.AIState.ENGAGE, true, "exit_evade 三分支之一")
	_check("恢复同一命令目标", ac.combat_target == cmd, true, "_current_target 无缝恢复")
	_check("evasion_mode 不卡 true", ac.evasion_mode, false,
			"旧 bug：卡 true → planner 持续 max+AB 武器静默")

	# 5) 恢复后铁律重新接管
	_check("脱险后铁律重接", ai._enforce_commanded_target(), true, "")

	_despawn_missile(m)
	cmd.free()
	_free_ai_aircraft(ai)


# ══════════════ 构造辅助 ══════════════

## 组装：root ── aircraft（挂 AIController 子节点）+ MissileManager 兄弟节点。
## 离树组装（不进 scene tree，不跑 _physics_process），_get_missile_manager 靠
## "aircraft.get_parent() 的子节点里找 MissileManager" 仍可用。
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
	ac.flares_remaining = 4
	ac._flare_cooldown = 0.0
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
	ac.free()  # 连同子节点 AIController 一起释放


func _make_enemy_target() -> Aircraft:
	var t: Aircraft = load("res://scripts/aircraft.gd").new()
	t.global_position = Vector2(2000, -2000)
	t.heading = 0.0
	t.speed = 250.0
	t.team = 1
	return t


func _spawn_missile(pos: Vector2, spd: float, target) -> Missile:
	var m := Missile.new()
	m.global_position = pos
	m.heading = 0.0
	m.speed = spd
	m.is_active = true
	m.is_flare_jammed = false
	m.target = target
	_mm.add_child(m)
	return m


func _despawn_missile(m: Missile) -> void:
	_mm.remove_child(m)
	m.free()


# ══════════════ 断言 ══════════════

func _check(name: String, got: bool, expect: bool, note: String) -> void:
	var ok := got == expect
	if ok: _pass += 1
	else: _fail += 1
	print("  %s %-28s 期望=%s 实际=%s — %s" % [
		"✓" if ok else "✗", name, str(expect), str(got), note])
