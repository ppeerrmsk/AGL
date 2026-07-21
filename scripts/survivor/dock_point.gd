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
const REARM_LEAVE_MULT := 1.15       ## 重新武装需离开的半径倍数

@export var radius: float = 600.0
@export var dock_kind: String = "airfield"      ## "airfield" / "carrier"
@export var display_name_key: String = "DOCK_HANEDA_NAME"

var mode: Node = null              ## SurvivorMode 引用：每帧解析当前操控机（1-4 切控后仍指对）
var player: Aircraft = null        ## 兜底/手动注入（mode 为空时用）
var _hold: float = 0.0
var _player_inside: bool = false
var _armed: bool = true

# ── 视觉 ──
const RING_COLOR := Color(0.45, 0.90, 0.78, 0.55)       ## 友军青绿
const RING_COLOR_ACTIVE := Color(0.55, 1.00, 0.85, 0.9)
const PROGRESS_COLOR := Color(0.98, 0.85, 0.40, 0.95)   ## 停靠倒计时金
const TEXT_COLOR := Color(0.75, 0.95, 0.88, 0.9)
const RUNWAY_COLOR := Color(0.45, 0.90, 0.78, 0.75)

func _ready() -> void:
	z_index = 40  # 地形之上、飞机之下
	add_to_group("dock_points")

func _process(delta: float) -> void:
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
	var speed_kmh: float = player.speed * 3.6
	if _armed and speed_kmh <= _land_threshold_kmh(pl):
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
		if _hold > 0.0:
			queue_redraw()
		_hold = 0.0

func _draw() -> void:
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
