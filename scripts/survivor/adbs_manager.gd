class_name AdbsManager
extends Node

## ADBS（Adds / 随机事件）管理器
##
## 负责触发与调度：
##   1. **开局教程**：game_time ≈ 5s 时在玩家正前方刷 2 架轰炸机，背对玩家逃离
##      （"第一桶金"教学）
##   2. **城区直升机事件**：周期性（60-120s）在随机城区刷一队 CH-47，飞向最近地图边界
##      弹出 HUD 提示。若玩家不理会，单位逃出地图后事件自动结束（靠 despawn_after meta）
##   3. （未来可扩展：空袭预警 / 王牌单发 / 护航等）
##
## 事件单位一律走 Adds 族群系统（不占 Token，逃离即消失），玩家击坠给高 XP 奖励。

## ── 事件调度 ──
const EVENT_INTERVAL_MIN := 60.0
const EVENT_INTERVAL_MAX := 120.0
const EVENT_DEFER_COOLDOWN := 30.0          ## 被跳过（玩家在战区内）后多久再 roll
const EVENT_NO_CANDIDATE_COOLDOWN := 25.0   ## 附近没合适城区时多久再 roll
const EVENT_SPAWN_MAX_DIST_PX := 4000.0     ## 事件生成点距玩家上限（≈8km）
const EVENT_DEFER_WHEN_IN_ZONE := true      ## 玩家在战区圆内时不刷支线

## ── 教程轰炸机 ──
## 距离略大于玩家默认雷达锁定范围（F-16 ≈ 1667 px），玩家要往前飞才进入锁定
## 但又不会远到看不到 / 飞不过去
const TUTORIAL_LEAD_DIST_PX := 3000.0       ## 第 0 架距玩家前方距离（≈6km；保留给日志用）
const TUTORIAL_SPAWN_MARGIN_PX := 1500.0    ## 防越界夹紧余量
const TUTORIAL_LATERAL_PX := 320.0          ## 左右交替偏置
const TUTORIAL_COLUMN_BACK_PX := 550.0      ## 每后一档的距离
const TUTORIAL_COUNT := 3                   ## 轰炸机数量
## 教程轰炸机锚点（固定世界坐标，与玩家起始点解耦；朝南逃离，因此置于原点北侧）
const TUTORIAL_BOMBER_ANCHOR := Vector2(0.0, 3000.0)

## ── 城区直升机事件 ──
const CITY_HELI_COUNT := 3

var mode: Node                 ## SurvivorMode
var _spawner: SurvivorSpawner
var _player: Aircraft
var _zone_hint: ZoneHint       ## 用于弹 toast

var _event_timer: float = 0.0
## 当前所有 ADBS 事件刷出的存活单位（供战术地图显示实时位置）
var active_units: Array[Aircraft] = []

func setup(p_mode: Node, spawner: SurvivorSpawner, player: Aircraft, hint: ZoneHint) -> void:
	mode = p_mode
	_spawner = spawner
	_player = player
	_zone_hint = hint
	_event_timer = randf_range(EVENT_INTERVAL_MIN * 0.6, EVENT_INTERVAL_MAX * 0.8)
	# 开局教程：立刻把 3 架轰炸机放在玩家前方（不触发 toast）
	_spawn_tutorial_bombers()

func _physics_process(delta: float) -> void:
	if not mode or not _player or _player.is_destroyed:
		return
	# 清理已死亡/已 free 的单位
	_cleanup_units()

	# BOSS 阶段（玩家在战术地图选了 BOSS）停止所有新随机奖励事件 ——
	# 已经在场上的奖励事件让它跑完，不暴力 free，符合"维持现状"原则。
	# 同时兼容旧的 _boss_spawned 兜底（极少数路径绕过 select_zone 也覆盖到）
	var boss_phase: bool = mode != null and "_zone_data" in mode \
			and mode._zone_data != null and mode._zone_data.is_boss_phase()
	var boss_spawned: bool = mode != null and "_boss_spawned" in mode \
			and bool(mode._boss_spawned)
	if boss_phase or boss_spawned:
		return

	# 城区事件：每 60-120s 一次
	_event_timer -= delta
	if _event_timer <= 0.0:
		_event_timer = randf_range(EVENT_INTERVAL_MIN, EVENT_INTERVAL_MAX)
		_trigger_city_heli_event()

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
		var arr := _spawner.spawn_bomber_flee(pos, flee_dir, 1)
		if arr.size() > 0:
			active_units.append(arr[0])
	EventLogger.log_event("ADBS", "Tutorial",
		"%d bombers placed %.0fpx ahead (optional)" % [TUTORIAL_COUNT, TUTORIAL_LEAD_DIST_PX])

# ══════════════════════════════════════════════
#  城区直升机事件
# ══════════════════════════════════════════════

func _trigger_city_heli_event() -> void:
	if not _spawner or not _player:
		return
	if MapGeography.URBAN_DISTRICTS.is_empty():
		return
	# 冲突处理：玩家正在某个战区圈内执行任务 → 跳过，短冷却后再 roll
	if EVENT_DEFER_WHEN_IN_ZONE and _player_in_any_zone():
		_event_timer = EVENT_DEFER_COOLDOWN
		EventLogger.log_event("ADBS", "Defer", "player in-zone, skipping heli event")
		return
	# 过滤：只从玩家附近的城区中选
	var city_center := _pick_nearby_city_center()
	if city_center == Vector2.INF:
		_event_timer = EVENT_NO_CANDIDATE_COOLDOWN
		return
	# 铁则：城区中心落在玩家视野内就延迟（避免凭空出现）
	if mode and mode.has_method("is_world_pos_visible") and mode.is_world_pos_visible(city_center):
		_event_timer = EVENT_NO_CANDIDATE_COOLDOWN
		EventLogger.log_event("ADBS", "Defer", "city center visible, postponing")
		return
	var flee_dir := _direction_to_nearest_border(city_center)
	var spawned := _spawner.spawn_heli_flee(city_center, flee_dir, CITY_HELI_COUNT)
	for h in spawned:
		h.is_mission_target = true
		active_units.append(h)
	_show_toast(tr("ADBS_CITY_HELIS_FMT") % _compass_label(flee_dir), 5.0)
	EventLogger.log_event("ADBS", "CityHeli",
		"heli flock spawned at %s fleeing %s (dist=%.0fpx)" %
			[city_center, _compass_label(flee_dir), _player.global_position.distance_to(city_center)])

## 指定位置是否落在任意 AVAILABLE / SELECTED 战区圈内（通用）
func _pos_in_any_zone(pos: Vector2) -> bool:
	if not mode:
		return false
	var zones: ZoneData = mode.get("_zone_data") if "_zone_data" in mode else null
	if not zones:
		return false
	for z_any in ZoneData.ZONES:
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

## 从所有城区多边形中挑一个距玩家 ≤ EVENT_SPAWN_MAX_DIST_PX 的，
## 且城区中心本身不落在任何活跃战区圈内（ADBS 奖励任务只刷在战区外）。
## 失败返回 Vector2.INF
func _pick_nearby_city_center() -> Vector2:
	var pp := _player.global_position
	var candidates: Array[Vector2] = []
	for poly_any in MapGeography.URBAN_DISTRICTS:
		var poly: PackedVector2Array = poly_any
		if poly.is_empty():
			continue
		var c := _polygon_centroid(poly)
		if pp.distance_to(c) > EVENT_SPAWN_MAX_DIST_PX:
			continue
		## 铁则：刷怪点落在任何活跃战区圆内 → 跳过，避免奖励任务污染战区任务空域
		if _pos_in_any_zone(c):
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
