class_name SquadCoordination
extends RefCounted

## 编队协同子系统（静态工具类）
## 从 ai_controller.gd 提取的 SQUAD_FOLLOW / 掩护扫描 / 协同齐射逻辑：
##   process_squad_follow       — SQUAD_FOLLOW 主循环（阵型槽位 / 反应延迟 / 自由或跟随长机交战 / 归队混合）
##   scan_leader_rear           — 扫描长机后半球威胁（掩护交战目标）
##   scan_squad_nearby_enemy    — 距离扫描附近敌机（自由交战目标）
##   end_cover_engagement       — 结束掩护交战，回归编队
##   broadcast_salvo            — leader 发射后广播齐射信号给僚机
##   process_salvo              — 处理齐射倒计时（在 aircraft._update_missile 中每帧调用）
##
## 状态仍住在 AIController。本模块不持有状态，只在 ai 上读写。
##
## 枚举/常量引用保留在 AIController：
##   AIController.AIState / AIController.EngageTactic / AIController.SquadEngageMode /
##   AIController.FORMATION_* / AIController.WINGMAN_ENGAGE_DELAY_* /
##   AIController.COVER_SCAN_RANGE / AIController.SQUAD_FREE_SCAN_RANGE /
##   AIController.SQUAD_FREE_MIN_DIST / AIController.SQUAD_SCAN_RADAR_MULT /
##   AIController.MIN_DUR_LEAD_PURSUIT
##
## 注意：_find_member_ai / _get_missile_manager / _is_target_already_squad_engaged
## 内部实现仍保留在 AIController（场景图辅助）。本模块通过 ai._xxx 调用。

# ══════════════════════════════════════════════
#  SQUAD_FOLLOW — 编队跟随（含自由/协同交战切换）
# ══════════════════════════════════════════════

static func process_squad_follow(ai: AIController, delta: float) -> void:
	if not ai.squad or not ai.squad.leader or not is_instance_valid(ai.squad.leader) or ai.squad.leader.is_destroyed:
		# 编队无效，回退到巡逻
		ai._state = AIController.AIState.PATROL
		ai.squad = null
		ai.aircraft.formation_mode = false
		ai.aircraft._formation_leader = null
		return

	var leader := ai.squad.leader

	# 安全网：若自己就是长机（例如中途原长机阵亡自动晋升）
	# 不能进入跟随分支，否则 get_wingman_target(squad_index≠0) 会算出
	# 一个相对于自身旋转的槽位，飞机陷入追自己尾巴的原地自转死循环
	if leader == ai.aircraft:
		ai.squad_index = 0
		ai.aircraft.formation_mode = false
		ai.aircraft._formation_leader = null
		ai._formation_blend = 0.0
		ai._rejoining = false
		ai._state = AIController.AIState.PATROL
		BFMTactics.set_patrol_altitude(ai)
		ai._set_next_waypoint()
		return

	# ── 导弹规避优先（BOSS 攻击手跳过） ──
	if ai.evade_missiles and ai.personality.missile_aware and not ai.is_boss_attacker():
		MissileEvasion.enter_evade(ai)
		return

	# ── 正常编队跟随 ──
	# 防御性清除：确保编队中无残留战斗目标干扰
	if ai.aircraft.combat_target != null:
		ai.aircraft.clear_combat_target()
		ai.aircraft.ai_override_pursuit = false
	ai._cover_target = null
	ai.aircraft.lod_level = 1  # 编队托管运算
	ai.aircraft.keep_target_on_arrival = true
	ai.aircraft.formation_mode = true
	ai.aircraft._formation_leader = leader
	ai.current_tactic_name = "TACTIC_FOLLOW_FORMATION"

	# 回归编队时渐变混合度（从自主飞行平滑过渡到完全托管）
	if ai._formation_blend < 1.0:
		ai._formation_blend = minf(ai._formation_blend + delta * 0.5, 1.0)  # ~2秒过渡
		ai.current_tactic_name = "TACTIC_REJOIN"
	else:
		ai._rejoining = false  # 完全融入编队，结束归队状态
	ai.aircraft._formation_blend = ai._formation_blend

	# 传递个体扰动相位
	ai.aircraft._formation_jitter_phase = ai._formation_jitter_phase

	# 计算阵型槽位
	var slot_pos := ai.squad.get_wingman_target(ai.squad_index)

	# 检测阵型变换：对比相对长机本地坐标系的偏移
	# （消除长机移动/转向带来的影响，只检测阵型 offset 本身的变化）
	if slot_pos != Vector2.INF:
		var new_offset_local := (slot_pos - leader.global_position).rotated(-leader.heading)
		if ai._prev_formation_offset_local != Vector2.INF:
			var offset_change := ai._prev_formation_offset_local.distance_to(new_offset_local)
			if offset_change > AIController.FORMATION_SWITCH_THRESH:
				# 阵型切换了：设置个体化反应延迟（0.3~1.3秒）
				# 用个体扰动相位让每架飞机反应略有差异（风格一致）
				var base_delay := AIController.FORMATION_REACT_BASE + (sin(ai._formation_jitter_phase) * AIController.FORMATION_JITTER_AMP + 0.5) * AIController.FORMATION_JITTER_ADD
				ai._formation_react_timer = base_delay + randf_range(-0.15, 0.15)
		ai._prev_formation_offset_local = new_offset_local

	# 反应延迟期间：不更新 target_position（飞机继续向旧槽位飞行）
	# 延迟过后突然更新 slot_pos，会触发 aircraft 编队代码的中距追击分支 → 自然曲线转弯
	if ai._formation_react_timer > 0.0:
		ai._formation_react_timer -= delta
		ai.current_tactic_name = "TACTIC_FORMATION_ADJUST"
	else:
		if slot_pos != Vector2.INF:
			ai.aircraft.target_position = slot_pos

	# ── 自由模式：独立扫描附近敌机，优先级低于长机协同 ──
	# 长机无目标时才独立找目标；长机一旦锁定会走下面的协同攻击入口。
	# 跟随长机模式不做独立扫描。
	#
	# 注：这里用的是距离扫描（_scan_squad_nearby_enemy）而不是 _try_engage(雷达锥扫描)。
	# 原因：_try_engage 只能看到"雷达锥内 + 已经锁定 30% 以上"的敌机；玩家平飞飞过
	# 一架敌机时，该敌机会在僚机的雷达锥外或只短暂进入，永远达不到锁定门槛——
	# 结果就是"我明明飞过一架敌机，僚机一动不动"。
	# 距离扫描绕开雷达锥和锁定门槛，让僚机拥有真正的"小队态势感知"。
	if ai.squad_engage_mode == AIController.SquadEngageMode.FREE and ai.enable_combat \
			and (leader.combat_target == null or not is_instance_valid(leader.combat_target) or leader.combat_target.is_destroyed):
		ai._scan_timer -= delta
		if ai._scan_timer <= 0.0:
			ai._scan_timer = 1.0  # 每秒一次扫描，flyby 不容易漏
			if ai._cooldown_timer <= 0.0:
				var tgt := scan_squad_nearby_enemy(ai)
				if tgt:
					# 进 ENGAGE：与协同攻击走一样的过渡，只是 target 是自己找的
					ai._current_target = tgt
					ai.aircraft.set_combat_target(tgt)
					ai.aircraft.ai_override_pursuit = true
					ai.aircraft.keep_target_on_arrival = false
					ai.aircraft.formation_mode = false
					ai.aircraft._formation_leader = null
					ai.aircraft._formation_blend = 0.0
					ai._formation_blend = 0.0
					ai.aircraft.lod_level = 0
					ai._state = AIController.AIState.ENGAGE
					ai._engage_timer = 0.0
					ai._tactic = AIController.EngageTactic.LEAD_PURSUIT
					ai._tactic_timer = 0.0
					ai._tactic_min_duration = AIController.MIN_DUR_LEAD_PURSUIT
					ai._squad_attacking_leader_target = false
					ai._squad_free_engaging = true  # 享有 range grace，避免刚进就被踢出
					ai._leader_target_lost_timer = 0.0
					ai._squad_range_grace_timer = 0.0
					ai.current_tactic_name = "TACTIC_FREE_ENGAGE"
					EventLogger.log_event("AI_STATE", ai._log_name(),
						"SQUAD FREE engage → %s" % ai._log_target_name(tgt))
					return

	# 跟随长机的交战目标（长机锁定敌机时僚机协同攻击）
	# FREE / FOLLOW_LEADER 都进这里——这是"跟随长机打谁"的入口
	if leader.combat_target and is_instance_valid(leader.combat_target) and not leader.combat_target.is_destroyed:
		# 反应延迟：每架僚机有不同的反应时间（0.3~1.5秒）
		# P4：planner 管理的僚机跳过反应延迟（"聪明 AI"立即响应长机锁定）
		# 旧 AI 保留延迟以维持人形不同步感
		if ai.aircraft.use_tactical_planner:
			ai._engage_delay = 0.0
		elif ai._engage_delay <= 0.0:
			ai._engage_delay = randf_range(AIController.WINGMAN_ENGAGE_DELAY_MIN, AIController.WINGMAN_ENGAGE_DELAY_MAX)
		ai._engage_delay -= delta
		if ai._engage_delay <= 0.0:
			ai._engage_delay = 0.0
			ai.aircraft.keep_target_on_arrival = false
			ai.aircraft.formation_mode = false
			ai.aircraft._formation_leader = null
			ai.aircraft._formation_blend = 0.0
			ai._formation_blend = 0.0  # 下次回归编队时从0开始混合
			ai.aircraft.set_combat_target(leader.combat_target)
			ai.aircraft.lod_level = 0
			ai._state = AIController.AIState.ENGAGE
			ai._engage_timer = 0.0
			ai._tactic = AIController.EngageTactic.LEAD_PURSUIT
			ai._tactic_timer = 0.0
			ai._tactic_min_duration = AIController.MIN_DUR_LEAD_PURSUIT
			ai._current_target = leader.combat_target
			ai.aircraft.ai_override_pursuit = true
			ai._squad_attacking_leader_target = true
			ai._squad_free_engaging = false  # 协同攻击路径互斥
			ai._leader_target_lost_timer = 0.0
			ai._squad_range_grace_timer = 0.0
			ai.current_tactic_name = "TACTIC_TEAM_ATTACK"
	else:
		ai._engage_delay = 0.0  # 长机无目标时重置延迟

## 扫描长机后半球威胁
static func scan_leader_rear(ai: AIController) -> Aircraft:
	if not ai.squad or not ai.squad.leader:
		return null
	var leader := ai.squad.leader
	var leader_fwd := Vector2(sin(leader.heading), -cos(leader.heading))

	var best_threat: Aircraft = null
	var best_dist := AIController.COVER_SCAN_RANGE

	var root := ai.aircraft.get_parent()
	if not root:
		return null

	for child in root.get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac.team == ai.aircraft.team or ac.is_destroyed:
			continue

		var to_enemy := ac.global_position - leader.global_position
		var dist := to_enemy.length()
		if dist > AIController.COVER_SCAN_RANGE or dist >= best_dist:
			continue

		# 检查是否在长机后半球（与长机航向的夹角 > 90°）
		var angle := leader_fwd.angle_to(to_enemy.normalized())
		if absf(angle) > PI * 0.5:
			best_dist = dist
			best_threat = ac

	return best_threat

## 小队自由交战：距离扫描最近的敌机（绕开雷达锥 + 锁定门槛）
## 设计理念：把"小队整体的感知"与"单机雷达"解耦——
## 即使敌机在僚机身后或侧面、没触发自身雷达锁定，只要在合理距离内就能被发现。
##
## 距离计算：
##   - flat_altitude=true（生存模式）：用 2D 距离，完全忽略高度差
##     —— 生存模式设计上是"任何高度都能到"，不应让高度差影响目标选择
##   - 否则（沙盒模式）：用 effective_distance_px 3D
static func scan_squad_nearby_enemy(ai: AIController) -> Aircraft:
	var root := ai.aircraft.get_parent()
	if not root:
		return null
	# max_range_px 必须严格小于 _process_engage 的脱战阈值 (radar_range * 1.5)。
	var max_range_px := AIController.SQUAD_FREE_SCAN_RANGE
	if ai.aircraft.params:
		max_range_px = minf(max_range_px, ai.aircraft.params.radar_range * AIController.SQUAD_SCAN_RADAR_MULT)
	var best: Aircraft = null
	var best_dist := max_range_px
	var use_2d := ai.aircraft.flat_altitude  # 生存模式走 2D
	for child in root.get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac.team == ai.aircraft.team or ac.is_destroyed:
			continue
		var d: float
		if use_2d:
			d = ai.aircraft.global_position.distance_to(ac.global_position)
		else:
			d = Aircraft.effective_distance_px(
				ai.aircraft.global_position, ai.aircraft.altitude,
				ac.global_position, ac.altitude
			)
		if d < AIController.SQUAD_FREE_MIN_DIST or d >= best_dist:
			continue
		# 不追刚被别的僚机盯上的目标：避免 3 架同时扑一个
		if ai._is_target_already_squad_engaged(ac):
			continue
		best_dist = d
		best = ac
	return best

## 结束掩护交战，回归编队
static func end_cover_engagement(ai: AIController) -> void:
	ai._cover_target = null
	ai.aircraft.clear_combat_target()
	ai.aircraft.ai_override_pursuit = false
	ai.aircraft.lod_level = 1
	ai.current_tactic_name = "TACTIC_RETURN_FORMATION"

# ══════════════════════════════════════════════
#  协同齐射系统（F-47 小队战术）
# ══════════════════════════════════════════════

## leader 发射导弹后广播齐射信号给编队僚机
static func broadcast_salvo(ai: AIController) -> void:
	if not ai.squad:
		return
	for member in ai.squad.members:
		if not is_instance_valid(member) or member.is_destroyed or member == ai.aircraft:
			continue
		var mai: AIController = ai._find_member_ai(member)
		if mai and not mai._salvo_pending:
			mai._salvo_pending = true
			mai._salvo_delay = randf_range(0.1, 0.4)  # 0.1~0.4 秒错开

## 处理齐射倒计时（在 aircraft._update_missile 中每帧调用）
static func process_salvo(ai: AIController, delta: float) -> bool:
	if not ai._salvo_pending:
		return false
	ai._salvo_delay -= delta
	if ai._salvo_delay <= 0.0:
		ai._salvo_pending = false
		return true  # 通知 aircraft 强制发射
	return false
