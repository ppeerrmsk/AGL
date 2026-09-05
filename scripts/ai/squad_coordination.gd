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
## 枚举/常量引用：
##   AIController.AIState / SquadEngageMode / SquadRole
##   AIController.COVER_SCAN_RANGE / SQUAD_FREE_SCAN_RANGE / SQUAD_FREE_MIN_DIST / SQUAD_SCAN_RADAR_MULT
##   Squad.FORMATION_SWITCH_THRESH / FORMATION_REACT_BASE / FORMATION_JITTER_AMP /
##   Squad.FORMATION_JITTER_ADD / WINGMAN_ENGAGE_DELAY_MIN / WINGMAN_ENGAGE_DELAY_MAX
##
## 注意：_find_member_ai / _get_missile_manager / _is_target_already_squad_engaged
## 内部实现仍保留在 AIController（场景图辅助）。本模块通过 ai._xxx 调用。

# ══════════════════════════════════════════════
#  SQUAD_FOLLOW — 编队跟随（含自由/协同交战切换）
# ══════════════════════════════════════════════

static func process_squad_follow(ai: AIController, delta: float) -> void:
	if not ai.squad or not ai.squad.leader or not is_instance_valid(ai.squad.leader) or ai.squad.leader.is_destroyed:
		# 编队无效，回退到巡逻（沿用现有航点，不重选——下一 tick _process_patrol 自理）
		ai.enter_patrol_state(false)
		ai.squad = null
		ai.aircraft.clear_formation()
		return

	var leader := ai.squad.leader

	# 安全网：若自己就是长机（例如中途原长机阵亡自动晋升）
	# 不能进入跟随分支，否则 get_wingman_target(squad_index≠0) 会算出
	# 一个相对于自身旋转的槽位，飞机陷入追自己尾巴的原地自转死循环
	if leader == ai.aircraft:
		ai.squad_index = 0
		ai.aircraft.clear_formation()
		ai._formation_blend = 0.0
		ai._rejoining = false
		ai.enter_patrol_state()
		return

	# ── 导弹规避优先（BOSS 攻击手跳过） ──
	# ⚠ 必须先过 should_enter_evade 分层门：evade_missiles 是静态配置位（多数机型常 true），
	#   不是"有导弹"信号。缺这道门 → 编队中每个 AI tick 空转 enter_evade → process_evade 无弹立即 exit
	#   回 SQUAD_FOLLOW → 再触发 …… EVADE↔SQUAD_FOLLOW 每帧弹跳（log 实证僚机狂刷 auto-enter SQUAD_FOLLOW、
	#   飘到边上变慢不参战）。与 _process_engage / _process_patrol 两处同源修复保持一致。
	#   B1 分层门（2026-07-02）：flare 能兜底 → 留在编队让智能 flare 末段处理，不散开。
	if ai.evade_missiles and ai.personality.missile_aware and not ai.is_boss_attacker() \
			and MissileEvasion.should_enter_evade(ai):
		MissileEvasion.enter_evade(ai)
		return

	# ── 护卫 flare（spec wingman-escort-evasion §3.2）──
	# 长机按 E 进护卫姿态 + 本机没被真威胁（上面 self-evade 已 return）→ 编队待命的同时，
	# 替长机投焰挡追它的导弹。仅玩家方僚机；近长机才有效；消耗自身 flare（详见 AircraftFlares）。
	if ai.aircraft.escort_cover_active:
		AircraftFlares.try_cover_flare(ai.aircraft, leader)

	# ── 生存层主动回防（spec battlefield-gravity §3.3，常开）──
	# 操控机被咬 → 就近指派僚机反咬追击者（≤MAX_DEFENDERS，绕开雷达锥）。
	# 优先于 GUARD_REAR/FREE/跟打长机所有分支——玩家活命第一（North Star）。
	ai._defense_scan_timer -= delta
	if ai._defense_scan_timer <= 0.0:
		ai._defense_scan_timer = 1.0
		if ai.enable_combat and ai._cooldown_timer <= 0.0 \
				and try_defend_protectee(ai):
			return

	# ── 正常编队跟随 ──
	# 防御性清除：确保编队中无残留战斗目标干扰。
	# 例外：TIGHT 齐射窗口（volley_fire_active，spec formation-discipline）——窗口期僚机
	# 在编队槽位里持目标开火（movement 仍归编队，武器链读 combat_target），不清。
	var retaining_assault_target := ai.squad_engage_mode == AIController.SquadEngageMode.FOLLOW_LEADER \
			and ai._squad_attacking_leader_target and leader.combat_target != null \
			and is_instance_valid(leader.combat_target) and not leader.combat_target.is_destroyed \
			and ai.aircraft.combat_target == leader.combat_target
	if ai.aircraft.combat_target != null and not ai.aircraft.volley_fire_active \
			and not retaining_assault_target:
		ai.aircraft.clear_combat_target()
		ai._squad_attacking_leader_target = false
		ai.aircraft.ai_override_pursuit = false
	ai._cover_target = null

	ai.current_tactic_name = "TACTIC_FOLLOW_FORMATION"

	# 计算阵型偏移（长机本地坐标系，未旋转）——这是槽位的"慢变部分"：用哪个阵型、第几槽。
	# 世界坐标（"快变部分"= offset 旋进长机当前机体系）改由 AircraftFormation 每物理帧实时算，
	# 长机一动全队同帧跟动（强相关），不再有"等下一个 AI tick 才更新冻结死点"的慢一拍。
	var new_offset_local := ai.squad.get_formation_offset(ai.squad_index)

	# 检测阵型变换：长机平移/转向不改变本地偏移，只有"换阵型类型"才会变 → 仅此时给反应延迟。
	if ai._prev_formation_offset_local != Vector2.INF:
		var offset_change := ai._prev_formation_offset_local.distance_to(new_offset_local)
		if offset_change > Squad.FORMATION_SWITCH_THRESH:
			# 阵型类型切换：设置个体化反应延迟（0.3~1.3秒），让换阵型显得自然、错落
			var base_delay := Squad.FORMATION_REACT_BASE + (sin(ai._formation_jitter_phase) * Squad.FORMATION_JITTER_AMP + 0.5) * Squad.FORMATION_JITTER_ADD
			ai._formation_react_timer = base_delay + randf_range(-0.15, 0.15)
	ai._prev_formation_offset_local = new_offset_local

	# 反应延迟期间：暂不采纳新偏移（committed 维持旧槽位），仅平滑"换阵型"过渡。
	# 注意：这只延迟"采纳哪个 offset"，不影响日常跟随——槽位世界坐标仍每帧实时跟长机。
	if ai._formation_react_timer > 0.0:
		ai._formation_react_timer -= delta
		ai.current_tactic_name = "TACTIC_FORMATION_ADJUST"
		if ai._formation_offset_committed == Vector2.INF:
			ai._formation_offset_committed = new_offset_local  # 首次进编队必须初始化，否则无槽位
	else:
		ai._formation_offset_committed = new_offset_local

	# 进入/更新编队托管态（formation_mode=true / _formation_leader / lod=1 / keep_arrival）。
	# 写入 AI-tick 新鲜的世界槽位作基线（committed 此处已保证非 INF）；
	# AircraftFormation._build_context 再每物理帧从 committed 偏移实时细化到 60Hz（消除慢一拍）。
	# 双保险：即使某条 spawn/接管/规避恢复路径让 committed 暂为 INF 或时序错位，
	# 回退用的也是这一帧的新鲜槽位，而不是陈旧死点（修 2026-06-07 队友追旧位置回归）。
	var world_slot := leader.global_position + ai._formation_offset_committed.rotated(leader.heading)
	ai.aircraft.set_formation_target(leader, world_slot)

	# 回归编队时渐变混合度（从自主飞行平滑过渡到完全托管）
	# AircraftFormation 通过 ac._ai_ref._formation_blend 直接读，不再镜像到 Aircraft
	if ai._formation_blend < 1.0:
		ai._formation_blend = minf(ai._formation_blend + delta * 0.5, 1.0)  # ~2秒过渡
		ai.current_tactic_name = "TACTIC_REJOIN"
	else:
		ai._rejoining = false  # 完全融入编队，结束归队状态

	# ── 守护后半球模式：僚机只盯长机六点钟后半球的威胁，绝不去打长机的进攻目标 ──
	# 长机负责进攻，僚机专职守后：扫到后半球敌机就去拦截，没有就保持编队守在长机身后。
	if ai.squad_engage_mode == AIController.SquadEngageMode.GUARD_REAR:
		_guard_rear_tick(ai, delta)
		return  # 无后方威胁 → 只保持编队守在长机身后，不打长机的前方目标

	# ── 自由模式：独立扫描附近敌机（优先级高于跟随长机协同）──
	# 改动（2026-05-04）：旧版有 `leader.combat_target == null` 闸门，导致玩家一选目标
	# 所有僚机就抛下身边的敌人扑过去抢同一个 → 僚机失去自主性。
	# 现在：自由扫描始终跑，找到附近敌机就引擎；扫不到再走下面的"跟随长机锁定"分支。
	# 后果：玩家选远敌时，附近若有敌机僚机优先打附近的；附近清光后才补射玩家选的远敌。
	#
	# 注：这里用的是距离扫描（_scan_squad_nearby_enemy）而不是 _try_engage(雷达锥扫描)。
	# 原因：_try_engage 只能看到"雷达锥内 + 已经锁定 30% 以上"的敌机；玩家平飞飞过
	# 一架敌机时，该敌机会在僚机的雷达锥外或只短暂进入，永远达不到锁定门槛——
	# 结果就是"我明明飞过一架敌机，僚机一动不动"。
	# 距离扫描绕开雷达锥和锁定门槛，让僚机拥有真正的"小队态势感知"。
	if ai.squad_engage_mode == AIController.SquadEngageMode.FREE and ai.enable_combat:
		ai._scan_timer -= delta
		if ai._scan_timer <= 0.0:
			ai._scan_timer = 1.0  # 每秒一次扫描，flyby 不容易漏
			if ai._cooldown_timer <= 0.0:
				var tgt := scan_squad_nearby_enemy(ai)
				if tgt and ai.acquire_target(tgt, AIController.TargetSource.TS_SCORED, "squad free scan"):
					# 进 ENGAGE：与协同攻击走一样的过渡，只是 target 是自己找的
					ai.aircraft.clear_formation()  # formation_mode/leader/keep_arrival/lod=0/ai_override
					ai.aircraft.ai_override_pursuit = true
					ai._formation_blend = 0.0  # 下次回归编队时从 0 开始混合
					ai.enter_engage_state()
					ai._squad_attacking_leader_target = false
					ai._squad_lateral_role = AIController.SquadRole.NONE  # 自由交战不分配角色
					ai._squad_free_engaging = true  # 小队交战由 leash 约束，不受雷达距脱离
					ai._leader_target_lost_timer = 0.0
					ai.current_tactic_name = "TACTIC_FREE_ENGAGE"
					EventLogger.log_event("AI_STATE", ai._log_name(),
						"SQUAD FREE engage → %s" % ai._log_target_name(tgt))
					return

	# 跟随长机的交战目标（长机锁定敌机时僚机协同攻击）
	# FREE / FOLLOW_LEADER 都进这里——这是"跟随长机打谁"的入口
	# 交战冷却门（对齐上方 FREE 扫描路径）：leash 拽回 / disengage 设的 _cooldown_timer
	# 必须对本路径同样生效。否则 leash 脱战同拍就被塞回长机的同一目标 →
	# ENGAGE↔SQUAD_FOLLOW 以 0.5s（SQUAD_LEASH_HYSTERESIS）反复横跳，永不真正归队，
	# UI 上交战线/移动标记同频频闪（2026-07-05 log：Guide 的 LEASH break-off 与
	# TARGET_ACQ "follow leader target" 同一时间戳循环 62 次）。
	if leader.combat_target and is_instance_valid(leader.combat_target) and not leader.combat_target.is_destroyed \
			and ai._cooldown_timer <= 0.0:
		# 自由机互掩（双重攻击学说）：FOLLOW_LEADER 焦点打"飞机"时，指定一架僚机不进攻、
		# 改守长机后半球；其余僚机照常压目标。打地面/船/BOSS 不留掩护 → 全员饱和。
		if _should_be_free_fighter(ai, leader.combat_target):
			ai._engage_delay = 0.0
			_guard_rear_tick(ai, delta)
			return
		# 反应延迟：每架僚机有不同的反应时间（0.3~1.5秒）
		# P4：planner 管理的僚机跳过反应延迟（"聪明 AI"立即响应长机锁定）
		# Drone（kamikaze_intercept 标识）：机器即时反应，无延迟
		# 旧 AI 保留延迟以维持人形不同步感
		if ai.aircraft.use_tactical_planner or ai.kamikaze_intercept:
			ai._engage_delay = 0.0
		elif ai._engage_delay <= 0.0:
			ai._engage_delay = randf_range(Squad.WINGMAN_ENGAGE_DELAY_MIN, Squad.WINGMAN_ENGAGE_DELAY_MAX)
		ai._engage_delay -= delta
		if ai._engage_delay <= 0.0:
			ai._engage_delay = 0.0
			var follows_player_command: bool = leader.commanded_target != null \
					and is_instance_valid(leader.commanded_target) \
					and not leader.commanded_target.is_destroyed \
					and leader.commanded_target == leader.combat_target
			var acquire_reason := "follow player commanded target" if follows_player_command else "follow leader target"
			if ai.acquire_target(leader.combat_target, AIController.TargetSource.TS_SCORED, acquire_reason):
				if ai.squad_engage_mode == AIController.SquadEngageMode.FOLLOW_LEADER:
					# 阵型攻击：共享目标只交给火控，movement authority 继续归 formation。
					ai.aircraft.ai_override_pursuit = false
					ai._squad_attacking_leader_target = true
					ai._squad_lateral_role = _role_for_squad_index(ai.squad_index)
					ai._squad_free_engaging = false
					ai._leader_target_lost_timer = 0.0
					ai.current_tactic_name = "TACTIC_FORMATION_ASSAULT"
				else:
					ai.aircraft.clear_formation()
					ai.aircraft.ai_override_pursuit = true
					ai._formation_blend = 0.0
					ai.enter_engage_state()
					ai._squad_attacking_leader_target = true
					ai._squad_lateral_role = _role_for_squad_index(ai.squad_index)
					ai._squad_free_engaging = false
					ai._leader_target_lost_timer = 0.0
					ai.current_tactic_name = "TACTIC_TEAM_ATTACK"
	else:
		ai._engage_delay = 0.0  # 长机无目标时重置延迟
		ai._squad_attacking_leader_target = false

# ══════════════════════════════════════════════
#  生存层主动回防（spec battlefield-gravity §3.3，面 B）
# ══════════════════════════════════════════════

## 回防僚机数上限（§3.3：防"一架 MiG 咬你、全队放弃 BOSS"的火力涣散；活命第一由带优先级裁决）
const MAX_DEFENDERS := 2

## 常开的操控机防御扫描：把"咬当前操控机"的追击者捞出来指派僚机反咬。
## 与 GUARD_REAR 的差异：①锚=操控机（非长机，切控随迁）②不要求模式开关/长机正在攻击
## ③绕开雷达锥+锁定门（直读 engaging_me 反向索引，追击者常在僚机锥外——log① 病根之一）。
## 距离门/威胁强度统一走 ObjectiveContext §2.3 判据（与面 A 评分同源，防公式漂移）。
## 返回 true = 已指派交战（调用方直接 return）。
static func try_defend_protectee(ai: AIController) -> bool:
	if not ObjectiveContext.enabled or not ai.aircraft.is_player_squad():
		return false
	var protectee: Aircraft = ObjectiveContext.protectee
	if protectee == null or not is_instance_valid(protectee) or protectee.is_destroyed:
		return false
	if protectee.engaging_me.is_empty():
		return false
	if _count_defenders(ai, protectee) >= MAX_DEFENDERS:
		return false
	# 挑最高威胁且未被队友分摊的追击者
	var best: Aircraft = null
	var best_t := 0.0
	for atk in protectee.engaging_me.values():
		if typeof(atk) != TYPE_OBJECT or not is_instance_valid(atk):
			continue
		if not ObjectiveContext.is_survival_threat(atk):
			continue  # 类型门（只对空）+ SURVIVAL_RANGE 距离门 + 存活，全在 §2.3 判据里
		var a: Aircraft = atk
		if a.is_lock_immune():
			continue  # 隐形一致性铁律（spec ace-squadron-tier §3.5）：不可索敌
		if ai._is_target_already_squad_engaged(a):
			continue
		var t := ObjectiveContext.threat01(a)
		if t > best_t:
			best_t = t
			best = a
	if best == null:
		return false
	_enter_autonomous_engage(ai, best, "TACTIC_GUARD_REAR")
	if ai.aircraft.combat_target != best:
		return false  # acquire 被更高优先级拒绝
	EventLogger.log_event("AI_STATE", ai._log_name(),
		"DEFEND protectee → %s" % ai._log_target_name(best))
	return true

## 数小队里已在打"咬操控机者"的僚机（无新增状态字段：按当前目标反查 engaging_me）
static func _count_defenders(ai: AIController, protectee: Aircraft) -> int:
	if not ai.squad:
		return 0
	var n := 0
	for m in ai.squad.members:
		if not is_instance_valid(m) or m.is_destroyed or m == ai.aircraft:
			continue
		var mai: AIController = m._ai_ref
		if mai == null or mai._current_target == null or not is_instance_valid(mai._current_target):
			continue
		if protectee.engaging_me.has(mai._current_target.get_instance_id()):
			n += 1
	return n

# ══════════════════════════════════════════════
#  护卫学说（spec squad-ai-escort §2.2 / §3.1-3.2）—— 目标评分加权
# ══════════════════════════════════════════════

## 本机是否为"护卫编队的僚机"（吃护卫评分）：
## 编队开了护卫学说 + 长机有效 + 自己不是长机（长机不护卫自己，§3.4）。
## 杂兵/散兵编队 escort_doctrine_enabled=false → 返回 false，评分路径全程跳过。
static func is_escort_wingman(ai: AIController) -> bool:
	if not ai.squad or not ai.squad.escort_doctrine_enabled:
		return false
	var leader: Aircraft = ai.squad.leader
	return leader != null and is_instance_valid(leader) and not leader.is_destroyed \
			and leader != ai.aircraft

## 候选敌机的护卫加权（叠加到现有就近/锁定分上）：
##   正在咬长机 → +ATTACKING_LEADER_BONUS（查长机 engaging_me 反向索引，O(1)）
##   威胁紧贴长机 → 按距长机插值 0~LEADER_PROXIMITY_BONUS_MAX
## 零威胁（远离长机且未咬长机）→ 返回 ≈0，自然退回就近交战（护卫优先但不死板）。
static func escort_target_bonus(leader: Aircraft, candidate: Aircraft) -> float:
	if leader == null or candidate == null:
		return 0.0
	var bonus := 0.0
	# 正在攻击长机：engaging_me 以"攻击者 instance_id"为键，O(1) 命中即该敌机在咬长机
	if leader.engaging_me.has(candidate.get_instance_id()):
		bonus += AIController.ATTACKING_LEADER_BONUS
	# 威胁距长机近：近 → 满加权，超出 COVER_SCAN_RANGE → 0
	var d_leader := leader.global_position.distance_to(candidate.global_position)
	var prox := 1.0 - clampf(d_leader / AIController.COVER_SCAN_RANGE, 0.0, 1.0)
	bonus += prox * AIController.LEADER_PROXIMITY_BONUS_MAX
	return bonus

## 进入"自主交战"态（FREE 就近 / GUARD_REAR 后方威胁 共用）：
## 切出编队托管 + 设 combat_target + 转 ENGAGE。tactic_name 仅用于 HUD/日志标签。
static func _enter_autonomous_engage(ai: AIController, tgt: CombatUnit, tactic_name: String) -> void:
	if not ai.acquire_target(tgt, AIController.TargetSource.TS_SCORED, "autonomous engage"):
		return  # 目标被更高优先级来源持有 → 放弃本次自主交战
	ai.aircraft.clear_formation()  # formation_mode/leader/keep_arrival/lod=0/ai_override
	ai.aircraft.ai_override_pursuit = true
	ai._formation_blend = 0.0  # 下次回归编队时从 0 开始混合
	ai.enter_engage_state()
	ai._squad_attacking_leader_target = false
	ai._squad_lateral_role = AIController.SquadRole.NONE
	ai._squad_free_engaging = true  # 小队交战由 leash 约束，不受雷达距脱离
	ai._leader_target_lost_timer = 0.0
	ai.current_tactic_name = tactic_name

## 守后行为（GUARD_REAR 模式 / 自由机互掩 共用）：
##   ① 优先拦后半球空中威胁（scan_leader_rear）；
##   ② 否则打威胁长机的地面防空（scan_leader_threat_ground）—— 默认 PREFER_MISSILE + GROUND_STRAFE 导弹模式
##      会从导弹包络远射，不会贴脸 strafe，避免吃 AA 火力（用户："AA 优先用导弹打掉避免受伤"）。
##   ③ 都没有 → 什么都不做（让 SQUAD_FOLLOW 编队托管继续，僚机守在阵位上盯后方）。
static func _guard_rear_tick(ai: AIController, delta: float) -> void:
	if not ai.enable_combat:
		return
	ai._scan_timer -= delta
	if ai._scan_timer <= 0.0:
		ai._scan_timer = 1.0
		if ai._cooldown_timer <= 0.0:
			var rear_threat := scan_leader_rear(ai)
			if rear_threat:
				_enter_autonomous_engage(ai, rear_threat, "TACTIC_GUARD_REAR")
				EventLogger.log_event("AI_STATE", ai._log_name(),
					"GUARD REAR engage → %s" % ai._log_target_name(rear_threat))
				return
			var ground_threat := scan_leader_threat_ground(ai)
			if ground_threat:
				_enter_autonomous_engage(ai, ground_threat, "TACTIC_GUARD_REAR")
				EventLogger.log_event("AI_STATE", ai._log_name(),
					"GUARD REAR engage GROUND AA → %s" % ai._log_target_name(ground_threat))

## 扫描威胁长机的地面防空（SAM / AAA）——守护者也帮长机拔掉对其构成威胁的地面 AA。
## 范围用 COVER_SCAN_RANGE（AA 能威胁长机所在空域的范围），不限后半球（地面静止，方位无意义）。
## 只挑 SAM/AAGun（真防空威胁）；坦克等非防空不算。已被本队其他僚机盯上的跳过（分摊）。
static func scan_leader_threat_ground(ai: AIController) -> GroundUnit:
	if not ai.squad or not ai.squad.leader:
		return null
	var leader := ai.squad.leader
	var best: GroundUnit = null
	# 范围 = 打地面时放宽到的 leash（SQUAD_LEASH_DIST），保证守护者够得着、不会刚扑上去就被 leash 拽回
	var best_dist := AIController.SQUAD_LEASH_DIST
	for unit in CombatUnit.all_units:
		# 仅防空地面单位（SAM / AAA）才算"威胁长机"
		if not is_instance_valid(unit) or not (unit is SAMUnit or unit is AAGunUnit):
			continue
		var g: GroundUnit = unit as GroundUnit
		if not ai.aircraft.is_hostile_to(g) or g.is_destroyed:
			continue
		if ai._is_target_already_squad_engaged(g):
			continue
		var d := g.global_position.distance_to(leader.global_position)
		if d < best_dist:
			best_dist = d
			best = g
	return best

## 自由机互掩判定（双重攻击学说，spec squad-cohesion §2.3/§3.3）：
## 仅 FOLLOW_LEADER 焦点开火 + 目标是"飞机"(非 BOSS) + 本队 ≥2 架存活自主僚机时，
## 指定 squad_index 最大的那架为"自由机"（不进攻、守后半球）。地面/船/BOSS → 不留掩护(饱和)。
## 瞬态：每 tick 按当前存活成员重算 → 操控切换 / 僚机减员自愈，不写持久属性。
static func _should_be_free_fighter(ai: AIController, target) -> bool:
	if ai.squad_engage_mode != AIController.SquadEngageMode.FOLLOW_LEADER:
		return false
	if not target is Aircraft or _is_boss_target(target):
		return false  # 地面/船/BOSS → 全员饱和，不留自由机
	if not ai.squad:
		return false
	# 自由机 = 存活自主僚机里 squad_index 最大的那架；只 1 架僚机时不留（它得去打）
	var max_idx := -1
	var alive_wingmen := 0
	for m in ai.squad.members:
		if not is_instance_valid(m) or m.is_destroyed or m == ai.squad.leader:
			continue
		var mai: AIController = m._ai_ref
		if mai == null or mai.manual_control:
			continue
		alive_wingmen += 1
		if mai.squad_index > max_idx:
			max_idx = mai.squad_index
	if alive_wingmen < 2:
		return false
	return ai.squad_index == max_idx

## 目标是否为 BOSS（category meta 含 "boss"：F-47 王牌队 / Mother Goose 旗舰+MQ-X 等）
static func _is_boss_target(target) -> bool:
	if not target.has_meta("category"):
		return false
	return String(target.get_meta("category")).contains("boss")

## 扫描长机后半球的"真威胁"——守护者只拦截真正威胁长机后方的敌机，而不是攻击身后任何敌人。
## 威胁判定（二选一即可）：① 正在咬长机（leader.engaging_me，反向索引 O(1)）；
##   ② 正朝长机飞来（approaching：敌机机头指向长机）。只是"在身后远处晃悠、暂不构成威胁"的 → 忽略。
## 范围用 REAR_GUARD_RANGE(≈2.4km, < leash)，让守护者贴着长机守而不飞远（修"守后却去打远处闲敌"）。
## 用 CombatUnit.all_units 共享列表代替 get_parent().get_children() 全树扫描（perf R4）。
static func scan_leader_rear(ai: AIController) -> Aircraft:
	if not ai.squad or not ai.squad.leader:
		return null
	var leader := ai.squad.leader

	var best_threat: Aircraft = null
	var best_score := 0.0  # rear_threat_score 必 > 0 才算威胁

	for unit in CombatUnit.all_units:
		# `not unit` 不能挡 freed 实例（仍 truthy），必须 is_instance_valid（perf R4）
		if not is_instance_valid(unit) or not unit is Aircraft:
			continue
		var ac: Aircraft = unit
		if not ai.aircraft.is_hostile_to(ac) or ac.is_destroyed:
			continue
		# 光学隐形 / 锁定免疫：不可索敌（spec ace-squadron-tier §3.5 隐形一致性铁律）
		if ac.is_lock_immune():
			continue
		# 已被本队其他僚机盯上的后方威胁跳过 → 多架守护者分摊不同威胁，不挤同一个
		if ai._is_target_already_squad_engaged(ac):
			continue

		# ★ 按"攻击长机的准备度"排序，而非最近优先：已咬长机 > 朝长机逼近 > 远处闲晃(=0 跳过)。
		# 修用户反馈："守后时正在/准备攻击长机的飞机加权更高"。同距离 tiebreak 才看贴长机近度。
		var score := rear_threat_score(leader, ac)
		if score <= best_score:
			continue
		best_score = score
		best_threat = ac

	return best_threat

## 后方威胁度评分（守后选定 + 目标选择守后加权 共用，保证两处同源）：
##   返回 [0,1]：0 = 非后方威胁（不在后半球 / 超 REAR_GUARD_RANGE / 既不咬也不逼近）。
##   已咬长机   → 0.7~1.0（按贴长机近度在档内插值）
##   朝长机逼近 → 0.42~0.6
##   → 任一"已咬"必压过任一"逼近"；档内近者优先。
static func rear_threat_score(leader: Aircraft, candidate: Aircraft) -> float:
	if leader == null or candidate == null \
			or not is_instance_valid(leader) or not is_instance_valid(candidate):
		return 0.0
	var to_cand := candidate.global_position - leader.global_position
	var dist := to_cand.length()
	if dist > AIController.REAR_GUARD_RANGE or dist < 1.0:
		return 0.0
	# 必须在长机后半球（与长机航向夹角 > 90°）
	var leader_fwd := Vector2(sin(leader.heading), -cos(leader.heading))
	if absf(leader_fwd.angle_to(to_cand.normalized())) <= PI * 0.5:
		return 0.0
	# 威胁等级：已咬长机 > 朝长机逼近（机头指向长机）> 闲晃(0)
	var threat := 0.0
	if leader.engaging_me.has(candidate.get_instance_id()):
		threat = 1.0
	else:
		var enemy_fwd := Vector2(sin(candidate.heading), -cos(candidate.heading))
		if enemy_fwd.dot((-to_cand).normalized()) > 0.3:
			threat = 0.6
	if threat <= 0.0:
		return 0.0
	var prox := 1.0 - clampf(dist / AIController.REAR_GUARD_RANGE, 0.0, 1.0)
	return threat * (0.7 + 0.3 * prox)

## 小队自由交战：距离扫描最近的敌机（绕开雷达锥 + 锁定门槛）
## 设计理念：把"小队整体的感知"与"单机雷达"解耦——
## 即使敌机在僚机身后或侧面、没触发自身雷达锁定，只要在合理距离内就能被发现。
##
## 距离计算：
##   - flat_altitude=true（生存模式）：用 2D 距离，完全忽略高度差
##     —— 生存模式设计上是"任何高度都能到"，不应让高度差影响目标选择
##   - 否则（沙盒模式）：用 effective_distance_px 3D
static func scan_squad_nearby_enemy(ai: AIController) -> Aircraft:
	# max_range_px 必须严格小于 _process_engage 的脱战阈值 (radar_range * 1.5)。
	var max_range_px := AIController.SQUAD_FREE_SCAN_RANGE
	if ai.aircraft.params:
		max_range_px = minf(max_range_px, ai.aircraft.params.radar_range * AIController.SQUAD_SCAN_RADAR_MULT)
	var use_2d := ai.aircraft.flat_altitude  # 生存模式走 2D
	# 护卫编队僚机：在就近分上叠加护卫加权（§2.2）；杂兵 escort_leader=null → 纯就近（行为不变）。
	# 用就近分 1/d*1000 选最大 ⟺ 选最近，与原 best_dist 纯距离选择对非护卫编队等价。
	var escort_leader: Aircraft = ai.squad.leader if is_escort_wingman(ai) else null
	var best: Aircraft = null
	var best_score := -INF
	for unit in CombatUnit.all_units:
		# `not unit` 不能挡 freed 实例（仍 truthy），必须 is_instance_valid（perf R4）
		if not is_instance_valid(unit) or not unit is Aircraft:
			continue
		var ac: Aircraft = unit
		if not ai.aircraft.is_hostile_to(ac) or ac.is_destroyed:
			continue
		# 光学隐形 / 锁定免疫：不可索敌。⚠ 本扫描刻意绕开雷达锥 + 锁定门槛（见函数注释），
		# 而隐形语义原本只在雷达累积循环里执行 —— 不在这里补门，隐形对小队自由交战完全失效
		# （spec ace-squadron-tier §3.5）
		if ac.is_lock_immune():
			continue
		var d: float
		if use_2d:
			d = ai.aircraft.global_position.distance_to(ac.global_position)
		else:
			d = Aircraft.effective_distance_px(
				ai.aircraft.global_position, ai.aircraft.altitude,
				ac.global_position, ac.altitude
			)
		if d < AIController.SQUAD_FREE_MIN_DIST or d >= max_range_px:
			continue
		# 不追刚被别的僚机盯上的目标：避免 3 架同时扑一个
		if ai._is_target_already_squad_engaged(ac):
			continue
		var score := 1.0 / maxf(d, 100.0) * 1000.0
		if escort_leader != null:
			score += escort_target_bonus(escort_leader, ac)
		# 战场引力三带（spec battlefield-gravity §3.2 共享 helper，与 _score_candidate 同源）：
		# 纯就近选会在"BOSS 成员 1400px / 杂鱼 600px"时选杂鱼——任务/生存候选必须压过纯就近。
		# 本扫描 range ≤1500px（锚近旁），引力衰减/可行性门在此无意义，只叠带加分。
		if ObjectiveContext.enabled and ai.aircraft.is_player_squad():
			score += ObjectiveContext.band_bonus(ac)
		if score > best_score:
			best_score = score
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

## 按 squad_index 分配协同角色：奇数 → 左翼包夹，偶数 → 右翼包夹，3 号 → 高位掩护，
## 4+ 继续左右交替（极少触发，玩家最多 3 僚机）。决定僚机的 pursuit_pos 偏移方向 +
## 是否抬升高度 + 偏好 intent，让 3 架僚机分散在目标周围而不是抢长机的尾后位置。
static func _role_for_squad_index(idx: int) -> int:
	if idx <= 0:
		return AIController.SquadRole.NONE  # 长机或未编队
	if idx == 3:
		return AIController.SquadRole.HIGH_COVER
	# 1, 2, 4, 5... 交替左右
	if idx % 2 == 1:
		return AIController.SquadRole.FLANK_LEFT
	return AIController.SquadRole.FLANK_RIGHT

## 处理齐射倒计时（在 aircraft._update_missile 中每帧调用）
static func process_salvo(ai: AIController, delta: float) -> bool:
	if not ai._salvo_pending:
		return false
	ai._salvo_delay -= delta
	if ai._salvo_delay <= 0.0:
		ai._salvo_pending = false
		return true  # 通知 aircraft 强制发射
	return false
