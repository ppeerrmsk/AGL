extends RefCounted

const AIAltitudePolicy := preload("res://scripts/ai/ai_altitude_policy.gd")

## 无头验收：Phase 2 状态机正交化（重构计划 §5 Phase 2）
##
## A. 过渡函数字段集 —— enter_engage/squad_follow/patrol 的字段清单唯一化断言
## B. EVADE modifier —— enter/exit 对称、背景状态保持、幂等、三路重定
## C. 约束层 —— combat_zone 出界回拉 + 小队 leash（ENGAGE/EVADE 一视同仁）+
##    命令铁律豁免（ENGAGE 有豁免 / EVADE 无豁免 = 旧语义保持）
##
## 运行：godot --headless --path . -- --bench=state_machine（或 --bench=all）

const DT := 1.0 / 60.0

var _pass := 0
var _fail := 0
var _root: Node2D = null


func run() -> void:
	print("\n════════ 状态机正交化验收（Phase 2） ════════")
	_root = Node2D.new()
	_test_transition_fields()
	_test_evade_modifier()
	_test_constraints()
	_root.free()
	_root = null
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 过渡函数字段集 ──
func _test_transition_fields() -> void:
	print("── A. 过渡函数：字段清单唯一化 ──")
	var ai := _make_ai()

	# enter_engage_state 全重置 planner 滞回
	ai.aircraft._last_plan = TacticalPlan.new()
	ai.aircraft._bfm_prev_intent = TacticalPlan.Intent.EXTEND_RECOVER
	ai.aircraft._bfm_intent_started_at = 9.9
	ai.aircraft._bfm_extend_until = 99.0
	ai._engage_timer = 9.9
	ai.enter_engage_state()
	_check("enter_engage：state+timer+plan 重置",
		ai._state == AIController.AIState.ENGAGE and ai._engage_timer == 0.0 \
		and ai.aircraft._last_plan == null and ai.aircraft._bfm_prev_intent == -1 \
		and ai.aircraft._bfm_intent_started_at == 0.0 and ai.aircraft._bfm_extend_until == 0.0,
		"新交战完整重置")

	# enter_engage_state(false) 软重连保留 planner 滞回
	var held_plan := TacticalPlan.new()
	held_plan.intent = TacticalPlan.Intent.LEAD_TURN
	ai.aircraft._last_plan = held_plan
	ai.aircraft._bfm_prev_intent = TacticalPlan.Intent.LEAD_TURN
	ai.aircraft._bfm_intent_started_at = 3.3
	ai.enter_engage_state(false)
	_check("enter_engage(false)：软重连不打断 plan",
		ai.aircraft._last_plan == held_plan \
		and ai.aircraft._bfm_prev_intent == TacticalPlan.Intent.LEAD_TURN \
		and ai.aircraft._bfm_intent_started_at == 3.3 \
		and ai._engage_timer == 0.0,
		"BOSS 维持/躲弹恢复用")

	# enter_squad_follow_state 常规归队
	ai.aircraft.ai_override_pursuit = true
	ai.aircraft.lod_level = 0
	ai.enter_squad_follow_state()
	_check("enter_squad_follow：归队字段集",
		ai._state == AIController.AIState.SQUAD_FOLLOW and ai._rejoining \
		and ai._formation_blend == 0.0 and ai._cover_target == null \
		and not ai.aircraft.ai_override_pursuit and ai.aircraft.lod_level == 1,
		"rejoin 渐变 + LOD1 + 清 override")

	# enter_squad_follow_state(true) 直接落位
	ai.enter_squad_follow_state(true)
	_check("enter_squad_follow(snap)：跳过渐变",
		not ai._rejoining and ai._formation_blend == 1.0,
		"玩家 UI 强制切模式用")

	# enter_patrol_state
	ai.aircraft.ai_override_pursuit = true
	ai.enter_patrol_state(false)
	_check("enter_patrol(false)：state + 清 override，航点归调用方",
		ai._state == AIController.AIState.PATROL and not ai.aircraft.ai_override_pursuit,
		"zone 回拉等自带航点路径")

	# 高度策略不再寄生在旧 BFMTactics；状态过渡、规避恢复与战术执行共享独立模块。
	ai.aircraft.flat_altitude = false
	ai.patrol_altitude = 8200.0
	AIAltitudePolicy.set_patrol(ai)
	_check("高度策略：连续巡逻高度", is_equal_approx(ai.aircraft.target_altitude, 8200.0),
		"独立模块接管 patrol profile")
	var altitude_target := _make_enemy()
	altitude_target.altitude = 1000.0
	ai._current_target = altitude_target
	AIAltitudePolicy.use_combat_preference(ai)
	_check("高度策略：作战偏好钳到目标 ±2500m",
		is_equal_approx(ai.aircraft.target_altitude, 3500.0), "保留高度优势但不脱离武器包线")
	AIAltitudePolicy.match_target(ai)
	_check("高度策略：近距直接匹配目标", is_equal_approx(ai.aircraft.target_altitude, 1000.0),
		"机炮战共用入口")
	ai.aircraft.flat_altitude = true
	altitude_target.altitude = 9000.0
	AIAltitudePolicy.match_target(ai)
	_check("高度策略：扁平模式匹配档位",
		ai.aircraft.target_altitude_tier == CombatUnit.AltitudeTier.HIGH, "不写连续高度")
	altitude_target.free()

	_free_ai(ai)


# ── B. EVADE modifier ──
func _test_evade_modifier() -> void:
	print("── B. EVADE modifier：正交模态进出 ──")
	var ai := _make_ai()

	# 背景状态保持
	ai._state = AIController.AIState.SQUAD_FOLLOW
	MissileEvasion.enter_evade(ai)
	_check("enter_evade 置 _evading、不占 _state 轴",
		ai._evading and ai._state == AIController.AIState.SQUAD_FOLLOW,
		"背景状态保持 SQUAD_FOLLOW")

	# 幂等
	ai._evade_committed_dir = Vector2(1, 0)
	MissileEvasion.enter_evade(ai)
	_check("enter_evade 幂等（重复调用不重置 break 方向）",
		ai._evade_committed_dir == Vector2(1, 0),
		"护卫/巡逻分支重复调用安全")

	# 三路重定 · 路线 C：无目标无编队 → PATROL
	ai._current_target = null
	ai.squad = null
	MissileEvasion.exit_evade(ai)
	_check("exit_evade 路线 C：→ PATROL",
		not ai._evading and ai._state == AIController.AIState.PATROL, "")

	# 三路重定 · 路线 A：目标存活 → ENGAGE（软恢复，planner 滞回保留）
	var tgt := _make_enemy()
	ai._current_target = tgt
	var evade_plan := TacticalPlan.new()
	evade_plan.intent = TacticalPlan.Intent.LAG_PURSUIT
	ai.aircraft._last_plan = evade_plan
	ai.aircraft._bfm_prev_intent = TacticalPlan.Intent.LAG_PURSUIT
	MissileEvasion.enter_evade(ai)
	MissileEvasion.exit_evade(ai)
	_check("exit_evade 路线 A：→ ENGAGE + plan 保留",
		ai._state == AIController.AIState.ENGAGE \
		and ai.aircraft._last_plan == evade_plan \
		and ai.aircraft._bfm_prev_intent == TacticalPlan.Intent.LAG_PURSUIT \
		and ai.aircraft.combat_target == tgt,
		"躲弹前的 planner 选择不被打断")

	# 三路重定 · 路线 B：目标已亡 + 有编队 → SQUAD_FOLLOW
	var leader := _make_enemy()
	leader.team = ai.aircraft.team
	var sq := Squad.new()
	sq.leader = leader
	ai.squad = sq
	ai._current_target = null
	MissileEvasion.enter_evade(ai)
	MissileEvasion.exit_evade(ai)
	_check("exit_evade 路线 B：→ SQUAD_FOLLOW",
		ai._state == AIController.AIState.SQUAD_FOLLOW and ai._rejoining,
		"长机存活即归队")

	tgt.free()
	leader.free()
	_free_ai(ai)


# ── C. 约束层 ──
func _test_constraints() -> void:
	print("── C. 约束层：zone + leash 全模态统一 ──")

	# zone 出界 → PATROL 回拉
	var ai := _make_ai()
	var anchor := Node2D.new()
	_root.add_child(anchor)
	anchor.global_position = Vector2(5000, 0)
	ai.combat_zone_anchor = anchor
	ai.combat_zone_radius = 1000.0
	ai.aircraft.global_position = Vector2.ZERO  # 距锚点 5000 > 1000 → 出界
	ai._state = AIController.AIState.ENGAGE
	var handled := ai._apply_constraints(DT)
	_check("zone 出界：约束接管 → PATROL 回拉",
		handled and ai._state == AIController.AIState.PATROL \
		and ai.waypoints.size() == 1 and ai.waypoints[0] == anchor.global_position,
		"waypoint 钉到锚点")
	ai.combat_zone_anchor = null
	ai.combat_zone_radius = 0.0

	# BOSS 释放与 hunter AI tick 不同步：已释放锚点必须在 `is` 判断前净化。
	var freed_anchor := Node2D.new()
	_root.add_child(freed_anchor)
	ai.combat_zone_anchor = freed_anchor
	ai.combat_zone_radius = 1000.0
	freed_anchor.free()
	handled = ai._apply_constraints(DT)
	_check("zone 锚点已释放：安全解除区域约束",
		not handled and ai.combat_zone_anchor == null and is_zero_approx(ai.combat_zone_radius),
		"通关后 hunter AI 不得对 freed BOSS 做类型判断")

	# leash · ENGAGE：越界 + 滞回 → 拽回归队 + 冷却
	var leader := _make_enemy()
	leader.team = ai.aircraft.team
	leader.global_position = Vector2(9000, 0)  # 远超 leash
	var sq := Squad.new()
	sq.leader = leader
	ai.squad = sq
	ai._state = AIController.AIState.ENGAGE
	var tgt := _make_enemy()
	ai._current_target = tgt
	ai.aircraft.set_combat_target(tgt)
	ai._squad_leash_timer = 0.0
	var fired := false
	for i in range(40):  # 40×DT=0.67s > 滞回 0.5s
		if ai._apply_constraints(DT):
			fired = true
			break
	_check("leash·ENGAGE：越界拽回（滞回后触发）",
		fired and ai._state == AIController.AIState.SQUAD_FOLLOW and ai._cooldown_timer >= 3.0,
		"disengage 归队 + 冷却防横跳")

	# leash · ENGAGE + 命令铁律：豁免不拽回
	ai._state = AIController.AIState.ENGAGE
	ai._current_target = tgt
	ai.aircraft.commanded_target = tgt
	ai._squad_leash_timer = 0.0
	fired = false
	for i in range(40):
		if ai._apply_constraints(DT):
			fired = true
			break
	_check("leash·命令豁免：玩家点名不拽回", not fired,
		"玩家要打多远就追多远")
	ai.aircraft.commanded_target = null

	# 僚机不拥有 commanded_target，但跟打长机点名目标时继承命令优先级。
	ai._state = AIController.AIState.ENGAGE
	ai._current_target = tgt
	ai.aircraft.set_combat_target(tgt)
	ai._squad_attacking_leader_target = true
	leader.set_combat_target(tgt)
	leader.commanded_target = tgt
	ai._squad_leash_timer = 0.0
	fired = false
	for i in range(40):
		if ai._apply_constraints(DT):
			fired = true
			break
	_check("leash·跟打命令豁免：归队不覆盖玩家点名", not fired and ai._cmd_engage_active(),
		"僚机跟打长机点名目标时继续攻击")

	# 长机取消点名后，继承优先级立即消失，普通 leash 恢复生效。
	leader.commanded_target = null
	ai._squad_leash_timer = 0.0
	fired = false
	for i in range(40):
		if ai._apply_constraints(DT):
			fired = true
			break
	_check("leash·长机取消命令：恢复归队", fired and not ai._cmd_engage_active(),
		"取消点名后不再豁免 leash")

	# leash · EVADE：躲弹同样被拽回（SEAM-010 根治核心）+ 再入冷却
	ai._state = AIController.AIState.SQUAD_FOLLOW
	ai._evading = true
	ai._evade_reenter_cd = 0.0
	ai._squad_leash_timer = 0.0
	fired = false
	for i in range(40):
		if ai._apply_constraints(DT):
			fired = true
			break
	_check("leash·EVADE：躲弹越界同样拽回",
		fired and not ai._evading and ai._evade_reenter_cd > 0.0,
		"exit_evade + 再入冷却（防 EVADE↔SQUAD_FOLLOW 振荡）")

	# leash · 界内不触发
	ai.aircraft.global_position = leader.global_position + Vector2(300, 0)
	ai._state = AIController.AIState.ENGAGE
	ai._current_target = tgt
	ai._squad_leash_timer = 0.0
	fired = false
	for i in range(40):
		if ai._apply_constraints(DT):
			fired = true
			break
	_check("leash·界内：不触发", not fired, "300px < leash")

	anchor.free()
	tgt.free()
	leader.free()
	_free_ai(ai)


# ── 工具 ──

func _make_ai() -> AIController:
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	ac.global_position = Vector2.ZERO
	ac.heading = 0.0
	ac.speed = 250.0
	ac.team = 0
	var p := AircraftParams.new()
	ac.params = p
	_root.add_child(ac)
	var ai: AIController = load("res://scripts/ai_controller.gd").new()
	ai.aircraft = ac
	ac._ai_ref = ai
	ac.add_child(ai)
	return ai


func _make_enemy() -> Aircraft:
	var t: Aircraft = load("res://scripts/aircraft.gd").new()
	t.global_position = Vector2(2000, -2000)
	t.heading = 0.0
	t.speed = 250.0
	t.team = 1
	t.params = AircraftParams.new()
	_root.add_child(t)
	return t


func _free_ai(ai: AIController) -> void:
	var ac: Aircraft = ai.aircraft
	_root.remove_child(ac)
	ac.free()


func _check(name: String, ok: bool, note: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s — %s" % [name, note])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [name, note])
