class_name AdbsManager
extends Node

## ADBS（Adds / 随机事件）管理器
##
## 负责触发与调度：
##   1. **开局教程**：game_time ≈ 5s 时在玩家正前方刷 2 架轰炸机，背对玩家逃离
##      （"第一桶金"教学）
##   2. **城区直升机事件**：低概率（每个 60-120s 调度窗 25%）在远端城区刷一队 CH-47，
##      飞向最近地图边界。玩家从战术地图主动寻找；若不理会，单位逃出地图后自动结束
##   3. （未来可扩展：空袭预警 / 王牌单发 / 护航等）
##
## 事件单位一律走 Adds 族群系统（不占 Token，逃离即消失），玩家击坠给高 XP 奖励。

## ── 事件调度 ──
const EVENT_INTERVAL_MIN := 60.0
const EVENT_INTERVAL_MAX := 120.0
const EVENT_DEFER_COOLDOWN := 30.0          ## 被跳过（玩家在战区内）后多久再 roll
const EVENT_NO_CANDIDATE_COOLDOWN := 25.0   ## 全图没有合适城区时多久再 roll
const EVENT_DEFER_WHEN_IN_ZONE := true      ## 玩家在战区圆内时不刷支线

## ── 教程轰炸机 ──
## 距离略大于玩家默认雷达锁定范围（F-16 ≈ 1667 px），玩家要往前飞才进入锁定
## 但又不会远到看不到 / 飞不过去
const TUTORIAL_LEAD_DIST_PX := 3000.0       ## 第 0 架距玩家前方距离（≈6km；保留给日志用）
const TUTORIAL_SPAWN_MARGIN_PX := 1500.0    ## 防越界夹紧余量
const TUTORIAL_LATERAL_PX := 320.0          ## 左右交替偏置
const TUTORIAL_COLUMN_BACK_PX := 550.0      ## 每后一档的距离
const TUTORIAL_COUNT := 3                   ## 轰炸机数量
## 教程轰炸机锚点：出生点正前方 TUTORIAL_LEAD_DIST_PX（spawn 后世界坐标固定不跟玩家走，
## 玩家后退 = 真拉开距离）。从 PLAYER_START_OFFSET_PX 派生 —— 2026-07-06 修复：旧值写死
## (0,3000) 是 30km 图时代的绝对坐标，60km 扩图后出生点挪到 (0,13900)，教程机变到 10.9km 外
const TUTORIAL_BOMBER_ANCHOR := MapBoundary.PLAYER_START_OFFSET_PX + Vector2(0.0, -TUTORIAL_LEAD_DIST_PX)

## ── 城区直升机事件 ──
const CITY_HELI_COUNT := 3
const CITY_HELI_ROLL_CHANCE := 0.25          ## 每个调度窗 25% 概率，保持偶遇感
const CITY_HELI_MAX_PER_RUN := 2             ## 一局最多两次
const CITY_HELI_MIN_PLAYER_DIST_PX := 6000.0 ## 至少 12km，必须从战术地图主动寻找
const CITY_HELI_MIN_EDGE_DIST_PX := 4000.0   ## 至少 8km 撤离航程，给玩家截击时间
## 全歼本次运输队的奖励：作战时间 +20s（走 survivor_mode.grant_time_extension，
## 与王牌中队全灭 +60s 同一注入点）。给的是"局内时间"而不是功勋 ——
## 玩家要有当场去打它的理由，而不是打完才发现只加了点局外货币。
const CITY_HELI_TIME_BONUS_S := 20.0

var mode: Node                 ## SurvivorMode
var _spawner: SurvivorSpawner
var _player: Aircraft
var _zone_hint: ZoneHint       ## 用于弹 toast

var _event_timer: float = 0.0
## 当前所有 ADBS 事件刷出的存活单位（供战术地图显示实时位置）
var active_units: Array[Aircraft] = []
## 本次城区直升机事件的编队与已确认击落数（全灭 → 奖励作战时间）
var _city_heli_group: Array[Aircraft] = []
var _city_heli_killed: int = 0
var _city_heli_spawn_count: int = 0

func setup(p_mode: Node, spawner: SurvivorSpawner, player: Aircraft, hint: ZoneHint) -> void:
	mode = p_mode
	_spawner = spawner
	_player = player
	_zone_hint = hint
	_city_heli_spawn_count = 0
	_event_timer = randf_range(EVENT_INTERVAL_MIN * 0.6, EVENT_INTERVAL_MAX * 0.8)
	# 开局教程：立刻把 3 架轰炸机放在玩家前方（不触发 toast）
	_spawn_tutorial_bombers()

func _physics_process(delta: float) -> void:
	if not mode or not _player or _player.is_destroyed:
		return
	# 清理已死亡/已 free 的单位（先结算直升机战果，_cleanup_units 会把尸体过滤掉）
	_track_city_heli_kills()
	_cleanup_units()

	# BOSS 阶段停止所有新随机奖励事件（城区直升机等）——
	# 已经在场上的奖励事件让它跑完，不暴力 free，符合"维持现状"原则
	# （残余单位由 spawner 的 BOSS 阶段撤离扫描接管）。
	# 闸门走 survivor_mode.is_boss_phase()（BOSS 解锁即为真）：旧实现只看
	# ZoneData.is_boss_phase()（= 玩家把 BOSS 圈设为 selected），导致 BOSS 接近的整个
	# PRE_STAGE 段还在刷直升机事件。留 _boss_spawned 兜底给没有该方法的旧调用方。
	var boss_phase: bool = mode != null and mode.has_method("is_boss_phase") \
			and bool(mode.is_boss_phase())
	var boss_spawned: bool = mode != null and "_boss_spawned" in mode \
			and bool(mode._boss_spawned)
	if boss_phase or boss_spawned:
		return

	if _city_heli_spawn_count >= CITY_HELI_MAX_PER_RUN and _city_heli_group.is_empty():
		return

	# 城区事件：每 60-120s 开一个调度窗，每窗仅 25% 概率真正生成
	_event_timer -= delta
	if _event_timer <= 0.0:
		_event_timer = randf_range(EVENT_INTERVAL_MIN, EVENT_INTERVAL_MAX)
		_trigger_city_heli_event(randf())

# ══════════════════════════════════════════════
#  教程：开局轰炸机（3 架纵阵，左右交替偏置；不弹 toast）
# ══════════════════════════════════════════════

func _spawn_tutorial_bombers() -> void:
	if not _spawner or not _player:
		return
	var fwd := Vector2(sin(_player.heading), -cos(_player.heading))
	var right := Vector2(-fwd.y, fwd.x)
	## 锚点固定在世界坐标，不再跟玩家走 —— 玩家往后退 = 真的拉开距离
	var lead_pos := TUTORIAL_BOMBER_ANCHOR
	if not MapBoundary.is_safe_inside(lead_pos, TUTORIAL_SPAWN_MARGIN_PX):
		lead_pos = MapBoundary.clamp_inside(lead_pos, TUTORIAL_SPAWN_MARGIN_PX)
	var flee_dir := fwd
	# L/R 交替纵阵偏置：[0] 中线，[1] 后一档右侧，[2] 再后一档左侧
	var offsets: Array[Vector2] = []
	for i in range(TUTORIAL_COUNT):
		var back := -fwd * TUTORIAL_COLUMN_BACK_PX * float(i)
		var side_sign := 0.0 if i == 0 else (1.0 if i % 2 == 1 else -1.0)
		offsets.append(back + right * TUTORIAL_LATERAL_PX * side_sign)
	# 教程轰炸机：不挂 TGT 标记（爱打不打；打了有额外奖励）
	for o in offsets:
		var pos: Vector2 = lead_pos + o
		var arr := _spawner.spawn_bomber_flee(pos, flee_dir, 1, false)  # 教程靶机：不带护卫
		if arr.size() > 0:
			active_units.append(arr[0])
	EventLogger.log_event("ADBS", "Tutorial",
		"%d bombers placed %.0fpx ahead (optional)" % [TUTORIAL_COUNT, TUTORIAL_LEAD_DIST_PX])

# ══════════════════════════════════════════════
#  城区直升机事件
# ══════════════════════════════════════════════

func _trigger_city_heli_event(roll: float) -> void:
	if not _spawner or not _player:
		return
	MapGeography.ensure_ready()
	if MapGeography.URBAN_DISTRICTS.is_empty():
		return
	if _city_heli_spawn_count >= CITY_HELI_MAX_PER_RUN:
		return
	# 同屏只允许一组：旧组未全灭/撤离时不覆盖其结算引用。
	if not _city_heli_group.is_empty():
		_event_timer = EVENT_DEFER_COOLDOWN
		EventLogger.log_event("ADBS", "Defer", "heli group still active, postponing")
		return
	# 冲突处理：玩家正在某个战区圈内执行任务 → 跳过，短冷却后再 roll
	if EVENT_DEFER_WHEN_IN_ZONE and _player_in_any_zone():
		_event_timer = EVENT_DEFER_COOLDOWN
		EventLogger.log_event("ADBS", "Defer", "player in-zone, skipping heli event")
		return
	# 过滤：从全图远端城区选，不在玩家附近凭空出现。
	var city_center := _pick_city_center()
	if city_center == Vector2.INF:
		_event_timer = EVENT_NO_CANDIDATE_COOLDOWN
		return
	if not city_heli_schedule_allows(roll, _city_heli_spawn_count, _city_heli_group.size()):
		EventLogger.log_event("ADBS", "ChanceMiss",
			"city heli roll %.3f >= %.2f" % [roll, CITY_HELI_ROLL_CHANCE])
		return
	# 铁则：城区中心落在玩家视野内就延迟（避免凭空出现）
	if mode and mode.has_method("is_world_pos_visible") and mode.is_world_pos_visible(city_center):
		_event_timer = EVENT_NO_CANDIDATE_COOLDOWN
		EventLogger.log_event("ADBS", "Defer", "city center visible, postponing")
		return
	var flee_dir := _direction_to_nearest_border(city_center)
	var spawned := _spawner.spawn_heli_flee(city_center, flee_dir, CITY_HELI_COUNT)
	if spawned.is_empty():
		_event_timer = EVENT_NO_CANDIDATE_COOLDOWN
		return
	_city_heli_group = spawned
	_city_heli_killed = 0
	_city_heli_spawn_count += 1
	for h in spawned:
		h.is_mission_target = true
		active_units.append(h)
	_show_toast(tr("ADBS_CITY_HELIS_FMT") % _compass_label(flee_dir), 5.0)
	EventLogger.log_event("ADBS", "CityHeli",
		"heli flock %d/%d spawned at %s fleeing %s (dist=%.0fpx)" %
			[_city_heli_spawn_count, CITY_HELI_MAX_PER_RUN, city_center,
			_compass_label(flee_dir), _player.global_position.distance_to(city_center)])

## 调度纯函数：25% 概率、整局上限 2 次、活跃组互斥。
static func city_heli_schedule_allows(roll: float, spawned_count: int, active_count: int) -> bool:
	return spawned_count < CITY_HELI_MAX_PER_RUN \
			and active_count == 0 \
			and roll >= 0.0 \
			and roll < CITY_HELI_ROLL_CHANCE

## 远端城区候选合同：距玩家 ≥12km、距边界 ≥8km、不得落入活跃战区。
static func city_heli_spawn_candidate_allowed(player_pos: Vector2, city_center: Vector2,
		in_active_zone: bool) -> bool:
	return not in_active_zone \
			and player_pos.distance_to(city_center) >= CITY_HELI_MIN_PLAYER_DIST_PX \
			and MapBoundary.distance_to_edge(city_center) >= CITY_HELI_MIN_EDGE_DIST_PX

## 指定位置是否落在任意 AVAILABLE / SELECTED 战区圈内（通用）
func _pos_in_any_zone(pos: Vector2) -> bool:
	if not mode:
		return false
	var zones: ZoneData = mode.get("_zone_data") if "_zone_data" in mode else null
	if not zones:
		return false
	for z_any in zones.get_zone_definitions():
		var z: Dictionary = z_any
		var zid: StringName = z["id"]
		var state := zones.get_state(zid)
		if state != ZoneData.State.AVAILABLE and state != ZoneData.State.SELECTED:
			continue
		var d: float = pos.distance_to(z["center"])
		if d <= float(z["radius"]):
			return true
	return false

## 玩家是否在任意 AVAILABLE / SELECTED 战区圈内（薄包装）
func _player_in_any_zone() -> bool:
	if not _player:
		return false
	return _pos_in_any_zone(_player.global_position)

## 从全图城区多边形中挑一个远离玩家、离边界有足够撤离航程、
## 且城区中心不落在任何活跃战区圈内的候选（ADBS 奖励任务只刷在战区外）。
## 失败返回 Vector2.INF
func _pick_city_center() -> Vector2:
	var pp := _player.global_position
	var candidates: Array[Vector2] = []
	for poly_any in MapGeography.URBAN_DISTRICTS:
		var poly: PackedVector2Array = poly_any
		if poly.is_empty():
			continue
		var c := _polygon_centroid(poly)
		## 铁则：远离玩家、保留截击时间，且不污染战区任务空域。
		if not city_heli_spawn_candidate_allowed(pp, c, _pos_in_any_zone(c)):
			continue
		candidates.append(c)
	if candidates.is_empty():
		return Vector2.INF
	return candidates[randi() % candidates.size()]

func _polygon_centroid(poly: PackedVector2Array) -> Vector2:
	var s := Vector2.ZERO
	for p in poly:
		s += p
	return s / poly.size()

## 城区直升机战果结算：全歼 → 作战时间 +20s。
## 用轮询而非信号，与 survivor_spawner._detect_kills 同一模式 ——
## 被击毁的机体会带着 is_destroyed=true 存活若干帧播放坠毁表演，轮询足够可靠。
## 逃出地图被回收的（instance 失效）不算战果，也不阻塞结算。
func _track_city_heli_kills() -> void:
	if _city_heli_group.is_empty():
		return
	var still_flying := 0
	for h in _city_heli_group:
		if not is_instance_valid(h):
			continue
		if h.is_destroyed:
			if not h.has_meta("adbs_heli_counted"):
				h.set_meta("adbs_heli_counted", true)
				_city_heli_killed += 1
		else:
			still_flying += 1
	if _city_heli_killed >= CITY_HELI_COUNT:
		_award_city_heli_bonus()
	elif still_flying == 0:
		# 剩下的都跑出地图了 —— 本次事件没打完，静默收摊
		_city_heli_group = []
		_city_heli_killed = 0

func _award_city_heli_bonus() -> void:
	_city_heli_group = []
	_city_heli_killed = 0
	if mode == null or not mode.has_method("grant_time_extension"):
		return
	# grant_time_extension 在 BOSS 阶段是 no-op（战区计时已冻结）。
	# 用 game_time 实际位移判断是否真给了时间 —— 没给就别弹"+20s"骗玩家。
	var before: float = float(mode.game_time)
	mode.grant_time_extension(CITY_HELI_TIME_BONUS_S)
	var granted: float = before - float(mode.game_time)
	if granted <= 0.0:
		EventLogger.log_event("ADBS", "CityHeli", "运输队全歼，但计时已冻结（BOSS 阶段）→ 无加时")
		return
	_show_toast(tr("ADBS_CITY_HELIS_CLEARED_FMT") % int(round(granted)), 4.5)
	EventLogger.log_event("ADBS", "CityHeli", "运输队全歼 → 作战时间 +%.0fs" % granted)

func _cleanup_units() -> void:
	var alive: Array[Aircraft] = []
	for u in active_units:
		if is_instance_valid(u) and not u.is_destroyed:
			alive.append(u)
	active_units = alive


## 从指定位置指向最近的地图边界（向外）的单位向量
func _direction_to_nearest_border(pos: Vector2) -> Vector2:
	var half := MapBoundary.world_half_px()
	var dx_left := pos.x - (-half)
	var dx_right := half - pos.x
	var dy_top := pos.y - (-half)
	var dy_bottom := half - pos.y
	var best := dx_left
	var dir := Vector2(-1, 0)
	if dx_right < best:
		best = dx_right
		dir = Vector2(1, 0)
	if dy_top < best:
		best = dy_top
		dir = Vector2(0, -1)
	if dy_bottom < best:
		best = dy_bottom
		dir = Vector2(0, 1)
	return dir

func _compass_label(dir: Vector2) -> String:
	if dir.x < -0.5: return "W"
	if dir.x > 0.5: return "E"
	if dir.y < -0.5: return "N"
	return "S"

# ══════════════════════════════════════════════
#  UI 辅助
# ══════════════════════════════════════════════

func _show_toast(msg: String, duration: float = 4.0) -> void:
	if _zone_hint:
		_zone_hint.show_temp(msg, duration)
