class_name MissileEvasion
extends RefCounted

## 导弹规避子系统（静态工具类）
## 从 ai_controller.gd 提取的 EVADE_MISSILE 状态逻辑：
##   process_evade            — EVADE 主循环：垂直规避 + Herbst 机动触发 + 高度档位切换
##   enter_evade / exit_evade — 状态转入/转出（退出编队托管 / 重入交战 / 归队 / 返回巡逻）
##   should_enter_evade       — 分层规避入口门（B1：flare 优先，无 flare 才机动）
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

# spec wingman-escort-evasion：旧 _process_scatter_evade（玩家广播 evasion 时僚机无脑散开扇形）
# 已废除 —— 护卫姿态改为 escort_cover_active + SQUAD_FOLLOW 待命 + 护卫 flare（僚机不脱队）。
# 僚机仅在"自己真被导弹咬住"时走下方 process_evade 的垂直规避机动逃命。

static func process_evade(ai: AIController, delta: float) -> void:
	# 躲弹 leash 已上收到 AIController._apply_constraints 约束层（Phase 2）——
	# 分发前统一执行，交战/躲弹一视同仁，本函数不再持有拷贝（SEAM-010 根治）。

	var missile := find_nearest_incoming_missile(ai)
	if not missile:
		# spec wingman-escort-evasion：自己被咬的那发一旦解除（jam/甩开/飞过头）→ 立即归队。
		# 不再因"长机正在广播规避"而持续 max+AB 散开 —— 旧的 scatter-on-broadcast 行为已废除，
		# 护卫姿态改由 escort_cover_active + SQUAD_FOLLOW 待命 + 护卫 flare 承担（不脱队）。
		# 先清 evasion_mode（enter_evade 自保时设的），防 planner evasion_intent 残留 + 守卫 bounce。
		if ai.aircraft.evasion_mode:
			ai.aircraft.set_evasion_mode(false)
		exit_evade(ai)
		return

	# ── 战术机动：后方来袭导弹逼近时一次性触发 ──
	var _mev := ai.aircraft.get_maneuver()
	if _mev and not _mev.is_used and not _mev.is_active:
		var missile_dist := missile.global_position.distance_to(ai.aircraft.global_position)
		if missile_dist < AIController.MANEUVER_ACTIVATE_DIST and is_missile_from_rear(ai, missile):
			_mev.activate()
			_submit_evade_pursuit(ai, _forward_point(ai, AIController.EVADE_FLIGHT_DIST))
			return
	# 战术机动执行中：保持航向等待完成
	if _mev and _mev.is_active:
		_submit_evade_pursuit(ai, _forward_point(ai, AIController.EVADE_FLIGHT_DIST))
		return

	var missile_dir := (ai.aircraft.global_position - missile.global_position).normalized()
	var evade_dir := Vector2(missile_dir.y, -missile_dir.x)

	var evade_heading_a := atan2(evade_dir.x, -evade_dir.y)
	var evade_heading_b := atan2(-evade_dir.x, evade_dir.y)
	var diff_a := absf(AIController._angle_diff(evade_heading_a, ai.aircraft.heading))
	var diff_b := absf(AIController._angle_diff(evade_heading_b, ai.aircraft.heading))
	var chosen_dir := evade_dir if diff_a < diff_b else -evade_dir
	# 承诺 break 方向：首次选定后保持，不每帧按"哪个垂直向更近"重选——否则导弹移动时
	# chosen_dir 来回翻 → target 左右跳 → 机身 bank 来回摆（2026-06-07 修 EVADE 抖）。
	# 现实导弹规避就是朝一个方向硬 break。承诺向与新 chosen 反向超过 90° 才允许重定（极端再机动）。
	if ai._evade_committed_dir == Vector2.ZERO or ai._evade_committed_dir.dot(chosen_dir) < -0.1:
		ai._evade_committed_dir = chosen_dir
	chosen_dir = ai._evade_committed_dir

	ai._evade_target_pos = ai.aircraft.global_position + chosen_dir * AIController.EVADE_TURN_DIST
	# Phase 1：AI 规避几何走 EVADE 意图槽（sticky：AI 分频写、60Hz resolve 读，
	# 且不再会被 planner 的 CRUISE/WAYPOINT 意外覆盖——慢写快读死点根治）
	_submit_evade_pursuit(ai, ai._evade_target_pos)

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
	# Phase 2：EVADE 是 modifier（_evading），不占 _state 轴——背景状态保持原值，
	# 分发层短路到 process_evade；本函数是 _evading 的唯一 true 写入点。
	if ai._evading:
		return  # 幂等：已在躲弹（护卫分支/巡逻分支可能重复调用）
	EventLogger.log_event("EVADE", ai._log_name(),
		"entering missile evasion (bg_state=%s, target=%s)" % [
			AIController.AIState.keys()[ai._state], ai._log_target_name(ai._current_target)])
	ai._evading = true
	ai._evade_committed_dir = Vector2.ZERO  # 每次新规避重新选 break 方向
	ai.aircraft.ai_override_pursuit = false
	# P4：planner 模式下置 evasion_mode → planner 选 EVADE_MISSILE intent → max + AB
	# MissileEvasion.process_evade 仍写 target_position（垂直规避向量），两者协作：
	# planner 决定速度/AB，process_evade 决定方向/高度
	# 走 set_evasion_mode 入口（B3）：保 evasion_modifiers 边界差量缩放对称；
	# AI 无 use_tactical_preference 不会触发僚机广播。
	if ai.aircraft.use_tactical_planner:
		ai.aircraft.set_evasion_mode(true)
	ai._squad_attacking_leader_target = false
	ai._squad_lateral_role = AIController.SquadRole.NONE
	ai._squad_free_engaging = false
	if ai.aircraft.combat_target:
		ai.aircraft.clear_combat_target()
	# 退出编队托管，规避机动必须走正常飞行物理（LOD 0）
	# 否则 lod_level==1 + formation_mode 会让规避航向变化走
	# aircraft.gd:261 的纯 lerp_angle 分支，绕过 G 限/bank 速率/corner speed，
	# 导致 ~360°/s 的瞬间机头扭转（见 2026-04-11 Jinx 规避 bug）。
	ai.aircraft.clear_formation()
	ai._formation_blend = 0.0  # 规避结束后从 0 开始重新融入编队

## EVADE 槽提交 helper（process_evade 三个几何分支共用）
static func _submit_evade_pursuit(ai: AIController, pos: Vector2) -> void:
	var ci := ControlIntent.new()
	ci.pursuit_pos = pos
	ai.aircraft.submit_intent(ControlIntent.SOURCE_EVADE, ci)


## 机头前方 dist px 的点（机动期间"保持航向"用）
static func _forward_point(ai: AIController, dist: float) -> Vector2:
	var fwd := Vector2(sin(ai.aircraft.heading), -cos(ai.aircraft.heading))
	return ai.aircraft.global_position + fwd * dist


static func exit_evade(ai: AIController) -> void:
	EventLogger.log_event("EVADE", ai._log_name(), "exiting missile evasion")
	# Phase 2：_evading 的唯一 false 写入点（与 enter_evade 对称）
	ai._evading = false
	# Phase 1：撤销规避几何主张（sticky 槽生命周期与 EVADE 模态对称）
	ai.aircraft.withdraw_intent(ControlIntent.SOURCE_EVADE)
	# P4：清 evasion_mode 让 planner 回到正常 intent 路径（走入口，同 enter 对称）
	if ai.aircraft.use_tactical_planner:
		ai.aircraft.set_evasion_mode(false)
	# 三路重定：躲弹期间目标/长机可能已亡，按当下上下文重选背景状态。
	# 字段清单收口到 AIController 的过渡函数（Phase 2），本处只补各路特有字段。
	# is_lock_immune()（光学隐形 / 锁定免疫）视同目标已失效 → 落到编队/巡逻分支，
	# 否则退出 EVADE 会把隐形目标重新写回 combat_target（spec ace-squadron-tier §3.5）
	if ai._current_target and is_instance_valid(ai._current_target) \
			and not ai._current_target.is_destroyed and not ai._current_target.is_lock_immune():
		ai.aircraft.set_combat_target(ai._current_target)
		BFMTactics.set_patrol_altitude(ai)
		ai.enter_engage_state(false)  # 恢复交战：不打断躲弹前的战术选择
		ai._tactic_timer = 0.0        # 但允许下一 tick 立刻重挑战术（旧行为）
	elif ai.squad and is_instance_valid(ai.squad.leader) and not ai.squad.leader.is_destroyed:
		ai.enter_squad_follow_state()
		ai.aircraft.clear_combat_target()
	else:
		ai._current_target = null
		ai.enter_patrol_state()

# ══════════════════════════════════════════════
#  分层规避入口门（B1 定稿策略 2026-07-02）
# ══════════════════════════════════════════════

## 是否应进入运动学规避（EVADE_MISSILE）。所有 enter_evade 的"入口"判定统一走这里；
## EVADE 的"维持/退出"仍由 process_evade 的 find_nearest_incoming_missile（带滞回）负责。
##
## 玩家方三层（见 docs/planning/physics-ai-control-refactor.md §3 B1 定稿策略）：
##   ① 无真威胁导弹 → 不躲。_is_evasion_threat 已滤掉"追不上/还很远/已过头"的导弹，
##      被雷达锁定本身不构成脱离命令/编队的理由。
##   ② 有真威胁但 flare 还能兜底（弹量/CD 就绪）→ 不进运动学规避，留在命令/编队航线，
##      智能 flare 会在末段（TTI≤1.5s）自动出手——多数导弹到此为止，不脱队。
##   ③ flare 不可用（弹尽/装填/冷却/隐身抑制/机动中）或 flare 已对这枚弹失误放弃
##      → 才允许加速散开躲弹（此时命令铁律让位，见 _enforce_commanded_target）。
## 敌方不受 flare 门约束（维持难度，行为与旧 check_incoming_missile 完全一致）。
static func should_enter_evade(ai: AIController) -> bool:
	# leash 拽回后的再入冷却：归队意志压过规避一小段（回程即变向，且回到护卫焰覆盖内）
	if ai._evade_reenter_cd > 0.0:
		return false
	var m := find_nearest_incoming_missile(ai)
	if m == null:
		return false
	if not ai.aircraft.is_player_squad():
		return true
	# 导弹穿透窗口期（刚放焰获得的免疫窗）：导弹打不中，无需散开
	if ai.aircraft.missile_phase_timer > 0.0:
		return false
	# flare 曾对这枚弹失误放弃（fail_chance roll）→ flare 不会再管它 → 必须机动
	if ai.aircraft._flare_ignored_missiles.has(m.get_instance_id()):
		return true
	# flare 就绪 → 交给智能 flare 末段兜底，不进运动学规避
	if AircraftFlares.flare_ready(ai.aircraft):
		return false
	return true

# ══════════════════════════════════════════════
#  导弹威胁检测
# ══════════════════════════════════════════════

# ── 玩家方规避威胁门（2026-06-14）──
# 用户反馈：僚机对慢速/追不上/还很远的导弹也 max+AB 散开飞离阵型，过激、不自然。
# 改为：只有"在逼近(会命中) 且 即将到达"的导弹才算规避威胁，触发加速散开；其余留在阵型，
# 由智能 flare 末段兜底（巡航/待机时最小限度努力）。比 flare 门更早一点（给机动留提前量），
# 但同样要求导弹确实在逼近。敌方不受此门约束（维持难度）。
const EVADE_MIN_CLOSING_MS := 60.0    ## 闭合速度 < 此(m/s) → 追不上/慢弹 → 不值得散开规避
const EVADE_TTI_THRESHOLD := 3.5      ## 命中剩余时间 > 此(s) → 还不急，先不进 max+AB 散开
const LEASH_REENTER_SUPPRESS_S := 2.0 ## leash 拽回后规避再入冷却（防 EVADE↔SQUAD_FOLLOW 振荡）

## 玩家方：这枚导弹是否值得进入/维持"加速散开"规避（在逼近 + 即将到达）。纯几何，可单测。
## already_evading 滞回：已在躲弹时用更宽松的门（更难解除）——否则僚机一加速就把 closing 拉低到
## 阈值下 → 退出 → 减速归队 → closing 又升回 → 重新进，在边界来回弹跳(EVADE↔SQUAD_FOLLOW 抖)。
static func _is_evasion_threat(ac: Aircraft, m: Missile, already_evading: bool = false) -> bool:
	var los: Vector2 = ac.global_position - m.global_position
	var dist_px: float = los.length()
	if dist_px < 1.0:
		return true
	var los_n: Vector2 = los / dist_px
	var v_ac: Vector2 = Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed
	var v_m: Vector2 = Vector2(sin(m.heading), -cos(m.heading)) * m.speed
	var closing_ms: float = (v_m - v_ac).dot(los_n)   # >0 = 间距在缩小（导弹在逼近）
	# 滞回：进入要求 closing≥60 & TTI≤3.5；已在躲则放宽到 closing≥30 & TTI≤5.0 才解除
	var min_closing: float = (EVADE_MIN_CLOSING_MS * 0.5) if already_evading else EVADE_MIN_CLOSING_MS
	var tti_max: float = (EVADE_TTI_THRESHOLD + 1.5) if already_evading else EVADE_TTI_THRESHOLD
	if closing_ms < min_closing:
		return false
	var dist_m: float = dist_px / CombatUnit.PIXELS_PER_METER
	return (dist_m / closing_ms) <= tti_max


static func check_incoming_missile(ai: AIController) -> bool:
	return find_nearest_incoming_missile(ai) != null

static func find_nearest_incoming_missile(ai: AIController) -> Missile:
	var missile_manager := ai._get_missile_manager()
	if not missile_manager:
		return null

	var nearest: Missile = null
	var nearest_dist := 99999.0
	var is_player_side: bool = ai.aircraft.is_player_squad()

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
		if is_player_side:
			# 玩家方 wingmen：只有"在逼近 + 即将到达"的导弹才算规避威胁（慢/远/追不上 → 不散开，
			# 留在阵型靠智能 flare 末段兜底）。一旦被甩开(closing 掉)/TTI 拉远，下一 tick 即退出散开归位。
			# already_evading 滞回：已在躲弹用更宽松门，防边界 EVADE↔SQUAD_FOLLOW 抖。
			var already_evading: bool = ai.aircraft.evasion_mode or ai._evading
			if not _is_evasion_threat(ai.aircraft, m, already_evading):
				continue
		else:
			# ── 敌方：保留原"熄火后追不上即解除"逻辑（维持难度）──
			# 导弹熄火滑行后会减速；若此刻距离已不再缩小（飞机甩开了它），它再不可能命中 → 解除。
			if m.params and m.age > m.params.motor_burn_time and to_ac.length() > 1.0:
				var los := to_ac.normalized()  # 从导弹指向飞机
				var v_ac := Vector2(sin(ai.aircraft.heading), -cos(ai.aircraft.heading)) * ai.aircraft.speed
				var v_m := m_fwd * m.speed
				# 距离变化率 (v_ac - v_m)·los ≥ 0 → 距离不再缩小 → 追不上
				if (v_ac - v_m).dot(los) >= 0.0:
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
