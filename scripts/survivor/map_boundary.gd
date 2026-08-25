class_name MapBoundary
extends Node2D

## 大地图边界系统（生存模式）
##
## 职责：
##   1. 定义世界矩形（WORLD_SIZE_M 见方，中心在原点；当前 64km × 64km）
##   2. 在世界空间绘制红色虚线边界 + corner ticks（Tactical Telemetry 风格）
##   3. 监测玩家进入旧 60km 核心外的外缘空域，连续倒计时后触发决策
##
## 使用：
##   var mb := MapBoundary.new()
##   mb.player = player_aircraft
##   add_child(mb)
##   mb.approach_warning.connect(_on_approach)
##   mb.boundary_crossed.connect(_on_crossed)

# ── 常量 ──
const WORLD_SIZE_M := 64000.0                    ## 真边界边长；三图共同底图 overscan 内的保守值
const WORLD_HALF_PX := WORLD_SIZE_M * 0.5 * GameConstants.PIXELS_PER_METER  ## 半边长 = 16000 px
const CORE_HALF_PX := 15000.0                    ## 旧 60km 边界；现在是外缘空域入口
const EXTENSION_WIDTH_PX := WORLD_HALF_PX - CORE_HALF_PX  ## 四边各 1000 px = 2km
const WARN_DISTANCE_M := 2000.0                  ## 警戒距离（米）
const WARN_DISTANCE_PX := WARN_DISTANCE_M * GameConstants.PIXELS_PER_METER  ## 1000 px
const EXIT_COUNTDOWN_S := 2.5                    ## 外缘空域连续停留多久才打开决策
const RETURN_RESET_MARGIN_PX := 40.0             ## 返回核心内侧少许后才允许下一次触发，防入口抖动
const AI_EDGE_TURN_MARGIN_PX := 300.0            ## AI 可进入大部分外缘带，只在真边界前收容
const CAMERA_CONTENT_INSET_PX := 32.0            ## 给电影 offset/滤波留余量，任何 zoom 不露底图外黑边
const PLAYER_START_OFFSET_PX := Vector2(0.0, 13900.0)  ## 距核心入口 1100px，保持旧开局语义

# ── 视觉 ──
## 边界线：温和琥珀（补给友好区）而非刺眼红
const BORDER_COLOR := Color(0.85, 0.65, 0.28, 0.65)
const BORDER_COLOR_PULSE := Color(0.98, 0.78, 0.35, 0.9)
const ENTRY_COLOR := Color(0.88, 0.76, 0.42, 0.42)
const EXTENSION_FILL := Color(0.78, 0.58, 0.20, 0.055)
const DASH_LEN := 60.0
const DASH_GAP := 30.0
const CORNER_TICK_LEN := 240.0
const CORNER_MARK_INTERVAL_PX := 1000.0          ## 每 1000 px（2km）画一个 tick
const TICK_LEN := 30.0
const BORDER_LINE_WIDTH := 2.0

# ── 状态 ──
var player: Variant = null
var _world_rect: Rect2 = Rect2(-WORLD_HALF_PX, -WORLD_HALF_PX, WORLD_HALF_PX * 2.0, WORLD_HALF_PX * 2.0)
var _core_rect: Rect2 = Rect2(-CORE_HALF_PX, -CORE_HALF_PX, CORE_HALF_PX * 2.0, CORE_HALF_PX * 2.0)
var _is_warning: bool = false
var _in_extension: bool = false
var _decision_latched: bool = false
var _countdown_remaining: float = EXIT_COUNTDOWN_S
var _pulse_time: float = 0.0

# ── 信号 ──
signal approach_warning(active: bool, distance_m: float)   ## 进入/离开警戒距离（≤2km）或距离刷新
signal boundary_countdown(active: bool, remaining_s: float) ## 外缘空域倒计时刷新/取消
signal boundary_crossed                                     ## 倒计时耗尽后触发一次边界决策

func get_world_rect() -> Rect2:
	return _world_rect

## 相机钳制矩形：严格内收，视口和电影偏移都不能采到正式底图外。
func get_camera_bounds() -> Rect2:
	return _world_rect.grow(-CAMERA_CONTENT_INSET_PX)

func get_core_rect() -> Rect2:
	return _core_rect

## 玩家起始世界坐标（供 survivor_mode 调用定位）
static func get_player_start() -> Vector2:
	return PLAYER_START_OFFSET_PX

## 世界矩形的边界常量（供刷怪系统快速查询，矩形固定中心在原点）
static func world_half_px() -> float:
	return WORLD_HALF_PX

## 到旧 60km 核心入口的距离；核心内为正，外缘空域/图外为 0 或负。
static func distance_to_extension_entry(pos: Vector2) -> float:
	var dx := minf(pos.x + CORE_HALF_PX, CORE_HALF_PX - pos.x)
	var dy := minf(pos.y + CORE_HALF_PX, CORE_HALF_PX - pos.y)
	return minf(dx, dy)

static func is_in_extension_zone(pos: Vector2) -> bool:
	return distance_to_extension_entry(pos) <= 0.0

## 返回 pos 到矩形边界的最短距离（px，内部为正，外部为 0 或负）
static func distance_to_edge(pos: Vector2) -> float:
	var dx := minf(pos.x - (-WORLD_HALF_PX), WORLD_HALF_PX - pos.x)
	var dy := minf(pos.y - (-WORLD_HALF_PX), WORLD_HALF_PX - pos.y)
	return minf(dx, dy)

## 判断 pos 是否在"安全区"内（离边界至少 margin_px）
static func is_safe_inside(pos: Vector2, margin_px: float) -> bool:
	return distance_to_edge(pos) >= margin_px

## 把 pos 钳制到距边界至少 margin_px 的位置
static func clamp_inside(pos: Vector2, margin_px: float) -> Vector2:
	return Vector2(
		clampf(pos.x, -WORLD_HALF_PX + margin_px, WORLD_HALF_PX - margin_px),
		clampf(pos.y, -WORLD_HALF_PX + margin_px, WORLD_HALF_PX - margin_px)
	)

func _ready() -> void:
	z_index = 50  # 在地形/天气之上，飞机之下

func _process(delta: float) -> void:
	_pulse_time += delta
	if typeof(player) != TYPE_OBJECT or player == null or not is_instance_valid(player) \
			or not (player is Node2D):
		if _in_extension:
			_in_extension = false
			_countdown_remaining = EXIT_COUNTDOWN_S
			boundary_countdown.emit(false, EXIT_COUNTDOWN_S)
			queue_redraw()
		return

	var p: Vector2 = (player as Node2D).global_position
	var core_dist_px := distance_to_extension_entry(p)
	var in_extension_now := core_dist_px <= 0.0

	# 警戒：核心入口内侧 ≤2km。BOSS 阶段仍弹警告，但 BoundaryUI 会切到
	# "无法补给 / 回血" 的专用文案
	var was_warning := _is_warning
	var should_warn := core_dist_px > 0.0 and core_dist_px <= WARN_DISTANCE_PX
	if should_warn != _is_warning:
		_is_warning = should_warn
		approach_warning.emit(_is_warning, core_dist_px / GameConstants.PIXELS_PER_METER)
		queue_redraw()  # 状态切换时重绘一次（脉冲颜色切换）
	elif _is_warning:
		approach_warning.emit(true, core_dist_px / GameConstants.PIXELS_PER_METER)
		queue_redraw()  # 警戒时才需要脉冲动画
	elif was_warning:
		# 刚退出警戒：再画一次清掉脉冲色
		queue_redraw()
	# 不警戒时：静态颜色，不需要每帧重绘（边界是几百条 draw_line）

	# 决策弹窗已触发后，必须真正回到核心内侧才重新武装；避免入口线抖动反复弹窗。
	if _decision_latched:
		if core_dist_px >= RETURN_RESET_MARGIN_PX:
			_decision_latched = false
			_countdown_remaining = EXIT_COUNTDOWN_S
		return

	if in_extension_now:
		if not _in_extension:
			_in_extension = true
			_countdown_remaining = EXIT_COUNTDOWN_S
		_countdown_remaining = maxf(_countdown_remaining - maxf(delta, 0.0), 0.0)
		boundary_countdown.emit(true, _countdown_remaining)
		queue_redraw()
		if _countdown_remaining <= 0.0:
			_in_extension = false
			_decision_latched = true
			boundary_countdown.emit(false, 0.0)
			boundary_crossed.emit()
	elif _in_extension:
		_in_extension = false
		_countdown_remaining = EXIT_COUNTDOWN_S
		boundary_countdown.emit(false, EXIT_COUNTDOWN_S)
		queue_redraw()

# ══════════════════════════════════════════════
#  绘制
# ══════════════════════════════════════════════

func _draw() -> void:
	var pulse_t := (sin(_pulse_time * 3.0) * 0.5 + 0.5)
	var entry_active := _is_warning or _in_extension
	var entry_col := ENTRY_COLOR.lerp(BORDER_COLOR_PULSE, pulse_t if entry_active else 0.0)

	_draw_extension_band()
	_draw_rect_dashed(_core_rect, entry_col)
	var r := _world_rect
	_draw_rect_dashed(r, BORDER_COLOR)

	_draw_corner_ticks(BORDER_COLOR)
	_draw_edge_marks(BORDER_COLOR)

func _draw_extension_band() -> void:
	var outer := _world_rect
	var core := _core_rect
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, core.position.y - outer.position.y)), EXTENSION_FILL)
	draw_rect(Rect2(Vector2(outer.position.x, core.end.y), Vector2(outer.size.x, outer.end.y - core.end.y)), EXTENSION_FILL)
	draw_rect(Rect2(Vector2(outer.position.x, core.position.y), Vector2(core.position.x - outer.position.x, core.size.y)), EXTENSION_FILL)
	draw_rect(Rect2(Vector2(core.end.x, core.position.y), Vector2(outer.end.x - core.end.x, core.size.y)), EXTENSION_FILL)

func _draw_rect_dashed(rect: Rect2, col: Color) -> void:
	_draw_dashed_edge(Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), col)
	_draw_dashed_edge(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), col)
	_draw_dashed_edge(Vector2(rect.end.x, rect.end.y), Vector2(rect.position.x, rect.end.y), col)
	_draw_dashed_edge(Vector2(rect.position.x, rect.end.y), Vector2(rect.position.x, rect.position.y), col)

func _draw_dashed_edge(a: Vector2, b: Vector2, col: Color) -> void:
	var total := a.distance_to(b)
	if total <= 0.0:
		return
	var dir := (b - a).normalized()
	var pos := 0.0
	while pos < total:
		var seg_end := minf(pos + DASH_LEN, total)
		draw_line(a + dir * pos, a + dir * seg_end, col, BORDER_LINE_WIDTH)
		pos = seg_end + DASH_GAP

func _draw_corner_ticks(col: Color) -> void:
	var r := _world_rect
	var L := CORNER_TICK_LEN
	# 四个角：两条粗实线沿边延伸
	var corners := [
		[Vector2(r.position.x, r.position.y), Vector2(1, 0), Vector2(0, 1)],
		[Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(r.end.x, r.end.y), Vector2(-1, 0), Vector2(0, -1)],
		[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)],
	]
	for c in corners:
		var o: Vector2 = c[0]
		var d1: Vector2 = c[1]
		var d2: Vector2 = c[2]
		draw_line(o, o + d1 * L, col, BORDER_LINE_WIDTH * 2.0)
		draw_line(o, o + d2 * L, col, BORDER_LINE_WIDTH * 2.0)

func _draw_edge_marks(col: Color) -> void:
	var r := _world_rect
	var step := CORNER_MARK_INTERVAL_PX
	var mark_col := Color(col.r, col.g, col.b, col.a * 0.55)
	# 顶底
	var x := r.position.x + step
	while x < r.end.x:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + TICK_LEN), mark_col, 1.5)
		draw_line(Vector2(x, r.end.y), Vector2(x, r.end.y - TICK_LEN), mark_col, 1.5)
		x += step
	# 左右
	var y := r.position.y + step
	while y < r.end.y:
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x + TICK_LEN, y), mark_col, 1.5)
		draw_line(Vector2(r.end.x, y), Vector2(r.end.x - TICK_LEN, y), mark_col, 1.5)
		y += step
