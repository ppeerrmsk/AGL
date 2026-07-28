class_name DockPoint
extends Node2D

## 停靠点（spec zone-reward-docking §2.2）：机场 / 航母甲板共用的着陆结算组件
##
## 判定：玩家操控机进入停靠圈 + 速度 ≤ LAND_SPEED_KMH 持续 HOLD_SEC → 发 docked 信号
## （由 survivor_mode 接住打开停靠结算）。docked 后须离圈重新武装，防贴圈重复触发。
##
## 性能：只追踪一架玩家机（每帧一次距离+速度比较）；绘制静态化——仅玩家在圈内时
## 每帧重绘（倒计时环），圈外只在状态切换时重绘一次。全图 3~4 个实例。

signal docked(dock: DockPoint)

const LAND_SPEED_FLOOR_KMH := 300.0  ## 着陆阈值地板（km/h）
const LAND_STALL_MULT := 1.3         ## 阈值 = max(地板, 本机失速基数 × 此系数)
const HOLD_SEC := 1.0                ## 达标须持续时间（秒）
const HOLD_DECAY_MULT := 2.0         ## 超阈时进度衰减速率（×累积，2026-07-24 容错：不清零防 G 抖动打回原点）
const REARM_LEAVE_MULT := 1.15       ## 重新武装需离开的半径倍数

@export var radius: float = 600.0
@export var dock_kind: String = "airfield"      ## "airfield" / "carrier"
@export var display_name_key: String = "DOCK_HANEDA_NAME"

var mode: Node = null              ## SurvivorMode 引用：每帧解析当前操控机（1-4 切控后仍指对）
var player: Aircraft = null        ## 兜底/手动注入（mode 为空时用）
var _hold: float = 0.0
var _player_inside: bool = false
var _armed: bool = true
## 一次性机场（spec zone-reward-docking §2.2 修订）：airfield 停靠一次即失效——
## 标记消失（主图/Tab 都不再画）+ 不再判定停靠。carrier 不置 spent（走自己的限 2 次登舰机制）。
## 机场的 ALLY 防空驻军（_spawn_airfield_garrison 独立实体）不受影响，原地保留。
var _spent: bool = false

# ── 视觉 ──
const RING_COLOR := Color(0.45, 0.90, 0.78, 0.55)       ## 友军青绿
const RING_COLOR_ACTIVE := Color(0.55, 1.00, 0.85, 0.9)
const PROGRESS_COLOR := Color(0.98, 0.85, 0.40, 0.95)   ## 停靠倒计时金
const TEXT_COLOR := Color(0.75, 0.95, 0.88, 0.9)
const RUNWAY_COLOR := Color(0.45, 0.90, 0.78, 0.75)

func _ready() -> void:
	z_index = 40  # 地形之上、飞机之下
	add_to_group("dock_points")

## 机场用尽：停靠一次后由 survivor_mode._on_dock_docked 调用。
## 立即清空主图标记（之后 _draw 早返回不再绘制），停判定。
func mark_spent() -> void:
	_spent = true
	_player_inside = false
	_hold = 0.0
	queue_redraw()

func is_spent() -> bool:
	return _spent

func _process(delta: float) -> void:
	if _spent:
		return
	var pl: Aircraft = player
	if mode and "player_aircraft" in mode and mode.player_aircraft:
		pl = mode.player_aircraft
	if not pl or not is_instance_valid(pl) or pl.is_destroyed:
		if _player_inside:
			_player_inside = false
			queue_redraw()
		return
	player = pl
	var dist := global_position.distance_to(pl.global_position)
	var inside := dist <= radius
	if inside != _player_inside:
		_player_inside = inside
		queue_redraw()
	if not inside:
		_hold = 0.0
		if not _armed and dist > radius * REARM_LEAVE_MULT:
			_armed = true
		return
	# 圈内：速度判定 + 停靠倒计时（单节点圈内每帧重绘，成本可忽略）
	# g 中和（2026-07-24 修订）：飞机转弯拉 G 时物理最低速被抬到角点速度（500~790km/h），
	# 用绝对 300 判定则绕圈永远够不到（旧 bug：明明写 300、到了 300 却不触发）。改比"是否已减到
	# 本机当前 G 下的最低速"——实测速度除以 g^0.4 折回 1G 当量再比阈值（物理最低速 = stall_base×g^0.4×1.05，
	# 除掉 g^0.4 后直线/绕圈的"减到底"都映射回同一 ~231 当量）。1G 直飞时 g^0.4=1，行为与旧实现一致。
	var eff_speed_kmh: float = _dock_speed_kmh(pl)
	if _armed and eff_speed_kmh <= _land_threshold_kmh(pl):
		_hold += delta
		queue_redraw()
		# 地勤优化（720 批）：停靠判定耗时减半
		var hold_need: float = HOLD_SEC
		if mode and "upgrade_stacks" in mode and int(mode.upgrade_stacks.get("ground_crew", 0)) > 0:
			hold_need = HOLD_SEC * 0.5
		if _hold >= hold_need:
			_hold = 0.0
			_armed = false
			EventLogger.log_event("DOCK", "Docked", "%s kind=%s" % [display_name_key, dock_kind])
			docked.emit(self)
	else:
		# 容错：不清零、改快速衰减——防绕圈时瞬时 G 抖动把进度环打回原点
		if _hold > 0.0:
			_hold = maxf(_hold - delta * HOLD_DECAY_MULT, 0.0)
			queue_redraw()

func _draw() -> void:
	if _spent:
		return  # 一次性机场用尽 → 标记消失
	var ring_col := RING_COLOR_ACTIVE if _player_inside else RING_COLOR
	# 虚线停靠圈（32 段取半）
	var segs := 32
	for i in range(segs):
		if i % 2 == 1:
			continue
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		draw_arc(Vector2.ZERO, radius, a0, a1, 4, ring_col, 2.0)
	# 跑道图标（机场）/ 甲板框（航母由船体自带外观，这里只画细框）
	if dock_kind == "airfield":
		draw_rect(Rect2(-100, -22, 200, 44), RUNWAY_COLOR, false, 2.5)
		for k in range(4):
			var x := -70.0 + 45.0 * float(k)
			draw_line(Vector2(x, 0), Vector2(x + 24, 0), RUNWAY_COLOR, 2.0)
	else:
		draw_rect(Rect2(-70, -26, 140, 52), RUNWAY_COLOR, false, 2.0)
	# 名称
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-radius, -radius - 26.0), tr(display_name_key),
		HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 30, TEXT_COLOR)
	# 玩家在圈内：减速提示 / 停靠进度环
	if _player_inside:
		if _hold > 0.0:
			draw_arc(Vector2.ZERO, radius * 0.82, -PI * 0.5,
				-PI * 0.5 + TAU * clampf(_hold / HOLD_SEC, 0.0, 1.0), 40, PROGRESS_COLOR, 5.0)
			draw_string(font, Vector2(-radius, radius + 16.0), tr("DOCK_HINT_DOCKING"),
				HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 30, PROGRESS_COLOR)
		elif _armed:
			draw_string(font, Vector2(-radius, radius + 16.0),
				tr("DOCK_HINT_SLOW") % [int(_land_threshold_kmh(player))],
				HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 30, TEXT_COLOR)

## 着陆速度阈值（km/h）：动态随机型 = max(地板 300, 失速基数 × 1.3)。
## 2026-07-06 playtest 修复：旧固定 250 压在玩家机 1G 失速地板（~252 km/h）之下，
## 右键减速物理上到不了 → 永远停不靠。读 params.stall_speed_base（稳定值，不随 G 抖），
## 永久升级改失速基数时阈值自动跟随。
func _land_threshold_kmh(pl: Aircraft) -> float:
	if pl and is_instance_valid(pl) and pl.params:
		return maxf(LAND_SPEED_FLOOR_KMH, pl.params.stall_speed_base * LAND_STALL_MULT)
	return LAND_SPEED_FLOOR_KMH

## 停靠判定用的 g 中和速度（km/h）：实测速度 ÷ g^0.4，折回 1G 当量。
## 飞机转弯时物理最低速随 G 抬升（= stall_base × g^0.4 × 1.05，见 aircraft_physics.update_speed），
## 除以 g^0.4 后恰好把"已减到当前 G 最低速"的状态映射回 1G 最低速当量（≈231），
## 使直线进近与绕圈进近都能在减速到底时触发停靠（2026-07-24 放宽判定容错，用户拍板）。
func _dock_speed_kmh(pl: Aircraft) -> float:
	var raw := pl.speed * 3.6
	var g := maxf(pl.g_load, 1.0)
	return raw / pow(g, 0.4)
