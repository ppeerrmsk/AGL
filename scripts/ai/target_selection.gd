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
##
## 评分哲学（spec target-engageability-selection）：选"现在最能干净命中"的目标，
## 而非"最近"。base ∈ [0,1] 由四因子加权（对正/包络/锁定封顶/邻近），再叠修饰倍率与
## 护卫/守后绝对加分。护卫/守后加分量级远大于 base → 威胁目标主导；无威胁时 base 独立决定。

# ── 可命中性四因子权重（和=1.0 → base∈[0,1]）──
const W_ALIGN := 0.45   ## 对正度：目标离机头多少度（与发射门同源）
const W_ENV   := 0.30   ## 导弹包络内
const W_LOCK  := 0.15   ## 已锁定（封顶 0/1，杜绝 runaway）
const W_PROX  := 0.10   ## 邻近（仅 tiebreaker）
# ── 修饰 ──
const OVERKILL_MULT := 0.10        ## 队友已发足量弹（必死）→ 让路，避免超杀浪费
const PREFERRED_ALT_MULT := 1.3    ## 命中偏好高度档
const STICKY_BONUS := 0.10         ## 当前目标专注度粘性（替代旧 focus*5，适配 [0,1] 尺度）
const REAR_GUARD_PRIORITY := 100.0 ## 守后语境：后方威胁主导加分（远大于 base，与 escort 同加性尺度）
# ── 切换迟滞（防抖；base[0,1] 尺度）──
const SWITCH_MARGIN_ENTER := 0.12  ## try_engage 换目标门槛
const SWITCH_MARGIN_REEVAL := 0.18 ## reevaluate 交战中更黏

# ══════════════════════════════════════════════
#  进入交战（雷达扫描 + 打分）
# ══════════════════════════════════════════════

static func try_engage(ai: AIController) -> void:
	if ai._cooldown_timer > 0.0:
		return

	var best_target: CombatUnit = null
	var best_score := -1.0
	var current_target_score := -1.0
	# 护卫编队僚机：候选叠加"咬长机/近长机"加权；非护卫 → null，评分不变
	var escort_leader: Aircraft = ai.squad.leader if SquadCoordination.is_escort_wingman(ai) else null
	var guard_ctx := _is_guard_rear_context(ai)

	for target_key in ai.aircraft.radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_ac: CombatUnit = target_key
		if target_ac.is_destroyed or not ai.aircraft.is_hostile_to(target_ac):
			continue

		var score := _score_candidate(ai, target_ac, escort_leader, guard_ctx)
		if score < 0.0:
			continue  # 未过最低锁定门

		# 目标粘性：当前目标获得专注度加成（生存带用 SURVIVAL_STICKY 防带内横跳，§2.1.3）
		if target_ac == ai._current_target:
			score += _sticky_for(ai)
			current_target_score = score

		if score > best_score:
			best_score = score
			best_target = target_ac

	if best_target:
		# §2.1.1 交战地板（spec battlefield-gravity）：最佳候选也不值得打 → 不进战。
		# 引力只压分，argmax 仍会选出唯一的远杂鱼——地板才是"留在编队/巡逻贴着锚"的机制。
		# survival(≥60)/objective(≥40) 恒过地板，天然豁免。仅玩家小队生效。
		if ObjectiveContext.enabled and ai.aircraft.is_player_squad() \
				and best_score < ObjectiveContext.ENGAGE_MIN_SCORE:
			return
		# 切换目标需要超越当前目标的粘性阈值
		if ai._current_target and is_instance_valid(ai._current_target) and not ai._current_target.is_destroyed:
			if best_target != ai._current_target and current_target_score > 0.0:
				if best_score < current_target_score + SWITCH_MARGIN_ENTER:
					return  # 新目标不够优，维持当前目标

		var prev_state := ai._state
		if not ai.acquire_target(best_target, AIController.TargetSource.TS_SCORED, "try_engage"):
			return  # 目标被更高优先级来源持有 → 放弃本次评分交战
		ai.enter_engage_state()
		ai._target_eval_timer = 0.0
		ai.aircraft.ai_override_pursuit = true
		ai._squad_attacking_leader_target = false  # 独立交战
		ai._squad_lateral_role = AIController.SquadRole.NONE
		ai._squad_free_engaging = false
		var dist_m := ai.aircraft.global_position.distance_to(best_target.global_position) / CombatUnit.PIXELS_PER_METER
		EventLogger.log_event("AI_STATE", ai._log_name(),
			"%s → ENGAGE (target=%s, dist=%.0fm, score=%.2f)" % [
				AIController.AIState.keys()[prev_state], ai._log_target_name(best_target), dist_m, best_score])

## 交战中重评估目标（受 focus 影响）
static func reevaluate_target(ai: AIController) -> void:
	var best_target: CombatUnit = null
	var best_score := -1.0
	var current_score := -1.0
	# 护卫编队僚机：交战中重评估也吃护卫加权——新出现的"咬长机者"能抢回护卫优先级
	var escort_leader: Aircraft = ai.squad.leader if SquadCoordination.is_escort_wingman(ai) else null
	var guard_ctx := _is_guard_rear_context(ai)

	for target_key in ai.aircraft.radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_ac: CombatUnit = target_key
		if target_ac.is_destroyed or not ai.aircraft.is_hostile_to(target_ac):
			continue

		var score := _score_candidate(ai, target_ac, escort_leader, guard_ctx)
		if score < 0.0:
			continue  # 未过最低锁定门

		# 当前目标获得专注度粘性加成（生存带用 SURVIVAL_STICKY 防带内横跳，§2.1.3）
		if target_ac == ai._current_target:
			score += _sticky_for(ai)
			current_score = score

		if score > best_score:
			best_score = score
			best_target = target_ac

	# §2.1.1 地板脱离（spec battlefield-gravity，reevaluate 侧）：顺手目标已不值得打
	# （远离战场/引力压穿地板）连续 2 次评估 → 主动脱离归队，治"存量僚机挂在远杂鱼上"。
	# survival/objective 候选分 ≥40，数值上永不触发（无需显式豁免）；只动 TS_SCORED 自主目标。
	if ObjectiveContext.enabled and ai.aircraft.is_player_squad() \
			and ai._target_source == AIController.TargetSource.TS_SCORED \
			and current_score > 0.0 \
			and current_score < ObjectiveContext.ENGAGE_MIN_SCORE + _sticky_for(ai):
		ai._gravity_low_evals += 1
		if ai._gravity_low_evals >= 2:
			ai._gravity_low_evals = 0
			disengage(ai)
			return
	else:
		ai._gravity_low_evals = 0

	if not best_target or best_target == ai._current_target:
		return

	# 必须显著优于当前目标才切换（交战中更黏，防横跳）
	if current_score > 0.0 and best_score < current_score + SWITCH_MARGIN_REEVAL:
		return

	# 切换目标
	var old_target := ai._current_target
	if not ai.acquire_target(best_target, AIController.TargetSource.TS_SCORED, "reevaluate switch"):
		return  # 目标被更高优先级来源持有 → 维持原目标
	ai._tactic_timer = 0.0
	ai._yoyo_phase = 0
	EventLogger.log_event("TARGET", ai._log_name(),
		"switched target: %s → %s (old_score=%.2f, new_score=%.2f)" % [
			ai._log_target_name(old_target), ai._log_target_name(best_target),
			current_score, best_score])

static func disengage(ai: AIController) -> void:
	# ── BOSS 攻击手：不真正脱离，重新锁定玩家 ──
	# 【关键】只重置 _engage_timer + _cooldown_timer 防止下一帧又触发 disengage；
	# 绝不动 _tactic_timer / _tactic_min_duration / 当前 tactic ——
	# 让正在跑的 BFM 战术自然完成最小持续时间（否则每帧重置 → BOSS 决策瘫痪）
	if ai.is_boss_attacker():
		var player: Aircraft = null
		# is_lock_immune()（光学隐形 / 锁定免疫）→ 不可再锁，走下面的扫描；扫描同样过滤，
		# 全场无可锁玩家机时 player 保持 null → 落到正常 disengage（spec ace-squadron-tier §3.5）
		if ai._current_target and is_instance_valid(ai._current_target) \
				and not ai._current_target.is_destroyed and not ai._current_target.is_lock_immune():
			player = ai._current_target as Aircraft
		else:
			# 用共享列表代替 get_parent().get_children() (perf)
			for unit in CombatUnit.all_units:
				# `unit` truthy 仍可能是 freed 实例 → is_instance_valid 守卫（perf R4）
				if not is_instance_valid(unit):
					continue
				if unit is Aircraft and unit.is_player_squad() and not unit.is_destroyed \
						and not unit.is_lock_immune():
					player = unit as Aircraft
					break
		if player and ai.acquire_target(player, AIController.TargetSource.TS_SCORED, "boss re-engage"):
			ai._engage_timer = 0.0
			ai._cooldown_timer = 0.0
			EventLogger.log_event("AI_STATE", ai._log_name(), "BOSS re-engage immediately")
			return

	# 先记快照再 release（release 后 _current_target 已清）；被高优先级拒绝 → 保持交战不脱离
	var _was_fighting: String = ai._log_target_name(ai._current_target)
	var _engaged_secs: float = ai._engage_timer
	if not ai.release_target(AIController.TargetSource.TS_SCORED, "disengage"):
		return
	EventLogger.log_event("AI_STATE", ai._log_name(),
		"DISENGAGE (was fighting %s, engaged %.1fs)" % [_was_fighting, _engaged_secs])
	ai.aircraft.ai_override_pursuit = false
	ai.aircraft.keep_target_on_arrival = false
	ai._cooldown_timer = ai.engage_cooldown
	ai._gravity_low_evals = 0  # 地板脱离计数复位（spec battlefield-gravity §2.1.1）
	ai.current_tactic_name = ""
	ai._squad_attacking_leader_target = false
	ai._squad_lateral_role = AIController.SquadRole.NONE
	ai._squad_free_engaging = false
	ai._leader_target_lost_timer = 0.0
	ai._squad_range_grace_timer = 0.0
	# 有编队且长机不是自己 → 回归编队；否则（独行或自己就是长机）回巡逻
	# bvr_only（F-47 逃跑手）不进编队跟随——走巡逻执行逃跑航点
	# 不能让单机长机/新晋升长机进 SQUAD_FOLLOW，否则会对着自己算槽位原地自转
	if not ai.bvr_only and ai.squad and is_instance_valid(ai.squad.leader) and not ai.squad.leader.is_destroyed \
			and ai.squad.leader != ai.aircraft:
		ai.enter_squad_follow_state()
	else:
		# 独自存活的长机走巡逻，顺便把 squad_index 归零（以防 squad 尚在但已是孤雁）
		if ai.squad and ai.squad.leader == ai.aircraft:
			ai.squad_index = 0
		ai.aircraft.clear_formation()
		ai.enter_patrol_state()

# ══════════════════════════════════════════════
#  可命中性评分（try_engage / reevaluate 共用，杜绝两份公式漂移）
# ══════════════════════════════════════════════

## 带感知粘性（spec battlefield-gravity §2.1.3）：当前目标是生存候选 → SURVIVAL_STICKY(8.0)。
## threat01 随距离连续变化（Δ300px≈4 分），base 尺度的 0.10/0.18 在 60~100 带内形同虚设，
## 无此滞回则防守僚机在两个追击者间每秒横跳、_tactic_timer 狂重置。
## objective 带刻意不加：+40 是常数，带内分差回落 base 尺度 → 现有阈值继续管用（设计的不对称）。
static func _sticky_for(ai: AIController) -> float:
	if ObjectiveContext.enabled and ai.aircraft.is_player_squad() \
			and ObjectiveContext.is_survival_threat(ai._current_target):
		return ObjectiveContext.SURVIVAL_STICKY
	return STICKY_BONUS

## 单个候选打分：返回 score（base + 修饰 + 加分），或 -1.0 表示未过最低锁定门。
## 不含粘性加成（STICKY_BONUS 由调用方在 target == current 时加）。
static func _score_candidate(ai: AIController, target_ac: CombatUnit,
		escort_leader: Aircraft, guard_ctx: bool) -> float:
	var lock_progress: float = ai.aircraft.radar_targets.get(target_ac, 0.0)
	var lock_time: float = ai.aircraft.params.lock_time if ai.aircraft.params else 3.0
	var lock01 := clampf(lock_progress / maxf(lock_time, 0.01), 0.0, 1.0)
	# 最低锁定门：高攻击性放宽到 30% 即可参选
	if lock01 < lerpf(1.0, 0.3, ai.aggression):
		return -1.0

	var dist_m := ai.aircraft.global_position.distance_to(target_ac.global_position) / CombatUnit.PIXELS_PER_METER

	# 对正度：目标离机头多少度（与发射门同源 atan2）
	var to_tgt: Vector2 = target_ac.global_position - ai.aircraft.global_position
	var hdg_to_tgt := atan2(to_tgt.x, -to_tgt.y)
	var off_axis_deg := absf(rad_to_deg(ai.aircraft._angle_diff(hdg_to_tgt, ai.aircraft.heading)))
	var radar_half: float = ai.aircraft.params.radar_half_angle if ai.aircraft.params else 30.0
	var align01 := clampf(1.0 - off_axis_deg / maxf(radar_half, 1.0), 0.0, 1.0)

	# 包络 + 邻近
	var env01 := _envelope_factor(ai.aircraft, target_ac, dist_m)
	var msl: MissileParams = ai.aircraft.params.missile if ai.aircraft.params else null
	var max_r: float = msl.max_range_rear if msl else 8000.0
	var prox01 := clampf(1.0 - dist_m / maxf(max_r, 1.0), 0.0, 1.0)

	var score := W_ALIGN * align01 + W_ENV * env01 + W_LOCK * lock01 + W_PROX * prox01

	# 视觉遮蔽（低空 / 云中）
	score *= _visibility_score_mult(target_ac)

	# 队友超杀让路：已发足量弹（含在途）→ 强降权
	var mm := ai.aircraft.missile_manager
	if mm and is_instance_valid(mm):
		if mm.team_inbound_damage(target_ac, ai.aircraft.team, ai.aircraft) >= target_ac.hp:
			score *= OVERKILL_MULT

	# 偏好高度
	if ai.preferred_altitude_tier != -99 and target_ac.get_altitude_tier() == ai.preferred_altitude_tier:
		score *= PREFERRED_ALT_MULT

	# ── 战场引力（spec battlefield-gravity §2/§3.2；仅玩家小队 AI 自主评分，沙盒/敌方零变化）──
	# 三带项只用 instance_id + global_position，候选可为任意 CombatUnit（不 cast Aircraft）
	var grav_on := ObjectiveContext.enabled and ai.aircraft.is_player_squad()
	var grav_surv := false
	var grav_obj := false
	if grav_on:
		grav_surv = ObjectiveContext.is_survival_threat(target_ac)
		grav_obj = ObjectiveContext.is_objective(target_ac)
		if not grav_surv and not grav_obj:
			# §2.1.2 可行性门：编队僚机不选"追出 leash 必被拽回"的目标（log① 45 次 engage↔rejoin 根因）
			if ai.squad and is_instance_valid(ai.squad.leader) and ai.squad.leader != ai.aircraft \
					and not ai.squad.leader.is_destroyed:
				var d_leader := ai.squad.leader.global_position.distance_to(target_ac.global_position)
				if d_leader > ai.effective_squad_leash() * ObjectiveContext.LEASH_FEAS_MARGIN:
					return -1.0
			# §2.2 顺手层引力衰减（只乘 base 修饰段；下方护卫/守后/三带加性项不衰减）
			score *= ObjectiveContext.gravity_mult(target_ac.global_position)

	# 护卫加权（绝对加分，量级远大于 base → 咬长机者主导）
	if escort_leader != null and target_ac is Aircraft:
		score += SquadCoordination.escort_target_bonus(escort_leader, target_ac as Aircraft)

	# 守后优先：仅守后语境，长机后半球且咬/逼近长机的敌机主导本次选择
	if guard_ctx and target_ac is Aircraft and ai.squad and is_instance_valid(ai.squad.leader):
		score += REAR_GUARD_PRIORITY * SquadCoordination.rear_threat_score(ai.squad.leader, target_ac as Aircraft)

	# ── 三带加性（§2.1：生存 60~100 > 任务 40 > 顺手 ≤1，可叠加）──
	if grav_obj:
		score += ObjectiveContext.OBJECTIVE_BONUS
	if grav_surv:
		score += ObjectiveContext.SURVIVAL_BONUS * ObjectiveContext.threat01(target_ac)

	return score

## 导弹包络因子：包络内=1.0；太近(要拉开)=0.3；超包络=0.15（低优先但仍可作兜底飞近再打）。
## 无导弹（纯机炮机）→ 1.0，不按导弹包络罚分。
static func _envelope_factor(ac: Aircraft, target: CombatUnit, dist_m: float) -> float:
	var msl: MissileParams = ac.params.missile if ac.params else null
	if msl == null:
		return 1.0
	if ac._is_in_missile_envelope(target, msl):
		return 1.0
	if dist_m < msl.min_range:
		return 0.3
	return 0.15

## 守后语境：整队 GUARD_REAR 模式。FOLLOW_LEADER 下的"自由机互掩守后"是逐帧瞬态，
## 由 scan_leader_rear 直接接管选定，不依赖本评分路径，故此处只认 GUARD_REAR。
static func _is_guard_rear_context(ai: AIController) -> bool:
	return ai.squad_engage_mode == AIController.SquadEngageMode.GUARD_REAR

# ══════════════════════════════════════════════
#  视觉遮蔽辅助
# ══════════════════════════════════════════════

## 低空 / 云中目标的 score 倍率（连续，无 tier 跳变）
##   贴地    → 0.80（轻度抑制）
##   3500m+ → 1.00
##   云密度 0~1 → 倍率 1.00 → 0.65（云中明显抑制）
##   两者取较强抑制（min），不相乘 —— 低空和云中通常不同时发生
static func _visibility_score_mult(target: CombatUnit) -> float:
	if target == null:
		return 1.0
	# 低空抑制：altitude 0~3500m 用 smoothstep 平滑衰减
	var alt_obscure := 1.0 - smoothstep(0.0, 3500.0, target.altitude)
	var alt_mult := lerpf(1.0, 0.80, alt_obscure)
	# 云中抑制：直接用 cloud_density (0~1) 线性
	var cloud_mult: float = 1.0
	if target is Aircraft:
		cloud_mult = lerpf(1.0, 0.65, (target as Aircraft).cloud_density)
	return minf(alt_mult, cloud_mult)
