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
const GUN_TARGET_AHEAD_MIN := 0.7      ## 开火要求目标本体 aim_align ≥ 此值（cos45.6°≈0.7）
									   ## 仅靠"前置点在锥内"会在横切高速目标时把机头前方的预测点判进锥，
									   ## 对着空域零碎喷子弹（用户反馈：面前没敌机也射击）。目标本体 >45° 离轴一律不开火。

# ── 对面攻击 pass（spec surface-attack-pass）几何常量 ──
const SURFACE_TURN_G := 7.0                 ## 估算最小转弯半径用的持续 G（与 planner SLOW_TARGET_TURN_G 同值）
const SURFACE_REATTACK_MULT := 1.5          ## dist < min_turn_r×此值 → too_close（转弯圆吃不下目标）
const SURFACE_REENTRY_MULT := 2.5           ## EGRESS 提交到 dist ≥ min_turn_r×此值 才折返（空间滞回带）
const SURFACE_REENTRY_FLOOR_M := 1500.0     ## ASSAULT 折返地板：拉出一段真正的 pass
const SURFACE_STANDOFF_INNER_M := 2200.0    ## STANDOFF 脱离/最小 AA 距离：只防贴近近距 AA，不从良好发射位后撤
                                            ## （病例2：命令打 6km 对舰不该 flee 到 9km——inner 是"别更近"，不是"退到远环"）
const SURFACE_INNER_FLOOR_M := 120.0        ## ASSAULT 穿越扫射内缘地板：防撞地
const SURFACE_EGRESS_OUT_PX := 3000.0       ## EGRESS 直线外推点距离（只给方向）
const AA_STANDOFF_SAFETY_MULT := 1.25       ## STANDOFF inner 相对目标对空火力半径的安全系数（spec aa-fire-awareness）
const AA_EGRESS_AB_ALIGN := 0.707           ## EGRESS 机头对准脱离方向 cos 阈值（45°内）→ AB 全速拉出
const AA_FPOLE_RING_PAD_M := 400.0          ## F-Pole 等待环 = inner + 此余量（米）

# ── 慢速空中目标 pass（spec slow-air-target-pass）──
# 与地面 pass 同一台相位机，只换三个包络常量。差异的物理来源：
# 目标在**空中且会缓慢移动**（要提前量），但**不还击对空火力**（inner 不必留 AA 安全圈）。
const SLOW_AIR_STANDOFF_INNER_M := 800.0    ## 慢速空中 STANDOFF 脱离环。远小于地面的 2200——
                                            ## 直升机没有对空火网，inner 的唯一约束是导弹 min_range。
                                            ## 2200 会让 RUN 在锁定攒满前就 EGRESS（雷达 3500m 起锁，
                                            ## 低空目标需 lock_time/0.7≈4.3s 连续照射 → 至少 1.3km 进场余量）。
const SLOW_AIR_ASSAULT_INNER_M := 250.0     ## 慢速空中 ASSAULT 穿越内缘：防空中相撞（地面版是 120m 防撞地）
## 折返距离 = inner + max(最小转弯半径×此值, 地板)。地面版（reentry≈1500m）对空中不够用：
## EGRESS 后机头背对目标，要先做 ~180° 掉头（corner 下 ~7.5s、横向偏移 2r），**再**留出
## 进场段把机头稳定到目标上。1500m 时掉头刚完成就已冲到目标脸上，全程卡在 SETUP 30° 门外
## 一路穿过去（无头 sim 实证：C 段 1161m→307m 全程 SETUP，off 卡 32°，从未进 RUN）。
const SLOW_AIR_REENTRY_TURN_MULT := 4.0
const SLOW_AIR_REENTRY_FLOOR_M := 1200.0
## RUN 退回 SETUP 的对准滞回（cos45°）。进 RUN 用 TAIL_AIM_THRESHOLD(30°)，退出放宽到 45°：
## 目标在动，纯 30° 单阈值会在边界上抖（无头 sim 实证：29.2°进 RUN → 30.0°退 SETUP →
## 34.5°… 相位每 1.5s 翻一次，锁定攒满了却始终没稳定几何去满足发射门）。
const SLOW_AIR_RUN_EXIT_ALIGN := 0.707

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
	# 速度选择：大角度转弯靠 corner speed，对准后冲 max×0.85（不浪费 AB）
	# ⚠ 改动（2026-05-07）：旧版在 hdiff=60° 处硬切换 target_speed_kmh 从 corner→max×0.85
	# （差距 ~700→1900 km/h，180% 跳变 + AB 瞬开），玩家手感上"过 60° 突然加力撒欢"，
	# 预测线也因此在转弯每次跨 60° 时整条重画一次。
	# 现在：在 [30°, 80°] 区间用 smoothstep 平滑 lerp，AB 条件改成"低于 target 的 90%"
	# 自然跟随 target_speed 一起平滑。详见 logs/combat_log_20260507_010656.txt 的
	# PRED_JUMP step=32 / 217 案例。
	var to_wp: Vector2 = waypoint - s.my_pos
	var hdg_to_wp: float = atan2(to_wp.x, -to_wp.y)
	var hdiff_deg: float = rad_to_deg(absf(Situation._angle_diff(hdg_to_wp, s.my_heading)))
	# t=0 全 corner speed（hdiff>=80°）；t=1 全 max×0.85（hdiff<=30°）；中间 smoothstep
	var t: float = clampf((80.0 - hdiff_deg) / 50.0, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)  # smoothstep
	var cruise_high: float = s.max_speed_kmh * 0.85
	p.target_speed_kmh = lerpf(s.corner_speed_kmh, cruise_high, t)
	# ── 僚机编队槽位追赶（2026-06-07）──
	# 僚机的 waypoint 是随长机实时移动的阵型槽位。上面纯航向的速度公式（为"玩家点击移动"设计）
	# 不含距离项：僚机一旦落后，会因"相对槽位航向差大"被锁在 corner 速度、即便对准也只有 0.85max，
	# 追不上开加力的长机 → 越追越远直至掉队（log 实测落后 2885px 仍只飞 699）。
	# 修：仅 is_wingman 时叠加"离槽位越远越猛追"——低端(转弯中)从 corner 抬到 (corner+max)/2，
	# 高端(对准)从 0.85max 抬到全速+AB；近距(≤400px)catchup=0 完全不变（紧密编队手感不动）。
	# 玩家(非 is_wingman)走原逻辑，点击移动手感不变。
	if s.is_wingman:
		var dist_to_wp: float = to_wp.length()
		var catchup: float = clampf((dist_to_wp - 400.0) / 1200.0, 0.0, 1.0)  # 400px→0 … 1600px→1 全力
		if catchup > 0.0:
			var lo: float = lerpf(s.corner_speed_kmh, (s.corner_speed_kmh + s.max_speed_kmh) * 0.5, catchup)
			var hi: float = lerpf(cruise_high, s.max_speed_kmh, catchup)
			p.target_speed_kmh = lerpf(lo, hi, t)
	# AB：当前速度低于 target 的 95% 就给 → 跟着 target_speed 平滑变化，无离散切换
	p.afterburner = (s.my_speed_ms * 3.6) < p.target_speed_kmh * 0.95
	p.rationale = "航点移动：hdiff=%d° t=%.2f tspd=%dkmh" % [int(hdiff_deg), t, int(p.target_speed_kmh)]
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

## 僚机翼侧切入：向"目标未来位置 + 侧向偏移"飞，截断目标行进路线（不抢长机尾后位）
##
## 几何思路：
##   future_pos = tgt_pos + tgt_fwd × (tgt_speed × CUTOFF_LEAD_SECONDS)
##   pursuit_pos = future_pos + perp_to_tgt × side × LATERAL_OFFSET
## side：-1 = 左翼（FLANK_LEFT），+1 = 右翼（FLANK_RIGHT）
##
## 速度：max × 0.95 + AB（要赶在目标前面，必须高速）
## 武器：复用 _apply_combat_weapon — 在导弹包络内仍走 crank（更高优先级）
## 距离 < gun_range × 1.2 时不调用本函数（planner 会回退 lead_pursuit）
const CUTOFF_LEAD_SECONDS := 5.0       ## 截击点提前量：目标 5s 后位置
const CUTOFF_LATERAL_M := 800.0        ## 翼侧偏移（米）
static func flank_cutoff(s: Situation, side: float) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.LEAD_PURSUIT  # 几何上属于前置拦截，复用 intent 不新增枚举
	# 目标未来位置
	var tgt_speed_px: float = s.tgt_speed_ms * CombatUnit.PIXELS_PER_METER
	var future_pos: Vector2 = s.tgt_pos + s.tgt_fwd * (tgt_speed_px * CUTOFF_LEAD_SECONDS)
	# 垂直于目标 heading 的法向（左手系：perp.x = -tgt_fwd.y, perp.y = tgt_fwd.x → 目标右侧）
	var perp: Vector2 = Vector2(-s.tgt_fwd.y, s.tgt_fwd.x)
	var lateral_px: float = CUTOFF_LATERAL_M * CombatUnit.PIXELS_PER_METER
	p.pursuit_pos = future_pos + perp * (side * lateral_px)
	_apply_combat_weapon(s, p)
	if p.weapon_mode == TacticalPlan.WeaponMode.MISSILE:
		# 导弹包络内：crank 几何更经济，让 _missile_engage_pos 接管
		p.pursuit_pos = _missile_engage_pos(s)
		var spd := _missile_engage_speed(s)
		p.target_speed_kmh = spd[0]
		p.afterburner = spd[1]
		p.rationale = "翼侧#%s：导弹 crank 接管 (dist=%.0fm)" % ["L" if side < 0 else "R", s.dist_m]
	else:
		p.target_speed_kmh = s.max_speed_kmh * 0.95
		p.afterburner = (s.my_speed_ms * 3.6) < s.max_speed_kmh * 0.85
		# 截击航线下机炮不开火（瞄具几何不对），让长机收人头；接近时 planner 会切回 LEAD_PURSUIT
		p.allow_gun_fire = false
		p.rationale = "翼侧#%s 截击：max×0.95+AB 抢目标 %.1fs 后位置" % [
			"L" if side < 0 else "R", CUTOFF_LEAD_SECONDS
		]
	_apply_target_altitude(s, p)
	return p

## 高位掩护：保持 +1500m 高度优势，走 lag 几何，作为 ARH 备份导弹平台
const HIGH_COVER_ALT_BUMP_M := 1500.0
static func high_cover(s: Situation) -> TacticalPlan:
	# 几何沿用 lag_pursuit（侧后内切），但高度抬升 1500m
	var p := lag_pursuit(s)
	p.target_altitude_m = s.tgt_alt + HIGH_COVER_ALT_BUMP_M
	# 拒绝机炮开火（高位掩护不下俯）
	p.allow_gun_fire = false
	p.rationale = "高位掩护：+%.0fm | %s" % [HIGH_COVER_ALT_BUMP_M, p.rationale]
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

## 对面攻击 pass 循环（spec surface-attack-pass）：对地面/舰船等静止目标做俯冲攻击跑
##   SETUP  ：未对准且有空间 → corner speed 转弯对准（关 AB）
##   RUN    ：已对准 → 俯冲/闭合开火（ASSAULT 贴地扫射 / STANDOFF 高位导弹）
##   EGRESS ：飞越或转不回来（太近） → 直线拉开到 reentry 再折返
## 姿态（attack_posture=AUTO 时按武器竞选结果推导）：
##   ASSAULT（机炮）  = 俯冲到 tgt_alt 穿越扫射，飞越后拉起折返
##   STANDOFF（导弹） = 高位进导弹包络就发射，够近前脱离，绝不俯冲进近距 AA
## 相位状态位住 Aircraft._strafe_pass_phase，经 Situation 读入 / plan 输出 / _apply_tactical_plan 回写。
static func ground_strafe(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.GROUND_STRAFE
	# pursuit 先临时瞄目标本体（供 _apply_combat_weapon 按真实目标几何算火控锥/开火门），
	# 相位机随后可能改写 pursuit（EGRESS 外推 / STANDOFF crank）——但开火门恒基于对准目标判定
	p.pursuit_pos = s.tgt_pos
	_apply_combat_weapon(s, p)

	# ── 姿态解析（AUTO=武器推导；command-wheel phase 4 可经 attack_posture 强制）──
	var is_standoff: bool
	match s.attack_posture:
		Situation.POSTURE_STANDOFF: is_standoff = true
		Situation.POSTURE_ASSAULT: is_standoff = false
		_: is_standoff = (p.weapon_mode == TacticalPlan.WeaponMode.MISSILE)
	var label: String = "STANDOFF" if is_standoff else "ASSAULT"

	# ── 包络解析（禁止烘焙，实时读 live params）──
	var gun_range_m: float = s.gun_range_m if s.gun_range_m > 0.0 else 1500.0
	var outer_m: float
	var inner_m: float
	if s.tgt_is_slow_air:
		# 慢速空中目标：同一相位机，换掉为地面 AA 火网设计的 inner（见常量注释）
		if is_standoff:
			outer_m = s.missile_max_range_m
			inner_m = maxf(SLOW_AIR_STANDOFF_INNER_M, s.missile_min_range_m * 1.5)
		else:
			outer_m = gun_range_m
			inner_m = minf(SLOW_AIR_ASSAULT_INNER_M, outer_m * 0.6)
	elif is_standoff:
		# STANDOFF「保持距离」= 维持"最小 AA 距离"（进到 ~2.2km 才脱离），而非"退到远环"。
		# 病例2 根因：早期 inner=missile_max×0.5（远环）→ 命令打环内目标（6km 对舰、弹程 16km→环 8km）
		# 时一进 RUN 就 dist≤inner → 立刻 EGRESS 背身外逃到 reentry(9km) → 20s 绕圈背飞。
		# 改为固定近距 inner：RUN 从当前距离一路压入开火到 2.2km 才 break（corner 硬 break 已解 coast-through）。
		outer_m = s.missile_max_range_m
		# AA 火圈感知（spec aa-fire-awareness §3.4）：inner 下限抬到目标对空火力半径 ×1.25。
		# CIWS 舰 2000→2500m（旧固定 2200 会被脱离 break 的惯性滑行擦进扫射圈磨血，
		# surface-attack-pass 验收实测 STANDOFF 最近逼到 1168m——已进 CIWS 近距反飞机圈）；
		# ZU-23 阵地 600×1.25=750 仍由 2200 地板兜底，行为不变。
		inner_m = clampf(maxf(SURFACE_STANDOFF_INNER_M, s.target_aa_range_m * AA_STANDOFF_SAFETY_MULT),
				s.missile_min_range_m * 1.5, s.missile_max_range_m * 0.6)
	else:
		outer_m = gun_range_m
		# C2 有效性守卫：防 outer<inner 反向死锁（ASSAULT 贴地穿越）
		inner_m = minf(SURFACE_INNER_FLOOR_M, outer_m * 0.6)

	# ── 最小转弯半径守卫（根治绕圈）+ 折返距离 ──
	var corner_ms: float = s.corner_speed_kmh / 3.6
	var min_turn_r: float = (corner_ms * corner_ms) / (9.81 * SURFACE_TURN_G) if corner_ms > 1.0 else 500.0
	var too_close: bool = s.dist_m < min_turn_r * SURFACE_REATTACK_MULT
	var reentry_m: float
	if s.tgt_is_slow_air:
		# 掉头 + 进场段都要留够（见 SLOW_AIR_REENTRY_* 注释）；两种姿态同式
		reentry_m = inner_m + maxf(min_turn_r * SLOW_AIR_REENTRY_TURN_MULT, SLOW_AIR_REENTRY_FLOOR_M)
	elif is_standoff:
		# 折返到 inner 外一点即可（再攻从 standoff 环外重新压入），夹在 [inner+500, outer×0.95]
		reentry_m = clampf(inner_m + maxf(min_turn_r * 2.0, 800.0), inner_m + 500.0, outer_m * 0.95)
	else:
		reentry_m = maxf(min_turn_r * SURFACE_REENTRY_MULT, SURFACE_REENTRY_FLOOR_M)

	# ── 相位机（读 prev → 算 next → 按 next 产出动作，同帧）──
	var aligned: bool = s.aim_align >= TAIL_AIM_THRESHOLD
	var phase: int = s.strafe_pass_phase
	match phase:
		TacticalPlan.SurfacePhase.SETUP:
			if aligned:
				phase = TacticalPlan.SurfacePhase.RUN
			elif too_close:
				phase = TacticalPlan.SurfacePhase.EGRESS
		TacticalPlan.SurfacePhase.RUN:
			# 退出阈值对慢速空目标放宽（见 SLOW_AIR_RUN_EXIT_ALIGN）；静止面目标维持原单阈值
			var run_exit_align: float = SLOW_AIR_RUN_EXIT_ALIGN if s.tgt_is_slow_air else TAIL_AIM_THRESHOLD
			if s.dist_m <= inner_m or ((not aligned) and too_close):
				phase = TacticalPlan.SurfacePhase.EGRESS
			elif s.aim_align < run_exit_align:
				phase = TacticalPlan.SurfacePhase.SETUP
		TacticalPlan.SurfacePhase.EGRESS:
			if s.dist_m >= reentry_m:
				phase = TacticalPlan.SurfacePhase.SETUP
		_:
			phase = TacticalPlan.SurfacePhase.SETUP
	# 中弹强转脱离（spec aa-fire-awareness §3.2）：警觉窗口内不做慢速 SETUP 对准 / RUN 压入——
	# 身处火力网时它们是最危险姿态。玩家（tactical preference 自治）不强转。
	if s.aa_fire_active and not s.is_tactical_preference_user:
		phase = TacticalPlan.SurfacePhase.EGRESS
	p.strafe_pass_phase = phase

	# ── 相位动作 ──
	match phase:
		TacticalPlan.SurfacePhase.EGRESS:
			# EGRESS 方向按姿态（都不沿机头——沿机头在头朝目标时会穿过目标，实测 min 1m）：
			# - ASSAULT：径向背离 -LOS。飞越后目标已在身后，径向≈机头，顺势拉开（俯冲 pass 已验证）。
			# - STANDOFF：侧向 beam break = (⟂LOS 朝机头偏侧 − 0.5·LOS) 归一。头朝目标触发 EGRESS 时
			#   180° 径向反转要 coast 冲进 AA（head-on 实测 min 421m）；beam 只需 ~90-120° 转向，coast 小又开距。
			# 纯函数无地图边界，靠 reentry 折返避免飞远。
			var los: Vector2 = s.to_target_dir
			var egress_dir: Vector2
			if is_standoff and los.length_squared() > 0.01:
				var cross: float = s.my_fwd.x * los.y - s.my_fwd.y * los.x
				var side: float = 1.0 if cross >= 0.0 else -1.0
				var tangent: Vector2 = Vector2(los.y, -los.x) * side  # ⟂LOS，朝机头当前偏的一侧（最小转向）
				egress_dir = (tangent - los * 0.5).normalized()       # 偏离目标 → 保证开距
			else:
				egress_dir = (-los) if los.length_squared() > 0.01 else s.my_fwd
			p.pursuit_pos = s.my_pos + egress_dir * SURFACE_EGRESS_OUT_PX
			# 加速脱离（spec aa-fire-awareness §3.3，敌我通用）：机头已转出（对准脱离方向
			# 45° 内）→ AB 全速拉出，不再慢速爬行泡在火网里。
			# 转向段维持 corner speed 硬 break（最大转率/最小半径），转出即松开。
			if s.my_fwd.dot(egress_dir) >= AA_EGRESS_AB_ALIGN:
				p.target_speed_kmh = s.max_speed_kmh
				p.afterburner = true
			else:
				p.target_speed_kmh = s.corner_speed_kmh
				p.afterburner = false
			_surface_altitude(s, p, is_standoff)
			p.rationale = "对面 EGRESS[%s]：硬 break 脱离折返 dist=%.0fm→reentry=%.0fm" % [label, s.dist_m, reentry_m]
		TacticalPlan.SurfacePhase.RUN:
			if is_standoff and s.fpole_hold:
				# F-Pole 等待（spec aa-fire-awareness §3.4）：弹已在飞（自己的弹在制导中，
				# 或团队在飞火力已足杀）→ 不再压入，环外切向绕行等命中；
				# 弹命中/失效后 fpole_hold 消失，恢复正常 RUN 压入。
				# 堵住"弹已出手还傻傻往里飞进 AA 圈"。
				var hold_radial: Vector2 = (s.my_pos - s.tgt_pos).normalized() if s.dist_px > 1.0 else -s.my_fwd
				var hold_tangent := Vector2(hold_radial.y, -hold_radial.x)
				var hold_r_px: float = (inner_m + AA_FPOLE_RING_PAD_M) * CombatUnit.PIXELS_PER_METER
				p.pursuit_pos = s.tgt_pos + hold_radial * hold_r_px + hold_tangent * (hold_r_px * 0.5)
				p.target_speed_kmh = s.cruise_speed_kmh
				p.afterburner = false
				_surface_altitude(s, p, true)
				p.rationale = "对面 RUN[STANDOFF/F-Pole]：弹在飞环外等待 dist=%.0fm ring=%.0fm" % [
						s.dist_m, inner_m + AA_FPOLE_RING_PAD_M]
			elif is_standoff and s.tgt_is_slow_air:
				# 慢速空中目标不 crank：crank 是为了对**会还击的**目标做 F-Pole 侧偏，
				# 直升机没有反击弹，侧偏只有代价——机头离轴 30~40° 会同时
				# ①拖慢/清空雷达锁积分（出锥 0.3s 清零）②撞上发射窗口的 off-axis 门。
				# 直接压向碰撞航路交会点 = 机头最快稳定在目标上 = 锁定最快攒满 = 最早开火。
				# 终端导弹跑瞄目标本体（纯追踪），不瞄交会点——与机炮跑瞄机炮解同理：
				# 发射门量的是"机头 vs 目标本体"的离轴角（≤ radar_half×0.55 ≈ 19°），
				# 而交会点带 asin(v_t/v_m) 的常驻前置偏置，close-in 段动态滞后还会放大到 30°+。
				# 结果是锁定攒满了却卡在发射门外，正是用户报的"锁定上了却不发射"
				# （无头 sim C 段实证：21.0s lock=3.30/3.00 满锁、nose=34.5° → 拒发，随后出锥清零）。
				# SETUP 段仍用交会点收敛；只有终端这一段切成纯追踪把离轴角压到 0。
				p.pursuit_pos = s.tgt_pos
				# 全程 corner speed（不加速到 cruise×1.15）：纯追踪要求的转率随距离按 1/R 发散
				# （LOS 率 = v·sin(off)/R），高速下转弯半径变大反而追不上——无头 sim 实证
				# 加速版在 RUN 里离轴角一路 29°→38°→54° 越追越偏，从没进过 19° 发射门。
				# corner speed 是最大转率点，纯追踪必收敛。慢速目标不还击，也没有"快点冲进去"的理由：
				# 关键路径是"把离轴角压进发射门"，不是"尽快抵达"。
				p.target_speed_kmh = s.corner_speed_kmh
				p.afterburner = false
				_surface_altitude(s, p, true)
				p.rationale = "慢速空目标 RUN[STANDOFF]：拦截航路压入攒锁 dist=%.0fm inner=%.0fm" % [
						s.dist_m, inner_m]
			elif is_standoff:
				p.pursuit_pos = _missile_engage_pos(s)  # crank 保锁（保持 standoff 距离）
				# 逼近脱离环时预减速到 corner：break 是硬 180，高速进 break → 转弯半径大 → coast 冲进 AA
				# （sim：cruise 速度 head-on break 从 2.2km coast 到 395m）。近环减速使 break 弧收紧。
				p.target_speed_kmh = s.corner_speed_kmh if s.dist_m < inner_m * 1.6 else s.cruise_speed_kmh * 1.15
				p.afterburner = false
				_surface_altitude(s, p, true)            # 保持 MID，不俯冲进 AA
				p.rationale = "对面 RUN[STANDOFF]：导弹包络推进 dist=%.0fm" % s.dist_m
			else:
				# 地面目标静止 → 不需提前量。慢速空目标的**终端机炮跑**要瞄机炮提前点，
				# 不是碰撞航路交会点：交会点按**本机**速度求解（前置角可达 asin(60/167)≈21°），
				# 而机炮解按**弹速** 1050m/s 求（前置角 ~3°）。拿交会点当机炮跑的引导点，
				# 机头会稳定停在离目标 ~10° 处掠过——雷达/导弹够用，但机炮 5° 火控锥永远不开门
				# （无头 sim 实证：B 段两趟 pass 分别掠到 174m / 254m，nose 恒 8.5~10°，0 次开火）。
				# SETUP 段仍用交会点收敛，只有终端这一段切到机炮解。
				p.pursuit_pos = _gun_lead_point(s) if s.tgt_is_slow_air else s.tgt_pos
				var run_kmh: float = clampf(s.cruise_speed_kmh * 1.4, s.cruise_speed_kmh, s.max_speed_kmh * 0.75)
				p.target_speed_kmh = run_kmh
				p.afterburner = (s.my_speed_ms * 3.6) < run_kmh * 0.95
				_surface_altitude(s, p, false)           # 俯冲到 tgt_alt（低空扫射）
				_apply_squad_lateral_offset(s, p)
				p.rationale = "对面 RUN[ASSAULT]：俯冲扫射 dist=%.0fm spd=%dkmh" % [s.dist_m, int(run_kmh)]
		_:  # SETUP
			p.pursuit_pos = _intercept_point(s) if s.tgt_is_slow_air else s.tgt_pos
			p.target_speed_kmh = s.corner_speed_kmh
			p.afterburner = false
			_surface_altitude(s, p, is_standoff)
			var off_deg: float = rad_to_deg(acos(clampf(s.aim_align, -1.0, 1.0)))
			p.rationale = "对面 SETUP[%s]：转弯对准 (off=%.0f° r=%.0fm) corner=%dkmh" % [
				label, off_deg, min_turn_r, int(s.corner_speed_kmh)]
	return p

## 对面 pass 的高度：玩家全程自治（走偏好 tier）；非玩家 STANDOFF 全程保持 MID（高位少受 AA）；
## ASSAULT 全程俯冲到目标高度并保持低空（贴地扫射——不在脱离时爬回 MID，否则高度churn 永远打不到地面）
static func _surface_altitude(s: Situation, p: TacticalPlan, is_standoff: bool) -> void:
	if s.is_tactical_preference_user:
		p.target_altitude_tier = _altitude_tier_from_preference(s.altitude_preference)
		return
	# 慢速空中目标：两种姿态都同高。MID 硬档是为躲地面 AA 而设，对直升机没有意义，
	# 反而制造高度差——雷达锥是水平锥，高度差会拉大真实离轴角，拖慢锁定。
	if s.tgt_is_slow_air:
		p.target_altitude_m = s.tgt_alt
	elif is_standoff:
		p.target_altitude_tier = CombatUnit.AltitudeTier.MID
	else:
		p.target_altitude_m = s.tgt_alt

## hdg 偏差 >90° → 大角度修正
static func wide_turn(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.WIDE_TURN
	p.pursuit_pos = s.tgt_pos
	p.target_speed_kmh = s.corner_speed_kmh
	p.afterburner = false
	p.weapon_mode = TacticalPlan.WeaponMode.NONE
	# 玩家高度走 preference；AI 沿用原来匹配目标的行为
	if s.is_tactical_preference_user:
		p.target_altitude_tier = _altitude_tier_from_preference(s.altitude_preference)
	else:
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
## 武器竞选单点入口（spec weapon-employment-doctrine §2.2）：planner 决策树（LINE_UP 判定）
## 与 _apply_combat_weapon 共用，保证同 tick 同结果。纯函数。
static func run_weapon_election(s: Situation) -> Dictionary:
	var cands: Array = []
	if s.railgun_band_max_m > 0.0:
		cands.append({"kind": "railgun", "band_min": s.railgun_band_min_m,
				"band_max": s.railgun_band_max_m, "ready": s.railgun_ready})
	cands.append({"kind": "missile", "band_min": s.missile_min_range_m,
			"band_max": s.missile_max_range_m * 1.1, "ready": s.missiles > 0})
	cands.append({"kind": "gun", "band_min": 60.0, "band_max": s.gun_range_m,
			"ready": s.ammo > 0})
	return WeaponSelector.select(cands, s.dist_m, s.primary_weapon_prev, s.primary_weapon_hold_s)


## LINE_UP —— 电磁炮射击纪律（spec weapon-employment-doctrine §3.2，阶段3）
## 平直对准目标提前点的直线航线：hitscan 无飞行时间 → 提前点 = 目标位置 + 微小外推；
## 每 tick 重算 → 充能期间持续追踪敌机航点（用户定稿 2a，小幅修正不触发甩头中断）；
## 恒巡航速稳定射击平台；坡度上限 30°（plan.bank_limit_deg → update_bank 消费）。
## 甩头中断充能的守卫在 RailgunEquipment 侧；射空可接受（定稿 2b，不抑制发射）。
const LINE_UP_EXTRAPOLATE_S := 0.4    ## 提前点外推秒数（微小：跟住目标航点趋势）
const LINE_UP_BANK_LIMIT_DEG := 30.0  ## 充能平台坡度上限
static func line_up(s: Situation) -> TacticalPlan:
	var p := TacticalPlan.new()
	p.intent = TacticalPlan.Intent.LINE_UP
	var aim_pos: Vector2 = s.tgt_pos \
			+ s.tgt_fwd * (s.tgt_speed_ms * CombatUnit.PIXELS_PER_METER) * LINE_UP_EXTRAPOLATE_S
	var dir: Vector2 = aim_pos - s.my_pos
	if dir.length_squared() < 1.0:
		dir = s.my_fwd
	# 远点直线航线：pursuit 放提前点方向远处 → heading_diff 恒小量，PD 自然平直跟踪
	p.pursuit_pos = s.my_pos + dir.normalized() * 5000.0
	p.target_speed_kmh = s.cruise_speed_kmh
	p.afterburner = false
	p.bank_limit_deg = LINE_UP_BANK_LIMIT_DEG
	p.rationale = "LINE_UP：电磁炮直线对准（dist=%dm）" % int(s.dist_m)
	_apply_combat_weapon(s, p)
	return p


static func _apply_combat_weapon(s: Situation, p: TacticalPlan) -> void:
	var in_msl_envelope: bool = s.missiles > 0 \
			and s.dist_m > s.missile_min_range_m \
			and s.dist_m < s.missile_max_range_m * 1.1
	var in_gun_envelope: bool = s.dist_m > 60.0 and s.dist_m <= s.gun_range_m
	var gun_in_cone: bool = false
	if p.pursuit_pos != Vector2.INF:
		var hdg_to_lead: float = _heading_to(s.my_pos, p.pursuit_pos)
		var angle_diff_deg: float = rad_to_deg(absf(Situation._angle_diff(hdg_to_lead, s.my_heading)))
		# 前置点在火控锥内 + 目标本体也大致在机头前方（aim_align）。两者都满足才允许开火，
		# 杜绝"前置点扫进锥、目标却在侧后"的对空放空（见 GUN_TARGET_AHEAD_MIN 注释）。
		gun_in_cone = angle_diff_deg <= FIRE_CONE_HALF_DEG and s.aim_align >= GUN_TARGET_AHEAD_MIN

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

	# ── 自动：武器竞选（spec weapon-employment-doctrine §2.2，2026-07-04 用户定稿）──
	# 候选距离带来自 Situation 的 live params 注入（升级即时生效）；重叠区命中率优先
	# （railgun 必中 100 > missile 70 > gun 50）；1.5s 滞回防带边界抖动换武器。
	# 火箭弹暂不参与竞选（保持机会射击，阶段 3 评估）；副导弹/激光为被动武器不竞选。
	var sel := run_weapon_election(s)
	p.primary_weapon = String(sel["kind"])
	match p.primary_weapon:
		"missile":
			p.weapon_mode = TacticalPlan.WeaponMode.MISSILE
			p.allow_gun_fire = false  # 不并发，专注导弹锁
			p.allow_missile_fire = in_msl_envelope
		"gun":
			p.weapon_mode = TacticalPlan.WeaponMode.GUN
			p.allow_gun_fire = gun_in_cone and in_gun_envelope
			p.allow_missile_fire = false
		"railgun":
			# 阶段2 过渡：LINE_UP intent 在阶段3 落地。先按导弹纪律 crank 保锁——
			# 电磁炮射程 = 本机雷达距离，crank 维持锁定的几何对它同样有效；发射时机
			# 暂仍由 RailgunEquipment 状态机自理。导弹包络内允许并射（现状不变）。
			p.weapon_mode = TacticalPlan.WeaponMode.MISSILE
			p.allow_gun_fire = false
			p.allow_missile_fire = in_msl_envelope
		_:
			# 无带内候选：wait_doctrine 区分两种情况——
			# "gun" = 有弹的机炮机在带外逼近 → 保持机炮几何收距离（CLOSE_TAIL 语义）；
			# 其余（含 railgun 逼近 = crank 保锁同效）= 导弹纪律 crank 等待（用户定稿 4b）
			# ——不再"机炮硬兜底"；各武器由自己的弹药/CD 门自然静默
			if String(sel.get("wait_doctrine", "missile")) == "gun":
				p.weapon_mode = TacticalPlan.WeaponMode.GUN
				p.allow_gun_fire = gun_in_cone and in_gun_envelope  # 带外恒 false，纯逼近
			else:
				p.weapon_mode = TacticalPlan.WeaponMode.MISSILE
				p.allow_gun_fire = false
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
	# 旧实现按"哪侧更对齐机头"离散选 crank 侧（ccw/cw）。目标接近正前方时两侧 align 几乎相等，
	# 单帧噪声就让 crank 侧翻号 → 追踪点在机身两侧 ±5000px(=10000m) 瞬移 → 平滑 bank 控制器
	# 忠实追摆 → 长机原地大坡摇摆打转（SEAM-013）。
	# 改为**连续 clamp**（无离散选侧）：瞄准航向 = LOS 朝机头当前方向偏移，封顶 crank_deg。
	#   - 机头正对目标(nose_off=0) → 瞄 LOS，无 crank、无翻号；
	#   - 机头小偏(|nose_off|<crank_deg) → 瞄机头当前方向(顺势直飞)，目标在锥内缓慢漂移；
	#   - 机头大偏(|nose_off|>crank_deg) → crank 封顶在 LOS 偏 crank_deg 处（朝机头侧，维持锁不过冲）。
	# nose_off 过零时 aim_hdg 连续穿过 LOS，无跳变 → 根除抖动。语义不变（朝机头侧 crank、封顶
	# crank_deg、维持锁），仅把"满 crank 离散选侧"换成"0~crank_deg 连续偏置"。
	var crank_deg: float = s.radar_half_angle_deg * 0.5
	var crank_rad: float = deg_to_rad(crank_deg)
	var los_hdg: float = _heading_to(s.my_pos, s.tgt_pos)
	var nose_off: float = Situation._angle_diff(s.my_heading, los_hdg)  # 机头相对 LOS 的有符号偏角
	var aim_hdg: float = los_hdg + clampf(nose_off, -crank_rad, crank_rad)
	var aim_dir: Vector2 = Vector2(sin(aim_hdg), -cos(aim_hdg))
	return s.my_pos + aim_dir * 5000.0

## 战斗 intent 的目标高度策略：
## - 玩家（use_tactical_preference）→ 永不匹配目标高度，始终走 altitude_preference 的 tier
##   原因：GUN 模式拉低跟敌后，combat_altitude_m 每帧取 ac.altitude → 切回 MISSILE 时也"保持当前低空"，
##   PREFER_CLIMB 失效，且高度切换的能量代价让飞机往远处飘。统一让玩家高度自治
## - AI MISSILE 模式 → 保自身作战高度，不向目标高度靠拢（高位发射 → 射程更远）
## - AI GUN 模式 / NONE（近距/对地）→ 匹配目标高度，否则机炮锥挂不上
## 调用方在 _apply_combat_weapon 之后调用本函数。
static func _apply_target_altitude(s: Situation, p: TacticalPlan) -> void:
	if s.is_tactical_preference_user:
		# 玩家：tier 走偏好（PREFER_CLIMB → HIGH / PREFER_LOW → LOW），target_altitude_m 留 -1 由 tier 主导
		p.target_altitude_tier = _altitude_tier_from_preference(s.altitude_preference)
		return
	if p.weapon_mode == TacticalPlan.WeaponMode.MISSILE:
		p.target_altitude_m = s.combat_altitude_m
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
## 碰撞航路拦截点：解"我以自身速度直飞 / 目标匀速直飞"的交会点。
##
## 为什么不能用 _gun_lead_point 做机动引导：那个函数按**子弹**飞行时间算提前量（~1000 m/s 量级），
## 对 1.6km 外的直升机只有 ~3° 偏置 ≈ 纯追踪。而纯追踪对横切目标存在**常驻滞后角**——
## 转弯率恰好被方位变化率吃光，机头稳定停在某个偏差上永不收敛。
## 实测（test_slow_air_pass C 段）：nose 从 1639m 一路压到 498m 全程卡死 35.0°，
## 而进 RUN 的门槛是 30°（TAIL_AIM_THRESHOLD）→ 差 5° 永远进不去 → 白飞一趟再 EGRESS。
##
## 解 |tgt_pos + tgt_v·t − my_pos| = my_speed·t 的最小正根 t，返回 t 时刻的目标位置。
## 追不上（目标更快）或退化时回落到目标本体，行为等同旧的纯追踪。
static func _intercept_point(s: Situation) -> Vector2:
	if not s.has_target:
		return s.my_pos + s.my_fwd * 1000.0
	var my_speed_px: float = s.my_speed_ms * CombatUnit.PIXELS_PER_METER
	if my_speed_px < 1.0:
		return s.tgt_pos
	var r: Vector2 = s.tgt_pos - s.my_pos
	var tv: Vector2 = s.tgt_fwd * (s.tgt_speed_ms * CombatUnit.PIXELS_PER_METER)
	var a: float = tv.length_squared() - my_speed_px * my_speed_px
	var b: float = 2.0 * r.dot(tv)
	var c: float = r.length_squared()
	var t: float = -1.0
	if absf(a) < 0.001:
		# 同速：退化成一次方程
		if absf(b) > 0.001:
			t = -c / b
	else:
		var disc: float = b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq: float = sqrt(disc)
			# 取两根中最小的正根 = 最早交会
			var t1: float = (-b + sq) / (2.0 * a)
			var t2: float = (-b - sq) / (2.0 * a)
			if t1 > 0.0 and t2 > 0.0:
				t = minf(t1, t2)
			else:
				t = maxf(t1, t2)
	if t <= 0.0 or not is_finite(t):
		return s.tgt_pos   # 无解（追不上）→ 纯追踪
	return s.tgt_pos + tv * t


static func _gun_lead_point(s: Situation) -> Vector2:
	if not s.has_target:
		return s.my_pos + s.my_fwd * 1000.0
	# 目标 fwd × 速度 × 飞行时间
	# 从 params 读实际初速（Situation 注入）。曾硬编码 1050 —— 与 aircraft.gd 扳机侧用
	# params.gun.muzzle_velocity 算的 lead 不一致，导致挂非 1050 初速机炮的飞机
	# 机头永远瞄在扳机认可点旁边（spec ace-squadron-tier 阶段 1）
	var bullet_speed_ms: float = s.gun_muzzle_mps if s.gun_muzzle_mps > 0.0 else 1050.0
	var bullet_speed_px: float = bullet_speed_ms * CombatUnit.PIXELS_PER_METER
	var t1: float = s.dist_px / maxf(bullet_speed_px, 100.0)
	var lead1: Vector2 = s.tgt_pos + s.tgt_fwd * (s.tgt_speed_ms * CombatUnit.PIXELS_PER_METER) * t1
	var t2: float = s.my_pos.distance_to(lead1) / maxf(bullet_speed_px, 100.0)
	return s.tgt_pos + s.tgt_fwd * (s.tgt_speed_ms * CombatUnit.PIXELS_PER_METER) * t2

## 从 from 看 to 的航向角（弧度，0=北顺时针）
static func _heading_to(from: Vector2, to: Vector2) -> float:
	var d: Vector2 = to - from
	return atan2(d.x, -d.y)
