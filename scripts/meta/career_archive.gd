extends Node

## CareerArchive — 玩家生涯档案（AutoLoad；spec career-archive）
##
## 跨局持久记录生涯战绩：分机型击坠 / BOSS 接战·击败 / 通关·阵亡·撤退·停机计数，
## 并驱动两个玩法输出：BOSS 档案轮换（BossRegistry 选型的 history 源）与
## 成就解锁（v1 样板：无人机猎手 → 忠诚僚机进战区奖励池）。
##
## 入档铁律（spec §3.5，仿 AircraftCodex）：
##   - bench / boss debug 局一律不入档 —— 守卫在调用方（survivor_mode.archive_enabled()）
##   - 本类不持有任何 Node/Aircraft 引用，只存值类型（SEAM-019 免疫）
##   - 逐击杀只改内存置脏；写盘收口在低频事件（结算/BOSS/停机/成就/开局/关窗）

signal achievement_unlocked(achievement_id: String)

const SECTION_KILLS := "kills"
const SECTION_BOSS := "boss"
const SECTION_ACE := "ace"
const SECTION_RUNS := "runs"
const SECTION_ACH := "achievements"

## UAV 族 enemy_type 集合（spec §2.3；MQ-X/母舰蜂群刷出时也打 "uav" tag）
const UAV_FAMILY: Array = ["uav", "ucav", "uav_commander", "uav_laser"]
const UAV_HUNTER_THRESHOLD := 30
const ACHIEVEMENT_UAV_HUNTER := "uav_hunter"

## 存档路径（var 而非 const：无头单测注入临时路径，不碰真存档）
var config_path := "user://career.cfg"

var _air_kills: Dictionary = {}        ## enemy_type → 击坠数
var _ground_kills: int = 0             ## 地面摧毁总数（legacy 聚合，保留兼容）
var _ground_kills_by_type: Dictionary = {}  ## 地面类型 tag（sam/aa/radar）→ 摧毁数（图鉴逐型）
var _boss_encounters: Dictionary = {}  ## boss_id → 接战次数
var _boss_defeats: Dictionary = {}     ## boss_id → 击败次数
var _last_boss: String = ""            ## 轮换指针：最近一次接战的 boss_id
var _ace_encounters: Dictionary = {}   ## 王牌中队 profile id → 遭遇次数（spec ace-squadron-tier §2.7）
var _ace_defeats: Dictionary = {}      ## 王牌中队 profile id → 全灭次数（ORION：此计数即宿敌成长轴）
var _ace_first_defeat: Dictionary = {} ## 王牌中队 profile id → 首次击破日期 "YYYY-MM-DD"
var _runs_started: int = 0
var _victories: Dictionary = {}        ## map_id → 通关次数
var _deaths: int = 0
var _retreats: int = 0
var _dockings: Dictionary = {}         ## dock_kind(airfield/carrier) → 停机次数
var _achievements: Dictionary = {}     ## id → 解锁日期 "YYYY-MM-DD"
var _dirty: bool = false

func _ready() -> void:
	reload_from_disk()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()

# ── 查询 API ──

func get_air_kills(etype: String) -> int:
	return int(_air_kills.get(etype, 0))

## 分机型击坠全表快照（键 = enemy_type tag）
func get_air_kill_table() -> Dictionary:
	return _air_kills.duplicate()

## UAV 族累计击坠（成就 uav_hunter 的判定量）
func get_uav_family_kills() -> int:
	var total := 0
	for t in UAV_FAMILY:
		total += int(_air_kills.get(t, 0))
	return total

func get_ground_kills() -> int:
	return _ground_kills

## 逐型地面摧毁数（tag = "sam"/"aa"/"radar"，敌人图鉴用）。
## ⚠ 旧存档只有聚合总数、无分型数据 → 老档案的历史战绩逐型显示为 0（总数仍在）
func get_ground_kills_by_type(tag: String) -> int:
	return int(_ground_kills_by_type.get(tag, 0))

func get_boss_encounters(boss_id: String) -> int:
	return int(_boss_encounters.get(boss_id, 0))

func get_boss_defeats(boss_id: String) -> int:
	return int(_boss_defeats.get(boss_id, 0))

func has_defeated_boss(boss_id: String) -> bool:
	return get_boss_defeats(boss_id) > 0

func get_last_boss() -> String:
	return _last_boss

## ── 王牌中队（非 BOSS）档案查询（spec ace-squadron-tier §2.7）──

func get_ace_encounters(ace_id: String) -> int:
	return int(_ace_encounters.get(ace_id, 0))

func get_ace_defeats(ace_id: String) -> int:
	return int(_ace_defeats.get(ace_id, 0))

func has_defeated_ace(ace_id: String) -> bool:
	return get_ace_defeats(ace_id) > 0

func get_ace_first_defeat_date(ace_id: String) -> String:
	return String(_ace_first_defeat.get(ace_id, ""))

## ORION 宿敌成长轴（spec events/ace-orion §2.2）：被玩家击坠的生涯累计 = 全灭计数
func get_orion_kills() -> int:
	return get_ace_defeats("orion")

func get_runs_started() -> int:
	return _runs_started

func get_victories(map_id: String) -> int:
	return int(_victories.get(map_id, 0))

func get_deaths() -> int:
	return _deaths

func get_retreats() -> int:
	return _retreats

## 停机次数。kind = "airfield"/"carrier"；"" = 总数
func get_dockings(kind: String = "") -> int:
	if kind != "":
		return int(_dockings.get(kind, 0))
	var total := 0
	for k in _dockings:
		total += int(_dockings[k])
	return total

func is_achievement_unlocked(achievement_id: String) -> bool:
	return _achievements.has(achievement_id)

## BOSS 轮换的 history 快照（BossRegistry.rotation_candidates 输入；spec §3.1）
func build_boss_history() -> Dictionary:
	var defeated: Dictionary = {}
	for id in _boss_defeats:
		defeated[id] = int(_boss_defeats[id]) > 0
	return {"last": _last_boss, "defeated": defeated}

# ── 记录 API（调用方负责正式局守卫 archive_enabled()）──

## 正式局开始（低频 → 顺手落盘，兼作"上局未结算增量"的冲刷点）
func record_run_started() -> void:
	_runs_started += 1
	_dirty = true
	flush()

## 玩家小队归因的空中击坠（归因过滤在调用方；spec §3.2）。只改内存，不落盘
func record_air_kill(etype: String) -> void:
	if etype == "":
		return
	_air_kills[etype] = int(_air_kills.get(etype, 0)) + 1
	_dirty = true
	if UAV_FAMILY.has(etype):
		_check_uav_hunter()

## 敌地面单位摧毁（不归因，粗粒度；spec §2.2）。只改内存，不落盘。
## tag 为空 = 只记聚合总数（兼容旧调用）；传 tag 同时记逐型（敌人图鉴用）
func record_ground_kill(tag: String = "") -> void:
	_ground_kills += 1
	if tag != "":
		_ground_kills_by_type[tag] = int(_ground_kills_by_type.get(tag, 0)) + 1
	_dirty = true

## BOSS 接战（ENGAGED 相）：接战计数 + 轮换指针跟随事实刷出的 BOSS
func record_boss_encounter(boss_id: String) -> void:
	if boss_id == "":
		return
	_boss_encounters[boss_id] = int(_boss_encounters.get(boss_id, 0)) + 1
	_last_boss = boss_id
	_dirty = true
	flush()
	EventLogger.log_event("ARCHIVE", "BossEncounter",
		"%s (第%d次)" % [boss_id, int(_boss_encounters[boss_id])])

## BOSS 击败：下局轮换必换（spec §3.1）
func record_boss_defeat(boss_id: String) -> void:
	if boss_id == "":
		return
	_boss_defeats[boss_id] = int(_boss_defeats.get(boss_id, 0)) + 1
	_dirty = true
	flush()
	EventLogger.log_event("ARCHIVE", "BossDefeat",
		"%s (第%d次)" % [boss_id, int(_boss_defeats[boss_id])])

## 王牌中队入场（低频 → 落盘）
func record_ace_encounter(ace_id: String) -> void:
	if ace_id == "":
		return
	_ace_encounters[ace_id] = int(_ace_encounters.get(ace_id, 0)) + 1
	_dirty = true
	flush()
	EventLogger.log_event("ARCHIVE", "AceEncounter",
		"%s (第%d次)" % [ace_id, int(_ace_encounters[ace_id])])

## 王牌中队被全灭（ORION：单机击坠即全灭 → 计数即成长轴）
func record_ace_defeat(ace_id: String) -> void:
	if ace_id == "":
		return
	_ace_defeats[ace_id] = int(_ace_defeats.get(ace_id, 0)) + 1
	if not _ace_first_defeat.has(ace_id):
		_ace_first_defeat[ace_id] = Time.get_date_string_from_system()
	_dirty = true
	flush()
	EventLogger.log_event("ARCHIVE", "AceDefeat",
		"%s (第%d次)" % [ace_id, int(_ace_defeats[ace_id])])

func record_victory(map_id: String) -> void:
	var key := map_id if map_id != "" else "default"
	_victories[key] = int(_victories.get(key, 0)) + 1
	_dirty = true
	flush()

func record_death() -> void:
	_deaths += 1
	_dirty = true
	flush()

func record_retreat() -> void:
	_retreats += 1
	_dirty = true
	flush()

func record_docking(dock_kind: String) -> void:
	var key := dock_kind if dock_kind != "" else "unknown"
	_dockings[key] = int(_dockings.get(key, 0)) + 1
	_dirty = true
	flush()

# ── 成就 ──

## uav_hunter：UAV 族累计击坠达标 → 一次性解锁（幂等）+ 立即落盘 + 发信号
func _check_uav_hunter() -> void:
	if is_achievement_unlocked(ACHIEVEMENT_UAV_HUNTER):
		return
	if get_uav_family_kills() < UAV_HUNTER_THRESHOLD:
		return
	_unlock_achievement(ACHIEVEMENT_UAV_HUNTER)

func _unlock_achievement(achievement_id: String) -> void:
	if _achievements.has(achievement_id):
		return
	_achievements[achievement_id] = Time.get_date_string_from_system()
	_dirty = true
	flush()
	EventLogger.log_event("ARCHIVE", "Achievement", achievement_id)
	achievement_unlocked.emit(achievement_id)

# ── 持久化 ──

## 从盘上重读（_ready / 单测注入路径后调用）。文件缺失 = 全零新档案
func reload_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	_air_kills = _as_dict(cfg.get_value(SECTION_KILLS, "air", {}))
	_ground_kills = maxi(0, int(cfg.get_value(SECTION_KILLS, "ground_total", 0)))
	_ground_kills_by_type = _as_dict(cfg.get_value(SECTION_KILLS, "ground_by_type", {}))
	_boss_encounters = _as_dict(cfg.get_value(SECTION_BOSS, "encounters", {}))
	_boss_defeats = _as_dict(cfg.get_value(SECTION_BOSS, "defeats", {}))
	_last_boss = String(cfg.get_value(SECTION_BOSS, "last_encountered", ""))
	_ace_encounters = _as_dict(cfg.get_value(SECTION_ACE, "encounters", {}))
	_ace_defeats = _as_dict(cfg.get_value(SECTION_ACE, "defeats", {}))
	_ace_first_defeat = _as_dict(cfg.get_value(SECTION_ACE, "first_defeat", {}))
	_runs_started = maxi(0, int(cfg.get_value(SECTION_RUNS, "started", 0)))
	_victories = _as_dict(cfg.get_value(SECTION_RUNS, "victories", {}))
	_deaths = maxi(0, int(cfg.get_value(SECTION_RUNS, "deaths", 0)))
	_retreats = maxi(0, int(cfg.get_value(SECTION_RUNS, "retreats", 0)))
	_dockings = _as_dict(cfg.get_value(SECTION_RUNS, "dockings", {}))
	_achievements = _as_dict(cfg.get_value(SECTION_ACH, "unlocked", {}))
	_dirty = false

## 脏则落盘（写盘唯一出口）
func flush() -> void:
	if not _dirty:
		return
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_KILLS, "air", _air_kills)
	cfg.set_value(SECTION_KILLS, "ground_total", _ground_kills)
	cfg.set_value(SECTION_KILLS, "ground_by_type", _ground_kills_by_type)
	cfg.set_value(SECTION_BOSS, "encounters", _boss_encounters)
	cfg.set_value(SECTION_BOSS, "defeats", _boss_defeats)
	cfg.set_value(SECTION_BOSS, "last_encountered", _last_boss)
	cfg.set_value(SECTION_ACE, "encounters", _ace_encounters)
	cfg.set_value(SECTION_ACE, "defeats", _ace_defeats)
	cfg.set_value(SECTION_ACE, "first_defeat", _ace_first_defeat)
	cfg.set_value(SECTION_RUNS, "started", _runs_started)
	cfg.set_value(SECTION_RUNS, "victories", _victories)
	cfg.set_value(SECTION_RUNS, "deaths", _deaths)
	cfg.set_value(SECTION_RUNS, "retreats", _retreats)
	cfg.set_value(SECTION_RUNS, "dockings", _dockings)
	cfg.set_value(SECTION_ACH, "unlocked", _achievements)
	cfg.save(config_path)
	_dirty = false

## 调试/主菜单删存档：清内存 + 重写空档案（单删 cfg 不够，内存态会写回）
func debug_reset() -> void:
	_air_kills = {}
	_ground_kills = 0
	_ground_kills_by_type = {}
	_boss_encounters = {}
	_boss_defeats = {}
	_last_boss = ""
	_ace_encounters = {}
	_ace_defeats = {}
	_ace_first_defeat = {}
	_runs_started = 0
	_victories = {}
	_deaths = 0
	_retreats = 0
	_dockings = {}
	_achievements = {}
	_dirty = true
	flush()

static func _as_dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}
