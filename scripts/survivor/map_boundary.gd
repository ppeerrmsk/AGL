class_name MapBoundary
extends Node2D

## 大地图边界系统（生存模式）
##
## 职责：
##   1. 定义世界矩形（50km × 50km，中心在原点）
##   2. 在世界空间绘制红色虚线边界 + corner ticks（Tactical Telemetry 风格）
##   3. 监测玩家到边界的距离，触发 approach / cross 信号
##
## 使用：
##   var mb := MapBoundary.new()
##   mb.player = player_aircraft
##   add_child(mb)
##   mb.approach_warning.connect(_on_approach)
##   mb.boundary_crossed.connect(_on_crossed)

# ── 常量 ──
const WORLD_SIZE_M := 30000.0                    ## 地图边长（米）
const WORLD_HALF_PX := WORLD_SIZE_M * 0.5 * GameConstants.PIXELS_PER_METER  ## 半边长 = 7500 px（30000m × 0.5 × 0.5 px/m）
const WARN_DISTANCE_M := 2000.0                  ## 警戒距离（米）
const WARN_DISTANCE_PX := WARN_DISTANCE_M * GameConstants.PIXELS_PER_METER  ## 1000 px
## 相机外缘扩张：相机最多能拉到游戏边界外这么远，再往外拉不动。
## 这样玩家能看到"边界之外还有一小块空域"，不会被生硬裁掉。
const CAMERA_MARGIN_M := 5000.0
const CAMERA_MARGIN_PX := CAMERA_MARGIN_M * GameConstants.PIXELS_PER_METER  ## 2500 px
const PLAYER_START_OFFSET_PX := Vector2(0.0, 6400.0)  ## 玩家起始点相对原点（南侧靠边缘，y 正向；距南边界 1100px ≈ 2.2km，刚好在 1000px 警戒带外）

# ── 视觉 ──
## 边界线：温和琥珀（补给友好区）而非刺眼红
const BORDER_COLOR := Color(0.85, 0.65, 0.28, 0.65)
const BORDER_COLOR_PULSE := Color(0.98, 0.78, 0.35, 0.9)
const DASH_LEN := 60.0
const DASH_GAP := 30.0
const CORNER_TICK_LEN := 240.0
const CORNER_MARK_INTERVAL_PX := 1000.0          ## 每 1000 px（2km）画一个 tick
const TICK_LEN := 30.0
const BORDER_LINE_WIDTH := 2.0

# ── 状态 ──
var player: Aircraft
var _world_rect: Rect2 = Rect2(-WORLD_HALF_PX, -WORLD_HALF_PX, WORLD_HALF_PX * 2.0, WORLD_HALF_PX * 2.0)
var _is_warning: bool = false
var _is_crossed: bool = false
var _pulse_time: float = 0.0

# ── 信号 ──
signal approach_warning(active: bool, distance_m: float)   ## 进入/离开警戒距离（≤2km）或距离刷新
signal boundary_crossed                                      ## 越界触发（玩家出 rect）

func get_world_rect() -> Rect2:
	return _world_rect

## 相机钳制矩形（比游戏边界大 CAMERA_MARGIN_PX，让玩家能看到"边界之外"少许空域）
func get_camera_bounds() -> Rect2:
	var m := CAMERA_MARGIN_PX
	return Rect2(
		_world_rect.position - Vector2(m, m),
		_world_rect.size + Vector2(m * 2.0, m * 2.0)
	)

## 玩家起始世界坐标（供 survivor_mode 调用定位）
static func get_player_start() -> Vector2:
	return PLAYER_START_OFFSET_PX

## 世界矩形的边界常量（供刷怪系统快速查询，矩形固定中心在原点）
static func world_half_px() -> float:
	return WORLD_HALF_PX

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
	if not player or not is_instance_valid(player):
		return

	var p: Vector2 = player.global_position
	var dist_px := _distance_to_border(p)
	var outside := not _world_rect.has_point(p)

	# 越界：发一次信号（BOSS 阶段也要发，由 survivor_mode._on_supply_confirmed 阻止补给）
	if outside and not _is_crossed:
		_is_crossed = true
		boundary_crossed.emit()
	elif not outside and _is_crossed:
		_is_crossed = false  # 回到内部（被撤退菜单的取消按钮拉回）

	# 警戒：进入/离开 ≤2km 区间。BOSS 阶段仍弹警告，但 BoundaryUI 会切到
	# "无法补给 / 回血" 的专用文案
	var was_warning := _is_warning
	var should_warn := (dist_px <= WARN_DISTANCE_PX) and not outside
	if should_warn != _is_warning:
		_is_warning = should_warn
		approach_warning.emit(_is_warning, dist_px / GameConstants.PIXELS_PER_METER)
		queue_redraw()  # 状态切换时重绘一次（脉冲颜色切换）
	elif _is_warning:
		approach_warning.emit(true, dist_px / GameConstants.PIXELS_PER_METER)
		queue_redraw()  # 警戒时才需要脉冲动画
	elif was_warning:
		# 刚退出警戒：再画一次清掉脉冲色
		queue_redraw()
	# 不警戒时：静态颜色，不需要每帧重绘（边界是几百条 draw_line）

## 点到矩形边界的最短距离（内部为正，外部为负）
func _distance_to_border(p: Vector2) -> float:
	var dx := minf(p.x - _world_rect.position.x, _world_rect.end.x - p.x)
	var dy := minf(p.y - _world_rect.position.y, _world_rect.end.y - p.y)
	return minf(dx, dy)

# ══════════════════════════════════════════════
#  绘制
# ══════════════════════════════════════════════

func _draw() -> void:
	var pulse_t := (sin(_pulse_time * 3.0) * 0.5 + 0.5)
	var col := BORDER_COLOR.lerp(BORDER_COLOR_PULSE, pulse_t if _is_warning else 0.0)

	var r := _world_rect
	_draw_dashed_edge(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), col)  # top
	_draw_dashed_edge(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), col)              # right
	_draw_dashed_edge(Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y), col)              # bottom
	_draw_dashed_edge(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y), col)    # left

	_draw_corner_ticks(col)
	_draw_edge_marks(col)

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
