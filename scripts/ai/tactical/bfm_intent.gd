class_name BfmIntent extends RefCounted

## BFM 战术意图函数集 —— 每个函数纯输入输出，可单独单元测试。
##
## 调用约定：
##   var plan: TacticalPlan = BfmIntent.tail_chase(situation)
##
## 函数签名：(s: Situation) → TacticalPlan
## 函数实现要求：
## 1. 不修改 s（Situation 在 _recompute 后视为只读）
## 2. 不读取 Aircraft / Node / 全局状态
## 3. 必填 plan.intent / pursuit_pos / target_speed_kmh / afterburner
## 4. 武器决策填 weapon_mode + allow_gun_fire + allow_missile_fire（默认 NONE / false）
## 5. plan.rationale 写一句中文为什么选这个 intent，便于 log

# 几何阈值（与 aircraft_combat_tracking 现有公式对齐）
const TAIL_AIM_THRESHOLD := 0.87       ## cos(30°) ≈ 0.866，超过即"已对准尾后"
const HEAD_ON_THRESHOLD := 0.7         ## head_on_dot > 0.7 视为对头几何
const HIGH_BANK_DEG := 60.0            ## 目标 bank 超此判定急转
const FIRE_CONE_HALF_DEG := 5.0        ## 机炮火控角（与 default_gun.tres 一致）
const GUN_RANGE_HYSTERESIS := 1.2      ## 进入射程的滞回缓冲

# ══════════════════════════════════════════════
#  无目标 / 巡航 / 移动
# ══════════════════════════════════════════════

static func cruise(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.CRUISE
	p.pursuit_pos = Vector2.INF
	p.target_speed_kmh = s.cruise_speed_kmh
	p.afterburner = false
	# CRUISE 显式设 GUN（不是 NONE）：让 update_missile 的 weapon_mode != MISSILE 早退守卫触发，
	# 杜绝 weapon_mode 残留 MISSILE 时 salvo 路径在玩家不知情下自动发射
	p.weapon_mode = TacticalPlan.WeaponMode.GUN
	# 玩家高度偏好（PREFER_CLIMB=0=HIGH, PREFER_LOW=1=LOW）
	p.target_altitude_tier = _altitude_tier_from_preference(s.altitude_preference)
	p.rationale = "无目标巡航"
	return p

## 玩家无 combat_target 但雷达锁住敌人 + auto-fire 开 → 让 salvo 路径接管发射
## 这是 RTS 风格的"被动开火"：玩家不需要点目标，雷达里只要锁住、在包络内就自动发
static func passive_auto_fire(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.PASSIVE_AUTO_FIRE
	p.pursuit_pos = Vector2.INF  # 不改变航向，玩家自由飞
	p.target_speed_kmh = s.cruise_speed_kmh
	p.afterburner = false
	# 给 salvo 路径开门：weapon_mode = MISSILE 让 update_missile 通过早退检查，
	# allow_missile_fire = true 让 _apply 写入 plan 时不阻断
	p.weapon_mode = TacticalPlan.WeaponMode.MISSILE
	p.allow_missile_fire = true
	# 玩家高度偏好仍生效
	p.target_altitude_tier = _altitude_tier_from_preference(s.altitude_preference)
	p.rationale = "被动 auto-fire：salvo 路径自由打雷达锁定目标"
	return p

static func waypoint_move(s: Situation, waypoint: Vector2) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.WAYPOINT_MOVE
	p.pursuit_pos = waypoint
	# 大角度转弯走 corner speed，对准后走 max_speed × 0.85（不浪费 AB）
	var to_wp: Vector2 = waypoint - s.my_pos
	var hdg_to_wp: float = atan2(to_wp.x, -to_wp.y)
	var hdiff_deg: float = rad_to_deg(absf(Situation._angle_diff(hdg_to_wp, s.my_heading)))
	if hdiff_deg > 60.0:
		p.target_speed_kmh = s.corner_speed_kmh
		p.afterburner = false
		p.rationale = "航点大角度转弯：corner speed"
	else:
		p.target_speed_kmh = s.max_speed_kmh * 0.85
		p.afterburner = (s.my_speed_ms * 3.6) < s.max_speed_kmh * 0.8
		p.rationale = "航点对准：max×0.85 巡航推进"
	# 即使在移动到航点中，也允许被动 auto-fire（条件同 PASSIVE_AUTO_FIRE）：
	# 移动 / 开火是两个独立通道，玩家点了"走那边"不应当抑制对锁定敌机的导弹发射
	if s.missile_auto_fire and s.missiles > 0 and s.has_radar_lock \
			and s.weapon_lock != Situation.WEAPON_LOCK_FORCE_GUN:
		p.weapon_mode = TacticalPlan.WeaponMode.MISSILE
		p.allow_missile_fire = true
		p.rationale += " | 被动 auto-fire 并行"
	# 玩家高度偏好：航点移动期间维持选定高度档
	p.target_altitude_tier = _altitude_tier_from_preference(s.altitude_preference)
	return p

# ══════════════════════════════════════════════
#  规避（最高优先级）
# ══════════════════════════════════════════════

static func evade_missile(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.EVADE_MISSILE
	# 规避具体几何（垂直机动 / 桶滚 / 高度切换）由 Aircraft._update_evasion 自己驱动 target_position，
	# planner 这里只决定速度 + AB + 武器静默
	p.pursuit_pos = Vector2.INF
	p.target_speed_kmh = s.max_speed_kmh
	p.afterburner = true
	p.weapon_mode = TacticalPlan.WeaponMode.NONE
	p.rationale = "规避导弹：max + AB，几何由 _update_evasion 决定"
	return p

# ══════════════════════════════════════════════
#  尾追三态：CLOSE_TAIL → TAIL_CHASE
# ══════════════════════════════════════════════

## 已咬尾对准但距离太远 → 加力闭合
static func close_tail(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.CLOSE_TAIL
	p.pursuit_pos = _gun_lead_point(s)  # 默认机炮模式 lead 点；missile 分支下方覆盖
	_apply_combat_weapon(s, p)
	if p.weapon_mode == TacticalPlan.WeaponMode.MISSILE:
		# 导弹模式 → 走 crank 几何 + 分段速度（远距加力闭合，crank 段才减速）
		p.pursuit_pos = _missile_engage_pos(s)
		var spd := _missile_engage_speed(s)
		p.target_speed_kmh = spd[0]
		p.afterburner = spd[1]
		p.rationale = "尾追：导弹（dist=%.0fm）" % s.dist_m
	else:
		# 机炮模式：加力闭合到机炮射程
		p.target_speed_kmh = s.max_speed_kmh * 0.9
		p.afterburner = (s.my_speed_ms * 3.6) < s.max_speed_kmh * 0.85
		p.rationale = "尾追远距：加力闭合机炮射程"
	_apply_squad_lateral_offset(s, p)
	_apply_target_altitude(s, p)
	return p

## 已咬尾在射程内 → 匹配速度稳定射击
static func tail_chase(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.TAIL_CHASE
	p.pursuit_pos = _gun_lead_point(s)
	_apply_combat_weapon(s, p)
	if p.weapon_mode == TacticalPlan.WeaponMode.MISSILE:
		p.pursuit_pos = _missile_engage_pos(s)
		var spd := _missile_engage_speed(s)
		p.target_speed_kmh = spd[0]
		p.afterburner = spd[1]
		p.rationale = "尾追：导弹（dist=%.0fm）" % s.dist_m
	else:
		var match_kmh: float = maxf(s.tgt_speed_ms * 3.6 * 1.2, s.corner_speed_kmh)
		p.target_speed_kmh = minf(match_kmh, s.max_speed_kmh)
		p.afterburner = false
		p.rationale = "尾追：机炮射程内匹配速度"
	_apply_squad_lateral_offset(s, p)
	_apply_target_altitude(s, p)
	return p

# ══════════════════════════════════════════════
#  侧翼 / 前半球
# ══════════════════════════════════════════════

## 后半球但未对准 → 抢占六点钟切入
static func lead_turn(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.LEAD_TURN
	var six_offset_px: float = clampf(s.gun_range_px() * 0.6, 200.0, s.gun_range_px() * 1.5)
	p.pursuit_pos = s.tgt_pos - s.tgt_fwd * six_offset_px
	_apply_combat_weapon(s, p)
	if p.weapon_mode == TacticalPlan.WeaponMode.MISSILE:
		# 导弹包络已满足就直接走 crank，不必再切六点
		p.pursuit_pos = _missile_engage_pos(s)
		var spd := _missile_engage_speed(s)
		p.target_speed_kmh = spd[0]
		p.afterburner = spd[1]
		p.rationale = "侧后未对准：导弹（dist=%.0fm）" % s.dist_m
	else:
		p.target_speed_kmh = s.corner_speed_kmh
		p.afterburner = false
		p.rationale = "后半球未对准：corner speed 切入六点"
	_apply_target_altitude(s, p)
	return p

## 侧翼 + 目标急转 → 内切圆滞后追踪（lag pursuit，BFM 经典反绕圈机动）
static func lag_pursuit(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.LAG_PURSUIT
	# 估算目标转弯圆心：R = V² / (g × tan(bank))
	var tgt_speed_ms: float = maxf(s.tgt_speed_ms, 50.0)
	var bank_rad: float = deg_to_rad(absf(s.tgt_bank_deg))
	var tan_bank: float = tan(bank_rad)
	if tan_bank < 0.1:
		# 没在转弯，退化成 lead pursuit
		return lead_pursuit(s)
	var radius_m: float = (tgt_speed_ms * tgt_speed_ms) / (9.81 * tan_bank)
	var radius_px: float = radius_m * CombatUnit.PIXELS_PER_METER
	var perp: Vector2 = Vector2(-s.tgt_fwd.y, s.tgt_fwd.x)
	var bank_sign: float = signf(s.tgt_bank_deg) if s.tgt_bank_deg != 0.0 else 1.0
	var center: Vector2 = s.tgt_pos - perp * bank_sign * radius_px
	var center_to_tgt: Vector2 = (s.tgt_pos - center).normalized()
	p.pursuit_pos = center + center_to_tgt * radius_px * 0.5
	_apply_combat_weapon(s, p)
	if p.weapon_mode == TacticalPlan.WeaponMode.MISSILE:
		# 急转目标 + 导弹包络满足：直接打导弹更经济，不用绕进圆
		p.pursuit_pos = _missile_engage_pos(s)
		var spd := _missile_engage_speed(s)
		p.target_speed_kmh = spd[0]
		p.afterburner = spd[1]
		p.rationale = "侧翼急转：导弹（dist=%.0fm）" % s.dist_m
	else:
		p.target_speed_kmh = s.corner_speed_kmh
		p.afterburner = false
		# lag 几何下机炮强制不开火（等绕到尾后再射）
		p.allow_gun_fire = false
		p.rationale = "侧翼+敌急转：内切圆 lag, R=%.0fm" % radius_m
	_apply_target_altitude(s, p)
	return p

## 侧翼一般情况 → 前置拦截
static func lead_pursuit(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.LEAD_PURSUIT
	p.pursuit_pos = _gun_lead_point(s)
	_apply_combat_weapon(s, p)
	if p.weapon_mode == TacticalPlan.WeaponMode.MISSILE:
		p.pursuit_pos = _missile_engage_pos(s)
		var spd := _missile_engage_speed(s)
		p.target_speed_kmh = spd[0]
		p.afterburner = spd[1]
		p.rationale = "侧翼：导弹（dist=%.0fm）" % s.dist_m
	else:
		p.target_speed_kmh = s.corner_speed_kmh
		p.afterburner = (s.my_speed_ms * 3.6) < s.corner_speed_kmh - 40.0
		p.rationale = "侧翼前置：corner speed 拦截"
	_apply_squad_lateral_offset(s, p)
	_apply_target_altitude(s, p)
	return p

## 对头交汇 → 不减速穿过（保留 closing 不浪费高度）
static func merge_pass(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.MERGE_PASS
	p.pursuit_pos = _gun_lead_point(s)
	_apply_combat_weapon(s, p)
	if p.weapon_mode == TacticalPlan.WeaponMode.MISSILE:
		# 对头远距用 crank 提前侧出，让导弹自走 + 自己脱离
		p.pursuit_pos = _missile_engage_pos(s)
		var spd := _missile_engage_speed(s)
		p.target_speed_kmh = spd[0]
		p.afterburner = spd[1]
		p.rationale = "对头：导弹（dist=%.0fm）" % s.dist_m
	else:
		# 机炮对头：max×0.9 不减速冲过
		p.target_speed_kmh = s.max_speed_kmh * 0.9
		p.afterburner = false
		# 对头机炮命中难度高，加额外角度 + 距离守卫
		p.allow_gun_fire = s.dist_m < s.gun_range_m * 0.5 and s.aim_align > 0.95
		p.rationale = "对头交汇：max×0.9 穿过"
	_apply_target_altitude(s, p)
	return p

# ══════════════════════════════════════════════
#  脱离 / 重整
# ══════════════════════════════════════════════

## 已飞过目标 → 直线脱离
static func extend_recover(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.EXTEND_RECOVER
	# 沿当前 heading 飞 3km
	p.pursuit_pos = s.my_pos + s.my_fwd * 3000.0 * CombatUnit.PIXELS_PER_METER
	p.target_speed_kmh = s.max_speed_kmh
	p.afterburner = true
	p.weapon_mode = TacticalPlan.WeaponMode.NONE
	p.target_altitude_m = s.my_alt
	p.rationale = "已穿过目标：直线脱离重整"
	return p

## 对地攻击（strafing run）：高速直线掠过地面目标
## 与空战不同：地面不机动，不需要 corner speed 做小半径转弯。
## 真实战机对地都是 max + AB 减少 AAA 暴露时间。降速反而更危险。
## 武器：在 _apply_combat_weapon 的导弹包络内优先 AGM，否则机炮（charge 强制机炮）
static func ground_strafe(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.GROUND_STRAFE
	# pursuit_pos：地面目标静止，直接瞄目标即可（不需要 lead）
	p.pursuit_pos = s.tgt_pos
	_apply_combat_weapon(s, p)
	if p.weapon_mode == TacticalPlan.WeaponMode.MISSILE:
		# 导弹模式：稳定推进保持锁定
		p.target_speed_kmh = s.cruise_speed_kmh * 1.15
		p.afterburner = false
		p.rationale = "对地：导弹包络稳定推进"
	else:
		# 机炮 strafe：max + AB 高速掠过
		p.target_speed_kmh = s.max_speed_kmh * 0.95
		p.afterburner = (s.my_speed_ms * 3.6) < s.max_speed_kmh * 0.85
		p.rationale = "对地 strafe：max + AB 高速掠过"
	p.target_altitude_m = s.tgt_alt
	return p

## hdg 偏差 >90° → 大角度修正
static func wide_turn(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.WIDE_TURN
	p.pursuit_pos = s.tgt_pos
	p.target_speed_kmh = s.corner_speed_kmh
	p.afterburner = false
	p.weapon_mode = TacticalPlan.WeaponMode.NONE
	p.target_altitude_m = s.tgt_alt
	p.rationale = "hdg偏差>90°：corner speed 大转弯"
	return p

# ══════════════════════════════════════════════
#  武器选择（所有战斗 intent 共享）
# ══════════════════════════════════════════════

## 战斗武器决策。
## 输入：situation + 已经填好 pursuit_pos 的 plan（用于 lead 角度判定）
## 输出：写入 p.weapon_mode / p.allow_gun_fire / p.allow_missile_fire
##
## 规则：
## - 玩家强制锁机炮（charge / weapon_lock=FORCE_GUN）→ 仅机炮
## - 玩家强制锁导弹（weapon_lock=FORCE_MISSILE）→ 仅导弹
## - 默认（PREFER_MISSILE）→ 导弹包络内优先导弹，否则机炮兜底
##
## 调用方可在返回后微调 allow_gun_fire（lag/merge 等几何条件不允许开火时设回 false）
static func _apply_combat_weapon(s: Situation, p: TacticalPlan) -> void:
	var in_msl_envelope: bool = s.missiles > 0 \
			and s.dist_m > s.missile_min_range_m \
			and s.dist_m < s.missile_max_range_m * 1.1
	var in_gun_envelope: bool = s.dist_m > 60.0 and s.dist_m <= s.gun_range_m
	var gun_in_cone: bool = false
	if p.pursuit_pos != Vector2.INF:
		var hdg_to_lead: float = _heading_to(s.my_pos, p.pursuit_pos)
		var angle_diff_deg: float = rad_to_deg(absf(Situation._angle_diff(hdg_to_lead, s.my_heading)))
		gun_in_cone = angle_diff_deg <= FIRE_CONE_HALF_DEG

	# 玩家强制锁机炮（charge 或 UI PREFER_GUN）
	if s.charge_intent or s.weapon_lock == Situation.WEAPON_LOCK_FORCE_GUN:
		p.weapon_mode = TacticalPlan.WeaponMode.GUN
		p.allow_gun_fire = gun_in_cone and in_gun_envelope
		p.allow_missile_fire = false
		return

	# 玩家强制锁导弹
	if s.weapon_lock == Situation.WEAPON_LOCK_FORCE_MISSILE:
		p.weapon_mode = TacticalPlan.WeaponMode.MISSILE
		p.allow_gun_fire = false
		p.allow_missile_fire = in_msl_envelope
		return

	# 自动（默认 PREFER_MISSILE）
	if in_msl_envelope:
		p.weapon_mode = TacticalPlan.WeaponMode.MISSILE
		p.allow_gun_fire = false  # 不并发，专注导弹锁
		p.allow_missile_fire = true
	else:
		# 导弹包络外（弹药 0 / 距离不在 min~max）→ 机炮兜底
		p.weapon_mode = TacticalPlan.WeaponMode.GUN
		p.allow_gun_fire = gun_in_cone and in_gun_envelope
		p.allow_missile_fire = false

# ══════════════════════════════════════════════
#  辅助
# ══════════════════════════════════════════════

## 导弹交战速度策略（与 _missile_engage_pos 几何对齐的分段）
##
## 接近阶段（dist > optimal_far）：max + AB 全速闭合，争取早打
## 锁定建立段（crank_band < dist < optimal_far）：max × 0.9 + AB 维持高速度，锁好就开火
## crank 段（min_safe < dist < crank_band）：cruise × 1.2 / corner 减速保持包络，避免冲过 min_range
## 反向脱离（dist < min_safe）：max + AB 拉远脱离危险半径
##
## 返回 (target_speed_kmh, afterburner) 元组（用 Array 简单包装）
static func _missile_engage_speed(s: Situation) -> Array:
	var optimal_far: float = s.missile_max_range_m * 0.7
	var crank_band: float = s.missile_max_range_m * 0.4
	var min_safe: float = s.missile_min_range_m * 1.5
	var my_kmh: float = s.my_speed_ms * 3.6

	if s.dist_m > optimal_far:
		# 远距：max + AB 全速闭合
		return [s.max_speed_kmh, true]
	elif s.dist_m > crank_band:
		# 锁定建立段：仍然 max × 0.9，未达速度就开 AB
		var v: float = s.max_speed_kmh * 0.9
		return [v, my_kmh < v - 50.0]
	elif s.dist_m > min_safe:
		# crank 段：减速保持稳定锁，不开 AB
		return [maxf(s.cruise_speed_kmh * 1.2, s.corner_speed_kmh), false]
	else:
		# 太近：拉远 max + AB
		return [s.max_speed_kmh, true]

## 导弹交战瞄准点（crank geometry）
##
## 导弹交战的几何完全不同于机炮：
## - 机炮要求小火控锥（5°）→ 必须正对目标 → pursuit_pos = 前置点
## - 导弹用雷达锥（半角 ~30°）→ 可以适度 crank 维持锁定不冲过包络
##
## 关键约束：crank 角度必须 < radar_half_angle，否则目标飞出雷达锥 → 锁定丢失。
## 用 0.5 × radar_half 作为安全 crank 角度，保证目标稳定在锥内有缓冲。
##
## 决策矩阵（按 lock 状态 + 距离）：
## - 未锁定（任何距离）：LOS 直瞄，全力建立锁
## - 已锁 + 远（dist > max × 0.7）：LOS 直接闭合
## - 已锁 + 中距（min × 1.5 < dist < max × 0.7）：crank ~15° 保持锁 + 不冲过 min_range
## - 任何距离 < min × 1.5：朝反 LOS 脱离 3km，重整
static func _missile_engage_pos(s: Situation) -> Vector2:
	var optimal_far: float = s.missile_max_range_m * 0.7
	var min_safe: float = s.missile_min_range_m * 1.5

	# 太近：先脱离重整（无论锁定状态）
	if s.dist_m <= min_safe:
		var away: Vector2 = -s.to_target_dir
		return s.my_pos + away * 3000.0

	# 未锁定：保持 LOS 让雷达累积进度（防止 crank 把目标甩出锥）
	if not s.target_locked:
		return s.tgt_pos

	# 已锁定 + 远距：LOS 闭合
	if s.dist_m > optimal_far:
		return s.tgt_pos

	# 已锁定 + 包络内：crank radar_half × 0.5
	var crank_deg: float = s.radar_half_angle_deg * 0.5
	var crank_rad: float = deg_to_rad(crank_deg)
	var ccw: Vector2 = s.to_target_dir.rotated(crank_rad)
	var cw: Vector2 = s.to_target_dir.rotated(-crank_rad)
	var ccw_align: float = ccw.dot(s.my_fwd)
	var cw_align: float = cw.dot(s.my_fwd)
	var crank_dir: Vector2 = ccw if ccw_align > cw_align else cw
	return s.my_pos + crank_dir * 5000.0

## 作战高度：使用自身偏好（patrol_altitude / my_alt），clamp 到目标 ±2500m 内
## 满足导弹包线 ±5000m 高度差限制，留余量给 yoyo / extension 等过渡。
const COMBAT_ALT_TARGET_MARGIN := 2500.0
static func _combat_altitude(s: Situation) -> float:
	if not s.has_target:
		return s.combat_altitude_m
	return clampf(s.combat_altitude_m, s.tgt_alt - COMBAT_ALT_TARGET_MARGIN, s.tgt_alt + COMBAT_ALT_TARGET_MARGIN)

## 战斗 intent 的目标高度策略：
## - MISSILE 模式（远距导弹战）→ 保自身作战高度，保留高度优势
## - GUN 模式 / NONE（近距/对地）→ 匹配目标高度，否则机炮挂不上
## 调用方在 _apply_combat_weapon 之后调用本函数。
static func _apply_target_altitude(s: Situation, p: TacticalPlan) -> void:
	if p.weapon_mode == TacticalPlan.WeaponMode.MISSILE:
		p.target_altitude_m = _combat_altitude(s)
	else:
		p.target_altitude_m = s.tgt_alt

## 玩家高度偏好 → AltitudeTier 映射
## PREFER_CLIMB (0) → HIGH, PREFER_LOW (1) → LOW
## 仅 cruise / waypoint_move 用（无敌目标的状态）；战斗 intent 已经按 tgt_alt 匹配高度
static func _altitude_tier_from_preference(pref: int) -> int:
	if pref == 1:  # PREFER_LOW
		return CombatUnit.AltitudeTier.LOW
	return CombatUnit.AltitudeTier.HIGH  # 默认 PREFER_CLIMB

## 僚机 squad 横向偏移：协同攻击同一目标时按 squad_index 错开槽位，避免抢长机位置
##
## index 1 → 左 250m，index 2 → 右 250m，index 3 → 左 500m，index 4 → 右 500m
## 仅在 GUN 模式（pursuit_pos 是 gun_lead 点）生效；MISSILE 模式 crank 已自带侧向，不再加
##
## 调用方在已设好 pursuit_pos 后调用本函数微调
static func _apply_squad_lateral_offset(s: Situation, p: TacticalPlan) -> void:
	if not s.is_wingman or not s.following_leader_target:
		return
	if p.weapon_mode != TacticalPlan.WeaponMode.GUN:
		return
	if s.squad_index <= 0:
		return
	var slot_side: float = -1.0 if (s.squad_index % 2 == 1) else 1.0
	var slot_distance_m: float = 250.0 * ceili(float(s.squad_index) / 2.0)
	# 垂直于 LOS 的法向（攻击侧翼方向）
	var perp: Vector2 = Vector2(-s.to_target_dir.y, s.to_target_dir.x)
	var offset_px: float = slot_distance_m * CombatUnit.PIXELS_PER_METER
	p.pursuit_pos += perp * (slot_side * offset_px)
	p.rationale += " | wing#%d lat=%.0fm" % [s.squad_index, slot_side * slot_distance_m]

## 机炮前置射击点（两轮迭代）
static func _gun_lead_point(s: Situation) -> Vector2:
	if not s.has_target:
		return s.my_pos + s.my_fwd * 1000.0
	# 目标 fwd × 速度 × 飞行时间
	var bullet_speed_ms: float = 1050.0  # 默认机炮，未来从 params 读
	var bullet_speed_px: float = bullet_speed_ms * CombatUnit.PIXELS_PER_METER
	var t1: float = s.dist_px / maxf(bullet_speed_px, 100.0)
	var lead1: Vector2 = s.tgt_pos + s.tgt_fwd * (s.tgt_speed_ms * CombatUnit.PIXELS_PER_METER) * t1
	var t2: float = s.my_pos.distance_to(lead1) / maxf(bullet_speed_px, 100.0)
	return s.tgt_pos + s.tgt_fwd * (s.tgt_speed_ms * CombatUnit.PIXELS_PER_METER) * t2

## 从 from 看 to 的航向角（弧度，0=北顺时针）
static func _heading_to(from: Vector2, to: Vector2) -> float:
	var d: Vector2 = to - from
	return atan2(d.x, -d.y)
