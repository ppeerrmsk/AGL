## 赫尔贝特轮机动模块（Herbst Maneuver / J-Turn）
## 利用推力矢量快速偏航 180°，追逐者变被追逐者。
## 作为子节点挂载到 Aircraft 上，BOSS 专用（可重复使用，有冷却）。
## AI 触发逻辑在 ai_controller.gd 中通过 aircraft.get_herbst() 查询。
## J-Turn 完成后自动进入反击窗口（counterattack_timer > 0），AI 暂停 bvr_only 逃跑行为。
class_name HerbstManeuver
extends Node

enum Phase { NONE, DECEL, TURN, ACCEL }

# ── 常量 ──
const DECEL_DURATION := 0.3         ## 减速阶段
const TURN_DURATION := 0.8          ## 180° 急转阶段
const ACCEL_DURATION := 0.5         ## 加速冲出阶段
const TOTAL_DURATION := 1.6         ## 总时长
const COOLDOWN := 15.0              ## 冷却时间（秒）
const DECEL_RATE := 300.0           ## 减速段强制减速 m/s²
const TURN_RATE := PI / TURN_DURATION  ## 180° / TURN_DURATION = 目标转弯速率 rad/s
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
	if not _aircraft.no_stamina:
		_aircraft._update_pilot_stamina(delta)

	match phase:
		Phase.DECEL:
			# 急刹车，降速到 corner speed（最佳转弯速度）
			var corner_spd := _aircraft._corner_speed_kmh() / 3.6 if _aircraft.has_method("_corner_speed_kmh") else _aircraft.params.stall_speed_base / 3.6 * 1.5
			_aircraft.speed = maxf(
				_aircraft.speed - DECEL_RATE * delta,
				corner_spd)
			visual_offset = clampf(_timer / DECEL_DURATION, 0.0, 0.5)
			if _timer >= DECEL_DURATION:
				_timer = 0.0
				phase = Phase.TURN
		Phase.TURN:
			# 180° 急转：直接修改 heading
			var turn_this_frame := TURN_RATE * delta * _turn_direction
			_aircraft.heading += turn_this_frame
			_aircraft.heading = fmod(_aircraft.heading + TAU, TAU)
			_aircraft.rotation = _aircraft.heading
			_turn_accumulated += absf(turn_this_frame)
			# 维持 corner speed
			var corner_spd := _aircraft._corner_speed_kmh() / 3.6 if _aircraft.has_method("_corner_speed_kmh") else _aircraft.params.stall_speed_base / 3.6 * 1.5
			_aircraft.speed = maxf(_aircraft.speed, corner_spd * 0.8)
			# 视觉偏移：转弯阶段最大
			visual_offset = clampf(0.5 + _timer / TURN_DURATION * 0.5, 0.5, 1.0)
			if _turn_accumulated >= PI or _timer >= TURN_DURATION:
				_timer = 0.0
				phase = Phase.ACCEL
		Phase.ACCEL:
			# 加力加速冲出
			visual_offset = 1.0 - clampf(_timer / ACCEL_DURATION, 0.0, 1.0)
			_aircraft.speed = lerpf(_aircraft.speed, _pre_speed * 1.1, delta * 3.0)
			_aircraft.is_afterburner = true
			# 设置目标位置为当前前方（让 AI 继续向前飞）
			var fwd := Vector2(sin(_aircraft.heading), -cos(_aircraft.heading))
			_aircraft.target_position = _aircraft.global_position + fwd * 2000.0
			if _timer >= ACCEL_DURATION:
				phase = Phase.NONE
				visual_offset = 0.0
				_aircraft.is_afterburner = false
				cooldown_remaining = COOLDOWN
				counterattack_timer = COUNTERATTACK_WINDOW  # 反击窗口激活
