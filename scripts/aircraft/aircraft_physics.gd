class_name AircraftPhysics
extends RefCounted

## 物理演算子系统（静态工具类）
## 从 aircraft.gd 提取的 _update_target_heading / _update_bank / _update_heading /
## _update_speed / _update_altitude / _update_stall / _update_g_load /
## _update_pilot_stamina / _apply_movement / _max_bank_angle / _effective_max_g /
## _corner_speed_kmh / _stall_speed / _max_speed_at_altitude / _air_density_ratio /
## _update_shock_absorb / _set_afterburner / _update_fuel / _update_energy_management /
## _max_bank_angle_at_speed 全套逻辑。
##
## 状态仍住在 Aircraft（heading / bank_angle / speed / altitude / g_load / fuel /
## pilot_stamina / is_afterburner / _ab_cooldown / _committed_turn_sign 等）。
## 本模块不持有状态，只在 ac 上读写。
##
## 调用约定（来自 aircraft.gd _physics_process）：
##   AircraftPhysics.update_target_heading(self)
##   AircraftPhysics.update_bank(self, delta)
##   AircraftPhysics.update_heading(self, delta)
##   AircraftPhysics.update_speed(self, delta)
##   AircraftPhysics.update_altitude(self, delta)
##   AircraftPhysics.update_stall(self)
##   AircraftPhysics.update_g_load(self)
##   AircraftPhysics.apply_movement(self, delta)
##   AircraftPhysics.update_shock_absorb(self, delta)
##   AircraftPhysics.update_fuel(self, delta)
##   AircraftPhysics.update_energy_management(self)

# ── 失速物理 ──
const STALL_DIVE_RATE_MIN := -100.0              ## 失速俯冲率最小（m/s）
const STALL_DIVE_RATE_MAX := -250.0              ## 失速俯冲率最大（m/s）
const STALL_BANK_MIN := 0.1                      ## 失速时bank角最小（rad）
const STALL_BANK_RANGE := 0.2                    ## 失速时bank角范围（rad）
const AIR_DENSITY_SCALE_M := 8500.0              ## 空气密度指数衰减标尺高度（米）

# ── Bank 翻转抗振守卫（详见 update_bank 注释）──
const BANK_FLIP_ESTABLISHED_RAD: float = 0.524  ## ≈30°，当前 bank 超过此值才启用翻转守卫
const BANK_FLIP_COMMIT_RAD: float = 0.087       ## ≈5°，翻转到反向需要的最小 heading_diff

# ── 冲击吸收 ──
const SHOCK_ABSORB_RATE: float = 1.0      ## HP/秒回复速率（慢，强调"逐渐恢复"而非"立即抵消"）


static func update_target_heading(ac: Aircraft) -> void:
	# Herbst 激活期间冻结目标航向 —— 模块自己控制 heading/rotation，
	# 不能让 _cached_target_heading 根据旧 target_position 持续刷新
	# （下游 _update_bank 虽然已被 Herbst 守卫拦住，但其它链路也可能读 _cached_target_heading）
	# 详见 docs/changelogs/player-ai-log.md 2026-04-21 (6)
	var _hm_th := ac.get_herbst()
	if _hm_th and _hm_th.is_active:
		return
	if ac.target_position == Vector2.INF:
		return
	var diff := ac.target_position - ac.global_position
	var dist := diff.length()
	# 到达判定：至少150px，或当前速度下2秒的飞行距离
	# 追踪战斗目标时跳过到达清除（由 _update_combat 持续更新）
	var arrival_dist := maxf(150.0, ac.speed * CombatUnit.PIXELS_PER_METER * 2.0)
	if dist < arrival_dist and ac.combat_target == null and not ac.keep_target_on_arrival:
		ac.target_position = Vector2.INF
		ac._evasion_override = false  # 到达目标后恢复规避
		# 清除预测路径缓存（防止下次点击前残留旧弧线）
		ac.predicted_path_cache.clear()
		ac.predicted_path_target = Vector2.INF
		return
	var _target_heading := atan2(diff.x, -diff.y)
	ac._cached_target_heading = _target_heading
	# 接近目标时衰减修正力度：在 arrival_dist ~ 3×arrival_dist 之间从 0 线性过渡到 1
	ac._proximity_damping = clampf((dist - arrival_dist) / (arrival_dist * 2.0), 0.0, 1.0)


static func update_bank(ac: Aircraft, delta: float) -> void:
	# Herbst 急转阶段：模块直接修改 heading（herbst_maneuver.gd:106），
	# _update_heading 已跳过此阶段；但 _update_bank 照常跑会看到 heading 被硬转
	# 3~4°/frame，heading_diff 剧变 → target_bank 在 ±max 之间翻转（bug 2026-04-20 (7)）。
	# 冻结 bank 也不对（会让进 TURN 时 ±85° 高 bank 持续到 ACCEL 结束，视觉 bank_compress
	# 严重压扁 X 轴，飞机图标看起来被斜着画（bug 2026-04-20 (9)））。
	# 正确做法：Herbst 全程（DECEL/TURN/ACCEL）都强制 bank 向 0 衰减 —— 真实 post-stall
	# yaw J-Turn 就是放平机翼纯绕 yaw 轴旋转，视觉转向由 Herbst.visual_offset 处理。
	# 2026-04-20 (9) 只覆盖 TURN，但 DECEL/ACCEL 期间 heading 也是冻结的（_update_heading
	# skip is_active 整段），而 AI 在 bvr_only 分支 Herbst 激活时每 tick 都会 fall through
	# 到 flee→_disengage→boss re-engage 闭环（ai_controller.gd:1216-1220），target_position
	# 在「远离玩家」和「LEAD_PURSUIT」之间反复跳 → target_bank 在 ±max 翻跳 → bank_compress
	# 抖动 → 机身视觉颤抖（bug 2026-04-21）。
	# 详见 docs/changelogs/player-ai-log.md 2026-04-20 (9) + 2026-04-21
	var _hm_bank := ac.get_herbst()
	if _hm_bank and _hm_bank.is_active:
		var roll_rate_herbst: float = ac.params.roll_rate if ac.params else 4.0
		ac.bank_angle = move_toward(ac.bank_angle, 0.0, roll_rate_herbst * delta)
		return

	if ac.target_position == Vector2.INF and abs(ac.bank_angle) < 0.01:
		ac.bank_angle = 0.0
		return

	var heading_diff := Aircraft._angle_diff(ac._cached_target_heading, ac.heading)

	if ac.target_position == Vector2.INF:
		# 无目标，回正
		heading_diff = 0.0
		ac._committed_turn_sign = 0.0

	# 转弯方向锁定：防止目标在正后方时 heading_diff 符号逐帧跳动导致滚转振荡
	# 当偏差 > ~143° 时锁定转弯方向，当偏差 < ~86° 时解锁
	if abs(heading_diff) > 2.5:
		if ac._committed_turn_sign == 0.0:
			ac._committed_turn_sign = signf(heading_diff)
			# 诊断：玩家 turn_sign 被锁定的瞬间立即打点 —— 追"绕错方向"bug 用
			if ac.use_tactical_preference and ac.combat_target != null:
				EventLogger.log_event("PURSUIT_LOCK", ac._log_name(),
					"turn_sign=%+d (hdg_diff=%+d°, tgt=%s) branch=%s" % [
						int(ac._committed_turn_sign), int(rad_to_deg(heading_diff)),
						ac._log_unit_name(ac.combat_target), ac._pursuit_branch])
		heading_diff = absf(heading_diff) * ac._committed_turn_sign
	elif abs(heading_diff) < 1.5:
		if ac._committed_turn_sign != 0.0 and ac.use_tactical_preference and ac.combat_target != null:
			EventLogger.log_event("PURSUIT_UNLOCK", ac._log_name(),
				"turn_sign cleared (hdg_diff=%+d°, tgt=%s)" % [
					int(rad_to_deg(heading_diff)), ac._log_unit_name(ac.combat_target)])
		ac._committed_turn_sign = 0.0

	# ── 预测式过冲补偿（critical damping）──
	# 真实飞行员会"预读"自己当前的转弯率：在到达目标航向**之前**就开始回正坡度，
	# 这样反馈环路才不会沿着 sinusoidal 摆动。
	# 1. 估算当前转弯率 ω = g·tan(bank)/V
	# 2. 估算把当前坡度从 |bank| 滚回 0 需要的时间 t_roll = |bank|/roll_rate
	# 3. 三角积分：滚出过程中航向再走 (ω · t_roll)/2 弧度
	# 4. 把这个预测量从 heading_diff 里扣掉，让下面的 P 控制器把"未来航向"对准目标
	# 注：仅在 anticipated_change 与 heading_diff 同号时扣（即正在朝目标转），
	#     避免在反向初动时把扣减算反。
	if absf(ac.bank_angle) > 0.05 and absf(heading_diff) > 0.001:
		var rr_val := ac.params.roll_rate if ac.params else 4.0
		var stall_ms_pre := stall_speed(ac) / 3.6
		if ac.speed < stall_ms_pre:
			var ctrl_pre := clampf(ac.speed / maxf(stall_ms_pre, 1.0), 0.1, 1.0)
			rr_val *= ctrl_pre
		var current_turn_rate := CombatUnit.GRAVITY * tan(ac.bank_angle) / maxf(ac.speed, 50.0)
		var t_roll := absf(ac.bank_angle) / maxf(rr_val, 0.5)
		var anticipated_change := current_turn_rate * t_roll * 0.5
		if signf(anticipated_change) == signf(heading_diff):
			# 软钳位（避免反馈环 bang-bang 振荡）：
			# 旧代码在 `|anticipated| >= |heading_diff|` 时把 heading_diff 硬归零 →
			# target_bank=0 → bank 回中一档 → 下一 tick turn_rate 缩水 → anticipated 跟着缩水
			# → heading_diff 原值重现未被吃完 → target_bank=±max → bank 回弹。
			# 结果 bank 在 ~max / (max - 5°) 两档以 ~4Hz 来回切，G 也跟着抖 5↔13
			# —— 视觉上就是 F-47 在近距咬尾（heading_diff ≈ 2~5°）时机身左右抽搐。
			# F-47 CLOSE_FIGHTER 的 full_bank_diff=0.033 rad（≈1.9°）阈值极紧，
			# target_bank 在此附近接近阶跃函数，放大了振荡。
			# 改成最多吃 heading_diff 的 80%，保留 20% 残余命令让 target_bank 留在
			# 平滑 lerp 区（而非阈值另一侧的 0），避免跨阈值跳变。
			# 详见 docs/changelogs/player-ai-log.md 2026-04-21 (9)
			var cap: float = absf(heading_diff) * 0.8
			var sub: float = minf(absf(anticipated_change), cap) * signf(heading_diff)
			heading_diff -= sub

	var max_bank := max_bank_angle(ac)
	var in_combat := ac.combat_target != null
	var target_bank: float

	# 大角度转弯时限制最大坡度到持续G水平，防止追踪时拉极端G螺旋
	# 只有小角度精确对准时才允许使用结构极限G
	# tactical_aggression 控制限制的强度：
	#   1.0 = 完全解除限制，拉到结构 G 上限（survivor 玩家默认）
	#   0.0 = 完全应用 70% 持续 G 限制（保守 AI）
	#   中间 = 按因子在两者之间插值（沙盒 AI 随飞行员属性动态调整）
	if in_combat and abs(heading_diff) > 0.5 and ac.tactical_aggression < 0.999:
		var sustained_g := ac.params.max_g if ac.params else 9.0
		var turn_g_capped := lerpf(sustained_g * 0.7, sustained_g, clampf((PI - abs(heading_diff)) / (PI - 0.5), 0.0, 1.0))
		var turn_g_full := effective_max_g(ac)
		var turn_g := lerpf(turn_g_capped, turn_g_full, clampf(ac.tactical_aggression, 0.0, 1.0))
		var sustained_bank := acos(1.0 / maxf(turn_g, 1.01))
		max_bank = minf(max_bank, sustained_bank)

	if in_combat:
		var cb := ac._combat_params()
		var full_diff := cb.combat_full_bank_diff / cb.combat_bank_aggression
		var half_diff := cb.combat_half_bank_diff / cb.combat_bank_aggression

		if ac.use_tactical_preference:
			# 战术偏好模式（玩家控制）：始终使用激进转弯，不受导弹阶段影响
			if abs(heading_diff) < half_diff:
				target_bank = 0.0
			elif abs(heading_diff) < full_diff:
				var bank_ratio: float = (abs(heading_diff) - half_diff) / (full_diff - half_diff)
				target_bank = sign(heading_diff) * max_bank * lerpf(0.4, 1.0, bank_ratio)
			else:
				target_bank = sign(heading_diff) * max_bank
		elif ac.weapon_mode == Aircraft.WeaponMode.MISSILE:
			# 导弹模式分三阶段：接近→照射→保持
			var msl_phase := ac._get_missile_phase()
			if msl_phase == 0:
				# 接近阶段：积极机动（与机炮模式相同）
				if abs(heading_diff) < half_diff:
					target_bank = 0.0
				elif abs(heading_diff) < full_diff:
					var bank_ratio: float = (abs(heading_diff) - half_diff) / (full_diff - half_diff)
					target_bank = sign(heading_diff) * max_bank * lerpf(0.4, 1.0, bank_ratio)
				else:
					target_bank = sign(heading_diff) * max_bank
			elif msl_phase == 1:
				# 照射阶段：目标在锥内累积锁定，适度稳定
				if abs(heading_diff) < 0.03:
					target_bank = 0.0
				else:
					target_bank = sign(heading_diff) * max_bank * clampf(abs(heading_diff) * 3.0, 0.2, 0.6)
			else:
				# 保持阶段（已锁定/crank）：极稳定
				if abs(heading_diff) < 0.02:
					target_bank = 0.0
				else:
					target_bank = sign(heading_diff) * max_bank * clampf(abs(heading_diff) * 2.0, 0.1, 0.35)
		else:
			# 机炮模式：激进转弯
			if abs(heading_diff) < half_diff:
				target_bank = 0.0
			elif abs(heading_diff) < full_diff:
				var gun_bank_ratio: float = (abs(heading_diff) - half_diff) / (full_diff - half_diff)
				target_bank = sign(heading_diff) * max_bank * lerpf(0.4, 1.0, gun_bank_ratio)
			else:
				target_bank = sign(heading_diff) * max_bank
	elif ac.formation_mode:
		# 编队跟随模式：积极转弯追赶阵型位置
		if abs(heading_diff) < 0.03:
			target_bank = 0.0
		elif abs(heading_diff) < 0.2:
			target_bank = sign(heading_diff) * max_bank * lerpf(0.3, 0.8, abs(heading_diff) / 0.2)
		else:
			target_bank = sign(heading_diff) * max_bank * 0.9
	elif ac.use_tactical_preference:
		# 玩家巡航模式（点击移动）：最激进的转弯，忽略距离衰减
		# 目的：最快到达点击位置，拉满 G 以获得最小转弯半径
		if abs(heading_diff) < 0.02:
			target_bank = 0.0
		elif abs(heading_diff) < 0.15:
			var player_ratio: float = (abs(heading_diff) - 0.02) / (0.15 - 0.02)
			target_bank = sign(heading_diff) * max_bank * lerpf(0.5, 1.0, player_ratio)
		else:
			target_bank = sign(heading_diff) * max_bank
		# 不应用 _proximity_damping：玩家要始终满 G 转弯
	else:
		# 巡航模式：温和修正
		if abs(heading_diff) < 0.05:
			target_bank = 0.0
		elif abs(heading_diff) < 0.4:
			target_bank = sign(heading_diff) * max_bank * 0.3
		else:
			target_bank = sign(heading_diff) * max_bank
		target_bank *= ac._proximity_damping

	# ── Bank 翻转抗振守卫 ──
	# 场景：target_position 横向移动时 heading_diff 反复过零，候选 target_bank 就在
	# `+max_bank` 和 `-max_bank` 之间瞬间切换。bank 滚转率 ~4 rad/s，从 +86° 滚到
	# -86° 需 0.75s；期间 heading_diff 又因目标持续移动摆回对侧，形成 bang-bang 振荡
	# —— 视觉上就是飞机剧烈颤抖、机头左右疯甩、原地打转、flare 堆在一处。
	# 守卫：当前 bank 已建立（>30°）且候选 target_bank 要反向时，如果 heading_diff 还
	# 不够大（<5°），强制先 roll 回中立（target_bank=0），过了中立再考虑翻。
	# 这相当于给"bank 反向"加一层迟滞，让控制器在目标明确移到另一侧前先放平机翼。
	# 不改原 target_bank 计算公式 —— 只在病态翻转场景 override。
	# 详见 docs/changelogs/player-ai-log.md 2026-04-20 (7)
	if absf(ac.bank_angle) > BANK_FLIP_ESTABLISHED_RAD \
			and signf(target_bank) != 0.0 \
			and signf(target_bank) != signf(ac.bank_angle) \
			and absf(heading_diff) < BANK_FLIP_COMMIT_RAD:
		target_bank = 0.0

	# 失速时：强制回正（机翼失去升力，无法维持侧倾）
	if ac.is_stalled:
		target_bank = 0.0
	elif ac._stall_recovery_timer > 0.0:
		# 失速恢复期：逐渐恢复机动能力，防止立即拉G再次失速
		var recovery_ratio := 1.0 - clampf(ac._stall_recovery_timer / 1.0, 0.0, 1.0)
		target_bank *= recovery_ratio  # 线性恢复，更快回复机动能力

	# 滚转速率限制
	var roll_rate_val := ac.params.roll_rate if ac.params else 4.0

	# 低速时滚转速率也下降
	var stall_ms := stall_speed(ac) / 3.6
	if ac.speed < stall_ms:
		var ctrl := clampf(ac.speed / maxf(stall_ms, 1.0), 0.1, 1.0)
		roll_rate_val *= ctrl

	var bank_diff := target_bank - ac.bank_angle
	var max_roll := roll_rate_val * delta
	ac.bank_angle += clampf(bank_diff, -max_roll, max_roll)


static func update_heading(ac: Aircraft, delta: float) -> void:
	# 赫尔贝特轮机动期间由模块直接控制 heading，跳过正常转弯
	var _hm_hdg := ac.get_herbst()
	if _hm_hdg and _hm_hdg.is_active:
		return
	if abs(ac.bank_angle) < 0.001:
		return
	# 转弯率 ω = g × tan(bank_angle) / speed
	var speed_ms := maxf(ac.speed, 1.0)  # 防止除零
	var turn_rate := CombatUnit.GRAVITY * tan(ac.bank_angle) / speed_ms

	# 低速时操控性急剧下降：速度低于失速速度时，转向能力线性衰减
	var stall_ms := stall_speed(ac) / 3.6
	if ac.speed < stall_ms:
		var control_ratio := clampf(ac.speed / maxf(stall_ms, 1.0), 0.0, 1.0)
		# 平方衰减：速度越低，操控越差
		turn_rate *= control_ratio * control_ratio

	ac.heading += turn_rate * delta
	# 归一化到 [-PI, PI]
	ac.heading = fmod(ac.heading + PI, TAU) - PI


static func update_speed(ac: Aircraft, delta: float) -> void:
	var _m := ac.get_maneuver()
	if _m and _m.is_active:
		return  # 战术机动期间速度由模块控制
	var target_ms := ac.target_speed_kmh / 3.6
	var max_speed_ms := max_speed_at_altitude(ac) / 3.6
	target_ms = minf(target_ms, max_speed_ms)

	# 安全速度下限：永远不主动减速到失速速度以下
	var stall_base_ms := (ac.params.stall_speed_base if ac.params else 220.0) / 3.6
	var min_safe_ms := stall_base_ms * 1.3  # 130% 失速速度作为安全余量
	target_ms = maxf(target_ms, min_safe_ms)

	var accel_rate := ac.params.acceleration if ac.params else 50.0
	var decel_rate := (ac.params.deceleration if ac.params else 80.0) * ac._executioner_decel_mult()  # 侩子手：+10%/层

	# 加力燃烧：提升加速度
	if ac.is_afterburner:
		var ab_mult := ac.params.afterburner_thrust_mult if ac.params else 1.5
		accel_rate *= ab_mult

	# 高G机动阻力：拉G越大减速越快
	var g_drag := ac.params.g_drag_factor if ac.params else 3.0
	var g_decel := maxf(ac.g_load - 1.0, 0.0) * g_drag  # 1G时无额外阻力
	decel_rate += g_decel

	# 非对称加减速
	var speed_diff := target_ms - ac.speed
	if speed_diff >= 0:
		ac.speed += minf(speed_diff, accel_rate * delta)
	else:
		ac.speed += maxf(speed_diff, -decel_rate * delta)

	# 高度⇌速度耦合：爬升减速、俯冲加速
	var spd := maxf(ac.speed, 10.0)
	var gravity_effect := CombatUnit.GRAVITY * ac.vertical_speed / spd
	ac.speed -= gravity_effect * delta

	ac.speed = maxf(ac.speed, 0.0)
	# AI 轨道限速：由 AIController 设置，0 = 不限制
	if ac.orbit_speed_cap > 0.0 and ac.speed > ac.orbit_speed_cap:
		ac.speed = ac.orbit_speed_cap


static func update_altitude(ac: Aircraft, delta: float) -> void:
	var alt_diff := ac.target_altitude - ac.altitude
	# altitude_authority_mult 同步放大三处，避免只改 max_climb 被指数尾巴拖慢：
	#   ① 钳制上限（前段快速接近）
	#   ② 增益 0.1（后段指数收敛）
	#   ③ 平滑 lerp 速率（响应延迟）
	var alt_mult: float = ac.altitude_authority_mult
	var max_climb := (ac.params.climb_rate_max if ac.params else 250.0) * alt_mult
	var gain := 0.1 * alt_mult
	var smooth_rate := 2.0 * alt_mult
	var target_vs: float
	if abs(alt_diff) < 10.0:
		target_vs = 0.0
	else:
		target_vs = clampf(alt_diff * gain, -max_climb, max_climb)
	ac.vertical_speed = lerpf(ac.vertical_speed, target_vs, delta * smooth_rate)
	ac.altitude += ac.vertical_speed * delta
	ac.altitude = maxf(ac.altitude, 0.0)


static func update_stall(ac: Aircraft) -> void:
	var stall_speed_ms := stall_speed(ac) / 3.6
	var was_stalled := ac.is_stalled
	ac.is_stalled = ac.speed < stall_speed_ms
	if ac.is_stalled:
		var delta := ac.get_physics_process_delta_time()
		# 失速严重程度（0=刚失速, 1=完全停止）
		var severity := 1.0 - clampf(ac.speed / maxf(stall_speed_ms, 1.0), 0.0, 1.0)

		# 强制机头下压俯冲（设置 vertical_speed，让重力耦合把高度转成速度）
		# 不直接修改 altitude —— _update_altitude 已经处理了
		var dive_rate := lerpf(STALL_DIVE_RATE_MIN, STALL_DIVE_RATE_MAX, severity)
		ac.vertical_speed = minf(ac.vertical_speed, dive_rate)

		# 失速时侧倾不稳定
		ac.bank_angle += randf_range(-1.0, 1.0) * severity * 2.0 * delta

		ac._stall_recovery_timer = 1.0  # 脱离失速后 1 秒内限制机动
	elif ac._stall_recovery_timer > 0.0:
		ac._stall_recovery_timer -= ac.get_physics_process_delta_time()


static func update_g_load(ac: Aircraft) -> void:
	var _m := ac.get_maneuver()
	if _m and _m.is_active:
		return  # 战术机动期间 G 力由模块直接设置
	if abs(ac.bank_angle) < 0.001:
		ac.g_load = 1.0
	else:
		ac.g_load = 1.0 / cos(ac.bank_angle)
		ac.g_load = absf(ac.g_load)
	if not ac.no_stamina:
		update_pilot_stamina(ac, ac.get_physics_process_delta_time())


static func update_pilot_stamina(ac: Aircraft, delta: float) -> void:
	var sustained_g := ac.params.max_g if ac.params else 9.0
	var max_stam := ac.params.pilot_stamina if ac.params else 100.0
	if ac.g_load > sustained_g:
		# 超过持续耐受G时消耗耐力，G力越高消耗越快
		var excess_ratio := (ac.g_load - sustained_g) / maxf(effective_max_g(ac) - sustained_g, 0.1)
		var drain := (ac.params.stamina_drain_rate if ac.params else 25.0) * excess_ratio
		ac.pilot_stamina = maxf(ac.pilot_stamina - drain * delta, 0.0)
	else:
		# 低于持续耐受G时恢复耐力
		var recovery := ac.params.stamina_recovery_rate if ac.params else 10.0
		ac.pilot_stamina = minf(ac.pilot_stamina + recovery * delta, max_stam)


static func apply_movement(ac: Aircraft, delta: float) -> void:
	# heading: 0=上(北), 顺时针为正
	# Godot 2D: x右, y下
	var velocity := Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed * CombatUnit.PIXELS_PER_METER
	ac.global_position += velocity * delta


# ========== 辅助计算 ==========

static func max_bank_angle(ac: Aircraft) -> float:
	var max_g_val := effective_max_g(ac)
	# G = 1/cos(bank) => bank = acos(1/G)
	var g_limited_bank := acos(1.0 / max_g_val)

	# 速度限制：不允许拉到会导致失速的G力
	# 失速速度 V_stall = V_base * sqrt(G)，所以允许的最大G = (V_current / V_base)²
	# 留 20% 安全余量防止拉G后立即失速抽搐
	var stall_base := (ac.params.stall_speed_base if ac.params else 220.0) / 3.6  # m/s
	var safe_margin := 1.2  # 保留20%速度余量
	if ac.speed > stall_base * safe_margin:
		var effective_speed := ac.speed / safe_margin  # 用折减后的速度计算允许G
		var max_g_for_speed := (effective_speed / stall_base) * (effective_speed / stall_base)
		var speed_limited_bank := acos(1.0 / maxf(max_g_for_speed, 1.01))
		return minf(g_limited_bank, speed_limited_bank)
	else:
		# 速度接近/低于安全线，线性衰减到几乎不能拉G
		var ratio := clampf(ac.speed / (stall_base * safe_margin), 0.0, 1.0)
		return STALL_BANK_MIN + ratio * STALL_BANK_RANGE  # 0.1~0.3 rad (约6°~17°)


static func effective_max_g(ac: Aircraft) -> float:
	## 根据飞行员耐力在 sustained G 与 structural G 之间插值
	var sustained := ac.params.max_g if ac.params else 9.0
	var structural := ac.params.max_g_structural if ac.params else 12.0
	var max_stam := ac.params.pilot_stamina if ac.params else 100.0
	var ratio := ac.pilot_stamina / maxf(max_stam, 0.01)
	var g := sustained + (structural - sustained) * ratio
	# 云中：能见度差、气流扰动导致机动受限
	if ac.cloud_state == 2:
		g *= 0.9
	return g


## 角点速度（km/h）：能承受当前 G 极限而不被 max_bank_angle 速度限制卡住的最低速度
## V_corner = V_stall_base × safe_margin × sqrt(G_effective)
## 大 G 转弯时应维持此速度以获得最小转弯半径（不过分减速导致 G 被速度钳制）
static func corner_speed_kmh(ac: Aircraft) -> float:
	var g_target := effective_max_g(ac)
	var stall_base_kmh := ac.params.stall_speed_base if ac.params else 220.0
	# safe_margin 与 max_bank_angle 保持一致（1.2）
	return stall_base_kmh * 1.2 * sqrt(maxf(g_target, 1.0))


static func stall_speed(ac: Aircraft) -> float:
	# V_stall = V_base * sqrt(G)
	var base := ac.params.stall_speed_base if ac.params else 220.0
	return base * sqrt(maxf(ac.g_load, 1.0))


static func max_speed_at_altitude(ac: Aircraft) -> float:
	var max_spd := ac.params.max_speed if ac.params else 2100.0
	max_spd *= ac._executioner_speed_mult()  # 侩子手：+5%/层
	# 简化：高空速度略降
	var density_ratio := exp(-ac.altitude / AIR_DENSITY_SCALE_M)
	var v := max_spd * sqrt(density_ratio)
	# 云中：气流扰动 + 机翼结冰风险 → 最大速度损失
	if ac.cloud_state == 2:
		v *= 0.9
	return v


static func air_density_ratio(ac: Aircraft) -> float:
	return exp(-ac.altitude / AIR_DENSITY_SCALE_M)


## 计算指定速度下的最大坡度角（预测线用）
static func max_bank_angle_at_speed(ac: Aircraft, spd: float, stall_base_ms: float) -> float:
	var max_g_val := effective_max_g(ac)
	var g_limited_bank := acos(1.0 / max_g_val)
	var safe_margin := 1.2
	if spd > stall_base_ms * safe_margin:
		var effective_speed := spd / safe_margin
		var max_g_for_speed := (effective_speed / stall_base_ms) * (effective_speed / stall_base_ms)
		var speed_limited_bank := acos(1.0 / maxf(max_g_for_speed, 1.01))
		return minf(g_limited_bank, speed_limited_bank)
	else:
		var ratio := clampf(spd / (stall_base_ms * safe_margin), 0.0, 1.0)
		return STALL_BANK_MIN + ratio * STALL_BANK_RANGE


# ========== 战区奖励 v2 辅助 ==========

## 冲击吸收：每帧把 shock_absorb_pending 中累积的 HP 慢慢还给玩家
static func update_shock_absorb(ac: Aircraft, delta: float) -> void:
	if ac.shock_absorb_pending <= 0.0 or ac.is_destroyed:
		return
	if not ac.params:
		return
	var step: float = minf(ac.shock_absorb_pending, SHOCK_ABSORB_RATE * delta)
	var max_hp: float = ac.params.max_hp
	var room: float = max_hp - ac.hp
	if room <= 0.0:
		ac.shock_absorb_pending = 0.0
		return
	step = minf(step, room)
	ac.hp += step
	ac.shock_absorb_pending -= step


# ========== 燃油 / 能量管理 ==========

## 带冷却的加力切换
static func set_afterburner(ac: Aircraft, on: bool) -> void:
	if on == ac.is_afterburner:
		return
	if ac._ab_cooldown > 0.0:
		return  # 冷却中，保持当前状态
	if on and ac.fuel <= 0.0:
		return
	ac.is_afterburner = on
	ac._ab_cooldown = ac._combat_params().ab_cooldown


static func update_fuel(ac: Aircraft, delta: float) -> void:
	ac._ab_cooldown = maxf(ac._ab_cooldown - delta, 0.0)
	if ac.infinite_fuel:
		return
	if ac.fuel <= 0.0:
		ac.fuel = 0.0
		ac.is_afterburner = false
		return
	var rate: float
	if ac.is_afterburner:
		rate = ac.params.fuel_rate_afterburner if ac.params else 8.0
	else:
		rate = ac.params.fuel_rate_normal if ac.params else 1.5
	ac.fuel -= rate * delta
	if ac.fuel <= 0.0:
		ac.fuel = 0.0
		ac.is_afterburner = false


## 自动能量管理：战斗时加力+俯冲换速，巡航时蓄能爬升
static func update_energy_management(ac: Aircraft) -> void:
	var cb := ac._combat_params()
	var cruise := ac.params.cruise_speed if ac.params else 900.0

	if ac.combat_target != null and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed:
		# 地面攻击模式（2026-04-21，详见 docs/changelogs/player-ai-log.md）
		# 分武器模式处理：
		#   - 机炮 / 火箭：地面目标固定，不需要照射；加力掠过 strafe，降低被 AAA 命中概率
		#   - 导弹：维持照射时间，cruise×0.7 保证锁定稳定
		if ac.combat_target is GroundUnit:
			if ac.weapon_mode == Aircraft.WeaponMode.MISSILE:
				ac.target_speed_kmh = cruise * 0.7
				set_afterburner(ac, false)
			else:
				var approach_spd := cruise * cb.approach_speed_mult
				ac.target_speed_kmh = approach_spd
				set_afterburner(ac, ac.speed * 3.6 < approach_spd - 50.0 and ac.fuel > 0.0)
			return
		# AI 战术机动模式：AI 控制器已设定速度，仅管理加力燃烧器
		if ac.ai_override_pursuit:
			var my_kmh := ac.speed * 3.6
			set_afterburner(ac, my_kmh < ac.target_speed_kmh - 50.0 and ac.fuel > 0.0)
			return
		# ---- 战斗模式 ----
		var dist := Aircraft.effective_distance_px(ac.global_position, ac.altitude, ac.combat_target.global_position, ac.combat_target.altitude)
		var gun_range := ac._gun_range_px()
		var tgt_speed_ms := ac.combat_target.speed
		var tgt_speed_kmh := tgt_speed_ms * 3.6

		# 战斗最低安全速度：不允许因追踪慢速目标而降到失速边缘
		var stall_base_kmh := ac.params.stall_speed_base if ac.params else 220.0
		var combat_min_kmh := stall_base_kmh * 1.8  # 180% 失速速度，留足高G机动余量
		# 慢目标判据（用于 gun 分支 + overshoot 分支）：目标速度 < 自己巡航的 40%
		# 这是稳定判据，不依赖 current speed 避免振荡
		var is_slow_target_persistent := ac.combat_target.speed * 3.6 < cruise * 0.4

		var is_missile_mode := ac.weapon_mode == Aircraft.WeaponMode.MISSILE

		# 预估到达射程所需时间
		var my_speed_px := ac.speed * CombatUnit.PIXELS_PER_METER
		var tgt_fwd := Vector2(sin(ac.combat_target.heading), -cos(ac.combat_target.heading))
		var tgt_speed_px := tgt_speed_ms * CombatUnit.PIXELS_PER_METER
		var to_tgt := (ac.combat_target.global_position - ac.global_position).normalized()
		var closure_px := Vector2(sin(ac.heading), -cos(ac.heading)).dot(to_tgt) * my_speed_px \
			- tgt_fwd.dot(to_tgt) * tgt_speed_px

		# ---- 计算朝目标的航向偏差 ----
		var heading_to_tgt := atan2(to_tgt.x, -to_tgt.y)
		var heading_diff_deg := absf(rad_to_deg(Aircraft._angle_diff(heading_to_tgt, ac.heading)))

		var my_kmh := ac.speed * 3.6
		var turn_speed := cruise * cb.turn_slow_speed_mult
		var needs_big_turn := heading_diff_deg > cb.turn_slow_angle

		var approach_speed := cruise * cb.approach_speed_mult

		if ac.use_tactical_preference and is_missile_mode:
			# ======== 战术偏好：导弹模式能量管理（v8 — corner speed for turn）========
			# 物理事实：最快转弯率在**角点速度 (corner speed)**，不是 cruise 也不是 approach
			#   ω_max = V/R, R_min = V²/(g×√(G²-1))
			#   → ω ∝ 1/V （G 固定情况下），所以越慢越好
			#   但是 V 太低 → 速度 G 封顶 (V/V_stall/1.2)² 把 G 压下去 → ω 反而变小
			#   corner speed 是这两条曲线的交点：V = V_stall × 1.2 × √G
			# 所以未对准时用 corner speed 获得最小转弯半径和最大角速度
			# AB 只在加速到 corner 的过程中用（帮助快速进入最优转弯态）
			var corner_kmh := corner_speed_kmh(ac)
			var eff_range_px := ac._effective_missile_range_px()

			# match_kmh: 敌机速度 + 50 kmh 小余量
			var match_kmh := clampf(tgt_speed_kmh + 50.0, combat_min_kmh, cruise)

			# 检查是否已有弹在飞向此目标
			var has_inflight_missile := false
			if ac.missile_manager:
				has_inflight_missile = ac.missile_manager.has_active_missile_at(ac, ac.combat_target)

			# 对准窗口：航向偏差小于此值才算"已对准"，可以减速累积锁定
			var align_window_deg := 35.0
			var is_aligned := heading_diff_deg <= align_window_deg

			# turn_target: corner speed 与 cruise×0.85 的较大值，保证在 V_stall G 封顶之上
			var turn_target_kmh := maxf(corner_kmh, cruise * 0.85)

			if has_inflight_missile:
				# 发射后：稳定 match，不继续冲
				ac.target_speed_kmh = match_kmh
				set_afterburner(ac, false)
			elif not is_aligned:
				# 未对准：用 corner speed（最大角速度点）
				# 如果当前速度低于 corner，用加力快速拉上来（加力服务于转弯，不是冲距离）
				ac.target_speed_kmh = turn_target_kmh
				set_afterburner(ac, my_kmh < turn_target_kmh - 40.0 and ac.fuel > 0.0)
			elif dist > eff_range_px:
				# 对准但超出雷达范围：cruise 稳步推进
				ac.target_speed_kmh = cruise
				set_afterburner(ac, false)
			else:
				# 对准且在雷达范围内：match 稳定累积锁定
				ac.target_speed_kmh = match_kmh
				set_afterburner(ac, false)
			ac.target_speed_kmh = maxf(ac.target_speed_kmh, combat_min_kmh)
		elif is_missile_mode:
			# ======== AI / 沙盒 导弹模式能量管理（v9 sync with tactical）========
			# 和玩家战术偏好统一：距离带 + corner speed 转弯 + match speed 稳锁
			# 区别：AI 的加力辅助转弯由 tactical_aggression 门控（pilot attrs 决定是否激进）
			var corner_kmh := corner_speed_kmh(ac)
			var eff_range_px := ac._effective_missile_range_px()

			# match_kmh: 敌机速度 + 50 kmh 小余量
			var match_kmh := clampf(tgt_speed_kmh + 50.0, combat_min_kmh, cruise)

			# 对准窗口：航向偏差小于此值才算"已对准"
			var align_window_deg := 35.0
			var is_aligned := heading_diff_deg <= align_window_deg

			# turn_target: corner speed
			var turn_target_kmh := maxf(corner_kmh, cruise * 0.85)

			if not is_aligned:
				# 未对准：corner speed 最大转弯率
				ac.target_speed_kmh = turn_target_kmh
				# AI 只在高 aggression（ace 飞行员）时才用加力辅助转弯
				if ac.tactical_aggression > 0.6:
					set_afterburner(ac, my_kmh < turn_target_kmh - 40.0 and ac.fuel > 0.0)
				else:
					set_afterburner(ac, false)
			elif dist > eff_range_px * 1.3 and ac.tactical_aggression > 0.6:
				# 真正远距离（超出有效射程 30%）+ 对准 + 激进 AI → 加力冲刺闭合
				ac.target_speed_kmh = approach_speed
				set_afterburner(ac, my_kmh < approach_speed and ac.fuel > 0.0)
			elif dist > eff_range_px:
				# 对准但超出雷达范围：cruise 稳步推进
				ac.target_speed_kmh = cruise
				set_afterburner(ac, false)
			else:
				# 对准且在雷达范围内：match 稳定累积锁定
				ac.target_speed_kmh = match_kmh
				set_afterburner(ac, false)

			ac.target_speed_kmh = maxf(ac.target_speed_kmh, combat_min_kmh)
			# 高度匹配敌机
			if ac.flat_altitude:
				ac.set_target_tier(ac.combat_target.get_altitude_tier())
			else:
				ac.target_altitude = ac.combat_target.altitude
		else:
			# ======== 机炮模式能量管理（原有逻辑） ========
			var maneuver_speed := cruise * cb.maneuver_speed_mult
			var overshoot_cap := tgt_speed_kmh * cb.overshoot_speed_margin

			# 距离相关的速度上限
			var dist_ratio := clampf(dist / gun_range, 0.0, 3.0)
			var speed_limit: float
			if dist_ratio > 2.0:
				speed_limit = approach_speed
			elif dist_ratio > 1.0:
				var t := (dist_ratio - 1.0)
				speed_limit = lerpf(overshoot_cap, approach_speed, t)
			else:
				speed_limit = overshoot_cap

			var has_overshot := not ac._in_rear_hemisphere and dist < gun_range * 1.5
			var recover_speed := tgt_speed_kmh * 0.85

			# ── 慢目标速度约束（直升机/轰炸机/UAV 等）──
			# 判据：目标速度 < 自己巡航速度的 40%（稳定判据，不依赖 my_kmh，避免振荡）
			# 按 BFM 分两种情况（2026-04-21，详见 docs/changelogs/player-ai-log.md）：
			#   A. 已咬尾（后半球 + 机头±30° 内）→ 目标速度 × 1.2，保持射程稳定射击
			#   B. 对头/横切/剪式 → 压到角点速度 corner_speed_kmh()，小半径高角速度
			#      等敌人过顶后以最短时间拉 180° 反咬后半球
			# 公式全部派生自当前 params（stall / G-limit / gun_range），升级自动生效
			var is_slow_target := is_slow_target_persistent
			if is_slow_target:
				var tail_aligned := ac._in_rear_hemisphere and heading_diff_deg < 30.0
				# 2026-04-22：如果目标速度 ×1.2 < combat_min（匹配被兜底到失速 ×1.8，毫无意义），
				# 说明目标实质上是静止（直升机 ~216 km/h vs combat_min ~400 km/h）。
				# 此时"咬尾匹配速度"反而把战斗机自废成慢飞标靶 —— 应该像对地 strafe 一样
				# 加力掠过。combat_min × 1.1 加一点滞回，防止 approach 本身贴着 combat_min 抖。
				var match_hits_floor := tgt_speed_kmh * 1.2 < combat_min_kmh * 1.1
				if match_hits_floor:
					# 近静止目标（直升机等）：加力掠袭，不降速匹配
					ac.target_speed_kmh = approach_speed
					set_afterburner(ac, my_kmh < approach_speed - 50.0 and ac.fuel > 0.0)
				elif tail_aligned:
					ac.target_speed_kmh = maxf(combat_min_kmh, tgt_speed_kmh * 1.2)
					set_afterburner(ac, false)
				else:
					ac.target_speed_kmh = corner_speed_kmh(ac)
					set_afterburner(ac, false)
			elif ac.is_firing:
				ac.target_speed_kmh = maneuver_speed
				set_afterburner(ac, false)
			elif has_overshot:
				ac.target_speed_kmh = recover_speed
				set_afterburner(ac, false)
			elif needs_big_turn:
				var turn_ratio := clampf(
					(heading_diff_deg - cb.turn_slow_angle) / (cb.turn_slow_max_angle - cb.turn_slow_angle),
					0.0, 1.0)
				var conservative_spd := lerpf(maneuver_speed, turn_speed, turn_ratio)
				# tactical_aggression 高 → 维持角点速度获得最小半径
				if ac.tactical_aggression > 0.01:
					var corner_kmh := corner_speed_kmh(ac)
					var aggressive_spd := maxf(corner_kmh, cruise * 0.9)
					ac.target_speed_kmh = lerpf(conservative_spd, aggressive_spd, clampf(ac.tactical_aggression, 0.0, 1.0))
				else:
					ac.target_speed_kmh = conservative_spd
				set_afterburner(ac, false)
			elif ac._in_rear_hemisphere:
				var max_kmh := ac.params.max_speed if ac.params else 2100.0
				if dist > gun_range * 0.5:
					ac.target_speed_kmh = max_kmh
					set_afterburner(ac, ac.fuel > 0.0)
				else:
					ac.target_speed_kmh = overshoot_cap
					set_afterburner(ac, false)
			elif dist > gun_range * cb.intercept_range_mult:
				ac.target_speed_kmh = approach_speed
				set_afterburner(ac, my_kmh < approach_speed and ac.fuel > 0.0)
			else:
				ac.target_speed_kmh = maneuver_speed
				set_afterburner(ac, false)

			# 战斗速度下限：防止追踪慢速目标时降到失速边缘抽搐
			ac.target_speed_kmh = maxf(ac.target_speed_kmh, combat_min_kmh)

			# ---- 高度⇌速度 能量转换（仅机炮模式） ----
			var my_kmh_now := ac.speed * 3.6
			var desired_kmh := ac.target_speed_kmh

			if ac.flat_altitude:
				# 扁平模式：用档位切换实现能量转换
				var tgt_tier := ac.combat_target.get_altitude_tier()
				ac.set_target_tier(tgt_tier)
				if has_overshot and my_kmh_now > desired_kmh:
					ac.set_target_tier(ac.tier_above())  # 爬升减速
				elif my_kmh_now > desired_kmh * cb.climb_brake_overspeed:
					ac.set_target_tier(ac.tier_above())  # 爬升刹车
				elif my_kmh_now < tgt_speed_kmh * cb.dive_speed_ratio:
					ac.set_target_tier(ac.tier_below())  # 俯冲换速
				elif needs_big_turn and my_kmh_now > desired_kmh * 1.1:
					ac.set_target_tier(ac.tier_above())  # 转弯前爬升
			else:
				var combat_alt := ac.combat_target.altitude
				var alt_ceiling := combat_alt + cb.climb_brake_height * 2.0
				ac.target_altitude = combat_alt

				if has_overshot and my_kmh_now > desired_kmh:
					ac.target_altitude = minf(combat_alt + cb.climb_brake_height * 1.5, alt_ceiling)
				elif my_kmh_now > desired_kmh * cb.climb_brake_overspeed:
					var excess_ratio := (my_kmh_now - desired_kmh) / maxf(desired_kmh, 100.0)
					var climb_amount := cb.climb_brake_height * clampf(excess_ratio * 3.0, 0.3, 1.0)
					ac.target_altitude = minf(combat_alt + climb_amount, alt_ceiling)
				elif my_kmh_now < tgt_speed_kmh * cb.dive_speed_ratio and ac.altitude > cb.dive_min_altitude:
					ac.target_altitude = maxf(combat_alt - cb.dive_depth, cb.dive_floor)
				elif needs_big_turn and my_kmh_now > desired_kmh * 1.1:
					ac.target_altitude = minf(combat_alt + cb.climb_brake_height * 0.5, alt_ceiling)
	else:
		# ---- 巡航模式 ----
		# 编队跟随时由AI控制器管理速度和高度，跳过自主能量管理
		if ac.formation_mode:
			return

		# 玩家战术偏好巡航（点击移动）：距离目标远且航向对齐时开加力冲刺
		if ac.use_tactical_preference and ac.target_position != Vector2.INF:
			var diff_to_tgt := ac.target_position - ac.global_position
			var dist_to_tgt := diff_to_tgt.length()
			var hdg_to_tgt := atan2(diff_to_tgt.x, -diff_to_tgt.y)
			var hdiff_deg := absf(rad_to_deg(Aircraft._angle_diff(hdg_to_tgt, ac.heading)))
			var approach_spd := cruise * cb.approach_speed_mult
			var my_kmh_cr := ac.speed * 3.6
			var corner_kmh_cr := corner_speed_kmh(ac)

			if hdiff_deg > cb.turn_slow_angle:
				# 大角度转弯：维持角点速度，拉满结构 G 获得最小转弯半径
				ac.target_speed_kmh = maxf(corner_kmh_cr, cruise * 0.9)
				set_afterburner(ac, false)
			elif dist_to_tgt > 800.0:
				# 远距离直线冲刺：开加力
				ac.target_speed_kmh = approach_spd
				set_afterburner(ac, my_kmh_cr < approach_spd and ac.fuel > 0.0)
			else:
				ac.target_speed_kmh = cruise
				set_afterburner(ac, false)
		else:
			set_afterburner(ac, false)
			ac.target_speed_kmh = cruise

		if ac.flat_altitude:
			if ac.use_tactical_preference:
				# 战术偏好：按玩家设定调整巡航高度
				match ac.altitude_preference:
					Aircraft.AltitudePreference.PREFER_CLIMB:
						ac.set_target_tier(CombatUnit.AltitudeTier.HIGH)
					Aircraft.AltitudePreference.PREFER_LOW:
						ac.set_target_tier(CombatUnit.AltitudeTier.LOW)
			else:
				# 扁平模式：富余速度时升档蓄能
				var cruise_ms := cruise / 3.6
				if ac.speed > cruise_ms * cb.climb_speed_ratio and ac.get_altitude_tier() < CombatUnit.AltitudeTier.HIGH:
					ac.set_target_tier(ac.tier_above())
		else:
			var cruise_ms := cruise / 3.6
			if ac.speed > cruise_ms * 1.1 and ac.altitude < ac.target_altitude - 100.0:
				pass
			elif ac.speed > cruise_ms * cb.climb_speed_ratio and ac.altitude < cb.climb_max_altitude:
				ac.target_altitude = minf(ac.altitude + 500.0, cb.climb_max_altitude)
