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

## 散开规避（无来袭导弹时的退路：玩家长机传播 evasion_mode 给僚机时使用）
## 每 SCATTER_REFRESH 秒重选一个方向，方向偏向地图中心 + 个体扰动，避免飞出边界
const SCATTER_REFRESH := 1.5      ## 方向刷新周期（秒）
const SCATTER_TURN_DIST := 1500.0 ## 散开目标点距离（像素）
const SCATTER_EDGE_MARGIN := 1000.0 ## 距边界 < 此值时强制朝中心（像素）
static func _process_scatter_evade(ai: AIController, delta: float) -> void:
	# 个体扰动相位（每架僚机不同 → 方向各异）
	ai._scatter_evade_timer -= delta
	if ai._scatter_evade_timer <= 0.0:
		ai._scatter_evade_timer = SCATTER_REFRESH + randf_range(-0.3, 0.3)
		# 默认方向：基于 squad_index 的固定 60-150° 散开扇形（每个僚机方向不同）
		var base_angle := ai.aircraft.heading + deg_to_rad(60.0 + ai.squad_index * 35.0)
		base_angle += randf_range(-0.4, 0.4)  # 随机扰动 ~±23°
		var dir := Vector2(sin(base_angle), -cos(base_angle))
		# 边界偏移：距边界 < SCATTER_EDGE_MARGIN 时把方向偏向地图中心
		var edge_dist := MapBoundary.distance_to_edge(ai.aircraft.global_position)
		if edge_dist < SCATTER_EDGE_MARGIN:
			var to_center: Vector2 = -ai.aircraft.global_position.normalized()
			# 边缘越近，越接近纯指向中心；EDGE_MARGIN 处 0% center，0 处 100% center
			var center_weight: float = clampf(1.0 - edge_dist / SCATTER_EDGE_MARGIN, 0.0, 1.0)
			dir = dir.lerp(to_center, center_weight).normalized()
		ai._evade_target_pos = ai.aircraft.global_position + dir * SCATTER_TURN_DIST
		# 安全网：clamp 到地图内部至少 500m，防止 target 本身越界
		ai._evade_target_pos = MapBoundary.clamp_inside(ai._evade_target_pos, 500.0)
		# 同步刷新时切换高度档（每 ~1.5s 一次，不每帧抖动）
		if ai.aircraft.flat_altitude:
			if ai.aircraft.get_altitude_tier() == Aircraft.AltitudeTier.LOW:
				ai.aircraft.set_target_tier(Aircraft.AltitudeTier.HIGH)
			else:
				ai.aircraft.set_target_tier(Aircraft.AltitudeTier.LOW)
	ai.aircraft.target_position = ai._evade_target_pos
	if ai.aircraft.combat_target:
		ai.aircraft.clear_combat_target()

static func process_evade(ai: AIController, delta: float) -> void:
	var missile := find_nearest_incoming_missile(ai)
	if not missile:
		# 僚机 + 长机 evasion 仍开 → 持续散开规避（不退出）
		# 旁路：长机 / 单机 evasion_mode 由其他系统驱动，这里只覆盖僚机散开场景
		if ai.aircraft.evasion_mode and ai.squad and is_instance_valid(ai.squad.leader) \
				and ai.squad.leader != ai.aircraft:
			_process_scatter_evade(ai, delta)
			return
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
	ai._squad_lateral_role = AIController.SquadRole.NONE
	ai._squad_free_engaging = false
	ai._scatter_evade_timer = 0.0  # 散开模式下保证首帧重选方向
	if ai.aircraft.combat_target:
		ai.aircraft.clear_combat_target()
	# 退出编队托管，规避机动必须走正常飞行物理（LOD 0）
	# 否则 lod_level==1 + formation_mode 会让规避航向变化走
	# aircraft.gd:261 的纯 lerp_angle 分支，绕过 G 限/bank 速率/corner speed，
	# 导致 ~360°/s 的瞬间机头扭转（见 2026-04-11 Jinx 规避 bug）。
	ai.aircraft.clear_formation()
	ai._formation_blend = 0.0  # 规避结束后从 0 开始重新融入编队

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
