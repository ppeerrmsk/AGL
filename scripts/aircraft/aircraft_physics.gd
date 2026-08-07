class_name AircraftPhysics
extends RefCounted

## 物理演算子系统（静态工具类）
## 从 aircraft.gd 提取的 _update_target_heading / _update_bank / _update_heading /
## _update_speed / _update_altitude / _update_stall / _update_g_load /
## _apply_movement / _max_bank_angle / _effective_max_g /
## _corner_speed_kmh / _stall_speed / _max_speed_at_altitude / _air_density_ratio /
## _update_shock_absorb / _set_afterburner / _update_fuel / _update_energy_management /
## _max_bank_angle_at_speed 全套逻辑。
##
## 状态仍住在 Aircraft（heading / bank_angle / speed / altitude / g_load / fuel /
## is_afterburner / _ab_cooldown / _committed_turn_sign 等）。
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

# ── 临界阻尼 PD 转弯控制（SEAM-012 根治，2026-06-07）──
# 控制律：target_turn_rate = kp·heading_diff − kd·current_turn_rate
#         bank = atan(target_turn_rate · v / g)（协调转弯反推）
# kd 项 = 旧位置式(P)控制缺失的速度(转速)阻尼项；接近目标航向且转速高时自动提前滚出，
# 从根上消除"航向过冲→翻号→来回"的欠阻尼极限环。无需 bank-flip 守卫 / 去抖等治标补丁。
# 注：用 static var 而非 const，方便 test_turn_physics 无头扫参；定稿值即默认值。
static var PD_KP_BASE: float = 3.0       ## PD 比例增益基数（rad/s per rad 航向误差）；combat_bank_aggression 在其上缩放
                                          ## 注：大误差(硬转)下 kp·e 早已饱和到 max_bank，kp 只影响小误差精跟随。
                                          ## 实测调低 kp 能减少同向"呼吸"但牺牲精瞄+恶化退化追击案例，3.0 是平衡点
static var PD_KD_SCALE: float = 3.0       ## PD 阻尼标尺；实际 kd = clamp(PD_KD_SCALE / roll_rate, …)：滚转越慢→阻尼越大→维持临界阻尼
static var PD_KD_MIN: float = 0.35       ## kd 下限（快滚转机防欠阻尼残余过冲）
static var PD_KD_MAX: float = 1.60       ## kd 上限（极慢滚转机防过阻尼僵滞/转弯迟钝）
static var TURN_RATE_FILT_ALPHA: float = 0.30  ## D 项转速低通系数：协调转弯下 ω 几乎一帧跟上指令，
                                          ## 直接反馈裸 ω 会形成单帧代数环(−kd)^n 交替抖；低通到 ~3 帧时间常数即破环
                                          ## 又保留真实滚出时标(~0.2~0.4s)的阻尼。是 PD 跨"近瞬时执行器"稳定的关键。
# LOS 前馈：理论上尾追转弯目标(e≈0 仍需稳态转速)需要它，但无头扫参实测在离散物理 +
# AI 分频跳变参考下恒为害（前馈在参考跳变时尖刺过冲，得不偿失），故默认 0 关闭。
# 保留管线，待将来有抗跳变的 LOS 估计再启用。残留的是同向 bank 幅度"呼吸"，非用户关心的大坡反转。
static var PD_LOS_FF: float = 0.0         ## 目标 LOS 角速度前馈系数（默认 0 关闭，见上）
static var PD_LOS_RATE_CAP: float = 0.45  ## LOS 角速度前馈封顶（rad/s）：喂入前馈的合法 LOS 上限
static var PD_LOS_FILT_ALPHA: float = 0.08  ## LOS 角速度专用慢低通
static var PD_LOS_SANE_CAP: float = 1.0   ## LOS 异常剔除阈值（rad/s）：超过此值视为参考跳变尖刺(瞬移/AI 分频重指 lead 点)，丢弃不喂前馈滤波

# ── 冲击吸收 ──
const SHOCK_ABSORB_RATE: float = 1.0      ## HP/秒回复速率（慢，强调"逐渐恢复"而非"立即抵消"）



## ⚠ 性能取舍：update_* 直接读写 ac，避免 FlightState populate/write_back 的 22+12 字段
## 拷贝开销（22 ac × 60Hz × 5 wrappers ≈ 449k 字段操作/秒，~13ms/秒）。
## step_*(state) 仍然是 prediction 唯一入口。两份实现的算法**必须一致**——任何对
## 物理公式的改动都要同时改 update_*（这里）和 step_*（下方），否则预测会与实飞行撕裂。
## 共享纯 helper：compute_target_bank / max_bank_angle_at_speed_pure / effective_max_g 等
## 同时被两边调用，是公式真正的"单一来源"。

static func update_target_heading(ac: Aircraft) -> void:
	var _hm_th := ac.get_herbst()
	if _hm_th and _hm_th.is_active:
		return
	if ac.target_position == Vector2.INF:
		return
	var diff := ac.target_position - ac.global_position
	var dist := diff.length()
	var arrival_dist := maxf(150.0, ac.speed * CombatUnit.PIXELS_PER_METER * 2.0)
	if dist < arrival_dist and ac.combat_target == null and not ac.keep_target_on_arrival:
		ac.target_position = Vector2.INF
		ac._evasion_override = false
		return
	ac._cached_target_heading = atan2(diff.x, -diff.y)
	ac._proximity_damping = clampf((dist - arrival_dist) / (arrival_dist * 2.0), 0.0, 1.0)


static func update_bank(ac: Aircraft, delta: float) -> void:
	# Herbst 守卫
	var _hm_bank := ac.get_herbst()
	if _hm_bank and _hm_bank.is_active:
		var roll_rate_h: float = ac.params.roll_rate if ac.params else 4.0
		ac.bank_angle = move_toward(ac.bank_angle, 0.0, roll_rate_h * delta)
		return

	if ac.target_position == Vector2.INF and abs(ac.bank_angle) < 0.01:
		ac.bank_angle = 0.0
		return

	var heading_diff := Aircraft._angle_diff(ac._cached_target_heading, ac.heading)

	if ac.target_position == Vector2.INF:
		heading_diff = 0.0
		ac._committed_turn_sign = 0.0

	# 转弯方向锁定
	if abs(heading_diff) > 2.5:
		if ac._committed_turn_sign == 0.0:
			ac._committed_turn_sign = signf(heading_diff)
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

	var stall_base_kmh: float = ac.params.stall_speed_base if ac.params else 220.0
	var stall_at_g_ms: float = stall_base_kmh * pow(maxf(ac.g_load, 1.0), 0.4) / 3.6

	# 当前实际转速（带符号），= PD 控制律的 D 项输入（协调转弯 ω = g·tan(bank)/v）
	# 低通滤波破除"协调转弯下 ω 一帧跟上指令 → (−kd)^n 单帧交替"代数环（见 TURN_RATE_FILT_ALPHA）
	var cur_v: float = maxf(ac.speed, 50.0)
	var current_turn_rate: float = CombatUnit.GRAVITY * tan(ac.bank_angle) / cur_v
	ac._turn_rate_filt = lerpf(ac._turn_rate_filt, current_turn_rate, TURN_RATE_FILT_ALPHA)
	var damp_turn_rate: float = ac._turn_rate_filt

	# 目标 LOS 角速度（前馈项）：追转弯目标时补偿稳态转速。
	# 默认 PD_LOS_FF=0（前馈关闭，见常量注释）→ 跳过整段计算，零成本
	var ff_los: float = 0.0
	if PD_LOS_FF != 0.0:
		if ac.target_position != Vector2.INF:
			if not is_nan(ac._prev_tgt_heading_pd):
				var raw: float = Aircraft._angle_diff(ac._cached_target_heading, ac._prev_tgt_heading_pd) / maxf(delta, 0.0001)
				# 异常剔除：瞬移/AI 分频重指 lead 点产生的 LOS 尖刺远超物理转速 → 丢弃，保持上次滤波值（防前馈过冲）
				if absf(raw) <= PD_LOS_SANE_CAP:
					ac._los_rate_filt = lerpf(ac._los_rate_filt, clampf(raw, -PD_LOS_RATE_CAP, PD_LOS_RATE_CAP), PD_LOS_FILT_ALPHA)
			ac._prev_tgt_heading_pd = ac._cached_target_heading
		else:
			ac._prev_tgt_heading_pd = NAN
			ac._los_rate_filt = 0.0
		ff_los = ac._los_rate_filt

	# max_bank（直接调原版 max_bank_angle，避免 effective_max_g + _dynamic_safe_margin 重复 fetch）
	var max_bank := max_bank_angle(ac)
	# plan 级坡度上限（LINE_UP 充能平台等武器纪律；⚠ step_bank 镜像同步，SEAM-017）
	if ac._plan_bank_limit_rad > 0.0:
		max_bank = minf(max_bank, ac._plan_bank_limit_rad)
	var in_combat := ac.combat_target != null

	if in_combat and abs(heading_diff) > 0.5 and ac.tactical_aggression < 0.999:
		var sustained_g: float = ac.params.max_g if ac.params else 9.0
		var turn_g_capped := lerpf(sustained_g * 0.7, sustained_g, clampf((PI - abs(heading_diff)) / (PI - 0.5), 0.0, 1.0))
		var turn_g := lerpf(turn_g_capped, effective_max_g(ac), clampf(ac.tactical_aggression, 0.0, 1.0))
		var sustained_bank := acos(1.0 / maxf(turn_g, 1.01))
		max_bank = minf(max_bank, sustained_bank)

	# PD 增益：Kp 受战斗激进度缩放；Kd 随 roll_rate 反比（维持临界阻尼，慢滚机阻尼更大）
	var roll_rate_base: float = ac.params.roll_rate if ac.params else 4.0
	var aggression: float = ac._combat_params().combat_bank_aggression if in_combat else 1.0
	var kp: float = PD_KP_BASE * aggression
	var kd: float = clampf(PD_KD_SCALE / maxf(roll_rate_base, 0.5), PD_KD_MIN, PD_KD_MAX)
	var deadzone: float = ac._combat_params().combat_half_bank_diff if in_combat else 0.02

	var msl_phase_now: int = ac._get_missile_phase() \
			if (in_combat and ac.weapon_mode == Aircraft.WeaponMode.MISSILE) else 0
	var target_bank: float = compute_target_bank(
			heading_diff, damp_turn_rate, ff_los, cur_v, max_bank, in_combat,
			ac.use_tactical_preference, ac.weapon_mode, msl_phase_now,
			ac.formation_mode and not ac._formation_full_bank, ac._proximity_damping, deadzone, kp, kd)

	# 失速回正
	if ac.is_stalled:
		target_bank = 0.0
	elif ac._stall_recovery_timer > 0.0:
		var recovery_ratio := 1.0 - clampf(ac._stall_recovery_timer / 1.0, 0.0, 1.0)
		target_bank *= recovery_ratio

	# Roll rate
	var roll_rate_val: float = ac.params.roll_rate if ac.params else 4.0
	if ac.speed < stall_at_g_ms:
		var ctrl := clampf(ac.speed / maxf(stall_at_g_ms, 1.0), 0.1, 1.0)
		roll_rate_val *= ctrl
	var alt_factor := clampf(ac.altitude / 15000.0, 0.0, 1.0)
	roll_rate_val *= 1.0 + alt_factor * 0.30
	# 722 sig_j36·三发推力：突击 buff 期间滚转 ×1.3
	if ac.sig_j36_assault_active:
		roll_rate_val *= 1.3

	var bank_diff := target_bank - ac.bank_angle
	var max_roll := roll_rate_val * delta
	ac.bank_angle += clampf(bank_diff, -max_roll, max_roll)

	# Bank rate EMA
	if delta > 0.0:
		var instant_rate: float = (ac.bank_angle - ac._prev_bank_for_rate) / delta
		ac._bank_rate_rad_s = ac._bank_rate_rad_s * 0.5 + instant_rate * 0.5
	ac._prev_bank_for_rate = ac.bank_angle


static func update_heading(ac: Aircraft, delta: float) -> void:
	var _hm_hdg := ac.get_herbst()
	if _hm_hdg and _hm_hdg.is_active:
		return
	if abs(ac.bank_angle) < 0.001:
		return
	var speed_ms := maxf(ac.speed, 1.0)
	var turn_rate := CombatUnit.GRAVITY * tan(ac.bank_angle) / speed_ms

	var stall_base_kmh: float = ac.params.stall_speed_base if ac.params else 220.0
	var stall_at_g_ms := stall_base_kmh * pow(maxf(ac.g_load, 1.0), 0.4) / 3.6
	if ac.speed < stall_at_g_ms:
		var control_ratio := clampf(ac.speed / maxf(stall_at_g_ms, 1.0), 0.0, 1.0)
		turn_rate *= control_ratio * control_ratio

	ac.heading += turn_rate * delta
	ac.heading = fmod(ac.heading + PI, TAU) - PI


static func update_speed(ac: Aircraft, delta: float) -> void:
	# B2 统一机动守卫：Cobra 全程 / Herbst 的 DECEL+TURN 让位；
	# Herbst ACCEL 阶段刻意交还本函数（开 AB 让物理自然拉回巡航）
	if maneuver_overrides_speed(ac):
		return

	var target_ms: float
	if ac.hard_brake:
		# 急刹（2026-07-03 用户定稿）：减到失速软地板为止——刹车 = 减到最小可控速度，
		# 不能刹进失速自杀。配合 survivor_mode 急刹只作用亲控长机（僚机靠编队逻辑自行减速）。
		var stall_base_hb: float = ac.params.stall_speed_base if ac.params else 220.0
		target_ms = stall_base_hb * pow(maxf(ac.g_load, 1.0), 0.4) / 3.6 * 1.05
	else:
		var t_kmh: float = ac.target_speed_kmh
		if ac.evasion_mode:
			var cruise_mult: float = float(ac.evasion_modifiers.get("cruise_speed_mult", 1.0))
			if cruise_mult != 1.0:
				t_kmh *= cruise_mult
		# 加力窗口（spec afterburner-mode）：目标速度地板 = 有效顶速——
		# 无论有无移动命令都全速（含僚机；玩家中途下令退出 evasion 后地板仍在）
		if ac.afterburner_window_active:
			t_kmh = maxf(t_kmh, effective_max_speed_kmh(ac))
		if ac.status_slow_active and t_kmh > StatusEffects.SLOW_SPEED_CAP_KMH:
			t_kmh = StatusEffects.SLOW_SPEED_CAP_KMH
		if ac.laser_stall_pressure_active():
			t_kmh = minf(t_kmh, stall_speed(ac) * 0.90)
		target_ms = t_kmh / 3.6

		var max_climb_norm: float = ac.params.climb_rate_max if ac.params else 250.0
		var vs_norm: float = clampf(ac.vertical_speed / maxf(max_climb_norm, 1.0), -1.0, 1.0)
		# 722 sig_typhoon·超巡爬升：爬升不削目标速度（俯冲增速照旧；PE↔KE 物理不豁免）
		if not (ac.sig_typhoon_active and vs_norm > 0.0):
			target_ms *= 1.0 - vs_norm * 0.10

		var max_speed_ms := max_speed_at_altitude(ac) / 3.6
		if ac.evasion_mode:
			var cm: float = float(ac.evasion_modifiers.get("cruise_speed_mult", 1.0))
			if cm > 1.0:
				max_speed_ms *= cm
		# 加力窗口：物理 cap 放开到有效顶速（与 evasion cruise_mult 抬 cap 同语义）
		if ac.afterburner_window_active:
			max_speed_ms = maxf(max_speed_ms, effective_max_speed_kmh(ac) / 3.6)
		target_ms = minf(target_ms, max_speed_ms)

		var stall_base_kmh: float = ac.params.stall_speed_base if ac.params else 220.0
		var stall_at_g_ms := stall_base_kmh * pow(maxf(ac.g_load, 1.0), 0.4) / 3.6
		var min_safe_ms := stall_at_g_ms * 1.05
		if not ac.laser_stall_pressure_active():
			target_ms = maxf(target_ms, min_safe_ms)

	var accel_rate: float = ac.params.acceleration if ac.params else 50.0
	if ac.status_overload_active:
		accel_rate *= StatusEffects.OVERLOAD_ACCEL_MULT
	# 加力窗口：加速度 ×3（spec afterburner-mode；replace_all 同步实物理与预测镜像两处）
	if ac.afterburner_window_active:
		accel_rate *= AB_WINDOW_ACCEL_MULT
	var decel_rate: float = (ac.params.deceleration if ac.params else 80.0) * ac._executioner_decel_mult()
	if ac.is_player_squad() and ac.status_bloodlust_active and ac.has_meta("upgrade_stacks"):
		var bl_stacks: Dictionary = ac.get_meta("upgrade_stacks")
		if int(bl_stacks.get(SkillHooks.SKILL_BLOODLUST_ARMOR_MOBILITY, 0)) > 0:
			accel_rate *= SkillHooks.BLOODLUST_ACCEL_MULT
			decel_rate *= SkillHooks.BLOODLUST_ACCEL_MULT
	# 722 签名：三发推力（J-36 突击 buff）加/减速 ×1.4；近太空冲刺（MiG-41）俯冲加速 ×1.5
	if ac.sig_j36_assault_active:
		accel_rate *= 1.4
		decel_rate *= 1.4
	if ac.hunter_assault_active:
		accel_rate *= 1.2
		decel_rate *= 1.2
	if ac._sig_mig41_dive_timer > 0.0:
		accel_rate *= 1.5
	if ac.is_afterburner and not ac.hard_brake:
		var ab_mult: float = ac.params.afterburner_thrust_mult if ac.params else 1.5
		accel_rate *= ab_mult
	if ac.hard_brake:
		# 急刹减速效率随速度衰减（阻力 ∝ v）：巡航段全额 deceleration，逼近失速地板时
		# 衰减到 35%。deceleration 按机型差异化（低级机天然刹得肉），
		# "轻按一秒速度就到底"不再发生。验收：--bench=hard_brake。
		const HARD_BRAKE_DRAG_FLOOR := 0.35  # ⚠ 与 step_speed 镜像同步（SEAM-017）
		var cruise_ms_hb: float = (ac.params.cruise_speed if ac.params else 900.0) / 3.6
		decel_rate *= clampf(ac.speed / maxf(cruise_ms_hb, 1.0), HARD_BRAKE_DRAG_FLOOR, 1.0)

	var speed_diff := target_ms - ac.speed
	if speed_diff >= 0:
		ac.speed += minf(speed_diff, accel_rate * delta)
	else:
		ac.speed += maxf(speed_diff, -decel_rate * delta)

	const G_DRAG_GLOBAL_MULT := 0.4
	const STRUCT_BLEED_FACTOR := 6.0  # 超持续 max_g 部分的额外掉速 (m/s² per G)；手感调参旋钮
	var alt_factor := clampf(ac.altitude / 15000.0, 0.0, 1.0)
	var alt_drag_mult := 1.0 - alt_factor * 0.30
	var g_drag := (ac.params.g_drag_factor if ac.params else 3.0) * G_DRAG_GLOBAL_MULT * alt_drag_mult
	var base_loss := maxf(ac.g_load - 1.0, 0.0) * g_drag
	# 双层 G 能量自限：超过持续 max_g 的部分额外狠掉速（瞬时结构 G 维持不住）
	# 编队托管豁免：僚机归队/追赶时频繁切向急转，若再吃结构超 G 掉速会"追不上长机"
	# → formation_mode 下只保留 base_loss，跳过 struct_loss（追赶手感优先；战斗/玩家不豁免）
	var sustained_g := effective_max_g(ac)
	var over_g := maxf(ac.g_load - sustained_g, 0.0)
	var struct_loss := 0.0 if ac.formation_mode else over_g * STRUCT_BLEED_FACTOR * alt_drag_mult
	# 🚫 头号硬约束：G 引致掉速最多拽到角点速度地板，绝不更低（转弯不得自陷失速）
	# 只钳制 G 掉速；直线按 target_speed 正常减速不受影响
	var g_loss_total := base_loss + struct_loss
	if ac.hunter_assault_active:
		g_loss_total *= 0.7
	var no_stall_floor_ms := corner_speed_kmh(ac) / 3.6
	var allowed_g_loss := maxf(ac.speed - no_stall_floor_ms, 0.0)
	ac.speed = maxf(ac.speed - minf(g_loss_total * delta, allowed_g_loss), 0.0)

	const PE_KE_BOOST := 2.5
	var spd := maxf(ac.speed, 10.0)
	var gravity_effect := CombatUnit.GRAVITY * ac.vertical_speed / spd * PE_KE_BOOST
	ac.speed -= gravity_effect * delta

	ac.speed = maxf(ac.speed, 0.0)
	if ac.orbit_speed_cap > 0.0 and ac.speed > ac.orbit_speed_cap:
		ac.speed = ac.orbit_speed_cap


static func update_altitude(ac: Aircraft, delta: float) -> void:
	# 垂直越过按绝对曲线主张高度；常规收敛必须让位，避免同帧重复爬升/俯冲。
	if ac._active_special == Aircraft.ActiveSpecialManeuver.VERTICAL_BREAK:
		return
	if ac.is_stalled:
		ac.altitude += ac.vertical_speed * delta
		ac.altitude = maxf(ac.altitude, 0.0)
		return
	var alt_diff := ac.target_altitude - ac.altitude
	var alt_mult: float = ac.altitude_authority_mult
	# alt_mult 只放大响应度(gain/smooth)，物理顶速最多 +30% —— 防止 PE↔KE 反抽吃光横速
	# (vapor_dodge × HIGH 档 target_altitude 翻车点，见 docs/architecture/known-seams.md)
	var base_climb: float = ac.params.climb_rate_max if ac.params else 250.0
	# 722 sig_typhoon·超巡爬升：高度调整速率 ×1.5（直接抬物理爬升顶速）
	if ac.sig_typhoon_active:
		base_climb *= 1.5
	var max_climb := base_climb * minf(alt_mult, 1.3)
	var gain := 0.4 * alt_mult
	var smooth_rate := 8.0 * alt_mult
	var target_vs: float
	if abs(alt_diff) < 10.0:
		target_vs = 0.0
	else:
		target_vs = clampf(alt_diff * gain, -max_climb, max_climb)

	if ac._stall_recovery_timer > 0.0 and target_vs > 0.0:
		target_vs = 0.0

	if target_vs > 0.0:
		var stall_base_kmh: float = ac.params.stall_speed_base if ac.params else 220.0
		var stall_at_g_ms: float = stall_base_kmh * pow(maxf(ac.g_load, 1.0), 0.4) / 3.6
		var speed_margin := ac.speed - stall_at_g_ms
		if speed_margin < 50.0:
			var climb_authority := clampf(speed_margin / 50.0, 0.0, 1.0)
			target_vs *= climb_authority

	ac.vertical_speed = lerpf(ac.vertical_speed, target_vs, delta * smooth_rate)
	ac.altitude += ac.vertical_speed * delta
	ac.altitude = maxf(ac.altitude, 0.0)
	if ac.is_player_squad() and ac.alt_change_stealth_factor > 0.0:
		var instant_v: float = absf(ac.vertical_speed)
		ac._alt_velocity = lerpf(ac._alt_velocity, instant_v, clampf(delta * 4.0, 0.0, 1.0))


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
	if maneuver_overrides_g(ac):
		return  # 战术机动（Cobra/Herbst）期间 G 力由模块直接设置
	if abs(ac.bank_angle) < 0.001:
		ac.g_load = 1.0
	else:
		ac.g_load = absf(1.0 / cos(ac.bank_angle))


# ── B2 机动接管守卫（2026-07-03，重构计划 §3）──
# Cobra/Herbst 挂在 Aircraft 子节点、每帧在物理之后跑并直写 speed/g_load。
# 旧守卫只查 Cobra，Herbst 被迫"同帧双写自卫"（先被本模块写一次、再自己钳回），
# 正确性依赖 Godot 父先子后树序——守卫矩阵不对称的实证。统一成下面两个谓词，
# 以后新增机动模块只改这里，不再往各 update_* 里散点补 if。

## 机动模块是否接管速度（update_speed 让位）
static func maneuver_overrides_speed(ac: Aircraft) -> bool:
	var m := ac.get_maneuver()
	if m and m.is_active:
		return true
	var h := ac.get_herbst()
	# Herbst ACCEL 阶段不接管速度：开加力交还 update_speed 自然拉回巡航
	return h != null and h.is_active and h.phase != HerbstManeuver.Phase.ACCEL

## 机动模块是否接管 G 力（update_g_load 让位；Herbst 全程自设 G）
static func maneuver_overrides_g(ac: Aircraft) -> bool:
	var m := ac.get_maneuver()
	if m and m.is_active:
		return true
	var h := ac.get_herbst()
	return h != null and h.is_active


static func apply_movement(ac: Aircraft, delta: float) -> void:
	# heading: 0=上(北), 顺时针为正
	# Godot 2D: x右, y下
	var velocity := Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed * CombatUnit.PIXELS_PER_METER
	ac.global_position += velocity * delta


# ========== 辅助计算 ==========

static func max_bank_angle(ac: Aircraft) -> float:
	# 物理瞬时上限用结构 G（猛拉可达）；能量自限靠掉速把稳态拽回持续 G
	var max_g_val := effective_max_g_instant(ac)
	# G = 1/cos(bank) => bank = acos(1/G)
	var g_limited_bank := acos(1.0 / max_g_val)

	# 速度限制：不允许拉到会导致失速的G力
	# 失速速度 V_stall = V_base * sqrt(G)，所以允许的最大G = (V_current / V_base)²
	# 留 20% 安全余量防止拉G后立即失速抽搐
	var stall_base := (ac.params.stall_speed_base if ac.params else 220.0) / 3.6  # m/s
	var safe_margin := _dynamic_safe_margin(ac)  # §B1/B2 BLOODLUST/被锁时降到 1.0；预测线共用此 helper
	if ac.speed > stall_base * safe_margin:
		var effective_speed := ac.speed / safe_margin  # 用折减后的速度计算允许G
		var max_g_for_speed := (effective_speed / stall_base) * (effective_speed / stall_base)
		var speed_limited_bank := acos(1.0 / maxf(max_g_for_speed, 1.01))
		return minf(g_limited_bank, speed_limited_bank)
	else:
		# 速度接近/低于安全线，线性衰减到几乎不能拉G
		var ratio := clampf(ac.speed / (stall_base * safe_margin), 0.0, 1.0)
		return STALL_BANK_MIN + ratio * STALL_BANK_RANGE  # 0.1~0.3 rad (约6°~17°)


## 机动性 G buff 乘数（云/被锁恐慌/血怒护甲）——持续 G 与瞬时结构 G 共享同一套乘数（SEAM-001）
## 未来任何 G 类 buff 只在此处加一段，即可同时透传持续 + 瞬时，AI 战术层自动感知
static func _g_buff_mult(ac: Aircraft) -> float:
	var m := 1.0
	# 云中：能见度差、气流扰动导致机动受限
	if ac.cloud_state == 2:
		m *= 0.9
	# §C 玩家技能"被锁时 +G"：is_locked 时按 lock_panic_g_mult 加成
	if ac.is_locked and ac.lock_panic_g_mult != 1.0:
		m *= ac.lock_panic_g_mult
	# 玩家技能"血怒护甲"：BLOODLUST 期间 max_g ×1.2
	if ac.is_player_squad() and ac.status_bloodlust_active and ac.has_meta("upgrade_stacks"):
		var stacks: Dictionary = ac.get_meta("upgrade_stacks")
		if int(stacks.get(SkillHooks.SKILL_BLOODLUST_ARMOR_MOBILITY, 0)) > 0:
			m *= SkillHooks.BLOODLUST_G_MULT
	# 玩家技能"保卫阵地"：防守圈内回转强化（720 批；squad_cmd 维护 flag）
	if ac.guard_zone_buff_active:
		m *= GUARD_ZONE_G_MULT
	return m


static func effective_max_g(ac: Aircraft) -> float:
	## 持续 G（可长期维持）：稳态转弯 / AI 战术规划 / corner speed / 稳态 bank cap 的依据
	var g := ac.params.max_g if ac.params else 9.0
	# 722 sig_j36·三发推力：突击 buff 期间 +2G（加法先于乘 buff，AI 经本 accessor 自动感知）
	if ac.sig_j36_assault_active:
		g += 2.0
	if ac.hunter_assault_active:
		g += 2.0
	return g * _g_buff_mult(ac)


static func effective_max_g_instant(ac: Aircraft) -> float:
	## 瞬时结构 G（猛拉入弯短暂可达）：仅 max_bank_angle 物理瞬时上限消费；
	## 能量自限（update_speed struct_loss）会靠掉速把速度拽回持续 G 对应的稳态转弯
	var g := ac.params.max_g_structural if ac.params else 12.0
	# 722 sig_j36·三发推力：瞬时结构 G 同步 +2（与持续 G 同源加法）
	if ac.sig_j36_assault_active:
		g += 2.0
	if ac.hunter_assault_active:
		g += 2.0
	return g * _g_buff_mult(ac)


## 角点速度（km/h）：能承受当前 G 极限而不被 max_bank_angle 速度限制卡住的最低速度
## V_corner = V_stall_base × safe_margin × sqrt(G_effective)
## 大 G 转弯时应维持此速度以获得最小转弯半径（不过分减速导致 G 被速度钳制）
static func corner_speed_kmh(ac: Aircraft) -> float:
	var g_target := effective_max_g(ac)
	var stall_base_kmh := ac.params.stall_speed_base if ac.params else 220.0
	# safe_margin 与 max_bank_angle 保持一致（1.2）
	return stall_base_kmh * 1.2 * sqrt(maxf(g_target, 1.0))


# ══════════════════════════════════════════════════════════════════════
#  effective_*() — AI 战术层 buff-aware accessor 层
# ══════════════════════════════════════════════════════════════════════
# 设计原则：
#   1) Situation.from_aircraft 和其他 AI 决策入口**只读这些 accessor**，
#      绝不直接读 ac.params.*（那样会绕过 buff 注入点）
#   2) 零 buff 状态下，accessor 返回值与旧的 params.* 直读完全一致
#      （保证现有导弹/机炮战术手感不被破坏）
#   3) 新增机动性 buff（速度/G/失速/转弯）只在两个地方注入：
#        a. 永久升级 → survivor_player.gd:apply_upgrade 改 params.* 字段
#        b. 状态/模式 buff → 在对应 effective_*() 加 if 块
#      禁止在 update_speed/update_bank 等物理 tick 里散点叠 buff
#   4) 注意区别：effective_max_speed_kmh ≠ max_speed_at_altitude
#        - effective_*: AI 战术参考（不含 q_factor/cloud/building 减成）
#        - max_speed_at_altitude: 物理实际可达上限（含所有减成）
#      物理 cap 仍走 max_speed_at_altitude，AI 目标走 effective_*
# ══════════════════════════════════════════════════════════════════════

## 紧急集合/撤离途中全力加速倍率（spec command-wheel §2.7/§2.7.1，与规避加力同幅同语义）
const COMMAND_SPRINT_MULT := 1.4

## 加力窗口加速度倍率（spec afterburner-mode）：与 AB 推力乘数叠乘，
## 让 6s 窗口内全队可见地冲到顶速（无此项典型机加满速需 ≈7s，窗口刚提速就结束）
const AB_WINDOW_ACCEL_MULT := 3.0
const GUARD_ZONE_G_MULT := 1.15         ## 保卫阵地：防守圈内 G 强化（720 批）
const EVAC_SHIFT_SPRINT_BONUS := 1.15   ## 阵地转移：撤离冲刺追加提速（720 批）

## AI 战术层用的"有效顶速"。零 buff = ac.params.max_speed
## buff 注入点：executioner（永久 stack）+ evasion_modifiers.cruise_speed_mult（模式）
## + command_sprint（紧急集合/撤离途中，command-wheel）
static func effective_max_speed_kmh(ac: Aircraft) -> float:
	var v := ac.params.max_speed if ac.params else 2100.0
	v *= ac._executioner_speed_mult()  # 侩子手 stack：每层 +5%
	v *= ac.speed_by_knight_mult       # 全速推进（720 批 T4）：按骑士轴技能数，cap +40%
	# 722 sig_tornado·地形跟随：低空 +8%（低空突防增速）
	if ac.sig_tornado_active and ac.get_altitude_tier() == CombatUnit.AltitudeTier.LOW:
		v *= 1.08
	if ac.evasion_mode:
		var cm: float = float(ac.evasion_modifiers.get("cruise_speed_mult", 1.0))
		if cm > 1.0:
			v *= cm
	if ac.command_sprint:
		v *= COMMAND_SPRINT_MULT  # 紧急集合/撤离全力加速（command-wheel §2.7）
		if ac.evac_shift_active:
			v *= EVAC_SHIFT_SPRINT_BONUS  # 阵地转移：撤离冲刺再提速（720 批）
	# Mother Goose 干扰场减速走标准 SLOW 状态（cap 至 SLOW_SPEED_CAP_KMH，
	# 由 update_speed 内的 status_slow_active 分支处理 + HUD 显示蓝条）
	return v


## AI 战术层用的"有效巡航速度"。零 buff = ac.params.cruise_speed
static func effective_cruise_speed_kmh(ac: Aircraft) -> float:
	var v := ac.params.cruise_speed if ac.params else 800.0
	# 722 sig_tornado·地形跟随：低空 +8%（与顶速同源）
	if ac.sig_tornado_active and ac.get_altitude_tier() == CombatUnit.AltitudeTier.LOW:
		v *= 1.08
	if ac.evasion_mode:
		var cm: float = float(ac.evasion_modifiers.get("cruise_speed_mult", 1.0))
		if cm > 1.0:
			v *= cm
	if ac.command_sprint:
		v *= COMMAND_SPRINT_MULT  # 紧急集合/撤离全力加速（command-wheel §2.7）
		if ac.evac_shift_active:
			v *= EVAC_SHIFT_SPRINT_BONUS  # 阵地转移：撤离冲刺再提速（720 批）
	return v


## AI 战术层用的"有效失速基数"。永久升级（DOGFIGHT_STALL_MULT 等）已经改了 params 本身，
## 直接读 params.stall_speed_base 即可
static func effective_stall_speed_kmh(ac: Aircraft) -> float:
	return ac.params.stall_speed_base if ac.params else 220.0


## AI 战术用的角点速度（不含 max_bank 的 ×1.2 safe_margin —— 那是物理转弯的安全余量）
## 公式与旧 Situation.from_aircraft 保持同型 stall × √max_g，只是 max_g 走 effective_max_g
## 零 buff 下 = stall × √params.max_g（与旧实现一致）
## 有 BLOODLUST/lock_panic/cloud 时自动随 effective_max_g 抬升
static func effective_corner_speed_kmh(ac: Aircraft) -> float:
	var stall := effective_stall_speed_kmh(ac)
	var g := effective_max_g(ac)
	return stall * sqrt(maxf(g, 1.0))


## 高度机动加成因子（0..1）：0m=0，15000m=1（线性饱和）
## 抽象表达"高空机动余量大"的物理直觉：
##   1) 真实空间中高空有更多垂直机动空间，能量转化更自由
##   2) 游戏 2D 顶视角下不能渲染垂直机动，用 roll_rate 加成 + g_drag 减成代替
##   3) 数值在 +30% / -30% 区间，与云中 ×0.9 debuff 形成"晴 HIGH 灵 vs 云 HIGH 钝"的对比
static func altitude_maneuver_factor(ac: Aircraft) -> float:
	return clampf(ac.altitude / 15000.0, 0.0, 1.0)


static func stall_speed(ac: Aircraft) -> float:
	# V_stall = V_base * pow(G, 0.4)
	# 之前用 sqrt(G) 太严：g=9 时 stall=660km/h，corner_speed 也 660km/h，急转必失速
	# 改 pow(G, 0.4)：g=9 → ×2.41 (529km/h)，g=4 → ×1.74，g=1 → ×1.0
	# 失速门槛更宽松，高 G 急转有缓冲，不会一进 corner 就被卡死
	var base := ac.params.stall_speed_base if ac.params else 220.0
	return base * pow(maxf(ac.g_load, 1.0), 0.4)


static func max_speed_at_altitude(ac: Aircraft) -> float:
	var max_spd := ac.params.max_speed if ac.params else 2100.0
	max_spd *= ac._executioner_speed_mult()  # 侩子手：+5%/层
	# 低空动压上限（q-limit）：海平面 70%，5000m 以上拿满 published max
	# 真实战机：低空空气稠密 → 阻力/结构负载顶住速度（F-16 海平面 ~Mach 1.2）
	# 高空稀薄 → 拿到设计 max（F-16 高空 ~Mach 2）
	# 注：俯冲时的 PE→KE 加成在 update_speed 末尾施加，可短暂顶破此 cap
	# 亚音速机（< Mach 1.05 ≈ 1300 km/h）不受 q-limit 影响 —— 结构动压上限只对超音速有意义
	# 含：F-86 / A-7 / Tu-160 / 直升机（AH-64 / CH-47）等
	var q_factor: float = 1.0
	if max_spd >= 1300.0:
		q_factor = lerpf(0.7, 1.0, clampf(ac.altitude / 5000.0, 0.0, 1.0))
	var v := max_spd * q_factor
	# 云中：气流扰动 + 机翼结冰风险 → 最大速度损失
	if ac.cloud_state == 2:
		v *= 0.9
	# 飞越建筑群：高楼之间气流紊乱 + 视觉障碍 → 进一步减速
	if ac.in_building:
		v *= 0.85
	return v


static func air_density_ratio(ac: Aircraft) -> float:
	return exp(-ac.altitude / AIR_DENSITY_SCALE_M)


## 共享 target_bank 计算 —— 临界阻尼 PD 控制（SEAM-012 根治，2026-06-07）
## 物理 update_bank 与预测线 step_bank/draw_predicted_path 都用，保证公式严格同源。
##
## 控制律：target_turn_rate = kp·heading_diff − kd·current_turn_rate + ff·los_rate
##         bank = atan(target_turn_rate · v / g)（协调转弯反推坡度）
## ── kp·heading_diff 是位置(P)项：航向误差越大压坡越狠。
## ── kd·current_turn_rate 是阻尼(D)项：当前转速越高越扣减目标转速 → 接近目标航向时自动
##    提前滚出，从根上消除旧位置式(P)控制"航向过冲→翻号→来回"的欠阻尼极限环。
## ── ff·los_rate 是前馈项：目标转弯(LOS 角速度≠0)时补偿稳态跟随转速，否则 D 项会与"跟上
##    目标必需的转速"对抗 → 弛豫极限环（追内圈转弯目标尤甚）。
## 因为命令的是"转速"再反推坡度，(g/v) 与 (v/g) 抵消 → 闭环阻尼与速度无关，跨机型/速度稳健。
##
## 模式只调三个旋钮：kp 缩放(激进度)/坡度上限比例(导弹阶段更柔)/死区(微误差不压坡)。
## 纯函数：不读 ac；调用方传入快照值（in_combat/weapon_mode/msl_phase/kp/kd/los_rate/speed 等）。
static func compute_target_bank(
		heading_diff: float,
		current_turn_rate: float,
		los_rate: float,
		speed: float,
		max_bank: float,
		in_combat: bool,
		use_tactical_preference: bool,
		weapon_mode: int,
		msl_phase: int,
		formation_mode: bool,
		proximity_damping: float,
		deadzone: float,
		kp: float,
		kd: float) -> float:
	# 模式决定：Kp 缩放 / 坡度上限比例 / 死区 / 近距降坡
	var kp_scale: float = 1.0
	var cap_frac: float = 1.0
	var dz: float = deadzone
	var prox: float = 1.0
	if in_combat:
		var aggressive_ok: bool = use_tactical_preference \
				or weapon_mode != Aircraft.WeaponMode.MISSILE \
				or msl_phase == 0
		if aggressive_ok:
			pass  # 满激进：kp_scale=1, cap=1
		elif msl_phase == 1:
			# 导弹照射阶段：稳定，柔和压坡
			kp_scale = 0.7
			cap_frac = 0.6
			dz = maxf(dz, 0.03)
		else:
			# 导弹保持(crank)：极稳
			kp_scale = 0.5
			cap_frac = 0.35
			dz = maxf(dz, 0.02)
	elif formation_mode:
		# 注：编队 bank 现由 AircraftFormation 接管，此分支基本不触发
		kp_scale = 0.9
		cap_frac = 0.9
		dz = maxf(dz, 0.03)
	elif use_tactical_preference:
		dz = maxf(dz, 0.02)  # 玩家点击巡航
	else:
		# 通用巡航：近目标降坡（proximity_damping）
		dz = maxf(dz, 0.05)
		prox = proximity_damping

	# P 项死区：航向误差很小就不再压坡（防微抖）；D 阻尼项始终生效 → 残余转速被吸收滚平。
	var e: float = heading_diff if absf(heading_diff) >= dz else 0.0
	var target_turn_rate: float = kp * kp_scale * e - kd * current_turn_rate
	# LOS 前馈（默认 PD_LOS_FF=0 关闭，见常量注释 —— 实测各种形态均为害，保留管线待将来）：
	# 仅"尾追对准"(误差小)时投入，门控 1@对准→0@大误差，避免硬转/跳变时过冲
	if PD_LOS_FF != 0.0:
		var ff_gate: float = 1.0 - smoothstep(0.08, 0.35, absf(heading_diff))
		target_turn_rate += PD_LOS_FF * los_rate * cap_frac * ff_gate
	# 协调转弯反推坡度：bank = atan(ω · v / g)
	var bank_cmd: float = atan(target_turn_rate * speed / CombatUnit.GRAVITY)
	var cap: float = max_bank * cap_frac
	return clampf(bank_cmd, -cap, cap) * prox


## max_bank 系列共享的"安全余量"。零 buff = 1.2；BLOODLUST/被锁恐慌时降到 1.0
## 让低速也能拉满 G 加成（min_safe_ms × 1.05 已在 update_speed 守底，5% 余量保证不立即失速抽搐）
## ⚠ 物理 max_bank_angle 与预测线 max_bank_angle_at_speed 必须用同一个值，否则预测路径撕裂
static func _dynamic_safe_margin(ac: Aircraft) -> float:
	if ac.is_player_squad():
		if ac.status_bloodlust_active and ac.has_meta("upgrade_stacks"):
			var stacks: Dictionary = ac.get_meta("upgrade_stacks")
			if int(stacks.get(SkillHooks.SKILL_BLOODLUST_ARMOR_MOBILITY, 0)) > 0:
				return 1.0
		if ac.is_locked and ac.lock_panic_g_mult != 1.0:
			return 1.0
	return 1.2


## 计算指定速度下的最大坡度角（预测线用）。纯函数版本接受预先算好的 max_g / safe_margin
## 调用方负责传入 effective_max_g(ac) + _dynamic_safe_margin(ac)（或缓存值）
static func max_bank_angle_at_speed_pure(spd: float, stall_base_ms: float, max_g: float, safe_margin: float) -> float:
	var g_limited_bank := acos(1.0 / max_g)
	if spd > stall_base_ms * safe_margin:
		var effective_speed := spd / safe_margin
		var max_g_for_speed := (effective_speed / stall_base_ms) * (effective_speed / stall_base_ms)
		var speed_limited_bank := acos(1.0 / maxf(max_g_for_speed, 1.01))
		return minf(g_limited_bank, speed_limited_bank)
	else:
		var ratio := clampf(spd / (stall_base_ms * safe_margin), 0.0, 1.0)
		return STALL_BANK_MIN + ratio * STALL_BANK_RANGE


## 兼容包裹器：旧调用方走这里
static func max_bank_angle_at_speed(ac: Aircraft, spd: float, stall_base_ms: float) -> float:
	return max_bank_angle_at_speed_pure(spd, stall_base_ms, effective_max_g(ac), _dynamic_safe_margin(ac))


## state-aware 版本：优先用 st.cached_*，否则 lazy compute（实物理 tick 路径）
static func _eff_max_g_st(st: FlightState) -> float:
	if not is_nan(st.cached_max_g):
		return st.cached_max_g
	return effective_max_g(st.ac)


## state-aware 结构 G 版本：基础 max_bank 必须与实飞 max_bank_angle 同口径（结构 G）。
## 2026-07-03 修：预测线此前误用持续 G（9G vs 实飞 12G）→ 预测弧线系统性偏宽 ~30%，
## 实机总"转得比线快"。持续 G（_eff_max_g_st）仍用于 sustained cap 的 aggression lerp。
static func _eff_max_g_instant_st(st: FlightState) -> float:
	if not is_nan(st.cached_max_g_instant):
		return st.cached_max_g_instant
	return effective_max_g_instant(st.ac)


static func _safe_margin_st(st: FlightState) -> float:
	if not is_nan(st.cached_safe_margin):
		return st.cached_safe_margin
	return _dynamic_safe_margin(st.ac)


static func _max_speed_alt_ms_st(st: FlightState) -> float:
	if not is_nan(st.cached_max_speed_alt_ms):
		return st.cached_max_speed_alt_ms
	return max_speed_at_altitude(st.ac) / 3.6


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
	# SLOW debuff：禁止开 AB（关 AB 始终允许）
	if on and ac.status_slow_active:
		return
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
	# P1：planner 已在帧顶写好 target_speed_kmh / is_afterburner / target_altitude，跳过旧能量管理
	if ac.use_tactical_planner:
		return
	var cb := ac._combat_params()
	var cruise := ac.params.cruise_speed if ac.params else 900.0

	if ac.combat_target != null and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed:
		# 地面攻击模式（2026-04-21，详见 docs/changelogs/player-ai-log.md）
		# 分武器模式处理：
		#   - 机炮 / 火箭：地面目标固定，不需要照射；加力掠过 strafe，降低被 AAA 命中概率
		#   - 导弹：未对准先 corner speed 转弯，超射程外 cruise 推进，进射程再 0.7× 稳锁
		#     （2026-04-24：对齐对空导弹分支的距离带；旧版无条件 0.7× 让玩家在 7km 外就主动减速还关 AB）
		if ac.combat_target is GroundUnit:
			if ac.weapon_mode == Aircraft.WeaponMode.MISSILE:
				var eff_range_px_g := ac._effective_missile_range_px()
				var dist_g := Aircraft.effective_distance_px(ac.global_position, ac.altitude,
					ac.combat_target.global_position, ac.combat_target.altitude)
				var to_tgt_g := (ac.combat_target.global_position - ac.global_position).normalized()
				var hdg_to_tgt_g := atan2(to_tgt_g.x, -to_tgt_g.y)
				var hdg_diff_deg_g := absf(rad_to_deg(Aircraft._angle_diff(hdg_to_tgt_g, ac.heading)))
				var my_kmh_g := ac.speed * 3.6
				if hdg_diff_deg_g > 35.0:
					# 未对准：corner speed 最大角速度，必要时加力帮助快速进入最优转弯态
					var turn_target_kmh_g := maxf(corner_speed_kmh(ac), cruise * 0.85)
					ac.target_speed_kmh = turn_target_kmh_g
					set_afterburner(ac, my_kmh_g < turn_target_kmh_g - 40.0 and ac.fuel > 0.0)
				elif dist_g > eff_range_px_g:
					# 对准但在射程外：cruise 推进，快速凑到照射距离
					ac.target_speed_kmh = cruise
					set_afterburner(ac, my_kmh_g < cruise - 50.0 and ac.fuel > 0.0)
				else:
					# 进入射程且对准：降速稳定照射（维持锁定累积）
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
				# 对准且在雷达范围内：判断是否到了"稳锁 camping"状态
				# 2026-04-24 修复：僚机一进雷达范围就降到 match_kmh（tgt+50）看起来"还没靠近就减速"。
				#   真正该进入 match_kmh 的条件应是：① 锁定已开始累积（radar 已在扫），
                                #   或 ② 离目标确实近（≤0.6×射程，稳定照射距离）。
                                #   其他情况继续 cruise 推进闭合距离。
				# 显式 float()：dict.get 返回 Variant，ternary 两分支类型须一致才不报 warning
				var lock_progress: float = float(ac.radar_targets.get(ac.combat_target, 0.0)) if ac.combat_target else 0.0
				var close_camping_dist: float = eff_range_px * 0.6
				if lock_progress > 0.1 or dist < close_camping_dist:
					ac.target_speed_kmh = match_kmh
				else:
					ac.target_speed_kmh = cruise
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
					# 距离守卫：尾后对齐但远超射程时不能锁 tgt×1.2 龟速匹配，
					# 否则 F-16 射程 1000m vs 慢目标（Sentinel 400km/h）会被 480km/h 锁死，
					# 闭合率 ~80km/h → 1500m gap 要 90 秒（player_ai-log 2026-04-25）。
					# 进入射程内（×1.2 滞回）才切回匹配速度稳定射击。
					if dist > gun_range * 1.2:
						ac.target_speed_kmh = approach_speed
						set_afterburner(ac, my_kmh < approach_speed - 50.0 and ac.fuel > 0.0)
					else:
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

		# 规避模式：拉满 max_speed + AB，最大化逃脱能力
		# 高度由 Aircraft._update_evasion 单独驱动（来袭时 LOW↔HIGH 切换），这里只管速度
		# 注意：规避中 target_position 被 _update_evasion 反复改写为垂直规避向量，
		# 让原本的"大角度转弯走 corner_speed"分支频繁触发，反而把 corner_speed (~800)
		# 当成稳态。改成 max_speed 后玩家牺牲一点转弯半径换最大逃脱速度。
		if ac.use_tactical_preference and ac.evasion_mode:
			ac.target_speed_kmh = ac.params.max_speed if ac.params else 2000.0
			set_afterburner(ac, true)
			return

		# 玩家战术偏好巡航（点击移动）：玩家点了地图就要积极冲，不按距离降温
		# （2026-04-24：旧版 dist < 800px 掉回 cruise 关 AB，和"攻击锁定外敌人才加速"表现不一致。
		#  现在只要点了 target_position 就统一加力 approach，让移动和攻击的积极性一致。）
		if ac.use_tactical_preference and ac.target_position != Vector2.INF:
			var diff_to_tgt := ac.target_position - ac.global_position
			var hdg_to_tgt := atan2(diff_to_tgt.x, -diff_to_tgt.y)
			var hdiff_deg := absf(rad_to_deg(Aircraft._angle_diff(hdg_to_tgt, ac.heading)))
			var approach_spd := cruise * cb.approach_speed_mult
			var my_kmh_cr := ac.speed * 3.6
			var corner_kmh_cr := corner_speed_kmh(ac)

			if hdiff_deg > cb.turn_slow_angle:
				# 大角度转弯：corner speed 最小半径，同时加力帮助快速拉到 corner
				var turn_target_kmh_cr := maxf(corner_kmh_cr, cruise * 0.9)
				ac.target_speed_kmh = turn_target_kmh_cr
				set_afterburner(ac, my_kmh_cr < turn_target_kmh_cr - 40.0 and ac.fuel > 0.0)
			else:
				# 对准后：不论距离一律 approach + 加力，玩家点了就要冲
				ac.target_speed_kmh = approach_spd
				set_afterburner(ac, my_kmh_cr < approach_spd and ac.fuel > 0.0)
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


# ══════════════════════════════════════════════════════════════════════
#  step_*() — 纯仿真步进（实物理 tick 与预测线共用）
# ══════════════════════════════════════════════════════════════════════
# 设计原则：
#   1) 实物理 tick：from_aircraft → step_X → write_back（每个 update_X 包裹器内部）
#   2) 预测线：from_aircraft(ac, true) → 循环跑 step_X → 不 write_back
#   3) is_prediction=true 时所有副作用（EventLogger / randf）禁用
#   4) 步进期间读 mutable 字段走 st.*（speed/bank/heading/position/g_load/
#      cached_target_heading/proximity_damping/committed_turn_sign），读 frozen
#      字段走 st.ac.*（params/evasion_modifiers/skills/altitude/cloud_state 等）
#   5) altitude / vertical_speed 在预测中不演化（snapshot 后冻结），update_altitude
#      不参与预测。这对短程预测足够准；超长程切档预测需要时再扩展
# ══════════════════════════════════════════════════════════════════════

const PHYSICS_DT: float = 1.0 / 60.0  ## 与 _physics_process 默认 tick 严格一致


## 目标航向缓存 + 接近衰减。到达目标时清 target_position = INF（外层据此终止预测循环）
static func step_target_heading(st: FlightState) -> void:
	var _hm := st.ac.get_herbst()
	if _hm and _hm.is_active:
		return
	if st.target_position == Vector2.INF:
		return
	var diff := st.target_position - st.position
	var dist := diff.length()
	var arrival_dist := maxf(150.0, st.speed * CombatUnit.PIXELS_PER_METER * 2.0)
	if dist < arrival_dist and st.ac.combat_target == null and not st.ac.keep_target_on_arrival:
		st.target_position = Vector2.INF
		st.evasion_override = false
		return
	st.cached_target_heading = atan2(diff.x, -diff.y)
	st.proximity_damping = clampf((dist - arrival_dist) / (arrival_dist * 2.0), 0.0, 1.0)


## bank 演化（最复杂的一步：方向锁定 + 过冲补偿 + max_bank cap + bank flip 守卫 +
## 失速回正 + roll_rate 限速 + EMA bank_rate 追踪）
static func step_bank(st: FlightState, delta: float) -> void:
	# Herbst 守卫：模块期间强制 bank → 0
	var _hm := st.ac.get_herbst()
	if _hm and _hm.is_active:
		var roll_rate_h: float = st.ac.params.roll_rate if st.ac.params else 4.0
		st.bank_angle = move_toward(st.bank_angle, 0.0, roll_rate_h * delta)
		return

	if st.target_position == Vector2.INF and abs(st.bank_angle) < 0.01:
		st.bank_angle = 0.0
		return

	var heading_diff := Aircraft._angle_diff(st.cached_target_heading, st.heading)

	if st.target_position == Vector2.INF:
		heading_diff = 0.0
		st.committed_turn_sign = 0.0

	# 转弯方向锁定（详见原 update_bank 注释）
	if abs(heading_diff) > 2.5:
		if st.committed_turn_sign == 0.0:
			st.committed_turn_sign = signf(heading_diff)
			if not st.is_prediction and st.ac.use_tactical_preference and st.ac.combat_target != null:
				EventLogger.log_event("PURSUIT_LOCK", st.ac._log_name(),
					"turn_sign=%+d (hdg_diff=%+d°, tgt=%s) branch=%s" % [
						int(st.committed_turn_sign), int(rad_to_deg(heading_diff)),
						st.ac._log_unit_name(st.ac.combat_target), st.ac._pursuit_branch])
		heading_diff = absf(heading_diff) * st.committed_turn_sign
	elif abs(heading_diff) < 1.5:
		if st.committed_turn_sign != 0.0 and not st.is_prediction \
				and st.ac.use_tactical_preference and st.ac.combat_target != null:
			EventLogger.log_event("PURSUIT_UNLOCK", st.ac._log_name(),
				"turn_sign cleared (hdg_diff=%+d°, tgt=%s)" % [
					int(rad_to_deg(heading_diff)), st.ac._log_unit_name(st.ac.combat_target)])
		st.committed_turn_sign = 0.0

	var stall_base_kmh: float = st.ac.params.stall_speed_base if st.ac.params else 220.0
	var stall_at_g_ms: float = stall_base_kmh * pow(maxf(st.g_load, 1.0), 0.4) / 3.6

	# 当前实际转速（带符号），= PD 控制律的 D 项输入（低通破单帧代数环，与 update_bank 同源）
	var cur_v: float = maxf(st.speed, 50.0)
	var current_turn_rate: float = CombatUnit.GRAVITY * tan(st.bank_angle) / cur_v
	st.turn_rate_filt = lerpf(st.turn_rate_filt, current_turn_rate, TURN_RATE_FILT_ALPHA)
	var damp_turn_rate: float = st.turn_rate_filt

	# 目标 LOS 角速度前馈（与 update_bank 同源）；默认关闭则跳过，零成本
	var ff_los: float = 0.0
	if PD_LOS_FF != 0.0:
		if st.target_position != Vector2.INF:
			if not is_nan(st.prev_tgt_heading_pd):
				var raw: float = Aircraft._angle_diff(st.cached_target_heading, st.prev_tgt_heading_pd) / maxf(delta, 0.0001)
				if absf(raw) <= PD_LOS_SANE_CAP:
					st.los_rate_filt = lerpf(st.los_rate_filt, clampf(raw, -PD_LOS_RATE_CAP, PD_LOS_RATE_CAP), PD_LOS_FILT_ALPHA)
			st.prev_tgt_heading_pd = st.cached_target_heading
		else:
			st.prev_tgt_heading_pd = NAN
			st.los_rate_filt = 0.0
		ff_los = st.los_rate_filt

	# max_bank（state-aware：prediction 走 cached_*，real tick 走 lazy）
	# 基础上限用结构 G（与实飞 max_bank_angle 同口径）；持续 G 只给下方 sustained cap 用
	var stall_base_ms: float = stall_base_kmh / 3.6
	var eff_max_g := _eff_max_g_st(st)
	var safe_margin := _safe_margin_st(st)
	var max_bank := max_bank_angle_at_speed_pure(st.speed, stall_base_ms, _eff_max_g_instant_st(st), safe_margin)
	# plan 级坡度上限（与实飞 update_bank 镜像同步，SEAM-017）
	if st.ac._plan_bank_limit_rad > 0.0:
		max_bank = minf(max_bank, st.ac._plan_bank_limit_rad)
	var in_combat := st.ac.combat_target != null

	if in_combat and abs(heading_diff) > 0.5 and st.ac.tactical_aggression < 0.999:
		var sustained_g: float = st.ac.params.max_g if st.ac.params else 9.0
		var turn_g_capped := lerpf(sustained_g * 0.7, sustained_g, clampf((PI - abs(heading_diff)) / (PI - 0.5), 0.0, 1.0))
		var turn_g := lerpf(turn_g_capped, eff_max_g, clampf(st.ac.tactical_aggression, 0.0, 1.0))
		var sustained_bank := acos(1.0 / maxf(turn_g, 1.01))
		max_bank = minf(max_bank, sustained_bank)

	# PD 增益（与实物理 update_bank 严格同源）
	var roll_rate_base: float = st.ac.params.roll_rate if st.ac.params else 4.0
	var aggression: float = st.ac._combat_params().combat_bank_aggression if in_combat else 1.0
	var kp: float = PD_KP_BASE * aggression
	var kd: float = clampf(PD_KD_SCALE / maxf(roll_rate_base, 0.5), PD_KD_MIN, PD_KD_MAX)
	var deadzone: float = st.ac._combat_params().combat_half_bank_diff if in_combat else 0.02

	var msl_phase_now: int = st.ac._get_missile_phase() \
			if (in_combat and st.ac.weapon_mode == Aircraft.WeaponMode.MISSILE) else 0
	var target_bank: float = compute_target_bank(
			heading_diff, damp_turn_rate, ff_los, cur_v, max_bank, in_combat,
			st.ac.use_tactical_preference, st.ac.weapon_mode, msl_phase_now,
			st.ac.formation_mode and not st.ac._formation_full_bank, st.proximity_damping, deadzone, kp, kd)

	# 失速回正
	if st.is_stalled:
		target_bank = 0.0
	elif st.stall_recovery_timer > 0.0:
		var recovery_ratio := 1.0 - clampf(st.stall_recovery_timer / 1.0, 0.0, 1.0)
		target_bank *= recovery_ratio

	# 滚转速率限制（低速 + 高度加成）
	var roll_rate_val: float = st.ac.params.roll_rate if st.ac.params else 4.0
	if st.speed < stall_at_g_ms:
		var ctrl := clampf(st.speed / maxf(stall_at_g_ms, 1.0), 0.1, 1.0)
		roll_rate_val *= ctrl
	var alt_factor := clampf(st.altitude / 15000.0, 0.0, 1.0)
	roll_rate_val *= 1.0 + alt_factor * 0.30

	var bank_diff := target_bank - st.bank_angle
	var max_roll := roll_rate_val * delta
	st.bank_angle += clampf(bank_diff, -max_roll, max_roll)

	# Bank rate EMA 追踪
	if delta > 0.0:
		var instant_rate: float = (st.bank_angle - st.prev_bank_for_rate) / delta
		st.bank_rate_rad_s = st.bank_rate_rad_s * 0.5 + instant_rate * 0.5
	st.prev_bank_for_rate = st.bank_angle


## heading 演化：ω = g·tan(bank)/V，低速衰减
static func step_heading(st: FlightState, delta: float) -> void:
	var _hm := st.ac.get_herbst()
	if _hm and _hm.is_active:
		return
	if abs(st.bank_angle) < 0.001:
		return
	var speed_ms := maxf(st.speed, 1.0)
	var turn_rate := CombatUnit.GRAVITY * tan(st.bank_angle) / speed_ms

	var stall_base_kmh: float = st.ac.params.stall_speed_base if st.ac.params else 220.0
	var stall_at_g_ms := stall_base_kmh * pow(maxf(st.g_load, 1.0), 0.4) / 3.6
	if st.speed < stall_at_g_ms:
		var control_ratio := clampf(st.speed / maxf(stall_at_g_ms, 1.0), 0.0, 1.0)
		turn_rate *= control_ratio * control_ratio

	st.heading += turn_rate * delta
	st.heading = fmod(st.heading + PI, TAU) - PI


## altitude / vertical_speed 演化：target_altitude 收敛 + 速度余量限制 + 失速恢复门控
## 预测期间用此函数让 vertical_speed 自然衰减到 0（飞机抵达目标高度后 PE/KE 不再耗速度
## → 预测线长度回归"巡航段长度"），不再因为冻结 vertical_speed 导致预测全程都被拉短
static func step_altitude(st: FlightState, delta: float) -> void:
	if st.is_stalled:
		st.altitude += st.vertical_speed * delta
		st.altitude = maxf(st.altitude, 0.0)
		return
	var alt_diff: float = st.ac.target_altitude - st.altitude
	var alt_mult: float = st.ac.altitude_authority_mult
	# 与 update_altitude 保持同步：alt_mult 只放大响应度，物理顶速最多 +30%
	var base_climb: float = st.ac.params.climb_rate_max if st.ac.params else 250.0
	var max_climb: float = base_climb * minf(alt_mult, 1.3)
	var gain: float = 0.4 * alt_mult
	var smooth_rate: float = 8.0 * alt_mult
	var target_vs: float
	if abs(alt_diff) < 10.0:
		target_vs = 0.0
	else:
		target_vs = clampf(alt_diff * gain, -max_climb, max_climb)

	if st.stall_recovery_timer > 0.0 and target_vs > 0.0:
		target_vs = 0.0

	if target_vs > 0.0:
		var stall_base_kmh: float = st.ac.params.stall_speed_base if st.ac.params else 220.0
		var stall_at_g_ms: float = stall_base_kmh * pow(maxf(st.g_load, 1.0), 0.4) / 3.6
		var speed_margin: float = st.speed - stall_at_g_ms
		if speed_margin < 50.0:
			var climb_authority: float = clampf(speed_margin / 50.0, 0.0, 1.0)
			target_vs *= climb_authority

	st.vertical_speed = lerpf(st.vertical_speed, target_vs, delta * smooth_rate)
	st.altitude += st.vertical_speed * delta
	st.altitude = maxf(st.altitude, 0.0)
	# §C 玩家"高度变化更难锁"副作用：仅 real tick 写回，prediction 跳过
	if not st.is_prediction and st.ac.is_player_squad() and st.ac.alt_change_stealth_factor > 0.0:
		var instant_v: float = absf(st.vertical_speed)
		st.ac._alt_velocity = lerpf(st.ac._alt_velocity, instant_v, clampf(delta * 4.0, 0.0, 1.0))


## speed 演化：target → 加/减速 → g_drag → PE/KE → orbit cap
static func step_speed(st: FlightState, delta: float) -> void:
	var ac := st.ac
	# 与 update_speed 同口径的机动守卫（2026-07-03 修镜像漂移：旧版只查 Cobra 漏 Herbst，
	# 玩家危机赫尔贝特期间实机速度被模块钳在近失速、预测线却自由加减速 → 撕裂）
	if maneuver_overrides_speed(ac):
		return

	var target_ms: float
	if ac.hard_brake:
		# 急刹失速软地板（与实物理 update_speed 镜像同步，2026-07-03）
		var stall_base_hb: float = ac.params.stall_speed_base if ac.params else 220.0
		target_ms = stall_base_hb * pow(maxf(st.g_load, 1.0), 0.4) / 3.6 * 1.05
	else:
		# ⚠ 读 st.target_speed_kmh 而非 ac —— 让 prediction 的 inline planner 能在循环里
		# 演化 target_speed（详见 predict_player_path 注释）。实物理 tick 里 st 是 ac 的快照，
		# 行为完全一致
		var t_kmh: float = st.target_speed_kmh
		if ac.evasion_mode:
			var cruise_mult: float = float(ac.evasion_modifiers.get("cruise_speed_mult", 1.0))
			if cruise_mult != 1.0:
				t_kmh *= cruise_mult
		# 加力窗口速度地板（与实物理 update_speed 镜像同步，spec afterburner-mode）
		if ac.afterburner_window_active:
			t_kmh = maxf(t_kmh, effective_max_speed_kmh(ac))
		if ac.status_slow_active and t_kmh > StatusEffects.SLOW_SPEED_CAP_KMH:
			t_kmh = StatusEffects.SLOW_SPEED_CAP_KMH
		if ac.laser_stall_pressure_active():
			t_kmh = minf(t_kmh, stall_speed(ac) * 0.90)
		target_ms = t_kmh / 3.6

		var max_climb_norm: float = ac.params.climb_rate_max if ac.params else 250.0
		var vs_norm: float = clampf(st.vertical_speed / maxf(max_climb_norm, 1.0), -1.0, 1.0)
		target_ms *= 1.0 - vs_norm * 0.10

		var max_speed_ms := _max_speed_alt_ms_st(st)
		if ac.evasion_mode:
			var cm: float = float(ac.evasion_modifiers.get("cruise_speed_mult", 1.0))
			if cm > 1.0:
				max_speed_ms *= cm
		# 加力窗口 cap 放开（与实物理 update_speed 镜像同步，spec afterburner-mode）
		if ac.afterburner_window_active:
			max_speed_ms = maxf(max_speed_ms, effective_max_speed_kmh(ac) / 3.6)
		target_ms = minf(target_ms, max_speed_ms)

		var stall_base_kmh: float = ac.params.stall_speed_base if ac.params else 220.0
		var stall_at_g_ms := stall_base_kmh * pow(maxf(st.g_load, 1.0), 0.4) / 3.6
		var min_safe_ms := stall_at_g_ms * 1.05
		if not ac.laser_stall_pressure_active():
			target_ms = maxf(target_ms, min_safe_ms)

	var accel_rate: float = ac.params.acceleration if ac.params else 50.0
	if ac.status_overload_active:
		accel_rate *= StatusEffects.OVERLOAD_ACCEL_MULT
	# 加力窗口：加速度 ×3（spec afterburner-mode；replace_all 同步实物理与预测镜像两处）
	if ac.afterburner_window_active:
		accel_rate *= AB_WINDOW_ACCEL_MULT
	var decel_rate: float = (ac.params.deceleration if ac.params else 80.0) * ac._executioner_decel_mult()
	if ac.is_player_squad() and ac.status_bloodlust_active and ac.has_meta("upgrade_stacks"):
		var bl_stacks: Dictionary = ac.get_meta("upgrade_stacks")
		if int(bl_stacks.get(SkillHooks.SKILL_BLOODLUST_ARMOR_MOBILITY, 0)) > 0:
			accel_rate *= SkillHooks.BLOODLUST_ACCEL_MULT
			decel_rate *= SkillHooks.BLOODLUST_ACCEL_MULT
	# 722 签名：三发推力（J-36 突击 buff）加/减速 ×1.4；近太空冲刺（MiG-41）俯冲加速 ×1.5
	if ac.sig_j36_assault_active:
		accel_rate *= 1.4
		decel_rate *= 1.4
	if ac.hunter_assault_active:
		accel_rate *= 1.2
		decel_rate *= 1.2
	if ac._sig_mig41_dive_timer > 0.0:
		accel_rate *= 1.5
	# AB 也走 st 而非 ac（同上 prediction 内联 planner 的需要）
	if st.is_afterburner and not ac.hard_brake:
		var ab_mult: float = ac.params.afterburner_thrust_mult if ac.params else 1.5
		accel_rate *= ab_mult
	if ac.hard_brake:
		# 急刹阻力随速度衰减（与实物理 update_speed 镜像同步，SEAM-017）
		const HARD_BRAKE_DRAG_FLOOR := 0.35
		var cruise_ms_hb: float = (ac.params.cruise_speed if ac.params else 900.0) / 3.6
		decel_rate *= clampf(st.speed / maxf(cruise_ms_hb, 1.0), HARD_BRAKE_DRAG_FLOOR, 1.0)

	var speed_diff := target_ms - st.speed
	if speed_diff >= 0:
		st.speed += minf(speed_diff, accel_rate * delta)
	else:
		st.speed += maxf(speed_diff, -decel_rate * delta)

	# 与实物理 update_speed 严格同源（双层 G 能量自限 + 角点速度失速地板）——
	# 任何对那边掉速公式的改动都要同步到此，否则预测线与实飞行轨迹"撕裂"（known-seams）
	const G_DRAG_GLOBAL_MULT := 0.4
	const STRUCT_BLEED_FACTOR := 6.0
	var alt_factor := clampf(st.altitude / 15000.0, 0.0, 1.0)
	var alt_drag_mult := 1.0 - alt_factor * 0.30
	var g_drag := (ac.params.g_drag_factor if ac.params else 3.0) * G_DRAG_GLOBAL_MULT * alt_drag_mult
	var base_loss := maxf(st.g_load - 1.0, 0.0) * g_drag
	var sustained_g := effective_max_g(ac)
	var over_g := maxf(st.g_load - sustained_g, 0.0)
	# 编队托管豁免结构超 G 掉速（与实物理 update_speed 同源）
	var struct_loss := 0.0 if ac.formation_mode else over_g * STRUCT_BLEED_FACTOR * alt_drag_mult
	var g_loss_total := base_loss + struct_loss
	if ac.hunter_assault_active:
		g_loss_total *= 0.7
	var no_stall_floor_ms := corner_speed_kmh(ac) / 3.6
	var allowed_g_loss := maxf(st.speed - no_stall_floor_ms, 0.0)
	st.speed = maxf(st.speed - minf(g_loss_total * delta, allowed_g_loss), 0.0)

	const PE_KE_BOOST := 2.5
	var spd := maxf(st.speed, 10.0)
	var gravity_effect := CombatUnit.GRAVITY * st.vertical_speed / spd * PE_KE_BOOST
	st.speed -= gravity_effect * delta

	st.speed = maxf(st.speed, 0.0)
	if ac.orbit_speed_cap > 0.0 and st.speed > ac.orbit_speed_cap:
		st.speed = ac.orbit_speed_cap


# ══════════════════════════════════════════════════════════════════════
#  predict_player_path — 玩家飞行轨迹精确预测
# ══════════════════════════════════════════════════════════════════════
## prediction 专用：在 sim 的每一步重新决定 target_speed_kmh / is_afterburner
## 等价于 BfmIntent.waypoint_move 的速度/AB 分支，只是输入用 sim state 而非 Situation
## 必须与 [bfm_intent.gd:waypoint_move](scripts/ai/tactical/bfm_intent.gd) 公式一致 ——
## 任何对那边速度曲线的调整都要同步过来，否则 prediction 与实飞行再次出现"撕裂"
static func _predict_inline_planner_waypoint_move(st: FlightState) -> void:
	if st.target_position == Vector2.INF:
		return
	var to_wp: Vector2 = st.target_position - st.position
	if to_wp.length_squared() < 1.0:
		return
	var hdg_to_wp: float = atan2(to_wp.x, -to_wp.y)
	var hdiff_deg: float = rad_to_deg(absf(Aircraft._angle_diff(hdg_to_wp, st.heading)))
	var t: float = clampf((80.0 - hdiff_deg) / 50.0, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var corner_kmh: float = st.cached_corner_speed_kmh if not is_nan(st.cached_corner_speed_kmh) else effective_corner_speed_kmh(st.ac)
	var max_kmh: float = st.cached_max_speed_kmh if not is_nan(st.cached_max_speed_kmh) else effective_max_speed_kmh(st.ac)
	var cruise_high: float = max_kmh * 0.85
	st.target_speed_kmh = lerpf(corner_kmh, cruise_high, t)
	st.is_afterburner = (st.speed * 3.6) < st.target_speed_kmh * 0.95


## 用同源 step_X 把当前 ac 状态向前推 max_steps 步（默认 180 步 = 3s @ PHYSICS_DT），
## 到达目标立即终止。返回**世界坐标**点列（渲染层每帧再做 to_local，便于缓存）。
##
## 与实物理 tick 顺序严格一致：target_heading → bank → heading → speed → g_load → 移动
## g_load 后置语义保留：step_speed 读上一步 g_load（与真实 tick 行为完全相同）
##
## 性能：单次调用 ~1ms（180 步 × ~5µs/step），渲染层应缓存到 20Hz refresh
## 缓存频率不能太低 —— 玩家飞行时 state 在变，长间隔会让"未来线"明显落后实际轨迹
##
## 返回 Dictionary：
##   points: PackedVector2Array — **世界坐标**点列（首点是飞机当前 global_position）
##   healths: PackedFloat32Array — 同长度，每点 (speed - stall_floor_at_g) / (cruise - stall_floor_1g)
static func predict_player_path(ac: Aircraft, max_steps: int = 180) -> Dictionary:
	var result := {
		"points": PackedVector2Array(),
		"healths": PackedFloat32Array(),
	}
	if ac == null or not is_instance_valid(ac):
		return result
	if ac.target_position == Vector2.INF:
		return result

	var stall_base_kmh: float = ac.params.stall_speed_base if ac.params else 220.0
	var cruise_kmh: float = ac.params.cruise_speed if ac.params else 900.0
	var cruise_ms: float = cruise_kmh / 3.6
	var stall_base_ms: float = stall_base_kmh / 3.6
	var cruise_health_span: float = maxf(cruise_ms - stall_base_ms * 1.05, 1.0)

	var st := FlightState.from_aircraft(ac, true)

	# ── 频繁调用的 helper 在这里只读一次 ac.* 就缓存到 state，省掉 180×N 的字典查询 ──
	# 这些字段在 prediction 期间不变（cloud_state / is_locked / status_bloodlust /
	# upgrade_stacks / altitude / cloud / in_building 都视作 frozen）
	st.cached_max_g = effective_max_g(ac)
	st.cached_max_g_instant = effective_max_g_instant(ac)
	st.cached_safe_margin = _dynamic_safe_margin(ac)
	st.cached_max_speed_alt_ms = max_speed_at_altitude(ac) / 3.6
	# inline planner 用：corner / max speed (km/h) 在 prediction 期间不变
	st.cached_corner_speed_kmh = effective_corner_speed_kmh(ac)
	st.cached_max_speed_kmh = effective_max_speed_kmh(ac)

	var pts: PackedVector2Array = result["points"]
	var healths: PackedFloat32Array = result["healths"]

	# 起点：飞机当前世界位置
	pts.append(st.position)
	var start_floor: float = stall_base_ms * pow(maxf(st.g_load, 1.0), 0.4) * 1.05
	healths.append((st.speed - start_floor) / cruise_health_span)

	for i in range(max_steps):
		step_target_heading(st)
		if st.target_position == Vector2.INF:
			break  # 已到达目标
		# ── inline planner（WAYPOINT_MOVE 决策）──
		# 必须在 step_speed 之前更新 st.target_speed_kmh / st.is_afterburner，让 sim plane
		# 自洽地"知道"未来转弯结束后会加速。否则 prediction 全程用快照时的 target_speed，
		# 实际飞机随对准目标 target_speed 渐增，prediction 末端就持续偏短，每帧 cache refresh
		# 都看到稍长一点的预测线 → 视觉上"反复延伸"。
		# 公式严格复制 bfm_intent.waypoint_move（smoothstep 30°-80°）
		_predict_inline_planner_waypoint_move(st)
		step_bank(st, PHYSICS_DT)
		step_heading(st, PHYSICS_DT)
		step_speed(st, PHYSICS_DT)
		# step_altitude 让 vertical_speed 在 sim 中收敛 → 飞机抵达目标高度后
		# PE/KE 项归零 → 预测线不会因为冻结 vertical_speed 被持续拉短
		step_altitude(st, PHYSICS_DT)
		# 与 update_g_load 同口径的机动守卫（Herbst/Cobra 期间 G 由模块直写，
		# 预测保持快照值，不按 bank 反推覆盖）
		if not maneuver_overrides_g(ac):
			if abs(st.bank_angle) < 0.001:
				st.g_load = 1.0
			else:
				st.g_load = absf(1.0 / cos(st.bank_angle))

		var velocity := Vector2(sin(st.heading), -cos(st.heading)) * st.speed * CombatUnit.PIXELS_PER_METER
		st.position += velocity * PHYSICS_DT

		pts.append(st.position)
		var floor_at_g: float = stall_base_ms * pow(maxf(st.g_load, 1.0), 0.4) * 1.05
		healths.append((st.speed - floor_at_g) / cruise_health_span)

	return result


## 旋翼机运动：平面速度与机头方向解耦，可切向平移、刹停和悬停。
## 放在文件末尾以避免新机制让既有物理索引全体移位。
static func update_rotorcraft(ac: Aircraft, delta: float) -> void:
	if ac.params == null:
		return
	if ac.rotorcraft_velocity == Vector2.ZERO and ac.speed > 0.1:
		ac.rotorcraft_velocity = Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed

	var desired_velocity := Vector2.ZERO
	if ac.target_position != Vector2.INF:
		var to_target: Vector2 = ac.target_position - ac.global_position
		var dist_px: float = to_target.length()
		if dist_px > 1.0 and ac.target_speed_kmh > 0.0:
			var desired_mps: float = minf(ac.target_speed_kmh, effective_max_speed_kmh(ac)) / 3.6
			# 靠近目标点时平顺减速；环绕 AI 会持续把目标点推到切线前方，因此不会误刹停。
			var arrival_mult: float = clampf(dist_px / 80.0, 0.0, 1.0)
			desired_velocity = to_target / dist_px * desired_mps * arrival_mult

	var changing_dir: bool = desired_velocity.dot(ac.rotorcraft_velocity) < 0.0
	var rate: float = ac.params.deceleration if desired_velocity.length() < ac.rotorcraft_velocity.length() or changing_dir else ac.params.acceleration
	ac.rotorcraft_velocity = ac.rotorcraft_velocity.move_toward(desired_velocity, maxf(rate, 1.0) * delta)
	ac.speed = ac.rotorcraft_velocity.length()
	ac.global_position += ac.rotorcraft_velocity * CombatUnit.PIXELS_PER_METER * delta

	var aim_vector := Vector2.ZERO
	if ac.rotorcraft_aim_position != Vector2.INF:
		aim_vector = ac.rotorcraft_aim_position - ac.global_position
	elif ac.rotorcraft_velocity.length_squared() > 0.01:
		aim_vector = ac.rotorcraft_velocity
	if aim_vector.length_squared() > 0.01:
		var desired_heading: float = atan2(aim_vector.x, -aim_vector.y)
		var yaw_step: float = deg_to_rad(75.0) * delta
		ac.heading += clampf(angle_difference(ac.heading, desired_heading), -yaw_step, yaw_step)

	# 视觉坡度只表达横移，不参与转弯物理；上限 18°。
	var velocity_heading: float = ac.heading
	if ac.rotorcraft_velocity.length_squared() > 0.01:
		velocity_heading = atan2(ac.rotorcraft_velocity.x, -ac.rotorcraft_velocity.y)
	var target_bank: float = clampf(angle_difference(ac.heading, velocity_heading) * 0.25,
		-deg_to_rad(18.0), deg_to_rad(18.0))
	ac.bank_angle = lerp_angle(ac.bank_angle, target_bank, clampf(delta * 4.0, 0.0, 1.0))
	ac.g_load = 1.0
	ac.is_stalled = false
	ac.is_afterburner = false

	var target_alt: float = CombatUnit.TIER_ALTITUDE.get(ac.target_altitude_tier, ac.target_altitude) \
			if ac.flat_altitude else ac.target_altitude
	var max_vertical_step: float = maxf(ac.params.climb_rate_max, 1.0) * delta
	ac.altitude = move_toward(ac.altitude, target_alt, max_vertical_step)
	ac.vertical_speed = clampf((target_alt - ac.altitude) / maxf(delta, 0.001),
		-ac.params.climb_rate_max, ac.params.climb_rate_max)
	ac.rotation = ac.heading
