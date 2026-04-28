class_name MissileEvasion
extends RefCounted

## 导弹规避子系统（静态工具类）
## 从 ai_controller.gd 提取的 EVADE_MISSILE 状态逻辑：
##   process_evade            — EVADE 主循环：垂直规避 + Herbst 机动触发 + 高度档位切换
##   enter_evade / exit_evade — 状态转入/转出（退出编队托管 / 重入交战 / 归队 / 返回巡逻）
##   check_incoming_missile   — 是否有来袭导弹
##   find_nearest_incoming_missile — 扫描最近来袭导弹（过滤热诱弹干扰 / 已过头导弹）
##   is_missile_from_rear     — 后半球来袭判定（用于眼镜蛇触发）
##
## 状态仍住在 AIController。本模块不持有状态，只在 ai 上读写。
##
## 枚举/常量引用保留在 AIController：
##   AIController.AIState / AIController.MANEUVER_ACTIVATE_DIST /
##   AIController.EVADE_FLIGHT_DIST / AIController.EVADE_TURN_DIST /
##   AIController.EVADE_ALT_CHANGE / AIController.EVADE_ALT_THRESH
##
## 注意：_get_missile_manager 是通用场景图辅助，仍保留在 AIController。

# ══════════════════════════════════════════════
#  EVADE_MISSILE — 导弹规避（保持原有逻辑）
# ══════════════════════════════════════════════

static func process_evade(ai: AIController, delta: float) -> void:
	var missile := find_nearest_incoming_missile(ai)
	if not missile:
		exit_evade(ai)
		return

	# ── 战术机动：后方来袭导弹逼近时一次性触发 ──
	var _mev := ai.aircraft.get_maneuver()
	if _mev and not _mev.is_used and not _mev.is_active:
		var missile_dist := missile.global_position.distance_to(ai.aircraft.global_position)
		if missile_dist < AIController.MANEUVER_ACTIVATE_DIST and is_missile_from_rear(ai, missile):
			_mev.activate()
			var fwd := Vector2(sin(ai.aircraft.heading), -cos(ai.aircraft.heading))
			ai.aircraft.target_position = ai.aircraft.global_position + fwd * AIController.EVADE_FLIGHT_DIST
			return
	# 战术机动执行中：保持航向等待完成
	if _mev and _mev.is_active:
		var fwd := Vector2(sin(ai.aircraft.heading), -cos(ai.aircraft.heading))
		ai.aircraft.target_position = ai.aircraft.global_position + fwd * AIController.EVADE_FLIGHT_DIST
		return

	var missile_dir := (ai.aircraft.global_position - missile.global_position).normalized()
	var evade_dir := Vector2(missile_dir.y, -missile_dir.x)

	var evade_heading_a := atan2(evade_dir.x, -evade_dir.y)
	var evade_heading_b := atan2(-evade_dir.x, evade_dir.y)
	var diff_a := absf(AIController._angle_diff(evade_heading_a, ai.aircraft.heading))
	var diff_b := absf(AIController._angle_diff(evade_heading_b, ai.aircraft.heading))
	var chosen_dir := evade_dir if diff_a < diff_b else -evade_dir

	ai._evade_target_pos = ai.aircraft.global_position + chosen_dir * AIController.EVADE_TURN_DIST
	ai.aircraft.target_position = ai._evade_target_pos

	if ai.aircraft.combat_target:
		ai.aircraft.clear_combat_target()

	if ai.aircraft.flat_altitude:
		# 扁平模式：规避时切换档位（低→中/高，高→中/低）
		if ai.aircraft.get_altitude_tier() == Aircraft.AltitudeTier.LOW:
			ai.aircraft.set_target_tier(Aircraft.AltitudeTier.HIGH)
		else:
			ai.aircraft.set_target_tier(Aircraft.AltitudeTier.LOW)
	else:
		var alt_change := AIController.EVADE_ALT_CHANGE if ai.aircraft.altitude < AIController.EVADE_ALT_THRESH else -AIController.EVADE_ALT_CHANGE
		ai.aircraft.target_altitude = ai.aircraft.altitude + alt_change

static func enter_evade(ai: AIController) -> void:
	EventLogger.log_event("EVADE", ai._log_name(),
		"entering missile evasion (was %s, target=%s)" % [
			AIController.AIState.keys()[ai._state], ai._log_target_name(ai._current_target)])
	ai._state = AIController.AIState.EVADE_MISSILE
	ai.aircraft.ai_override_pursuit = false
	# P4：planner 模式下置 evasion_mode → planner 选 EVADE_MISSILE intent → max + AB
	# MissileEvasion.process_evade 仍写 target_position（垂直规避向量），两者协作：
	# planner 决定速度/AB，process_evade 决定方向/高度
	if ai.aircraft.use_tactical_planner:
		ai.aircraft.evasion_mode = true
	ai._squad_attacking_leader_target = false
	ai._squad_free_engaging = false
	if ai.aircraft.combat_target:
		ai.aircraft.clear_combat_target()
	# 退出编队托管，规避机动必须走正常飞行物理（LOD 0）
	# 否则 lod_level==1 + formation_mode 会让规避航向变化走
	# aircraft.gd:261 的纯 lerp_angle 分支，绕过 G 限/bank 速率/corner speed，
	# 导致 ~360°/s 的瞬间机头扭转（见 2026-04-11 Jinx 规避 bug）。
	ai.aircraft.formation_mode = false
	ai.aircraft._formation_leader = null
	ai.aircraft._formation_blend = 0.0
	ai._formation_blend = 0.0  # 规避结束后从 0 开始重新融入编队
	ai.aircraft.lod_level = 0
	ai.aircraft.keep_target_on_arrival = false

static func exit_evade(ai: AIController) -> void:
	EventLogger.log_event("EVADE", ai._log_name(), "exiting missile evasion")
	# P4：清 evasion_mode 让 planner 回到正常 intent 路径
	if ai.aircraft.use_tactical_planner:
		ai.aircraft.evasion_mode = false
	if ai._current_target and is_instance_valid(ai._current_target) and not ai._current_target.is_destroyed:
		ai.aircraft.set_combat_target(ai._current_target)
		BFMTactics.set_patrol_altitude(ai)
		ai._state = AIController.AIState.ENGAGE
		ai._tactic_timer = 0.0
	elif ai.squad and is_instance_valid(ai.squad.leader) and not ai.squad.leader.is_destroyed:
		ai._state = AIController.AIState.SQUAD_FOLLOW
		ai._cover_target = null
		ai._rejoining = true
		ai._formation_blend = 0.0  # 从0开始渐变回编队托管
		ai.aircraft.clear_combat_target()
		ai.aircraft.ai_override_pursuit = false
		ai.aircraft.lod_level = 1
	else:
		ai._current_target = null
		ai._state = AIController.AIState.PATROL
		BFMTactics.set_patrol_altitude(ai)
		ai.aircraft.ai_override_pursuit = false
		ai._set_next_waypoint()

# ══════════════════════════════════════════════
#  导弹威胁检测
# ══════════════════════════════════════════════

static func check_incoming_missile(ai: AIController) -> bool:
	return find_nearest_incoming_missile(ai) != null

static func find_nearest_incoming_missile(ai: AIController) -> Missile:
	var missile_manager := ai._get_missile_manager()
	if not missile_manager:
		return null

	var nearest: Missile = null
	var nearest_dist := 99999.0

	for child in missile_manager.get_children():
		if not child is Missile:
			continue
		var m: Missile = child
		if not m.is_active:
			continue
		if m.target != ai.aircraft:
			continue
		if m.is_flare_jammed:
			continue  # 已被热诱弹干扰，不再构成威胁
		# 过滤"已经飞过头、正在远离"的导弹——否则僚机做完第一次横滚规避后，
		# 还未失效的过头导弹会让 missile_aware 一直为 true，AI 反复 _enter_evade
		# 持续横滚脱队，直到导弹燃料/寿命耗尽（几十秒）才恢复，表现为"发呆平飞+飞离很远"。
		var to_ac := ai.aircraft.global_position - m.global_position
		var m_fwd := Vector2(sin(m.heading), -cos(m.heading))
		if to_ac.length() > 1.0 and m_fwd.dot(to_ac.normalized()) < -0.2:
			continue
		var dist := to_ac.length()
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = m

	return nearest

## 判断导弹是否从后半球逼近（用于眼镜蛇触发）
## 同时检查两个条件：
##   1. 导弹在飞机后方（位置判定）
##   2. 导弹正朝飞机飞来（速度方向判定，排除已飞过的导弹）
static func is_missile_from_rear(ai: AIController, missile: Missile) -> bool:
	var missile_to_ac := (ai.aircraft.global_position - missile.global_position).normalized()
	var ac_fwd := Vector2(sin(ai.aircraft.heading), -cos(ai.aircraft.heading))
	# 条件 1：导弹在飞机后方锥内
	if ac_fwd.dot(missile_to_ac) <= 0.3:
		return false
	# 条件 2：导弹的飞行方向朝向飞机（而非已经飞过去了）
	var missile_fwd := Vector2(sin(missile.heading), -cos(missile.heading))
	return missile_fwd.dot(missile_to_ac) > 0.3
