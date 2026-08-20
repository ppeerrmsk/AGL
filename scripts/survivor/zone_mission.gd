class_name ZoneMission
extends Node

const ZONE_ATMOSPHERE_SCRIPT := preload("res://scripts/survivor/zone_atmosphere_combat.gd")
const TIER3_SUPER_CANNON_SCRIPT := preload("res://scripts/survivor/tier3_super_cannon_part.gd")
const TIER3_SIEGE_TANK_SCRIPT := preload("res://scripts/survivor/tier3_siege_tank.gd")

## 战区任务执行器
##
## 职责拆分：
##   1. **静态刷怪**：当前 AVAILABLE 的奖励/护送战区先广播并等待 6 秒，再把
##      TGT + 驻守单位刷出来。玩家没来也一直存在。
##   2. **任务触发（双通道）**：满足任一条件即激活任务
##        - A. 玩家进入战区圆
##        - B. 玩家在圈外就击中了 TGT —— 既然能打到，就算玩家正在做这个
##             任务，击杀也正常结算，不做血量手脚
##      两条通道都走 `_should_trigger`，未来要加新触发类型就改这一处。
##   3. **完成判定**：已 triggered 的战区内所有已刷 TGT 单位都被击毁 →
##      发出 mission_completed 信号。

signal mission_triggered(zone_id: StringName)  ## 玩家进入 SELECTED 战区
signal mission_completed(zone_id: StringName)
signal mission_failed(zone_id: StringName, reason: String)
signal mission_spawn_announced(zone_id: StringName, mission_type: String)
signal tier3_threat_changed(zone_id: StringName, profile: StringName, active: bool)

const SAM_COUNT := 3
const AA_COUNT := 3
## 机场解放战区地面防空编成（spec airfield-liberation-zones §2.2）：固定 1 SAM + 2 AA
const AIRFIELD_SAM_COUNT := 1
const AIRFIELD_AA_COUNT := 2
const SCATTER_RADIUS_SCALE := 0.85      ## 散布半径 = zone.radius × 此值
const MIN_UNIT_SEPARATION_PX := 650.0   ## 地面单位最小间距（≈1.3km）
const MIN_ROAD_DISTANCE_PX := 180.0     ## 距道路/高速的最小距离（≈360m）
const MAX_SAMPLE_ATTEMPTS := 80         ## 每个单位最多尝试 N 次随机位置
const MISSION_SPAWN_RADIO_LEAD_S := 6.0
## 玩家已按 Tab 选中任务并抵达战区边缘时，不能让“生成区碰到视野”安全门永久
## 卡住实体。空中敌人统一从地图边界外入场；地面/舰船静态目标保持既有可达性语义。
const VISIBLE_SPAWN_RECOVERY_APPROACH_PX := 400.0
## 战区空军进入巡逻环外沿后结束 ingress 冻结豁免；之后恢复普通 zone_air LOD。
const ZONE_AIR_INGRESS_ARRIVE_BAND_PX := 320.0
const BOMBER_ESCORT_COUNT := 3
const BOMBER_ESCORT_FIGHTER_COUNT := 2
const BOMBER_ESCORT_BOMBER_HP := 30.0
const BOMBER_ESCORT_TARGET_HP := 75.0
const BOMBER_ESCORT_RADIUS_PX := 900.0
const BOMBER_ESCORT_DEADLINE_S := 150.0
const BOMBER_ESCORT_ENTRY_OUTSET_PX := 1200.0
const BOMBER_ESCORT_PLAYER_CLEARANCE_PX := 5000.0
const BOMBER_ESCORT_INGRESS_LEG_PX := 12500.0
const BOMBER_ESCORT_LINEUP_PX := 1500.0
const BOMBER_ESCORT_EXIT_PX := 3500.0
const BOMBER_ESCORT_CACHE_TICK_S := 0.1
const BOMBER_ESCORT_MIN_RESPONSE_LEVEL := 5
const BOMBER_ESCORT_THREAT_BUDGET_BASE := 24
const BOMBER_ESCORT_THREAT_BUDGET_PER_STAR := 4
const BOMBER_ESCORT_THREAT_BUDGET_PER_WINGMAN := 3
const BOMBER_ESCORT_PLAYER_SUPPORT_RADIUS_PX := 3500.0
const BOMBER_ESCORT_RESPONSE_LAUNCH_PROGRESS := 0.06
const BOMBER_ESCORT_RESPONSE_ARM_PROGRESS := 0.32
const BOMBER_ESCORT_RESERVE_TRIGGER_PROGRESS := 0.40
const BOMBER_ESCORT_UNATTENDED_ABORT_PROGRESS := 0.58
## 专用护送航线目录：普通 A–G 只借用任务/奖励槽位，不再提供目标地理。
## axis 是同一条航线的正向进攻轴；运行时只允许反转该轴来避开玩家，不临时换线。
const BOMBER_ESCORT_ROUTE_CATALOG: Array[Dictionary] = [
	{"id": &"YOKOHAMA_FREIGHT", "target": Vector2(-7600.0, -3600.0), "axis": Vector2(1.0, 0.12)},
	{"id": &"TOKYO_SOUTH", "target": Vector2(-3200.0, -9300.0), "axis": Vector2(0.18, 1.0)},
	{"id": &"CHIBA_PORT_REAR", "target": Vector2(7100.0, 200.0), "axis": Vector2(-1.0, 0.18)},
	{"id": &"BOSO_WEST", "target": Vector2(8200.0, 7200.0), "axis": Vector2(-0.22, -1.0)},
	{"id": &"MIURA_INLAND", "target": Vector2(-7500.0, 5800.0), "axis": Vector2(1.0, -0.5)},
	{"id": &"CHIBA_EAST", "target": Vector2(7431.663, 1329.134), "axis": Vector2(-1.0, -0.08)},
	{"id": &"HANEDA_INLAND", "target": Vector2(-500.0, -7600.0), "axis": Vector2(0.35, 1.0)},
]
const BOMBER_ESCORT_ROUTE_SLOT_IDS: Array[StringName] = [&"A", &"B", &"C", &"D", &"E", &"F", &"G"]

## 战区第三方支援（spec zone-air-support-naval-safety）：每项权益每局首次合资格 ACTIVE 后入场。
## 对空按星级生成 2/3/4 架 F-86；非机场对地固定生成 2 架 A-10；结束后物理飞出地图。
enum SupportPhase { INGRESS_PENDING, ON_STATION, EGRESS }
const SUPPORT_TICK_S := 0.5
const SUPPORT_SPAWN_CANDIDATES := 8
const SUPPORT_SPAWN_MIN_RADIUS_PX := 2400.0
const SUPPORT_SPAWN_RADIUS_FRAC := 0.9
const SUPPORT_SPAWN_VISUAL_REACH_PX := 600.0
const SUPPORT_ORBIT_MIN_RADIUS_PX := 1200.0
const SUPPORT_ORBIT_RADIUS_FRAC := 0.48
const SUPPORT_ZONE_LEASH_EXTRA_PX := 1500.0
const SUPPORT_EXIT_OUTSET_PX := 1200.0
const SUPPORT_FREE_OUTSET_PX := 800.0
const SUPPORT_WITHDRAW_REENGAGE_S := 4.0
const SUPPORT_FIGHTER_TYPE := SurvivorSpawner.EnemyType.F86
const SUPPORT_GROUND_COUNT := 2
const SUPPORT_A10_ALTITUDE_M := 3200.0
const _SUPPORT_AIRCRAFT_SCENE := preload("res://scenes/aircraft.tscn")
const _SUPPORT_A10_PARAMS := preload("res://resources/playable_a10_base.tres")

## 雷达站 TGT（2026-07-06 任务丰富化）：★★+ 地面战区附带，datalink 共享 20km 感知
const _RADAR_SCENE := preload("res://scenes/radar_station.tscn")
const _RADAR_PARAMS := preload("res://resources/radar_station_params.tres")
const _AIRBURST_AA_SCENE := preload("res://scenes/airburst_aa_unit.tscn")
const _AIRBURST_AA_PARAMS := preload("res://resources/airburst_aa_params.tres")
const _TIER3_GROUND_BASE_PARAMS := preload("res://resources/aa_gun_params.tres")

const TIER3_DESERT_MAP_ID := "desert_railway_preview"
const TIER3_VLS_RANGE_M := 40000.0
const TIER3_VLS_LIFETIME_S := 65.0
const TIER3_CANNON_BASE_HP := 220.0
const TIER3_CANNON_BODY_HP := 320.0
const TIER3_SIEGE_TANK_HP := 600.0
const TIER3_CANNON_PART_OFFSETS: Array[Vector2] = [
	Vector2(-85.0, -85.0), Vector2(85.0, -85.0),
	Vector2(-85.0, 85.0), Vector2(85.0, 85.0), Vector2.ZERO,
]

var mode: Node
var _zones: ZoneData
var _player: Aircraft
var _sam_scene: PackedScene
var _aa_scene: PackedScene
var _sam_params: Resource
var _aa_params: Resource
var _bullet_manager: Node2D
var _missile_manager: Node2D
var _spawner: SurvivorSpawner  ## 用于创建空战中队敌机（复用 _create_enemy 工厂）
## preload 实例，避免全局 class cache 尚未刷新时依赖 class_name 解析。
var _zone_atmosphere: Node2D

## zone_id → Array[Node]（任务目标：SAM/AA 或 空战中队，攻克判定依据）
var _spawned_zones: Dictionary = {}
## zone_id → Array[Aircraft]（驻守敌机：空中守卫，不是任务目标，攻克后撤离）
var _garrison_zones: Dictionary = {}
## 玩家是否至少进入过该战区一次（无论是否通过 Tab 选中）
var _triggered_zones: Dictionary = {}
## 已发完成信号的战区（防止重复）
var _completed_zones: Dictionary = {}
## 已发失败信号的战区（防止 timeout / 编队全灭等条件同帧重复结算）。
var _failed_zones: Dictionary = {}
## zone_id → 广播后剩余生成延迟；只在正式局用于奖励/护送目标。
var _spawn_lead_timers: Dictionary = {}
## zone_id → {target, route, controller}; 圆心读取 BomberMission 的 10Hz 缓存。
var _bomber_escort_runs: Dictionary = {}
## 待撤离单位：等玩家视线外才 queue_free（铁则：敌人不在玩家画面里消失）
## 由 _despawn_garrison / refresh_active_zones_for_level 等共用
## （BOSS 阶段清场已改由 survivor_spawner._update_boss_phase_purge 统一负责，不再走本队列）
var _pending_despawn: Array = []
## 支援飞行队生命周期。允许旧队 EGRESS 时同战区重开并生成新队，故用 generation id
## 区分，而不是只存 zone_id → members。
var _support_flights: Array[Dictionary] = []
var _active_support_by_zone: Dictionary = {}  ## zone_id → generation id
var _support_generation: int = 0
var _support_tick_accum: float = 0.0
var _bomber_cache_accum: float = 0.0
## 每项战区支援权益每局只出动一次；fighter / attack 分账，避免互相吞额度。
var _support_dispatched_kinds: Dictionary = {}
## 普通地图每个战区只抽一次；刷新/安全降级不得让气氛层反复出现或消失。
var _zone_atmosphere_enabled: Dictionary = {}
var _force_all_zone_atmosphere := false
## F6 专用：zone_id → super_cannon / siege_tank；空或 auto 服从正式地图 profile。
var _debug_tier3_profile_by_zone: Dictionary = {}
var _tier3_sources_by_zone: Dictionary = {} ## zone_id → {profile, sources, active}
var _tier3_source_tick_s := 0.0

func setup(p_mode: Node, zones: ZoneData, player: Aircraft,
		sam_scene: PackedScene, sam_params: Resource,
		aa_scene: PackedScene, aa_params: Resource,
		bullet_mgr: Node2D, missile_mgr: Node2D,
		spawner: SurvivorSpawner, force_all_zone_atmosphere: bool = false) -> void:
	mode = p_mode
	_zones = zones
	_player = player
	_sam_scene = sam_scene
	_sam_params = sam_params
	_aa_scene = aa_scene
	_aa_params = aa_params
	_bullet_manager = bullet_mgr
	_missile_manager = missile_mgr
	_spawner = spawner
	_force_all_zone_atmosphere = force_all_zone_atmosphere
	_zone_atmosphere = ZONE_ATMOSPHERE_SCRIPT.new()
	_zone_atmosphere.name = "ZoneAtmosphereCombat"
	add_child(_zone_atmosphere)
	_zone_atmosphere.setup(mode, spawner)

func _physics_process(delta: float) -> void:
	if not _zones or not _player:
		return
	if _zone_atmosphere != null:
		_zone_atmosphere.update(delta, _player)
	_update_tier3_source_states(delta)

	# 每帧处理待撤离队列：单位飘到视线外就 free（与 BOSS 阶段共用机制）
	if not _pending_despawn.is_empty():
		_flush_pending_despawn()
	# 支援撤离必须在 BOSS 闸门之前继续推进，否则战区阶段结束后绿色飞机会冻结在场内。
	_update_air_support(delta)

	# BOSS 阶段：常规战区 A/B/C/D 任务全部停止（不再刷怪、不再触发、不再判定完成）
	# 闸门走 survivor_mode.is_boss_phase()（BOSS 解锁即为真，不必等玩家选中 BOSS 圈）。
	# 残余单位的清场【单一归属】= survivor_spawner._update_boss_phase_purge：
	# 敌机物理撤离出图、舰船原样保留。本类不再自己 despawn 战区单位
	# （旧行为会把战区舰船也一起偷偷 free，与"战区里的船保留"冲突）。
	if _is_boss_phase():
		return

	# 1. 为所有当前 AVAILABLE/SELECTED 的战区确保已刷怪
	_ensure_spawned_for_active_zones(delta)
	_update_bomber_escort_caches(delta)

	if _player.is_destroyed:
		return

	# 2. 遍历所有"玩家可见"（AVAILABLE / SELECTED）的战区：
	#    - 玩家进入过 → 记录 triggered（无需 Tab 选中）
	#    - 已 triggered 且全灭 → 发完成信号
	for z_any in ZoneData.ZONES:
		var z: Dictionary = z_any
		var zid: StringName = z["id"]
		var state := _zones.get_state(zid)
		if state != ZoneData.State.AVAILABLE and state != ZoneData.State.SELECTED:
			continue
		if _completed_zones.has(zid):
			continue
		# 首次触发：激活任务 + 给该战区已刷的单位打 TGT
		# 触发条件见类顶注释（模块化：进入 / 交火 任一满足）
		if not _triggered_zones.has(zid):
			if _should_trigger(zid, z):
				_triggered_zones[zid] = true
				_mark_as_target(_spawned_zones.get(zid, []))
				if _zones.get_mission_type(zid) == "bomber_escort":
					_start_bomber_escort(zid)
				_start_air_support_if_needed(zid, z)
				mission_triggered.emit(zid)
		# 已触发 → 查完成
		if _triggered_zones.has(zid):
			if _all_zone_units_destroyed(zid):
				_completed_zones[zid] = true
				_despawn_garrison(zid)      ## 撤离驻守敌机
				_begin_air_support_egress(zid, "mission completed")
				mission_completed.emit(zid)

# ══════════════════════════════════════════════
#  静态刷怪
# ══════════════════════════════════════════════

## 对 AVAILABLE / SELECTED（即"玩家能看到在地图上的"）战区，
## 如果还没刷过地面单位，就刷一次。
func _ensure_spawned_for_active_zones(delta: float = 0.0) -> void:
	for z in ZoneData.ZONES:
		var zid: StringName = z["id"]
		var state := _zones.get_state(zid)
		# 只给"玩家可见的"战区（AVAILABLE/SELECTED）刷怪，不给 LOCKED/CLEARED 刷
		if state != ZoneData.State.AVAILABLE and state != ZoneData.State.SELECTED:
			_spawn_lead_timers.erase(zid)
			continue
		# 以前这里有"AVAILABLE + 全灭 → 自动清数据重刷"的分支，
		# 但它会在玩家打完最后一个 TGT 的当帧先于完成判定跑一遍，
		# 把 _triggered_zones / _completed_zones 擦掉 → mission_completed 永远不 emit
		# → 奖励不发，紧接着又刷了一队让玩家以为"任务重复了"。
		# 现在改成：战区重开的残留清理由 reset_zone() 在 mark_cleared 之后主动调用，
		# 这里只负责"没刷过就刷一次"。
		if _spawned_zones.has(zid):
			_spawn_lead_timers.erase(zid)
			continue
		var mission_type := _zones.get_mission_type(zid)
		if _requires_spawn_announcement(zid, mission_type):
			if not _spawn_lead_timers.has(zid):
				_spawn_lead_timers[zid] = MISSION_SPAWN_RADIO_LEAD_S
				mission_spawn_announced.emit(zid, mission_type)
				continue
			var remaining := maxf(float(_spawn_lead_timers[zid]) - delta, 0.0)
			_spawn_lead_timers[zid] = remaining
			if remaining > 0.0:
				continue
		# 铁则：战区**生成半径**与玩家视野有重叠时推迟刷新（下帧再试）
		# 只测中心点远远不够 —— 空中中队生成环离中心 720px、陆基单位散布到 radius×0.85，
		# 所以只要战区可能刷出的任何单位会落在屏幕里就往后推
		if mode and mode.has_method("is_world_pos_visible"):
			var spawn_reach: float = float(z["radius"]) * SCATTER_RADIUS_SCALE
			var zone_center := _zones.get_zone_center(zid)
			if mode.is_world_pos_visible(zone_center, spawn_reach):
				var player_distance := _player.global_position.distance_to(zone_center)
				var entered_zone := player_distance <= float(z["radius"])
				var selected_at_edge := state == ZoneData.State.SELECTED \
						and player_distance <= float(z["radius"]) \
							+ VISIBLE_SPAWN_RECOVERY_APPROACH_PX
				if not entered_zone and not selected_at_edge:
					continue
				# 所有空中敌机都从地图边界外进场；静态目标沿用既有死锁恢复语义。
				EventLogger.log_event("ZONE", "VisibleSpawnRecovery",
					"id=%s state=%d mission=%s distance=%.0f radius=%.0f air_ingress=edge" % [
						zid, state, mission_type, player_distance, float(z["radius"])])
		# 倒计时归零后若仍被可见性门挡住，保留 0 秒计时器，避免每帧重开 6 秒并重复播报。
		_spawn_lead_timers.erase(zid)
		_spawn_zone_units(zid, z)

func _requires_spawn_announcement(zone_id: StringName, mission_type: String) -> bool:
	if mode != null and "_bench_mode" in mode and bool(mode.get("_bench_mode")):
		return false
	return mission_type == "bomber_escort" or not _zones.get_reward(zone_id).is_empty()

func _spawn_zone_units(zone_id: StringName, zone: Dictionary) -> void:
	# runtime mission_type（可能被 zone_data 动态滚过：ground / squadron / air / naval / airfield）
	var mission_type: String = _zones.get_mission_type(zone_id) if _zones else zone.get("mission_type", "ground")
	# 最后一道防线：若 mission_type 是 ground 但战区几乎没有陆地（可能是旧存档、
	# 基础定义改成"海上"战区、或采样抖动），改为空战中队，避免 SAM/AA 刷到海面
	if mission_type == "ground" and _zones and not ZoneData.zone_has_land(zone_id):
		mission_type = "squadron"
		_zones.set_mission_type(zone_id, "squadron")
		EventLogger.log_event("ZONE", "OverrideGroundToAir",
			"id=%s reason=water_zone" % [zone_id])
	# 机场解放战区（spec airfield-liberation-zones §2.3）：首刷时按当前热度定档，
	# 使战术地图星级 / 升空迎战规模 / 机型选型三者一致。
	if mission_type == "airfield" and _zones:
		var star := _airfield_difficulty_from_heat()
		_zones.set_airfield_difficulty(zone_id, star)
	match mission_type:
		"bomber_escort":
			_prepare_bomber_escort(zone_id, zone)
		"air", "squadron":
			_spawn_air_squadron(zone_id, zone)
		"naval":
			# 水域硬闸：完整舰队/缩编/单旗舰都找不到全水解时，零舰船落地并退化为空战。
			if not _spawn_naval_fleet(zone_id, zone):
				mission_type = "squadron"
				if _zones:
					_zones.set_mission_type(zone_id, mission_type)
				_spawn_air_squadron(zone_id, zone)
		"airfield":
			_spawn_airfield_ground(zone_id, zone)
		_:
			_spawn_ground_garrison(zone_id, zone)
	# 所有战区：按难度刷驻守敌机（守卫者，非 TGT，攻克后撤离）
	# naval 任务不加空中驻守（玩家专心打船）
	if mission_type != "naval":
		_spawn_zone_defenders(zone_id, zone, mission_type)
	if _zones != null and _zones.get_difficulty(zone_id) == ZoneData.DIFFICULTY_MAX:
		_spawn_tier3_profile(zone_id, mission_type, zone)
	_register_zone_atmosphere(zone_id, mission_type, zone)

## 正式气氛层只复用本战区已经生成的敌军名单，不做全场扫描，也不重复生成敌方。
func _register_zone_atmosphere(zone_id: StringName, mission_type: String,
		zone: Dictionary) -> void:
	if _zone_atmosphere == null or mission_type == "bomber_escort":
		return
	if not _zone_atmosphere_enabled_for_zone(zone_id):
		return
	var hostiles: Array = []
	for value in _spawned_zones.get(zone_id, []):
		if is_instance_valid(value) and not hostiles.has(value):
			hostiles.append(value)
	for value in _garrison_zones.get(zone_id, []):
		if is_instance_valid(value) and not hostiles.has(value):
			hostiles.append(value)
	_zone_atmosphere.register_zone(zone_id, mission_type, zone, hostiles, _player)

func _zone_atmosphere_enabled_for_zone(zone_id: StringName) -> bool:
	if _force_all_zone_atmosphere:
		return true
	if _zone_atmosphere_enabled.has(zone_id):
		return bool(_zone_atmosphere_enabled[zone_id])
	var enabled: bool = ZONE_ATMOSPHERE_SCRIPT.cached_enabled(
		_zone_atmosphere_enabled, zone_id, randf())
	EventLogger.log_event("ZONE", "AtmosphereRoll", "id=%s chance=%.2f enabled=%s" % [
		zone_id, ZONE_ATMOSPHERE_SCRIPT.ORDINARY_ZONE_CHANCE, str(enabled)])
	return enabled

func _retire_zone_atmosphere(zone_id: StringName) -> void:
	if _zone_atmosphere == null:
		return
	for ally in _zone_atmosphere.retire_zone(zone_id):
		_schedule_despawn(ally)

func _retire_all_zone_atmosphere() -> void:
	if _zone_atmosphere == null:
		return
	for ally in _zone_atmosphere.retire_all():
		_schedule_despawn(ally)

## AVAILABLE 阶段只预刷特殊目标并缓存航路；护送编队在玩家进入移动圆后才正式出发。
func _prepare_bomber_escort(zone_id: StringName, _zone: Dictionary) -> void:
	_zones.clear_dynamic_center(zone_id)
	var route_plan := build_bomber_escort_route(zone_id, _player.global_position)
	var target_pos: Vector2 = route_plan.get("target", Vector2.INF)
	var route: PackedVector2Array = route_plan.get("route", PackedVector2Array())
	if target_pos == Vector2.INF or route.size() < 4:
		_spawned_zones[zone_id] = []
		_bomber_escort_runs[zone_id] = {"error": "no_land_target"}
		EventLogger.log_event("ZONE", "BomberEscortPrepareFailed",
			"id=%s reason=no_land_target" % zone_id)
		return
	var entry: Vector2 = route[0]
	var attack_dir := (target_pos - entry).normalized()
	if attack_dir.length_squared() < 0.1:
		attack_dir = Vector2.DOWN
	var target := _spawner.spawn_strategic_target(
		StrategicTarget.TargetKind.BUNKER, CombatUnit.TEAM_HOSTILE, target_pos) as StrategicTarget
	if target == null:
		_spawned_zones[zone_id] = []
		_bomber_escort_runs[zone_id] = {"error": "target_spawn_failed"}
		return
	if target.params != null:
		target.params = target.params.duplicate(true)
		target.params.max_hp = BOMBER_ESCORT_TARGET_HP
	target.hp = BOMBER_ESCORT_TARGET_HP
	target.set_bomber_escort_objective(true)
	target.set_meta("zone_mission", zone_id)
	target.set_meta("skip_far_cleanup", true)
	_spawned_zones[zone_id] = [target]
	_bomber_escort_runs[zone_id] = {
		"target": target,
		"route": route,
		"route_id": route_plan.get("route_id", &""),
		"controller": null,
	}
	var ingress_heading := atan2(attack_dir.x, -attack_dir.y)
	_zones.set_objective_center(zone_id, target_pos)
	_zones.set_mission_route(zone_id, route)
	_zones.set_mission_status(zone_id, _bomber_status_snapshot(target, null))
	_zones.set_dynamic_center(zone_id, route[0], BOMBER_ESCORT_RADIUS_PX, ingress_heading)
	EventLogger.log_event("ZONE", "PreSpawnBomberEscort",
		"id=%s route=%s target=%s ingress=%s leg=%.0f player_clearance=%.0f deadline=%.0f" % [
			zone_id, route_plan.get("route_id", &""), target_pos, route[0],
			BOMBER_ESCORT_INGRESS_LEG_PX, route[0].distance_to(_player.global_position),
			BOMBER_ESCORT_DEADLINE_S])

## 为普通战区槽位稳定分配一条专用护送航线；目标只在专用锚点附近吸附安全部署陆地。
static func build_bomber_escort_route(zone_id: StringName, player_pos: Vector2,
		world_half_px: float = -1.0) -> Dictionary:
	var slot_idx := BOMBER_ESCORT_ROUTE_SLOT_IDS.find(zone_id)
	if slot_idx < 0:
		slot_idx = absi(String(zone_id).hash()) % BOMBER_ESCORT_ROUTE_CATALOG.size()
	var spec: Dictionary = BOMBER_ESCORT_ROUTE_CATALOG[slot_idx % BOMBER_ESCORT_ROUTE_CATALOG.size()]
	var target := _snap_bomber_target_to_land(spec["target"])
	if target == Vector2.INF:
		return {}
	var axis: Vector2 = spec["axis"]
	axis = axis.normalized()
	var half := world_half_px if world_half_px > 0.0 else MapBoundary.world_half_px()
	var candidates: Array[Vector2] = [
		target - axis * BOMBER_ESCORT_INGRESS_LEG_PX,
		target + axis * BOMBER_ESCORT_INGRESS_LEG_PX,
	]
	var entries: Array[Vector2] = []
	for candidate in candidates:
		if maxf(absf(candidate.x), absf(candidate.y)) >= half + BOMBER_ESCORT_ENTRY_OUTSET_PX:
			entries.append(candidate)
	if entries.is_empty():
		return {}
	var entry := Vector2.INF
	var best_player_clearance := -INF
	for candidate in entries:
		var clearance := candidate.distance_to(player_pos)
		if clearance >= BOMBER_ESCORT_PLAYER_CLEARANCE_PX and clearance > best_player_clearance:
			entry = candidate
			best_player_clearance = clearance
	if entry == Vector2.INF:
		entry = entries[0]
		for candidate in entries:
			if candidate.distance_to(player_pos) > entry.distance_to(player_pos):
				entry = candidate
	var attack_dir := (target - entry).normalized()
	return {
		"route_id": spec["id"],
		"target": target,
		"route": PackedVector2Array([
			entry,
			target - attack_dir * BOMBER_ESCORT_LINEUP_PX,
			target,
			target + attack_dir * BOMBER_ESCORT_EXIT_PX,
		]),
	}

static func _snap_bomber_target_to_land(anchor: Vector2) -> Vector2:
	return MapGeography.find_ground_spawn_near(anchor, 5000.0)

func _start_bomber_escort(zone_id: StringName) -> void:
	if not _bomber_escort_runs.has(zone_id):
		fail_zone(zone_id, "escort_not_prepared")
		return
	var run: Dictionary = _bomber_escort_runs[zone_id]
	if run.get("controller") != null:
		return
	if run.has("error"):
		fail_zone(zone_id, String(run["error"]))
		return
	var target: StrategicTarget = run.get("target") as StrategicTarget
	var route: PackedVector2Array = run.get("route", PackedVector2Array())
	if not is_instance_valid(target) or route.size() < 3:
		fail_zone(zone_id, "escort_setup_invalid")
		return
	var controller := _spawner.spawn_bomber_mission(CombatUnit.TEAM_ALLY, route,
		target.global_position, BOMBER_ESCORT_COUNT, target, BOMBER_ESCORT_DEADLINE_S,
		SurvivorSpawner.BomberFormation.TRAIL, 1, BOMBER_ESCORT_FIGHTER_COUNT,
		BOMBER_ESCORT_BOMBER_HP) as BomberMission
	if controller == null:
		fail_zone(zone_id, "bomber_spawn_failed")
		return
	var difficulty := _zones.get_difficulty(zone_id) if _zones else 1
	var response_level := maxi(BOMBER_ESCORT_MIN_RESPONSE_LEVEL,
		_spawner.get_response_level())
	var player_squad_size := _spawner.player_squad_size()
	var variant_seed := hash(String(zone_id))
	var response_plan := bomber_interceptor_plan(response_level, difficulty,
		player_squad_size, variant_seed)
	run["controller"] = controller
	run["interceptors"] = []
	run["response_plan"] = response_plan
	run["initial_response_spawned"] = false
	run["response_level"] = response_level
	run["player_squad_size"] = player_squad_size
	run["variant_seed"] = variant_seed
	run["player_intervened"] = false
	run["response_armed"] = false
	run["reserve_spawned"] = false
	run["route_progress"] = 0.0
	_bomber_escort_runs[zone_id] = run
	controller.mission_failed.connect(_on_bomber_escort_failed.bind(zone_id))
	EventLogger.log_event("ZONE", "BomberEscortStarted",
		"id=%s stars=%d response=%d squad=%d bombers=%d escorts=%d response_pending=true plan=%s release_each=1 deadline=%.0f" % [
			zone_id, difficulty, response_level, player_squad_size, BOMBER_ESCORT_COUNT,
			BOMBER_ESCORT_FIGHTER_COUNT, bomber_interceptor_plan_summary(response_plan),
			BOMBER_ESCORT_DEADLINE_S])

## 根据正式敌机池组建“截击 B-1B + 扫荡 F-4E”混编。响应等级决定机型时代，
## 星级和直属僚机数只改变 Token 威胁预算，避免固定机型/固定人头硬压。
static func bomber_interceptor_plan(response_level: int, difficulty: int,
		player_squad_size: int, variant_seed: int = 0) -> Array[Dictionary]:
	var response := maxi(BOMBER_ESCORT_MIN_RESPONSE_LEVEL, response_level)
	var strike_rows := _bomber_role_rows(response, "intercept")
	var screen_rows := _bomber_role_rows(response, "dogfight")
	if strike_rows.is_empty() or screen_rows.is_empty():
		return []
	var strike_row: Dictionary = strike_rows[posmod(variant_seed, strike_rows.size())]
	var screen_row: Dictionary = screen_rows[posmod(variant_seed * 3 + 1, screen_rows.size())]
	var stars := clampi(difficulty, 1, 3)
	var wingmen := clampi(player_squad_size - 1, 0, 3)
	var budget := BOMBER_ESCORT_THREAT_BUDGET_BASE \
		+ BOMBER_ESCORT_THREAT_BUDGET_PER_STAR * stars \
		+ BOMBER_ESCORT_THREAT_BUDGET_PER_WINGMAN * wingmen
	var strike_budget := int(round(float(budget) * 0.67))
	var screen_budget := maxi(1, budget - strike_budget)
	var strike_count := clampi(int(round(float(strike_budget) \
		/ float(maxi(1, int(strike_row["token_cost"]))))), 3, 5)
	var screen_count := clampi(int(round(float(screen_budget) \
		/ float(maxi(1, int(screen_row["token_cost"]))))), 2, 3)
	return [
		{"type": int(strike_row["type"]), "count": strike_count,
			"assignment": "bomber", "role": "intercept"},
		{"type": int(screen_row["type"]), "count": screen_count,
			"assignment": "escort", "role": "dogfight"},
	]

static func bomber_reserve_plan(response_level: int, difficulty: int,
		bombers_alive: int, active_strikers: int, variant_seed: int = 0) -> Array[Dictionary]:
	if bombers_alive <= 0:
		return []
	var response := maxi(BOMBER_ESCORT_MIN_RESPONSE_LEVEL, response_level)
	var rows := _bomber_role_rows(response, "intercept")
	if rows.is_empty():
		return []
	var row: Dictionary = rows[posmod(variant_seed * 5 + 1, rows.size())]
	var missing_pressure := bombers_alive * 2 - maxi(0, active_strikers)
	var count := clampi(missing_pressure + clampi(difficulty, 1, 3) - 1, 2, 4)
	return [{"type": int(row["type"]), "count": count,
		"assignment": "bomber", "role": "intercept"}]

static func _bomber_role_rows(response_level: int, role: String) -> Array[Dictionary]:
	var broad: Array[Dictionary] = []
	var current_band: Array[Dictionary] = []
	for raw_row in EnemyPoolRegistry.ROWS:
		var row: Dictionary = raw_row
		if String(row.get("role", "")) != role:
			continue
		var unlock := int(row.get("unlock", 999))
		var retire := int(row.get("retire", -1))
		if unlock > response_level or (retire >= 0 and response_level > retire):
			continue
		broad.append(row)
		if unlock >= response_level - 3:
			current_band.append(row)
	return current_band if not current_band.is_empty() else broad

static func bomber_interceptor_plan_summary(plan: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for group in plan:
		parts.append("%s:%s×%d" % [String(group.get("role", "?")),
			SurvivorSpawner.type_tag_of(int(group.get("type", -1))),
			int(group.get("count", 0))])
	return ",".join(parts)

func _update_bomber_escort_caches(delta: float) -> void:
	if not _zones:
		return
	_bomber_cache_accum += delta
	if _bomber_cache_accum < BOMBER_ESCORT_CACHE_TICK_S:
		return
	_bomber_cache_accum = fmod(_bomber_cache_accum, BOMBER_ESCORT_CACHE_TICK_S)
	for zid_any in _bomber_escort_runs.keys():
		var zid: StringName = zid_any
		var run: Dictionary = _bomber_escort_runs[zid]
		var target := run.get("target") as StrategicTarget
		var controller := run.get("controller") as BomberMission
		if controller != null and is_instance_valid(controller):
			var center := controller.get_live_center()
			if center != Vector2.INF:
				_zones.set_dynamic_center(zid, center, BOMBER_ESCORT_RADIUS_PX,
					controller.get_live_heading())
				var route: PackedVector2Array = run.get("route", PackedVector2Array())
				run["route_progress"] = bomber_route_progress(route, center)
			_spawn_bomber_initial_response_if_ready(zid, run, controller)
			_update_bomber_player_intervention(run, controller)
			_update_bomber_response_fire(run)
			_spawn_bomber_reserve_if_needed(zid, run, controller)
			_retarget_bomber_interceptors(run, controller)
			_bomber_escort_runs[zid] = run
			if should_abort_bomber_escort(float(run.get("route_progress", 0.0)),
					bool(run.get("player_intervened", false))) \
					and not controller.is_outcome_resolved() \
					and (target == null or not is_instance_valid(target) or not target.is_destroyed):
				EventLogger.log_event("BOMBER_MISSION", "ESCORT_ABSENT",
					"zone=%s progress=%.3f response=%d" % [zid,
						float(run.get("route_progress", 0.0)),
						int(run.get("response_level", BOMBER_ESCORT_MIN_RESPONSE_LEVEL))])
				controller.abort("escort_absent")
				continue
		_zones.set_mission_status(zid, _bomber_status_snapshot(target, controller,
			run.get("interceptors", []), run))

func _bomber_status_snapshot(target: StrategicTarget, controller: BomberMission,
		interceptors: Array = [], run: Dictionary = {}) -> Dictionary:
	var max_hp := 150.0
	var hp := 0.0
	if target != null and is_instance_valid(target):
		hp = maxf(target.hp, 0.0)
		if target.params != null:
			max_hp = maxf(target.params.max_hp, 1.0)
	return {
		"phase": controller.get_phase_key() if controller != null and is_instance_valid(controller) else "standby",
		"target_hp": hp,
		"target_max_hp": max_hp,
		"remaining_s": controller.get_remaining_time() if controller != null and is_instance_valid(controller) else BOMBER_ESCORT_DEADLINE_S,
		"bombers_alive": controller.get_alive_bomber_count() if controller != null and is_instance_valid(controller) else BOMBER_ESCORT_COUNT,
		"bombers_total": BOMBER_ESCORT_COUNT,
		"escorts_alive": controller.get_alive_escort_count() if controller != null and is_instance_valid(controller) else BOMBER_ESCORT_FIGHTER_COUNT,
		"escorts_total": BOMBER_ESCORT_FIGHTER_COUNT,
		"interceptors_alive": _alive_aircraft_count(interceptors),
		"interceptors_total": interceptors.size(),
		"route_progress": float(run.get("route_progress", 0.0)),
		"player_intervened": bool(run.get("player_intervened", false)),
	}

static func bomber_route_progress(route: PackedVector2Array, world_pos: Vector2) -> float:
	if route.size() < 3:
		return 0.0
	var leg := route[2] - route[0]
	var length_sq := leg.length_squared()
	if length_sq <= 0.001:
		return 0.0
	return clampf((world_pos - route[0]).dot(leg) / length_sq, 0.0, 1.0)

static func should_abort_bomber_escort(route_progress: float,
		player_intervened: bool) -> bool:
	return not player_intervened \
		and route_progress >= BOMBER_ESCORT_UNATTENDED_ABORT_PROGRESS

static func bomber_response_weapons_should_arm(route_progress: float) -> bool:
	return route_progress >= BOMBER_ESCORT_RESPONSE_ARM_PROGRESS

## 轰炸机先飞完 6% 航程（约 750px），响应队才从实时航迹后方同向追入。
static func bomber_response_should_launch(route_progress: float) -> bool:
	return route_progress >= BOMBER_ESCORT_RESPONSE_LAUNCH_PROGRESS

func _spawn_bomber_initial_response_if_ready(zone_id: StringName, run: Dictionary,
		controller: BomberMission) -> void:
	if bool(run.get("initial_response_spawned", false)):
		return
	var center := controller.get_live_center()
	if center == Vector2.INF or not bomber_response_should_launch(
			float(run.get("route_progress", 0.0))):
		return
	run["initial_response_spawned"] = true
	var response_plan: Array[Dictionary] = run.get("response_plan", [])
	var interceptors := _spawner.spawn_bomber_interceptors(center,
		Vector2(sin(controller.get_live_heading()), -cos(controller.get_live_heading())),
		controller.get_bombers(), controller.get_escort_fighters(), response_plan, 0)
	run["interceptors"] = interceptors
	EventLogger.log_event("BOMBER_MISSION", "REAR_PURSUIT_LAUNCHED",
		"zone=%s progress=%.3f spawned=%d center=%s plan=%s" % [zone_id,
			float(run.get("route_progress", 0.0)), interceptors.size(), center.round(),
			bomber_interceptor_plan_summary(response_plan)])

## 响应队从后方真实接近与建立锁定；32% 航程前只维持共享武器
## cooldown，避免高阶远射让任务刚刷新就结束。过线一次性放行，此后不再扫描。
func _update_bomber_response_fire(run: Dictionary) -> void:
	if bool(run.get("response_armed", false)):
		return
	var route_progress := float(run.get("route_progress", 0.0))
	var arm_now := bomber_response_weapons_should_arm(route_progress)
	for raw in run.get("interceptors", []):
		if typeof(raw) != TYPE_OBJECT or raw == null or not is_instance_valid(raw) \
				or not (raw is Aircraft) or (raw as Aircraft).is_destroyed:
			continue
		var interceptor := raw as Aircraft
		if arm_now:
			interceptor._fire_cooldown = 0.0
			interceptor._missile_cooldown = 0.0
		else:
			interceptor._fire_cooldown = maxf(interceptor._fire_cooldown, 0.35)
			interceptor._missile_cooldown = maxf(interceptor._missile_cooldown, 0.35)
	if arm_now:
		run["response_armed"] = true
		EventLogger.log_event("BOMBER_MISSION", "RESPONSE_WEAPONS_ARMED",
			"progress=%.3f" % route_progress)

func _update_bomber_player_intervention(run: Dictionary,
		controller: BomberMission) -> void:
	if bool(run.get("player_intervened", false)):
		return
	var center := controller.get_live_center()
	if center != Vector2.INF and _player != null and is_instance_valid(_player) \
			and not _player.is_destroyed \
			and _player.global_position.distance_to(center) \
				<= BOMBER_ESCORT_PLAYER_SUPPORT_RADIUS_PX:
		run["player_intervened"] = true
		EventLogger.log_event("BOMBER_MISSION", "PLAYER_ESCORT_ESTABLISHED",
			"source=proximity progress=%.3f" % float(run.get("route_progress", 0.0)))
		return
	for raw in run.get("interceptors", []):
		if typeof(raw) != TYPE_OBJECT or raw == null or not is_instance_valid(raw) \
				or not (raw is Aircraft):
			continue
		var interceptor := raw as Aircraft
		var player_damage := int(interceptor.get_meta("kill_attacker_team", -1)) \
			== CombatUnit.TEAM_PLAYER
		if not player_damage and interceptor.has_meta("_pending_attacker"):
			var attacker := CombatUnit.safe_attacker(
				interceptor.get_meta("_pending_attacker"))
			player_damage = attacker is CombatUnit \
				and (attacker as CombatUnit).team == CombatUnit.TEAM_PLAYER
		if player_damage:
			run["player_intervened"] = true
			EventLogger.log_event("BOMBER_MISSION", "PLAYER_ESCORT_ESTABLISHED",
				"source=damage progress=%.3f" % float(run.get("route_progress", 0.0)))
			return

func _spawn_bomber_reserve_if_needed(zone_id: StringName, run: Dictionary,
		controller: BomberMission) -> void:
	if bool(run.get("reserve_spawned", false)) \
			or bool(run.get("player_intervened", false)) \
			or float(run.get("route_progress", 0.0)) < BOMBER_ESCORT_RESERVE_TRIGGER_PROGRESS:
		return
	run["reserve_spawned"] = true
	var active_strikers := 0
	for raw in run.get("interceptors", []):
		if typeof(raw) == TYPE_OBJECT and raw != null and is_instance_valid(raw) \
				and raw is Aircraft and not (raw as Aircraft).is_destroyed \
				and String((raw as Aircraft).get_meta(
					"bomber_intercept_assignment", "bomber")) == "bomber":
			active_strikers += 1
	var difficulty := _zones.get_difficulty(zone_id) if _zones else 1
	var reserve_plan := bomber_reserve_plan(
		int(run.get("response_level", BOMBER_ESCORT_MIN_RESPONSE_LEVEL)),
		difficulty, controller.get_alive_bomber_count(), active_strikers,
		int(run.get("variant_seed", 0)))
	if reserve_plan.is_empty():
		return
	var center := controller.get_live_center()
	var reserve := _spawner.spawn_bomber_interceptors(center,
		Vector2(sin(controller.get_live_heading()), -cos(controller.get_live_heading())),
		controller.get_bombers(), controller.get_escort_fighters(), reserve_plan, 1)
	var interceptors: Array = run.get("interceptors", [])
	interceptors.append_array(reserve)
	run["interceptors"] = interceptors
	EventLogger.log_event("BOMBER_MISSION", "HOSTILE_RESERVE",
		"zone=%s progress=%.3f alive_bombers=%d active_strikers=%d spawned=%d plan=%s" % [
			zone_id, float(run.get("route_progress", 0.0)),
			controller.get_alive_bomber_count(), active_strikers, reserve.size(),
			bomber_interceptor_plan_summary(reserve_plan)])

func _retarget_bomber_interceptors(run: Dictionary, controller: BomberMission) -> void:
	if _spawner == null or controller == null or not is_instance_valid(controller):
		return
	var alive_bombers: Array[Aircraft] = []
	for bomber in controller.get_bombers():
		if is_instance_valid(bomber) and not bomber.is_destroyed:
			alive_bombers.append(bomber)
	if alive_bombers.is_empty():
		return
	var interceptors: Array = run.get("interceptors", [])
	for i in range(interceptors.size()):
		var raw: Variant = interceptors[i]
		if typeof(raw) != TYPE_OBJECT or raw == null or not is_instance_valid(raw) \
				or not (raw is Aircraft) or (raw as Aircraft).is_destroyed:
			continue
		var interceptor := raw as Aircraft
		var assigned_raw: Variant = interceptor.get_meta("bomber_intercept_target", null)
		var assigned_alive := typeof(assigned_raw) == TYPE_OBJECT and assigned_raw != null \
			and is_instance_valid(assigned_raw) and assigned_raw is Aircraft \
			and not (assigned_raw as Aircraft).is_destroyed
		if not assigned_alive:
			_spawner.assign_bomber_intercept_target(interceptor,
				alive_bombers[0])
			interceptor.set_meta("bomber_intercept_assignment", "bomber")

static func _alive_aircraft_count(values: Array) -> int:
	var count := 0
	for raw in values:
		if typeof(raw) == TYPE_OBJECT and raw != null and is_instance_valid(raw) \
				and raw is Aircraft and not (raw as Aircraft).is_destroyed:
			count += 1
	return count

func _on_bomber_escort_failed(reason: String, zone_id: StringName) -> void:
	# BomberMission 已经按“成功优先 + 在途炸弹落地窗口”裁决；这里只转入统一失败链。
	fail_zone(zone_id, reason)

## 陆地守备：SAM + AA 按星级/等级缩放
func _spawn_ground_garrison(zone_id: StringName, zone: Dictionary) -> void:
	var units: Array = []
	var placed_positions: Array[Vector2] = []
	var center: Vector2 = zone["center"]
	var scatter: float = float(zone["radius"]) * SCATTER_RADIUS_SCALE
	## 若战区配了 ground_spawn_polygons，SAM/AA 改在多边形内随机刷（仍走严格陆地判定）
	var spawn_polys: Array = zone.get("ground_spawn_polygons", [])
	var use_polys: bool = not spawn_polys.is_empty()

	## TGT 数量随星级（HP 不缩放，直接用基础 params）
	##   ★2+2 / ★★3+3 / ★★★5+5
	var lvl: int = _player_level()
	var difficulty: int = _zones.get_difficulty(zone_id) if _zones else 1
	var scale: Dictionary = SurvivorData.ground_tgt_scale(difficulty, lvl)
	var sam_count: int = int(scale["sam_count"])
	var aa_count: int = int(scale["aa_count"])

	for i in range(sam_count):
		var pos := _find_valid_spawn_pos(center, scatter, placed_positions, spawn_polys if use_polys else [])
		if pos == Vector2.INF:
			continue  ## 采样失败：战区这一侧全是海，跳过这颗单位
		var u := _spawn_ground(_sam_scene, _sam_params, pos, zone_id)
		if u:
			units.append(u)
			placed_positions.append(pos)
	for i in range(aa_count):
		var pos := _find_valid_spawn_pos(center, scatter, placed_positions, spawn_polys if use_polys else [])
		if pos == Vector2.INF:
			continue
		# 普通地面战区最多一门空爆炮，替换首个 AA 槽而不增加总单位数。
		var aa_scene := _AIRBURST_AA_SCENE if i == 0 else _aa_scene
		var aa_params := _AIRBURST_AA_PARAMS if i == 0 else _aa_params
		var u := _spawn_ground(aa_scene, aa_params, pos, zone_id)
		if u:
			units.append(u)
			placed_positions.append(pos)
	## 任务丰富化（2026-07-06 密度调优）：★★+ 附带雷达站 TGT。刷得比 SAM/AA 靠内
	## （scatter×0.6，受 SAM 环保护），datalink 给全区共享 20km 感知——先打雷达可削弱预警
	var radar_count: int = int(scale.get("radar_count", 0))
	for i in range(radar_count):
		var pos := _find_valid_spawn_pos(center, scatter * 0.6, placed_positions, spawn_polys if use_polys else [])
		if pos == Vector2.INF:
			continue
		var u := _spawn_ground(_RADAR_SCENE, _RADAR_PARAMS, pos, zone_id)
		if u:
			units.append(u)
			placed_positions.append(pos)
	_spawned_zones[zone_id] = units
	# TGT 标记在玩家进入战区（mission_triggered）时才打上，预刷阶段不标
	EventLogger.log_event("ZONE", "PreSpawnGround",
		"id=%s lvl=%d diff=%d units=%d center=%s"
		% [zone_id, lvl, difficulty, units.size(), center])


## 地面 3★ 的地图身份。东京湾/default 固定巨炮；沙漠等权抽巨炮/攻城坦克。
## roll 参数是专项测试 seam，运行时只调用一次并把结果固化在已生成实体上。
static func tier3_ground_profile_for(map_id: String, roll: float) -> StringName:
	if map_id == TIER3_DESERT_MAP_ID:
		return &"siege_tank" if clampf(roll, 0.0, 1.0) < 0.5 else &"super_cannon"
	return &"super_cannon"


func _spawn_tier3_profile(zone_id: StringName, mission_type: String,
		zone: Dictionary) -> void:
	var registered_profile: StringName = &""
	match mission_type:
		"ground":
			var map_id := String(mode.get("_map_id")) if mode != null and "_map_id" in mode \
				else "default"
			var profile := StringName(_debug_tier3_profile_by_zone.get(zone_id, &""))
			if profile != &"super_cannon" and profile != &"siege_tank":
				profile = tier3_ground_profile_for(map_id, randf())
			if profile == &"siege_tank":
				_spawn_tier3_siege_tank(zone_id, zone)
			else:
				_spawn_tier3_super_cannon(zone_id, zone)
			registered_profile = profile
		"air", "squadron":
			_spawn_tier3_deadair(zone_id, zone)
			registered_profile = &"deadair"
		"naval":
			# 舰船已在 `_spawn_naval_formation` 实例化前拿到深拷贝的远程 VLS 参数。
			registered_profile = &"long_range_vls"
	if registered_profile != &"":
		_register_tier3_sources(zone_id, registered_profile)


func _register_tier3_sources(zone_id: StringName, profile: StringName) -> void:
	var sources: Array = []
	for value in _spawned_zones.get(zone_id, []):
		if typeof(value) == TYPE_OBJECT and value != null and is_instance_valid(value) \
				and value is CombatUnit and bool(value.get_meta(&"tier3_threat_source", false)):
			sources.append(value)
	if sources.is_empty():
		push_error("ZoneMission: Tier3 profile %s has no live source in zone %s" % [profile, zone_id])
		return
	_tier3_sources_by_zone[zone_id] = {
		"profile": profile,
		"sources": sources,
		"active": true,
	}
	tier3_threat_changed.emit(zone_id, profile, true)


func _update_tier3_source_states(delta: float) -> void:
	_tier3_source_tick_s = maxf(_tier3_source_tick_s - delta, 0.0)
	if _tier3_source_tick_s > 0.0:
		return
	_tier3_source_tick_s = 0.25
	for zone_id_value in _tier3_sources_by_zone.keys():
		var zone_id := StringName(zone_id_value)
		var entry: Dictionary = _tier3_sources_by_zone[zone_id]
		var live := false
		for value in entry.get("sources", []):
			if typeof(value) == TYPE_OBJECT and value != null and is_instance_valid(value) \
					and value is CombatUnit and not (value as CombatUnit).is_destroyed:
				live = true
				break
		if bool(entry.get("active", false)) and not live:
			entry["active"] = false
			_tier3_sources_by_zone[zone_id] = entry
			tier3_threat_changed.emit(zone_id, StringName(entry.get("profile", &"")), false)


func _end_tier3_zone(zone_id: StringName) -> void:
	if not _tier3_sources_by_zone.has(zone_id):
		return
	var entry: Dictionary = _tier3_sources_by_zone[zone_id]
	if bool(entry.get("active", false)):
		tier3_threat_changed.emit(zone_id, StringName(entry.get("profile", &"")), false)
	_tier3_sources_by_zone.erase(zone_id)


func _existing_zone_target_positions(zone_id: StringName) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for value in _spawned_zones.get(zone_id, []):
		if typeof(value) == TYPE_OBJECT and value != null and is_instance_valid(value) \
				and value is Node2D:
			positions.append((value as Node2D).global_position)
	return positions


func _find_cannon_compound_center(center: Vector2, radius: float,
		placed: Array[Vector2]) -> Vector2:
	for _attempt in range(MAX_SAMPLE_ATTEMPTS):
		var candidate := _random_pos_in_circle(center, radius * 0.55)
		if not _far_from_placed(candidate, placed) or not _far_from_roads(candidate):
			continue
		var all_safe := true
		for offset in TIER3_CANNON_PART_OFFSETS:
			if not MapGeography.is_ground_spawn_safe(candidate + offset):
				all_safe = false
				break
		if all_safe:
			return candidate
	return Vector2.INF


func _tier3_ground_params(display_name: String, hp_value: float) -> AircraftParams:
	var p := _TIER3_GROUND_BASE_PARAMS.duplicate(true) as AircraftParams
	p.display_name = display_name
	p.max_hp = hp_value
	p.radar_range = 0.0
	p.lock_time = 2.5
	p.gun = null
	p.missile = null
	return p


func _spawn_tier3_super_cannon(zone_id: StringName, zone: Dictionary) -> void:
	var center := _find_cannon_compound_center(zone["center"], float(zone["radius"]),
		_existing_zone_target_positions(zone_id))
	if center == Vector2.INF:
		push_warning("ZoneMission: no safe Tier3 super cannon compound for %s" % zone_id)
		return
	var units: Array = _spawned_zones.get(zone_id, [])
	for i in range(TIER3_CANNON_PART_OFFSETS.size()):
		var part = TIER3_SUPER_CANNON_SCRIPT.new()
		var is_body := i == TIER3_CANNON_PART_OFFSETS.size() - 1
		part.params = _tier3_ground_params("STONEHENGE" if is_body else "STONEHENGE BASE",
			TIER3_CANNON_BODY_HP if is_body else TIER3_CANNON_BASE_HP)
		part.position = center + TIER3_CANNON_PART_OFFSETS[i]
		part.team = CombatUnit.TEAM_HOSTILE
		part.callsign = "STONEHENGE-%s" % ("BODY" if is_body else "B%d" % (i + 1))
		part.configure(TIER3_SUPER_CANNON_SCRIPT.PartKind.BODY if is_body \
			else TIER3_SUPER_CANNON_SCRIPT.PartKind.BASE, zone_id)
		part.set_meta(&"zone_mission", zone_id)
		part.set_meta(&"tier3_special_unit", true)
		part.set_meta(&"tier3_profile", &"super_cannon")
		if is_body:
			part.set_meta(&"tier3_threat_source", true)
		mode.add_child(part)
		units.append(part)
	_spawned_zones[zone_id] = units
	EventLogger.log_event("TIER3", "SuperCannonSpawn",
		"zone=%s targets=5 center=%s" % [zone_id, center.round()])


func _spawn_tier3_siege_tank(zone_id: StringName, zone: Dictionary) -> void:
	var placed := _existing_zone_target_positions(zone_id)
	var pos := _find_valid_spawn_pos(zone["center"], float(zone["radius"]) * 0.55,
		placed, zone.get("ground_spawn_polygons", []))
	if pos == Vector2.INF:
		push_warning("ZoneMission: no safe Tier3 siege tank position for %s" % zone_id)
		return
	var tank = TIER3_SIEGE_TANK_SCRIPT.new()
	tank.params = _tier3_ground_params("SIEGE TANK", TIER3_SIEGE_TANK_HP)
	tank.position = pos
	tank.team = CombatUnit.TEAM_HOSTILE
	tank.callsign = "SIEGE-%s" % zone_id
	tank.configure(zone_id)
	tank.set_meta(&"zone_mission", zone_id)
	tank.set_meta(&"tier3_special_unit", true)
	tank.set_meta(&"tier3_threat_source", true)
	tank.set_meta(&"tier3_profile", &"siege_tank")
	mode.add_child(tank)
	tank.arm_mounts(mode, _bullet_manager, _missile_manager)
	var units: Array = _spawned_zones.get(zone_id, [])
	units.append(tank)
	_spawned_zones[zone_id] = units
	EventLogger.log_event("TIER3", "SiegeTankSpawn",
		"zone=%s mounts=2CIWS+LR-SAM+AIRBURST pos=%s" % [zone_id, pos.round()])


func _spawn_tier3_deadair(zone_id: StringName, zone: Dictionary) -> void:
	if _spawner == null:
		return
	var center: Vector2 = zone["center"]
	var orbit_r := maxf(AIR_SQUADRON_ORBIT_RADIUS,
		float(zone["radius"]) * AIR_SQUADRON_ORBIT_RADIUS_FRAC)
	var origin := _zone_air_spawn_origin(center)
	var heading_deg := _zone_air_heading_deg(origin, center)
	var heading_rad := deg_to_rad(heading_deg)
	var waypoints := PackedVector2Array()
	for k in range(AIR_SQUADRON_PATROL_WAYPOINTS):
		var angle := float(k) / float(AIR_SQUADRON_PATROL_WAYPOINTS) * TAU
		waypoints.append(center + Vector2(cos(angle), sin(angle)) * orbit_r)
	var sq := SquadFactory.create()
	sq.formation = Squad.Formation.WEDGE
	var core := _spawner._create_enemy(SurvivorSpawner.EnemyType.DEADAIR,
		origin, heading_deg)
	if core == null:
		return
	_tag_zone_air_ingress(core, center, orbit_r + ZONE_AIR_INGRESS_ARRIVE_BAND_PX)
	core.set_meta(&"zone_mission", zone_id)
	core.set_meta(&"tier3_special_unit", true)
	core.set_meta(&"tier3_threat_source", true)
	core.set_meta(&"tier3_profile", &"deadair")
	SquadFactory.register_leader(sq, core)
	var core_ai := _get_ai_of(core)
	if core_ai != null:
		core_ai.waypoints = waypoints
	var escorts: Array[Aircraft] = []
	var escort_types: Array[int] = _tier3_deadair_escort_types()
	for i in range(2):
		var offset := sq.get_formation_offset(i + 1).rotated(heading_rad)
		var escort := _spawner._create_enemy(escort_types[i], origin + offset, heading_deg)
		if escort == null:
			continue
		_tag_zone_air_ingress(escort, center, orbit_r + ZONE_AIR_INGRESS_ARRIVE_BAND_PX)
		escort.set_meta(&"zone_garrison", zone_id)
		SquadFactory.register_wingman(sq, escort, true)
		var escort_ai := _get_ai_of(escort)
		if escort_ai != null:
			escort_ai.waypoints = waypoints
		escorts.append(escort)
	_spawner.register_tier3_deadair_squad(sq, core)
	var targets: Array = _spawned_zones.get(zone_id, [])
	targets.append(core)
	_spawned_zones[zone_id] = targets
	var garrison: Array = _garrison_zones.get(zone_id, [])
	garrison.append_array(escorts)
	_garrison_zones[zone_id] = garrison
	EventLogger.log_event("TIER3", "DeadairSpawn",
		"zone=%s core=1 escorts=%d" % [zone_id, escorts.size()])


func _tier3_deadair_escort_types() -> Array[int]:
	var lvl := SurvivorData.tgt_level_for_zone(ZoneData.DIFFICULTY_MAX, _player_level())
	var pool := SurvivorData.get_zone_enemy_pool(lvl, true, true)
	var result: Array[int] = []
	for _i in range(2):
		var picked := SurvivorData.pick_zone_enemy(pool, 999, lvl)
		var etype := int(picked.get("type", SurvivorSpawner.EnemyType.F15)) \
			if not picked.is_empty() else int(SurvivorSpawner.EnemyType.F15)
		result.append(etype)
	return result

## 机场难度定档（spec airfield-liberation-zones §2.3）：读 ROE 热度 → 1/2/3★。
## heat<34→1★，<67→2★，≥67→3★。_roe 未就绪则回退 1★。
func _airfield_difficulty_from_heat() -> int:
	var heat: float = 0.0
	if _spawner and _spawner._roe:
		heat = _spawner._roe.heat
	if heat < 34.0:
		return 1
	if heat < 67.0:
		return 2
	return 3

## 机场地面防空（spec airfield-liberation-zones §2.2）：固定 1 SAM + 2 AA（敌方 TGT），
## 复刻原 ALLY 驻军编成。HP 不缩放。打光这 3 门＝解放机场。升空迎战由 _spawn_zone_defenders 另刷。
func _spawn_airfield_ground(zone_id: StringName, zone: Dictionary) -> void:
	var units: Array = []
	var placed_positions: Array[Vector2] = []
	var center: Vector2 = zone["center"]
	var scatter: float = float(zone["radius"]) * SCATTER_RADIUS_SCALE
	for i in range(AIRFIELD_SAM_COUNT):
		var pos := _find_valid_spawn_pos(center, scatter, placed_positions, [])
		if pos == Vector2.INF:
			continue
		var u := _spawn_ground(_sam_scene, _sam_params, pos, zone_id)
		if u:
			units.append(u)
			placed_positions.append(pos)
	for i in range(AIRFIELD_AA_COUNT):
		var pos := _find_valid_spawn_pos(center, scatter, placed_positions, [])
		if pos == Vector2.INF:
			continue
		# 仅 3★ 机场把第一门 AA 替换为空爆炮；低星级和解放后的友军防御仍是 ZU-23。
		var use_airburst := i == 0 and (_zones.get_difficulty(zone_id) if _zones else 1) >= 3
		var aa_scene := _AIRBURST_AA_SCENE if use_airburst else _aa_scene
		var aa_params := _AIRBURST_AA_PARAMS if use_airburst else _aa_params
		var u := _spawn_ground(aa_scene, aa_params, pos, zone_id)
		if u:
			units.append(u)
			placed_positions.append(pos)
	_spawned_zones[zone_id] = units
	# TGT 标记在玩家进入战区（mission_triggered）时才打上，预刷阶段不标
	EventLogger.log_event("ZONE", "PreSpawnAirfield",
		"id=%s heat_star=%d ground=%d center=%s"
		% [zone_id, _zones.get_difficulty(zone_id) if _zones else 1, units.size(), center])

## 空战中队：从地图边界外飞向战区巡逻环，不受 Token 限制。
## 复用 SurvivorSpawner 的边缘候选算法与 _create_enemy 工厂。
const AIR_SQUADRON_COUNT := 4
const AIR_SQUADRON_ORBIT_RADIUS := 1200.0   ## 地板值；实际取 max(地板, zone.radius × 0.48)（2026-07-06 战区扩到 3500 后随半径撑开）
const AIR_SQUADRON_PATROL_WAYPOINTS := 4    ## 绕中心的航点数
const AIR_SQUADRON_ORBIT_RADIUS_FRAC := 0.48  ## 轨道半径 = zone.radius × 此值（与地板取大）

## 驻守敌机（garrison）：地面战区的空中守卫，不是任务目标，不标 TGT
## 难度 → [数量, 敌机池]
## 攻克战区后自动撤离（queue_free）
const GARRISON_ORBIT_RADIUS := 1800.0        ## 地板值；实际取 max(地板, zone.radius × 0.72)，比 air_squadron 稍大避免与 SAM 扎堆
const GARRISON_ORBIT_RADIUS_FRAC := 0.72     ## 驻守环 = zone.radius × 此值（与地板取大）

## 正式战区空军与旅途增援共用同一边界外生成算法。fallback 只服务缺少完整
## SurvivorSpawner/player 的单元测试或 fail-open 场景，仍保证落在世界边界外。
func _zone_air_spawn_origin(center: Vector2) -> Vector2:
	if _spawner != null and _spawner.player_aircraft != null \
			and is_instance_valid(_spawner.player_aircraft):
		return _spawner._ingress_spawn_point(center)
	var half := MapBoundary.world_half_px() + SurvivorData.INGRESS_SPAWN_OUTSET_PX
	if absf(center.x) > absf(center.y):
		var sx := 1.0 if center.x >= 0.0 else -1.0
		return Vector2(sx * half, clampf(center.y, -half, half))
	var sy := 1.0 if center.y >= 0.0 else -1.0
	if center == Vector2.ZERO:
		sy = -1.0
	return Vector2(clampf(center.x, -half, half), sy * half)

static func _zone_air_heading_deg(from: Vector2, center: Vector2) -> float:
	var direction := (center - from).normalized()
	return rad_to_deg(atan2(direction.x, -direction.y))

static func _zone_patrol_entry_index(entry: Vector2, center: Vector2,
		waypoint_count: int) -> int:
	var entry_angle := (entry - center).angle()
	return posmod(int(round(entry_angle / TAU * float(waypoint_count))), waypoint_count)

func _tag_zone_air_ingress(ac: Aircraft, center: Vector2,
		arrive_radius: float) -> void:
	ac.set_meta("category", "zone_air")
	ac.set_meta("skip_far_cleanup", true)
	ac.set_meta("zone_ingress", true)
	ac.set_meta("zone_ingress_center", center)
	ac.set_meta("zone_ingress_arrive_radius", arrive_radius)

func _spawn_air_squadron(zone_id: StringName, zone: Dictionary) -> void:
	if not _spawner:
		return
	var center: Vector2 = zone["center"]
	var units: Array = []
	# 一个战区一支中队 = 同一机型
	# 2026-04-21：TGT 用"虚拟等级"(玩家等级 + 星级加成)选型，保证 TGT 强于护卫
	#   ★    → +0（与护卫同级）
	#   ★★   → +2
	#   ★★★  → +4（Lv7 ★★★ → virtual Lv11，抽到 Su-27/MiG-31 级）
	var lvl: int = _player_level()
	var difficulty: int = _zones.get_difficulty(zone_id) if _zones else 1
	var tgt_lvl: int = SurvivorData.tgt_level_for_zone(difficulty, lvl)
	var pool := SurvivorData.get_zone_enemy_pool(tgt_lvl, true, true)
	var picked := SurvivorData.pick_zone_enemy(pool, 999, tgt_lvl)  ## 空战中队不受 token 预算限制
	var etype: int = int(picked.get("type", SurvivorSpawner.EnemyType.F86))
	## 中队规模也按星级放大：★4 / ★★5 / ★★★6（2026-07-06 密度调优）
	var squadron_count: int = SurvivorData.air_squadron_count_for_difficulty(difficulty)
	## 任务丰富化（2026-07-06）：长机用高一档机型（tgt_lvl+2 选型），僚机维持 tgt_lvl —— "队长机"质感
	var leader_etype: int = etype
	var lead_pick := SurvivorData.pick_zone_enemy(
			SurvivorData.get_zone_enemy_pool(tgt_lvl + 2, true, true), 999, tgt_lvl + 2)
	if not lead_pick.is_empty():
		leader_etype = int(lead_pick.get("type", etype))
	## 轨道半径随战区半径撑开（战区 3500 时 ≈1680，占住扩大后的圈）
	var orbit_r: float = maxf(AIR_SQUADRON_ORBIT_RADIUS, float(zone["radius"]) * AIR_SQUADRON_ORBIT_RADIUS_FRAC)

	# 长机在地图边界外生成，机头指向战区；进入巡逻环后按既有航点盘旋。
	var leader_pos := _zone_air_spawn_origin(center)
	var heading_deg := _zone_air_heading_deg(leader_pos, center)
	var heading_rad := deg_to_rad(heading_deg)

	# 预生成长机盘旋航点（绕战区中心），仅长机持有
	var leader_waypoints := PackedVector2Array()
	for k in range(AIR_SQUADRON_PATROL_WAYPOINTS):
		var wa := float(k) / float(AIR_SQUADRON_PATROL_WAYPOINTS) * TAU
		leader_waypoints.append(center + Vector2(cos(wa), sin(wa)) * orbit_r)
	# 先切入靠近入场边的环点，避免横穿战区中心。
	var start_idx := _zone_patrol_entry_index(leader_pos, center,
		AIR_SQUADRON_PATROL_WAYPOINTS)

	var sq := SquadFactory.create()
	sq.formation = Squad.random_formation()  # 杂鱼随机阵型（凝聚已由 FOLLOW_LEADER 默认继承）
	for i in range(squadron_count):
		var spawn_pos: Vector2
		if i == 0:
			spawn_pos = leader_pos
		else:
			# 僚机按编队偏移从长机侧后方展开（真正的编队，不是独立绕圈）
			var offset := sq.get_formation_offset(i)
			spawn_pos = leader_pos + offset.rotated(heading_rad)

		var ac: Aircraft = _spawner._create_enemy(leader_etype if i == 0 else etype, spawn_pos, heading_deg)
		if not ac:
			continue
		# 入场完成前豁免远距冻结；到达巡逻环后由 spawner 8s 航点 tick 清标。
		_tag_zone_air_ingress(ac, center,
			orbit_r + ZONE_AIR_INGRESS_ARRIVE_BAND_PX)
		ac.set_meta("zone_mission", zone_id)

		if i == 0:
			SquadFactory.register_leader(sq, ac)
		else:
			SquadFactory.register_wingman(sq, ac, true)  # Step 4：显式进 SQUAD_FOLLOW

		var ai := _get_ai_of(ac)
		if ai:
			# 所有成员都持有同一套盘旋航点：SQUAD_FOLLOW 期间航点被忽略；
			# 长机阵亡后僚机回退 PATROL 时，能独立绕战区盘旋而不是直线平飞出圈
			ai.waypoints = leader_waypoints
			# 错开起点 index，避免几架飞机堆在同一个航点上
			ai.current_waypoint_index = (start_idx + i) % AIR_SQUADRON_PATROL_WAYPOINTS
		units.append(ac)

	_spawned_zones[zone_id] = units
	# TGT 标记在玩家进入战区（mission_triggered）时才打上，预刷阶段不标
	EventLogger.log_event("ZONE", "PreSpawnAir",
		"id=%s type=%d aircraft=%d lvl=%d tgt_lvl=%d diff=%d entry=%s center=%s"
		% [zone_id, etype, units.size(), lvl, tgt_lvl, difficulty,
		leader_pos.round(), center])

## 驻守敌机：Token 预算制（2026-04-21 改）
##
## 预算公式：SurvivorData.zone_defender_budget(difficulty, player_level)
##   ★    8  × (1 + 0.08 × (level-1))   —— Lv10 ≈ 14
##   ★★  15 × (1 + 0.08 × (level-1))   —— Lv10 ≈ 26
##   ★★★ 30 × (1 + 0.08 × (level-1))   —— Lv10 ≈ 52
##
## 以"中队"为单位切分预算：每次从等级加权池抽一种机型，按 cost 决定中队规模
## （便宜的杂鱼 4 架 / 中价 3 架 / 精英 2 架），够预算就组一队，不够就缩减或停止。
##
## 【硬规则】Sentinel 绝不出现在驻守池里，永远通过 _spawn_commander_squad（随机刷新）/
## _spawn_sentinel_garrison（战区驻守障碍）带队登场，不允许以单架驻守机形式出现。
##
## 【原则】Token 不必占满，优先让玩家能应对当前等级（超纲敌人由等级钟形权重过滤）。

## 按 cost 决定"中队"规模（包括长机）
static func _squad_size_for_cost(cost: int) -> int:
	if cost <= 2:
		return 4  ## MQ-109/MQ-110/F-4E：4 架杂鱼群
	if cost <= 3:
		return 3  ## F-86/A-7：3 架轻量编队
	if cost <= 4:
		return 3  ## MiG-23/MiG-29/Q-5：3 架主力编队
	if cost <= 5:
		return 2  ## J-7/F-100：2 架打带跑对
	return 2      ## Su-27/MiG-31：2 架精英对（受 INSTANCE_CAP 天然限制）

func _spawn_zone_defenders(zone_id: StringName, zone: Dictionary, mission_type: String = "ground") -> void:
	if not _spawner or not _zones:
		return
	var difficulty: int = _zones.get_difficulty(zone_id)
	var lvl: int = _player_level()
	## 驻守虚拟等级：★★/★★★ 提升护卫池子等级，避免低级玩家满屏 MQ-109/MQ-110/F-4E
	var g_vlvl: int = SurvivorData.zone_virtual_level(difficulty, lvl, "garrison")
	var budget: int = SurvivorData.zone_defender_budget(difficulty, lvl)  ## 预算仍按真实等级（让强敌自然减量）
	var exclude_sentinel: bool = true  ## 驻守池硬规则：Sentinel 永不单刷

	## Sentinel 战区驻守障碍（spec early-game-uav-rework §2.4B）：elite 任务移除后，
	## Sentinel 偶尔以"驻守障碍"形式带 MQ-109 小队出现——非 TGT，可绕可打。
	## 唯一性：场上已有 Sentinel（含随机刷新的）就不出；出现时驻守预算减半防双倍叠加。
	if mission_type != "naval" and mission_type != "airfield" \
			and randf() < SENTINEL_GARRISON_CHANCE \
			and _count_type_in_scene(int(SurvivorSpawner.EnemyType.UAV_COMMANDER)) == 0:
		_spawn_sentinel_garrison(zone_id, zone)
		budget = int(budget * 0.5)

	var center: Vector2 = zone["center"]
	## 驻守环随战区半径撑开（战区 3500 时 ≈2520，填满扩大后的圈）
	var garrison_r: float = maxf(GARRISON_ORBIT_RADIUS, float(zone["radius"]) * GARRISON_ORBIT_RADIUS_FRAC)
	var units: Array[Aircraft] = []
	var guard := 12  ## 死循环保险（每循环刷一整队）

	while budget > 0 and guard > 0:
		guard -= 1
		## 等级加权池，优先中队友好（排除 MiG-31 这种强制单机）
		var pool := SurvivorData.get_zone_enemy_pool(g_vlvl, exclude_sentinel, true)
		if pool.is_empty():
			break
		var pick := SurvivorData.pick_zone_enemy(pool, budget, g_vlvl)
		if pick.is_empty():
			break
		var etype: int = int(pick["type"])
		var cost: int = int(pick["cost"])
		## 中队规模：按 cost 决定，再用预算夹一次（至少 1）
		var want_size: int = _squad_size_for_cost(cost)
		var affordable: int = int(floor(float(budget) / float(cost)))
		var squad_size: int = mini(want_size, maxi(affordable, 1))
		## 实例上限：若剩余允许不足 2，就只刷 1 架（避免组不成队又硬塞）
		var type_cap: int = int(SurvivorData.TOKEN_INSTANCE_CAP.get(etype, -1))
		if type_cap > 0:
			var room: int = type_cap - _count_type_in_scene(etype)
			if room <= 0:
				## 占满了就换下一种（把这种从后续抽取里排掉需重跑池子；简单起见直接跳本轮）
				continue
			squad_size = mini(squad_size, room)

		var leader_pos := _zone_air_spawn_origin(center)
		var heading_deg := _zone_air_heading_deg(leader_pos, center)
		var heading_rad := deg_to_rad(heading_deg)

		## 预生成盘旋航点（绕战区中心）—— 全队共用
		var wp := PackedVector2Array()
		var n_wp := 4
		for k in range(n_wp):
			var wa := float(k) / float(n_wp) * TAU
			wp.append(center + Vector2(cos(wa), sin(wa)) * garrison_r)
		var start_wp_idx := _zone_patrol_entry_index(leader_pos, center, n_wp)

		var sq := SquadFactory.create()
		sq.formation = Squad.random_formation()  # 杂鱼随机阵型（凝聚已由 FOLLOW_LEADER 默认继承）
		var spawned_in_squad := 0
		for i in range(squad_size):
			if cost > budget:
				break  ## 预算吃空
			var spawn_pos: Vector2
			if i == 0:
				spawn_pos = leader_pos
			else:
				var offset: Vector2 = sq.get_formation_offset(i)
				spawn_pos = leader_pos + offset.rotated(heading_rad)
			var ac: Aircraft = _spawner._create_enemy(etype, spawn_pos, heading_deg)
			if not ac:
				## 实例上限击中 → 放弃该队剩余槽位
				break
			_tag_zone_air_ingress(ac, center,
				garrison_r + ZONE_AIR_INGRESS_ARRIVE_BAND_PX)
			ac.set_meta("zone_garrison", zone_id)
			if i == 0:
				SquadFactory.register_leader(sq, ac)
			else:
				SquadFactory.register_wingman(sq, ac, true)  # Step 4：显式进 SQUAD_FOLLOW
			var ai := _get_ai_of(ac)
			if ai:
				## 长机走航点盘旋；僚机由 SQUAD_FOLLOW 跟随；长机阵亡后僚机自然转 PATROL
				ai.waypoints = wp
				ai.current_waypoint_index = (start_wp_idx + i) % n_wp
			units.append(ac)
			budget -= cost
			spawned_in_squad += 1
		## 如果这一队一架都没刷出来（通常是 cap 击中且 room=0），guard 会逐步耗尽
		if spawned_in_squad == 0:
			continue

	_garrison_zones[zone_id] = units
	EventLogger.log_event("ZONE", "Garrison",
		"id=%s diff=%d lvl=%d mission=%s defenders=%d edge_ingress=%d budget_left=%d"
		% [zone_id, difficulty, lvl, mission_type, units.size(), units.size(), budget])

## 场景中某类型当前活着的敌机数（给 instance cap 检查用）
func _count_type_in_scene(etype: int) -> int:
	var count := 0
	for child in mode.get_children():
		if child is Aircraft and child.team == CombatUnit.TEAM_HOSTILE and not child.is_destroyed:
			if int(child.get_meta("enemy_type_idx", -1)) == etype:
				count += 1
	return count

## 当前玩家等级；spawner.survivor_player 不可用时回退 1
func _player_level() -> int:
	if _spawner and _spawner.survivor_player:
		return int(_spawner.survivor_player.level)
	return 1

## Sentinel 战区驻守障碍（spec early-game-uav-rework §2.4B，取代已移除的 elite 任务）：
## Sentinel + 6-10 架 MQ-109 作为驻守小队绕区盘旋——**非 TGT**，完成判定不看它，
## 玩家可以全程无视绕开。攻克战区后随驻守撤离。
## Sentinel 永远带小队出现，绝不单独部署
## （Aura 会持续招募路过的 is_unmanned 飞机；但初始必须有固定护卫，防止单架裸奔）
const SENTINEL_GARRISON_CHANCE := 0.25       ## 每个战区首刷时 roll 一次（待 playtest 校准）
const SENTINEL_GARRISON_ESCORT_MIN := 6      ## 最少护卫数（MQ-109）（沿用 2026-07-06 密度调优值）
const SENTINEL_GARRISON_ESCORT_MAX := 10     ## 最多护卫数
func _spawn_sentinel_garrison(zone_id: StringName, zone: Dictionary) -> void:
	if not _spawner:
		return
	var center: Vector2 = zone["center"]
	var garrison: Array = _garrison_zones.get(zone_id, [])
	var garrison_r: float = maxf(GARRISON_ORBIT_RADIUS,
		float(zone["radius"]) * GARRISON_ORBIT_RADIUS_FRAC)
	var leader_pos := _zone_air_spawn_origin(center)
	var heading_deg := _zone_air_heading_deg(leader_pos, center)
	var ac: Aircraft = _spawner._create_enemy(
		SurvivorSpawner.EnemyType.UAV_COMMANDER, leader_pos, heading_deg)
	if not ac:
		return
	_tag_zone_air_ingress(ac, center,
		garrison_r + ZONE_AIR_INGRESS_ARRIVE_BAND_PX)
	ac.set_meta("zone_garrison", zone_id)
	# 挂载光环 + 视觉覆盖（仿照 survivor_spawner._spawn_commander_squad）
	var aura := CommanderAura.new()
	aura.name = "CommanderAura"
	ac.add_child(aura)
	var overlay := CommanderOverlay.new()
	overlay.name = "CommanderOverlay"
	ac.add_child(overlay)
	# 绑定 Squad，让 aura._try_recruit 能运作 + 僚机能挂上来
	var sq := SquadFactory.create()
	SquadFactory.register_leader(sq, ac)
	var leader_ai := _get_ai_of(ac)
	if leader_ai:
		## 长机绕驻守环盘旋（与普通驻守机同一半径规则）
		var wp := PackedVector2Array()
		var n_wp := 4
		for k in range(n_wp):
			var wa := float(k) / float(n_wp) * TAU
			wp.append(center + Vector2(cos(wa), sin(wa)) * garrison_r)
		leader_ai.waypoints = wp
		leader_ai.current_waypoint_index = _zone_patrol_entry_index(
			leader_pos, center, n_wp)
	garrison.append(ac)

	# Sentinel 自带 MQ-109 小队（光环 buff 的作用对象，硬性 ≥ 5 架，纯 MQ-109）
	# 设计约束：与随机刷怪路径 `SurvivorSpawner._spawn_commander_squad` 保持一致。
	#   战区的通用混编护卫由 `_spawn_zone_defenders` 另外独立刷出，与此无关。
	var escort_count := randi_range(SENTINEL_GARRISON_ESCORT_MIN, SENTINEL_GARRISON_ESCORT_MAX)
	for i in range(escort_count):
		var rand_angle := randf() * TAU
		var rand_dist := randf_range(220.0, 420.0)
		var spawn_pos := leader_pos + Vector2(cos(rand_angle), sin(rand_angle)) * rand_dist
		var wingman: Aircraft = _spawner._create_enemy(
			SurvivorSpawner.EnemyType.UAV, spawn_pos, heading_deg)
		if not wingman:
			continue
		_tag_zone_air_ingress(wingman, center,
			garrison_r + ZONE_AIR_INGRESS_ARRIVE_BAND_PX)
		wingman.set_meta("zone_garrison", zone_id)
		wingman.set_meta("sentinel_native_escort", true)
		sq.add_member(wingman)
		var wai := _get_ai_of(wingman)
		if wai:
			wai.squad = sq
			wai.squad_index = i + 1
			wai.orbit_squad_leader = true
			wai.shield_leader = true
			wai.enable_combat = true
			wai.evade_missiles = false
			wai.aggression = randf_range(0.7, 0.95)
			wai.waypoints = PackedVector2Array()
		garrison.append(wingman)
	_garrison_zones[zone_id] = garrison
	EventLogger.log_event("ZONE", "SentinelGarrison",
		"id=%s entry=%s center=%s escorts=%d lvl=%d diff=%d (obstacle, not TGT)"
		% [zone_id, leader_pos.round(), center, escort_count, _player_level(),
		_zones.get_difficulty(zone_id) if _zones else 1])

## 海上舰队 —— 按难度缩放编队组成；数量对齐空战任务的 4/5/6 个 TGT。
##   1★ = 4 FFG
##   2★ = 2 DDG + 3 FFG
##   3★ = 1 CG + 2 DDG + 3 FFG
## 安全方案实际保留的每艘船都是 TGT，必须全灭才完成任务。
const _NAVAL_FLEET_DDG_PARAMS_PATH := "res://resources/naval/destroyer_ddg.tres"
const _NAVAL_FLEET_FFG_PARAMS_PATH := "res://resources/naval/frigate_ffg.tres"
const _NAVAL_FLEET_CG_PARAMS_PATH := "res://resources/naval/cruiser_cg.tres"

## 编成表是舰型数量的代码 SSOT；首项为旗舰，其余项与 NAVAL_ESCORT_OFFSETS 同序。
const NAVAL_FLEET_COMPOSITIONS: Dictionary = {
	1: [&"FFG", &"FFG", &"FFG", &"FFG"],
	2: [&"DDG", &"DDG", &"FFG", &"FFG", &"FFG"],
	3: [&"CG", &"DDG", &"DDG", &"FFG", &"FFG", &"FFG"],
}

# ── 舰队几何（2026-07-28 重做：直线往返 → 恒定盘旋 + 水域校验）──
## 旧写法：旗舰沿 `center.x ± radius×0.7~0.85` 走东西直线、端点 180° U-turn，僚舰偏移最大 2600 px，
## 且**一次水域校验都没有**。战区 E（浦贺水道，radius 2500）实测舰队扫过半径 3331/3897/4725 px，
## 采样点 9.7% / 15.7% / 16.0% 落在陆地上 —— 玩家看到的"船开到陆地上"就是这个。
## 该水域能容下的最大全水圆只有 ~2750 px 半径，所以**编队必须缩到装得进去**，挪位置解决不了。
## 新写法：旗舰绕摆位圆心恒定盘旋（不掉头，见 NavalUnit.patrol_center），僚舰刚体跟随，
## 摆位圆心经 NavalPlacement 按"6 个转位 × 全部船位"打分挑水面最干净的一处。
const NAVAL_RING_RADIUS: float = 900.0        ## 旗舰盘旋半径（各档统一）
## 盘旋半径降级序列：水域装不下就缩圈，最后 0 = 原地驻泊（宁可不动，也不许开上岸）
const NAVAL_RING_CANDIDATES: Array = [NAVAL_RING_RADIUS, 450.0, 0.0]
const NAVAL_LEADER_HEADING_DEG: float = 90.0  ## 旗舰初始朝向（正东）；驻泊降级时决定整队摆放朝向
## 摆位候选圆心偏移（由近及远，八方向）—— 原位优先，不行才往外挪
const NAVAL_PLACEMENT_NUDGE_RADII: Array = [900.0, 1800.0]
## 各难度的僚舰偏移（旗舰本地系：+X 船头 / +Y 右舷）
## 占地半径 = NAVAL_RING_RADIUS + max|offset|，必须 ≤ 战区可用水域半径
const NAVAL_ESCORT_OFFSETS: Dictionary = {
	1: [Vector2(-675, -975), Vector2(-675, 975), Vector2(-1250, 0)],
	2: [Vector2(900, 0), Vector2(-420, -1260), Vector2(-420, 1260), Vector2(-1100, 0)],
	3: [Vector2(850, -300), Vector2(850, 300), Vector2(-620, -1488),
		Vector2(-620, 1488), Vector2(-1250, 0)],
}

func _spawn_naval_fleet(zone_id: StringName, zone: Dictionary) -> bool:
	var center: Vector2 = zone["center"]
	var difficulty: int = _zones.get_difficulty(zone_id) if _zones else 1

	var ffg_params: Resource = load(_NAVAL_FLEET_FFG_PARAMS_PATH)
	if ffg_params == null:
		push_error("ZoneMission _spawn_naval_fleet: missing FFG params")
		return false

	var spawned := _spawn_naval_formation(zone_id, center, difficulty, ffg_params)
	if not spawned:
		EventLogger.log_event("ZONE", "NavalFallbackAir",
			"id=%s star=%d reason=no_zero_land_placement" % [zone_id, difficulty])
		return false

	EventLogger.log_event("ZONE", "PreSpawnNaval",
		"id=%s star=%d" % [zone_id, difficulty])
	return true

## 编队设计（2026-07-28 重做）：
##   旗舰绕摆位圆心**恒定盘旋**（NavalUnit.patrol_center/patrol_radius，全程不掉头），
##   僚舰 formation_leader = 旗舰、刚体跟随固定偏移（+X = 船头方向，+Y = 右舷）
##   摆位圆心经 NavalPlacement 打分（6 个转位 × 全部船位）挑水面最干净的一处
##
## 为什么不再走"直线往返 + U-turn"：僚舰是刚体跟随，掉头一次 = 整队原地旋转
## （见 changelog 2026-07-28 naval-formation-spin-fix）；而直线往返的航程 + 编队偏移
## 会把舰队甩出战区、开到陆地上（战区 E 实测 16% 采样点在岸上）。
##
## 编成由 NAVAL_FLEET_COMPOSITIONS 驱动；安全方案保留的全舰都是任务目标。
func _spawn_naval_formation(zone_id: StringName, center: Vector2, difficulty: int,
		ffg_params: Resource) -> bool:
	var ddg_params: Resource = load(_NAVAL_FLEET_DDG_PARAMS_PATH)
	var cg_params: Resource = load(_NAVAL_FLEET_CG_PARAMS_PATH)
	if ddg_params == null or cg_params == null:
		push_error("ZoneMission naval: missing DDG / CG params")
		return false

	var composition: Array = NAVAL_FLEET_COMPOSITIONS.get(difficulty, NAVAL_FLEET_COMPOSITIONS[1])
	var ship_classes: Array = []
	var ship_params: Array[Resource] = []
	for kind_any in composition:
		var kind: StringName = kind_any
		match kind:
			&"CG":
				ship_classes.append(CruiserShip)
				ship_params.append(_tier3_naval_params(cg_params) if difficulty == 3 else cg_params)
			&"DDG":
				ship_classes.append(DestroyerShip)
				ship_params.append(_tier3_naval_params(ddg_params) if difficulty == 3 else ddg_params)
			_:
				ship_classes.append(FrigateShip)
				ship_params.append(_tier3_naval_params(ffg_params) if difficulty == 3 else ffg_params)

	var full_offsets: Array = NAVAL_ESCORT_OFFSETS.get(difficulty, NAVAL_ESCORT_OFFSETS[1])
	if ship_classes.size() != full_offsets.size() + 1:
		push_error("ZoneMission naval composition/offset mismatch: star=%d ships=%d offsets=%d"
			% [difficulty, ship_classes.size(), full_offsets.size()])
		return false
	# 先完成全部水域计算，再实例化任何舰船：完整编成无解就逐艘移除最外侧护卫，
	# 最终宁可单旗舰驻泊；连单舰都无解则返回 false，由调用方原子退化为空战。
	var plan := safe_naval_plan(center, difficulty)
	if plan.is_empty():
		return false
	var placement: Dictionary = plan["placement"]
	var kept_indices: Array = plan["escort_indices"]
	var offsets: Array = plan["offsets"]
	var ring_center: Vector2 = placement["center"]
	var ring: float = float(placement["ring"])
	var land_hits: int = int(placement["land"])
	EventLogger.log_event("ZONE", "NavalPlacement",
			"id=%s star=%d center=(%d,%d) ring=%d reach=%d land=%d escorts=%d/%d" % [zone_id, difficulty,
			roundi(ring_center.x), roundi(ring_center.y), roundi(ring),
			roundi(NavalPlacement.fleet_reach(ring, offsets)), land_hits,
			kept_indices.size(), full_offsets.size()])
	# safe_naval_plan 的唯一成功契约；保留断言防未来调用路径绕过硬闸。
	if land_hits != 0:
		push_error("ZoneMission naval hard gate violated: %s land=%d" % [zone_id, land_hits])
		return false

	# 旗舰：出生点落在盘旋圆上（圆心在右舷），初始 heading 恰好是切线 → 无入圈瞬态
	var heading_deg: float = NAVAL_LEADER_HEADING_DEG
	var leader_spawn: Vector2 = NavalPlacement.leader_pos(
			ring_center, ring, deg_to_rad(heading_deg))
	var leader: NavalUnit = _make_zone_ship(ship_classes[0].new(), ship_params[0], leader_spawn,
			heading_deg, PackedVector2Array(), zone_id)
	# ring = 0（窄水域降级）→ patrol 模式关闭，舰队原地驻泊
	leader.patrol_center = ring_center if ring > 1.0 else Vector2.INF
	leader.patrol_radius = ring

	var escort: Array = []
	for local_i in range(kept_indices.size()):
		var source_i: int = int(kept_indices[local_i])
		var off: Vector2 = offsets[local_i]
		var pos: Vector2 = _compute_formation_world_pos(leader, off)
		var ship: NavalUnit = _make_zone_ship(ship_classes[source_i + 1].new(), ship_params[source_i + 1], pos,
				heading_deg, PackedVector2Array(), zone_id)
		ship.formation_leader = leader
		ship.formation_offset = off
		escort.append(ship)
	_spawned_zones[zone_id] = build_naval_target_roster(leader, escort)
	return true


## 只复制并延长 VLS 弹体的真实可达距离/寿命；CIWS、Flak、SAM、舰体和冷却保持普通舰队值。
## 外部 .tres 绝不原地改，避免一个 3★ 把后续 1★/2★舰队一并升级。
static func _tier3_naval_params(source: Resource) -> Resource:
	var original := source as NavalParams
	if original == null:
		return source
	var cloned := original.duplicate() as NavalParams
	var mount_configs: Array[WeaponMountParams] = []
	var has_vls := false
	for original_mount in original.mount_configs:
		var mount := original_mount.duplicate() as WeaponMountParams
		if mount.weapon_type == WeaponMountParams.WeaponType.VLS_SALVO \
				and original_mount.weapon_params is MissileParams:
			var missile := (original_mount.weapon_params as MissileParams).duplicate() as MissileParams
			missile.max_range_rear = maxf(missile.max_range_rear, TIER3_VLS_RANGE_M)
			missile.max_lifetime = maxf(missile.max_lifetime, TIER3_VLS_LIFETIME_S)
			mount.weapon_params = missile
			has_vls = true
		mount_configs.append(mount)
	cloned.mount_configs = mount_configs
	if has_vls:
		cloned.set_meta(&"tier3_vls_source", true)
	return cloned

## 安全方案实际生成的全舰登记为 TGT；集中成纯 helper，防止未来又退化成只登记旗舰。
static func build_naval_target_roster(leader: NavalUnit, escorts: Array) -> Array:
	var targets: Array = [leader]
	leader.is_mission_target = true
	for ship_any in escorts:
		var ship := ship_any as NavalUnit
		if ship == null:
			continue
		ship.is_mission_target = true
		targets.append(ship)
	return targets

## 对舰摆位纯规划：完整编成无全水解时，每轮移除轨道半径最大的护卫再试。
## 返回空字典 = 连单旗舰原地驻泊都没有安全位置，调用方必须零舰船 fallback。
static func safe_naval_plan(center: Vector2, difficulty: int,
		placement_picker: Callable = Callable()) -> Dictionary:
	var full_offsets: Array = NAVAL_ESCORT_OFFSETS.get(difficulty, NAVAL_ESCORT_OFFSETS[1])
	var kept_indices: Array = []
	for i in range(full_offsets.size()):
		kept_indices.append(i)
	var nudges := NavalPlacement.ring_nudges(NAVAL_PLACEMENT_NUDGE_RADII)
	var heading_rad := deg_to_rad(NAVAL_LEADER_HEADING_DEG)
	while true:
		var offsets: Array = []
		for source_i in kept_indices:
			offsets.append(full_offsets[int(source_i)])
		var placement: Dictionary
		if placement_picker.is_valid():
			# 测试 seam：注入人工海岸几何的摆位结果，不参与运行时路径。
			placement = placement_picker.call(offsets)
		else:
			placement = NavalPlacement.pick_placement(
					center, nudges, NAVAL_RING_CANDIDATES, offsets, heading_rad)
		if int(placement.get("land", -1)) == 0:
			return {
				"placement": placement,
				"escort_indices": kept_indices.duplicate(),
				"offsets": offsets,
			}
		if kept_indices.is_empty():
			return {}
		var drop_at := 0
		var farthest := -1.0
		for j in range(kept_indices.size()):
			var source_i: int = int(kept_indices[j])
			var r: float = (full_offsets[source_i] as Vector2).length()
			# >= 让同半径时优先移除数组尾部，保留编成表前面的高价值护卫。
			if r >= farthest:
				farthest = r
				drop_at = j
		kept_indices.remove_at(drop_at)
	# GDScript 的静态返回分析不把 while true 视为穷尽；运行时不会抵达这里。
	return {}

## 根据 leader 当前位置 / 朝向 + 编队偏移算出僚舰初始世界坐标
func _compute_formation_world_pos(leader: NavalUnit, offset: Vector2) -> Vector2:
	var lead_fwd := Vector2(sin(leader.heading), -cos(leader.heading))
	var lead_stb := Vector2(cos(leader.heading), sin(leader.heading))
	return leader.global_position + lead_fwd * offset.x + lead_stb * offset.y

## 通用船只创建 + 注入 manager + 打 meta 标签
func _make_zone_ship(ship: NavalUnit, params_res: Resource, pos: Vector2, heading_deg: float, wps: PackedVector2Array, zone_id: StringName) -> NavalUnit:
	ship.params = params_res
	ship.position = pos
	ship.initial_heading_deg = heading_deg
	ship.waypoints = wps
	ship.set_meta("zone_mission", zone_id)
	ship.set_meta("category", "zone_naval")
	ship.set_meta("skip_far_cleanup", true)
	if params_res != null and params_res.has_meta(&"tier3_vls_source"):
		ship.set_meta(&"tier3_special_unit", true)
		ship.set_meta(&"tier3_threat_source", true)
		ship.set_meta(&"tier3_profile", &"long_range_vls")
	mode.add_child(ship)
	_inject_ship_managers(ship)
	return ship

## 给船注入 bullet / missile manager（zone_mission.mode 就是 survivor_mode）
func _inject_ship_managers(ship: NavalUnit) -> void:
	if "bullet_manager" in mode:
		ship.bullet_manager = mode.bullet_manager
	if "missile_manager" in mode:
		ship.missile_manager = mode.missile_manager

## 攻克战区后，让驻守机"撤离"
## 【铁则】不允许在玩家画面内消失 —— 视线内的单位入队等它飘出屏外再 free
func _despawn_garrison(zone_id: StringName) -> void:
	var units: Array = _garrison_zones.get(zone_id, [])
	for u in units:
		_schedule_despawn(u)
	_garrison_zones.erase(zone_id)

func _get_ai_of(ac: Aircraft) -> AIController:
	for child in ac.get_children():
		if child is AIController:
			return child
	return null

## 星级 → 支援规模的单杠杆映射（1★/2★/3★ = 2/3/4）。
static func support_count_for_difficulty(difficulty: int) -> int:
	return clampi(difficulty + 1, 2, 4)

## 合资格任务首次 ACTIVE 时登记一支待入场友军；未触发任务绝不预刷。
func _start_air_support_if_needed(zone_id: StringName, zone: Dictionary) -> void:
	if not _spawner or _active_support_by_zone.has(zone_id):
		return
	var mission_type := _zones.get_mission_type(zone_id) if _zones else String(zone.get("mission_type", ""))
	var formal_run: bool = mode != null and mode.has_method("archive_enabled") \
			and bool(mode.call("archive_enabled"))
	var support_kind := ""
	var support_count := 0
	if mission_type == "air" or mission_type == "squadron":
		if not MetaShop.is_zone_air_support_entitled(formal_run):
			return
		support_kind = "fighter"
		support_count = support_count_for_difficulty(_zones.get_difficulty(zone_id))
	elif mission_type == "ground":
		if not MetaShop.is_zone_ground_support_entitled(formal_run):
			return
		support_kind = "attack"
		support_count = SUPPORT_GROUND_COUNT
	else:
		return
	if _support_dispatched_kinds.has(support_kind):
		return
	_support_dispatched_kinds[support_kind] = true
	_support_generation += 1
	var flight := {
		"id": _support_generation,
		"zone_id": zone_id,
		"zone": zone.duplicate(true),
		"phase": SupportPhase.INGRESS_PENDING,
		"members": [],
		"anchor": null,
		"hp_watch": 0.0,
		"reengage_s": 0.0,
		"support_kind": support_kind,
		"support_count": support_count,
	}
	_support_flights.append(flight)
	_active_support_by_zone[zone_id] = _support_generation
	EventLogger.log_event("ZONE", "AirSupportRequested",
		"id=%s kind=%s star=%d count=%d" % [zone_id, support_kind,
		_zones.get_difficulty(zone_id), support_count])

## 生命周期统一低频 tick：只扫每支 2~4 架的持有数组，不做全场扫描。
func _update_air_support(delta: float) -> void:
	if _support_flights.is_empty():
		return
	_support_tick_accum += delta
	if _support_tick_accum < SUPPORT_TICK_S:
		return
	var step := _support_tick_accum
	_support_tick_accum = 0.0
	for i in range(_support_flights.size() - 1, -1, -1):
		var flight: Dictionary = _support_flights[i]
		var phase: int = int(flight.get("phase", SupportPhase.INGRESS_PENDING))
		match phase:
			SupportPhase.INGRESS_PENDING:
				if _try_spawn_air_support(flight):
					flight["phase"] = SupportPhase.ON_STATION
			SupportPhase.ON_STATION:
				if _support_live_members(flight).is_empty():
					_finish_air_support_flight(i, flight)
					continue
			SupportPhase.EGRESS:
				if _tick_air_support_egress(flight, step):
					_finish_air_support_flight(i, flight)
					continue
		_support_flights[i] = flight

## 从战区外缘附近的镜头外点物理入场。优先玩家机头前半球；八点全可见就下次 tick 重试。
func _support_spawn_point(zone: Dictionary) -> Vector2:
	var center: Vector2 = zone["center"]
	var spawn_r := maxf(SUPPORT_SPAWN_MIN_RADIUS_PX,
		float(zone["radius"]) * SUPPORT_SPAWN_RADIUS_FRAC)
	var player_pos := _player.global_position
	var player_fwd := Vector2(sin(_player.heading), -cos(_player.heading))
	var jitter := randf() * TAU
	var best_forward := Vector2.INF
	var best_forward_d := INF
	var best_any := Vector2.INF
	var best_any_d := INF
	for k in range(SUPPORT_SPAWN_CANDIDATES):
		var a := jitter + TAU * float(k) / float(SUPPORT_SPAWN_CANDIDATES)
		var cand := center + Vector2(cos(a), sin(a)) * spawn_r
		if mode and mode.has_method("is_world_pos_visible") \
				and mode.is_world_pos_visible(cand, SUPPORT_SPAWN_VISUAL_REACH_PX):
			continue
		var d := cand.distance_to(player_pos)
		if d < best_any_d:
			best_any_d = d
			best_any = cand
		var from_player := (cand - player_pos).normalized()
		if player_fwd.dot(from_player) > 0.0 and d < best_forward_d:
			best_forward_d = d
			best_forward = cand
	return best_forward if best_forward != Vector2.INF else best_any

func _try_spawn_air_support(flight: Dictionary) -> bool:
	var zone: Dictionary = flight["zone"]
	var spawn_center := _support_spawn_point(zone)
	if spawn_center == Vector2.INF:
		return false
	var center: Vector2 = zone["center"]
	var to_center := (center - spawn_center).normalized()
	var heading_rad := atan2(to_center.x, -to_center.y)
	var heading_deg := rad_to_deg(heading_rad)
	var zone_id: StringName = flight["zone_id"]
	var count := int(flight.get("support_count", 0))
	var support_kind := String(flight.get("support_kind", "fighter"))

	var anchor := Node2D.new()
	anchor.name = "ZoneAirSupportAnchor_%s_%d" % [zone_id, int(flight["id"])]
	anchor.position = center
	mode.add_child(anchor)

	var orbit_r := maxf(SUPPORT_ORBIT_MIN_RADIUS_PX,
		float(zone["radius"]) * SUPPORT_ORBIT_RADIUS_FRAC)
	var waypoints := PackedVector2Array()
	var entry_angle := (spawn_center - center).angle()
	for k in range(AIR_SQUADRON_PATROL_WAYPOINTS):
		var a := entry_angle + TAU * float(k + 1) / float(AIR_SQUADRON_PATROL_WAYPOINTS)
		waypoints.append(center + Vector2(cos(a), sin(a)) * orbit_r)

	var sq := SquadFactory.create()
	sq.formation = Squad.random_formation()
	var members: Array = []
	for i in range(count):
		var spawn_pos := spawn_center
		if i > 0:
			spawn_pos += sq.get_formation_offset(i).rotated(heading_rad)
		var ac: Aircraft
		if support_kind == "attack":
			ac = _create_a10_support(spawn_pos, heading_deg)
		else:
			ac = _spawner._create_enemy(SUPPORT_FIGHTER_TYPE, spawn_pos, heading_deg)
		if ac == null:
			continue
		if ac.team != CombatUnit.TEAM_ALLY:
			AllyForce.convert_aircraft(ac)
		ac.set_meta("zone_support", zone_id)
		ac.set_meta("air_targets_only", support_kind == "fighter")
		ac.set_meta("ground_targets_only", support_kind == "attack")
		# F-86 保持既有编队；两架 A-10 各自搜索 GroundUnit，避免跟随态让僚机闲置，
		# 也避免临时支援结束时留下 Aircraft ↔ Squad 的引用环。
		if support_kind == "fighter":
			if i == 0 or members.is_empty():
				SquadFactory.register_leader(sq, ac)
			else:
				SquadFactory.register_wingman(sq, ac, true)
		var ai := _get_ai_of(ac)
		if ai:
			ai.enable_combat = true
			ai.waypoints = waypoints
			ai.current_waypoint_index = i % waypoints.size()
			ai.combat_zone_anchor = anchor
			ai.combat_zone_radius = float(zone["radius"]) + SUPPORT_ZONE_LEASH_EXTRA_PX
		members.append(ac)

	if members.is_empty():
		anchor.queue_free()
		return false
	flight["members"] = members
	flight["anchor"] = anchor
	flight["hp_watch"] = _support_members_hp(members)
	EventLogger.log_event("ZONE", "AirSupportOnStation",
		"id=%s kind=%s aircraft=%d spawn=%s" % [zone_id, support_kind,
		members.size(), str(spawn_center.round())])
	return true

## 支援 A-10 走独立轻量工厂：基础机体参数 + GAU-8，去掉火箭/鱼雷并锁为只对地。
func _create_a10_support(spawn_pos: Vector2, heading_deg: float) -> Aircraft:
	if mode == null:
		return null
	var ac := _SUPPORT_AIRCRAFT_SCENE.instantiate() as Aircraft
	if ac == null:
		return null
	ac.params = _SUPPORT_A10_PARAMS.duplicate(true)
	SurvivorPlayableSetup.deep_dup_weapons(ac.params)
	ac.params.rocket = null
	ac.params.torpedo = null
	ac.position = spawn_pos
	ac.initial_heading_deg = heading_deg
	ac.bullet_manager = _bullet_manager
	ac.missile_manager = _missile_manager
	ac.flat_altitude = true
	ac.attack_air_targets = false
	ac.set_meta("ground_targets_only", true)
	AllyForce.convert_aircraft(ac)
	mode.add_child(ac)
	ac.altitude = SUPPORT_A10_ALTITUDE_M
	ac.target_altitude_tier = Aircraft.AltitudeTier.LOW
	ac.target_altitude = SUPPORT_A10_ALTITUDE_M

	var ai := AIController.new()
	ai.name = "AI_%s" % ac.name
	ai.aircraft = ac
	ai.simple_ai = true
	ai.ground_combat_only = true
	ai.enable_combat = true
	ai.patrol_altitude = SUPPORT_A10_ALTITUDE_M
	ai.engage_cooldown = 2.0
	ai.engage_duration = 30.0
	ac._ai_ref = ai
	ac.add_child(ai)
	# AIController._ready 会按 LOW 档重写一次目标高度；支援攻击机保持 3200m 驻留高度。
	ac.target_altitude = SUPPORT_A10_ALTITUDE_M
	return ac

func _support_live_members(flight: Dictionary) -> Array:
	var live: Array = []
	for m in flight.get("members", []):
		if is_instance_valid(m) and not m.is_destroyed:
			live.append(m)
	return live

func _support_members_hp(members: Array) -> float:
	var total := 0.0
	for m in members:
		if is_instance_valid(m) and not m.is_destroyed:
			total += float(m.hp)
	return total

func _begin_air_support_egress(zone_id: StringName, reason: String) -> void:
	if not _active_support_by_zone.has(zone_id):
		return
	var generation: int = int(_active_support_by_zone[zone_id])
	_active_support_by_zone.erase(zone_id)
	for i in range(_support_flights.size()):
		var flight: Dictionary = _support_flights[i]
		if int(flight.get("id", -1)) != generation:
			continue
		flight["phase"] = SupportPhase.EGRESS
		flight["reengage_s"] = 0.0
		flight["hp_watch"] = _support_members_hp(flight.get("members", []))
		_command_air_support_exit(flight)
		_support_flights[i] = flight
		EventLogger.log_event("ZONE", "AirSupportEgress",
			"id=%s aircraft=%d reason=%s" % [zone_id, _support_live_members(flight).size(), reason])
		return

func _begin_all_air_support_egress(reason: String) -> void:
	for zid in _active_support_by_zone.keys().duplicate():
		_begin_air_support_egress(zid, reason)

func _command_air_support_exit(flight: Dictionary) -> void:
	var anchor = flight.get("anchor")
	if is_instance_valid(anchor):
		anchor.queue_free()
	flight["anchor"] = null
	for m in _support_live_members(flight):
		var ac: Aircraft = m
		var ai := _get_ai_of(ac)
		if ai:
			ai.release_target(AIController.TargetSource.TS_COMMANDED, "zone support egress")
			ai.combat_zone_anchor = null
			ai.combat_zone_radius = 0.0
			ai.enable_combat = false
			ai.enter_patrol_state(false)
			ai.waypoints = PackedVector2Array([_support_exit_point(ac.global_position)])
			ai.current_waypoint_index = 0
		ac.clear_formation()
		ac.is_afterburner = true
		if ac.params:
			ac.target_speed_kmh = ac.params.max_speed

func _support_exit_point(from: Vector2) -> Vector2:
	var half := MapBoundary.world_half_px()
	var out := half + SUPPORT_EXIT_OUTSET_PX
	var sx := 1.0 if from.x >= 0.0 else -1.0
	var sy := 1.0 if from.y >= 0.0 else -1.0
	if (half - absf(from.x)) < (half - absf(from.y)):
		return Vector2(sx * out, from.y)
	return Vector2(from.x, sy * out)

## 返回 true = 该队已经全灭/全部飞出，可从生命周期数组删除。
func _tick_air_support_egress(flight: Dictionary, delta: float) -> bool:
	var live := _support_live_members(flight)
	if live.is_empty():
		return true
	var hp_now := _support_members_hp(live)
	var reengage_s := float(flight.get("reengage_s", 0.0))
	if hp_now < float(flight.get("hp_watch", hp_now)) - 0.01 and reengage_s <= 0.0:
		reengage_s = SUPPORT_WITHDRAW_REENGAGE_S
		for m in live:
			var ai := _get_ai_of(m)
			if ai:
				ai.enable_combat = true
	flight["hp_watch"] = hp_now
	if reengage_s > 0.0:
		reengage_s -= delta
		if reengage_s <= 0.0:
			_command_air_support_exit(flight)
	flight["reengage_s"] = maxf(reengage_s, 0.0)

	var survivors := 0
	for m in live:
		var ac: Aircraft = m
		if MapBoundary.distance_to_edge(ac.global_position) <= -SUPPORT_FREE_OUTSET_PX:
			ac.set_meta("xp_granted", true)
			CombatUnit.release_target_refs(ac)
			ac.queue_free()
		else:
			survivors += 1
	return survivors == 0

func _finish_air_support_flight(index: int, flight: Dictionary) -> void:
	var anchor = flight.get("anchor")
	if is_instance_valid(anchor):
		anchor.queue_free()
	var zid: StringName = flight.get("zone_id", &"")
	if _active_support_by_zone.get(zid, -1) == flight.get("id", -2):
		_active_support_by_zone.erase(zid)
	_support_flights.remove_at(index)

## 无线电只允许真实演员开口：返回本战区第一艘/架存活任务目标，不做全场扫描。
func get_live_hostile_target(zone_id: StringName) -> CombatUnit:
	for value in _spawned_zones.get(zone_id, []):
		if typeof(value) != TYPE_OBJECT or value == null or not is_instance_valid(value):
			continue
		if value is CombatUnit and not (value as CombatUnit).is_destroyed:
			return value as CombatUnit
	return null

## 地面任务完成时在气氛层注销前快照幸存友军；无幸存者即 null，感谢台词静默。
func get_surviving_atmosphere_ally(zone_id: StringName) -> CombatUnit:
	if _zone_atmosphere == null or not is_instance_valid(_zone_atmosphere) \
			or not _zone_atmosphere.has_method("first_live_ally"):
		return null
	var candidate: Variant = _zone_atmosphere.call("first_live_ally", zone_id)
	if typeof(candidate) != TYPE_OBJECT or candidate == null or not is_instance_valid(candidate):
		return null
	if not (candidate is CombatUnit):
		return null
	return candidate as CombatUnit

## 玩家是否正在至少一个活跃战区任务中（触发过但未完成）。
## 用于旅途刷怪系统判断"玩家当前是否有战区任务在身"。
func is_player_in_active_mission() -> bool:
	for zid in _triggered_zones:
		if not _completed_zones.has(zid) and not _failed_zones.has(zid):
			return true
	return false

## 战场引力（spec battlefield-gravity §2.4）：距 from_pos 最近的 triggered 未完成战区。
## 多战区并发时的单槽选择规则=最近；返回 {"center": Vector2, "units": Array}，无 → 空字典。
## units = 该战区任务目标（TGT）+ 驻守敌机（皆为"战区里的目标"，同吃任务层 +40）。
func get_nearest_triggered_objective(from_pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for z_any in ZoneData.ZONES:
		var z: Dictionary = z_any
		var zid: StringName = z["id"]
		if not _triggered_zones.has(zid) or _completed_zones.has(zid) or _failed_zones.has(zid):
			continue
		var c: Vector2 = _zones.get_zone_center(zid)
		var d := from_pos.distance_to(c)
		if d < best_d:
			best_d = d
			var units: Array = []
			units.append_array(_spawned_zones.get(zid, []))
			units.append_array(_garrison_zones.get(zid, []))
			best = {"center": c, "units": units}
	return best


## 普通失败/Debug 撤离先停火再等画外回收；BOSS 转场按已批准契约直接移除来源组件。
func _retire_tier3_unit(value: Variant, immediate: bool) -> void:
	if typeof(value) != TYPE_OBJECT or value == null or not is_instance_valid(value) \
			or not (value is CombatUnit):
		return
	var unit := value as CombatUnit
	if not bool(unit.get_meta(&"tier3_special_unit", false)):
		return
	if unit.has_method("cease_tier3_threat"):
		unit.call("cease_tier3_threat")
	elif unit is NavalUnit:
		unit.apply_status(StatusEffects.JAM, 9999.0)
	if unit is Aircraft and String(unit.get_meta(&"tier3_profile", "")) == "deadair" \
			and _spawner != null:
		_spawner.retire_deadair_source(unit as Aircraft)
	if immediate:
		CombatUnit.release_target_refs(unit)
		unit.queue_free()

## 8 分钟战区阶段结束时调用（由 survivor_mode._check_warzone_phase_timeout）：
## 取消所有战区任务 —— 已刷的 TGT 单位继续存活、可击杀给 XP，但不再发完成信号、
## 不再发奖励、UI 上 TGT 括号去掉。是"任务取消但敌人留场"的语义。
##
## 注意：本函数只清记录 + TGT 标记，不 despawn 单位。units 由 spawner 击杀流自然回收。
func cancel_all_zone_missions() -> void:
	_begin_all_air_support_egress("all missions cancelled")
	_retire_all_zone_atmosphere()
	for zid in _bomber_escort_runs.keys().duplicate():
		_retire_bomber_run(zid)
	var canceled_count := 0
	for zid in _spawned_zones.keys():
		if _zones:
			_zones.clear_dynamic_center(zid)
		var units: Array = _spawned_zones.get(zid, [])
		for u in units:
			if is_instance_valid(u) and u is CombatUnit:
				if bool(u.get_meta(&"tier3_special_unit", false)):
					_retire_tier3_unit(u, true)
					continue
				u.is_mission_target = false
				u.queue_redraw()
		_end_tier3_zone(StringName(zid))
		canceled_count += 1
	_spawned_zones.clear()
	_spawn_lead_timers.clear()
	_triggered_zones.clear()
	_completed_zones.clear()
	_failed_zones.clear()
	EventLogger.log_event("ZONE", "AllMissionsCancelled",
		"phase_ended; %d zones, TGT marks cleared, units remain combat-active" % canceled_count)

## 战区被 mark_cleared 之后调用（由 survivor_mode 在 _on_zone_mission_completed 里转发）：
## 清掉该战区的 spawn/trigger/completion 记录，让下一次该战区重新 AVAILABLE
## 时能干净地重刷一批单位。
func reset_zone(zone_id: StringName) -> void:
	_begin_air_support_egress(zone_id, "zone reset")
	_end_tier3_zone(zone_id)
	_retire_zone_atmosphere(zone_id)
	_retire_bomber_run(zone_id)
	_spawned_zones.erase(zone_id)
	_spawn_lead_timers.erase(zone_id)
	_garrison_zones.erase(zone_id)
	_triggered_zones.erase(zone_id)
	_completed_zones.erase(zone_id)
	_failed_zones.erase(zone_id)
	if _zones:
		_zones.clear_dynamic_center(zone_id)

## 失败结算的唯一入口。失败目标与驻守单位不在玩家眼前凭空消失，而是进入统一延迟撤离队列。
## ZoneData 的 FAILED 状态、奖励清理和补开战区由 survivor_mode 的 signal handler 负责。
func fail_zone(zone_id: StringName, reason: String) -> void:
	if _completed_zones.has(zone_id) or _failed_zones.has(zone_id):
		return
	_failed_zones[zone_id] = reason
	_end_tier3_zone(zone_id)
	_begin_air_support_egress(zone_id, "mission failed")
	_retire_zone_atmosphere(zone_id)
	var targets: Array = _spawned_zones.get(zone_id, [])
	for unit in targets:
		if is_instance_valid(unit) and unit is CombatUnit:
			_retire_tier3_unit(unit, false)
			unit.is_mission_target = false
			unit.queue_redraw()
			_schedule_despawn(unit)
	_spawned_zones.erase(zone_id)
	_spawn_lead_timers.erase(zone_id)
	_despawn_garrison(zone_id)
	_retire_bomber_run(zone_id)
	_triggered_zones.erase(zone_id)
	if _zones:
		_zones.clear_dynamic_center(zone_id)
	EventLogger.log_event("ZONE", "MissionFailed", "id=%s reason=%s" % [zone_id, reason])
	mission_failed.emit(zone_id, reason)

## Debug: 彻底把一个战区的敌人从世界里擦掉（不只是改 state，是真的 queue_free 单位）
## 走"视线外延迟 free"队列，铁则依然遵守
func debug_purge_zone(zone_id: StringName) -> void:
	_begin_air_support_egress(zone_id, "debug purge")
	_end_tier3_zone(zone_id)
	_retire_zone_atmosphere(zone_id)
	_retire_bomber_run(zone_id)
	# 任务目标（_spawned_zones）
	var tgts: Array = _spawned_zones.get(zone_id, [])
	for u in tgts:
		_retire_tier3_unit(u, false)
		_schedule_despawn(u)
	_spawned_zones.erase(zone_id)
	_spawn_lead_timers.erase(zone_id)
	# 驻守单位（_garrison_zones）
	_despawn_garrison(zone_id)
	# 触发/完成记录
	_triggered_zones.erase(zone_id)
	_completed_zones.erase(zone_id)
	_failed_zones.erase(zone_id)
	if _zones:
		_zones.clear_dynamic_center(zone_id)
	EventLogger.log_event("ZONE", "DebugPurge", "id=%s" % zone_id)

# ══════════════════════════════════════════════
#  Debug 辅助（F6 面板用）
# ══════════════════════════════════════════════

## 强制重刷某战区内容：撤走旧单位 + 按当前 mission_type 重 spawn
## 与 refresh_active_zones_for_level 的区别：无视 _triggered_zones（玩家正在打也强换）
## 前提：战区已处于 AVAILABLE / SELECTED（LOCKED 的先调 debug_force_unlock_zone）
func debug_force_respawn_zone(id: StringName) -> void:
	if not _zones:
		return
	var z := _zones.get_zone_by_id(id)
	if z.is_empty():
		return
	var state := _zones.get_state(id)
	if state != ZoneData.State.AVAILABLE and state != ZoneData.State.SELECTED:
		push_warning("debug_force_respawn_zone: zone %s is not AVAILABLE/SELECTED" % id)
		return

	# 撤走旧驻守 + 旧 TGT（视线内的延迟 free）
	_begin_air_support_egress(id, "debug respawn")
	_end_tier3_zone(id)
	_retire_zone_atmosphere(id)
	_retire_bomber_run(id)
	_despawn_garrison(id)
	var tgts: Array = _spawned_zones.get(id, [])
	for u in tgts:
		_retire_tier3_unit(u, false)
		_schedule_despawn(u)
	_spawned_zones.erase(id)
	_spawn_lead_timers.erase(id)
	_triggered_zones.erase(id)
	_completed_zones.erase(id)

	# 重刷
	_spawn_zone_units(id, z)
	EventLogger.log_event("ZONE", "DebugRespawn",
		"id=%s new_mt=%s" % [id, _zones.get_mission_type(id)])


func debug_set_tier3_profile(id: StringName, profile: StringName) -> void:
	if profile == &"super_cannon" or profile == &"siege_tank":
		_debug_tier3_profile_by_zone[id] = profile
	else:
		_debug_tier3_profile_by_zone.erase(id)


func debug_get_tier3_profile(id: StringName) -> StringName:
	return StringName(_debug_tier3_profile_by_zone.get(id, &"auto"))


## 通过真实伤害入口摧毁当前 3★来源，用于 F6 验证 NEUTRALIZED；不直接改状态或伪造结果。
func debug_neutralize_tier3_sources(id: StringName) -> int:
	var destroyed := 0
	for value in _spawned_zones.get(id, []):
		if typeof(value) != TYPE_OBJECT or value == null or not is_instance_valid(value) \
				or not (value is CombatUnit):
			continue
		var unit := value as CombatUnit
		if not bool(unit.get_meta(&"tier3_threat_source", false)) or unit.is_destroyed:
			continue
		if unit is NavalUnit:
			var ship := unit as NavalUnit
			ship.take_damage_at(maxf(ship.hull_hp, ship.hull_hp_max) + 9999.0,
				ship.global_position, 0.0, true)
		else:
			unit.take_damage(maxf(unit.hp, 1.0) + 9999.0, _player, "debug")
		destroyed += 1
	EventLogger.log_event("TIER3", "DebugNeutralize",
		"zone=%s sources=%d" % [id, destroyed])
	return destroyed

## 强制解锁某战区并立即刷内容（LOCKED / CLEARED → AVAILABLE + spawn）
func debug_force_unlock_zone(id: StringName) -> void:
	if not _zones:
		return
	var z := _zones.get_zone_by_id(id)
	if z.is_empty():
		return
	# 先清旧
	_begin_air_support_egress(id, "debug unlock")
	_end_tier3_zone(id)
	_retire_zone_atmosphere(id)
	_retire_bomber_run(id)
	_despawn_garrison(id)
	var tgts: Array = _spawned_zones.get(id, [])
	for u in tgts:
		_retire_tier3_unit(u, false)
		_schedule_despawn(u)
	_spawned_zones.erase(id)
	_spawn_lead_timers.erase(id)
	_triggered_zones.erase(id)
	_completed_zones.erase(id)

	# 置为 AVAILABLE + 重 roll 难度 / 奖励 / 任务类型（走 ZoneData 公开方法）
	_zones.debug_set_available(id)

	# 刷新内容
	_spawn_zone_units(id, z)
	EventLogger.log_event("ZONE", "DebugUnlock",
		"id=%s mt=%s" % [id, _zones.get_mission_type(id)])

## 2026-04-21：攻克一个战区后，对所有其他仍处于 AVAILABLE 状态的战区做一次"敌情升级"
## —— 把旧驻守机撤走 + 清 spawn 记录，下一帧 _ensure_spawned_for_active_zones 会按当前
## 玩家等级重刷一套新的敌人池（已触发 TGT 交战的战区跳过，避免打到一半敌人突然换型）。
##   except_id: 刚攻克的那个战区，不参与升级
## 返回被刷新的战区 id 列表（survivor_mode 可以据此发提示）
func refresh_active_zones_for_level(except_id: StringName) -> Array[StringName]:
	var refreshed: Array[StringName] = []
	if not _zones:
		return refreshed
	for z in ZoneData.ZONES:
		var zid: StringName = z["id"]
		if zid == except_id:
			continue
		var state := _zones.get_state(zid)
		if state != ZoneData.State.AVAILABLE and state != ZoneData.State.SELECTED:
			continue
		## 已进入交战的战区不改（否则玩家正在打的敌人会突然换型，体验差）
		if _triggered_zones.has(zid):
			continue
		## 没刷过就不用刷新（等 _ensure_spawned_for_active_zones 首次刷即可拿到当前等级）
		if not _spawned_zones.has(zid) and not _garrison_zones.has(zid):
			continue
		## 先撤走驻守 + TGT（视线内的入队延迟 free；不做飞出动画）
		_retire_zone_atmosphere(zid)
		_despawn_garrison(zid)
		var tgts: Array = _spawned_zones.get(zid, [])
		for u in tgts:
			_schedule_despawn(u)
		_spawned_zones.erase(zid)
		_spawn_lead_timers.erase(zid)
		refreshed.append(zid)
		EventLogger.log_event("ZONE", "RefreshedForLevel",
			"id=%s new_level=%d" % [zid, _player_level()])
	return refreshed

## 给一批单位打上"是任务目标"的标记，UI 上会显示 TGT 括号
func _mark_as_target(units: Array) -> void:
	for u in units:
		if u is CombatUnit:
			u.is_mission_target = true
			u.queue_redraw()

## 在战区内找一个满足 3 条规则的位置：
##   1. 安全部署判定（全图 OSM 陆地 - 港池水面，周围 50px 仍连续为陆地）
##   2. 距已放置的同战区单位 ≥ MIN_UNIT_SEPARATION_PX
##   3. 距任何道路 ≥ MIN_ROAD_DISTANCE_PX
## 失败时降级：放弃道路距离，再放弃间距。但**绝不放弃陆地判定** —— 宁可少刷几架
## 也不能让 SAM/AA 漂在水面上。全部失败返回 Vector2.INF，调用方跳过该单位。
##
## 采样源：polys 非空 → 按面积加权挑一块多边形再 reject-sample；否则在 (center, scatter) 圆内采样。
func _find_valid_spawn_pos(center: Vector2, scatter: float, placed: Array[Vector2], polys: Array = []) -> Vector2:
	var use_polys := not polys.is_empty()
	# Pass 1: 严格陆地 + 间距 + 距路
	for i in range(MAX_SAMPLE_ATTEMPTS):
		var p := _random_pos_in_polygons(polys) if use_polys else _random_pos_in_circle(center, scatter)
		if p == Vector2.INF:
			continue
		if MapGeography.is_ground_spawn_safe(p) \
				and _far_from_placed(p, placed) \
				and _far_from_roads(p):
			return p
	# Pass 2: 放弃道路距离
	for i in range(MAX_SAMPLE_ATTEMPTS):
		var p := _random_pos_in_polygons(polys) if use_polys else _random_pos_in_circle(center, scatter)
		if p == Vector2.INF:
			continue
		if MapGeography.is_ground_spawn_safe(p) and _far_from_placed(p, placed):
			return p
	# Pass 3: 放弃间距限制（挤在一起好过刷到海里）
	for i in range(MAX_SAMPLE_ATTEMPTS):
		var p := _random_pos_in_polygons(polys) if use_polys else _random_pos_in_circle(center, scatter)
		if p == Vector2.INF:
			continue
		if MapGeography.is_ground_spawn_safe(p):
			return p
	# 全部失败：返回 INF 哨兵值，让调用方跳过这颗单位
	return Vector2.INF

func _far_from_placed(p: Vector2, placed: Array[Vector2]) -> bool:
	for other in placed:
		if p.distance_to(other) < MIN_UNIT_SEPARATION_PX:
			return false
	return true

func _far_from_roads(p: Vector2) -> bool:
	# 高速公路
	for hw_any in MapGeography.HIGHWAYS:
		var hw: Dictionary = hw_any
		var pts: PackedVector2Array = hw.get("pts", PackedVector2Array())
		for i in range(pts.size() - 1):
			if _point_segment_distance(p, pts[i], pts[i + 1]) < MIN_ROAD_DISTANCE_PX:
				return false
	# 跨湾通道（尽管多半在海上）
	var aq: PackedVector2Array = MapGeography.AQUALINE_PATH
	for i in range(aq.size() - 1):
		if _point_segment_distance(p, aq[i], aq[i + 1]) < MIN_ROAD_DISTANCE_PX:
			return false
	return true

## 点到线段最短距离
func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _spawn_ground(scene: PackedScene, params: Resource, pos: Vector2, zone_id: StringName) -> Node:
	if scene == null or not MapGeography.is_ground_spawn_safe(pos):
		return null
	var u: Node = scene.instantiate()
	u.position = pos
	if params and "params" in u:
		u.params = params
	if "team" in u:
		u.team = 1
	if "bullet_manager" in u:
		u.bullet_manager = _bullet_manager
	if "missile_manager" in u:
		u.missile_manager = _missile_manager
	u.set_meta("zone_mission", zone_id)
	mode.add_child(u)
	return u

func _random_pos_in_circle(center: Vector2, radius: float) -> Vector2:
	var a := randf() * TAU
	var r := sqrt(randf()) * radius
	return center + Vector2(cos(a), sin(a)) * r

## BOSS 阶段闸门（真源 = survivor_mode.is_boss_phase()：boss_unlocked ∪ selected==BOSS ∪ 已 spawn）。
## 缺方法的旧调用方（测试挂具）回落到 ZoneData 的旧语义。
func _is_boss_phase() -> bool:
	if mode and mode.has_method("is_boss_phase"):
		return bool(mode.is_boss_phase())
	return _zones != null and _zones.is_boss_phase()

## 加入待撤离队列：offscreen 立即 free，onscreen 入队等它飘出屏外
## 【铁则】敌人不允许在玩家画面内凭空消失
func _schedule_despawn(u) -> void:
	if not is_instance_valid(u):
		return
	if "is_destroyed" in u and u.is_destroyed:
		return
	if mode and mode.has_method("is_world_pos_visible") \
			and not mode.is_world_pos_visible(u.global_position, 0.0):
		u.queue_free()
		return
	if not _pending_despawn.has(u):
		_pending_despawn.append(u)

func _retire_bomber_run(zone_id: StringName) -> void:
	if not _bomber_escort_runs.has(zone_id):
		return
	var run: Dictionary = _bomber_escort_runs[zone_id]
	var controller := run.get("controller") as BomberMission
	if controller != null and is_instance_valid(controller):
		controller.retire()
		for escort in controller.get_escort_fighters():
			_schedule_despawn(escort)
	for raw in run.get("interceptors", []):
		if typeof(raw) != TYPE_OBJECT or raw == null or not is_instance_valid(raw) \
				or not (raw is Aircraft) or (raw as Aircraft).is_destroyed:
			continue
		var interceptor := raw as Aircraft
		var ai := _get_ai_of(interceptor)
		if ai != null:
			ai.enable_combat = false
			ai.set_event_directive(AIDirective.fly_to(_support_exit_point(
				interceptor.global_position), AIDirective.OnArrival.HOLD, 300.0))
		interceptor.set_meta("bomber_intercept_target", null)
		_schedule_despawn(interceptor)
	_bomber_escort_runs.erase(zone_id)

## 每帧扫描 _pending_despawn：飘出视线的立即 free。
## 单位沿自身 AI 航线继续飞（不强制撤离朝向）；玩家视线跟随谁，队列就等谁。
func _flush_pending_despawn() -> void:
	if not mode or not mode.has_method("is_world_pos_visible"):
		return
	var kept: Array = []
	for u in _pending_despawn:
		if not is_instance_valid(u):
			continue
		if "is_destroyed" in u and u.is_destroyed:
			continue
		if mode.is_world_pos_visible(u.global_position, 0.0):
			kept.append(u)
		else:
			u.queue_free()
	_pending_despawn = kept

## 多边形面积（shoelace，绝对值）。接受 Array[Vector2] 或 PackedVector2Array
func _polygon_area(poly) -> float:
	var n: int = poly.size()
	if n < 3:
		return 0.0
	var s := 0.0
	for i in range(n):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5

## 把 Array[Vector2] / PackedVector2Array 统一转成 PackedVector2Array（is_point_in_polygon 要求）
func _to_packed(poly) -> PackedVector2Array:
	if poly is PackedVector2Array:
		return poly
	var pv := PackedVector2Array()
	pv.resize(poly.size())
	for i in range(poly.size()):
		pv[i] = poly[i]
	return pv

## 在多边形列表里随机挑一块（面积加权）→ 在该多边形 bbox 内 reject-sample。
## 全失败时返回 Vector2.INF（调用方会算成跳过此次采样）
func _random_pos_in_polygons(polys: Array) -> Vector2:
	if polys.is_empty():
		return Vector2.INF
	# 面积加权挑选
	var weights: Array[float] = []
	var total := 0.0
	for p_any in polys:
		var w := _polygon_area(p_any)
		weights.append(w)
		total += w
	if total <= 0.0:
		return Vector2.INF
	var r := randf() * total
	var pick_idx := polys.size() - 1
	var acc := 0.0
	for i in range(weights.size()):
		acc += weights[i]
		if r <= acc:
			pick_idx = i
			break
	var poly_raw = polys[pick_idx]
	if poly_raw.size() < 3:
		return Vector2.INF
	var poly: PackedVector2Array = _to_packed(poly_raw)
	# bbox
	var bb_min: Vector2 = poly[0]
	var bb_max: Vector2 = poly[0]
	for v in poly:
		bb_min.x = minf(bb_min.x, v.x)
		bb_min.y = minf(bb_min.y, v.y)
		bb_max.x = maxf(bb_max.x, v.x)
		bb_max.y = maxf(bb_max.y, v.y)
	# 多边形内 reject-sample（小多边形成功率很高，20 次足够）
	for i in range(20):
		var p := Vector2(
			bb_min.x + randf() * (bb_max.x - bb_min.x),
			bb_min.y + randf() * (bb_max.y - bb_min.y)
		)
		if Geometry2D.is_point_in_polygon(p, poly):
			return p
	# 兜底：返回多边形质心（一定在凸多边形内，凹形可能不在但概率极小）
	var c := Vector2.ZERO
	for v in poly:
		c += v
	return c / float(poly.size())

# ══════════════════════════════════════════════
#  完成判定
# ══════════════════════════════════════════════

## 统一的触发判定入口（模块化接口）。
## 双通道：进入战区圆 / TGT 已被攻击（hp 下降或已毁）。
## 未来要加新触发类型（如"接近到 X 距离"）就在这里扩展。
func _should_trigger(zone_id: StringName, zone: Dictionary) -> bool:
	# 护送任务的编队生成点在边界外，不能要求玩家先飞进一个不可达的移动圆。
	# 战术地图选择就是明确的出发命令，选择当帧开始倒计时并让任务包从场外入场。
	if _zones.get_mission_type(zone_id) == "bomber_escort" \
			and _zones.get_state(zone_id) == ZoneData.State.SELECTED:
		return true
	var d: float = _player.global_position.distance_to(_zones.get_zone_center(zone_id))
	if d <= float(zone["radius"]):
		return true
	if _any_tgt_engaged(zone_id):
		return true
	return false

## 战区任意一个 TGT 单位：已 free / is_destroyed / hp < max_hp 均视为已被攻击
func _any_tgt_engaged(zone_id: StringName) -> bool:
	var units: Array = _spawned_zones.get(zone_id, [])
	for u in units:
		if not is_instance_valid(u):
			return true
		if "is_destroyed" in u and u.is_destroyed:
			return true
		if "hp" in u and "params" in u and u.params and "max_hp" in u.params:
			if float(u.hp) < float(u.params.max_hp):
				return true
	return false

func _all_zone_units_destroyed(zone_id: StringName) -> bool:
	var units: Array = _spawned_zones.get(zone_id, [])
	if units.is_empty():
		return false
	for u in units:
		if not is_instance_valid(u):
			continue  # 节点已 free 视为毁灭
		if "is_destroyed" in u and not u.is_destroyed:
			return false
		if not ("is_destroyed" in u):
			return false
	return true

## 某战区的进度（已毁 / 总数），未刷则返回 (0,0)
func get_progress_for(zone_id: StringName) -> Vector2i:
	var units: Array = _spawned_zones.get(zone_id, [])
	if units.is_empty():
		return Vector2i.ZERO
	var total := units.size()
	var killed := 0
	for u in units:
		if not is_instance_valid(u):
			killed += 1
			continue
		if "is_destroyed" in u and u.is_destroyed:
			killed += 1
	return Vector2i(killed, total)
