## 眼镜蛇机动模块
## 作为子节点挂载到 Aircraft 上，任何飞机只需 add_child(CobraManeuver.new()) 即可获得该能力。
## AI 触发逻辑在 ai_controller.gd 中通过 aircraft.get_maneuver() 查询。
class_name CobraManeuver
extends Node

enum Phase { NONE, PITCH_UP, HOLD, RECOVER }

# ── 常量 ──
const PITCH_DURATION := 0.4        ## 抬头阶段
const HOLD_DURATION := 0.6         ## 保持阶段
const RECOVER_DURATION := 0.8      ## 恢复阶段
const TOTAL_DURATION := 1.8        ## 总时长（三阶段之和）
const POST_IMMUNITY := 1.5         ## 机动结束后额外无敌时间（秒）
const DECEL_RATE := 280.0          ## 强制减速 m/s²
const FLARE_COOLDOWN_AFTER := 5.0  ## 机动结束后热诱弹冷却（秒）
const AB_COOLDOWN_AFTER := 4.0     ## 机动结束后加力冷却（秒）—— 防止能量管理立刻把 AB 重新点亮

# ── 状态（供外部查询） ──
var phase: int = Phase.NONE
var is_used: bool = false           ## 已使用过（一次性）
var visual_offset: float = 0.0     ## 俯视压缩比例（0~1, 1=最大仰角）

## 是否处于激活状态（机动进行中）
var is_active: bool:
	get: return phase != Phase.NONE

# ── 内部状态 ──
var _aircraft: Aircraft = null
var _timer: float = 0.0
var _pre_speed: float = 0.0        ## 机动前速度 m/s

func _ready() -> void:
	_aircraft = get_parent() as Aircraft

## 触发眼镜蛇机动（每架飞机仅一次）
func activate() -> bool:
	if is_used or phase != Phase.NONE:
		return false
	if not _aircraft:
		return false
	is_used = true
	phase = Phase.PITCH_UP
	_timer = 0.0
	_pre_speed = _aircraft.speed
	# 设置飞机的免疫计时器
	_aircraft.missile_phase_timer = TOTAL_DURATION + POST_IMMUNITY
	_aircraft._lock_immunity_timer = TOTAL_DURATION + POST_IMMUNITY
	_aircraft.show_tactic_popup(tr("POPUP_COBRA"))
	return true

func _physics_process(delta: float) -> void:
	if phase == Phase.NONE:
		return
	if not _aircraft or _aircraft.is_destroyed:
		phase = Phase.NONE
		return
	_timer += delta

	# G 力负荷：抬头 6G → 保持 3G → 恢复 4G
	var cobra_g: float
	match phase:
		Phase.PITCH_UP: cobra_g = 6.0
		Phase.HOLD: cobra_g = 3.0
		_: cobra_g = 4.0
	_aircraft.g_load = cobra_g
	if not _aircraft.no_stamina:
		_aircraft._update_pilot_stamina(delta)

	match phase:
		Phase.PITCH_UP:
			# 急剧减速 + 视觉偏移从 0 → 1
			_aircraft.speed = maxf(
				_aircraft.speed - DECEL_RATE * delta,
				_aircraft.params.stall_speed_base / 3.6 * 0.5)
			visual_offset = clampf(_timer / PITCH_DURATION, 0.0, 1.0)
			if _timer >= PITCH_DURATION:
				_timer = 0.0
				phase = Phase.HOLD
		Phase.HOLD:
			# 速度钳制在失速附近，视觉保持最大仰角
			_aircraft.speed = maxf(
				_aircraft.speed,
				_aircraft.params.stall_speed_base / 3.6 * 0.4)
			visual_offset = 1.0
			if _timer >= HOLD_DURATION:
				_timer = 0.0
				phase = Phase.RECOVER
		Phase.RECOVER:
			# 视觉偏移从 1 → 0，速度通过 lerp 自然恢复（不强制开 AB —— cobra 本身是低速机动，
			# 强制 AB 既不符合机动语义，又会绕过 _set_afterburner 冷却造成 AB 视觉黏着）
			var t := clampf(_timer / RECOVER_DURATION, 0.0, 1.0)
			visual_offset = 1.0 - t
			_aircraft.speed = lerpf(_aircraft.speed, _pre_speed, delta * 2.0)
			if _timer >= RECOVER_DURATION:
				phase = Phase.NONE
				visual_offset = 0.0
				_aircraft.is_afterburner = false
				_aircraft._flare_cooldown = FLARE_COOLDOWN_AFTER
				# 加力冷却：阻止能量管理在 cobra 后的几秒内立刻重新点 AB
				# 玩家战术分支会在速度低时无条件 _set_afterburner(true)，
				# 没这段冷却 AB 视觉会"挂"在飞机后面好几秒
				_aircraft._ab_cooldown = AB_COOLDOWN_AFTER
