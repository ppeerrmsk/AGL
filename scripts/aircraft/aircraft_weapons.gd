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
const LAUNCH_QUALITY_OFFAX_RATIO := 0.85         ## 目标距雷达锥边缘留 15% 余量（仅挡贴边的 4.5°）
const LAUNCH_QUALITY_MAX_BANK_DEG := 60.0        ## 玩家 bank 超此判为急转，不发导弹

## 发射窗口质量过滤（仅玩家自动发射用）：返回 true 表示当前几何稳定可发，false 跳过这一帧
## 设计目标：避免半主动导弹（AIM-7M）射后丢失照射 — 既要目标在锥内有余量，
## 又要玩家自身稳定（不在 60°+ bank 急转中）
## 不过滤手动触发（玩家右键 / 单点击 set_combat_target 后单发逻辑由 update_missile 单走）—
## 由用户体验决定，玩家明确指令也应被尊重
##
## fire_and_forget 导弹（自主制导）跳过本检查：发射后不需要发射器照射，
## 玩家姿态/目标在锥位置都不影响命中率
static func _has_stable_launch_window(ac: Aircraft, target_unit: CombatUnit) -> bool:
	if not ac.params or not is_instance_valid(target_unit):
		return true
	# fire-and-forget 导弹不需要发射器照射 → 不必检查 launch geometry
	if ac.params.missile and ac.params.missile.fire_and_forget:
		return true
	# 玩家急转中 → 等转完
	var bank_deg: float = absf(rad_to_deg(ac.bank_angle))
	if bank_deg > LAUNCH_QUALITY_MAX_BANK_DEG:
		return false
	# 目标距雷达锥边缘留余量
	var to_tgt: Vector2 = target_unit.global_position - ac.global_position
	var hdg_to_tgt: float = atan2(to_tgt.x, -to_tgt.y)
	var off_axis_deg: float = absf(rad_to_deg(ac._angle_diff(hdg_to_tgt, ac.heading)))
	var radar_half_deg: float = ac.params.radar_half_angle
	if off_axis_deg > radar_half_deg * LAUNCH_QUALITY_OFFAX_RATIO:
		return false
	return true


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

	ac.is_firing = best_target != null

static func update_gun(ac: Aircraft, delta: float) -> void:
	ac._fire_cooldown = maxf(ac._fire_cooldown - delta, 0.0)
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
				_launch_rocket(ac, q["heading"], q["pos"])
				ac._rocket_queue.remove_at(i)
			i -= 1

	# 新齐射判定
	if ac.rockets_remaining <= 0:
		return
	if ac._rocket_burst_cooldown > 0.0:
		return
	if ac.combat_target == null or not is_instance_valid(ac.combat_target) or ac.combat_target.is_destroyed:
		return
	# crank / 导弹发射阶段不打火箭，避免动作冲突
	if ac._crank_timer > 0.0:
		return

	var tgt_pos := ac.combat_target.global_position
	var dist_px := ac.global_position.distance_to(tgt_pos)
	var dist_m := dist_px / CombatUnit.PIXELS_PER_METER

	# 距离过滤
	if dist_m < rk.min_range or dist_m > rk.max_fire_range:
		return

	# 高度差过滤（扁平高度模式忽略；地面目标忽略）
	if not ac.flat_altitude and not (ac.combat_target is GroundUnit):
		if absf(ac.altitude - ac.combat_target.altitude) > ROCKET_FIRE_ALT_DIFF_M:
			return

	# 机头偏角过滤：目标必须在机头前方的 fire_cone_half_angle 内
	var to_tgt := (tgt_pos - ac.global_position).normalized()
	var hdg_to_tgt := atan2(to_tgt.x, -to_tgt.y)
	var angle_diff := absf(ac._angle_diff(hdg_to_tgt, ac.heading))
	if angle_diff > deg_to_rad(rk.fire_cone_half_angle):
		return

	# 启动齐射：随机决定本次齐射枚数，入队延迟发射
	var burst_n: int = randi_range(rk.burst_count_min, rk.burst_count_max)
	burst_n = mini(burst_n, ac.rockets_remaining)
	if burst_n <= 0:
		return

	for n in range(burst_n):
		ac._rocket_queue.append({
			"delay": float(n) * rk.burst_interval,
			"heading": hdg_to_tgt,  ## 朝目标方向发射（由 _launch_rocket 再加散布）
			"pos": ac.global_position,
		})
	ac._rocket_burst_cooldown = rk.burst_cooldown

## 真正把一发火箭弹交给 BulletManager
static func _launch_rocket(ac: Aircraft, base_heading: float, _queued_pos: Vector2) -> void:
	if not ac.params or not ac.params.rocket or ac.rockets_remaining <= 0:
		return
	if not ac.bullet_manager or not ac.bullet_manager.has_method("spawn_rocket"):
		return
	var rk: RocketParams = ac.params.rocket
	var spread_rad := deg_to_rad(rk.spread_angle)
	var dir := base_heading + randf_range(-spread_rad, spread_rad)
	var muzzle_pos := ac.global_position + Vector2(sin(ac.heading), -cos(ac.heading)) * 24.0
	ac.bullet_manager.spawn_rocket(muzzle_pos, dir, rk.muzzle_velocity, ac, rk.rocket_damage, rk.max_range)
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

	# 发射窗口质量：玩家激烈机动 / 目标在锥边缘 → 跳过这一帧（不计冷却，下帧重试），
	# 等条件稳定后才发射。
	# 解决用户反馈：A-7 在 28° 锥边发射 + 玩家急切转向 → 导弹丢失制导（半主动需持续照射）
	if ac.use_tactical_preference and not _has_stable_launch_window(ac, ac.combat_target):
		ac._log_msl_block("UNSTABLE_WIN", "off-axis 或 bank 超阈值，等下次窗口")
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
	if not ac.infinite_ammo:
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
		# 机炮正在射击 combat_target 时，不给 combat_target 发导弹（避免浪费）；
		# 齐射仍可打其他锁定目标
		if ac.use_tactical_preference and ac.is_firing and target_unit == ac.combat_target:
			continue
		# 发射窗口质量过滤（仅玩家）：目标在锥边缘 / 玩家急转中 → 跳过该目标
		if ac.use_tactical_preference and not _has_stable_launch_window(ac, target_unit):
			continue
		locked_targets.append(target_unit)

	if locked_targets.is_empty():
		return false

	# 玩家战术偏好 + 显式指定了 combat_target：
	# 要求 combat_target 必须出现在发射列表里，否则整个齐射取消。
	# 例外 1：combat_target 已经有在飞导弹（说明上一轮已经打过它了），允许齐射打其他目标
	# 例外 2：机炮正在打 combat_target（is_firing），允许齐射打其他目标
	if ac.use_tactical_preference and ac.combat_target != null \
			and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed:
		if locked_targets.find(ac.combat_target) == -1:
			var combat_target_busy: bool = ac.missile_manager.has_active_missile_at(ac, ac.combat_target) \
					or ac.is_firing
			if not combat_target_busy:
				return false

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
		if not ac.infinite_ammo:
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
