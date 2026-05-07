## Mother Goose 周期性干扰护盾
##
## 状态机周期 = 60s：
##   COOLDOWN 40s → WARNING 4s（HUD 红色警示，无效果）→ EXPANDING 8s（半径 400→2500 px）→
##   SUSTAIN 8s（满范围 R=2500）→ 回 COOLDOWN
##
## 启动效果（WARNING 之后）：场内玩家方 Aircraft 速度 ×0.6 + status_jam_active=true（武器禁射）
## 视觉：在 boss 主体 _draw 里调用 draw(canvas_item)，画淡红色透明圆 + 边缘环
##
## 不挂在 _process 里跑 —— 由 MotherGooseUnit 的 _physics_process 每帧调 update(delta)
## 与 commander_aura 同思路：仅 active 期间 queue_redraw（守 perf 守则）

class_name MotherGooseJamShield
extends RefCounted

enum State { COOLDOWN, WARNING, EXPANDING, SUSTAIN }

const WARNING_DURATION: float = 4.0
const EXPANDING_DURATION: float = 8.0
const SUSTAIN_DURATION: float = 8.0
const COOLDOWN_DURATION: float = 40.0

## 干扰场最大半径 = CommanderAura.AURA_RADIUS（1500），与"强化无人机的范围"统一
## 视觉/gameplay 上"jam 减速圈" 与 "UAV 增益圈"是同一个范围 —— 玩家更容易内化 boss 的影响半径
const RADIUS_MIN: float = 300.0
const RADIUS_MAX: float = 1500.0

const PLAYER_SPEED_MULT: float = 0.6   ## 场内玩家顶速压制系数（被 effective_max_speed_kmh 读取）

var state: int = State.COOLDOWN
var state_timer: float = 0.0   ## 当前状态已耗秒数

## 当前外圈半径（像素）；COOLDOWN/WARNING 时有意义，但效果由 is_effect_active 控制
var current_radius: float = 0.0

## 是否首轮已启动；首版默认进入战斗即开始 COOLDOWN（玩家有 40s 准备）
var started: bool = false

func start() -> void:
	if started:
		return
	started = true
	state = State.COOLDOWN
	state_timer = 0.0

## 是否处于"实际施加效果"的阶段（EXPANDING + SUSTAIN）
func is_effect_active() -> bool:
	return state == State.EXPANDING or state == State.SUSTAIN

## 仅显示警示（用于 HUD 提示玩家提前撤离），不施加效果
func is_warning_active() -> bool:
	return state == State.WARNING

## 是否当前帧需要绘制（WARNING/EXPANDING/SUSTAIN 都画）
func is_visible() -> bool:
	return state != State.COOLDOWN

func update(delta: float) -> void:
	if not started:
		return
	state_timer += delta
	match state:
		State.COOLDOWN:
			current_radius = 0.0
			if state_timer >= COOLDOWN_DURATION:
				_enter_state(State.WARNING)
		State.WARNING:
			current_radius = RADIUS_MIN  ## 显示提示圈但不施加效果
			if state_timer >= WARNING_DURATION:
				_enter_state(State.EXPANDING)
		State.EXPANDING:
			var t: float = clampf(state_timer / EXPANDING_DURATION, 0.0, 1.0)
			current_radius = lerpf(RADIUS_MIN, RADIUS_MAX, t)
			if state_timer >= EXPANDING_DURATION:
				_enter_state(State.SUSTAIN)
		State.SUSTAIN:
			current_radius = RADIUS_MAX
			if state_timer >= SUSTAIN_DURATION:
				_enter_state(State.COOLDOWN)

func _enter_state(s: int) -> void:
	state = s
	state_timer = 0.0

## 检查某点是否在场内（用于受效逻辑）
func contains_world_point(boss_pos: Vector2, p: Vector2) -> bool:
	if not is_effect_active():
		return false
	return boss_pos.distance_to(p) <= current_radius

## 在 CanvasItem 上绘制（坐标系 = boss 本地，因此调用方应在 _draw 内
## 用 draw_set_transform 把坐标系拉回世界 / 或直接画在 boss 自己 transform 下）
## 我们用最简单做法：CanvasItem 是 boss 自己，但 boss 自己 rotation = heading，
## 于是以 boss 中心画圆即可（圆形旋转无差别）。
static func draw_into(ci: CanvasItem, shield: MotherGooseJamShield) -> void:
	if shield == null or not shield.is_visible():
		return
	var r: float = shield.current_radius
	if r <= 0.0:
		return
	# 颜色：WARNING 偏黄，EXPANDING 偏橙，SUSTAIN 偏红
	var fill_col: Color
	var ring_col: Color
	match shield.state:
		State.WARNING:
			fill_col = Color(1.0, 0.85, 0.2, 0.05)
			ring_col = Color(1.0, 0.85, 0.2, 0.55)
		State.EXPANDING:
			fill_col = Color(1.0, 0.45, 0.15, 0.10)
			ring_col = Color(1.0, 0.55, 0.20, 0.75)
		State.SUSTAIN:
			fill_col = Color(0.95, 0.20, 0.20, 0.13)
			ring_col = Color(1.0, 0.30, 0.30, 0.80)
		_:
			return
	ci.draw_circle(Vector2.ZERO, r, fill_col)
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, ring_col, 2.0, true)
	# 内圈细线指示"安全核心"边界
	if shield.state == State.EXPANDING or shield.state == State.SUSTAIN:
		var inner: Color = ring_col
		inner.a *= 0.4
		ci.draw_arc(Vector2.ZERO, RADIUS_MIN, 0.0, TAU, 48, inner, 1.0, true)
