class_name TargetSelection
extends RefCounted

## 目标选择 / 交战生命周期子系统（静态工具类）
## 从 ai_controller.gd 提取的三个阶段：
##   try_engage        — 进入交战：雷达扫描 + 打分 + 锁定优先 + 粘性阈值
##   reevaluate_target — 交战中换目标（受 focus 影响）
##   disengage         — 退出 ENGAGE：BOSS 重入 / 僚机归队 / 巡逻返回
##
## 状态仍住在 AIController。本模块不持有状态，只在 ai 上读写。
##
## 枚举/常量引用保留在 AIController：
##   AIController.AIState / AIController.EngageTactic / AIController.MIN_DUR_LEAD_PURSUIT
##
## 注意：_try_engage_in_tether_range 与 _try_engage_simple 是 simple_ai 路径，
## 仍保留在 AIController，未提取。

# ══════════════════════════════════════════════
#  进入交战（雷达扫描 + 打分）
# ══════════════════════════════════════════════

static func try_engage(ai) -> void:
	if ai._cooldown_timer > 0.0:
		return

	var best_target: CombatUnit = null
	var best_score := -1.0
	var current_target_score := -1.0

	for target_key in ai.aircraft.radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_ac: CombatUnit = target_key
		if target_ac.is_destroyed or target_ac.team == ai.aircraft.team:
			continue

		var lock_progress: float = ai.aircraft.radar_targets[target_key]
		var lock_time: float = ai.aircraft.params.lock_time if ai.aircraft.params else 3.0

		var dist := ai.aircraft.global_position.distance_to(target_ac.global_position)
		var dist_score := 1.0 / maxf(dist, 100.0) * 1000.0
		var lock_score := lock_progress / lock_time
		var score := lock_score * 2.0 + dist_score

		# 低空目标攻击欲望降低
		var tgt_tier := target_ac.get_altitude_tier()
		if tgt_tier == CombatUnit.AltitudeTier.LOW:
			score *= 0.65
		elif tgt_tier == CombatUnit.AltitudeTier.GROUND:
			score *= 0.5

		# 云中目标（HIGH + 在云内）同样降低攻击欲望：视觉遮蔽 + 追踪困难
		if target_ac.cloud_state == 2:
			score *= 0.6

		# 偏好高度加成
		if ai.preferred_altitude_tier != -99 and tgt_tier == ai.preferred_altitude_tier:
			score *= 1.3

		# 目标粘性：当前目标获得专注度加成
		if target_ac == ai._current_target:
			score += ai.focus * 5.0
			current_target_score = score

		var min_lock_ratio := lerpf(1.0, 0.3, ai.aggression)
		if lock_score < min_lock_ratio:
			continue

		if score > best_score:
			best_score = score
			best_target = target_ac

	if best_target:
		# 切换目标需要超越当前目标的粘性阈值
		if ai._current_target and is_instance_valid(ai._current_target) and not ai._current_target.is_destroyed:
			if best_target != ai._current_target and current_target_score > 0.0:
				var switch_threshold := ai.focus * 2.0
				if best_score < current_target_score + switch_threshold:
					return  # 新目标不够优，维持当前目标

		var prev_state := ai._state
		ai._current_target = best_target
		ai.aircraft.set_combat_target(best_target)
		ai._state = AIController.AIState.ENGAGE
		ai._engage_timer = 0.0
		ai._tactic = AIController.EngageTactic.LEAD_PURSUIT
		ai._tactic_timer = 0.0
		ai._tactic_min_duration = AIController.MIN_DUR_LEAD_PURSUIT
		ai._target_eval_timer = 0.0
		ai.aircraft.ai_override_pursuit = true
		ai._squad_attacking_leader_target = false  # 独立交战
		ai._squad_free_engaging = false
		var dist_m := ai.aircraft.global_position.distance_to(best_target.global_position) / CombatUnit.PIXELS_PER_METER
		EventLogger.log_event("AI_STATE", ai._log_name(),
			"%s → ENGAGE (target=%s, dist=%.0fm, score=%.2f)" % [
				AIController.AIState.keys()[prev_state], ai._log_target_name(best_target), dist_m, best_score])

## 交战中重评估目标（受 focus 影响）
static func reevaluate_target(ai) -> void:
	var best_target: CombatUnit = null
	var best_score := -1.0
	var current_score := -1.0

	for target_key in ai.aircraft.radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_ac: CombatUnit = target_key
		if target_ac.is_destroyed or target_ac.team == ai.aircraft.team:
			continue

		var lock_progress: float = ai.aircraft.radar_targets[target_key]
		var lock_time: float = ai.aircraft.params.lock_time if ai.aircraft.params else 3.0

		var dist := ai.aircraft.global_position.distance_to(target_ac.global_position)
		var dist_score := 1.0 / maxf(dist, 100.0) * 1000.0
		var lock_score := lock_progress / lock_time
		var score := lock_score * 2.0 + dist_score

		# 当前目标获得专注度粘性加成
		if target_ac == ai._current_target:
			score += ai.focus * 5.0
			current_score = score

		if score > best_score:
			best_score = score
			best_target = target_ac

	if not best_target or best_target == ai._current_target:
		return

	# 必须显著优于当前目标才切换
	var switch_threshold := ai.focus * 3.0
	if current_score > 0.0 and best_score < current_score + switch_threshold:
		return

	# 切换目标
	var old_target := ai._current_target
	ai._current_target = best_target
	ai.aircraft.set_combat_target(best_target)
	ai._tactic_timer = 0.0
	ai._yoyo_phase = 0
	EventLogger.log_event("TARGET", ai._log_name(),
		"switched target: %s → %s (old_score=%.2f, new_score=%.2f)" % [
			ai._log_target_name(old_target), ai._log_target_name(best_target),
			current_score, best_score])

static func disengage(ai) -> void:
	EventLogger.log_event("AI_STATE", ai._log_name(),
		"DISENGAGE (was fighting %s, engaged %.1fs)" % [
			ai._log_target_name(ai._current_target), ai._engage_timer])

	# ── BOSS 攻击手：不真正脱离，立即重新进入交战 ──
	if ai.is_boss_attacker():
		# 即使 _current_target 丢失也不脱离——重新锁定玩家
		var player: Aircraft = null
		if ai._current_target and is_instance_valid(ai._current_target) and not ai._current_target.is_destroyed:
			player = ai._current_target as Aircraft
		else:
			# 搜索玩家（team 0 的飞机）
			for child in ai.aircraft.get_parent().get_children():
				if child is Aircraft and child.team == 0 and not child.is_destroyed:
					player = child
					break
		if player:
			ai._current_target = player
			ai.aircraft.combat_target = player
			ai._engage_timer = 0.0
			ai._cooldown_timer = 0.0
			ai._tactic_timer = 0.0
			ai._tactic_min_duration = 0.0
			BFMTactics.apply_new_tactic(ai, AIController.EngageTactic.LEAD_PURSUIT)
			EventLogger.log_event("AI_STATE", ai._log_name(), "BOSS re-engage immediately")
			return

	ai.aircraft.clear_combat_target()
	ai.aircraft.ai_override_pursuit = false
	ai.aircraft.keep_target_on_arrival = false
	ai._current_target = null
	ai._cooldown_timer = ai.engage_cooldown
	ai.current_tactic_name = ""
	ai._squad_attacking_leader_target = false
	ai._squad_free_engaging = false
	ai._leader_target_lost_timer = 0.0
	ai._squad_range_grace_timer = 0.0
	# 有编队且长机不是自己 → 回归编队；否则（独行或自己就是长机）回巡逻
	# bvr_only（F-47 逃跑手）不进编队跟随——走巡逻执行逃跑航点
	# 不能让单机长机/新晋升长机进 SQUAD_FOLLOW，否则会对着自己算槽位原地自转
	if not ai.bvr_only and ai.squad and is_instance_valid(ai.squad.leader) and not ai.squad.leader.is_destroyed \
			and ai.squad.leader != ai.aircraft:
		ai._state = AIController.AIState.SQUAD_FOLLOW
		ai._cover_target = null
		ai._rejoining = true
		ai._formation_blend = 0.0  # 从0开始渐变回编队托管
		ai.aircraft.lod_level = 1
	else:
		# 独自存活的长机走巡逻，顺便把 squad_index 归零（以防 squad 尚在但已是孤雁）
		if ai.squad and ai.squad.leader == ai.aircraft:
			ai.squad_index = 0
		ai.aircraft.formation_mode = false
		ai.aircraft._formation_leader = null
		ai._state = AIController.AIState.PATROL
		BFMTactics.set_patrol_altitude(ai)
		ai._set_next_waypoint()
