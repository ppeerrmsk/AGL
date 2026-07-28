## 交战速度治理（Engagement Speed Governor）
##
## 解决的问题（playtest log 20260720_172222）：王牌中队全程 `ph=HI_BANK` + `g` 钉死在
## max_g，四架同姿态绕着玩家转圈，机头**一次都没指向过目标**（tp_brg 长期 ±90°）。
##
## ── 根因是几何，不是战术 ──
## 稳定盘旋半径  R = V² / (g·√(n²−1))
## F-47 角点速度 173 m/s → R = 255 m（能咬住）
## F-47 approach 速度 711 m/s → R = 4310 m（交战距离才 ~2000 m → 半径是距离的两倍）
## 半径大于距离时，机头指向目标在**几何上不可能**：AI 拉满 G 也只是绕着目标画圆。
## 任何上层战术（包夹 / 高度优势 / 角色分工）在这个状态下都无法执行 —— 必须先修几何。
##
## ── 治理方式 ──
## 反解"要咬住 dist 外的目标，速度最多是多少"：
##     R_max = dist × RADIUS_RATIO
##     V_cap = √(R_max · g · √(n²−1))
## 距离越近压得越狠（自然涌现"接近时高速、进入格斗后减速"），距离远则不限速。
##
## ── 两条硬约束 ──
## 1. **地板 = 角点速度**。绝不把飞机压到角点以下 —— 那会掉进"转弯转到失速、速度提不
##    起来"的死亡螺旋（用户明确禁止）。角点速度本身就是转弯性能最优点，压得更低毫无收益。
## 2. 只压 plan 的**速度主张**，不碰 G / bank / 几何。治理层不做战术决策。

class_name EngagementSpeedGovernor
extends RefCounted

const GRAVITY := 9.81

## 允许的盘旋半径占交战距离的比例。
## 0.5 = 半径最多为距离的一半 → 能明显转进目标内圈而不是绕着它画圆。
const RADIUS_RATIO := 0.5

## 治理生效的最远距离。更远时不限速 —— 远距接近本来就该开快，
## 且此时半径大也无所谓（还没进入指向阶段）。
const MAX_GOVERN_DIST_M := 6000.0

## 最小交战距离夹取：避免 dist→0 时把 cap 压到 0
const MIN_GOVERN_DIST_M := 300.0


## 反解速度上限（km/h）。max_g ≤ 1 时无法稳定盘旋，直接返回角点速度。
static func speed_cap_kmh(dist_m: float, max_g: float, corner_speed_kmh: float) -> float:
	if max_g <= 1.0:
		return corner_speed_kmh
	var d: float = clampf(dist_m, MIN_GOVERN_DIST_M, MAX_GOVERN_DIST_M)
	var r_max: float = d * RADIUS_RATIO
	# n 为过载倍数，向心加速度 = g·√(n²−1)
	var lateral_acc: float = GRAVITY * sqrt(max_g * max_g - 1.0)
	var v_ms: float = sqrt(r_max * lateral_acc)
	var v_kmh: float = v_ms * 3.6
	# 地板：角点速度。低于它既转不快也没能量，纯亏
	return maxf(v_kmh, corner_speed_kmh)


## 把治理应用到 plan。返回是否实际压制了速度（供日志/测试判定）。
## ⚠ 只在有目标且进入治理距离内才生效；不改 pursuit_pos / G / bank。
static func apply(s: Situation, p: TacticalPlan) -> bool:
	if not s.has_target or s.dist_m > MAX_GOVERN_DIST_M:
		return false
	var cap: float = speed_cap_kmh(s.dist_m, s.max_g, s.corner_speed_kmh)
	if p.target_speed_kmh <= cap:
		return false
	p.target_speed_kmh = cap
	# 超上限还开加力 = 直接抵消治理，必须一并关掉
	p.afterburner = false
	p.rationale += " | 速度治理：%.0f→%.0f km/h（%.0fm 内盘旋半径需 ≤%.0fm）" % [
		s.max_speed_kmh, cap, s.dist_m, s.dist_m * RADIUS_RATIO]
	return true


## 当前是否受治理约束（调用方决定要不要接线）。
## 目前**只对王牌中队生效** —— 该 tier 的高 cruise + 高 approach_speed_mult 组合是
## 本问题最严重的实例。是否推广到 Lancer 系（MiG-31 / F-104 同样高速）留待 playtest。
static func is_governed(ac: Node) -> bool:
	return AceTier.is_ace(ac)


# ══════════════════════════════════════════════
#  减速迟滞（执行精度失误，spec bosses/wraith-squadron §2.4）
# ══════════════════════════════════════════════

## 每次【新进入】治理区（上一帧没被压、这一帧要被压）时掷一次骰：
## DECEL_LAG_CHANCE 概率延迟 DECEL_LAG_MIN~MAX 秒才开始减速 —— 结果就是冲过头，
## 给玩家一个可利用的反咬窗口。
##
## ⚠ 这是**执行层的物理偏差，不是决策层放水**。他们的判断永远正确（该减速就是该减速），
##   只是手慢了半拍。禁止把随机放进战术决策（"这次不包夹了"）—— 那会让 BOSS 显得愚蠢
##   而不是显得像人。
const DECEL_LAG_CHANCE := 0.25
const DECEL_LAG_MIN := 0.6
const DECEL_LAG_MAX := 1.2

## 带迟滞的治理接线。返回是否实际压制了速度。
## 状态（计时器 / 上一帧是否受压）存在 Aircraft 上 —— 本模块保持无状态纯函数。
static func apply_with_lag(ac: Aircraft, s: Situation, p: TacticalPlan, delta: float) -> bool:
	var wants_cap: bool = s.has_target and s.dist_m <= MAX_GOVERN_DIST_M \
			and p.target_speed_kmh > speed_cap_kmh(s.dist_m, s.max_g, s.corner_speed_kmh)

	if not wants_cap:
		# 离开治理区：解除锁存，下次进入重新掷骰
		ac._ace_decel_lag_latched = false
		ac._ace_decel_lag_timer = 0.0
		return false

	# 新进入治理区 → 掷一次骰（本次进入内只掷一次，靠 latched 锁住）
	if not ac._ace_decel_lag_latched:
		ac._ace_decel_lag_latched = true
		if randf() < DECEL_LAG_CHANCE:
			ac._ace_decel_lag_timer = randf_range(DECEL_LAG_MIN, DECEL_LAG_MAX)
			EventLogger.log_event("ACE", ac._log_name(),
				"减速迟滞 %.2fs（执行失误 → 会冲过头）" % ac._ace_decel_lag_timer)
		else:
			ac._ace_decel_lag_timer = 0.0

	if ac._ace_decel_lag_timer > 0.0:
		ac._ace_decel_lag_timer -= delta
		return false   # 迟滞期间不压速 —— 保持高速冲进去

	return apply(s, p)
