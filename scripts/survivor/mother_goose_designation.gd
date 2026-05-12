## Mother Goose 指定猎杀（DESIGNATION）状态机
##
## 周期：COOLDOWN 180s → WARNING 3s（红线从 boss 伸到玩家身上，无效果） →
##       ACTIVE 15s（全场敌人锁定玩家 + UAV 蜂群切 hunter + 卡位包围） → 回 COOLDOWN
##
## 仅作为时间轴节拍器；行为副作用由 MotherGooseController._designation_tick 实施。
## 视觉 tether 由 MotherGooseDesignationOverlay 接管（脱离 boss transform）。
##
## 与 jam_shield 同生命周期 / 同 RefCounted 风格，方便统一管理。

class_name MotherGooseDesignation
extends RefCounted

enum State { COOLDOWN, WARNING, ACTIVE }

const COOLDOWN_DURATION: float = 180.0   ## 3 分钟一轮（首轮起算）
const WARNING_DURATION: float = 3.0      ## 红线伸出预警 / 玩家觉察
const ACTIVE_DURATION: float = 15.0      ## 全场猎杀窗口

var state: int = State.COOLDOWN
var state_timer: float = 0.0
var started: bool = false


func start() -> void:
	if started:
		return
	started = true
	state = State.COOLDOWN
	state_timer = 0.0


func is_active() -> bool:
	return state == State.ACTIVE


func is_warning() -> bool:
	return state == State.WARNING


## 是否需要绘制 tether（WARNING 细线 + ACTIVE 粗线）
func is_drawing() -> bool:
	return state == State.WARNING or state == State.ACTIVE


func update(delta: float) -> void:
	if not started:
		return
	state_timer += delta
	match state:
		State.COOLDOWN:
			if state_timer >= COOLDOWN_DURATION:
				_enter(State.WARNING)
		State.WARNING:
			if state_timer >= WARNING_DURATION:
				_enter(State.ACTIVE)
		State.ACTIVE:
			if state_timer >= ACTIVE_DURATION:
				_enter(State.COOLDOWN)


func _enter(s: int) -> void:
	state = s
	state_timer = 0.0
