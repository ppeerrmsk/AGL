class_name LockWarning
extends RefCounted

## 锁定攻击警告系统（模块化）
## 任何敌方 CombatUnit 持有一个 LockWarning.State；
## 每帧由 CombatUnit.update_lock_line_state() 调用 LockWarning.update(...)
## 状态机本身只管"上升沿触发 + 计时器衰减"，policy（是否准备发射）由子类决定。
##
## ── 接入新机制（干扰 / ECM / 隐身等）的钩子 ──
## - LockWarning.suppress(state, seconds)：屏蔽 N 秒内的新警告（干扰弹、ECM 吊舱）
## - LockWarning.clear(state)：立即清空当前警告（隐身激活、被无效化的瞬间）
## - LockWarning.notify_fired(state)：发射瞬间叠加 flash（由武器路径调用）
## - 子类覆写 _lock_line_can_engage_player()：决定何为"准备发射"

# ── 计时常量（视觉手感参数集中在这里） ──
const FLASH_DURATION: float = 0.6   ## 发射瞬间高频闪烁时长
const MIN_DISPLAY: float = 2.5      ## 锁定上升沿触发的最少显示时长

# ── 视觉常量（draw 也归此模块统一管理） ──
const COLOR_RGB: Color = Color(1.0, 0.2, 0.18)
const PRE_LAUNCH_BLINK_HZ: float = 2.0
const FLASH_BLINK_HZ: float = 6.6
const PRE_LAUNCH_LINE_WIDTH: float = 1.4
const FLASH_LINE_WIDTH: float = 1.8
const PRE_LAUNCH_MARKER_RADIUS: float = 7.0
const FLASH_MARKER_RADIUS: float = 8.0


## 每个单位持有一份；存储锁定线运行时状态
class State extends RefCounted:
	var show_timer: float = 0.0      ## > 0 时线可见
	var flash_timer: float = 0.0     ## > 0 时叠加高频闪烁
	var was_armed: bool = false      ## 上一帧是否处于"准备发射"状态（用于上升沿）
	var suppress_timer: float = 0.0  ## > 0 时屏蔽新警告（干扰挂钩）


## 主每帧入口：上升沿触发 + 计时器衰减
## locked_by_player: 玩家 locked_by 中是否包含本单位
## can_engage_player: 子类 _lock_line_can_engage_player() 的返回值
## skip: 友方 / 已击毁 / 其它需要静音的状态（外部判定，传入即跳过）
static func update(state: State, locked_by_player: bool, can_engage_player: bool, skip: bool, delta: float) -> void:
	if state.show_timer > 0.0:
		state.show_timer -= delta
	if state.flash_timer > 0.0:
		state.flash_timer -= delta
	if state.suppress_timer > 0.0:
		state.suppress_timer -= delta
	if skip:
		state.was_armed = false
		return
	var armed: bool = locked_by_player and can_engage_player and state.suppress_timer <= 0.0
	if armed and not state.was_armed:
		state.show_timer = MIN_DISPLAY
	state.was_armed = armed


## 发射瞬间调用：闪烁警告 + 保证 show_timer 至少持续到 flash 结束
static func notify_fired(state: State) -> void:
	state.flash_timer = FLASH_DURATION
	if state.show_timer < FLASH_DURATION:
		state.show_timer = FLASH_DURATION


## 屏蔽 N 秒内的新警告（不影响当前 show_timer 衰减）
## 用法：玩家干扰弹释放 / ECM 模式开启时对附近敌方调用
static func suppress(state: State, seconds: float) -> void:
	if seconds > state.suppress_timer:
		state.suppress_timer = seconds
	state.was_armed = false


## 立即清空当前显示（用于隐身/瞬时丢锁等"硬切"语义）
static func clear(state: State) -> void:
	state.show_timer = 0.0
	state.flash_timer = 0.0
	state.was_armed = false


## 通用绘制：unit 的本地坐标系下从 (0,0) 画到玩家位置
## 不依赖具体单位类型，只需 unit 是 Node2D + 玩家是 Node2D
## skip_cloaked 让调用方决定隐身时是否仍然画（默认隐身→不画）
static func draw(unit: Node2D, player: Node2D, skip_cloaked: bool = true) -> void:
	if player == null or not is_instance_valid(player):
		return
	var unit_state: State = unit.lock_warning_state if "lock_warning_state" in unit else null
	if unit_state == null or unit_state.show_timer <= 0.0:
		return
	if skip_cloaked and unit is Aircraft and unit.is_cloaked:
		return
	var is_flash: bool = unit_state.flash_timer > 0.0
	var local_target: Vector2 = unit.to_local(player.global_position)
	var blink_hz: float = FLASH_BLINK_HZ if is_flash else PRE_LAUNCH_BLINK_HZ
	var blink_amp: float = 0.45 if is_flash else 0.35
	var blink_base: float = 0.55 if is_flash else 0.65
	var blink: float = blink_base + blink_amp * sin(Time.get_ticks_msec() * 0.001 * TAU * blink_hz)
	var line_color: Color = Color(COLOR_RGB.r, COLOR_RGB.g, COLOR_RGB.b, 0.55 * blink)
	var line_width: float = FLASH_LINE_WIDTH if is_flash else PRE_LAUNCH_LINE_WIDTH
	unit.draw_line(Vector2.ZERO, local_target, line_color, line_width, true)
	var d: float = FLASH_MARKER_RADIUS if is_flash else PRE_LAUNCH_MARKER_RADIUS
	unit.draw_line(local_target + Vector2(-d, 0), local_target + Vector2(d, 0), line_color, line_width)
	unit.draw_line(local_target + Vector2(0, -d), local_target + Vector2(0, d), line_color, line_width)
	unit.draw_arc(local_target, d, 0.0, TAU, 20, Color(line_color, 0.7 * blink), 1.2, true)
