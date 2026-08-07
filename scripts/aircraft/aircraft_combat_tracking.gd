class_name AircraftCombatTracking
extends RefCounted

## 战斗追踪子系统（静态工具类）
## 从 aircraft.gd 提取的 _update_combat / _update_combat_ground_attack /
## _choose_dogfight_pursuit_pos / _missile_cannot_hit_but_gun_can /
## _should_commit_gun_pass / _is_gun_pass_finished / _is_in_missile_envelope /
## _log_pursuit_snapshot / _log_enemy_squads_engaging_player 全套逻辑。
##
## 状态仍住在 Aircraft（combat_target / weapon_mode / _overshoot_timer /
## _pursuit_branch / _pursuit_log_timer / _gun_lead_heading / _in_rear_hemisphere /
## _strafe_state / _strafe_extend_dist 等）。本模块不持有状态，只在 ac 上读写。
##
## 调用约定（来自 aircraft.gd _physics_process）：
##   AircraftCombatTracking.update_combat(self, delta)

const OVERSHOOT_DIST_PX: float = 80.0           ## 像素 触发过顶 extension 的距离（≈160m）
const OVERSHOOT_EXTEND_TIME: float = 1.2        ## 秒  extension 持续时间
const OVERSHOOT_EXTEND_DIST_PX: float = 2000.0  ## 像素 extension 直飞目标点投射距离
const MIN_GUN_FIRE_DIST_PX: float = 60.0        ## 像素 低于此距离强制不开火（≈120m）

const PURSUIT_LOG_INTERVAL: float = 0.5

const LEAD_TIME_MIN := 0.3                       ## 战术偏好追踪提前量下限（秒）
const LEAD_TIME_MAX := 1.5                       ## 战术偏好追踪提前量上限（秒）
const SIX_OCLOCK_OFFSET_MIN_PX := 80.0           ## 6 点钟偏移最小距离（像素）
const MISSILE_IDEAL_RANGE_MULT := 0.55           ## 理想导弹交战距离 = 有效射程 × 此值
const DEFAULT_MISSILE_RANGE_PX := 500.0          ## 无导弹时默认交战距离（像素）
const CRANK_LATERAL_RATIO := 0.8                 ## Crank 侧向距离比
const INTERCEPT_LEAD_MIN := 0.5                  ## 拦截提前量下限（秒）
const LOCK_LEAD_MIN := 0.2                       ## 照射阶段提前量下限（秒）
const LOCK_LEAD_MAX := 1.5                       ## 照射阶段提前量上限（秒）
const OVERSHOOT_SLOW_TARGET_MULT := 3.0          ## 慢目标过顶禁用倍率

const GUN_FIRE_ALT_DIFF_M := 500.0               ## 开火允许的最大高度差（米）
const SIX_OCLOCK_NORM := 2.0                     ## 6 点钟偏移距离归一化因子
const SIX_OCLOCK_FAR_RATIO := 0.3                ## 远距 6 点钟偏移比
const SIX_OCLOCK_MAX_MULT := 1.5                 ## 6 点钟偏移最大倍率
const MIN_CLOSING_RATE_PX := 30.0                ## 最小闭合速率（像素/秒）
const PREDICT_TIME_MIN := 0.3                    ## 前置预测时间下限（秒）
const PREDICT_TIME_MAX := 3.0                    ## 前置预测时间上限（秒）
const GUN_PASS_COMMIT_MULT := 2.0                ## 机炮攻击提交范围 = 枪程 × 此值
const TARGET_BEHIND_DOT := -0.2                  ## 目标在身后判定点积

const STRAFE_HEADING_DEG := 30.0                 ## 攻击进入航向对齐阈值（度）
const STRAFE_EXTEND_FWD_PX := 1000.0             ## 延伸飞行前方距离（像素）
const STRAFE_TURNBACK_HDG_DEG := 45.0            ## 回转航向阈值（度）
const STRAFE_TURNBACK_RATIO := 0.8               ## 回转距离比
const STRAFE_ATTACK_ALT_M := 500.0               ## 攻击高度（米，低空掠袭匹配地面目标）
const STRAFE_CLIMB_ALT_M := 3000.0               ## 脱离爬升高度（米）
const GROUND_FIRE_CONE_MULT := 1.5               ## 对地火控角放宽倍率

const WEAPON_MODE_HYSTERESIS_M := 150.0          ## 枪→弹模式切换滞后缓冲（米）

const STRAFE_ATTACK_RANGE := 1500.0   ## 像素，开始攻击判定距离
const STRAFE_EXTEND_RANGE := 800.0    ## 像素，越过后继续直飞距离
const STRAFE_APPROACH_RANGE := 3000.0 ## 像素，进入跑道对准距离


static func update_combat(ac: Aircraft, _delta: float) -> void:
	# P1：planner 已在帧顶写好 target_position / is_firing / _gun_lead_heading，跳过旧追踪
	if ac.use_tactical_planner:
		return
	# Herbst 激活期间完全停摆：OVERSHOOT / lead pursuit / 机炮 lead 这些分支都会写
	# target_position、is_firing、_gun_lead_heading，和 Herbst 模块抢 heading/position 控制权。
	# 详见 docs/changelogs/player-ai-log.md 2026-04-21 (6)
	var _hm_uc := ac.get_herbst()
	if _hm_uc and _hm_uc.is_active:
		ac.is_firing = false
		return
	if ac.combat_target == null:
		return
	if not is_instance_valid(ac.combat_target) or ac.combat_target.is_destroyed:
		ac.clear_combat_target()
		ac.target_position = Vector2.INF  # 目标被击毁，停止直飞
		return
	# 目标隐形 → 取消交战（从地图上消失）
	if ac.combat_target is Aircraft and ac.combat_target.is_cloaked:
		ac.clear_combat_target()
		return

	# 地面目标 → 只有机炮模式才舔地（降到 LOW）；导弹模式保持当前高度，
	# 让 PN 制导的导弹自己往下俯冲命中（避免被强拉到低空增加地面威胁暴露）
	# 包含 GroundUnit / NavalUnit / MountTarget（船挂点代理）—— 都是"非机动表面目标"，
	# 走 strafe 流程（低空高速掠过 + 直瞄），与导弹模式分流处理
	var tgt_is_surface: bool = ac.combat_target is GroundUnit \
			or ac.combat_target is NavalUnit \
			or ac.combat_target is MountTarget
	if tgt_is_surface and ac.weapon_mode != Aircraft.WeaponMode.MISSILE:
		update_combat_ground_attack(ac)
		return

	var cb := ac._combat_params()
	var my_pos := ac.global_position
	var tgt_pos := ac.combat_target.global_position
	var dist := my_pos.distance_to(tgt_pos)

	# 基本向量
	var tgt_fwd := Vector2(sin(ac.combat_target.heading), -cos(ac.combat_target.heading))
	var my_fwd := Vector2(sin(ac.heading), -cos(ac.heading))
	var my_speed_px := ac.speed * CombatUnit.PIXELS_PER_METER
	var tgt_speed_px := ac.combat_target.speed * CombatUnit.PIXELS_PER_METER
	var to_target := (tgt_pos - my_pos).normalized()

	# 闭合率：正值=在接近，负值=在拉开
	var closing_rate := my_fwd.dot(to_target) * my_speed_px - tgt_fwd.dot(to_target) * tgt_speed_px

	# 后半球判定：我在敌机尾部方向的夹角
	# 0 = 正后方(六点钟), PI = 正前方(十二点钟)
	var to_me_dir := (my_pos - tgt_pos).normalized()
	var aspect_angle := acos(clampf(-tgt_fwd.dot(to_me_dir), -1.0, 1.0))
	var in_rear_hemisphere := aspect_angle < deg_to_rad(90.0)
	ac._in_rear_hemisphere = in_rear_hemisphere

	# ---- 近距过顶 extension ----
	# 与目标距离小于阈值时追击/开火都会退化，强制沿机头直飞一段时间脱离，
	# 让正常追击逻辑在飞出后（target 落到后半球 heading_diff>90°）掉头重新接敌。
	#
	# 对极慢目标（直升机/轰炸机等，cruise×0.4 以下）：完全禁用 extension
	#   - 原因：慢目标不会真正威胁到玩家，不需要"拉开距离脱离"
	#   - 禁用后玩家穿过目标时持续开火（用 lead 计算仍然能准确命中侧向/过顶点）
	#   - 过顶后 heading_diff>90° 的掉头逻辑 + combat_min 降到 1.3x 失速 → 小半径转弯
	#     形成"穿过射击→小圈掉头→再穿过"的高效连击，不再大回环
	var is_slow_tgt_for_overshoot := false
	if ac.params:
		is_slow_tgt_for_overshoot = tgt_speed_px * OVERSHOOT_SLOW_TARGET_MULT < (ac.params.cruise_speed / 3.6 * CombatUnit.PIXELS_PER_METER)
	# 已对准的追尾（后半球 + 机头±30° 内）不触发 extension：此时正是最优射击位，
	# 强制飞过去只会把屁股让给敌机反咬。穿过目标后 in_rear_hemisphere 自然变 false，
	# 下一帧再走正常的 heading_diff>90° 掉头逻辑
	# 附加判定而非修改 extension 本身 —— 详见 docs/changelogs/player-ai-log.md
	var aligned_tail_chase := in_rear_hemisphere and my_fwd.dot(to_target) > 0.87
	ac._overshoot_timer = maxf(ac._overshoot_timer - _delta, 0.0)
	if not is_slow_tgt_for_overshoot and not aligned_tail_chase:
		if dist < OVERSHOOT_DIST_PX:
			ac._overshoot_timer = OVERSHOOT_EXTEND_TIME
		if ac._overshoot_timer > 0.0:
			ac.target_position = my_pos + my_fwd * OVERSHOOT_EXTEND_DIST_PX
			ac.is_firing = false
			ac._gun_lead_heading = ac.heading
			if ac.use_tactical_preference:
				ac._pursuit_branch = "OVERSHOOT_EXT"
				_log_pursuit_snapshot(ac, dist, 0.0, false, 0.0)
			return

	var is_missile_mode := ac.weapon_mode == Aircraft.WeaponMode.MISSILE

	# 战术偏好模式（玩家手动控制）：按武器模式动态选择拦截方案
	# - 导弹模式：纯前置拦截点，保持锁定和追踪（发射后 cooldown 结束能立刻再射）
	# - 机炮模式：根据距离+前后半球动态切换六点钟偏移 / lead turn，避免死执行
	#   导致的"冲过去→overshoot→再冲回来"循环
	if ac.use_tactical_preference:
		if is_missile_mode:
			var lead_time := clampf(dist / maxf(my_speed_px, 50.0), LEAD_TIME_MIN, LEAD_TIME_MAX)
			ac.target_position = tgt_pos + tgt_fwd * tgt_speed_px * lead_time
		else:
			ac.target_position = choose_dogfight_pursuit_pos(
					ac, my_pos, dist, tgt_pos, tgt_fwd, tgt_speed_px, my_speed_px, in_rear_hemisphere)
	elif not ac.ai_override_pursuit:
		var gun_range := ac._gun_range_px()
		var eff_range := ac._effective_range_px()
		var pursuit_pos: Vector2
		var six_offset := maxf(SIX_OCLOCK_OFFSET_MIN_PX, eff_range * cb.six_oclock_offset_ratio)

		# 大角度转向：当目标在后方（航向偏差>90°）时，先直接转向目标位置
		# 避免追踪六点钟/前置点导致追踪点不断偏移形成螺旋
		var heading_to_tgt := atan2(to_target.x, -to_target.y)
		var heading_diff_to_tgt := absf(Aircraft._angle_diff(heading_to_tgt, ac.heading))
		if heading_diff_to_tgt > deg_to_rad(90.0):
			ac.target_position = tgt_pos
			# 目标在后半球（>90°），机炮打不到。必须清 is_firing + 把 lead 对回机头，
			# 否则 _update_gun 会用上一帧陈旧 _gun_lead_heading 持续朝世界某方向侧射
			# （_auto_gun_scan 开头的 is_firing 保护进一步冻结 lead）
			ac.is_firing = false
			ac._gun_lead_heading = ac.heading
			if ac.use_tactical_preference:
				ac._pursuit_branch = "BIG_TURN_>90"
				_log_pursuit_snapshot(ac, dist, my_fwd.dot(to_target), in_rear_hemisphere, heading_diff_to_tgt)
			return

		if is_missile_mode:
			# ---- 导弹模式（分阶段追踪 + 距离保持） ----
			# v9 sync: ideal_range 基于雷达有效射程（和 tactical/energy_management 一致）
			var msl_phase := ac._get_missile_phase()
			var msl := ac.params.missile
			var min_range_px := msl.min_range * CombatUnit.PIXELS_PER_METER if msl else 250.0
			var ideal_range_px := ac._effective_missile_range_px() * MISSILE_IDEAL_RANGE_MULT if msl else DEFAULT_MISSILE_RANGE_PX

			if dist < min_range_px:
				# 太近：拉开距离，垂直于目标航向脱离
				var away := (my_pos - tgt_pos).normalized()
				pursuit_pos = my_pos + away * ideal_range_px * 0.5
			elif dist < ideal_range_px and msl_phase >= 1:
				# 已在射程内且正在锁定/已发射：保持当前距离，不再接近
				# 沿目标侧面平行飞行（crank 机动）
				var perp := Vector2(-tgt_fwd.y, tgt_fwd.x)  # 目标航向的垂直方向
				var side: float = sign(perp.dot(my_pos - tgt_pos))  # 我在目标的哪一侧
				if side == 0:
					side = 1.0
				pursuit_pos = tgt_pos + perp * side * dist * CRANK_LATERAL_RATIO + tgt_fwd * tgt_speed_px * 1.0
			elif msl_phase == 0:
				# 接近阶段：拦截追踪，但限制最小保持距离
				var intercept_lead := clampf(dist / maxf(my_speed_px, 50.0), INTERCEPT_LEAD_MIN, cb.intercept_lead_max)
				pursuit_pos = tgt_pos + tgt_fwd * tgt_speed_px * intercept_lead
			elif msl_phase == 1:
				# 照射阶段：温和跟踪
				var lead_time := clampf(dist / maxf(my_speed_px + tgt_speed_px, 100.0), LOCK_LEAD_MIN, LOCK_LEAD_MAX)
				pursuit_pos = tgt_pos + tgt_fwd * tgt_speed_px * lead_time
			else:
				# 保持阶段（已发射）：维持距离
				pursuit_pos = tgt_pos
		else:
			# ---- 机炮模式追踪：复用距离+速度感知的动态追踪 ----
			pursuit_pos = choose_dogfight_pursuit_pos(
					ac, my_pos, dist, tgt_pos, tgt_fwd, tgt_speed_px, my_speed_px, in_rear_hemisphere)

		ac.target_position = pursuit_pos

	# ---- 开火判定（对前置点）—— 仅机炮模式 ----
	var gun := ac.params.gun if ac.params else null
	if gun and ac.ammo > 0 and not is_missile_mode:
		var range_px := ac.effective_gun_range_m() * CombatUnit.PIXELS_PER_METER
		var base_cone := deg_to_rad(ac.effective_gun_cone_half_angle_deg())

		# 计算前置射击点（两轮迭代修正）：
		# 第一轮用到目标距离估算飞行时间，第二轮用到前置点距离修正，
		# 解决追击高速目标时前置量不足、子弹落在目标后方的问题
		var bullet_speed_px := gun.muzzle_velocity * CombatUnit.PIXELS_PER_METER
		var t1 := dist / maxf(bullet_speed_px, 100.0)
		var lead1 := tgt_pos + tgt_fwd * tgt_speed_px * t1
		var t2 := my_pos.distance_to(lead1) / maxf(bullet_speed_px, 100.0)
		var lead_pos := tgt_pos + tgt_fwd * tgt_speed_px * t2

		# 机头与前置点的偏差
		var to_lead := lead_pos - my_pos
		var angle_to_lead := atan2(to_lead.x, -to_lead.y)
		var angle_diff := absf(Aircraft._angle_diff(angle_to_lead, ac.heading))
		var lead_dist := to_lead.length()

		var fire_cone: float
		var fire_range: float
		if in_rear_hemisphere or closing_rate > my_speed_px * cb.closing_rate_threshold:
			# 在后半球 或 闭合率充裕：标准射击，满射程
			fire_cone = base_cone
			fire_range = range_px
		else:
			# 侧面/正面且追不上：机会射击，缩短射程
			fire_cone = base_cone * cb.opportunity_cone_mult
			fire_range = range_px * cb.opportunity_range_mult

		# 高度差检查（米），超过 500m 不开火（扁平高度模式下忽略）
		var alt_diff := absf(ac.altitude - ac.combat_target.altitude)
		# 射程检查用到目标的实际距离（dist），不用到前置点的距离（lead_dist），
		# 因为迭代修正后前置点更远，用 lead_dist 会误判超出射程导致不开火
		var _want_fire := dist > MIN_GUN_FIRE_DIST_PX and dist <= fire_range and angle_diff <= fire_cone and (ac.flat_altitude or alt_diff < GUN_FIRE_ALT_DIFF_M)
		ac.is_firing = ac._ai_gun_burst_allowed(_want_fire, ac.get_physics_process_delta_time())
		# 缓存前置点供 _update_gun 使用
		ac._gun_lead_heading = angle_to_lead
	else:
		ac.is_firing = false
		ac._gun_lead_heading = ac.heading

	# 诊断快照（仅玩家，节流 0.5s 一次）—— 详见 docs/changelogs/player-ai-log.md
	if ac.use_tactical_preference:
		_log_pursuit_snapshot(ac, dist, my_fwd.dot(to_target), in_rear_hemisphere, aspect_angle)

## ========== 地面攻击（Strafing Run） ==========
## 飞机对地面静止/慢速目标的攻击模式：
## 1. 从远处直线飞向目标（进入跑道）
## 2. 飞越目标上空，途中开火
## 3. 越过后直线延伸脱离
## 4. 掉头回来进行下一轮

static func update_combat_ground_attack(ac: Aircraft) -> void:
	var my_pos := ac.global_position
	var tgt_pos := ac.combat_target.global_position
	var dist := my_pos.distance_to(tgt_pos)
	var my_fwd := Vector2(sin(ac.heading), -cos(ac.heading))
	var to_target := (tgt_pos - my_pos).normalized()
	var is_missile_mode := ac.weapon_mode == Aircraft.WeaponMode.MISSILE

	# 目标是否在前方（点积 > 0 = 前方）
	var dot_fwd := my_fwd.dot(to_target)
	var heading_to_tgt := atan2(to_target.x, -to_target.y)
	var heading_diff := absf(Aircraft._angle_diff(heading_to_tgt, ac.heading))

	# 状态机
	match ac._strafe_state:
		0:  # 进入：远距离对准目标
			if dist < STRAFE_ATTACK_RANGE and heading_diff < deg_to_rad(STRAFE_HEADING_DEG):
				ac._strafe_state = 1  # 进入攻击阶段
			else:
				# 对准目标直飞
				ac.target_position = tgt_pos
		1:  # 攻击：直线飞向/飞越目标
			ac.target_position = tgt_pos
			# 检查是否已经飞过目标（目标在身后）
			if dot_fwd < -0.2 and dist > 50.0:
				ac._strafe_state = 2
				ac._strafe_extend_dist = 0.0
		2:  # 脱离：越过后继续直飞一段距离
			# 保持当前方向直飞
			ac.target_position = my_pos + my_fwd * STRAFE_EXTEND_FWD_PX
			ac._strafe_extend_dist += ac.speed * CombatUnit.PIXELS_PER_METER * ac.get_physics_process_delta_time()
			if ac._strafe_extend_dist > STRAFE_EXTEND_RANGE:
				ac._strafe_state = 3
		3:  # 掉头：转向目标准备下一轮
			ac.target_position = tgt_pos
			if heading_diff < deg_to_rad(STRAFE_TURNBACK_HDG_DEG) and dist > STRAFE_ATTACK_RANGE * STRAFE_TURNBACK_RATIO:
				ac._strafe_state = 0  # 回到进入阶段

	# ---- 高度管理：攻击时降低高度 ----
	if ac.flat_altitude:
		if ac._strafe_state <= 1:
			ac.set_target_tier(CombatUnit.AltitudeTier.LOW)  # 攻击时降到低空
		else:
			# 脱离/掉头时根据偏好恢复
			if ac.altitude_preference == Aircraft.AltitudePreference.PREFER_CLIMB:
				ac.set_target_tier(CombatUnit.AltitudeTier.MID)
	else:
		if ac._strafe_state <= 1:
			ac.target_altitude = STRAFE_ATTACK_ALT_M  # 低空进入
		else:
			ac.target_altitude = STRAFE_CLIMB_ALT_M  # 脱离时爬升

	# ---- 开火判定 ----
	ac.is_firing = false
	ac._gun_lead_heading = ac.heading

	# 导弹模式：远距离锁定发射
	if is_missile_mode:
		# 导弹发射由 _update_missile 处理，这里不设 is_firing
		pass
	else:
		# 机炮：攻击阶段 + 在范围内 + 机头对准 → 开火
		var gun := ac.params.gun if ac.params else null
		if gun and ac.ammo > 0 and ac._strafe_state <= 1:
			var range_px := ac.effective_gun_range_m() * CombatUnit.PIXELS_PER_METER
			var fire_cone := deg_to_rad(ac.effective_gun_cone_half_angle_deg() * GROUND_FIRE_CONE_MULT)  # 对地放宽火控角
			if dist < range_px and heading_diff < fire_cone:
				ac.is_firing = true
				ac._gun_lead_heading = heading_to_tgt  # 地面目标静止，直接瞄

## 智能攻击位置评估（所有机炮攻击共用）
## ══════════════════════════════════════════════════════════
##  评估当前几何 → 选最优攻击角度（不是套一个固定公式）：
##
##   情况 A — 已经对准目标（机头夹角 < 30° 且在后半球）：
##       → 直接瞄目标本体，走高效击杀路径（配合 OVERSHOOT 禁用，穿过时持续开火）
##       → 对慢目标最高效：一次通场直接打死
##
##   情况 B — 在后半球但角度未对准（夹角 > 30°）：
##       → 6 点钟偏移（尾跟位）把自己导入到后半球合适位置
##       → 偏移被 gun_range × 1.5 封顶，防止对慢目标出现"瞄远离目标的点"
##
##   情况 C — 前半球 / 侧翼：
##       → 前置拦截（lead intercept），瞄目标预测位置
##       → 玩家切入完成侧向或迎头攻击，穿过后自然落到后半球重新评估
##
##  核心原则（用户要求的"永远做这个判断"）：
##   1. 观察敌机朝向 tgt_fwd + 速度 → 知道目标在往哪飞
##   2. 计算瞄准对齐度 aim_align → 知道自己现在对得准不准
##   3. 综合相对位置（后半/前半）+ 对齐度 → 选最优策略
## 玩家追击状态快照（节流 0.5s 一次）
## 输出：branch / dist_m / aim_align / rear / aspect_deg / target_bearing_rel / heading_diff / turn_sign / firing / wpn / ammo
## 含义：
##   - branch: 选中的追击分支（A_rear_aligned / B_rear_six_offset / C_lead_intercept / C_head_on_guard / OVERSHOOT_EXT / BIG_TURN_>90）
##   - tgt_bearing_rel: target_position 相对玩家机头的方位角（度），+右 / -左 → 用来对照"该往哪边转"
##   - heading_diff: 当前机头与 target_position 方向的差（度，带符号）
##   - turn_sign: _committed_turn_sign 状态（0 未锁 / +1 右 / -1 左）→ 判断是否卡在错误方向
static func _log_pursuit_snapshot(ac: Aircraft, dist_px: float, aim_align: float, in_rear: bool, aspect_angle_rad: float) -> void:
	ac._pursuit_log_timer -= ac.get_physics_process_delta_time()
	if ac._pursuit_log_timer > 0.0:
		return
	ac._pursuit_log_timer = PURSUIT_LOG_INTERVAL

	var tgt_bearing_rel_deg := 0.0
	var heading_diff_deg := 0.0
	if ac.target_position != Vector2.INF:
		var to_tp := ac.target_position - ac.global_position
		var tp_heading := atan2(to_tp.x, -to_tp.y)
		tgt_bearing_rel_deg = rad_to_deg(Aircraft._angle_diff(tp_heading, ac.heading))
		heading_diff_deg = tgt_bearing_rel_deg  # 和 target_position 方向的差
	var tgt_name := ac._log_unit_name(ac.combat_target)
	var wpn := "GUN" if ac.weapon_mode == Aircraft.WeaponMode.GUN else "MSL"
	var msg := "branch=%s tgt=%s dist=%dm aim=%.2f rear=%s asp=%d° tp_brg=%+d° hdg_diff=%+d° turn_sign=%+d firing=%s wpn=%s ammo=%d" % [
		ac._pursuit_branch, tgt_name,
		int(dist_px / CombatUnit.PIXELS_PER_METER),
		aim_align, str(in_rear), int(rad_to_deg(aspect_angle_rad)),
		int(tgt_bearing_rel_deg), int(heading_diff_deg),
		int(ac._committed_turn_sign), str(ac.is_firing), wpn, ac.ammo,
	]
	EventLogger.log_event("PURSUIT", ac._log_name(), msg)

	# 同周期附带：扫描正在交战玩家的敌方飞机，打印中队结构 + 战术 + 各自目标
	# 用来诊断"同中队飞机爱理不睬"—— 同一 squad 的僚机若 target 各不相同或多数 target 为空，
	# 就是编队协同失效的证据。
	_log_enemy_squads_engaging_player(ac)

## 扫描敌方中队，找出"至少有一个成员在交战玩家"的中队，列出整个中队所有成员
## 关键：哪怕某架僚机自己没把玩家当目标（正在跑路/归队/乱飞），只要它的中队有人在打玩家，
## 这架僚机就要进 log —— 用来诊断"1 架打玩家其他 3 架跑向地图边缘"这类协同失效 bug
## 每条记录：<callsign>[type] sq=<leader#idx> st=<state> tac=<tactic> tgt=<他的目标> d=<距玩家> dL=<距长机> spd=<km/h> hdg=<°>
static func _log_enemy_squads_engaging_player(ac: Aircraft) -> void:
	# Pass 1: 找到至少有一个成员在交战玩家的中队 + 无中队的单机交战者
	var engaged_squads: Array[Squad] = []
	var solo_engagers: Array[Aircraft] = []
	for unit in CombatUnit.all_units:
		if not is_instance_valid(unit) or unit.is_destroyed:
			continue
		if not ac.is_hostile_to(unit):
			continue
		if not (unit is Aircraft):
			continue
		var enemy_ac: Aircraft = unit
		var ai := enemy_ac._get_ai_controller()
		var engaging: bool = (ai != null and ai._current_target == ac) or enemy_ac.combat_target == ac
		if not engaging:
			continue
		if ai and ai.squad:
			if not engaged_squads.has(ai.squad):
				engaged_squads.append(ai.squad)
		else:
			solo_engagers.append(enemy_ac)

	if engaged_squads.is_empty() and solo_engagers.is_empty():
		return

	# Pass 2: 对每个参战中队列出所有存活成员（含不交战玩家的那几架）+ 单机交战者
	var entries: Array[String] = []
	for sq in engaged_squads:
		if not sq or not sq.leader or not is_instance_valid(sq.leader):
			continue
		var ldr_name: String = sq.leader.callsign
		for member_ac in sq.members:
			if not is_instance_valid(member_ac) or member_ac.is_destroyed:
				continue
			entries.append(_format_enemy_entry(ac, member_ac, ldr_name, sq.leader))
	for solo_ac in solo_engagers:
		entries.append(_format_enemy_entry(ac, solo_ac, "", null))
	if entries.is_empty():
		return
	EventLogger.log_event("ENEMY_SQUAD", ac._log_name(), " | ".join(entries))

## 格式化单架敌机诊断条目（被 _log_enemy_squads_engaging_player 复用）
static func _format_enemy_entry(ac: Aircraft, enemy_ac: Aircraft, ldr_name: String, leader: Aircraft) -> String:
	var ai := enemy_ac._get_ai_controller()
	var state_abbr := "-"
	var tactic := "-"
	var his_tgt := "-"
	var flags := ""
	var idx: int = -1
	if ai:
		match ai._state:
			0: state_abbr = "P"
			1: state_abbr = "E"
			2: state_abbr = "V"
			3: state_abbr = "F"
			_: state_abbr = "?"
		tactic = ai.current_tactic_name if ai.current_tactic_name != "" else "-"
		idx = ai.squad_index
		if ai._squad_attacking_leader_target:
			flags += "[tm]"
		if ai._squad_free_engaging:
			flags += "[fr]"
		if ai.salvo_leader:
			flags += "[sl]"
		if ai._current_target and is_instance_valid(ai._current_target) and not ai._current_target.is_destroyed:
			his_tgt = ac._log_unit_name(ai._current_target)
	if his_tgt == "-" and enemy_ac.combat_target and is_instance_valid(enemy_ac.combat_target):
		his_tgt = ac._log_unit_name(enemy_ac.combat_target)
	var sq_tag: String = ("%s#%d" % [ldr_name, idx]) if ldr_name != "" else "solo"
	var d_me: int = int(ac.global_position.distance_to(enemy_ac.global_position) / CombatUnit.PIXELS_PER_METER)
	var d_ldr_str := ""
	if leader and leader != enemy_ac and is_instance_valid(leader):
		var d_ldr: int = int(enemy_ac.global_position.distance_to(leader.global_position) / CombatUnit.PIXELS_PER_METER)
		d_ldr_str = " dL=%dm" % d_ldr
	var spd_kmh: int = int(enemy_ac.speed * 3.6)
	var hdg_deg: int = int(rad_to_deg(enemy_ac.heading))
	var type_name: String = enemy_ac.params.display_name if enemy_ac.params else "?"
	return "%s[%s] sq=%s st=%s tac=%s%s tgt=%s d=%dm%s spd=%d hdg=%d°" % [
		enemy_ac.callsign, type_name, sq_tag, state_abbr, tactic, flags, his_tgt, d_me, d_ldr_str, spd_kmh, hdg_deg,
	]

static func choose_dogfight_pursuit_pos(
		ac: Aircraft,
		my_pos: Vector2,
		dist: float,
		tgt_pos: Vector2,
		tgt_fwd: Vector2,
		tgt_speed_px: float,
		my_speed_px: float,
		in_rear: bool
) -> Vector2:
	var gun_range := ac._gun_range_px()

	# ── 当前瞄准对齐度 ──
	var my_fwd := Vector2(sin(ac.heading), -cos(ac.heading))
	var to_target := (tgt_pos - my_pos).normalized()
	var aim_align := my_fwd.dot(to_target)  ## 1.0=完美对准, 0=90°偏, -1=背朝

	# ══════════════════════════════════════
	# 情况 A：后半球 + 已对准（30° 内）→ 直瞄目标，立即高效开火
	# ══════════════════════════════════════
	if in_rear and aim_align > 0.87:  # cos(30°) ≈ 0.866
		# 玩家机头已经指着目标方向，最优策略就是直线冲进去连续射击
		# 配合 OVERSHOOT 禁用（慢目标专用），穿过目标时依然开火
		# 穿过后 in_rear 会变 false，自然切到 C 分支
		if ac.use_tactical_preference:
			ac._pursuit_branch = "A_rear_aligned"
		# 2026-04-22 修：target_position 从 tgt_pos 改为 lead 点。
		# 原因：开火判定用的是 lead_pos，高速目标（UAV 178m/s）lead 横偏可达
		# ~17°，而 fire_cone=5°，机头追 tgt_pos 时永远不满足 angle_diff<=fire_cone
		# → 追尾对准却一发不发。让 target_position 直接收敛到 lead 即可消除这个偏差。
		var gun_a: GunParams = ac.params.gun if ac.params else null
		if gun_a:
			var bullet_px: float = gun_a.muzzle_velocity * CombatUnit.PIXELS_PER_METER
			var t1_a: float = dist / maxf(bullet_px, 100.0)
			var lead1_a: Vector2 = tgt_pos + tgt_fwd * tgt_speed_px * t1_a
			var t2_a: float = my_pos.distance_to(lead1_a) / maxf(bullet_px, 100.0)
			return tgt_pos + tgt_fwd * tgt_speed_px * t2_a
		return tgt_pos

	# ══════════════════════════════════════
	# 情况 B：后半球但未对准 → 6 点钟偏移，导入合适位置
	# ══════════════════════════════════════
	if in_rear:
		# 6 点钟偏移：距离越近偏移越大（防冲过）
		# 上限被 gun_range × 1.5 封顶（约 1500m），避免对慢目标形成远离目标的追踪点
		var t_six := clampf(dist / (gun_range * SIX_OCLOCK_NORM), 0.0, 1.0)
		var offset_ratio := lerpf(1.0, SIX_OCLOCK_FAR_RATIO, t_six)  ## 近距 1.0× 到远距 0.3×
		var six_offset := clampf(gun_range * offset_ratio, SIX_OCLOCK_OFFSET_MIN_PX, gun_range * SIX_OCLOCK_MAX_MULT)

		# 守卫：玩家已经在目标六点钟"内侧"（dist < six_offset）时，原公式的
		# pursuit_pos = tgt_pos - tgt_fwd × six_offset 会落在玩家身后 → 飞机 180° U 形
		# 倒退到"理想的六点钟切入点"，再重新冲进来，形成大回环死循环。
		# 见 docs/changelogs/player-ai-log.md 2026-04-20 (3) 的 log 分析。
		# 原 B 分支公式保留不动；仅在"候选追击点在我身后"这个病态几何下 early-return 到目标本身，
		# 让物理照 aim_align 继续朝目标延伸，等 in_rear 自然翻转到 false 后走 C 分支
		var six_pos := tgt_pos - tgt_fwd * six_offset
		var to_six_dir := (six_pos - my_pos).normalized()
		if to_six_dir.dot(my_fwd) < 0.0:
			if ac.use_tactical_preference:
				ac._pursuit_branch = "B_guard_six_behind_me"
			return tgt_pos

		if ac.use_tactical_preference:
			ac._pursuit_branch = "B_rear_six_offset"
		return six_pos

	# ══════════════════════════════════════
	# 情况 C：前半球 / 侧翼 → 前置拦截，瞄目标预测位置
	# ══════════════════════════════════════
	# 2026-04-22：闭合率改用 LOS 方向分量（真实相对速度投影），替代原 my_speed - tgt_speed
	# 的粗暴公式。原公式在敌机更快 + 非完美对头（head_on_guard 接不住）时被 MIN 钳死 →
	# predict_time 拉满 3s → 前置点飞到 2500m 外的随机方位 → 玩家 heading 永远追不上 →
	# 5° fire_cone 判定永远失败 → 永远不开火。
	# 合成真实闭合率（沿 LOS 方向）：
	#   我沿连线的分量 = my_fwd · to_target = aim_align
	#   敌沿反向连线的分量 = -tgt_fwd · to_target = head_on_dot
	# 对头、侧翼、追尾三种几何都对。
	var head_on_dot := -tgt_fwd.dot(to_target)  # 1.0 = 完美对头, -1.0 = 同向追尾
	var closing_rate := maxf(aim_align * my_speed_px + head_on_dot * tgt_speed_px, MIN_CLOSING_RATE_PX)
	var predict_time := clampf(dist / closing_rate, PREDICT_TIME_MIN, PREDICT_TIME_MAX)

	# ── 对头场景守卫（保留作为保守子集，主闭合率公式已修正后其实是等价的）──
	# head_on_dot > 0.7 + aim_align > 0.7 这条原本是补救，现在作为 no-op 保险，
	# 万一以后主公式改回也不会漏掉强对头场景。
	if head_on_dot > 0.7 and aim_align > 0.7:
		if ac.use_tactical_preference:
			ac._pursuit_branch = "C_head_on_guard"
		return tgt_pos + tgt_fwd * tgt_speed_px * predict_time

	if ac.use_tactical_preference:
		ac._pursuit_branch = "C_lead_intercept"
	return tgt_pos + tgt_fwd * tgt_speed_px * predict_time


static func missile_cannot_hit_but_gun_can(ac: Aircraft) -> bool:
	if ac.combat_target == null or not is_instance_valid(ac.combat_target) or ac.combat_target.is_destroyed:
		return false
	if not ac.params or not ac.params.gun:
		return false  # 无机炮可切
	var dist_m := ac.global_position.distance_to(ac.combat_target.global_position) / CombatUnit.PIXELS_PER_METER
	var gun_range_m: float = ac.effective_gun_range_m()
	if dist_m > gun_range_m:
		return false  # 机炮也打不到
	# 选取"将要发射"的导弹类型对应的 min_range（与 _update_missile 选择逻辑一致）：
	# 地面目标 → AGM（secondary），空中目标 → AAM（primary）
	# 2026-04-21 bug 修复：原来固定用 primary min_range，AGM min 300m 的机会被
	# AAM 500m 门槛吞掉，导致靠近 SAM 时 weapon_mode 被切到 GUN 再也回不来
	var target_is_ground: bool = ac.combat_target is GroundUnit
	var effective_missile: MissileParams = null
	if target_is_ground and ac.params.secondary_missile and ac.secondary_missiles_remaining > 0:
		effective_missile = ac.params.secondary_missile
	elif ac.params.missile and ac.missiles_remaining > 0:
		effective_missile = ac.params.missile
	elif target_is_ground and ac.params.missile and ac.missiles_remaining > 0:
		effective_missile = ac.params.missile  # fallback
	if effective_missile == null:
		return true  # 无可用导弹只能用机炮
	# 核心规则：dist 太近（进不了导弹 min_range）且机炮能打 → 用机炮
	var min_threshold: float = effective_missile.min_range
	# 滞回：已在机炮模式时，需要飞出 min_range + 150m 才切回导弹
	if ac.weapon_mode == Aircraft.WeaponMode.GUN:
		min_threshold += WEAPON_MODE_HYSTERESIS_M
	if dist_m < min_threshold:
		return true
	return false

## 是否应当提交这次机炮攻击：有目标且已接近机炮射程范围
static func should_commit_gun_pass(ac: Aircraft) -> bool:
	if ac.combat_target == null or not is_instance_valid(ac.combat_target) or ac.combat_target.is_destroyed:
		return false
	var dist := ac.global_position.distance_to(ac.combat_target.global_position)
	# 接近机炮射程（2 倍范围内）视为开始攻击，进入提交
	return dist < ac._gun_range_px() * GUN_PASS_COMMIT_MULT

## 机炮攻击是否已完成：目标在身后且拉开距离，或目标失效
static func is_gun_pass_finished(ac: Aircraft) -> bool:
	if ac.combat_target == null or not is_instance_valid(ac.combat_target) or ac.combat_target.is_destroyed:
		return true
	var to_tgt := ac.combat_target.global_position - ac.global_position
	var dist := to_tgt.length()
	if dist < 1.0:
		return false
	var my_fwd := Vector2(sin(ac.heading), -cos(ac.heading))
	var fwd_dot := my_fwd.dot(to_tgt / dist)
	# 目标在身后 (dot < -0.2 ≈ 超过机尾 100° 锥内) 且 已拉开到机炮射程外 → 飞过完成
	return fwd_dot < TARGET_BEHIND_DOT and dist > ac._gun_range_px()

## 检查目标是否在导弹射程包线内
static func is_in_missile_envelope(ac: Aircraft, target_unit: CombatUnit, msl: MissileParams) -> bool:
	var dist_px := ac.global_position.distance_to(target_unit.global_position)
	var dist_m := dist_px / CombatUnit.PIXELS_PER_METER

	if dist_m < msl.min_range:
		return false

	# TAA（目标纵横角）
	var tgt_fwd := Vector2(sin(target_unit.heading), -cos(target_unit.heading))
	var to_me := (ac.global_position - target_unit.global_position).normalized()
	var taa_rad := acos(clampf(-tgt_fwd.dot(to_me), -1.0, 1.0))
	var taa_deg := rad_to_deg(taa_rad)

	# 最大射程
	var max_range: float
	if taa_deg <= 90.0:
		var t := taa_deg / 90.0
		max_range = msl.max_range_rear * msl.front_rear_ratio * (1.0 - t) + msl.max_range_rear * t
	else:
		max_range = msl.max_range_rear

	# 高度射程加成（扁平模式下固定中档基准）
	var alt_factor: float
	if ac.flat_altitude:
		alt_factor = 1.5
	else:
		alt_factor = clampf(1.0 + (ac.altitude / 12000.0) * 1.5, 1.0, 3.0)
	max_range *= alt_factor

	if dist_m > max_range:
		return false

	# 高度差限制（扁平模式下忽略）——**仅对空中目标**：
	# 5000m 上限：use_combat_altitude 把 AI 高度 clamp 到 ±2500m，正常情况下不会触底；
	# 触发本限制说明 AI 处在 yoyo / extension 等过渡状态，应当禁火等高度回落。
	# 面目标（非 Aircraft：地面/舰船 altitude≈0）豁免（2026-07-26，log 20260726_165536）：
	# STANDOFF 学说命令 MID(3500~7500) 高位打带跑，其上半带（>5000m）+ 玩家 PREFER_CLIMB
	# （HIGH≥7500）会恒触此门 → 对地导弹永拒且无声（高度落哪半带决定发/不发 = 玄学复发）。
	# 对空语义原样保留。
	if not ac.flat_altitude and target_unit is Aircraft \
			and absf(ac.altitude - target_unit.altitude) > 5000.0:
		return false

	return true
