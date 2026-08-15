class_name BFMTactics
extends RefCounted

## BFM 战术子系统（静态工具类）
## 从 ai_controller.gd 提取的态势评估 / 决策树 / 8 种战术执行器 / 高度速度辅助。
##
## 状态仍住在 AIController（_tactic / _yoyo_phase / _break_phase / _scissors_* /
## _lufberry_* / _gun_jink_* / _defensive_time 等）。本模块不持有状态，只在 ai 上读写。
##
## 类型引用保留在 AIController：
##   AIController.SituationData / AIController.EngageTactic / AIController.TACTIC_DISPLAY_NAME
##
## 调用约定（来自 ai_controller.gd _process_engage）：
##   var sit := BFMTactics.assess_situation(self)
##   BFMTactics.update_lufberry_detection(self, sit, delta)
##   BFMTactics.choose_tactic(self, sit)
##   BFMTactics.execute_<tactic>(self, sit [, delta])
##   BFMTactics.update_gun_jink(self, sit, delta)

# ══════════════════════════════════════════════
#  态势评估
# ══════════════════════════════════════════════

static func assess_situation(ai: AIController) -> AIController.SituationData:
	var s := AIController.SituationData.new()
	s.my_pos = ai.aircraft.global_position
	s.tgt_pos = ai._current_target.global_position
	# 扁平模式：纯2D距离（战斗不受高度限制）；否则含高度的有效距离
	if ai.aircraft.flat_altitude:
		s.dist_px = s.my_pos.distance_to(s.tgt_pos)
	else:
		s.dist_px = Aircraft.effective_distance_px(s.my_pos, ai.aircraft.altitude, s.tgt_pos, ai._current_target.altitude)
	s.to_target = (s.tgt_pos - s.my_pos).normalized()

	s.tgt_fwd = Vector2(sin(ai._current_target.heading), -cos(ai._current_target.heading))
	s.my_fwd = Vector2(sin(ai.aircraft.heading), -cos(ai.aircraft.heading))

	s.my_speed = ai.aircraft.speed
	s.tgt_speed = ai._current_target.speed
	s.speed_ratio = s.my_speed / maxf(s.tgt_speed, 1.0)

	var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
	var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER

	# 闭合率
	s.closing_rate = s.my_fwd.dot(s.to_target) * my_speed_px - s.tgt_fwd.dot(s.to_target) * tgt_speed_px

	# 我在敌机的偏置角（aspect angle）
	var to_me := (s.my_pos - s.tgt_pos).normalized()
	s.aspect_angle = acos(clampf(-s.tgt_fwd.dot(to_me), -1.0, 1.0))
	s.in_rear_hemi = s.aspect_angle < deg_to_rad(90.0)

	# 敌机在我的攻击角（AOT）
	var to_enemy := (s.tgt_pos - s.my_pos).normalized()
	s.my_aot = acos(clampf(s.my_fwd.dot(to_enemy), -1.0, 1.0))

	# 敌机是否在我的后半球
	s.enemy_in_my_rear = s.my_aot > deg_to_rad(90.0)

	# 高度差
	s.alt_diff = ai.aircraft.altitude - ai._current_target.altitude

	# 机炮射程
	s.gun_range_px = 150.0
	if ai.aircraft.params and ai.aircraft.params.gun:
		s.gun_range_px = ai.aircraft.effective_gun_range_m() * Aircraft.PIXELS_PER_METER

	# 迎头判定：双方都面朝对方（aspect > 120° 且 my_aot < 60°）
	s.is_head_on = s.aspect_angle > deg_to_rad(120.0) and s.my_aot < deg_to_rad(60.0) and s.closing_rate > 0

	return s

# ══════════════════════════════════════════════
#  拉弗伯雷圆圈（mutual orbit）检测与脱出
# ══════════════════════════════════════════════

## 每帧更新拉弗伯雷检测：双方近距互绕超时则强制切换战术脱出
static func update_lufberry_detection(ai: AIController, s: AIController.SituationData, delta: float) -> void:
	if ai._lufberry_cooldown > 0.0:
		ai._lufberry_cooldown -= delta

	var close_range := s.gun_range_px * AIController.LUFBERRY_CLOSE_MULT
	# 条件：近距 + 双方都不在对方后半球 + 都有一定偏置角 → 互绕中
	if s.dist_px < close_range and not s.in_rear_hemi and not s.enemy_in_my_rear \
			and s.my_aot > deg_to_rad(30.0) and s.aspect_angle > deg_to_rad(30.0) \
			and ai._lufberry_cooldown <= 0.0:
		ai._lufberry_timer += delta
	else:
		ai._lufberry_timer = maxf(ai._lufberry_timer - delta * 2.0, 0.0)

	var lufberry_threshold := lerpf(AIController.LUFBERRY_THRESH_MIN, AIController.LUFBERRY_THRESH_MAX, 1.0 - ai._effective_skill())
	if ai._lufberry_timer > lufberry_threshold:
		ai._lufberry_timer = 0.0
		ai._lufberry_cooldown = AIController.LUFBERRY_COOLDOWN
		var new_tactic: AIController.EngageTactic
		if ai.aggression > 0.5 or ai._effective_self_preservation() < 0.4:
			new_tactic = AIController.EngageTactic.HIGH_YOYO
		else:
			new_tactic = AIController.EngageTactic.EXTENSION
		if new_tactic != ai._tactic:
			apply_new_tactic(ai, new_tactic)

# ══════════════════════════════════════════════
#  战术选择决策树
# ══════════════════════════════════════════════

static func choose_tactic(ai: AIController, s: AIController.SituationData) -> void:
	# ── §3 FEAR panic：玩家技能强加 FEAR 时，AI 强制 EXTENSION（脱离） ──
	# 不动 _current_target（玩家追得上），只换战术 → 视觉反馈"敌人转身就跑"
	# FEAR 自然衰减（StatusEffects.tick）后，下次 choose_tactic 自动恢复
	# BOSS 攻击手豁免：FEAR 仍生效（stress=1.0 → 失误/SA 衰减/精度下降），但不会脱离
	# 战区目标 (zone_air) 豁免：仅"发呆平飞"，不脱离不加速，避免任务变成无解追逃
	if ai.aircraft and ai.aircraft.status_fear_active and not ai.is_boss_attacker():
		if ai.aircraft.get_meta("category", "") == "zone_air":
			_apply_fear_daze(ai)
			return
		if ai._tactic != AIController.EngageTactic.EXTENSION:
			apply_new_tactic(ai, AIController.EngageTactic.EXTENSION)
		return

	# ── 优先级 0：机头对准型武器（电磁炮 / 激光剑等）→ SNIPER_HOLD 取代 LEAD_PURSUIT ──
	# 适用条件：敌机在前半球（my_aot < 80°），不太近（避免冲过去），不在后半球被咬
	# 不满足 → 走下方常规 BFM（如 LEAD_TURN 转身、BREAK_TURN 防御）
	var _hm_tactic: HerbstManeuver = ai.aircraft.get_herbst()
	var in_counterattack := _hm_tactic and _hm_tactic.counterattack_timer > 0.0
	if ai.prefer_nose_aligned_weapon and not in_counterattack:
		var tgt_in_front: bool = s.my_aot < deg_to_rad(80.0)
		var not_too_close: bool = s.dist_px > s.gun_range_px * 0.8
		var not_being_chased: bool = not s.enemy_in_my_rear
		if tgt_in_front and not_too_close and not_being_chased:
			if ai._tactic != AIController.EngageTactic.SNIPER_HOLD:
				apply_new_tactic(ai, AIController.EngageTactic.SNIPER_HOLD)
			return
		# 不在条件内 → 让步给常规 BFM 处理（转身/防御等）

	# ── BVR 狙击模式：只用 EXTENSION 或 LEAD_PURSUIT（远距），不选近距战术 ──
	# 反击窗口中则跳过此限制，允许近距战术
	if ai.bvr_only and not in_counterattack:
		if s.dist_px < s.gun_range_px * AIController.BVR_CLOSE_MULT:
			# 太近了，强制脱离
			if ai._tactic != AIController.EngageTactic.EXTENSION:
				apply_new_tactic(ai, AIController.EngageTactic.EXTENSION)
		else:
			# 远距保持 LEAD_PURSUIT（导弹追踪）
			if ai._tactic != AIController.EngageTactic.LEAD_PURSUIT:
				apply_new_tactic(ai, AIController.EngageTactic.LEAD_PURSUIT)
		return

	# ── 优先级 0.5：FEAR debuff → 强制 EXTENSION 逃跑 ──
	# 玩家"震慑射击 / 惊鸿扩散"等技能注入；此优先级在 BVR/SNIPER 之后、常规 BFM 决策之前
	# BOSS 攻击手豁免：仅吃 stress 副作用（精度/SA 下降），不会脱离玩家
	# 战区目标 (zone_air) 豁免：仅"发呆平飞"
	if ai.aircraft.status_fear_active and not ai.is_boss_attacker():
		if ai.aircraft.get_meta("category", "") == "zone_air":
			_apply_fear_daze(ai)
			return
		if ai._tactic != AIController.EngageTactic.EXTENSION:
			apply_new_tactic(ai, AIController.EngageTactic.EXTENSION)
		return

	var new_tactic := ai._tactic
	var close_range := s.gun_range_px * AIController.TACTIC_CLOSE_MULT
	var mid_range := s.gun_range_px * AIController.TACTIC_MID_MULT
	var aggression_factor := ai.aggression  # 0~1

	var esp := ai._effective_self_preservation()

	# ── 0. 高自保 + 意识到被锁定：即使没被咬尾也可能切防御 ──
	if ai.personality.lock_aware and esp > 0.6 and not s.enemy_in_my_rear:
		if esp > 0.85:
			new_tactic = AIController.EngageTactic.EXTENSION
		elif esp > 0.7:
			new_tactic = AIController.EngageTactic.BREAK_TURN

	# ── 1. 被咬尾检测（需要态势感知"看到"后方威胁） ──
	# 如果飞行员没有意识到后方威胁，会继续当前战术（致命失误）
	elif s.enemy_in_my_rear and s.dist_px < mid_range and ai.personality.rear_threat_aware:
		# 低自保飞行员被咬尾也可能反转迎头
		if esp < 0.3 and s.dist_px > close_range:
			new_tactic = AIController.EngageTactic.LEAD_TURN
		elif ai.aircraft.hp < ai.aircraft.params.max_hp * AIController.HEALTH_EXTEND_THRESH or s.speed_ratio < AIController.SPEED_EXTEND_THRESH:
			new_tactic = AIController.EngageTactic.EXTENSION
		elif ai._defensive_time > AIController.DEFENSIVE_COUNTER_TIME:
			if aggression_factor > AIController.AGGRESSION_COUNTER_THRESH and esp < 0.6:
				new_tactic = AIController.EngageTactic.LEAD_TURN
				ai._defensive_time = 0.0
			else:
				new_tactic = AIController.EngageTactic.EXTENSION
				ai._defensive_time = 0.0
		elif s.dist_px < close_range and s.my_speed < AIController.SCISSORS_LOW_SPEED and s.tgt_speed < AIController.SCISSORS_LOW_SPEED:
			new_tactic = AIController.EngageTactic.SCISSORS
		else:
			# 急转防御
			new_tactic = AIController.EngageTactic.BREAK_TURN

	# ── 2. 迎头接近 ──
	elif s.is_head_on:
		new_tactic = AIController.EngageTactic.LEAD_TURN

	# ── 3. 我在敌后半球（进攻位置） ──
	elif s.in_rear_hemi:
		if s.closing_rate > AIController.CR_HIGHYOYO_CLOSE and s.dist_px < close_range:
			# 闭合率过高 + 近距 → 高悠悠防冲过
			new_tactic = AIController.EngageTactic.HIGH_YOYO
		elif s.closing_rate > AIController.CR_LAG_PURSUIT and s.dist_px < mid_range and s.speed_ratio > AIController.SPEED_RATIO_LAG:
			# 闭合但速度优势明显 → 滞后追踪
			new_tactic = AIController.EngageTactic.LAG_PURSUIT
		elif s.dist_px > mid_range and s.closing_rate < AIController.CR_LOWYOYO_FAR:
			# 远距离 + 闭合慢 → 低悠悠加速
			new_tactic = AIController.EngageTactic.LOW_YOYO
		else:
			# 正常追踪
			new_tactic = AIController.EngageTactic.LEAD_PURSUIT

	# ── 4. 侧面/其他位置 ──
	else:
		if s.dist_px > mid_range:
			new_tactic = AIController.EngageTactic.LEAD_PURSUIT
		elif s.dist_px < close_range and s.closing_rate > AIController.CR_HIGHYOYO_SIDE:
			new_tactic = AIController.EngageTactic.HIGH_YOYO
		elif s.dist_px > mid_range * AIController.MID_RANGE_LOWYOYO and s.closing_rate < AIController.CR_LOWYOYO_SIDE:
			new_tactic = AIController.EngageTactic.LOW_YOYO
		else:
			new_tactic = AIController.EngageTactic.LEAD_PURSUIT

	# BOSS 攻击手：禁逃跑 + 远距离只允许直追（不做能量管理花式机动）
	if ai.is_boss_attacker():
		if new_tactic == AIController.EngageTactic.EXTENSION:
			new_tactic = AIController.EngageTactic.LEAD_PURSUIT
		# 远距离（> 2000px ≈ 4km）时只允许 LEAD/LAG_PURSUIT，禁止 LOW_YOYO/HIGH_YOYO/SCISSORS
		# 这些能量管理战术不直接闭合距离，BOSS 应该先赶回来再做机动
		elif s.dist_px > 2000.0:
			if new_tactic in [AIController.EngageTactic.LOW_YOYO, AIController.EngageTactic.HIGH_YOYO,
					AIController.EngageTactic.SCISSORS, AIController.EngageTactic.BREAK_TURN]:
				new_tactic = AIController.EngageTactic.LEAD_PURSUIT

	# 激进度调整：激进 AI 更倾向进攻战术
	if aggression_factor > 0.7:
		if new_tactic == AIController.EngageTactic.EXTENSION and ai.aircraft.hp > ai.aircraft.params.max_hp * AIController.HEALTH_AGGRESSIVE_EXTEND:
			new_tactic = AIController.EngageTactic.BREAK_TURN

	# ── 决策失误：有概率选到次优战术 ──
	var eff := ai._effective_skill()
	var mistake_chance := (1.0 - eff) * AIController.MAX_MISTAKE_CHANCE  # 最高 15% 失误率
	if randf() < mistake_chance and new_tactic != ai._tactic:
		new_tactic = make_mistake(ai, new_tactic)

	if new_tactic != ai._tactic:
		apply_new_tactic(ai, new_tactic)

## 应用新战术并重置相关状态
static func apply_new_tactic(ai: AIController, new_tactic: AIController.EngageTactic) -> void:
	var eff := ai._effective_skill()
	var old_tactic := ai._tactic
	ai._prev_tactic = ai._tactic
	ai._tactic = new_tactic
	ai._tactic_timer = 0.0
	ai._yoyo_phase = 0
	if ai.aircraft:
		ai.aircraft.show_tactic_popup(AIController.TACTIC_DISPLAY_NAME.get(ai._tactic, ""))
	EventLogger.log_event("TACTIC", ai._log_name(),
		"%s → %s (target=%s, stress=%.2f, skill_eff=%.2f)" % [
			AIController.TACTIC_DISPLAY_NAME.get(old_tactic, "?"),
			AIController.TACTIC_DISPLAY_NAME.get(ai._tactic, "?"),
			ai._log_target_name(ai._current_target),
			ai.personality.stress, eff])

	var reaction_mult := 1.0 + (1.0 - eff) * 1.0
	match ai._tactic:
		AIController.EngageTactic.LEAD_PURSUIT:
			ai._tactic_min_duration = AIController.MIN_DUR_LEAD_PURSUIT * reaction_mult
		AIController.EngageTactic.LAG_PURSUIT:
			ai._tactic_min_duration = AIController.MIN_DUR_LAG_PURSUIT * reaction_mult
		AIController.EngageTactic.LEAD_TURN:
			ai._tactic_min_duration = AIController.MIN_DUR_LEAD_TURN * reaction_mult
		AIController.EngageTactic.HIGH_YOYO:
			ai._tactic_min_duration = AIController.MIN_DUR_HIGH_YOYO * reaction_mult
			ai._yoyo_base_alt = ai.aircraft.altitude
		AIController.EngageTactic.LOW_YOYO:
			ai._tactic_min_duration = AIController.MIN_DUR_LOW_YOYO * reaction_mult
			ai._yoyo_base_alt = ai.aircraft.altitude
		AIController.EngageTactic.BREAK_TURN:
			ai._tactic_min_duration = AIController.MIN_DUR_BREAK_TURN * reaction_mult
			ai._break_phase = 0
		AIController.EngageTactic.EXTENSION:
			ai._tactic_min_duration = AIController.MIN_DUR_EXTENSION * reaction_mult
			ai._extension_start_pos = ai.aircraft.global_position
		AIController.EngageTactic.SCISSORS:
			ai._tactic_min_duration = AIController.MIN_DUR_SCISSORS * reaction_mult
			ai._scissors_side = 1.0
			ai._scissors_reverse_timer = 0.0

	ai.personality.alt_error = randf_range(-1.0, 1.0) * (1.0 - eff) * AIController.ALTITUDE_ERROR_AMP

## 决策失误：返回一个"次优"战术替代正确选择
static func make_mistake(ai: AIController, correct: AIController.EngageTactic) -> AIController.EngageTactic:
	# 每种正确战术对应的常见失误
	match correct:
		AIController.EngageTactic.HIGH_YOYO:
			# 该防冲过时继续追 → 冲过
			return AIController.EngageTactic.LEAD_PURSUIT
		AIController.EngageTactic.LAG_PURSUIT:
			# 该控制节奏时莽冲
			return AIController.EngageTactic.LEAD_PURSUIT
		AIController.EngageTactic.LOW_YOYO:
			# 该加速闭合时选了保守跟踪
			return AIController.EngageTactic.LAG_PURSUIT
		AIController.EngageTactic.BREAK_TURN:
			# 该急转时慌了选剪刀（犹豫不决）
			return AIController.EngageTactic.SCISSORS if randf() > 0.5 else AIController.EngageTactic.EXTENSION
		AIController.EngageTactic.EXTENSION:
			# 该跑时却转向（不甘心）
			return AIController.EngageTactic.BREAK_TURN
		AIController.EngageTactic.LEAD_TURN:
			# 该提前转时直冲（没有战术意识）
			return AIController.EngageTactic.LEAD_PURSUIT
		AIController.EngageTactic.SCISSORS:
			# 该剪刀时选了脱离（太慌张）
			return AIController.EngageTactic.EXTENSION
		_:
			return correct

# ══════════════════════════════════════════════
#  战术执行
# ══════════════════════════════════════════════

## 前置追踪：瞄准敌机前方，积极闭合距离
static func execute_lead_pursuit(ai: AIController, s: AIController.SituationData) -> void:
	var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
	var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER

	# 复用距离+速度感知的动态追踪（远距直追→中距过渡→近距战术）
	var pursuit_pos := ai.aircraft._choose_dogfight_pursuit_pos(
			s.my_pos, s.dist_px, s.tgt_pos, s.tgt_fwd,
			tgt_speed_px, my_speed_px, s.in_rear_hemi)

	ai.aircraft.target_position = ai._apply_position_error(pursuit_pos)
	# 远距（导弹区）保自身作战高度，近距（机炮区）匹配敌机
	if s.dist_px > s.gun_range_px * 3.0:
		use_combat_altitude(ai)
	else:
		match_target_altitude(ai)
	set_engage_speed(ai, s, 1.2)

## 滞后追踪：瞄准敌机后方，防止冲过，保持后半球位置
static func execute_lag_pursuit(ai: AIController, s: AIController.SituationData) -> void:
	# 性格偏移：斗士贴近六点钟(0.18)，骑士保持距离(0.45)
	var lag_offset := maxf(AIController.LAG_OFFSET_MIN, s.gun_range_px * ai._cb().six_oclock_offset_ratio)
	var pursuit_pos := s.tgt_pos - s.tgt_fwd * lag_offset

	ai.aircraft.target_position = ai._apply_position_error(pursuit_pos)
	match_target_altitude(ai)

	# 匹配敌机速度，略低以防冲过
	var target_speed_kmh := ai._current_target.speed * 3.6 * AIController.LAG_SPEED_RATIO
	ai.aircraft.target_speed_kmh = ai._apply_speed_error(clampf(target_speed_kmh,
		AIController.LAG_MIN_SPEED, AircraftPhysics.effective_max_speed_kmh(ai.aircraft)))

## 提前转弯：迎头接近时提前转向敌机飞行路径后方
static func execute_lead_turn(ai: AIController, s: AIController.SituationData) -> void:
	var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER

	var pass_time := s.dist_px / maxf(s.closing_rate + AIController.LEAD_TURN_CLOSING_ADJ, 100.0)
	var future_tgt_pos := s.tgt_pos + s.tgt_fwd * tgt_speed_px * pass_time
	# 性格偏移：六点钟偏移 × 1.2（lead_turn 天然比 lag 更远一些）
	var six_pos := future_tgt_pos - s.tgt_fwd * maxf(AIController.LEAD_TURN_SIXOCLOCK_MIN, s.gun_range_px * ai._cb().six_oclock_offset_ratio * AIController.LEAD_TURN_SIXOCLOCK_MULT)

	ai.aircraft.target_position = ai._apply_position_error(six_pos)
	# Lead turn 是迎头/侧前的中远距过渡：默认保自身作战高度，
	# 距离已进机炮区时才匹配（防止冲到 merge 还在错档）
	if s.dist_px > s.gun_range_px * 3.0:
		use_combat_altitude(ai)
	else:
		match_target_altitude(ai)
	set_engage_speed(ai, s, 1.0)

## 高悠悠：拉高减速防止冲过，然后俯冲回来继续追踪
static func execute_high_yoyo(ai: AIController, s: AIController.SituationData, delta: float) -> void:
	if ai._yoyo_phase == 0:
		# 阶段0：拉高
		if ai.aircraft.flat_altitude:
			# 扁平模式：切到上一档
			ai.aircraft.set_target_tier(ai.aircraft.tier_above())
		else:
			# 性格偏移：斗士爬升幅度小(600m)，骑士爬升高(1000m)
			var climb_height := ai._cb().climb_brake_height
			var climb_target := ai._yoyo_base_alt + ai._apply_altitude_error(climb_height)
			if ai.aircraft.params:
				climb_target = clampf(climb_target, ai._yoyo_base_alt + AIController.HIGH_YOYO_CLIMB_MIN, ai.aircraft.params.max_altitude - AIController.ALTITUDE_MATCH_THRESH)
			ai.aircraft.target_altitude = climb_target

		var lag_pos := s.tgt_pos - s.tgt_fwd * s.gun_range_px * AIController.HIGH_YOYO_LAG_RATIO
		ai.aircraft.target_position = ai._apply_position_error(lag_pos)

		# 性格偏移：斗士减速更猛(0.80)，骑士保速(0.90)
		ai.aircraft.target_speed_kmh = ai._apply_speed_error(ai._current_target.speed * 3.6 * ai._cb().dive_speed_ratio)

		if ai.aircraft.flat_altitude:
			# 扁平模式：到达目标档位即切阶段
			if ai.aircraft.get_altitude_tier() >= ai.aircraft.target_altitude_tier or ai._tactic_timer > 4.0:
				ai._yoyo_phase = 1
		else:
			if ai.aircraft.altitude >= ai.aircraft.target_altitude - 100.0 or ai._tactic_timer > 4.0:
				ai._yoyo_phase = 1
	else:
		# 阶段1：俯冲回来
		match_target_altitude(ai)
		var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		var lead_time := clampf(s.dist_px / maxf(my_speed_px, 50.0), AIController.HIGH_YOYO_LEAD_MIN, AIController.HIGH_YOYO_LEAD_MAX)
		ai.aircraft.target_position = ai._apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * lead_time)
		set_engage_speed(ai, s, 1.1)

		if ai.aircraft.flat_altitude:
			if ai.aircraft.get_altitude_tier() == ai._current_target.get_altitude_tier():
				ai._tactic_timer = ai._tactic_min_duration
		else:
			if absf(ai.aircraft.altitude - ai._current_target.altitude) < 200.0:
				ai._tactic_timer = ai._tactic_min_duration

## 低悠悠：俯冲加速缩短距离，再拉高攻击
static func execute_low_yoyo(ai: AIController, s: AIController.SituationData, delta: float) -> void:
	if ai._yoyo_phase == 0:
		# 阶段0：俯冲加速
		if ai.aircraft.flat_altitude:
			# 扁平模式：切到下一档
			ai.aircraft.set_target_tier(ai.aircraft.tier_below())
		else:
			# 性格偏移：斗士俯冲更深(1500m)，骑士浅俯冲(800m)
			var dive_target := ai._yoyo_base_alt - ai._apply_altitude_error(ai._cb().dive_depth)
			if ai.aircraft.params:
				dive_target = clampf(dive_target, ai._cb().dive_floor, ai._yoyo_base_alt - 200.0)
			ai.aircraft.target_altitude = dive_target

		var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		var lead_time := clampf(s.dist_px / maxf(my_speed_px, 50.0), AIController.LOW_YOYO_LEAD_MIN, AIController.LOW_YOYO_LEAD_MAX)
		ai.aircraft.target_position = ai._apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * lead_time)

		# 性格偏移：骑士俯冲加速更猛，斗士稍温和
		set_engage_speed(ai, s, 1.2 + ai._cb().approach_speed_mult * AIController.LOW_YOYO_APPROACH_SCALE)

		if ai.aircraft.flat_altitude:
			if ai.aircraft.get_altitude_tier() <= ai.aircraft.target_altitude_tier or ai._tactic_timer > 4.0:
				ai._yoyo_phase = 1
		else:
			if ai.aircraft.altitude <= ai.aircraft.target_altitude + 100.0 or ai._tactic_timer > 4.0:
				ai._yoyo_phase = 1
	else:
		# 阶段1：拉高回到敌机高度
		match_target_altitude(ai)
		var my_speed_px := s.my_speed * Aircraft.PIXELS_PER_METER
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		var lead_time := clampf(s.dist_px / maxf(my_speed_px, 50.0), AIController.LOW_YOYO_CLIMB_LEAD_MIN, AIController.LOW_YOYO_CLIMB_LEAD_MAX)
		ai.aircraft.target_position = ai._apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * lead_time)
		set_engage_speed(ai, s, 1.1)

		if ai.aircraft.flat_altitude:
			if ai.aircraft.get_altitude_tier() == ai._current_target.get_altitude_tier():
				ai._tactic_timer = ai._tactic_min_duration
		else:
			if absf(ai.aircraft.altitude - ai._current_target.altitude) < 200.0:
				ai._tactic_timer = ai._tactic_min_duration

## 急转脱离：被咬尾时急转增大偏置角，然后反转迎头
## Shaw 原则：Break Turn 是初始防御，之后必须反转或脱离，不能一直平转
static func execute_break_turn(ai: AIController, s: AIController.SituationData) -> void:
	if ai._break_phase == 0 and ai._tactic_timer < 2.0:
		# 阶段0（前2秒）：急转垂直于威胁方向，建立偏置角
		var threat_dir := (ai.aircraft.global_position - s.tgt_pos).normalized()
		var perp_a := Vector2(threat_dir.y, -threat_dir.x)
		var perp_b := Vector2(-threat_dir.y, threat_dir.x)

		var heading_a := atan2(perp_a.x, -perp_a.y)
		var heading_b := atan2(perp_b.x, -perp_b.y)
		var diff_a := absf(AIController._angle_diff(heading_a, ai.aircraft.heading))
		var diff_b := absf(AIController._angle_diff(heading_b, ai.aircraft.heading))
		var chosen_dir := perp_a if diff_a < diff_b else perp_b

		ai.aircraft.target_position = ai._apply_position_error(ai.aircraft.global_position + chosen_dir * AIController.BREAK_TURN_DIST)

		if ai.aircraft.flat_altitude:
			pass  # 扁平模式：急转时保持当前档位
		elif ai.aircraft.altitude > 3000.0:
			ai.aircraft.target_altitude = ai.aircraft.altitude - AIController.BREAK_TURN_ALT_REDUCE
		else:
			ai.aircraft.target_altitude = ai.aircraft.altitude

		set_engage_speed(ai, s, 1.0)
	else:
		# 阶段1（2秒后）：反转迎头
		ai._break_phase = 1
		var tgt_speed_px := s.tgt_speed * Aircraft.PIXELS_PER_METER
		ai.aircraft.target_position = ai._apply_position_error(s.tgt_pos + s.tgt_fwd * tgt_speed_px * AIController.BREAK_TURN_COUNTER_LEAD)
		match_target_altitude(ai)
		set_engage_speed(ai, s, AIController.BREAK_TURN_COUNTER_SPEED)

## 战区目标 FEAR 豁免：发呆平飞（保持 heading + cruise + 禁加力 + 不爬升）
## 不切 _tactic，FEAR 衰减后下次 choose_tactic 自动回到原战术决策树
static func _apply_fear_daze(ai: AIController) -> void:
	var fwd := Vector2(sin(ai.aircraft.heading), -cos(ai.aircraft.heading))
	ai.aircraft.target_position = ai.aircraft.global_position + fwd * 1500.0
	ai.aircraft.target_altitude = ai.aircraft.altitude
	if ai.aircraft.params:
		ai.aircraft.target_speed_kmh = AircraftPhysics.effective_cruise_speed_kmh(ai.aircraft)
	ai.aircraft.is_afterburner = false

## 加速脱离：远离敌机拉开距离
static func execute_extension(ai: AIController, s: AIController.SituationData) -> void:
	var away_dir := (ai.aircraft.global_position - s.tgt_pos).normalized()

	# FEAR 守卫：恐慌时 away_dir 几乎总指向"远离玩家"，玩家在敌机后方追击 →
	# away_dir 多半指向地图外。距边 ≤3km 时把 away_dir 朝地图中心 lerp，避免飞出战场
	var feared := ai.aircraft.status_fear_active
	if feared:
		var pos_for_bound := ai.aircraft.global_position
		var edge_dist := MapBoundary.distance_to_edge(pos_for_bound)
		if edge_dist <= MapBoundary.WARN_DISTANCE_PX + 1000.0:
			var inward := (Vector2.ZERO - pos_for_bound).normalized()
			if away_dir.dot(inward) < 0.0:
				var blend := clampf(1.0 - edge_dist / (MapBoundary.WARN_DISTANCE_PX + 1000.0), 0.3, 1.0)
				away_dir = away_dir.lerp(inward, blend).normalized()

	# 低技能飞行员脱离方向可能有偏差
	ai.aircraft.target_position = ai._apply_position_error(ai.aircraft.global_position + away_dir * AIController.EXTENSION_DISTANCE)

	# 性格偏移：骑士脱离更快(approach_speed_mult=1.75→0.95×max)，
	# 斗士脱离较慢(1.55→0.89×max)，但斗士本身很少选 extension
	# FEAR 守卫：恐慌脱离改用 cruise 速度且禁加力，防止全速冲出战场
	if feared and ai.aircraft.params:
		ai.aircraft.target_speed_kmh = ai._apply_speed_error(
			AircraftPhysics.effective_cruise_speed_kmh(ai.aircraft))
		ai.aircraft.is_afterburner = false
	elif ai.aircraft.params:
		var escape_mult := lerpf(AIController.EXTENSION_ESCAPE_MIN, AIController.EXTENSION_ESCAPE_MAX, ai._cb().approach_speed_mult / 2.0)
		ai.aircraft.target_speed_kmh = ai._apply_speed_error(
			AircraftPhysics.effective_max_speed_kmh(ai.aircraft) * escape_mult)
	else:
		ai.aircraft.target_speed_kmh = ai._apply_speed_error(1800.0)

	# 脱离时爬升保能（FEAR 不爬升，避免高速 + 高空双重远走高飞）
	if feared:
		ai.aircraft.target_altitude = ai.aircraft.altitude
	elif ai.aircraft.flat_altitude:
		ai.aircraft.set_target_tier(ai.aircraft.tier_above())
	else:
		ai.aircraft.target_altitude = ai.aircraft.altitude + AIController.EXTENSION_CLIMB

	var separation := ai.aircraft.global_position.distance_to(ai._extension_start_pos)
	if separation > AIController.EXTENSION_SUCCESS_DIST and s.dist_px > s.gun_range_px * AIController.EXTENSION_SUCCESS_MULT:
		ai._tactic_timer = ai._tactic_min_duration

## 剪刀机动：近距反复交叉反转，利用低速优势抢位
static func execute_scissors(ai: AIController, s: AIController.SituationData, delta: float) -> void:
	ai._scissors_reverse_timer += delta

	# 剪刀反转间隔（根据距离和速度调整）
	var reverse_interval := clampf(s.dist_px / maxf(s.my_speed * Aircraft.PIXELS_PER_METER, 30.0), AIController.SCISSORS_REVERSE_MIN, AIController.SCISSORS_REVERSE_MAX)

	if ai._scissors_reverse_timer >= reverse_interval:
		ai._scissors_side *= -1.0
		ai._scissors_reverse_timer = 0.0

	# 计算交叉方向：垂直于我与敌机连线
	var to_tgt_dir := s.to_target
	var cross_dir := Vector2(to_tgt_dir.y, -to_tgt_dir.x) * ai._scissors_side

	# 目标位置：侧向偏移 + 略微朝向敌机
	var scissors_pos := ai.aircraft.global_position + cross_dir * AIController.SCISSORS_LATERAL + to_tgt_dir * AIController.SCISSORS_FORWARD
	ai.aircraft.target_position = ai._apply_position_error(scissors_pos)

	# 减速！剪刀机动中低速优势是关键（低技能飞行员可能减速不够）
	if ai.aircraft.params:
		var min_safe_speed := AircraftPhysics.effective_stall_speed_kmh(ai.aircraft) \
			* AIController.SCISSORS_SAFE_SPEED
		ai.aircraft.target_speed_kmh = ai._apply_speed_error(min_safe_speed)
	else:
		ai.aircraft.target_speed_kmh = ai._apply_speed_error(AIController.SCISSORS_FALLBACK_SPEED)

	match_target_altitude(ai)

# ══════════════════════════════════════════════
#  速度管理辅助
# ══════════════════════════════════════════════

## 高度匹配敌机（自动适配扁平/连续模式）—— 仅近距/机炮战使用
static func match_target_altitude(ai: AIController) -> void:
	if not ai._current_target:
		return
	if ai.aircraft.flat_altitude:
		ai.aircraft.set_target_tier(ai._current_target.get_altitude_tier())
	else:
		ai.aircraft.target_altitude = ai._current_target.altitude

## 作战高度：使用自身 patrol_altitude 作为偏好（保留高度优势），
## clamp 到目标 ±2500m 内以满足导弹包线 ±5000m 的高度差限制（留足余量）。
## 远距/导弹战调用本函数代替 match_target_altitude。
const COMBAT_ALT_TARGET_MARGIN := 2500.0
static func use_combat_altitude(ai: AIController) -> void:
	if not ai._current_target:
		set_patrol_altitude(ai)
		return
	var tgt_alt: float = ai._current_target.altitude
	var prefer: float = ai.patrol_altitude if ai.patrol_altitude > 0.0 else tgt_alt
	var combat_alt: float = clampf(prefer, tgt_alt - COMBAT_ALT_TARGET_MARGIN, tgt_alt + COMBAT_ALT_TARGET_MARGIN)
	if ai.aircraft.flat_altitude:
		# 扁平模式：选 patrol 对应档，clamp 到目标 ±1 档（保证导弹高度差不超档）
		var tgt_tier: int = ai._current_target.get_altitude_tier()
		var prefer_tier: int = _altitude_to_tier(prefer)
		var clamped_tier: int = clampi(prefer_tier, tgt_tier - 1, tgt_tier + 1)
		ai.aircraft.set_target_tier(clamped_tier)
	else:
		if ai.aircraft.params:
			combat_alt = clampf(combat_alt, 200.0, ai.aircraft.params.max_altitude - 200.0)
		ai.aircraft.target_altitude = combat_alt

static func _altitude_to_tier(alt: float) -> int:
	if alt < 3500.0:
		return CombatUnit.AltitudeTier.LOW
	if alt < 7500.0:
		return CombatUnit.AltitudeTier.MID
	return CombatUnit.AltitudeTier.HIGH

## 设置巡逻高度（自动适配扁平/连续模式）
static func set_patrol_altitude(ai: AIController) -> void:
	if ai.aircraft.flat_altitude:
		ai.aircraft.set_target_tier(Aircraft.AltitudeTier.MID)
	else:
		ai.aircraft.target_altitude = ai.patrol_altitude

## 机炮闪避：被追尾射击时叠加蛇形偏移（仅斗士型，幅度受技能梯度控制）
## 不改变战术状态，只在当前战术的 target_position 上叠加垂直偏移
static func update_gun_jink(ai: AIController, s: AIController.SituationData, delta: float) -> void:
	# 只有斗士型（combat_bank_aggression > 1.0）才做机炮闪避
	if ai._cb().combat_bank_aggression <= 1.0:
		ai._gun_jink_active = false
		return

	# 触发条件：敌机在我后半球开火 + 我意识到了 + 在威胁距离内
	var should_jink := false
	if ai._current_target and is_instance_valid(ai._current_target) and ai._current_target is Aircraft:
		var enemy: Aircraft = ai._current_target
		if enemy.is_firing and s.enemy_in_my_rear and ai.personality.rear_threat_aware \
				and s.dist_px < s.gun_range_px * AIController.GUN_JINK_RANGE_MULT:
			should_jink = true

	if should_jink:
		ai._gun_jink_active = true
		ai._gun_jink_grace = AIController.GUN_JINK_GRACE  # 停火后继续闪避
	elif ai._gun_jink_grace > 0.0:
		ai._gun_jink_grace -= delta
	else:
		ai._gun_jink_active = false
		ai._gun_jink_timer = 0.0
		return

	ai._gun_jink_timer += delta

	# 技能梯度：高技能=大幅快频稳定，低技能=小幅慢频不稳
	var eff := ai._effective_skill()
	var base_amp := lerpf(AIController.GUN_JINK_AMP_MIN, AIController.GUN_JINK_AMP_MAX, eff)       # 像素偏移幅度
	var base_period := lerpf(AIController.GUN_JINK_PERIOD_MAX, AIController.GUN_JINK_PERIOD_MIN, eff)        # 秒/周期（高技能更快切换）
	# 低技能噪声：幅度随机波动，模拟"犯傻"
	var noise := 0.0
	if eff < 0.7:
		noise = sin(ai._gun_jink_timer * AIController.GUN_JINK_NOISE_FREQ) * (1.0 - eff) * AIController.GUN_JINK_NOISE_AMP
	var amp := base_amp * (1.0 + noise)
	var sway := sin(ai._gun_jink_timer * TAU / base_period) * amp

	# 偏移方向：垂直于敌机→我的追尾方向
	var to_me := (ai.aircraft.global_position - ai._current_target.global_position).normalized()
	var perp := Vector2(to_me.y, -to_me.x)
	ai.aircraft.target_position += perp * sway

static func set_engage_speed(ai: AIController, s: AIController.SituationData, mult: float) -> void:
	if not ai.aircraft.params:
		ai.aircraft.target_speed_kmh = ai._apply_speed_error(AIController.FALLBACK_ENGAGE_SPEED * mult)
		return
	var cruise := AircraftPhysics.effective_cruise_speed_kmh(ai.aircraft)
	# 性格偏移：斗士近战减速求转弯(0.9)，骑士保持高速保能量(1.15)
	var style := ai._cb().maneuver_speed_mult
	var target := clampf(cruise * mult * style,
		AircraftPhysics.effective_stall_speed_kmh(ai.aircraft) * AIController.ENGAGE_STALL_SAFETY,
		AircraftPhysics.effective_max_speed_kmh(ai.aircraft))
	ai.aircraft.target_speed_kmh = ai._apply_speed_error(target)


## ──────────────────────────────────────────────────────
## SNIPER_HOLD：狙击稳瞄战术（电磁炮 / 激光剑等"机头对准"武器专用）
## ──────────────────────────────────────────────────────
##
## 设计目标：让 AI 飞机停下高 G 转弯陀螺，机头死锁玩家当前位置（不取 lead），
## 减速到接近巡航让 bank 趋于平稳，给 RailgunEquipment 等装备稳定的锁定 + 充能窗口。
##
## 与 LEAD_PURSUIT 的核心区别：
##   - LEAD_PURSUIT: target_position = 玩家未来位置（lead 点）→ 玩家移动 → AI 持续转头追
##   - SNIPER_HOLD:  target_position = 玩家当前位置 → 玩家移动 → AI 缓慢调整 → 稳定瞄准窗口
##
## 速度策略：
##   - 远距 (dist > 4000px / 8km)：减速到 cruise × 0.7（稳瞄）
##   - 中距 (2500-4000px / 5-8km)：cruise × 0.6（更稳）
##   - 近距 (< 2500px)：意味着武器站位失败 —— 速度照常，等 BFM 退出 SNIPER_HOLD
##
## 用法：AI 设 prefer_nose_aligned_weapon = true，BFMTactics.choose_tactic 在交战
## 几何合适时（目标在前 60° 锥内、>min_engage 距离）会自动选 SNIPER_HOLD。
static func execute_sniper_hold(ai: AIController, s: AIController.SituationData) -> void:
	# 直瞄：用敌机当前位置（不取 lead），让机头有"稳定瞄准目标"
	ai.aircraft.target_position = ai._apply_position_error(s.tgt_pos)

	# 高度匹配：和敌机同高，避免射击有垂直偏差
	match_target_altitude(ai)

	# 减速稳瞄
	if ai.aircraft.params:
		var cruise := AircraftPhysics.effective_cruise_speed_kmh(ai.aircraft)
		var stall := AircraftPhysics.effective_stall_speed_kmh(ai.aircraft)
		var speed_mult: float = 0.7
		if s.dist_px < 4000.0 and s.dist_px >= 2500.0:
			speed_mult = 0.6
		elif s.dist_px < 2500.0:
			speed_mult = 0.85  # 太近，稍提速避免被超
		var target_kmh := clampf(cruise * speed_mult,
			stall * AIController.ENGAGE_STALL_SAFETY,
			AircraftPhysics.effective_max_speed_kmh(ai.aircraft))
		ai.aircraft.target_speed_kmh = ai._apply_speed_error(target_kmh)
	else:
		ai.aircraft.target_speed_kmh = AIController.FALLBACK_ENGAGE_SPEED * 0.7
