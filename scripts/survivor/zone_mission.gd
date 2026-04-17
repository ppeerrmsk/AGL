class_name ZoneMission
extends Node

## 战区任务执行器
##
## 职责拆分：
##   1. **静态刷怪**：所有当前 AVAILABLE 的战区在开局（或刚解锁时）就把
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

const SAM_COUNT := 3
const AA_COUNT := 3
const SCATTER_RADIUS_SCALE := 0.85      ## 散布半径 = zone.radius × 此值
const MIN_UNIT_SEPARATION_PX := 650.0   ## 地面单位最小间距（≈1.3km）
const MIN_ROAD_DISTANCE_PX := 180.0     ## 距道路/高速的最小距离（≈360m）
const MAX_SAMPLE_ATTEMPTS := 80         ## 每个单位最多尝试 N 次随机位置

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

## zone_id → Array[Node]（任务目标：SAM/AA 或 空战中队，攻克判定依据）
var _spawned_zones: Dictionary = {}
## zone_id → Array[Aircraft]（驻守敌机：空中守卫，不是任务目标，攻克后撤离）
var _garrison_zones: Dictionary = {}
## 玩家是否至少进入过该战区一次（无论是否通过 Tab 选中）
var _triggered_zones: Dictionary = {}
## 已发完成信号的战区（防止重复）
var _completed_zones: Dictionary = {}

func setup(p_mode: Node, zones: ZoneData, player: Aircraft,
		sam_scene: PackedScene, sam_params: Resource,
		aa_scene: PackedScene, aa_params: Resource,
		bullet_mgr: Node2D, missile_mgr: Node2D,
		spawner: SurvivorSpawner) -> void:
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

func _physics_process(_delta: float) -> void:
	if not _zones or not _player:
		return

	# 1. 为所有当前 AVAILABLE/SELECTED 的战区确保已刷怪
	_ensure_spawned_for_active_zones()

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
				mission_triggered.emit(zid)
		# 已触发 → 查完成
		if _triggered_zones.has(zid):
			if _all_zone_units_destroyed(zid):
				_completed_zones[zid] = true
				_despawn_garrison(zid)      ## 撤离驻守敌机
				mission_completed.emit(zid)

# ══════════════════════════════════════════════
#  静态刷怪
# ══════════════════════════════════════════════

## 对 AVAILABLE / SELECTED（即"玩家能看到在地图上的"）战区，
## 如果还没刷过地面单位，就刷一次。
func _ensure_spawned_for_active_zones() -> void:
	for z in ZoneData.ZONES:
		var zid: StringName = z["id"]
		var state := _zones.get_state(zid)
		# 只给"玩家可见的"战区（AVAILABLE/SELECTED）刷怪，不给 LOCKED/CLEARED 刷
		if state != ZoneData.State.AVAILABLE and state != ZoneData.State.SELECTED:
			continue
		# 以前这里有"AVAILABLE + 全灭 → 自动清数据重刷"的分支，
		# 但它会在玩家打完最后一个 TGT 的当帧先于完成判定跑一遍，
		# 把 _triggered_zones / _completed_zones 擦掉 → mission_completed 永远不 emit
		# → 奖励不发，紧接着又刷了一队让玩家以为"任务重复了"。
		# 现在改成：战区重开的残留清理由 reset_zone() 在 mark_cleared 之后主动调用，
		# 这里只负责"没刷过就刷一次"。
		if _spawned_zones.has(zid):
			continue
		# 铁则：战区**生成半径**与玩家视野有重叠时推迟刷新（下帧再试）
		# 只测中心点远远不够 —— 空中中队生成环离中心 720px、陆基单位散布到 radius×0.85，
		# 所以只要战区可能刷出的任何单位会落在屏幕里就往后推
		if mode and mode.has_method("is_world_pos_visible"):
			var spawn_reach: float = float(z["radius"]) * SCATTER_RADIUS_SCALE
			if mode.is_world_pos_visible(z["center"], spawn_reach):
				continue
		_spawn_zone_units(zid, z)

func _spawn_zone_units(zone_id: StringName, zone: Dictionary) -> void:
	# runtime mission_type（可能被 zone_data 动态滚过：ground / squadron / elite / air）
	var mission_type: String = _zones.get_mission_type(zone_id) if _zones else zone.get("mission_type", "ground")
	match mission_type:
		"air", "squadron":
			_spawn_air_squadron(zone_id, zone)
		"elite":
			_spawn_elite_target(zone_id, zone)
		_:
			_spawn_ground_garrison(zone_id, zone)
	# 所有战区：按难度刷驻守敌机（守卫者，非 TGT，攻克后撤离）
	_spawn_zone_defenders(zone_id, zone, mission_type)

## 陆地守备：SAM + AA 在陆地上散布
func _spawn_ground_garrison(zone_id: StringName, zone: Dictionary) -> void:
	var units: Array = []
	var placed_positions: Array[Vector2] = []
	var center: Vector2 = zone["center"]
	var scatter: float = float(zone["radius"]) * SCATTER_RADIUS_SCALE

	for i in range(SAM_COUNT):
		var pos := _find_valid_spawn_pos(center, scatter, placed_positions)
		var u := _spawn_ground(_sam_scene, _sam_params, pos, zone_id)
		if u:
			units.append(u)
			placed_positions.append(pos)
	for i in range(AA_COUNT):
		var pos := _find_valid_spawn_pos(center, scatter, placed_positions)
		var u := _spawn_ground(_aa_scene, _aa_params, pos, zone_id)
		if u:
			units.append(u)
			placed_positions.append(pos)
	_spawned_zones[zone_id] = units
	# TGT 标记在玩家进入战区（mission_triggered）时才打上，预刷阶段不标
	EventLogger.log_event("ZONE", "PreSpawnGround",
		"id=%s units=%d center=%s" % [zone_id, units.size(), center])

## 空战中队：在战区中心刷一队敌机，绕战区盘旋，不受 Token 限制
## 复用 SurvivorSpawner 的 _create_enemy → 然后挂锚定 waypoint + adds 标记
const AIR_SQUADRON_COUNT := 4
const AIR_SQUADRON_ORBIT_RADIUS := 1200.0
const AIR_SQUADRON_SPAWN_RING_RATIO := 0.6  ## 初始生成环 = 轨道半径 × 此值
const AIR_SQUADRON_PATROL_WAYPOINTS := 4    ## 绕中心的航点数

## 驻守敌机（garrison）：地面战区的空中守卫，不是任务目标，不标 TGT
## 难度 → [数量, 敌机池]
## 攻克战区后自动撤离（queue_free）
const GARRISON_ORBIT_RADIUS := 1800.0        ## 比 air_squadron 稍大，避免与 SAM 扎堆

func _spawn_air_squadron(zone_id: StringName, zone: Dictionary) -> void:
	if not _spawner:
		return
	var center: Vector2 = zone["center"]
	var units: Array = []
	# 一个战区一支中队 = 同一机型（MIG / F86 / MIG23 中随机选一种）
	# 混编不叫"中队"，任务文案说"击灭敌方中队"就得真的是同型编队
	var enemy_pool := [
		SurvivorSpawner.EnemyType.MIG,
		SurvivorSpawner.EnemyType.F86,
		SurvivorSpawner.EnemyType.MIG23,
	]
	var etype: int = enemy_pool[randi() % enemy_pool.size()]

	# 长机起始位置：战区生成环上随机一点，朝切线方向飞
	var leader_angle := randf() * TAU
	var leader_pos := center + Vector2(cos(leader_angle), sin(leader_angle)) * AIR_SQUADRON_ORBIT_RADIUS * AIR_SQUADRON_SPAWN_RING_RATIO
	var heading_deg := rad_to_deg(leader_angle + PI * 0.5)
	var heading_rad := deg_to_rad(heading_deg)

	# 预生成长机盘旋航点（绕战区中心），仅长机持有
	var leader_waypoints := PackedVector2Array()
	for k in range(AIR_SQUADRON_PATROL_WAYPOINTS):
		var wa := float(k) / float(AIR_SQUADRON_PATROL_WAYPOINTS) * TAU
		leader_waypoints.append(center + Vector2(cos(wa), sin(wa)) * AIR_SQUADRON_ORBIT_RADIUS)
	# 从当前 leader_angle 的下一个扇区开始，使长机往前飞而不是折返
	var start_idx := int(floor((leader_angle + PI * 0.5) / TAU * AIR_SQUADRON_PATROL_WAYPOINTS)) % AIR_SQUADRON_PATROL_WAYPOINTS

	var sq := Squad.new()
	for i in range(AIR_SQUADRON_COUNT):
		var spawn_pos: Vector2
		if i == 0:
			spawn_pos = leader_pos
		else:
			# 僚机按编队偏移从长机侧后方展开（真正的编队，不是独立绕圈）
			var offset := sq.get_formation_offset(i)
			spawn_pos = leader_pos + offset.rotated(heading_rad)

		var ac: Aircraft = _spawner._create_enemy(etype, spawn_pos, heading_deg)
		if not ac:
			continue
		# 跳过全局 hunter / far_cleanup / boundary_discipline
		ac.set_meta("zone_mission", zone_id)
		ac.set_meta("category", "zone_air")
		ac.set_meta("skip_far_cleanup", true)

		sq.add_member(ac)
		if i == 0:
			sq.leader = ac

		var ai := _get_ai_of(ac)
		if ai:
			ai.squad = sq
			ai.squad_index = i
			# 所有成员都持有同一套盘旋航点：SQUAD_FOLLOW 期间航点被忽略；
			# 长机阵亡后僚机回退 PATROL 时，能独立绕战区盘旋而不是直线平飞出圈
			# （zone 专用 Squad 不在 _spawner._squads 里，不会被自动晋升新长机；
			#  且 zone_air 被全局 waypoints/boundary/hunters 三个补救都 skip）
			ai.waypoints = leader_waypoints
			# 错开起点 index，避免几架飞机堆在同一个航点上
			ai.current_waypoint_index = (start_idx + i) % AIR_SQUADRON_PATROL_WAYPOINTS
		units.append(ac)

	_spawned_zones[zone_id] = units
	# TGT 标记在玩家进入战区（mission_triggered）时才打上，预刷阶段不标
	EventLogger.log_event("ZONE", "PreSpawnAir",
		"id=%s type=%d aircraft=%d center=%s" % [zone_id, etype, units.size(), center])

## 驻守敌机：Token 预算制
##   ★    8 Token
##   ★★   15 Token
##   ★★★  30 Token
## 从池子里按权重抽取（Sentinel 权重加倍），直到预算不够最便宜的单位为止
## elite 任务已用 Sentinel 作为 TGT → 本函数里 Sentinel 从池中排除
## 驻守机不标 TGT，走和 air_squadron 一样的锚定轨道（不追玩家出圈）
const DEFENDER_BUDGET_BY_DIFFICULTY := {1: 8, 2: 15, 3: 30}

## 战区守卫池：type / weight / cost 动态从 SurvivorData.TOKEN_COST 读
## 【硬规则】Sentinel 绝不出现在驻守池里。Sentinel 永远通过
## _spawn_commander_squad（固定 5 架 UAV）或 _spawn_elite_target（5-8 架 UAV/UCAV）
## 带队登场，不允许以单架驻守机形式出现 —— 驻守是随机混编，不符合"首领必带护卫"规则。
const DEFENDER_POOL := [
	{"type": SurvivorSpawner.EnemyType.F86,           "weight": 1.0},
	{"type": SurvivorSpawner.EnemyType.MIG23,         "weight": 1.0},
	{"type": SurvivorSpawner.EnemyType.MIG,           "weight": 1.0},
	{"type": SurvivorSpawner.EnemyType.A7,            "weight": 0.9},
	{"type": SurvivorSpawner.EnemyType.Q5,            "weight": 0.9},
	{"type": SurvivorSpawner.EnemyType.INTERCEPTOR,   "weight": 0.7},
	{"type": SurvivorSpawner.EnemyType.F100,          "weight": 0.7},
	{"type": SurvivorSpawner.EnemyType.SU27,          "weight": 0.5},
	{"type": SurvivorSpawner.EnemyType.MIG31,         "weight": 0.3},
]

func _spawn_zone_defenders(zone_id: StringName, zone: Dictionary, mission_type: String = "ground") -> void:
	if not _spawner or not _zones:
		return
	var difficulty: int = _zones.get_difficulty(zone_id)
	var budget: int = int(DEFENDER_BUDGET_BY_DIFFICULTY.get(difficulty, 8))
	# elite 任务：Sentinel 已作为 TGT 出现，不再从 defender 池里抽 Sentinel
	var exclude_sentinel: bool = (mission_type == "elite")
	var center: Vector2 = zone["center"]
	var units: Array[Aircraft] = []
	var slot_index := 0
	var guard := 30  ## 死循环保险
	while budget > 0 and guard > 0:
		guard -= 1
		var pick := _pick_defender(budget, exclude_sentinel)
		if pick.is_empty():
			break
		var etype: int = pick["type"]
		var cost: int = pick["cost"]
		var a := float(slot_index) / 6.0 * TAU + randf_range(-0.3, 0.3)
		var spawn_pos := center + Vector2(cos(a), sin(a)) * GARRISON_ORBIT_RADIUS * 0.7
		var heading_deg := rad_to_deg(a + PI * 0.5)
		var ac: Aircraft = _spawner._create_enemy(etype, spawn_pos, heading_deg)
		if not ac:
			budget -= cost  ## 防止实例 cap 击中时死循环
			continue
		ac.set_meta("zone_garrison", zone_id)
		ac.set_meta("category", "zone_air")
		ac.set_meta("skip_far_cleanup", true)
		var ai := _get_ai_of(ac)
		if ai:
			var wp := PackedVector2Array()
			var n_wp := 4
			for k in range(n_wp):
				var wa := float(k) / float(n_wp) * TAU
				wp.append(center + Vector2(cos(wa), sin(wa)) * GARRISON_ORBIT_RADIUS)
			ai.waypoints = wp
			ai.current_waypoint_index = 0
		units.append(ac)
		budget -= cost
		slot_index += 1
	_garrison_zones[zone_id] = units
	EventLogger.log_event("ZONE", "Garrison",
		"id=%s diff=%d mission=%s defenders=%d" % [zone_id, difficulty, mission_type, units.size()])

## 按权重从 DEFENDER_POOL 抽一个负担得起的敌人，返回 {type, cost}
func _pick_defender(budget: int, exclude_sentinel: bool) -> Dictionary:
	var candidates: Array = []
	var total_weight := 0.0
	for entry_any in DEFENDER_POOL:
		var entry: Dictionary = entry_any
		var etype: int = entry["type"]
		if exclude_sentinel and etype == SurvivorSpawner.EnemyType.UAV_COMMANDER:
			continue
		var cost: int = int(SurvivorData.TOKEN_COST.get(etype, 99))
		if cost > budget:
			continue
		candidates.append({"type": etype, "cost": cost, "weight": float(entry["weight"])})
		total_weight += float(entry["weight"])
	if candidates.is_empty() or total_weight <= 0.0:
		return {}
	var r := randf() * total_weight
	var acc := 0.0
	for c_any in candidates:
		var c: Dictionary = c_any
		acc += c["weight"]
		if r <= acc:
			return {"type": c["type"], "cost": c["cost"]}
	return {"type": candidates[-1]["type"], "cost": candidates[-1]["cost"]}

## 精英任务：Sentinel 作为首领怪 TGT（3 星独占）
## Sentinel 永远带 5-8 架 UAV/UCAV 僚机一起出现，绝不单独部署
## （Aura 会持续招募路过的 is_unmanned 飞机；但初始必须有固定护卫，防止单架裸奔）
const ELITE_SENTINEL_ESCORT_MIN := 5  ## 战区首领怪最少护卫数（UAV/UCAV）
const ELITE_SENTINEL_ESCORT_MAX := 8  ## 战区首领怪最多护卫数
func _spawn_elite_target(zone_id: StringName, zone: Dictionary) -> void:
	if not _spawner:
		return
	var center: Vector2 = zone["center"]
	var units: Array = []
	var ac: Aircraft = _spawner._create_enemy(SurvivorSpawner.EnemyType.UAV_COMMANDER, center, 0.0)
	if not ac:
		return
	ac.set_meta("zone_mission", zone_id)
	ac.set_meta("category", "zone_air")
	ac.set_meta("skip_far_cleanup", true)
	# 挂载光环 + 视觉覆盖（仿照 survivor_spawner._spawn_commander_squad）
	var aura := CommanderAura.new()
	aura.name = "CommanderAura"
	ac.add_child(aura)
	var overlay := CommanderOverlay.new()
	overlay.name = "CommanderOverlay"
	ac.add_child(overlay)
	# 绑定 Squad，让 aura._try_recruit 能运作 + 僚机能挂上来
	var sq := Squad.new()
	sq.add_member(ac)
	sq.leader = ac
	var leader_ai := _get_ai_of(ac)
	if leader_ai:
		leader_ai.squad = sq
		leader_ai.squad_index = 0
		var wp := PackedVector2Array()
		var n_wp := 4
		for k in range(n_wp):
			var wa := float(k) / float(n_wp) * TAU
			wp.append(center + Vector2(cos(wa), sin(wa)) * AIR_SQUADRON_ORBIT_RADIUS)
		leader_ai.waypoints = wp
		leader_ai.current_waypoint_index = 0
	units.append(ac)
	_spawned_zones[zone_id] = units  ## 只有 Sentinel 是任务目标（TGT）；护卫走驻守池

	# 固定护卫：5-8 架 UAV/UCAV 混编，绕 Sentinel 散开生成
	# 护卫不是任务目标，放入 _garrison_zones → 攻克战区后自动撤离
	var garrison: Array = _garrison_zones.get(zone_id, [])
	var escort_count := randi_range(ELITE_SENTINEL_ESCORT_MIN, ELITE_SENTINEL_ESCORT_MAX)
	for i in range(escort_count):
		var rand_angle := randf() * TAU
		var rand_dist := randf_range(220.0, 420.0)
		var spawn_pos := center + Vector2(cos(rand_angle), sin(rand_angle)) * rand_dist
		var etype: int = SurvivorSpawner.EnemyType.UAV if (i % 2 == 0) else SurvivorSpawner.EnemyType.UCAV
		var wingman: Aircraft = _spawner._create_enemy(etype, spawn_pos, rad_to_deg(rand_angle))
		if not wingman:
			continue
		wingman.set_meta("zone_mission", zone_id)
		wingman.set_meta("category", "zone_air")
		wingman.set_meta("skip_far_cleanup", true)
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
	EventLogger.log_event("ZONE", "PreSpawnElite",
		"id=%s center=%s escort=%d" % [zone_id, center, escort_count])

## 攻克战区后，让驻守机"撤离"（直接 queue_free；未来可改成飞向边界）
func _despawn_garrison(zone_id: StringName) -> void:
	var units: Array = _garrison_zones.get(zone_id, [])
	for u in units:
		if is_instance_valid(u) and not u.is_destroyed:
			u.queue_free()
	_garrison_zones.erase(zone_id)

func _get_ai_of(ac: Aircraft) -> AIController:
	for child in ac.get_children():
		if child is AIController:
			return child
	return null

## 战区被 mark_cleared 之后调用（由 survivor_mode 在 _on_zone_mission_completed 里转发）：
## 清掉该战区的 spawn/trigger/completion 记录，让下一次该战区重新 AVAILABLE
## 时能干净地重刷一批单位。
func reset_zone(zone_id: StringName) -> void:
	_spawned_zones.erase(zone_id)
	_garrison_zones.erase(zone_id)
	_triggered_zones.erase(zone_id)
	_completed_zones.erase(zone_id)

## 给一批单位打上"是任务目标"的标记，UI 上会显示 TGT 括号
func _mark_as_target(units: Array) -> void:
	for u in units:
		if u is CombatUnit:
			u.is_mission_target = true

## 在战区圆内找一个满足 3 条规则的位置：
##   1. 在陆地多边形内
##   2. 距已放置的同战区单位 ≥ MIN_UNIT_SEPARATION_PX
##   3. 距任何道路 ≥ MIN_ROAD_DISTANCE_PX
## 失败时降级放宽：先放弃道路距离，再放弃陆地限制，最后回退到圆内任意点
func _find_valid_spawn_pos(center: Vector2, scatter: float, placed: Array[Vector2]) -> Vector2:
	# Pass 1: 全部规则
	for i in range(MAX_SAMPLE_ATTEMPTS):
		var p := _random_pos_in_circle(center, scatter)
		if MapGeography.is_on_land(p) \
				and _far_from_placed(p, placed) \
				and _far_from_roads(p):
			return p
	# Pass 2: 放弃道路距离
	for i in range(MAX_SAMPLE_ATTEMPTS):
		var p := _random_pos_in_circle(center, scatter)
		if MapGeography.is_on_land(p) and _far_from_placed(p, placed):
			return p
	# Pass 3: 放弃陆地限制（少数边界情况，如战区完全在海上）
	for i in range(MAX_SAMPLE_ATTEMPTS):
		var p := _random_pos_in_circle(center, scatter)
		if _far_from_placed(p, placed):
			return p
	# 最终 fallback：圆内任意点
	return _random_pos_in_circle(center, scatter)

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
	if scene == null:
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

# ══════════════════════════════════════════════
#  完成判定
# ══════════════════════════════════════════════

## 统一的触发判定入口（模块化接口）。
## 双通道：进入战区圆 / TGT 已被攻击（hp 下降或已毁）。
## 未来要加新触发类型（如"接近到 X 距离"）就在这里扩展。
func _should_trigger(zone_id: StringName, zone: Dictionary) -> bool:
	var d: float = _player.global_position.distance_to(zone["center"])
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
