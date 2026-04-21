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
const BOSS_DESPAWN_INTERVAL := 1.0     ## BOSS 阶段视线外清理节拍（秒）

var _boss_despawn_timer: float = 0.0
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

func _physics_process(delta: float) -> void:
	if not _zones or not _player:
		return

	# BOSS 阶段：常规战区 A/B/C/D 任务全部停止（不再刷怪、不再触发、不再判定完成）
	# 已经刷出来的 TGT/驻守敌机在玩家视线外悄悄 free（不做飞出动画）
	# 节流到 1Hz —— 单位都飞着，玩家几秒后才注意到根本看不出来
	# BOSS 由 ace_squad/F-47 系统单独管理，不走本类
	if _zones.is_boss_phase():
		_boss_despawn_timer -= delta
		if _boss_despawn_timer <= 0.0:
			_boss_despawn_timer = BOSS_DESPAWN_INTERVAL
			_despawn_zone_units_offscreen()
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
	# 最后一道防线：若 mission_type 是 ground 但战区几乎没有陆地（可能是旧存档、
	# 基础定义改成"海上"战区、或采样抖动），改为空战中队，避免 SAM/AA 刷到海面
	if mission_type == "ground" and _zones and not ZoneData.zone_has_land(zone_id):
		mission_type = "squadron"
		_zones.set_mission_type(zone_id, "squadron")
		EventLogger.log_event("ZONE", "OverrideGroundToAir",
			"id=%s reason=water_zone" % [zone_id])
	match mission_type:
		"air", "squadron":
			_spawn_air_squadron(zone_id, zone)
		"elite":
			_spawn_elite_target(zone_id, zone)
		_:
			_spawn_ground_garrison(zone_id, zone)
	# 所有战区：按难度刷驻守敌机（守卫者，非 TGT，攻克后撤离）
	_spawn_zone_defenders(zone_id, zone, mission_type)

## 陆地守备：SAM + AA 按星级/等级缩放
func _spawn_ground_garrison(zone_id: StringName, zone: Dictionary) -> void:
	var units: Array = []
	var placed_positions: Array[Vector2] = []
	var center: Vector2 = zone["center"]
	var scatter: float = float(zone["radius"]) * SCATTER_RADIUS_SCALE
	## 若战区配了 ground_spawn_polygons，SAM/AA 改在多边形内随机刷（仍走严格陆地判定）
	var spawn_polys: Array = zone.get("ground_spawn_polygons", [])
	var use_polys: bool = not spawn_polys.is_empty()

	## 2026-04-21：TGT 强度随星级 + 玩家等级缩放
	##   数量：★2+2 / ★★3+3 / ★★★5+5
	##   HP：  每级 +10%，每星 +20%（上限 ×3）
	var lvl: int = _player_level()
	var difficulty: int = _zones.get_difficulty(zone_id) if _zones else 1
	var scale: Dictionary = SurvivorData.ground_tgt_scale(difficulty, lvl)
	var sam_count: int = int(scale["sam_count"])
	var aa_count: int = int(scale["aa_count"])
	var hp_mult: float = float(scale["hp_mult"])

	## 深拷贝 params 并按 hp_mult 放大 max_hp（避免共享修改污染其他战区）
	var sam_params_scaled: Resource = _sam_params.duplicate(true) if _sam_params else null
	if sam_params_scaled and "max_hp" in sam_params_scaled:
		sam_params_scaled.max_hp *= hp_mult
	var aa_params_scaled: Resource = _aa_params.duplicate(true) if _aa_params else null
	if aa_params_scaled and "max_hp" in aa_params_scaled:
		aa_params_scaled.max_hp *= hp_mult

	for i in range(sam_count):
		var pos := _find_valid_spawn_pos(center, scatter, placed_positions, spawn_polys if use_polys else [])
		if pos == Vector2.INF:
			continue  ## 采样失败：战区这一侧全是海，跳过这颗单位
		var u := _spawn_ground(_sam_scene, sam_params_scaled, pos, zone_id)
		if u:
			units.append(u)
			placed_positions.append(pos)
	for i in range(aa_count):
		var pos := _find_valid_spawn_pos(center, scatter, placed_positions, spawn_polys if use_polys else [])
		if pos == Vector2.INF:
			continue
		var u := _spawn_ground(_aa_scene, aa_params_scaled, pos, zone_id)
		if u:
			units.append(u)
			placed_positions.append(pos)
	_spawned_zones[zone_id] = units
	# TGT 标记在玩家进入战区（mission_triggered）时才打上，预刷阶段不标
	EventLogger.log_event("ZONE", "PreSpawnGround",
		"id=%s lvl=%d diff=%d units=%d hp_x%.2f center=%s"
		% [zone_id, lvl, difficulty, units.size(), hp_mult, center])

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
	## 中队规模也按星级放大：★3 / ★★4 / ★★★5
	var squadron_count: int = SurvivorData.air_squadron_count_for_difficulty(difficulty)

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
	for i in range(squadron_count):
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
		"id=%s type=%d aircraft=%d lvl=%d tgt_lvl=%d diff=%d center=%s"
		% [zone_id, etype, units.size(), lvl, tgt_lvl, difficulty, center])

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
## 【硬规则】Sentinel 绝不出现在驻守池里，永远通过 _spawn_commander_squad /
## _spawn_elite_target 带队登场，不允许以单架驻守机形式出现。
##
## 【原则】Token 不必占满，优先让玩家能应对当前等级（超纲敌人由等级钟形权重过滤）。

## 按 cost 决定"中队"规模（包括长机）
static func _squad_size_for_cost(cost: int) -> int:
	if cost <= 2:
		return 4  ## UAV/UCAV：4 架杂鱼群
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
	## 驻守虚拟等级：★★/★★★ 提升护卫池子等级，避免低级玩家满屏 UAV/UCAV
	var g_vlvl: int = SurvivorData.zone_virtual_level(difficulty, lvl, "garrison")
	var budget: int = SurvivorData.zone_defender_budget(difficulty, lvl)  ## 预算仍按真实等级（让强敌自然减量）
	var exclude_sentinel: bool = true  ## 驻守池硬规则：Sentinel 永不单刷
	## elite 任务本身已出 Sentinel，驻守预算减半（避免护卫 + 驻守双倍叠加）
	if mission_type == "elite":
		budget = int(budget * 0.5)

	var center: Vector2 = zone["center"]
	var units: Array[Aircraft] = []
	var squad_index := 0
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

		var slot_angle: float = float(squad_index) / 6.0 * TAU + randf_range(-0.3, 0.3)
		var leader_pos: Vector2 = center + Vector2(cos(slot_angle), sin(slot_angle)) * GARRISON_ORBIT_RADIUS * 0.7
		var heading_rad: float = slot_angle + PI * 0.5
		var heading_deg: float = rad_to_deg(heading_rad)

		## 预生成盘旋航点（绕战区中心）—— 全队共用
		var wp := PackedVector2Array()
		var n_wp := 4
		for k in range(n_wp):
			var wa := float(k) / float(n_wp) * TAU
			wp.append(center + Vector2(cos(wa), sin(wa)) * GARRISON_ORBIT_RADIUS)
		var start_wp_idx: int = int(floor((slot_angle + PI * 0.5) / TAU * n_wp)) % n_wp

		var sq := Squad.new()
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
			ac.set_meta("zone_garrison", zone_id)
			ac.set_meta("category", "zone_air")
			ac.set_meta("skip_far_cleanup", true)
			sq.add_member(ac)
			if i == 0:
				sq.leader = ac
			var ai := _get_ai_of(ac)
			if ai:
				ai.squad = sq
				ai.squad_index = i
				## 长机走航点盘旋；僚机由 SQUAD_FOLLOW 跟随；长机阵亡后僚机自然转 PATROL
				ai.waypoints = wp
				ai.current_waypoint_index = (start_wp_idx + i) % n_wp
			units.append(ac)
			budget -= cost
			spawned_in_squad += 1
		squad_index += 1
		## 如果这一队一架都没刷出来（通常是 cap 击中且 room=0），guard 会逐步耗尽
		if spawned_in_squad == 0:
			continue

	_garrison_zones[zone_id] = units
	EventLogger.log_event("ZONE", "Garrison",
		"id=%s diff=%d lvl=%d mission=%s defenders=%d budget_left=%d"
		% [zone_id, difficulty, lvl, mission_type, units.size(), budget])

## 场景中某类型当前活着的敌机数（给 instance cap 检查用）
func _count_type_in_scene(etype: int) -> int:
	var count := 0
	for child in mode.get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			if int(child.get_meta("enemy_type_idx", -1)) == etype:
				count += 1
	return count

## 当前玩家等级；spawner.survivor_player 不可用时回退 1
func _player_level() -> int:
	if _spawner and _spawner.survivor_player:
		return int(_spawner.survivor_player.level)
	return 1

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

	# Sentinel 自带 UAV 小队（光环 buff 的作用对象，硬性 ≥ 5 架，纯 UAV）
	# 设计约束：Sentinel 作为 UAV 群的指挥机，出场必带自己的小队 —— 跟它随机
	#   刷怪路径 `SurvivorSpawner._spawn_commander_squad` 保持完全一致（纯 UAV）。
	#   战区的通用混编护卫由 `_spawn_zone_defenders` 另外独立刷出，与此无关。
	var garrison: Array = _garrison_zones.get(zone_id, [])
	var escort_count := randi_range(ELITE_SENTINEL_ESCORT_MIN, ELITE_SENTINEL_ESCORT_MAX)
	var lvl_e: int = _player_level()
	var diff_e: int = _zones.get_difficulty(zone_id) if _zones else 3
	for i in range(escort_count):
		var rand_angle := randf() * TAU
		var rand_dist := randf_range(220.0, 420.0)
		var spawn_pos := center + Vector2(cos(rand_angle), sin(rand_angle)) * rand_dist
		var wingman: Aircraft = _spawner._create_enemy(SurvivorSpawner.EnemyType.UAV, spawn_pos, rad_to_deg(rand_angle))
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
		"id=%s center=%s sentinel_uav_squad=%d lvl=%d diff=%d (garrison spawned separately)"
		% [zone_id, center, escort_count, lvl_e, diff_e])

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

## 玩家是否正在至少一个活跃战区任务中（触发过但未完成）。
## 用于旅途刷怪系统判断"玩家当前是否有战区任务在身"。
func is_player_in_active_mission() -> bool:
	for zid in _triggered_zones:
		if not _completed_zones.has(zid):
			return true
	return false

## 战区被 mark_cleared 之后调用（由 survivor_mode 在 _on_zone_mission_completed 里转发）：
## 清掉该战区的 spawn/trigger/completion 记录，让下一次该战区重新 AVAILABLE
## 时能干净地重刷一批单位。
func reset_zone(zone_id: StringName) -> void:
	_spawned_zones.erase(zone_id)
	_garrison_zones.erase(zone_id)
	_triggered_zones.erase(zone_id)
	_completed_zones.erase(zone_id)

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
		## 先撤走驻守 + TGT（静默 queue_free；没有任务残留）
		_despawn_garrison(zid)
		var tgts: Array = _spawned_zones.get(zid, [])
		for u in tgts:
			if is_instance_valid(u) and "is_destroyed" in u and not u.is_destroyed:
				u.queue_free()
		_spawned_zones.erase(zid)
		refreshed.append(zid)
		EventLogger.log_event("ZONE", "RefreshedForLevel",
			"id=%s new_level=%d" % [zid, _player_level()])
	return refreshed

## 给一批单位打上"是任务目标"的标记，UI 上会显示 TGT 括号
func _mark_as_target(units: Array) -> void:
	for u in units:
		if u is CombatUnit:
			u.is_mission_target = true

## 在战区内找一个满足 3 条规则的位置：
##   1. 严格陆地判定（只认 OSM LAND_MASK，避免港池/海湾被误判为陆地）
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
		if MapGeography.is_on_land_strict(p) \
				and _far_from_placed(p, placed) \
				and _far_from_roads(p):
			return p
	# Pass 2: 放弃道路距离
	for i in range(MAX_SAMPLE_ATTEMPTS):
		var p := _random_pos_in_polygons(polys) if use_polys else _random_pos_in_circle(center, scatter)
		if p == Vector2.INF:
			continue
		if MapGeography.is_on_land_strict(p) and _far_from_placed(p, placed):
			return p
	# Pass 3: 放弃间距限制（挤在一起好过刷到海里）
	for i in range(MAX_SAMPLE_ATTEMPTS):
		var p := _random_pos_in_polygons(polys) if use_polys else _random_pos_in_circle(center, scatter)
		if p == Vector2.INF:
			continue
		if MapGeography.is_on_land_strict(p):
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

## BOSS 阶段下：把战区已刷的 TGT (_spawned_zones) + 驻守敌机 (_garrison_zones)
## 在玩家视线外 queue_free。视线内的暂时不动，等飞出去再撤。
## 系统资源让给 BOSS（F-47 王牌中队），不做飞出动画。
func _despawn_zone_units_offscreen() -> void:
	if not mode or not mode.has_method("is_world_pos_visible"):
		return
	for tracker in [_spawned_zones, _garrison_zones]:
		for zid in tracker.keys():
			var arr: Array = tracker[zid]
			var kept: Array = []
			for u in arr:
				if not is_instance_valid(u):
					continue
				if "is_destroyed" in u and u.is_destroyed:
					continue
				if mode.is_world_pos_visible(u.global_position, 0.0):
					kept.append(u)
				else:
					u.queue_free()
			tracker[zid] = kept

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
