extends RefCounted
##
## ZoneSpawnJob — 战区首刷的分帧续段（ZoneMission 专用）
##
## 地面目标（任务主分支）仍在触发帧同步生成，保证首个镜头帧已有任务目标；
## 其后的驻守敌机、3★ 内容与战区气氛层按【原顺序】转入本任务，由 ZoneMission 每帧在
## 时间预算与单位数上限内推进（run_piece 一次只做一架驻守机或一个阶段）。
## 驻守敌机从地图边缘入场，分帧不改变画面；全局随机数仍按原代码的先后顺序抽取，
## 驻守预算、中队规模、阵型偏移、航点与 AI 配置与一次性生成完全同一套逻辑。

enum Phase { DEFENDERS, TIER3, ATMOSPHERE, DONE }
enum DefenderStage { SETUP, SELECT, MEMBER, COMMIT }

var mission: ZoneMission
var zone_id: StringName
var zone: Dictionary
var mission_type: String
var phase: int = Phase.DEFENDERS
var finished := false
## 只跑驻守阶段（ZoneMission._spawn_zone_defenders 的同步实现复用本状态机）
var defenders_only := false

var _d_stage: int = DefenderStage.SETUP
## 原函数在缺 spawner / zones 时直接返回：不落账、不记日志
var _d_skip_commit := false
var _d_units: Array[Aircraft] = []
var _d_budget := 0
var _d_guard := 0
var _d_g_vlvl := 0
var _d_lvl := 0
var _d_difficulty := 0
var _d_exclude_sentinel := true
var _d_center := Vector2.ZERO
var _d_garrison_r := 0.0
var _d_etype := 0
var _d_cost := 0
var _d_squad_size := 0
var _d_member := 0
var _d_leader_pos := Vector2.ZERO
var _d_heading_deg := 0.0
var _d_heading_rad := 0.0
var _d_wp := PackedVector2Array()
var _d_start_wp_idx := 0
var _d_squad: Squad


func _init(p_mission: ZoneMission, p_zone_id: StringName, p_zone: Dictionary,
		p_mission_type: String, p_defenders_only: bool = false) -> void:
	mission = p_mission
	zone_id = p_zone_id
	zone = p_zone
	mission_type = p_mission_type
	defenders_only = p_defenders_only
	# naval 任务不加空中驻守（与原 _spawn_zone_units 一致）。
	if mission_type == "naval" and not defenders_only:
		phase = Phase.TIER3


## 同步跑完（Debug / 专项入口）。
func run_all() -> void:
	while not finished:
		run_piece()


## 执行一个最小片段；返回本片段新生成的实体数（供每帧单位上限计数）。
func run_piece() -> int:
	match phase:
		Phase.DEFENDERS:
			var spawned := _step_defenders()
			if _d_stage == DefenderStage.COMMIT:
				if not _d_skip_commit:
					_commit_defenders()
				if defenders_only:
					_finish()
				else:
					phase = Phase.TIER3
			return spawned
		Phase.TIER3:
			phase = Phase.ATMOSPHERE
			if mission._zones != null \
					and mission._zones.get_difficulty(zone_id) == ZoneData.DIFFICULTY_MAX:
				mission._spawn_tier3_profile(zone_id, mission_type, zone)
				return 1
			return 0
		Phase.ATMOSPHERE:
			mission._atmosphere_register_deferred = true
			mission._register_zone_atmosphere(zone_id, mission_type, zone)
			mission._atmosphere_register_deferred = false
			_finish()
			return 0
	_finish()
	return 0


## 撤销/失败/重置时把已生成的驻守机按原语义落账（等同原函数在此处结束），交由既有清理流程处理。
func commit_partial() -> void:
	if phase == Phase.DEFENDERS and _d_stage != DefenderStage.SETUP \
			and _d_stage != DefenderStage.COMMIT and not _d_skip_commit:
		_commit_defenders()
	_finish()


func _finish() -> void:
	phase = Phase.DONE
	finished = true


func _commit_defenders() -> void:
	mission._garrison_zones[zone_id] = _d_units
	EventLogger.log_event("ZONE", "Garrison",
		"id=%s diff=%d lvl=%d mission=%s defenders=%d edge_ingress=%d budget_left=%d"
		% [zone_id, _d_difficulty, _d_lvl, mission_type, _d_units.size(), _d_units.size(), _d_budget])
	_d_stage = DefenderStage.COMMIT


## 与原 ZoneMission._spawn_zone_defenders 逐句对应，只是把"每架驻守机"拆成一个片段。
func _step_defenders() -> int:
	match _d_stage:
		DefenderStage.SETUP:
			if not mission._spawner or not mission._zones:
				_d_skip_commit = true
				_d_stage = DefenderStage.COMMIT
				return 0
			_d_difficulty = mission._zones.get_difficulty(zone_id)
			_d_lvl = mission._player_level()
			## 驻守虚拟等级：★★/★★★ 提升护卫池子等级，避免低级玩家满屏 MQ-109/MQ-110/F-4E
			_d_g_vlvl = SurvivorData.zone_virtual_level(_d_difficulty, _d_lvl, "garrison")
			_d_budget = SurvivorData.zone_defender_budget(_d_difficulty, _d_lvl)
			_d_exclude_sentinel = true
			var spawned := 0
			if mission_type != "naval" and mission_type != "airfield" \
					and randf() < ZoneMission.SENTINEL_GARRISON_CHANCE \
					and mission._count_type_in_scene(int(SurvivorSpawner.EnemyType.UAV_COMMANDER)) == 0:
				mission._spawn_sentinel_garrison(zone_id, zone)
				_d_budget = int(_d_budget * 0.5)
				# 哨兵中队一次生成整队，占满本帧的单位额度。
				spawned = ZoneMission.SPAWN_SLICE_MAX_UNITS
			_d_center = zone["center"]
			_d_garrison_r = maxf(ZoneMission.GARRISON_ORBIT_RADIUS,
				float(zone["radius"]) * ZoneMission.GARRISON_ORBIT_RADIUS_FRAC)
			_d_units = []
			_d_guard = 12
			_d_stage = DefenderStage.SELECT
			return spawned
		DefenderStage.SELECT:
			_select_squad()
			return 0
		DefenderStage.MEMBER:
			return _spawn_member()
	return 0


func _select_squad() -> void:
	while _d_budget > 0 and _d_guard > 0:
		_d_guard -= 1
		var pool := SurvivorData.get_zone_enemy_pool(_d_g_vlvl, _d_exclude_sentinel, true)
		if pool.is_empty():
			break
		var pick := SurvivorData.pick_zone_enemy(pool, _d_budget, _d_g_vlvl)
		if pick.is_empty():
			break
		_d_etype = int(pick["type"])
		_d_cost = int(pick["cost"])
		var want_size: int = ZoneMission._squad_size_for_cost(_d_cost)
		var affordable: int = int(floor(float(_d_budget) / float(_d_cost)))
		_d_squad_size = mini(want_size, maxi(affordable, 1))
		var type_cap: int = int(SurvivorData.TOKEN_INSTANCE_CAP.get(_d_etype, -1))
		if type_cap > 0:
			var room: int = type_cap - mission._count_type_in_scene(_d_etype)
			if room <= 0:
				continue
			_d_squad_size = mini(_d_squad_size, room)
		_d_leader_pos = mission._zone_air_spawn_origin(_d_center)
		_d_heading_deg = ZoneMission._zone_air_heading_deg(_d_leader_pos, _d_center)
		_d_heading_rad = deg_to_rad(_d_heading_deg)
		_d_wp = PackedVector2Array()
		var n_wp := 4
		for k in range(n_wp):
			var wa := float(k) / float(n_wp) * TAU
			_d_wp.append(_d_center + Vector2(cos(wa), sin(wa)) * _d_garrison_r)
		_d_start_wp_idx = ZoneMission._zone_patrol_entry_index(_d_leader_pos, _d_center, n_wp)
		_d_squad = SquadFactory.create()
		_d_squad.formation = Squad.random_formation()
		_d_member = 0
		_d_stage = DefenderStage.MEMBER
		return
	_d_stage = DefenderStage.COMMIT


func _spawn_member() -> int:
	if _d_member >= _d_squad_size or _d_cost > _d_budget:
		_d_stage = DefenderStage.SELECT
		return 0
	var i := _d_member
	var spawn_pos: Vector2
	if i == 0:
		spawn_pos = _d_leader_pos
	else:
		var offset: Vector2 = _d_squad.get_formation_offset(i)
		spawn_pos = _d_leader_pos + offset.rotated(_d_heading_rad)
	var ac: Aircraft = mission._spawner._create_enemy(_d_etype, spawn_pos, _d_heading_deg)
	if not ac:
		_d_stage = DefenderStage.SELECT
		return 0
	mission._tag_zone_air_ingress(ac, _d_center,
		_d_garrison_r + ZoneMission.ZONE_AIR_INGRESS_ARRIVE_BAND_PX)
	ac.set_meta("zone_garrison", zone_id)
	if i == 0:
		SquadFactory.register_leader(_d_squad, ac)
	else:
		SquadFactory.register_wingman(_d_squad, ac, true)
	var ai := mission._get_ai_of(ac)
	if ai:
		ai.waypoints = _d_wp
		ai.current_waypoint_index = (_d_start_wp_idx + i) % 4
	_d_units.append(ac)
	_d_budget -= _d_cost
	_d_member += 1
	return 1
