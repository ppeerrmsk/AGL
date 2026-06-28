class_name TacticalPlanner extends RefCounted

## 战术决策入口 —— 唯一的"选 intent"路径。
##
## 调用约定：
##   var s := Situation.from_aircraft(player)
##   var plan := TacticalPlanner.plan(s, waypoint)  # waypoint 可为 INF
##
## 设计原则：
## 1. **决策树清晰**。每个 if/elif 检查一条几何条件，落到一个 BfmIntent 函数
## 2. **无副作用**。不写 Aircraft / 不读 Node。整个文件都是纯函数
## 3. **武器锁定后置**。intent 函数先按几何选武器，最后由 _apply_weapon_lock 强制覆盖

# ══════════════════════════════════════════════
#  顶层决策
# ══════════════════════════════════════════════

## 战斗 intent 之间的最短保持时间（秒）。
## 防止几何边界附近（如 aspect 89-91° 反复跳）的 intent 高频翻转。
## EVADE_MISSILE / WAYPOINT_MOVE / CRUISE 等不参与 hysteresis（紧急或非战斗，立即响应）
const HYSTERESIS_MIN_HOLD := 0.5

## ── 慢速目标交战（按目标速度决定打法，与武器无关）──
## 问题：快机在角点速度下最小转弯半径 ~ corner²/(g·G)。当目标近乎静止、且交战距离 ≲ 该半径时，
## 快机绕着目标空转（aspect 永远 ~90°，机头带不到目标 → 枪打不准、导弹也对不准）。
## 解法：目标够慢时，过顶/正横（hdg>90°）不绕大圈 WIDE_TURN，而是按距离分流：
##   太近（转不回来）→ 短 extend 拉开间距；有间距 → wide turn 从远处转回。
## 配合"指向接近（hdg<90°）走正常 lead/tail 决策对准开火"形成清晰的 pass-攻击-脱离-重攻循环。
const SLOW_TARGET_SPEED_RATIO := 0.5   ## 目标速度 < 本机角点速度×此值 → 视为"慢速目标"
const SLOW_TARGET_TURN_G := 7.0        ## 估算最小转弯半径用的持续 G（近似）
const SLOW_TARGET_REATTACK_MULT := 1.5 ## 距离 < 最小转弯半径×此值 → 太近，先 extend 拉开
const SLOW_TARGET_EXTEND_SEC := 1.5    ## 慢目标贴脸过顶时的 extend 时长（拉开间距，不要太长以免飞远）

## 参与 hysteresis 的 intent 集合（战斗类）
static func _is_combat_intent(intent_id: int) -> bool:
	match intent_id:
		TacticalPlan.Intent.TAIL_CHASE, TacticalPlan.Intent.CLOSE_TAIL, \
		TacticalPlan.Intent.LEAD_TURN, TacticalPlan.Intent.LEAD_PURSUIT, \
		TacticalPlan.Intent.LAG_PURSUIT, TacticalPlan.Intent.MERGE_PASS, \
		TacticalPlan.Intent.WIDE_TURN, TacticalPlan.Intent.GROUND_STRAFE:
			return true
		_:
			return false

## 重跑指定 intent 的几何（hysteresis 期间用，situation 是当前帧的）
static func _replay_intent(intent_id: int, s: Situation) -> TacticalPlan:
	match intent_id:
		TacticalPlan.Intent.TAIL_CHASE: return BfmIntent.tail_chase(s)
		TacticalPlan.Intent.CLOSE_TAIL: return BfmIntent.close_tail(s)
		TacticalPlan.Intent.LEAD_TURN: return BfmIntent.lead_turn(s)
		TacticalPlan.Intent.LEAD_PURSUIT: return BfmIntent.lead_pursuit(s)
		TacticalPlan.Intent.LAG_PURSUIT: return BfmIntent.lag_pursuit(s)
		TacticalPlan.Intent.MERGE_PASS: return BfmIntent.merge_pass(s)
		TacticalPlan.Intent.WIDE_TURN: return BfmIntent.wide_turn(s)
		TacticalPlan.Intent.GROUND_STRAFE: return BfmIntent.ground_strafe(s)
		_: return BfmIntent.cruise(s)

static func plan(s: Situation, waypoint: Vector2 = Vector2.INF) -> TacticalPlan:
	var fresh: TacticalPlan = _decide(s, waypoint)

	# Hysteresis：战斗 intent 至少持 HYSTERESIS_MIN_HOLD 秒才允许切到不同战斗 intent
	# 例外：相同 intent / 非战斗 intent / 紧急（EVADE）→ 不锁
	if s.prev_intent != -1 \
			and _is_combat_intent(s.prev_intent) \
			and _is_combat_intent(fresh.intent) \
			and fresh.intent != s.prev_intent \
			and s.prev_intent_held_for < HYSTERESIS_MIN_HOLD:
		var held: TacticalPlan = _replay_intent(s.prev_intent, s)
		held.rationale += " | held %.2fs (was %s)" % [
			s.prev_intent_held_for, TacticalPlan.intent_name(fresh.intent)
		]
		return _apply_weapon_lock(s, held)

	return fresh

## 内部决策树（不含 hysteresis）
##
## 优先级阶梯：
## 1. EVADE_MISSILE（紧急覆盖一切）
## 2. EXTEND_RECOVER 残余计时（穿过目标后 2s 强制脱离）
## 3. 无目标 → CRUISE / WAYPOINT_MOVE / PASSIVE_AUTO_FIRE
## 4. 地面 / 水面 → GROUND_STRAFE
## 5. overshoot 检测（dist 极近 + 远离中）→ 触发 EXTEND_RECOVER
## 6. WIDE_TURN（hdg 偏 >90°）
## 7. 对头几何 → MERGE_PASS
## 8. 后半球 → CLOSE_TAIL / TAIL_CHASE / LEAD_TURN
## 9. 侧翼 → LAG_PURSUIT / LEAD_PURSUIT
static func _decide(s: Situation, waypoint: Vector2) -> TacticalPlan:
	# 优先级 1：规避（最高，覆盖所有交战）
	if s.evasion_intent:
		return BfmIntent.evade_missile(s)

	# 优先级 1.5：FEAR debuff —— 飞行员恐慌，立即脱离逃跑
	# 即使没有锁定 / 没被咬尾也强制 EXTEND_RECOVER；hysteresis 不阻塞（EXTEND 不在战斗 intent 集合）
	# 与普通 EXTEND_RECOVER 区别：朝远离目标（玩家方向）的方向逃跑而非沿当前 heading，
	# 避免"feared 还在撞向玩家"的反直觉表现
	# BOSS 攻击手豁免：FEAR 不让 BOSS 脱离（仅吃 stress→精度/SA 衰减），仍走正常决策树
	if s.is_feared and not s.is_boss_attacker:
		var fear_ext := BfmIntent.extend_recover(s)
		if s.has_target:
			var flee_dir: Vector2 = (s.my_pos - s.tgt_pos)
			if flee_dir.length_squared() > 1.0:
				flee_dir = flee_dir.normalized()
				fear_ext.pursuit_pos = s.my_pos + flee_dir * 3000.0 * CombatUnit.PIXELS_PER_METER
		fear_ext.rationale = "FEAR debuff → panic flee"
		return fear_ext

	# 优先级 2：仍在 EXTEND 计时内 → 强制保持脱离
	# （即使重新有目标也不立即接战，让飞机先拉开距离再回头）
	if s.extend_remaining > 0.0:
		var ext := BfmIntent.extend_recover(s)
		ext.rationale += " | extend_remain=%.2fs" % s.extend_remaining
		return ext

	# 优先级 3：无目标
	if not s.has_target:
		if waypoint == Vector2.INF:
			# 被动 auto-fire：雷达锁住敌人 + 开关开 + 有导弹 → 让 salvo 路径自动发
			if s.missile_auto_fire and s.missiles > 0 and s.has_radar_lock \
					and s.weapon_lock != Situation.WEAPON_LOCK_FORCE_GUN:
				return BfmIntent.passive_auto_fire(s)
			return BfmIntent.cruise(s)
		return BfmIntent.waypoint_move(s, waypoint)

	# 优先级 4：水面 / 地面目标 → ground_strafe（max + AB 高速掠过）
	# 包含 GroundUnit（SAM/AAA/雷达站等）和 NavalUnit（舰船）
	if s.tgt_is_surface:
		return _apply_weapon_lock(s, BfmIntent.ground_strafe(s))

	# 优先级 5a：overshoot 检测 — 距离极近 + 正在远离 → 已穿过目标
	if s.dist_m < s.gun_range_m * 0.4 and s.closing_rate_ms < -50.0:
		var ext_trigger := BfmIntent.extend_recover(s)
		ext_trigger.trigger_extend_seconds = 2.0
		ext_trigger.rationale = "overshoot: dist=%.0fm closing=%.0fm/s → 2s EXTEND" % [
			s.dist_m, s.closing_rate_ms
		]
		return ext_trigger

	# 优先级 5b：boom-zoom 触发 — 长时间咬不上尾（能量劣势 / 转弯打不过）
	# 条件：combat intent 持续 >8s 且 aspect 仍在前半球（>80°）→ 拉远重整再战
	# Gladiator 排除：极高攻击欲（aggression > 0.85）的 AI 是设计上"不撤退"的近战机型
	#   （SU27 / F86 等），boom_zoom 会破坏其 commit 风格 → 跳过
	#   玩家飞机无 AIController，默认 ai_aggression=0.5 → 不触发本守卫，正常 BOOM_ZOOM
	if _is_combat_intent(s.prev_intent) and s.prev_intent_held_for > 8.0 \
			and s.aspect_angle_deg > 80.0 \
			and s.ai_aggression <= 0.85:
		var bz_trigger := BfmIntent.extend_recover(s)
		bz_trigger.trigger_extend_seconds = 3.0  # 比 overshoot 长，给充分能量重建
		bz_trigger.intent = TacticalPlan.Intent.BOOM_ZOOM_OUT
		bz_trigger.rationale = "energy disadvantage: held %.1fs aspect=%.0f° → 3s BOOM_ZOOM" % [
			s.prev_intent_held_for, s.aspect_angle_deg
		]
		return bz_trigger

	# ── P5：僚机跟随长机撤离（保持队形完整，避免落单暴露）──
	# 长机进 EXTEND_RECOVER / BOOM_ZOOM_OUT → 同目标的僚机也跟着撤
	# 仅 following_leader_target 触发：自由交战的僚机不打断自己的追击
	if s.is_wingman and s.following_leader_target \
			and (s.leader_intent == TacticalPlan.Intent.EXTEND_RECOVER \
				or s.leader_intent == TacticalPlan.Intent.BOOM_ZOOM_OUT):
		var follow_ext := BfmIntent.extend_recover(s)
		follow_ext.rationale += " | 僚机跟随长机撤离"
		return _apply_weapon_lock(s, follow_ext)

	# 优先级 5.9：慢速空中目标过顶/正横（hdg>90°）—— 别绕大圈空转，按距离分流（与武器无关）
	# 仅拦截 hdg>90° 的"绕圈"病态；hdg<90°（正在指向接近）继续走下面正常决策对准开火。
	if not s.tgt_is_surface and s.heading_diff_to_target_deg > 90.0 \
			and (s.tgt_speed_ms * 3.6) < s.corner_speed_kmh * SLOW_TARGET_SPEED_RATIO:
		var corner_ms: float = s.corner_speed_kmh / 3.6
		var min_turn_r: float = (corner_ms * corner_ms) / (9.81 * SLOW_TARGET_TURN_G)
		if s.dist_m < min_turn_r * SLOW_TARGET_REATTACK_MULT:
			# 太近（半径 > 距离，转不回来）→ 短 extend 拉开间距，下次从远处转回做 pass
			var ext: TacticalPlan = BfmIntent.extend_recover(s)
			ext.trigger_extend_seconds = SLOW_TARGET_EXTEND_SEC
			ext.rationale = "慢目标贴脸过顶 → extend 拉开重攻（绕不动：半径%.0fm vs 距%.0fm）" % [min_turn_r, s.dist_m]
			return _apply_weapon_lock(s, ext)
		# 有间距 → wide turn 从远处转回（机头能带到目标，不空转）
		var wt: TacticalPlan = BfmIntent.wide_turn(s)
		wt.rationale += " | 慢目标远距转回"
		return _apply_weapon_lock(s, wt)

	# 优先级 6：hdg 偏差 >90° — 先把头转回来
	if s.heading_diff_to_target_deg > 90.0:
		return _apply_weapon_lock(s, BfmIntent.wide_turn(s))

	# 优先级 7：对头几何
	if s.head_on_dot > BfmIntent.HEAD_ON_THRESHOLD and s.aim_align > BfmIntent.HEAD_ON_THRESHOLD:
		# 守卫：目标已在急转中（bank > HIGH_BANK_DEG）→ 跳过 MERGE_PASS。
		# MERGE_PASS GUN 模式 max×0.9 直冲过去，对方借急转切到尾位拿尾追枪 → 自杀。
		# 改走 lead_pursuit：减速到 corner_speed + 用 MRM/lead 解决，避免送人头。
		# 典型场景：玩家 F-16 对头 UAV，UAV 已 bank=80° G=6 蛇形（log 2026-05-07 UAV-14）
		if absf(s.tgt_bank_deg) > BfmIntent.HIGH_BANK_DEG:
			var lp := BfmIntent.lead_pursuit(s)
			lp.rationale += " | 替代 MERGE_PASS：目标急转 bank=%.0f°" % s.tgt_bank_deg
			return _apply_weapon_lock(s, lp)
		return _apply_weapon_lock(s, BfmIntent.merge_pass(s))

	# ── P5.5：僚机协同角色（FLANK_LEFT / FLANK_RIGHT / HIGH_COVER）──
	# 角色由 squad_coordination 在进入 TEAM_ATTACK 时按 squad_index 分配，全程稳定不抖动
	# 仅在中远距生效；近距（< gun_range × 1.2）回退到下面的常规几何决策避免抢长机尾位/误伤
	if s.is_wingman and s.following_leader_target and s.squad_role != AIController.SquadRole.NONE \
			and s.dist_m > s.gun_range_m * 1.2 and not s.tgt_is_surface:
		match s.squad_role:
			AIController.SquadRole.FLANK_LEFT:
				return _apply_weapon_lock(s, BfmIntent.flank_cutoff(s, -1.0))
			AIController.SquadRole.FLANK_RIGHT:
				return _apply_weapon_lock(s, BfmIntent.flank_cutoff(s, 1.0))
			AIController.SquadRole.HIGH_COVER:
				return _apply_weapon_lock(s, BfmIntent.high_cover(s))

	# 优先级 8：后半球
	if s.in_rear_hemisphere:
		if s.aim_align > BfmIntent.TAIL_AIM_THRESHOLD:
			# 已对准尾后
			# ── 后半球僚机角色未触发（近距 / 无 role）的退路：保留旧的奇偶 LAG/LEAD 互补
			# 让长机占尾后位置，僚机从内圈/侧翼包夹，避免 wingmen 抢尾位
			if s.is_wingman and s.following_leader_target \
					and s.squad_role == AIController.SquadRole.NONE \
					and (s.leader_intent == TacticalPlan.Intent.TAIL_CHASE \
						or s.leader_intent == TacticalPlan.Intent.CLOSE_TAIL):
				var support_plan: TacticalPlan
				if s.squad_index % 2 == 1:
					support_plan = BfmIntent.lag_pursuit(s)
					support_plan.rationale += " | 僚机#%d 互补 LAG（长机占尾）" % s.squad_index
				else:
					support_plan = BfmIntent.lead_pursuit(s)
					support_plan.rationale += " | 僚机#%d 互补 LEAD（长机占尾）" % s.squad_index
				return _apply_weapon_lock(s, support_plan)
			if s.dist_m > s.gun_range_m * BfmIntent.GUN_RANGE_HYSTERESIS:
				return _apply_weapon_lock(s, BfmIntent.close_tail(s))
			else:
				return _apply_weapon_lock(s, BfmIntent.tail_chase(s))
		else:
			# 后半球但未对准 → 抢六点
			return _apply_weapon_lock(s, BfmIntent.lead_turn(s))

	# 优先级 9：前半球 / 侧翼
	# lag pursuit 触发：目标急转 + 距离够近能感知到圆周（< gun_range × 3）
	if absf(s.tgt_bank_deg) > BfmIntent.HIGH_BANK_DEG \
			and s.dist_m < s.gun_range_m * 3.0 \
			and s.aspect_angle_deg > 60.0 and s.aspect_angle_deg < 130.0:
		return _apply_weapon_lock(s, BfmIntent.lag_pursuit(s))

	# 默认：lead pursuit
	return _apply_weapon_lock(s, BfmIntent.lead_pursuit(s))

# ══════════════════════════════════════════════
#  武器锁定覆盖（玩家意图最终拍板）
# ══════════════════════════════════════════════

## 应用 weapon_lock + charge_intent 对 plan.weapon_mode / allow_missile_fire 的强制覆盖
static func _apply_weapon_lock(s: Situation, p: TacticalPlan) -> TacticalPlan:
	# 双击冲锋 = 强制机炮（覆盖 weapon_lock）
	if s.charge_intent:
		p.weapon_mode = TacticalPlan.WeaponMode.GUN
		p.allow_missile_fire = false
		p.rationale += " | charge:force-gun"
		return p

	# 玩家显式锁机炮
	if s.weapon_lock == Situation.WEAPON_LOCK_FORCE_GUN:
		p.weapon_mode = TacticalPlan.WeaponMode.GUN
		p.allow_missile_fire = false
		p.rationale += " | lock:force-gun"
		return p

	# 玩家显式锁导弹（暂留接口，UI 层未实现）
	if s.weapon_lock == Situation.WEAPON_LOCK_FORCE_MISSILE:
		p.weapon_mode = TacticalPlan.WeaponMode.MISSILE
		p.allow_gun_fire = false
		p.rationale += " | lock:force-missile"
		return p

	return p
