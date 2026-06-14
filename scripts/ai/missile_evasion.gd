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
## 散开兜底超时：累计"无导弹"扫描超过此值就强制退出 evade，
## 不再受 leader 的 evasion_mode 广播控制（防 LOD2 / 广播脱节导致 wingman
## 在无威胁状态下持续 max+AB 散开飞出地图，并留下不消失的 flare 特效）
const SCATTER_NO_MISSILE_TIMEOUT := 3.5
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
	# ── 小队 leash 也管躲弹（spec squad-cohesion）──
	# 躲弹无 leash 是僚机脱队的大头：被地面 SAM 反复打 → 一路 max+AB 躲到天边（log 实测 7km），
	# 守后/编队名存实亡。这里：躲弹中游走出长机 leash 距离 → 停躲归队（仍有真威胁会在近处重新进躲）。
	if ai.squad and is_instance_valid(ai.squad.leader) and ai.squad.leader != ai.aircraft \
			and not ai.bvr_only and not ai.is_boss_attacker() and ai.combat_zone_anchor == null:
		var ld := ai.aircraft.global_position.distance_to(ai.squad.leader.global_position)
		if ld > ai.effective_squad_leash():
			ai._squad_leash_timer += delta
			if ai._squad_leash_timer >= AIController.SQUAD_LEASH_HYSTERESIS:
				ai._squad_leash_timer = 0.0
				ai.aircraft.evasion_mode = false  # 清掉防 ai_controller evade 守卫 re-enter bounce
				EventLogger.log_event("AI_STATE", ai._log_name(),
					"LEASH break-off (evade %.0fpx from leader) → rejoin" % ld)
				exit_evade(ai)
				return
		else:
			ai._squad_leash_timer = 0.0

	var missile := find_nearest_incoming_missile(ai)
	if not missile:
		# 只有"长机正在广播规避"（玩家按了规避键，全队陪同散开）才持续散开。
		# 僚机自己躲的那发一旦解除（jam/甩开/飞过头），长机没在广播 → 立刻清 evasion_mode 退出归位，
		# 不再空跑 3.5s 散开尾巴（用户反馈：威胁一解除就该立刻归队）。
		var leader_broadcasting: bool = ai.squad and is_instance_valid(ai.squad.leader) \
				and ai.squad.leader != ai.aircraft and ai.squad.leader.evasion_mode
		if ai.aircraft.evasion_mode and leader_broadcasting:
			# 兜底超时：累计"无导弹散开"时长 > SCATTER_NO_MISSILE_TIMEOUT 就强制 exit，
			# 防 LOD/广播脱节导致 wingman 无威胁还持续 max+AB 散开飞出地图
			ai._scatter_no_missile_secs += delta
			if ai._scatter_no_missile_secs >= SCATTER_NO_MISSILE_TIMEOUT:
				# 关键：本地清 evasion_mode，否则 ai_controller 的 evade 守卫下一帧又强制
				# enter_evade 形成 bounce。leader 下次 toggle 时 _propagate 会重新写回 true。
				ai.aircraft.evasion_mode = false
				exit_evade(ai)
				return
			_process_scatter_evade(ai, delta)
			return
		# 自己躲的那发已解除 + 长机没在广播 → 立即归位。
		# 先清 evasion_mode（同上：防 ai_controller evade 守卫 bounce），再 exit。
		if ai.aircraft.evasion_mode:
			ai.aircraft.evasion_mode = false
		exit_evade(ai)
		return
	# 检测到真实导弹 → 重置散开兜底计时（让 wingman 在真有威胁时无限散开）
	ai._scatter_no_missile_secs = 0.0

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
	# 承诺 break 方向：首次选定后保持，不每帧按"哪个垂直向更近"重选——否则导弹移动时
	# chosen_dir 来回翻 → target 左右跳 → 机身 bank 来回摆（2026-06-07 修 EVADE 抖）。
	# 现实导弹规避就是朝一个方向硬 break。承诺向与新 chosen 反向超过 90° 才允许重定（极端再机动）。
	if ai._evade_committed_dir == Vector2.ZERO or ai._evade_committed_dir.dot(chosen_dir) < -0.1:
		ai._evade_committed_dir = chosen_dir
	chosen_dir = ai._evade_committed_dir

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
	ai._evade_committed_dir = Vector2.ZERO  # 每次新规避重新选 break 方向
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
	ai._scatter_no_missile_secs = 0.0  # 兜底计时清零
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
	ai._scatter_no_missile_secs = 0.0
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

# ── 玩家方规避威胁门（2026-06-14）──
# 用户反馈：僚机对慢速/追不上/还很远的导弹也 max+AB 散开飞离阵型，过激、不自然。
# 改为：只有"在逼近(会命中) 且 即将到达"的导弹才算规避威胁，触发加速散开；其余留在阵型，
# 由智能 flare 末段兜底（巡航/待机时最小限度努力）。比 flare 门更早一点（给机动留提前量），
# 但同样要求导弹确实在逼近。敌方不受此门约束（维持难度）。
const EVADE_MIN_CLOSING_MS := 60.0    ## 闭合速度 < 此(m/s) → 追不上/慢弹 → 不值得散开规避
const EVADE_TTI_THRESHOLD := 3.5      ## 命中剩余时间 > 此(s) → 还不急，先不进 max+AB 散开

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
	var is_player_side: bool = ai.aircraft.team == 0

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
			var already_evading: bool = ai.aircraft.evasion_mode \
					or ai._state == AIController.AIState.EVADE_MISSILE
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
