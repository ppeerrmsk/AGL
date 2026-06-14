class_name FlightState
extends RefCounted

## 飞行状态快照 / 仿真载体
##
## 设计目的：让物理 tick（update_target_heading / update_bank / update_heading /
## update_speed）和预测线（predict_player_path）共享**同一份代码**，避免"预测器
## 与物理器各跑一份，长期 patch 不同步导致预测撕裂"的老问题。
##
## 用法：
## 1) 实物理 tick：from_aircraft(ac) → step_X(st, dt) → write_back(ac)
##    每个 update_X(ac, dt) 包裹器内部完成一轮，4 次/tick。
##    fan-in/fan-out 各 ~12 字段，60Hz × 22 架机 × 4 函数 ≈ 80k 字段读写/sec，可忽略。
## 2) 预测线：from_aircraft(ac, true) → 循环跑 step_X → 记录 position
##    is_prediction=true 时 step_X 内禁用 EventLogger 等副作用，结束不 write_back。
##
## 设计取舍：
## - 可变字段（snapshot 后被 step_X 演化）住在 FlightState 自己的成员里
## - 不变字段（params / evasion_modifiers / skill stacks / target_position 等）
##   通过 `st.ac.*` 直接读，不复制 → 内存不膨胀，prediction 期间也确保看到当前真值
## - target_position 是个例外：实物理 tick 里 update_target_heading 会把到达后的
##   target 清成 INF（写回 ac），所以这个字段进 state 走可变通道
## - is_prediction 标志门控所有副作用（EventLogger / 写回 ac / randf）

# ── 可变字段：snapshot 自 Aircraft，被 step_X 演化 ──
var position: Vector2
var heading: float
var bank_angle: float
var speed: float                    ## m/s
var vertical_speed: float           ## m/s
var altitude: float                 ## 米
var g_load: float                   ## G
var target_position: Vector2
var cached_target_heading: float
var proximity_damping: float
var committed_turn_sign: float
var bank_rate_rad_s: float
var turn_rate_filt: float           ## 低通滤波航向角速度（PD D 项输入）
var prev_tgt_heading_pd: float      ## 上一帧目标方位（LOS 角速度用）
var los_rate_filt: float            ## 低通滤波目标 LOS 角速度（PD 前馈项）
var prev_bank_for_rate: float
var evasion_override: bool
var is_stalled: bool                ## 步进期间也维护，避免预测时低速 bank 没被失速守卫拦
var stall_recovery_timer: float
## planner 决策字段（target_speed / AB）—— 实物理 tick 由外部 planner 写入 ac，
## 通过 from_aircraft snapshot 进 state；prediction 内部跑 inline planner 逐步更新这些
var target_speed_kmh: float
var is_afterburner: bool

# ── 冻结引用：通过 ac.* 读不变字段 ──
var ac: Aircraft

# ── 副作用门 ──
var is_prediction: bool = false

# ── 预测专用 helper 缓存：avoid 重复 effective_max_g / _dynamic_safe_margin /
# max_speed_at_altitude 这些跑 dictionary 查询的 helper（cloud/lock/bloodlust 等
# frozen 字段在预测期间不变）。NaN = 未缓存，step_X 走 lazy compute（实物理 tick 路径）
var cached_max_g: float = NAN
var cached_safe_margin: float = NAN
var cached_max_speed_alt_ms: float = NAN
## predict 用 inline planner 时需要的 frozen 输入：corner / max_speed (km/h)
var cached_corner_speed_kmh: float = NAN
var cached_max_speed_kmh: float = NAN


## 把 ac 状态填入当前实例（实物理 tick 用：复用一个共享实例避免 60Hz × N ac × 5 wrappers
## 的 RefCounted 分配开销 —— 实测降低 ac_phys.kine 从 1125µs 回到 ~115µs/frame）
func populate_from(a: Aircraft, prediction: bool = false) -> void:
	ac = a
	is_prediction = prediction
	position = a.global_position
	heading = a.heading
	bank_angle = a.bank_angle
	speed = a.speed
	vertical_speed = a.vertical_speed
	altitude = a.altitude
	g_load = a.g_load
	target_position = a.target_position
	cached_target_heading = a._cached_target_heading
	proximity_damping = a._proximity_damping
	committed_turn_sign = a._committed_turn_sign
	bank_rate_rad_s = a._bank_rate_rad_s
	turn_rate_filt = a._turn_rate_filt
	prev_tgt_heading_pd = a._prev_tgt_heading_pd
	los_rate_filt = a._los_rate_filt
	prev_bank_for_rate = a._prev_bank_for_rate
	evasion_override = a._evasion_override
	is_stalled = a.is_stalled
	stall_recovery_timer = a._stall_recovery_timer
	target_speed_kmh = a.target_speed_kmh
	is_afterburner = a.is_afterburner
	# 缓存字段必须每次 populate 时清掉（NaN）—— 实物理 tick 路径走 lazy compute；
	# predict 路径会在 from_aircraft 之后再单独填充缓存
	cached_max_g = NAN
	cached_safe_margin = NAN
	cached_max_speed_alt_ms = NAN
	cached_corner_speed_kmh = NAN
	cached_max_speed_kmh = NAN


## 创建新实例（predict 用：每次 cache refresh 调一次，频率低，分配可接受）
static func from_aircraft(a: Aircraft, prediction: bool = false) -> FlightState:
	var st := FlightState.new()
	st.populate_from(a, prediction)
	return st


## 把 target_heading / bank / heading / speed 类字段写回 Aircraft
## update_altitude 单独走 write_back_altitude，避免 step_speed wrapper 写脏 vertical_speed
func write_back() -> void:
	if is_prediction:
		return
	ac.global_position = position
	ac.heading = heading
	ac.bank_angle = bank_angle
	ac.speed = speed
	ac.target_position = target_position
	ac._cached_target_heading = cached_target_heading
	ac._proximity_damping = proximity_damping
	ac._committed_turn_sign = committed_turn_sign
	ac._bank_rate_rad_s = bank_rate_rad_s
	ac._turn_rate_filt = turn_rate_filt
	ac._prev_tgt_heading_pd = prev_tgt_heading_pd
	ac._los_rate_filt = los_rate_filt
	ac._prev_bank_for_rate = prev_bank_for_rate
	ac._evasion_override = evasion_override
	# target_speed_kmh / is_afterburner 不写回：实物理 tick 由外部 planner 在 _apply_tactical_plan
	# 直接写到 ac，update_speed 包裹器只是 read-through，不应该把 step_speed 内部使用值覆盖回去


## update_altitude 专用 write_back（vertical_speed/altitude）
func write_back_altitude() -> void:
	if is_prediction:
		return
	ac.vertical_speed = vertical_speed
	ac.altitude = altitude
