class_name SubmarineShip
extends NavalUnit

## SS 核潜艇 —— 事件 BOSS 级（预留接口，非常规 spawner 刷新）
##
## 1 挂点：船背 VLS-MEGA（HP 300）—— 浮出时齐射 18 枚远程巡航导弹
## 无 CIWS（潜艇靠下潜无敌，不依赖近防）
## 无弱点，VLS 挂点死 = 船死；总血 800
##
## 浮出/下潜状态机（预留，未来事件系统挂接）：
##   SUBMERGED  完全无敌、不可锁、alpha=0（当前默认进入 SURFACED 方便 Debug 测试）
##   SURFACING  3 秒淡入，modulate.a 从 0 到 1
##   SURFACED   10-15 秒射击窗口 + 可被打
##   SUBMERGING 3 秒淡出，下次 SUBMERGED 重置 intercept_hp
##
## 当前 spawn 默认是 SURFACED，可完全正常被打。
## 接入事件系统时改为：事件触发 → 从 SUBMERGED 进入 SURFACING，射完窗口关了就 SUBMERGING 回 SUBMERGED

enum PhaseState { SUBMERGED, SURFACING, SURFACED, SUBMERGING }

var phase: int = PhaseState.SURFACED  ## 默认浮出
var phase_timer: float = 0.0

## 视觉外形（俯视）：长条潜水艇 + 中央指挥塔 + 后部垂直发射井
func _draw_hull_placeholder() -> void:
	if params == null:
		return
	var L: float = params.hull_length
	var W: float = params.hull_width
	var color: Color = GameConstants.team_color(team)
	var outline_color: Color = color.darkened(0.35)
	var half_L: float = L * 0.5
	var half_W: float = W * 0.5

	# 细长流线潜艇外形（两端椭圆尖头）
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -half_L),
		Vector2(half_W * 0.5, -half_L * 0.92),
		Vector2(half_W * 0.85, -half_L * 0.75),
		Vector2(half_W, -half_L * 0.4),
		Vector2(half_W, half_L * 0.4),
		Vector2(half_W * 0.85, half_L * 0.75),
		Vector2(half_W * 0.5, half_L * 0.92),
		Vector2(0, half_L),
		Vector2(-half_W * 0.5, half_L * 0.92),
		Vector2(-half_W * 0.85, half_L * 0.75),
		Vector2(-half_W, half_L * 0.4),
		Vector2(-half_W, -half_L * 0.4),
		Vector2(-half_W * 0.85, -half_L * 0.75),
		Vector2(-half_W * 0.5, -half_L * 0.92),
	])
	draw_colored_polygon(body, color)
	for i in range(body.size()):
		draw_line(body[i], body[(i + 1) % body.size()], outline_color, 1.5)

	# 指挥塔（船中稍前，长方形）
	var sail_color: Color = outline_color.darkened(0.2)
	var sail_rect := Rect2(-half_W * 0.35, -half_L * 0.1, half_W * 0.7, half_L * 0.2)
	draw_rect(sail_rect, sail_color)
	draw_rect(sail_rect, color.lightened(0.12), false, 1.0)

	# VLS 发射井（船背中后部，16 格网格暗示齐射发射源）
	var vls_color: Color = outline_color.lightened(0.2)
	var vls_rect := Rect2(-half_W * 0.45, half_L * 0.15, half_W * 0.9, half_L * 0.4)
	draw_rect(vls_rect, vls_color, false, 1.2)
	# 简化的 4x4 发射格
	for col in range(1, 4):
		var gx: float = lerpf(-half_W * 0.45, half_W * 0.45, float(col) / 4.0)
		draw_line(Vector2(gx, half_L * 0.15), Vector2(gx, half_L * 0.55), vls_color, 0.6)
	for row in range(1, 4):
		var gy: float = lerpf(half_L * 0.15, half_L * 0.55, float(row) / 4.0)
		draw_line(Vector2(-half_W * 0.45, gy), Vector2(half_W * 0.45, gy), vls_color, 0.6)


# ============================================================
#  浮出/下潜状态机（预留接口）
# ============================================================

## 由外部事件调用 —— 从 SUBMERGED 开始浮出序列
func begin_surface() -> void:
	if phase != PhaseState.SUBMERGED:
		return
	phase = PhaseState.SURFACING
	phase_timer = 0.0

## 由外部事件调用 —— 从 SURFACED 开始下潜序列
func begin_submerge() -> void:
	if phase != PhaseState.SURFACED:
		return
	phase = PhaseState.SUBMERGING
	phase_timer = 0.0

## TODO：后续事件系统接入时把 phase 推进逻辑写到 _physics_process 里
## - SURFACING 3s → SURFACED，同时 modulate.a 从 0 → 1
## - SURFACED 10-15s → SUBMERGING（或被打沉）
## - SUBMERGING 3s → SUBMERGED，modulate.a 从 1 → 0，锁点 disable
