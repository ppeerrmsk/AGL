class_name AircraftWeapons
extends RefCounted

## 武器子系统（静态工具类）
## 从 aircraft.gd 提取的 _auto_gun_scan / _update_gun / _update_ciws /
## _update_rocket / _launch_rocket / _update_weapon_mode /
## _update_weapon_mode_tactical / _update_missile / _fire_missile_at /
## _fire_multi_lock_salvo 全套逻辑。
##
## 状态仍住在 Aircraft（is_firing / ammo / _fire_cooldown / _ciws_cooldown /
## _gun_reload_active / _rocket_queue / _missile_cooldown / _crank_timer 等）。
## 本模块不持有状态，只在 ac 上读写 + 调 bullet_manager / missile_manager。
##
## 调用约定（来自 aircraft.gd _physics_process）：
##   AircraftWeapons.update_weapon_mode(self)
##   AircraftWeapons.auto_gun_scan(self)
##   AircraftWeapons.update_gun(self, delta)
##   AircraftWeapons.update_ciws(self, delta)
##   AircraftWeapons.update_rocket(self, delta)
##   AircraftWeapons.update_missile(self, delta)

const AUTO_GUN_SCAN_INTERVAL := 0.3
const ROCKET_FIRE_ALT_DIFF_M := 800.0            ## 火箭弹发射最大高度差（米）

## 发射窗口稳定度阈值表（按 missile_skill 双线性插值）
## skill=0 端 = 极宽（几乎不过滤），skill=1 端 = 老逻辑严格值
## SARH 比 f&f 更收紧（半主动制导发射后还要持续照射，发射器姿态影响命中）
const STABLE_OFFAX_RATIO_SARH_LOOSE := 0.95
const STABLE_OFFAX_RATIO_SARH_TIGHT := 0.5
const STABLE_OFFAX_RATIO_FAF_LOOSE  := 1.0
const STABLE_OFFAX_RATIO_FAF_TIGHT  := 0.85
const STABLE_MAX_BANK_DEG_SARH_LOOSE := 75.0
const STABLE_MAX_BANK_DEG_SARH_TIGHT := 35.0
const STABLE_MAX_BANK_DEG_FAF_LOOSE  := 90.0
const STABLE_MAX_BANK_DEG_FAF_TIGHT  := 60.0
const STABLE_MAX_ROLL_RATE_DEG_S_LOOSE := 120.0
const STABLE_MAX_ROLL_RATE_DEG_S_TIGHT := 30.0

## 前置 lead 检查的 off-axis 收紧系数（lerp(LOOSE, TIGHT, skill)）
## TIGHT 端对应 skill=1：seeker_half_deg(默认 30°) × 此比 = 实际允许偏角
## SARH 0.30 → 9° 内才发；f&f 0.55 → 16.5° 内才发
## 旧值 0.5 / 0.7 偏松，玩家 skill=0.85 时仍允许 17° 偏角，看起来"打中间"
const LEAD_OFFAX_RATIO_SARH_LOOSE := 1.0
const LEAD_OFFAX_RATIO_SARH_TIGHT := 0.30
const LEAD_OFFAX_RATIO_FAF_LOOSE  := 1.0
const LEAD_OFFAX_RATIO_FAF_TIGHT  := 0.55
## 估算导弹平均飞行速度系数：avg = max(ac.speed, msl.max_speed * 此系数)
const LEAD_MISSILE_AVG_SPEED_FRAC := 0.85

## 当前架次的"导弹熟练度"实际生效值（base ± jitter，每次发射判定重新摇）
##  - 没有 missile loadout / 没有 combat 资源：返回 0（语义上不参与本系统）
##  - 仅对 params.missile != null 的飞机有意义；纯机炮/纯火箭飞机不会进入 update_missile
static func _missile_skill(ac: Aircraft) -> float:
	if not ac.params or not ac.params.missile or not ac.params.combat:
		return 0.0
	var c: CombatParams = ac.params.combat
	var base: float = c.missile_skill
	var j: float = c.missile_skill_jitter
	if j <= 0.0:
		return clampf(base, 0.0, 1.0)
	return clampf(base + randf_range(-j, j), 0.0, 1.0)

## 发射窗口质量过滤：返回 true 表示当前几何稳定可发，false 跳过这一帧
## skill=0 → 阈值放到 LOOSE 端（行为≈不过滤），skill=1 → TIGHT 端（老严格值）
## SARH 与 f&f 走两套阈值：SARH 半主动需持续照射，门槛收紧
static func _has_stable_launch_window(ac: Aircraft, target_unit: CombatUnit, skill: float) -> bool:
	if not ac.params or not is_instance_valid(target_unit):
		return true
	var is_faf: bool = ac.params.missile and ac.params.missile.fire_and_forget
	var s: float = clampf(skill, 0.0, 1.0)
	# 1. 滚转率检查：仅 SARH 受限（f&f 发射后自主制导，发射器姿态无关）
	if not is_faf:
		var roll_rate_deg_s: float = absf(rad_to_deg(ac._bank_rate_rad_s))
		var roll_limit: float = lerpf(STABLE_MAX_ROLL_RATE_DEG_S_LOOSE, STABLE_MAX_ROLL_RATE_DEG_S_TIGHT, s)
		if roll_rate_deg_s > roll_limit:
			return false
	# 2. bank 检查
	var bank_deg: float = absf(rad_to_deg(ac.bank_angle))
	var bank_limit: float
	if is_faf:
		bank_limit = lerpf(STABLE_MAX_BANK_DEG_FAF_LOOSE, STABLE_MAX_BANK_DEG_FAF_TIGHT, s)
	else:
		bank_limit = lerpf(STABLE_MAX_BANK_DEG_SARH_LOOSE, STABLE_MAX_BANK_DEG_SARH_TIGHT, s)
	if bank_deg > bank_limit:
		return false
	# 3. off-axis 检查
	var to_tgt: Vector2 = target_unit.global_position - ac.global_position
	var hdg_to_tgt: float = atan2(to_tgt.x, -to_tgt.y)
	var off_axis_deg: float = absf(rad_to_deg(ac._angle_diff(hdg_to_tgt, ac.heading)))
	var radar_half_deg: float = ac.params.radar_half_angle
	var offax_ratio: float
	if is_faf:
		offax_ratio = lerpf(STABLE_OFFAX_RATIO_FAF_LOOSE, STABLE_OFFAX_RATIO_FAF_TIGHT, s)
	else:
		offax_ratio = lerpf(STABLE_OFFAX_RATIO_SARH_LOOSE, STABLE_OFFAX_RATIO_SARH_TIGHT, s)
	if off_axis_deg > radar_half_deg * offax_ratio:
		return false
	return true

## 前置 lead 解算：估算 TTI、计算预测命中点，验证：
##  1) 预测点仍在导弹包络内（max_range × alt_factor，按 TAA 取）—— 物理上不可漏的"废弹"过滤
##  2) 我机当前机头到预测点的偏角 ≤ seeker_fov × 0.5 × ratio(skill, is_faf)
##     （skill 越高越收紧，避免发射器还在大幅偏置就扣扳机让导弹烧能量找前置）
## 算法两轮迭代（与 BfmIntent._gun_lead_point 同型）
## 返回 [pass: bool, tti_s: float, off_to_lead_deg: float] 用于日志
static func _has_lead_intercept_solution(ac: Aircraft, target_unit: CombatUnit, msl: MissileParams, skill: float) -> Array:
	if not ac.params or not is_instance_valid(target_unit) or msl == null:
		return [true, 0.0, 0.0]
	var avg_speed_ms: float = maxf(ac.speed, msl.max_speed * LEAD_MISSILE_AVG_SPEED_FRAC)
	if avg_speed_ms < 100.0:
		avg_speed_ms = 100.0
	var avg_speed_px: float = avg_speed_ms * CombatUnit.PIXELS_PER_METER
	var my_pos: Vector2 = ac.global_position
	var tgt_pos: Vector2 = target_unit.global_position
	var tgt_speed_px: float = target_unit.speed * CombatUnit.PIXELS_PER_METER
	var tgt_vel: Vector2 = Vector2(sin(target_unit.heading), -cos(target_unit.heading)) * tgt_speed_px
	# 两轮迭代估 TTI
	var t1: float = my_pos.distance_to(tgt_pos) / avg_speed_px
	var lead1: Vector2 = tgt_pos + tgt_vel * t1
	var t2: float = my_pos.distance_to(lead1) / avg_speed_px
	var final_lead: Vector2 = tgt_pos + tgt_vel * t2
	# 1) 包络检查（始终启用，与 skill 无关：物理上的废弹判定）
	if not AircraftCombatTracking.envelope_pass_at(ac, final_lead, target_unit.heading, target_unit.altitude, msl):
		var lead_dist_m: float = my_pos.distance_to(final_lead) / CombatUnit.PIXELS_PER_METER
		return [false, t2, lead_dist_m]
	# 2) off-axis 偏角到预测点（按 skill 收紧）
	var s: float = clampf(skill, 0.0, 1.0)
	var to_lead: Vector2 = final_lead - my_pos
	var hdg_to_lead: float = atan2(to_lead.x, -to_lead.y)
	var off_lead_deg: float = absf(rad_to_deg(ac._angle_diff(hdg_to_lead, ac.heading)))
	var is_faf: bool = msl.fire_and_forget
	var ratio: float
	if is_faf:
		ratio = lerpf(LEAD_OFFAX_RATIO_FAF_LOOSE, LEAD_OFFAX_RATIO_FAF_TIGHT, s)
	else:
		ratio = lerpf(LEAD_OFFAX_RATIO_SARH_LOOSE, LEAD_OFFAX_RATIO_SARH_TIGHT, s)
	var seeker_half_deg: float = msl.seeker_fov * 0.5
	if off_lead_deg > seeker_half_deg * ratio:
		return [false, t2, off_lead_deg]
	return [true, t2, off_lead_deg]


## 射击更新
## 无交战目标时自动扫描：前方有敌机就开火
static func auto_gun_scan(ac: Aircraft) -> void:
	# 2026-04-22 玩家独立射击意识：取消"有 combat_target 就整体跳过"，让扫描兜底——
	# 只要前方锥内有敌机进入射程（包括 combat_target 因前置角/距离不满足而被 _update_combat
	# 判为不开火，或玩家正忙于操作其他事），机炮自动开火。
	# 仅对玩家（use_tactical_preference）启用；AI 保持原行为（有 combat_target 整体跳过），
	# 避免 AI 烧弹或干扰 AIController 的战术节奏。
	# 2026-04-26 修复：之前重构时加过 "if ac.is_firing: return" 想避免覆盖 lead_heading，
	# 但绕过了下面的 0.3s 节流，导致 is_firing 永不重评估、lead 冻结、UAV 高 bank 时持续
	# 朝侧面喷子弹。详见下方节流处注释。
	# 机动中（眼镜蛇/赫尔贝特）：机头指向与速度和正常追击严重脱节，
	# 继续开火会对着旧 _gun_lead_heading 狂喷。直接中止射击。
	var cobra := ac.get_maneuver()
	if cobra and cobra.is_active:
		ac.is_firing = false
		return
	var herbst := ac.get_herbst()
	if herbst and herbst.is_active:
		ac.is_firing = false
		return
	# 注意：不要在这里加 "if ac.is_firing: return" 早返 —— 那会绕过下面的
	# `_auto_gun_scan_timer` 节流，导致 is_firing 一旦锁存就永不重评估，
	# `_gun_lead_heading` 冻结在初次开火那帧的世界方向。aircraft 高 bank
	# 旋转时（>60°/s）会持续朝侧面喷子弹。0.3s 一次的 scan 重置才是
	# 正确节奏 —— 射速由 `_fire_cooldown` 单独节流。
	# P4：planner 模式 + 有 combat_target 时，scan 只针对 combat_target 决定开火，
	# 不再扫描随机敌人覆写 is_firing/lead_heading（之前的 bug：玩家朝不相干敌机贸然开火）。
	# 但如果 combat_target 当前在锥内 + 射程内，仍允许 scan 设 is_firing —
	# 兜底 planner 因 fire_cone 5° 边缘抖动判 false 而漏射的情况。
	var planner_locked_target: bool = ac.use_tactical_planner and ac.combat_target != null \
			and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed
	if not ac.use_tactical_preference:
		# AI 分支：保持旧行为——有 combat_target 时整体跳过
		if ac.combat_target != null and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed:
			return
	# 对地专用机型：永远不对空中目标开火（_auto_gun_scan 仅扫描 Aircraft）
	if not ac.attack_air_targets:
		return
	# 导弹模式不自动扫射
	if ac.weapon_mode == Aircraft.WeaponMode.MISSILE:
		return
	if not ac.params or not ac.params.gun or ac.ammo <= 0:
		return

	var gun: GunParams = ac.params.gun
	var range_px := gun.max_range * CombatUnit.PIXELS_PER_METER
	var fire_cone := deg_to_rad(gun.fire_cone_half_angle)
	var bullet_speed_px := gun.muzzle_velocity * CombatUnit.PIXELS_PER_METER
	var my_pos := ac.global_position
	var my_fwd := Vector2(sin(ac.heading), -cos(ac.heading))

	# 节流：扫描只需 ~3Hz 频率（子弹速度慢到此频率下瞄准误差可忽略）
	# is_firing 一旦 true 会保持到下次扫描前，所以不会出现"应开火但没开"
	ac._auto_gun_scan_timer -= ac.get_physics_process_delta_time()
	if ac._auto_gun_scan_timer > 0.0:
		return
	ac._auto_gun_scan_timer = AUTO_GUN_SCAN_INTERVAL

	var best_target: Aircraft = null
	var best_angle := fire_cone

	# planner 模式 + 有 combat_target → 只考虑 combat_target，不扫随机敌机
	# 否则保留旧行为（用 all_units 全场扫描）
	var scan_pool: Array
	if planner_locked_target:
		if ac.combat_target is Aircraft:
			scan_pool = [ac.combat_target]
		else:
			# 地面/水面目标走另一套（_update_combat_ground_attack），auto_gun_scan 不处理
			return
	else:
		scan_pool = CombatUnit.all_units

	for unit in scan_pool:
		# 跨帧静态数组，可能持有已释放的节点
		if not is_instance_valid(unit):
			continue
		if not unit is Aircraft:
			continue
		var other: Aircraft = unit
		if other.team == ac.team or other.is_destroyed or other.is_cloaked:
			continue

		var to_ac := other.global_position - my_pos
		var dist := to_ac.length()
		if dist > range_px or dist < 10.0:
			continue

		# 高度差检查（扁平高度模式下忽略）
		if not ac.flat_altitude and absf(ac.altitude - other.altitude) > 500.0:
			continue

		# 前置点计算
		var tgt_fwd := Vector2(sin(other.heading), -cos(other.heading))
		var tgt_speed_px := other.speed * CombatUnit.PIXELS_PER_METER
		var flight_time := dist / maxf(bullet_speed_px, 100.0)
		var lead_pos := other.global_position + tgt_fwd * tgt_speed_px * flight_time

		var to_lead := lead_pos - my_pos
		var angle_to_lead := atan2(to_lead.x, -to_lead.y)
		var angle_diff := absf(ac._angle_diff(angle_to_lead, ac.heading))

		if angle_diff < best_angle:
			best_angle = angle_diff
			best_target = other
			ac._gun_lead_heading = angle_to_lead

	ac.is_firing = ac._ai_gun_burst_allowed(best_target != null, ac.get_physics_process_delta_time())

static func update_gun(ac: Aircraft, delta: float) -> void:
	ac._fire_cooldown = maxf(ac._fire_cooldown - delta, 0.0)
	# §C 玩家技能"AB 时回机炮弹"：开 AB 时持续 regen（受 max_ammo 上限）
	if ac.team == 0 and ac.is_afterburner and ac.ab_gun_regen_per_sec > 0.0 \
			and ac.params and ac.params.gun:
		var max_ammo: int = ac.params.gun.max_ammo
		if ac.ammo < max_ammo:
			# 累加 fractional → 整数（剩余分量挂在 _ab_gun_regen_accum）
			if not ac.has_meta("_ab_gun_regen_accum"):
				ac.set_meta("_ab_gun_regen_accum", 0.0)
			var accum: float = float(ac.get_meta("_ab_gun_regen_accum")) + ac.ab_gun_regen_per_sec * delta
			var add: int = int(accum)
			if add > 0:
				ac.ammo = mini(ac.ammo + add, max_ammo)
				accum -= float(add)
			ac.set_meta("_ab_gun_regen_accum", accum)
	# 整匣装填（生存模式）：弹药耗尽 → 进入 CD → 一次性补满
	if ac.enable_gun_reload and ac._gun_reload_active:
		ac._gun_reload_timer += delta
		ac.gun_reload_progress = clampf(ac._gun_reload_timer / ac.gun_reload_duration, 0.0, 1.0)
		if ac._gun_reload_timer >= ac.gun_reload_duration:
			if ac.params and ac.params.gun:
				ac.ammo = ac.params.gun.max_ammo
			ac._gun_reload_active = false
			ac._gun_reload_timer = 0.0
			ac.gun_reload_progress = 0.0
		ac.is_firing = false
		return
	if not ac.is_firing:
		return
	# JAM 干扰：所有武器封锁
	if ac.status_jam_active:
		ac.is_firing = false
		return
	if not ac.params or not ac.params.gun:
		return
	if ac.ammo <= 0:
		ac.is_firing = false
		return
	if ac._fire_cooldown > 0.0:
		return

	var gun: GunParams = ac.params.gun
	# 射速冷却：60 / fire_rate 秒
	ac._fire_cooldown = 60.0 / gun.fire_rate

	# 飞行员瞄准误差（仅玩家）：火控窗口打开时摇一次 burst 级 lead 偏移
	# skill=0 → ±5° / skill=1 → ±0.5°
	if ac.use_tactical_preference and ac.is_firing and not ac._was_gun_firing:
		var skill: float = clampf(ac.pilot_aim_skill, 0.0, 1.0)
		var base_err_deg: float = lerpf(5.0, 0.5, skill)
		ac._gun_aim_offset_rad = deg_to_rad(base_err_deg) * randf_range(-1.0, 1.0)
	if ac.use_tactical_preference:
		ac._was_gun_firing = ac.is_firing

	# 生成弹丸：朝前置射击方向发射
	if ac.bullet_manager and ac.bullet_manager.has_method("spawn_bullet"):
		var spread_rad := deg_to_rad(gun.spread_angle)
		# 云中目标：视觉遮蔽导致瞄准偏差，散布扩大
		# ⚠ combat_target 可能是刚被摧毁/释放的 MountTarget 代理，先做 is_instance_valid
		#   守卫，否则直接 `is Aircraft` 会抛 "Left operand of 'is' is a previously freed instance"
		var tgt := ac.combat_target
		if is_instance_valid(tgt) and tgt is Aircraft and tgt.cloud_state == 2:
			spread_rad *= 2.2
		# 自己在云中：瞄准工具/视野被云雾干扰，散布再扩大
		if ac.cloud_state == 2:
			spread_rad *= 1.8
		# 机动惩罚（仅玩家）：自身 bank>30° / 目标 bank>60° → 加额外 per-bullet 误差
		var maneuver_err_rad: float = 0.0
		if ac.use_tactical_preference:
			var own_bank_deg: float = absf(rad_to_deg(ac.bank_angle))
			var bank_penalty_deg: float = clampf((own_bank_deg - 30.0) / 60.0, 0.0, 1.0) * 2.0
			var tgt_bank_penalty_deg: float = 0.0
			if is_instance_valid(tgt) and tgt is Aircraft:
				var t_bank: float = absf(rad_to_deg(tgt.bank_angle))
				if t_bank > 60.0:
					tgt_bank_penalty_deg = clampf((t_bank - 60.0) / 30.0, 0.0, 1.0) * 1.5
			maneuver_err_rad = deg_to_rad(bank_penalty_deg + tgt_bank_penalty_deg) * randf_range(-1.0, 1.0)
		var bullet_dir := ac._gun_lead_heading + ac._gun_aim_offset_rad + maneuver_err_rad + randf_range(-spread_rad, spread_rad)
		var muzzle_pos := ac.global_position + Vector2(sin(ac.heading), -cos(ac.heading)) * 20.0
		ac.bullet_manager.spawn_bullet(muzzle_pos, bullet_dir, gun.muzzle_velocity, ac, gun.bullet_damage)
		# §C 玩家技能"机炮发射时减伤"：刷新窗口时间戳，下次受伤 _apply_damage 查
		if ac.team == 0 and ac.gun_fire_dr_window > 0.0:
			ac._gun_fire_recently_until = EventLogger.get_game_time() + ac.gun_fire_dr_window
		# 音效：连射节流 0.5s 一次，防每颗子弹叠声道
		if ac._sfx_gun_cd <= 0.0:
			ac._sfx_gun_cd = 0.5
			var gun_sfx := "gun_long" if ac.gun_extra_barrels >= 2 else "gun_fire"
			AudioManager.play_sfx_2d(gun_sfx, muzzle_pos, 7.0)
		# 多管齐射：额外射出左右偏角子弹
		if ac.gun_extra_barrels >= 2:
			var fan_angle := deg_to_rad(15.0)
			var dir_l := ac._gun_lead_heading - fan_angle + randf_range(-spread_rad, spread_rad)
			var dir_r := ac._gun_lead_heading + fan_angle + randf_range(-spread_rad, spread_rad)
			ac.bullet_manager.spawn_bullet(muzzle_pos, dir_l, gun.muzzle_velocity, ac, gun.bullet_damage)
			ac.bullet_manager.spawn_bullet(muzzle_pos, dir_r, gun.muzzle_velocity, ac, gun.bullet_damage)

	if not ac.infinite_ammo:
		ac.ammo -= 1
		if ac.gun_extra_barrels >= 2:
			ac.ammo -= 2
		ac.ammo = maxi(ac.ammo, 0)
	# 弹药耗尽 → 进入装填 CD（生存模式）
	if ac.enable_gun_reload and ac.ammo <= 0 and not ac._gun_reload_active:
		ac._gun_reload_active = true
		ac._gun_reload_timer = 0.0
		ac.gun_reload_progress = 0.0

## ========== CIWS 近防炮（进化技能：自动拦截正面来袭导弹） ==========
## 不转机头，只拦截恰好在机炮锥内的导弹。与手动射击并行，共用弹药池。
static func update_ciws(ac: Aircraft, delta: float) -> void:
	if not ac.gun_ciws_active or not ac.missile_manager or not ac.params or not ac.params.gun:
		return
	if ac.ammo <= 0 or ac._gun_reload_active:
		return

	ac._ciws_cooldown = maxf(ac._ciws_cooldown - delta, 0.0)
	if ac._ciws_cooldown > 0.0:
		return

	var gun: GunParams = ac.params.gun
	var range_px := gun.max_range * CombatUnit.PIXELS_PER_METER
	var cone_rad := deg_to_rad(gun.fire_cone_half_angle)
	var my_fwd := Vector2(sin(ac.heading), -cos(ac.heading))

	# 找正面锥内最近的来袭导弹
	var best_missile: Missile = null
	var best_dist := INF
	for child in ac.missile_manager.get_children():
		if not (child is Missile):
			continue
		var m: Missile = child as Missile
		if not m.is_active or m.is_flare_jammed or m.team == ac.team:
			continue
		if m.target != ac:
			continue
		var to_m := (m.global_position - ac.global_position).normalized()
		var angle := acos(clampf(my_fwd.dot(to_m), -1.0, 1.0))
		if angle > cone_rad:
			continue
		var dist := ac.global_position.distance_to(m.global_position)
		if dist > range_px or dist > best_dist:
			continue
		best_dist = dist
		best_missile = m

	if not best_missile:
		return

	# 前置射击：导弹速度快，需要精确前置
	var m_fwd := Vector2(sin(best_missile.heading), -cos(best_missile.heading))
	var m_speed_px := best_missile.speed * CombatUnit.PIXELS_PER_METER
	var bullet_speed_px := gun.muzzle_velocity * CombatUnit.PIXELS_PER_METER
	var t := best_dist / maxf(bullet_speed_px, 100.0)
	var lead_pos := best_missile.global_position + m_fwd * m_speed_px * t
	var lead_dir := (lead_pos - ac.global_position).normalized()
	var fire_heading := atan2(lead_dir.x, -lead_dir.y)

	# 前置点也必须在锥内
	var lead_angle := acos(clampf(my_fwd.dot(lead_dir), -1.0, 1.0))
	if lead_angle > cone_rad:
		return

	# 发射 CIWS 子弹（带 is_ciws 标记，仅这种子弹碰撞导弹）
	ac._ciws_cooldown = 60.0 / gun.fire_rate
	var spread_rad := deg_to_rad(gun.spread_angle)
	var bullet_dir := fire_heading + randf_range(-spread_rad, spread_rad)
	var muzzle_pos := ac.global_position + Vector2(sin(ac.heading), -cos(ac.heading)) * 20.0
	ac.bullet_manager.spawn_bullet(muzzle_pos, bullet_dir, gun.muzzle_velocity, ac, gun.bullet_damage, true)
	ac.ammo -= 1
	ac.ammo = maxi(ac.ammo, 0)
	if ac.enable_gun_reload and ac.ammo <= 0 and not ac._gun_reload_active:
		ac._gun_reload_active = true
		ac._gun_reload_timer = 0.0
		ac.gun_reload_progress = 0.0

## ========== 火箭弹（无制导副武器） ==========
## 对空中或地面目标发射一串无制导火箭。散布很大，命中率故意调低。
## 发射时机：有战斗目标 + 目标在机头前方 + 距离在火箭弹射程内 + 齐射冷却归零。
## 齐射内部通过 _rocket_queue 按间隔连发，不立即一次性射出。
## 火箭弹更新（全自动扫描齐射，遵循"全武器无手动开火"哲学）
## 流程：
##   1. CD 倒数 + 队列出膛
##   2. 扫描机头前 fire_cone_half_angle 锥内 [min_range, max_fire_range] 是否有敌方
##   3. 有则启动一次"扇形速发"：burst_count_max 枚火箭从左右挂点同时射出，
##      角度沿 [-spread_angle, +spread_angle] 等距分布，形成机头前方扇形扩散
##   4. 进入 burst_cooldown 等下次扫描
static func update_rocket(ac: Aircraft, delta: float) -> void:
	if not ac.params or not ac.params.rocket:
		return
	var rk: RocketParams = ac.params.rocket
	ac._rocket_burst_cooldown = maxf(ac._rocket_burst_cooldown - delta, 0.0)

	# 发射待发射队列中的火箭（delay 到了就出膛）
	if not ac._rocket_queue.is_empty():
		var i := ac._rocket_queue.size() - 1
		while i >= 0:
			var q: Dictionary = ac._rocket_queue[i]
			q["delay"] = float(q["delay"]) - delta
			if q["delay"] <= 0.0:
				var pylon_val: int = int(q.get("pylon", 0))
				_launch_rocket(ac, q["heading"], q["pos"], pylon_val)
				ac._rocket_queue.remove_at(i)
			i -= 1

	# 齐射前置检查
	if not rk.infinite_ammo and ac.rockets_remaining <= 0:
		return
	if ac._rocket_burst_cooldown > 0.0:
		return
	# crank / 导弹发射阶段不打火箭，避免动作冲突
	if ac._crank_timer > 0.0:
		return
	# JAM 干扰：所有武器封锁
	if ac.status_jam_active:
		return

	# 扫描：机头前锥内是否有敌方目标
	var fire_cone := deg_to_rad(rk.fire_cone_half_angle)
	var range_min_px: float = rk.min_range * CombatUnit.PIXELS_PER_METER
	var range_max_px: float = rk.max_fire_range * CombatUnit.PIXELS_PER_METER
	var found_target := false
	for unit in CombatUnit.all_units:
		if not is_instance_valid(unit) or unit.is_destroyed:
			continue
		if unit == ac or unit.team == ac.team:
			continue
		if unit is Aircraft and (unit as Aircraft).is_cloaked:
			continue
		var dist_px: float = ac.global_position.distance_to(unit.global_position)
		if dist_px < range_min_px or dist_px > range_max_px:
			continue
		# 高度差过滤（扁平高度 / 地面海面目标忽略）
		if not ac.flat_altitude and not (unit is GroundUnit) and not (unit is NavalUnit):
			if absf(ac.altitude - unit.altitude) > ROCKET_FIRE_ALT_DIFF_M:
				continue
		# 机头偏角
		var to_u := (unit.global_position - ac.global_position).normalized()
		var hdg_to_u := atan2(to_u.x, -to_u.y)
		if absf(ac._angle_diff(hdg_to_u, ac.heading)) > fire_cone:
			continue
		found_target = true
		break

	if not found_target:
		return

	# 启动扇形齐射
	var burst_n: int = rk.burst_count_max
	if not rk.infinite_ammo:
		burst_n = mini(burst_n, ac.rockets_remaining)
	if burst_n <= 0:
		return

	var spread_rad := deg_to_rad(rk.spread_angle)
	for n in range(burst_n):
		# 角度沿 [-spread, +spread] 等距分布
		var ratio: float = 0.5 if burst_n <= 1 else float(n) / float(burst_n - 1)
		var angle_offset: float = lerpf(-spread_rad, spread_rad, ratio)
		ac._rocket_queue.append({
			"delay": float(n / 2) * rk.burst_interval,  # 每对（左右）共享 delay
			"heading": ac.heading + angle_offset,
			"pos": ac.global_position,
			"pylon": -1 if (n % 2 == 0) else 1,
		})
	ac._rocket_burst_cooldown = rk.burst_cooldown

## 真正把一发火箭弹交给 BulletManager
## pylon: -1 = 左挂点 / 1 = 右挂点 / 0 = 机身中线
## base_heading 已包含 update_rocket 在扇形齐射时计算的角度偏移，这里不再随机 spread
static func _launch_rocket(ac: Aircraft, base_heading: float, _queued_pos: Vector2, pylon: int = 0) -> void:
	if not ac.params or not ac.params.rocket:
		return
	var rk: RocketParams = ac.params.rocket
	if not rk.infinite_ammo and ac.rockets_remaining <= 0:
		return
	if not ac.bullet_manager or not ac.bullet_manager.has_method("spawn_rocket"):
		return
	# 机头前向 = (sin, -cos)；右舷法向 = (cos, sin)
	var fwd := Vector2(sin(ac.heading), -cos(ac.heading))
	var right := Vector2(cos(ac.heading), sin(ac.heading))
	var muzzle_pos := ac.global_position + fwd * 24.0 + right * (float(pylon) * 18.0)
	if rk.min_damage_mult < 1.0:
		ac.bullet_manager.spawn_rocket_with_falloff(
			muzzle_pos, base_heading, rk.muzzle_velocity, ac,
			rk.rocket_damage, rk.max_range,
			rk.proximity_fuse_radius_m, rk.aoe_radius_m, rk.aoe_damage,
			rk.min_damage_mult,
		)
	else:
		ac.bullet_manager.spawn_rocket(
			muzzle_pos, base_heading, rk.muzzle_velocity, ac,
			rk.rocket_damage, rk.max_range,
			rk.proximity_fuse_radius_m, rk.aoe_radius_m, rk.aoe_damage,
		)
	# 玩家技能 SKILL_ROCKET_HOMING：把刚生成的火箭弹标记为追踪型
	if ac.team == 0 and ac.has_meta("upgrade_stacks"):
		var stacks: Dictionary = ac.get_meta("upgrade_stacks")
		if int(stacks.get(SkillHooks.SKILL_ROCKET_HOMING, 0)) > 0:
			ac.bullet_manager.mark_last_rocket_homing()
	if not rk.infinite_ammo:
		ac.rockets_remaining -= 1

static func update_weapon_mode(ac: Aircraft) -> void:
	# P1：planner 已在帧顶写好 weapon_mode，跳过旧决策
	if ac.use_tactical_planner:
		return
	# 战术偏好模式（生存模式玩家）
	if ac.use_tactical_preference:
		_update_weapon_mode_tactical(ac)
		return

	# BVR 狙击模式：永远锁定导弹模式，不切机炮
	# 反击窗口中允许正常武器切换（近距可用机炮）
	var ai_node: AIController = ac._get_ai_controller()
	if ai_node and ai_node.bvr_only:
		var _hm_wpn: HerbstManeuver = ac.get_herbst()
		if not _hm_wpn or _hm_wpn.counterattack_timer <= 0.0:
			if ac.params and ac.params.missile and ac.missiles_remaining > 0:
				ac.weapon_mode = Aircraft.WeaponMode.MISSILE
			else:
				ac.weapon_mode = Aircraft.WeaponMode.GUN  # 弹药耗尽才用机炮
			return

	# 近距纠缠模式：强制机炮优先（近距时用机炮，远距才切导弹）
	if ac.prefer_gun_mode:
		if ac.combat_target and is_instance_valid(ac.combat_target):
			var gun_dist := ac.global_position.distance_to(ac.combat_target.global_position)
			var gun_range := ac._gun_range_px() * 1.5  # 机炮射程的 1.5 倍以内用机炮
			if gun_dist <= gun_range:
				ac.weapon_mode = Aircraft.WeaponMode.GUN
				return
		# 超出机炮范围才切导弹
		if ac.params and ac.params.missile and ac.missiles_remaining > 0:
			ac.weapon_mode = Aircraft.WeaponMode.MISSILE
		else:
			ac.weapon_mode = Aircraft.WeaponMode.GUN
		return

	# AI / 沙盒模式（v9 sync with tactical）
	# 规则：默认偏好导弹；只在 _missile_cannot_hit_but_gun_can() 为真时切机炮
	# 统一导弹：所有目标共享 ac.missiles_remaining，不按类型区分
	if not ac.params or not ac.params.missile or ac.missiles_remaining <= 0:
		ac.weapon_mode = Aircraft.WeaponMode.GUN
		return
	# 发射后 crank 阶段：保持导弹模式稳定照射
	if ac._crank_timer > 0.0:
		ac.weapon_mode = Aircraft.WeaponMode.MISSILE
		return
	# 与战术偏好同源的回退规则：导弹打不到但机炮能 → 机炮
	if ac._missile_cannot_hit_but_gun_can():
		ac.weapon_mode = Aircraft.WeaponMode.GUN
	else:
		ac.weapon_mode = Aircraft.WeaponMode.MISSILE

## 战术偏好武器模式：玩家手动控制，简洁明确
static func _update_weapon_mode_tactical(ac: Aircraft) -> void:
	# 双击冲锋：强制 GUN（让 combat_tracking 走贴近 pursuit），导弹通道由 update_missile 单独例外允许
	if ac.charge_attack:
		ac.weapon_mode = Aircraft.WeaponMode.GUN
		ac._gun_pass_committed = false
		return
	match ac.weapon_preference:
		Aircraft.WeaponPreference.PREFER_MISSILE:
			var has_missile := ac.missiles_remaining > 0
			var reloading := ac.enable_missile_reload and ac._missile_reload_active

			# 机炮攻击提交状态维护：飞过目标后解除
			if ac._gun_pass_committed:
				if ac._is_gun_pass_finished():
					ac._gun_pass_committed = false
				# 导弹已装填完成 → 取消机炮 pass，切回导弹（不要错过发射窗口）
				elif has_missile and not reloading:
					ac._gun_pass_committed = false

			# 装填中 或 正在完成机炮攻击 → 保持机炮模式
			if reloading or ac._gun_pass_committed:
				ac.weapon_mode = Aircraft.WeaponMode.GUN
				# 装填中且接近目标 → 提交这次机炮攻击
				# 一旦提交，即使装填好了也要完成这套攻击再切回导弹
				if reloading and ac._should_commit_gun_pass():
					ac._gun_pass_committed = true
			elif not has_missile and ac._crank_timer <= 0.0:
				# 导弹打完：用机炮应急
				ac.weapon_mode = Aircraft.WeaponMode.GUN
			elif ac._crank_timer > 0.0:
				# 保持 crank 状态
				ac.weapon_mode = Aircraft.WeaponMode.MISSILE
			elif ac._missile_cannot_hit_but_gun_can():
				# 导弹优先回退规则：导弹打不中（太近/太远/出锥）但机炮能打 → 用机炮
				ac.weapon_mode = Aircraft.WeaponMode.GUN
			else:
				ac.weapon_mode = Aircraft.WeaponMode.MISSILE
		Aircraft.WeaponPreference.PREFER_GUN:
			ac.weapon_mode = Aircraft.WeaponMode.GUN
			ac._gun_pass_committed = false

static func update_missile(ac: Aircraft, delta: float) -> void:
	ac._missile_cooldown = maxf(ac._missile_cooldown - delta, 0.0)
	ac._sfx_gun_cd = maxf(ac._sfx_gun_cd - delta, 0.0)
	ac._crank_timer = maxf(ac._crank_timer - delta, 0.0)
	ac._msl_block_log_timer = maxf(ac._msl_block_log_timer - delta, 0.0)

	# JAM 干扰：完全无法发射导弹（仍允许 cooldown 走完，恢复后立刻能打）
	if ac.status_jam_active:
		return

	# 导弹装填系统（生存模式）
	if ac.enable_missile_reload and ac._missile_reload_active:
		ac._missile_reload_timer += delta
		# 侩子手：装填时间 ×0.92/层，5 层 ≈ ×0.66
		var eff_reload: float = ac.missile_reload_duration * ac._executioner_reload_mult()
		ac.missile_reload_progress = clampf(ac._missile_reload_timer / eff_reload, 0.0, 1.0)
		if ac._missile_reload_timer >= eff_reload:
			ac.missiles_remaining = ac.params.missile.max_count if ac.params and ac.params.missile else 0
			# AGM 与 AAM 共享装填（生存模式 AGM 数值 = AAM 克隆，同步补满）
			if ac.params and ac.params.secondary_missile:
				ac.secondary_missiles_remaining = ac.params.secondary_missile.max_count
			ac._missile_reload_active = false
			ac._missile_reload_timer = 0.0
			ac.missile_reload_progress = 0.0
		return

	# 机炮优先模式下不自动发射导弹（双击冲锋同样阻断：双击 = 纯机炮专注）
	if ac.use_tactical_preference and ac.weapon_preference == Aircraft.WeaponPreference.PREFER_GUN:
		return
	if ac.weapon_mode != Aircraft.WeaponMode.MISSILE:
		ac._log_msl_block("WEAPON_MODE", "mode=%d" % ac.weapon_mode)
		return
	if ac._missile_cooldown > 0.0:
		# 协同齐射倒计时仍然继续（但不发射）
		var ai_cd: AIController = ac._get_ai_controller()
		if ai_cd:
			SquadCoordination.process_salvo(ai_cd, delta)
		ac._log_msl_block("COOLDOWN", "cd=%.2fs" % ac._missile_cooldown)
		return
	if not ac.missile_manager:
		return

	# ── 协同齐射：僚机收到信号后发射（需在射程+雷达锥内）──
	var ai_sv: AIController = ac._get_ai_controller()
	if ai_sv and SquadCoordination.process_salvo(ai_sv, delta):
		if ac.params and ac.params.missile and ac.missiles_remaining > 0 and ac.combat_target \
				and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed:
			# 必须满足射击条件：在射程内 + 在雷达锥内
			if ac._is_in_missile_envelope(ac.combat_target, ac.params.missile) \
					and ac.is_in_radar_cone(ac.combat_target.global_position):
				_fire_missile_at(ac, ac.combat_target, ac.params.missile, false)
			return

	# 统一导弹：所有目标共享 params.missile + ac.missiles_remaining 计数
	# secondary_missile / secondary_missiles_remaining 字段保留但底层不再使用
	# （避免低层 AAM/AGM 双轨制带来的同步、装填、选择路径复杂度）
	var msl: MissileParams = null
	if ac.params and ac.params.missile and ac.missiles_remaining > 0:
		msl = ac.params.missile

	if msl == null:
		ac._log_msl_block("NO_MSL", "missiles_remaining=%d" % ac.missiles_remaining)
		return

	# 战术偏好模式 + 自动发射开启：走齐射路径
	# - 无多目标追踪升级：齐射循环自动挑一枚最合适的目标开火
	# - 有升级：对所有锁定目标同时发射
	# 这条路径无需玩家点击 combat_target，完全自动
	# 关闭自动发射时跳过这里，直接走下方单发路径——多锁定升级因此被临时禁用，
	# 玩家只会对手点的 combat_target 开火
	if ac.use_tactical_preference and ac.missile_auto_fire:
		if _fire_multi_lock_salvo(ac, msl):
			return
		# 多锁定升级下齐射就是完整路径：齐射没找到目标也不要 fall-through，
		# 否则下一帧（齐射不设冷却）单发路径会绕过 has_active_missile_at 检查
		# 对 combat_target 重复开火，造成同一目标连发两枚的浪费 bug。
		if ac.max_simultaneous_locks > 1:
			return
		# 无升级时允许 fall-through 到单发（让玩家手点的目标仍能由单发路径打中）

	# 必须有明确的交战目标才允许发射导弹（玩家点击敌机设定）
	if ac.combat_target == null or not is_instance_valid(ac.combat_target) or ac.combat_target.is_destroyed:
		return

	# 每目标在飞限制：AI 允许同目标 2 枚在飞（连发两枚）；玩家自动发射限 1 枚
	# 玩家手动点击目标不受此限（允许补射）
	var max_inflight := 2 if not ac.use_tactical_preference else 1
	if ac.missile_manager.count_active_missiles_at(ac, ac.combat_target) >= max_inflight:
		if not ac.use_tactical_preference or ac.missile_auto_fire:
			ac._log_msl_block("ACTIVE_MSL", "already %d in flight" % max_inflight)
			return

	# 队友已发足够伤害 → 不再补射（避免浪费弹药）
	# 累计 team 内（不含自己）已发的 active+未失锁导弹伤害 ≥ 目标 hp → 跳过
	# 自然涵盖"目标快死了 / 已经必死"两种场景；BOSS 因 hp >> 单弹伤害不会被屏蔽
	# 例外：玩家手动点击目标（auto_fire=false）允许补射，与 max_inflight 例外保持一致
	if not (ac.use_tactical_preference and not ac.missile_auto_fire):
		var team_inbound: float = ac.missile_manager.team_inbound_damage(ac.combat_target, ac.team, ac)
		if team_inbound >= ac.combat_target.hp:
			ac._log_msl_block("TEAM_OVERKILL", "team inbound dmg=%.0f >= tgt hp=%.0f" % [team_inbound, ac.combat_target.hp])
			return

	# 机炮正在对 combat_target 开火时不发射导弹（避免机炮击毁后还补一发）
	if ac.use_tactical_preference and ac.is_firing:
		ac._log_msl_block("GUN_ACTIVE", "shooting combat_target with gun")
		return

	var _dist_m := ac.global_position.distance_to(ac.combat_target.global_position) / CombatUnit.PIXELS_PER_METER
	if not ac._is_in_missile_envelope(ac.combat_target, msl):
		# 判断超射程还是低于最小射程
		var envelope_detail := ""
		if _dist_m < msl.min_range:
			envelope_detail = "too_close dist=%.0fm min=%.0fm" % [_dist_m, msl.min_range]
		else:
			envelope_detail = "out_of_envelope dist=%.0fm" % _dist_m
		ac._log_msl_block("ENVELOPE", envelope_detail)
		return

	if not ac.is_in_radar_cone(ac.combat_target.global_position):
		var to_tgt := ac.combat_target.global_position - ac.global_position
		var hdg_to_tgt := atan2(to_tgt.x, -to_tgt.y)
		var off_axis_deg := absf(rad_to_deg(ac._angle_diff(hdg_to_tgt, ac.heading)))
		ac._log_msl_block("OFF_CONE", "dist=%.0fm off_axis=%.0f°" % [_dist_m, off_axis_deg])
		return

	var lock_progress: float = ac.radar_targets.get(ac.combat_target, 0.0)
	# 玩家战术偏好 / TacticalPlanner（P4 僚机）跳过 1 秒稳定 buffer，只要 lock_time 到就开火
	# 原因：buffer 是给"哑 AI"的防抖，planner-managed 的飞机决策稳定不需要
	# 节省 1 秒让玩家与僚机在更远距离发射，火力对称
	var lock_threshold: float = ac.params.lock_time
	if not ac.use_tactical_preference and not ac.use_tactical_planner:
		lock_threshold += Aircraft.LOCK_STABLE_BUFFER
	if lock_progress < lock_threshold:
		ac._log_msl_block("LOCK", "dist=%.0fm lock=%.2fs/%.2fs" % [
			_dist_m, lock_progress, lock_threshold])
		return

	# 发射纪律：missile_skill 控制三道门槛
	#  - 发射窗口稳定（bank/roll/off-axis）按 skill 双线性插值
	#  - 前置 lead 解算（包络 + off-axis-to-lead）按 skill 收紧
	# skill=0 → 阈值放到 LOOSE 端（≈不过滤），skill=1 → TIGHT 端（老严格值）
	# 见 combat_params.gd `missile_skill` 字段说明
	var skill := _missile_skill(ac)
	if not _has_stable_launch_window(ac, ac.combat_target, skill):
		var bank_deg: float = absf(rad_to_deg(ac.bank_angle))
		var roll_deg_s: float = absf(rad_to_deg(ac._bank_rate_rad_s))
		var to_tgt2: Vector2 = ac.combat_target.global_position - ac.global_position
		var off_ax: float = absf(rad_to_deg(ac._angle_diff(atan2(to_tgt2.x, -to_tgt2.y), ac.heading)))
		ac._log_msl_block("UNSTABLE_WIN",
				"skill=%.2f bank=%.0f° roll=%.0f°/s off=%.0f°" % [skill, bank_deg, roll_deg_s, off_ax])
		return
	var lead_res: Array = _has_lead_intercept_solution(ac, ac.combat_target, msl, skill)
	if not lead_res[0]:
		ac._log_msl_block("LEAD_GEOM",
				"skill=%.2f tti=%.1fs detail=%.0f（前置点超出包络或我机偏角过大）" % [skill, lead_res[1], lead_res[2]])
		return

	_fire_missile_at(ac, ac.combat_target, msl, false)
	if ac.use_tactical_preference:
		ac._log_threat_picture("after single-fire")
	# 开火成功：清除阻塞原因缓存
	ac._msl_last_block_reason = ""
	# ── 协同齐射：leader 发射后通知小队僚机 ──
	var ai_salvo: AIController = ac._get_ai_controller()
	if ai_salvo and ai_salvo.salvo_leader:
		SquadCoordination.broadcast_salvo(ai_salvo)

## 对指定目标发射一枚导弹
static func _fire_missile_at(ac: Aircraft, target_unit: CombatUnit, msl: MissileParams, is_secondary: bool = false) -> void:
	var dist_m := ac.global_position.distance_to(target_unit.global_position) / CombatUnit.PIXELS_PER_METER
	var remaining := (ac.secondary_missiles_remaining - 1) if is_secondary else (ac.missiles_remaining - 1)
	EventLogger.log_event("MISSILE", ac._log_name(),
		"fired %s → %s (range=%.0fm, remaining=%d)" % [
			msl.display_name if msl.display_name else "missile",
			ac._log_unit_name(target_unit), dist_m, remaining])
	ac.missile_manager.spawn_missile(ac, target_unit, msl)
	ac.notify_missile_fired_at(target_unit)
	AudioManager.play_sfx_2d("missile_launch" if randf() < 0.5 else "missile_launch_alt", ac.global_position, -12.0)
	if not ac.infinite_ammo and not _overload_ammo_free(ac):
		if is_secondary:
			ac.secondary_missiles_remaining -= 1
		else:
			ac.missiles_remaining -= 1
	ac._missile_cooldown = msl.cooldown
	ac._crank_timer = Aircraft.CRANK_DURATION
	# 装填触发
	if ac.enable_missile_reload and ac.missiles_remaining <= 0:
		ac._missile_reload_active = true
		ac._missile_reload_timer = 0.0
		ac.missile_reload_progress = 0.0


## 多目标齐射：选出多个已锁定目标，每个目标发射一枚
## 返回是否至少发射了一枚导弹
static func _fire_multi_lock_salvo(ac: Aircraft, msl: MissileParams) -> bool:
	var locked_targets: Array[CombatUnit] = []
	# 锁定阈值：AI 模式额外加 1 秒稳定缓冲；玩家战术偏好模式直接用 lock_time，
	# 与单发路径保持一致——否则齐射路径要求更高，combat_target 经常 fall-through
	# 到单发路径，单发路径会设满冷却，把 3 秒内才能成熟的兄弟目标全堵死。
	# lock_time 本身就要持续在锥内追踪 1.25 秒，沿途瞬时穿越的目标到不了阈值。
	var lock_threshold := ac.params.lock_time
	if not ac.use_tactical_preference and not ac.use_tactical_planner:
		lock_threshold += Aircraft.LOCK_STABLE_BUFFER

	for target_key in ac.radar_targets:
		if not is_instance_valid(target_key):
			continue
		var target_unit: CombatUnit = target_key as CombatUnit
		if target_unit == null or target_unit.is_destroyed:
			continue
		if target_unit.team == ac.team:
			continue
		if ac.radar_targets[target_key] < lock_threshold:
			continue
		# 锁定框 = 完整雷达锥：只要目标当前在雷达锥内且锁定已稳定，就算"在射击位置"
		if not ac.is_in_radar_cone(target_unit.global_position):
			continue
		if not ac._is_in_missile_envelope(target_unit, msl):
			continue
		if ac.missile_manager.has_active_missile_at(ac, target_unit):
			continue
		# 队友已发足够伤害（含自己已发的）→ 跳过该目标，避免浪费
		# 过滤掉 exclude_source=ac 自己，因为上一行已经查过自己；这里就是看队友贡献
		if ac.missile_manager.team_inbound_damage(target_unit, ac.team, ac) >= target_unit.hp:
			continue
		# 机炮正在射击 combat_target 时，不给 combat_target 发导弹（避免浪费）；
		# 齐射仍可打其他锁定目标
		if ac.use_tactical_preference and ac.is_firing and target_unit == ac.combat_target:
			continue
		# 发射纪律：missile_skill 双门槛（窗口稳定 + 前置 lead 解算）
		var skill_s := _missile_skill(ac)
		if not _has_stable_launch_window(ac, target_unit, skill_s):
			continue
		var lead_s: Array = _has_lead_intercept_solution(ac, target_unit, msl, skill_s)
		if not lead_s[0]:
			continue
		locked_targets.append(target_unit)

	if locked_targets.is_empty():
		return false

	# 玩家战术偏好 + 显式指定了 combat_target：
	# 旧版（< 2026-05-07）：combat_target 不在 locked_targets 时整个齐射 return false。
	# 这与 missile_swarm 升级（max_simultaneous_locks > 1，齐射成为唯一发射路径）冲突——
	# 玩家点远处一艘还没锁定的船 / 还没进包络的敌机时，所有已锁定目标也跟着不开火，
	# 导致用户感受到的"不点船它不打、点了又卡死"。修复：combat_target 仅作为"优先级提示"
	# （由下方排序逻辑提到队首），不再作为"独占发射许可"。
	# combat_target 自身没进 locked_targets 不影响其他目标继续打——这是 RTS 风格的
	# auto-fire 应有的行为（与 passive_auto_fire 一致）。
	# 双击冲锋（charge_attack）由更上层 [aircraft_weapons.gd:611-613]
	# weapon_preference=PREFER_GUN 阻断导弹路径，本修复不会让冲锋时误发。

	# 按距离排序，优先打近的
	var ac_pos := ac.global_position
	locked_targets.sort_custom(func(a: CombatUnit, b: CombatUnit) -> bool:
		return ac_pos.distance_squared_to(a.global_position) < ac_pos.distance_squared_to(b.global_position)
	)

	# 战术偏好模式：把玩家手点的 combat_target 提到列表最前面（如果它在列表里）
	if ac.use_tactical_preference and ac.combat_target != null and is_instance_valid(ac.combat_target):
		var idx := locked_targets.find(ac.combat_target)
		if idx > 0:
			locked_targets.remove_at(idx)
			locked_targets.insert(0, ac.combat_target)

	# 有多目标追踪升级（max_simultaneous_locks > 1）时，对所有锁定目标一起发射，
	# 只受剩余导弹数限制；无升级时仍按老逻辑只打 1 枚。
	var max_fire: int
	if ac.max_simultaneous_locks > 1:
		max_fire = locked_targets.size()
	else:
		max_fire = 1
	var fire_count := mini(max_fire, ac.missiles_remaining)
	var msl_display: String = msl.display_name if msl.display_name else "missile"
	# 规范化到 [0, 360°)，与游戏内 HDG 显示一致
	var hdg_deg := fposmod(rad_to_deg(ac.heading), 360.0)
	for i in range(fire_count):
		var tgt: CombatUnit = locked_targets[i]
		var dist_m := ac.global_position.distance_to(tgt.global_position) / CombatUnit.PIXELS_PER_METER
		# 诊断：目标相对机头的偏角
		var to_tgt := tgt.global_position - ac.global_position
		var hdg_to_tgt := atan2(to_tgt.x, -to_tgt.y)
		var off_axis_deg := rad_to_deg(ac._angle_diff(hdg_to_tgt, ac.heading))
		var tgt_abs_brg := fposmod(rad_to_deg(hdg_to_tgt), 360.0)
		var lock_val: float = ac.radar_targets.get(tgt, 0.0)
		EventLogger.log_event("MISSILE", ac._log_name(),
			"fired %s → %s (range=%.0fm, remaining=%d, salvo %d/%d, hdg=%03.0f° tgt_brg=%03.0f° tgt_off=%+.0f° lock=%.2fs)" % [
				msl_display, ac._log_unit_name(tgt), dist_m,
				ac.missiles_remaining - 1, i + 1, fire_count,
				hdg_deg, tgt_abs_brg, off_axis_deg, lock_val])
		ac.missile_manager.spawn_missile(ac, tgt, msl)
		ac.notify_missile_fired_at(tgt)
		# 音效：齐射整体只响一下
		if i == 0:
			AudioManager.play_sfx_2d("missile_launch" if randf() < 0.5 else "missile_launch_alt", ac.global_position, -12.0)
		if not ac.infinite_ammo and not _overload_ammo_free(ac):
			ac.missiles_remaining -= 1

	if fire_count > 0:
		# 多目标追踪升级下跳过冷却，允许新锁定好的目标下一帧立刻开火；
		# 单锁定模式仍保留正常冷却
		if ac.max_simultaneous_locks <= 1:
			ac._missile_cooldown = msl.cooldown
		ac._crank_timer = Aircraft.CRANK_DURATION
		if ac.enable_missile_reload and ac.missiles_remaining <= 0:
			ac._missile_reload_active = true
			ac._missile_reload_timer = 0.0
			ac.missile_reload_progress = 0.0
		if ac.use_tactical_preference:
			ac._log_threat_picture("after salvo x%d" % fire_count)
		return true
	return false


## 玩家技能"燃尽自如"：超载期间发射不消耗导弹弹量
## 仅 team 0 + status_overload_active + 持有该技能时返回 true
static func _overload_ammo_free(ac: Aircraft) -> bool:
	if ac.team != 0 or not ac.status_overload_active:
		return false
	if not ac.has_meta("upgrade_stacks"):
		return false
	var stacks: Dictionary = ac.get_meta("upgrade_stacks")
	return int(stacks.get(SkillHooks.SKILL_OVERLOAD_EXTENDED_AMMO, 0)) > 0


## 空中漂浮雷：规避模式下 CD 完毕自动在机身周围投下若干颗
## 投下后留在原地缓慢漂移 + 缓降，不追踪，敌人靠近自爆 AOE
## 不需要装填弹药，CD 持续倒数（不论是否在规避模式），但只在规避模式下才会触发投放
static func update_torpedo(ac: Aircraft, delta: float) -> void:
	if not ac.params or not ac.params.torpedo:
		return
	var tp: TorpedoParams = ac.params.torpedo

	# 冷却持续倒数（不在规避模式时也减，但不会发射 → 进入规避瞬间不会立刻获得免费一发）
	ac._torpedo_cooldown = maxf(ac._torpedo_cooldown - delta, 0.0)

	# 仅在规避模式下投放
	if not ac.evasion_mode:
		return
	if ac._torpedo_cooldown > 0.0:
		return
	# JAM 干扰：所有武器封锁
	if ac.status_jam_active:
		return
	# BulletManager 必须在场（A-10 是玩家，沙盒/生存都注入了 bullet_manager）
	if not ac.bullet_manager or not ac.bullet_manager.has_method("spawn_torpedo"):
		return

	# 投下若干颗：起始位置 = 飞机当前位置（留在原地）
	# 漂移方向：在 0~2π 内均匀分布 + 小抖动，让"几个方向都有"
	var count: int = maxi(tp.drop_count, 1)
	var base_angle: float = randf() * TAU
	for n in range(count):
		var dir_jitter: float = randf_range(-0.25, 0.25)  # ±0.25 弧度 ≈ ±14°
		var drift_angle: float = base_angle + (TAU / float(count)) * float(n) + dir_jitter
		var drift_speed: float = randf_range(tp.drift_speed_min, tp.drift_speed_max)
		ac.bullet_manager.spawn_torpedo(ac.global_position, drift_angle, drift_speed, ac, tp)
	ac._torpedo_cooldown = tp.cooldown


## 忠诚僚机无人机：规避模式下 CD 完毕从机尾释放一架伴飞 drone
## drone 是真正的 Aircraft 实例（带 simple_ai + orbit_squad_leader + shield_leader + chase_leader_target）
## 共享导弹自爆拦截能力（来自 shield_leader），无需新增 kamikaze 逻辑
## 同源同屏 cap：max_simultaneous（默认 2）— 与漂浮雷的 21 cap 同设计哲学
const _LOYAL_WINGMAN_SCENE_PATH := "res://scenes/aircraft.tscn"
static var _loyal_wingman_scene: PackedScene = null

static func update_loyal_wingman(ac: Aircraft, delta: float) -> void:
	if not ac.params or not ac.params.loyal_wingman:
		return
	var lw: LoyalWingmanParams = ac.params.loyal_wingman

	# 清理无效 / 已死的 drone 引用 + 离屏消失计时
	# 设计：drone 在屏幕内永久存在；只有连续离屏超过 offscreen_despawn_seconds 才静默 queue_free
	var i := ac._alive_drones.size() - 1
	while i >= 0:
		var d: Aircraft = ac._alive_drones[i]
		if d == null or not is_instance_valid(d) or d.is_destroyed:
			ac._alive_drones.remove_at(i)
		else:
			# 离屏计时
			if lw.offscreen_despawn_seconds > 0.0:
				if _is_drone_on_screen(d):
					d.set_meta("_drone_offscreen_timer", 0.0)
				else:
					var t: float = float(d.get_meta("_drone_offscreen_timer", 0.0)) + delta
					if t >= lw.offscreen_despawn_seconds:
						EventLogger.log_event("WINGMAN", d.callsign,
							"drone despawned after %.1fs offscreen" % t)
						d.queue_free()
						ac._alive_drones.remove_at(i)
					else:
						d.set_meta("_drone_offscreen_timer", t)
		i -= 1

	# 冷却持续倒数（即使不在规避模式 — 进规避瞬间不送免费一发）
	ac._loyal_wingman_cooldown = maxf(ac._loyal_wingman_cooldown - delta, 0.0)

	# 早退：不在规避模式 / CD 未到 / 已达 cap / JAM 干扰
	if not ac.evasion_mode:
		return
	if ac._loyal_wingman_cooldown > 0.0:
		return
	if ac._alive_drones.size() >= lw.max_simultaneous:
		return
	if ac.status_jam_active:
		return
	if lw.drone_aircraft_params == null:
		push_warning("LoyalWingmanParams.drone_aircraft_params 未设，无法 spawn drone")
		return

	var drone: Aircraft = _spawn_loyal_wingman_drone(ac, lw)
	if drone != null:
		ac._alive_drones.append(drone)
		ac._loyal_wingman_cooldown = lw.cooldown
		EventLogger.log_event("WINGMAN", ac._log_name(),
			"deployed drone (active=%d/%d)" % [ac._alive_drones.size(), lw.max_simultaneous])


## 检查 drone 是否在玩家视口内（含外扩边距，避免边缘瞬时离屏导致计时器抖动）
## 复用 missile_manager 同款逻辑：camera 中心 + 视口尺寸 / zoom
static func _is_drone_on_screen(drone: Aircraft) -> bool:
	if not drone.is_inside_tree():
		return false
	var cam: Camera2D = drone.get_viewport().get_camera_2d()
	if cam == null:
		return true  # 无相机时默认认为可见
	var center: Vector2 = cam.get_screen_center_position()
	var vp_size: Vector2 = drone.get_viewport().get_visible_rect().size
	var zoom_x: float = maxf(cam.zoom.x, 0.0001)
	var zoom_y: float = maxf(cam.zoom.y, 0.0001)
	# 外扩边距 200px，避免缘镜头瞬时离屏导致计时器抖动
	var half_w: float = (vp_size.x * 0.5) / zoom_x + 200.0
	var half_h: float = (vp_size.y * 0.5) / zoom_y + 200.0
	var pos: Vector2 = drone.global_position
	return absf(pos.x - center.x) < half_w and absf(pos.y - center.y) < half_h


## 实例化 + 配置 drone Aircraft（编队跟随模式：与玩家同 squad / formation_mode + SQUAD_FOLLOW）
## 与僚机同套机制（aircraft_formation.gd 三段式跟随），跟得上玩家剧烈机动；
## 额外加 kamikaze_intercept 让 drone 检测到来袭导弹时主动撞毁。
static func _spawn_loyal_wingman_drone(ac: Aircraft, lw: LoyalWingmanParams) -> Aircraft:
	# 加载场景（首次调用时才 preload，避免冷启动开销）
	if _loyal_wingman_scene == null:
		_loyal_wingman_scene = load(_LOYAL_WINGMAN_SCENE_PATH)
		if _loyal_wingman_scene == null:
			push_error("Failed to load aircraft.tscn for loyal wingman drone")
			return null

	# 懒创建 drone squad（leader=ac；与玩家本身的 wingman squad 解耦，不影响阵型槽位）
	if ac._drone_squad == null:
		ac._drone_squad = SquadFactory.create(Squad.Formation.TRAIL, Squad.EngageMode.FOLLOW_LEADER)
		SquadFactory.register_leader(ac._drone_squad, ac)

	var drone: Aircraft = _loyal_wingman_scene.instantiate()
	drone.params = lw.drone_aircraft_params.duplicate(true)
	drone.team = ac.team
	drone.bullet_manager = ac.bullet_manager
	drone.missile_manager = ac.missile_manager
	drone.flat_altitude = ac.flat_altitude
	drone.altitude = ac.altitude
	drone.is_drone = true  # 跳过预测线 / 数据标签 / 锁定指示，纯 2D 极简视觉
	drone.set_meta("silhouette", "drone")  # 切换到 XQ-58 Valkyrie / MQ-28 Ghost Bat 风格的小型外观

	# 计算 squad slot：当前活跃数 + 1（已死的 drone 之前已被 prune）
	var slot_idx: int = ac._drone_squad.members.size()  # 玩家是 0，下一个是 1
	# 出生位置 = 玩家当前位置（drone 接下来由 SQUAD_FOLLOW 自然移到 TRAIL formation 槽位）
	drone.position = ac.global_position
	drone.initial_heading_deg = rad_to_deg(ac.heading)
	drone.target_altitude = ac.altitude

	# 标识 group（便于 EventLogger / debug）
	drone.add_to_group("loyal_wingman")

	# 挂 AIController：SQUAD_FOLLOW 状态 + kamikaze 拦截 flag
	# 不用 simple_ai / orbit / shield_leader — 走与玩家僚机同样的 formation_mode 路径，反应快
	var ai: AIController = AIController.new()
	ai.name = "AI_Drone%d" % slot_idx
	ai.aircraft = drone
	ai.enable_combat = true
	ai.evade_missiles = true
	# 完美飞行员（同玩家僚机），不受压力/技能退化影响
	ai.aggression = 1.0
	ai.skill_level = 1.0
	ai.composure = 1.0
	ai.focus = 1.0
	ai.situational_awareness = 1.0
	ai.self_preservation = 0.5
	# 关键：drone 只打玩家锁定的目标（FOLLOW_LEADER 已在 squad.engage_mode 上）
	ai.squad_engage_mode = AIController.SquadEngageMode.FOLLOW_LEADER
	# kamikaze 拦截：来袭导弹瞄向 leader 时，drone 主动撞毁
	ai.kamikaze_intercept = true
	drone.add_child(ai)
	SquadFactory.register_wingman(ac._drone_squad, drone)  # squad/squad_index/_state=SQUAD_FOLLOW

	# 预置编队托管态：让 frame 1 直接走 LOD 1 编队分支（不经过 LOD 0 漂移过渡）
	# set_formation_target 一次性写 formation_mode/_formation_leader/lod=1/keep_arrival/target_position
	var initial_slot: Vector2 = ac._drone_squad.get_wingman_target(slot_idx)
	drone.set_formation_target(ac, initial_slot)
	# register_wingman 已在前面调用，这里 add_member 是 no-op（保留作为意图标记可省）

	# 加到主场景节点（与玩家同 parent）
	var parent_node: Node = ac.get_parent()
	if parent_node:
		parent_node.add_child(drone)

	# 性能优化：drone 短命，TrailRibbon 顶点数大幅压缩（R6 历史教训）
	if drone._trail_ribbon != null:
		drone._trail_ribbon.max_points = 60

	# 离屏消失计时器初始化（在屏幕内永久存在，离屏累计超过 offscreen_despawn_seconds 才消失）
	drone.set_meta("_drone_offscreen_timer", 0.0)

	return drone
