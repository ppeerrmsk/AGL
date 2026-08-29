class_name BattlefieldFlow
extends RefCounted

## 生存模式战场流程的局内权威状态。
##
## SurvivorMode 仍负责场景对象、信号、UI 与事件启动；本类只负责会跨多个调用点的
## 游戏规则状态：净时间轴、战区/BOSS 阶段、战区关闭事务、王牌固定槽与宿敌一次性门。

enum Phase {
	WARZONE,
	BOSS,
}

const DEFAULT_WARZONE_DURATION_S := 600.0

## 只跨“同一客户端会话”保留，用于避免连续两局第一支王牌相同；不属于单局状态。
static var _previous_ace_first: String = ""

var game_time: float = 0.0
var warzone_duration_s: float = DEFAULT_WARZONE_DURATION_S
var phase: Phase = Phase.WARZONE

var _ace_slots_opened: int = 0
var _ace_squads_used: Dictionary = {}
var _ace_run_order: Array = []
var _orion_spawned: bool = false


func reset_run(duration_s: float = DEFAULT_WARZONE_DURATION_S) -> void:
	game_time = 0.0
	warzone_duration_s = maxf(0.0, duration_s)
	phase = Phase.WARZONE
	_ace_slots_opened = 0
	_ace_squads_used.clear()
	_ace_run_order.clear()
	_orion_spawned = false


func set_game_time(value: float) -> void:
	game_time = maxf(0.0, value)


func set_warzone_duration(value: float) -> void:
	warzone_duration_s = maxf(0.0, value)


func is_boss_phase(zones: ZoneData, boss_spawned: bool = false) -> bool:
	if phase == Phase.BOSS or boss_spawned:
		return true
	return zones != null and (zones.is_boss_phase() or zones.boss_unlocked)


func advance_time(delta: float, blocked: bool, zones: ZoneData,
		boss_spawned: bool = false) -> void:
	if blocked or is_boss_phase(zones, boss_spawned):
		return
	game_time += maxf(0.0, delta)


func remaining_s() -> float:
	return maxf(0.0, warzone_duration_s - game_time)


func apply_time_cost(seconds: float) -> float:
	if phase != Phase.WARZONE:
		return 0.0
	var before := game_time
	game_time = minf(game_time + maxf(0.0, seconds), warzone_duration_s)
	return game_time - before


func grant_time_extension(seconds: float, zones: ZoneData,
		boss_spawned: bool = false) -> float:
	if is_boss_phase(zones, boss_spawned):
		return 0.0
	var before := game_time
	game_time = maxf(0.0, game_time - maxf(0.0, seconds))
	return before - game_time


## 战区超时的唯一事务入口。phase 先锁存为 BOSS，避免取消任务的同步回调重入后重复结算。
func close_warzone_if_due(zones: ZoneData, missions: ZoneMission) -> bool:
	if phase != Phase.WARZONE or zones == null or game_time < warzone_duration_s:
		return false
	phase = Phase.BOSS
	zones.phase_ended = true
	if missions != null and is_instance_valid(missions):
		missions.cancel_all_zone_missions()
	zones.lock_all_open_zones_except(&"")
	if zones.selected_id != &"" and zones.selected_id != &"BOSS":
		zones.set_state(zones.selected_id, ZoneData.State.LOCKED)
		zones.selected_id = &""
	zones.finalize_boss_placement()
	zones.boss_unlocked = true
	zones.set_state(&"BOSS", ZoneData.State.AVAILABLE)
	return true


func prepare_ace_run_order(rng: RandomNumberGenerator) -> bool:
	if not _ace_run_order.is_empty():
		return false
	_ace_run_order = AceSquadProfiles.build_run_order(rng, _previous_ace_first)
	if not _ace_run_order.is_empty():
		_previous_ace_first = String(_ace_run_order[0])
	return true


func ace_run_order() -> Array:
	return _ace_run_order.duplicate()


## 锁存已到达的固定时间槽，并原子认领下一支可用王牌；空串表示本帧不应生成。
func claim_next_ace_profile(rng: RandomNumberGenerator, occupied: bool = false) -> String:
	_ace_slots_opened = AceSquadProfiles.advance_scheduled_wave_count(
		_ace_slots_opened, game_time, warzone_duration_s)
	if occupied or _ace_squads_used.size() >= _ace_slots_opened:
		return ""
	var candidates: Array = []
	for id in AceSquadProfiles.pool_at(game_time):
		if not _ace_squads_used.has(id):
			candidates.append(id)
	if candidates.is_empty():
		return ""
	prepare_ace_run_order(rng)
	var pick := ""
	for id in _ace_run_order:
		if candidates.has(id):
			pick = String(id)
			break
	if pick.is_empty():
		pick = String(candidates[0])
	_ace_squads_used[pick] = true
	return pick


func ace_slots_opened() -> int:
	return _ace_slots_opened


func ace_squads_used_count() -> int:
	return _ace_squads_used.size()


func claim_orion_if_due(trigger_s: float) -> bool:
	if _orion_spawned or phase != Phase.WARZONE or game_time < trigger_s:
		return false
	_orion_spawned = true
	return true
