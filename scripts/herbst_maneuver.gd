## 赫尔贝特轮机动模块（Herbst Maneuver / J-Turn）
## 利用推力矢量快速偏航 180°，追逐者变被追逐者。
## 作为子节点挂载到 Aircraft 上，BOSS 专用（可重复使用，有冷却）。
## AI 触发逻辑在 ai_controller.gd 中通过 aircraft.get_herbst() 查询。
## J-Turn 完成后自动进入反击窗口（counterattack_timer > 0），AI 暂停 bvr_only 逃跑行为。
class_name HerbstManeuver
extends Node

enum Phase { NONE, DECEL, TURN, ACCEL }

# ── 常量 ──
## 节奏：真实 F/A-18 post-stall J-Turn 全程 ≥3s —— 先猛刹到近失速，
## 用推力矢量低速偏航 180°，然后低速重新加速冲出。玩家要看得到三个阶段。
const DECEL_DURATION := 0.5         ## 减速阶段：迅速猛刹到近失速（原 1.0s 太慢，被玩家白嫖）
## TURN 阶段持续时间 —— 2026-04-21 (12) 从 1.0s 拉长到 1.8s
## 原因：1.0s 对应 180°/秒偏航 = 每帧 3° 递增，超出 Godot CanvasItem 在旋转下的
## 像素/抗锯齿对齐容限，导致画在飞机 _draw() 里的所有东西（图标多边形边、标签框
## Rect 边界、"J-TURN" popup 文字光栅）每帧子像素对齐不同，人眼感知为"剧烈抖动"。
## 拉长到 1.8s → 100°/秒 = 1.67°/帧，低于感知阈值，视觉上平滑。代价是 J-Turn
## 不再那么快（之前 (8) 缩短是因为太慢被白嫖，现在的 1.8s 配合 (7) 的导弹+机炮
## 免疫窗口，既能看清动作又不会被白嫖）。
## 详见 docs/changelogs/player-ai-log.md 2026-04-21 (12)
const TURN_DURATION := 1.8          ## 180° 低速偏航（100°/秒，感知阈值内）
const ACCEL_DURATION := 0.6         ## 加速冲出
const TOTAL_DURATION := 2.9         ## 总时长（DECEL 0.5 + TURN 1.8 + ACCEL 0.6）
const COOLDOWN := 15.0              ## 冷却时间（秒）
const DECEL_RATE := 1400.0          ## 减速段 m/s²（DECEL 缩到 0.5s 需要更猛的刹车才能到低速）
const TURN_RATE := PI / TURN_DURATION  ## 180° / TURN_DURATION = 目标转弯速率 rad/s
const TURN_SPEED_FACTOR := 1.15     ## TURN 阶段速度 = 失速速度 × 此值（近失速低速偏航）
const ACCEL_SPEED_FACTOR := 1.4     ## ACCEL 阶段起始速度上限 = 失速速度 × 此值
const POST_IMMUNITY := 0.3          ## 机动结束后额外锁定免疫时间（秒）— 短，BOSS 不应长时间无法被锁
const COUNTERATTACK_WINDOW := 5.0   ## J-Turn 后反击窗口（秒）— AI 暂停 bvr_only 逃跑

# ── 状态（供外部查询） ──
var phase: int = Phase.NONE
var visual_offset: float = 0.0      ## 俯视压缩比例（0~1, 1=最大侧偏）
var cooldown_remaining: float = 0.0 ## 冷却剩余时间
var counterattack_timer: float = 0.0 ## 反击窗口倒计时（> 0 时 AI 不逃跑，主动攻击）

## 是否处于激活状态（机动进行中）
var is_active: bool:
	get: return phase != Phase.NONE

## 是否可以激活（冷却完毕且不在机动中）
var can_activate: bool:
	get: return phase == Phase.NONE and cooldown_remaining <= 0.0

# ── 内部状态 ──
var _aircraft: Aircraft = null
var _timer: float = 0.0
var _pre_speed: float = 0.0         ## 机动前速度 m/s
var _turn_accumulated: float = 0.0  ## 已转过的角度（弧度）
var _turn_direction: float = 1.0    ## 转弯方向（1=右, -1=左）

func _ready() -> void:
	_aircraft = get_parent() as Aircraft

## 触发赫尔贝特轮（可重复使用，有冷却）
func activate(turn_dir: float = 0.0) -> bool:
	if not can_activate:
		return false
	if not _aircraft:
		return false
	phase = Phase.DECEL
	_timer = 0.0
	_pre_speed = _aircraft.speed
	_turn_accumulated = 0.0
	# 转弯方向：传入 0 则随机
	if turn_dir != 0.0:
		_turn_direction = signf(turn_dir)
	else:
		_turn_direction = 1.0 if randf() > 0.5 else -1.0
	# 设置飞机免疫计时器
	_aircraft.missile_phase_timer = TOTAL_DURATION + POST_IMMUNITY
	_aircraft._lock_immunity_timer = TOTAL_DURATION + POST_IMMUNITY
	_aircraft.show_tactic_popup("J-TURN")
	return true

func _physics_process(delta: float) -> void:
	# 冷却倒计时（无论是否在机动中都走）
	if cooldown_remaining > 0.0:
		cooldown_remaining = maxf(cooldown_remaining - delta, 0.0)
	# 反击窗口倒计时
	if counterattack_timer > 0.0:
		counterattack_timer = maxf(counterattack_timer - delta, 0.0)

	if phase == Phase.NONE:
		return
	if not _aircraft or _aircraft.is_destroyed:
		phase = Phase.NONE
		return
	_timer += delta

	# G 力负荷：减速 3G → 急转 8G → 加速 4G
	var herbst_g: float
	match phase:
		Phase.DECEL: herbst_g = 3.0
		Phase.TURN: herbst_g = 8.0
		_: herbst_g = 4.0
	_aircraft.g_load = herbst_g

	# 基准失速速度（不受当前 g_load 影响，稳定参考值）
	var stall_base_ms: float = (_aircraft.params.stall_speed_base if _aircraft.params else 220.0) / 3.6
	var turn_target_ms: float = stall_base_ms * TURN_SPEED_FACTOR
	var accel_ceiling_ms: float = stall_base_ms * ACCEL_SPEED_FACTOR

	match phase:
		Phase.DECEL:
			# 猛刹车：强制降速到 turn_target（接近失速），同时关加力
			_aircraft.is_afterburner = false
			_aircraft.speed = maxf(
				_aircraft.speed - DECEL_RATE * delta,
				turn_target_ms)
			# 同步意图字段保持一致（update_speed 已被 maneuver_overrides_speed 守卫让位，
			# 此写仅供 HUD/预测线读到正确意图，不再是对抗 update_speed 的自卫手段）
			_aircraft.target_speed_kmh = turn_target_ms * 3.6
			# 前方虚拟目标，避免别处读到过期 target_position
			var fwd_d := Vector2(sin(_aircraft.heading), -cos(_aircraft.heading))
			_aircraft.target_position = _aircraft.global_position + fwd_d * 2000.0
			visual_offset = clampf(_timer / DECEL_DURATION * 0.5, 0.0, 0.5)
			if _timer >= DECEL_DURATION:
				_timer = 0.0
				phase = Phase.TURN
		Phase.TURN:
			# 低速偏航：heading 由模块每帧硬转，速度压在近失速
			var turn_this_frame := TURN_RATE * delta * _turn_direction
			_aircraft.heading += turn_this_frame
			_aircraft.heading = fmod(_aircraft.heading + TAU, TAU)
			_aircraft.rotation = _aircraft.heading
			_turn_accumulated += absf(turn_this_frame)
			_aircraft.is_afterburner = false
			# 严格压在 turn_target（update_speed 已让位，本模块是 DECEL/TURN 期间速度唯一写者）
			_aircraft.speed = turn_target_ms
			_aircraft.target_speed_kmh = turn_target_ms * 3.6
			var fwd_t := Vector2(sin(_aircraft.heading), -cos(_aircraft.heading))
			_aircraft.target_position = _aircraft.global_position + fwd_t * 2000.0
			visual_offset = clampf(0.5 + _timer / TURN_DURATION * 0.5, 0.5, 1.0)
			if _turn_accumulated >= PI or _timer >= TURN_DURATION:
				_timer = 0.0
				phase = Phase.ACCEL
		Phase.ACCEL:
			# 加力冲出：开加力，让 Aircraft._update_speed 自然拉回巡航（燃油守卫防零油白嫖）
			_aircraft.is_afterburner = _aircraft.fuel > 0.0
			# 起始 tick 把速度钳在 accel_ceiling（避免一帧暴起）
			if _timer < 0.05:
				_aircraft.speed = minf(_aircraft.speed, accel_ceiling_ms)
			_aircraft.target_speed_kmh = _aircraft.params.cruise_speed if _aircraft.params else 1600.0
			visual_offset = 1.0 - clampf(_timer / ACCEL_DURATION, 0.0, 1.0)
			var fwd := Vector2(sin(_aircraft.heading), -cos(_aircraft.heading))
			_aircraft.target_position = _aircraft.global_position + fwd * 2000.0
			if _timer >= ACCEL_DURATION:
				phase = Phase.NONE
				visual_offset = 0.0
				cooldown_remaining = COOLDOWN
				counterattack_timer = COUNTERATTACK_WINDOW  # 反击窗口激活
				# 722 签名技能：特殊机动完成事件（急停机动 Su-27 / 落叶飘 Su-35）
				SkillHooks.on_special_maneuver_done(_aircraft)
