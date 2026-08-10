extends RefCounted

const StrategicTargetScript = preload("res://scripts/strategic_target.gd")
const BomberMissionScript = preload("res://scripts/survivor/bomber_mission.gd")
const AtmosphereArtilleryScript = preload("res://scripts/survivor/atmosphere_artillery_unit.gd")
const SurvivorModeScript = preload("res://scripts/survivor/survivor_mode.gd")

var _pass := 0
var _fail := 0
var _spawned: Array = []

func run() -> void:
	print("\n════════ 轰炸 / 旋翼机 / 空爆炮验收 ════════")
	_test_strategic_damage_gate()
	_test_bomber_outcome_priority()
	_test_optional_mission_frequency()
	_test_spawn_announcement_lead()
	_test_bomber_escort_xp_reward()
	_test_failed_zone_contract()
	_test_bomber_escort_package_geometry()
	_test_rotorcraft_translation()
	_test_special_projectile_contracts()
	_test_airburst_aim_and_effectiveness()
	_test_naval_flak_mount()
	_test_visual_scale()
	_test_artillery_analytic_rail()
	_cleanup()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════\n")

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		printerr("  ✗ FAIL: %s" % label)

func _cleanup() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()

func _test_strategic_damage_gate() -> void:
	print("── A. 战略硬目标双重权限门 ──")
	var target = StrategicTargetScript.new()
	target.params = load("res://resources/strategic_target_params.tres")
	target.hp = 150.0
	target.team = CombatUnit.TEAM_HOSTILE
	var player := CombatUnit.new()
	player.team = CombatUnit.TEAM_PLAYER
	_spawned.append_array([target, player])
	target.take_damage(999.0, player, "gun")
	_check(is_equal_approx(target.hp, 150.0), "机炮伤害被拒绝")
	target.take_missile_damage(999.0)
	_check(is_equal_approx(target.hp, 150.0), "导弹一击必杀入口被拒绝")
	_check(target.is_lock_immune(), "永久不可锁定")
	target.take_bomber_damage(75.0, CombatUnit.TEAM_PLAYER, player)
	_check(is_equal_approx(target.hp, 75.0), "第一枚敌对轰炸弹保留 75 HP")
	target.take_bomber_damage(75.0, CombatUnit.TEAM_HOSTILE, null)
	_check(is_equal_approx(target.hp, 75.0), "同阵营轰炸弹不伤害")
	var escort_target = StrategicTargetScript.new()
	escort_target.params = load("res://resources/strategic_target_params.tres").duplicate(true)
	escort_target.params.max_hp = ZoneMission.BOMBER_ESCORT_TARGET_HP
	escort_target.hp = ZoneMission.BOMBER_ESCORT_TARGET_HP
	escort_target.team = CombatUnit.TEAM_HOSTILE
	escort_target.set_bomber_escort_objective(true)
	_check(escort_target.bomber_escort_objective and escort_target.is_mission_target,
		"护送目标在 AVAILABLE 预刷阶段即启用世界 TGT 提示")
	escort_target.take_bomber_damage(75.0, CombatUnit.TEAM_PLAYER, player)
	_check(escort_target.is_destroyed and escort_target.hp <= 0.0,
		"任意一架轰炸机的一枚 75 伤害炸弹即可摧毁护送目标")
	_spawned.append(escort_target)

func _test_bomber_outcome_priority() -> void:
	print("── A2. 轰炸护送成功优先 / 在途炸弹窗口 ──")
	var target := StrategicTargetScript.new()
	target.params = load("res://resources/strategic_target_params.tres")
	target.hp = 150.0
	target.team = CombatUnit.TEAM_HOSTILE
	var mission = BomberMissionScript.new()
	mission._outcome_target = target
	mission._outcome_enabled = true
	mission._deadline_s = 150.0
	var success := [false]
	var failed := [false]
	mission.mission_succeeded.connect(func(): success[0] = true)
	mission.mission_failed.connect(func(_reason: String): failed[0] = true)
	mission._last_release_at = 10.0
	mission._lifetime = 10.1
	mission._update_outcome(0)
	_check(not failed[0], "轰炸机全灭后最后一枚在途炸弹仍保留落地窗口")
	target.is_destroyed = true
	mission._lifetime = 13.4
	mission._update_outcome(0)
	_check(success[0] and not failed[0], "同一裁决 tick 目标已毁时成功优先于全灭失败")

	var timeout_target := StrategicTargetScript.new()
	timeout_target.params = load("res://resources/strategic_target_params.tres")
	timeout_target.hp = 150.0
	var timeout_mission = BomberMissionScript.new()
	timeout_mission._outcome_target = timeout_target
	timeout_mission._outcome_enabled = true
	timeout_mission._deadline_s = 150.0
	timeout_mission._lifetime = 150.0
	var timeout_reason := [""]
	timeout_mission.mission_failed.connect(func(reason: String): timeout_reason[0] = reason)
	timeout_mission._update_outcome(1)
	_check(timeout_reason[0] == "timeout", "150 秒截止时目标仍存活会失败")
	_spawned.append_array([target, mission, timeout_target, timeout_mission])

func _test_optional_mission_frequency() -> void:
	print("── A3. 可选战区任务整局频率 / 额外候选槽 ──")
	_check(ZoneData.optional_mission_quota_for_roll(0.0) == 2 \
			and ZoneData.optional_mission_quota_for_roll(0.199999) == 2,
		"整局骰低于 20% 时配额固定为两次")
	_check(ZoneData.optional_mission_quota_for_roll(0.20) == 1 \
			and ZoneData.optional_mission_quota_for_roll(1.0) == 1,
		"20% 边界及以上时配额固定为一次")
	_check(not ZoneData.initial_reward_unlock_ready(59.99, 3) \
			and not ZoneData.initial_reward_unlock_ready(60.0, 2) \
			and ZoneData.initial_reward_unlock_ready(60.0, 3),
		"普通奖励目标必须同时达到 60 秒与 Lv3")
	_check(not ZoneData.optional_mission_unlock_ready(149.99, 5) \
			and not ZoneData.optional_mission_unlock_ready(150.0, 4) \
			and ZoneData.optional_mission_unlock_ready(150.0, 5),
		"护送任务必须同时达到 150 秒与 Lv5")
	var deferred := ZoneData.new(Callable(), true, true)
	_check(deferred.get_state(&"A") == ZoneData.State.LOCKED \
			and deferred.get_state(&"B") == ZoneData.State.LOCKED \
			and deferred.get_optional_mission_assigned_count() == 0,
		"正式延迟构造不会在开局生成奖励目标或护送任务")
	_check(deferred.release_initial_reward_zones() \
			and not deferred.get_reward(&"A").is_empty() \
			and not deferred.get_reward(&"B").is_empty(),
		"门槛到达后才 roll 并开放 A/B 奖励")
	var released_optional := deferred.release_first_optional_mission()
	_check(released_optional != &"" \
			and deferred.get_mission_type(released_optional) == "bomber_escort",
		"首批奖励开放后才能追加一个护送候选")

	seed(20260809)
	var zones := ZoneData.new(Callable())
	var initial_optional_ids: Array[StringName] = []
	for zid in ZoneData.OPTIONAL_MISSION_CARRIER_IDS:
		if zones.get_state(zid) == ZoneData.State.AVAILABLE \
				and ZoneData.is_optional_mission_type(zones.get_mission_type(zid)):
			initial_optional_ids.append(zid)
	_check(initial_optional_ids.size() == 1, "每局开局额外保底且只保底一个可选战区任务")
	_check(not ZoneData.is_optional_mission_type(zones.get_mission_type(&"A")) \
			and not ZoneData.is_optional_mission_type(zones.get_mission_type(&"B")),
		"额外任务不吃掉 A/B 两个普通开局任务")
	_check(not zones.get_reward(&"A").is_empty() and not zones.get_reward(&"B").is_empty(),
		"A/B 普通奖励与开局保底槽保持存在")
	_check(zones.get_optional_mission_assigned_count() == 1 \
			and zones.get_optional_mission_run_quota() in [1, 2],
		"开局只消耗一次整局配额且硬上限为两次")

	var double_run: ZoneData = null
	for attempt in range(128):
		seed(900000 + attempt)
		var candidate := ZoneData.new(Callable())
		if candidate.get_optional_mission_run_quota() == 2:
			double_run = candidate
			break
	_check(double_run != null, "确定性种子样本能覆盖 20% 的二次配额分支")
	if double_run != null:
		var first_id := StringName(double_run._scheduled_optional_mission_ids.keys()[0])
		_check(double_run.get_optional_mission_assigned_count() == 1 \
				and double_run._scheduled_optional_mission_ids.size() == 1,
			"二次配额不会让两个可选任务在开局同时出现")
		double_run.select_zone(first_id)
		double_run.mark_failed(first_id, "frequency_test_first")
		_check(double_run.get_optional_mission_assigned_count() == 2 \
				and double_run._scheduled_optional_mission_ids.size() == 1,
			"第一次结算后的刷新才追加第二次可选任务")
		var second_id := StringName(double_run._scheduled_optional_mission_ids.keys()[0])
		_check(second_id != first_id and double_run.get_state(second_id) == ZoneData.State.AVAILABLE \
				and ZoneData.is_optional_mission_type(double_run.get_mission_type(second_id)),
			"第二次使用不同生命周期槽并作为额外候选开放")
		_check(double_run.get_reward(second_id).is_empty(), "第二次可选任务同样不占普通战区奖励")
		double_run.mark_failed(second_id, "frequency_test_second")
		_check(double_run.get_optional_mission_assigned_count() == 2 \
				and double_run._scheduled_optional_mission_ids.is_empty(),
			"第二次结算后不再刷新第三次任务")
	randomize()

func _test_bomber_escort_xp_reward() -> void:
	print("── A4. 轰炸护送只发特殊经验 ──")
	seed(20260808)
	var zones := ZoneData.new(Callable())
	zones.debug_set_mission_type(&"A", "bomber_escort")
	_check(zones.get_reward(&"A").is_empty(), "护送任务清除已有普通战区奖励")
	_check(ZoneData.bomber_escort_xp_reward(1) == 150, "一星护送固定奖励 150 XP")
	_check(ZoneData.bomber_escort_xp_reward(2) == 300, "二星护送固定奖励 300 XP")
	_check(ZoneData.bomber_escort_xp_reward(3) == 450, "三星护送固定奖励 450 XP")
	var i18n_ready := true
	for locale in ["zh", "en", "ja"]:
		var translation := load("res://i18n/gameplay.%s.translation" % locale) as Translation
		i18n_ready = i18n_ready and translation != null \
			and not str(translation.get_message("ZONE_REWARD_BOMBER_XP_FMT")).is_empty() \
			and not str(translation.get_message("ZONE_CLEARED_BOMBER_XP_FMT")).is_empty() \
			and not str(translation.get_message("ZONE_OPTIONAL_MISSION_TAG")).is_empty() \
			and not str(translation.get_message("ZONE_OPTIONAL_BOMBER_ESCORT_NAME")).is_empty()
	_check(i18n_ready, "中英日 Translation 资源包含可选任务类别、护送名称与 XP 提示")

	var untouched_roll_count := zones._reward_roll_count
	zones.debug_set_mission_type(&"C", "bomber_escort")
	zones.debug_set_available(&"C")
	_check(zones.get_reward(&"C").is_empty() and zones._reward_roll_count == untouched_roll_count,
		"已知为护送任务时不抽普通奖励且不推进 pity")

	zones.set_airfield_difficulty(&"A", 3)
	var player_progress := SurvivorPlayer.new()
	var mode = SurvivorModeScript.new()
	mode._zone_data = zones
	mode.survivor_player = player_progress
	mode._bench_mode = true
	mode._on_zone_mission_completed(&"A")
	_check(player_progress.total_xp_gained == 450,
		"三星护送成功只把预告的 450 XP 注入共享经验池")
	_check(zones.get_state(&"A") == ZoneData.State.CLEARED,
		"特殊经验结算后仍按成功战区完成状态推进")
	_spawned.append_array([mode, player_progress])
	randomize()

func _test_spawn_announcement_lead() -> void:
	print("── A3b. 目标广播先于实体生成 ──")
	var zones := ZoneData.new(Callable(), true, true)
	zones.release_initial_reward_zones()
	for airport_id in ZoneData.AIRFIELD_IDS:
		zones.set_state(airport_id, ZoneData.State.LOCKED)
	var mode = SurvivorModeScript.new()
	mode._bench_mode = false
	var mission := ZoneMission.new()
	mission.mode = mode
	mission._zones = zones
	mission._player = Aircraft.new()
	var announced: Array = []
	mission.mission_spawn_announced.connect(func(zid: StringName, mission_type: String):
		announced.append([zid, mission_type]))
	mission._ensure_spawned_for_active_zones(0.0)
	_check(announced.size() == 2 and mission._spawn_lead_timers.size() == 2,
		"A/B 开放时先发广播信号并建立两个 6 秒倒计时")
	_check(mission._spawned_zones.is_empty(),
		"广播所在 tick 不生成任何奖励目标实体")
	mission._player.free()
	mission.free()
	mode.free()

	var optional_zones := ZoneData.new(Callable(), true, true)
	optional_zones.release_initial_reward_zones()
	var optional_id := optional_zones.release_first_optional_mission()
	for z in ZoneData.ZONES:
		var zid: StringName = z["id"]
		if zid != optional_id:
			optional_zones.set_state(zid, ZoneData.State.LOCKED)
	var optional_mode = SurvivorModeScript.new()
	optional_mode._bench_mode = false
	var optional_mission := ZoneMission.new()
	optional_mission.mode = optional_mode
	optional_mission._zones = optional_zones
	optional_mission._player = Aircraft.new()
	var optional_types: Array[String] = []
	optional_mission.mission_spawn_announced.connect(
		func(_zid: StringName, mt: String): optional_types.append(mt))
	optional_mission._ensure_spawned_for_active_zones(0.0)
	_check(optional_types == ["bomber_escort"] \
			and is_equal_approx(float(optional_mission._spawn_lead_timers[optional_id]), 6.0),
		"护送任务同样先广播并保持 6 秒实体生成前导")
	optional_mission._player.free()
	optional_mission.free()
	optional_mode.free()

func _test_failed_zone_contract() -> void:
	print("── A5. FAILED 战区无痕 / 无收益契约 ──")
	seed(20260808)
	var zones := ZoneData.new(Callable())
	zones.select_zone(&"A")
	zones.set_objective_center(&"A", Vector2(-321.0, -654.0))
	zones.set_dynamic_center(&"A", Vector2(123.0, 456.0), 900.0, 1.25)
	zones.set_mission_route(&"A", PackedVector2Array([Vector2(-1000.0, 0.0), Vector2.ZERO]))
	zones.set_mission_status(&"A", {"target_hp": 75.0})
	var before_cleared := zones.cleared_count
	zones.mark_failed(&"A", "test_timeout")
	_check(zones.get_state(&"A") == ZoneData.State.FAILED, "失败战区进入独立 FAILED 终态")
	_check(zones.selected_id == &"" and zones.cleared_count == before_cleared,
		"失败清选择且不计入攻克次数")
	_check(zones.get_reward(&"A").is_empty(), "失败战区不保留待领战区奖励")
	_check(zones.get_zone_center(&"A") != Vector2(123.0, 456.0)
			and not is_equal_approx(zones.get_zone_radius(&"A"), 900.0),
		"失败清除移动圆心与动态半径缓存")
	_check(not zones.has_dynamic_center(&"A")
			and zones.get_objective_center(&"A") != Vector2(-321.0, -654.0),
		"失败同时清除编队朝向与固定目标缓存")
	_check(zones.get_mission_route(&"A").is_empty() and zones.get_mission_status(&"A").is_empty(),
		"失败同时清除航线与任务状态缓存")
	var tactical := TacticalMap.new()
	tactical._zones = zones
	_check(tactical._should_hide_zone(&"A"), "FAILED 在战术地图绘制/hover/点击入口统一隐藏")
	tactical.free()
	randomize()

func _test_bomber_escort_package_geometry() -> void:
	print("── A6. 护送任务独立航线 / 场外入口 / 纵队 / 单次投弹 ──")
	var player_pos := MapBoundary.get_player_start()
	var first_plan := ZoneMission.build_bomber_escort_route(&"A", player_pos, MapBoundary.world_half_px())
	var target_pos: Vector2 = first_plan["target"]
	var first_route: PackedVector2Array = first_plan["route"]
	var entry: Vector2 = first_route[0]
	_check(MapBoundary.distance_to_edge(entry) < 0.0, "护送任务入口严格位于地图边界外")
	_check(entry.distance_to(player_pos) >= ZoneMission.BOMBER_ESCORT_PLAYER_CLEARANCE_PX,
		"场外入口离玩家至少 5000px（10km）")
	for zid in ZoneMission.BOMBER_ESCORT_ROUTE_SLOT_IDS:
		var plan := ZoneMission.build_bomber_escort_route(zid, player_pos, MapBoundary.world_half_px())
		var planned_target: Vector2 = plan.get("target", Vector2.INF)
		var planned_route: PackedVector2Array = plan.get("route", PackedVector2Array())
		var ordinary_center: Vector2 = _zone_center_for_test(zid)
		_check(planned_route.size() == 4 and MapGeography.is_ground_spawn_safe(planned_target),
			"%s 专用航线有四段节点且目标位于实体陆地" % zid)
		_check(planned_target != ordinary_center and planned_target.distance_to(ordinary_center) >= 500.0,
			"%s 目标不复用普通战区圆心" % zid)
		if planned_route.size() == 4:
			var axis := (planned_target - planned_route[0]).normalized()
			_check(MapBoundary.distance_to_edge(planned_route[0]) <= -ZoneMission.BOMBER_ESCORT_ENTRY_OUTSET_PX + 0.1
					and planned_route[0].distance_to(player_pos) >= ZoneMission.BOMBER_ESCORT_PLAYER_CLEARANCE_PX,
				"%s 航线从边界外至少 1200px 且避开玩家的一端入场" % zid)
			_check(is_equal_approx(planned_route[0].distance_to(planned_target),
				ZoneMission.BOMBER_ESCORT_INGRESS_LEG_PX),
				"%s 长机到目标固定为 12500px 等时航程" % zid)
			_check(absf((planned_route[1] - planned_target).cross(axis)) < 0.1
					and absf((planned_route[3] - planned_target).cross(axis)) < 0.1,
				"%s 入口、整队、目标与离场点保持同一直线" % zid)
	var flight_dir := (target_pos - entry).normalized()
	var slot_1 := SurvivorSpawner.bomber_formation_offset(1, 3, flight_dir,
		SurvivorSpawner.BomberFormation.TRAIL)
	var slot_2 := SurvivorSpawner.bomber_formation_offset(2, 3, flight_dir,
		SurvivorSpawner.BomberFormation.TRAIL)
	_check(absf(slot_1.cross(flight_dir)) < 0.01 and is_equal_approx(slot_1.dot(flight_dir), -300.0),
		"二号轰炸机在长机正后方 300px")
	_check(absf(slot_2.cross(flight_dir)) < 0.01 and is_equal_approx(slot_2.dot(flight_dir), -600.0),
		"三号轰炸机在长机正后方 600px")

	var aircraft_list: Array[Aircraft] = []
	var routes: Array = []
	var route := PackedVector2Array([entry, target_pos - flight_dir * 1500.0,
		target_pos, target_pos + flight_dir * 3500.0])
	for i in range(3):
		var ac := Aircraft.new()
		ac.params = AircraftParams.new()
		ac.params.cruise_speed = 820.0
		aircraft_list.append(ac)
		routes.append(route)
		_spawned.append(ac)
	var bm := BulletManager.new()
	var mission = BomberMissionScript.new()
	_check(mission.get_release_count() == BomberMission.RELEASE_COUNT,
		"既有气氛轰炸任务默认仍保持五枚投弹")
	mission.setup(aircraft_list, routes, target_pos, bm, null, 150.0, 1)
	_check(mission.get_release_count() == 1, "护送任务每架轰炸机只释放一枚炸弹")
	_check(mission.get_alive_bomber_count() == 3 and mission.get_phase_key() == "ingress",
		"地图状态接口能报告三架存活轰炸机与进入航段")
	_spawned.append_array([bm, mission])

	var zones := ZoneData.new(Callable())
	zones.debug_set_mission_type(&"A", "bomber_escort")
	zones.set_objective_center(&"A", target_pos)
	zones.set_dynamic_center(&"A", entry, 900.0, atan2(flight_dir.x, -flight_dir.y))
	var tactical := TacticalMap.new()
	tactical._zones = zones
	_check(tactical._zone_primary_center(&"A") == target_pos
			and zones.get_zone_center(&"A") == entry,
		"战术地图固定目标与移动编队位置使用两份独立缓存")
	tactical.free()
	var trigger := ZoneMission.new()
	trigger._zones = zones
	trigger._player = aircraft_list[0]
	zones.select_zone(&"A")
	_check(trigger._should_trigger(&"A", zones.get_zone_by_id(&"A")),
		"选择护送战区即可触发场外编队入场")
	trigger.free()

func _zone_center_for_test(zid: StringName) -> Vector2:
	for zone in ZoneData.ZONES:
		if zone["id"] == zid:
			return zone["center"]
	return Vector2.INF

func _test_rotorcraft_translation() -> void:
	print("── B. 旋翼机速度/机头解耦 ──")
	var ac := Aircraft.new()
	ac.params = load("res://resources/enemy_ah64.tres").duplicate(true)
	ac.heading = 0.0 # 机头朝北
	ac.target_position = Vector2(500, 0) # 向东平移
	ac.rotorcraft_aim_position = Vector2(0, -500) # 继续瞄北
	ac.target_speed_kmh = 180.0
	ac.target_altitude_tier = CombatUnit.AltitudeTier.LOW
	ac.altitude = 2000.0
	_spawned.append(ac)
	AircraftPhysics.update_rotorcraft(ac, 1.0)
	_check(ac.global_position.x > 0.0 and absf(ac.global_position.y) < 0.01, "可沿机头侧向平移")
	var velocity_heading := atan2(ac.rotorcraft_velocity.x, -ac.rotorcraft_velocity.y)
	_check(absf(rad_to_deg(ac.heading)) < 10.0 and absf(angle_difference(ac.heading, velocity_heading)) > deg_to_rad(60.0),
		"平移时机头仍朝瞄准点而非速度方向")
	ac.target_position = ac.global_position
	ac.target_speed_kmh = 0.0
	for i in range(4):
		AircraftPhysics.update_rotorcraft(ac, 1.0)
	_check(ac.speed <= 0.01, "可刹停至悬停")

func _test_special_projectile_contracts() -> void:
	print("── C. 炸弹/空爆弹数据契约 ──")
	var bm := BulletManager.new()
	var src := CombatUnit.new()
	src.team = CombatUnit.TEAM_HOSTILE
	src.altitude = 10000.0
	_spawned.append_array([bm, src])
	bm.spawn_bomber_bomb(Vector2.ZERO, Vector2(100, 0), src, 3.2, 160.0, 75.0)
	_check(bm._bombs.size() == 1 and is_equal_approx(float(bm._bombs[0]["radius_px"]), 80.0),
		"炸弹 160m 半径正确换算为 80px")
	bm.spawn_airburst_shell(Vector2.ZERO, 0.0, 450.0, src, 2.0, 5500.0, 220.0, 75.0, 7)
	_check(bm._airburst_shells.size() == 1 and is_equal_approx(float(bm._airburst_shells[0]["radius_px"]), 110.0),
		"空爆 220m 半径正确换算为 110px")
	_check(int(bm._airburst_shells[0]["burst_id"]) == 7, "三连发共享 burst id")
	bm.spawn_bullet(Vector2.ZERO, 0.0, 900.0, src, 0.0)
	_check(bool(bm._bullets.back().get("visual_only", false)),
		"零伤害气氛弹仍生成但进入免碰撞视觉快路径")
	var mission = BomberMissionScript.new()
	_spawned.append(mission)
	var exit := mission._egress_point(PackedVector2Array([Vector2.ZERO, Vector2(0, -1000)]), Vector2.ZERO)
	_check(exit.y < -5000.0, "任务完成后沿末段继续飞出地图")

func _test_airburst_aim_and_effectiveness() -> void:
	print("── D. 空爆炮射向约束 / 3000m 横穿实效 ──")
	var gun := AirburstAAUnit.new()
	var target := Aircraft.new()
	var bm := BulletManager.new()
	gun.bullet_manager = bm
	gun.ammo = 10000
	gun.team = CombatUnit.TEAM_HOSTILE
	gun.global_position = Vector2.ZERO
	target.params = AircraftParams.new()
	target.team = CombatUnit.TEAM_PLAYER
	target.global_position = Vector2(0.0, -3000.0 * CombatUnit.PIXELS_PER_METER)
	target.heading = PI * 0.5 # 向东横穿
	target.speed = 250.0
	target.altitude = 5500.0
	_spawned.append_array([gun, target, bm])

	var target_vel := Vector2(sin(target.heading), -cos(target.heading)) \
			* target.speed * CombatUnit.PIXELS_PER_METER
	var nominal_travel := gun.global_position.distance_to(target.global_position) \
			/ (AirburstAAUnit.SHELL_SPEED_MS * CombatUnit.PIXELS_PER_METER)
	var nominal_aim := target.global_position + target_vel * nominal_travel
	var nominal_heading := atan2(nominal_aim.x, -nominal_aim.y)
	var max_departure_error := 0.0
	var group_hits := 0
	var groups := 240
	seed(20260803)
	for group in range(groups):
		bm._airburst_shells.clear()
		gun._begin_burst(target)
		var group_hit := false
		for shell_index in range(AirburstAAUnit.BURST_SIZE):
			gun._fire_airburst_shell()
			var shell: Dictionary = bm._airburst_shells.back()
			var shell_vel: Vector2 = shell["vel"]
			var shell_heading := atan2(shell_vel.x, -shell_vel.y)
			max_departure_error = maxf(max_departure_error,
				absf(angle_difference(nominal_heading, shell_heading)))
			var fuse_time := float(shell["life"])
			var detonation_pos: Vector2 = shell["pos"] + shell_vel * fuse_time
			# 后两发仍用第一发冻结解，目标则在 0.25s 组内间隔中继续飞行。
			var target_at_burst := target.global_position + target_vel \
					* (fuse_time + float(shell_index) * AirburstAAUnit.BURST_INTERVAL)
			if detonation_pos.distance_to(target_at_burst) <= float(shell["radius_px"]):
				group_hit = true
		if group_hit:
			group_hits += 1
	var hit_rate := float(group_hits) / float(groups)
	_check(max_departure_error <= AirburstAAUnit.MAX_GROUP_AIM_ERROR \
			+ AirburstAAUnit.MAX_SHELL_AIM_JITTER + deg_to_rad(0.1),
		"所有炮弹都朝冻结预瞄空域发射（随机偏角 ≤ 8.6°）")
	_check(group_hits > 0 and group_hits < groups,
		"3000m / 250m·s 横穿样本同时存在命中组和落空组")
	print("    实测：%d 组中 %d 组至少一发覆盖，组命中率 %.1f%%；最大随机偏角 %.2f°" % [
		groups, group_hits, hit_rate * 100.0, rad_to_deg(max_departure_error)])
	randomize()

func _test_naval_flak_mount() -> void:
	print("── E. DDG 舰载 Flak 挂点 / 炮组状态 ──")
	var params: NavalParams = load("res://resources/naval/destroyer_ddg.tres").duplicate(true)
	var type_counts := {
		WeaponMountParams.WeaponType.VLS_SALVO: 0,
		WeaponMountParams.WeaponType.CIWS: 0,
		WeaponMountParams.WeaponType.NAVAL_FLAK: 0,
	}
	for cfg in params.mount_configs:
		if type_counts.has(cfg.weapon_type):
			type_counts[cfg.weapon_type] = int(type_counts[cfg.weapon_type]) + 1
	_check(params.mount_configs.size() == 4
			and int(type_counts[WeaponMountParams.WeaponType.VLS_SALVO]) == 2
			and int(type_counts[WeaponMountParams.WeaponType.CIWS]) == 1
			and int(type_counts[WeaponMountParams.WeaponType.NAVAL_FLAK]) == 1,
		"DDG 固定为 2×VLS + 1×CIWS + 1×Flak（总挂点仍为 4）")

	var ship := NavalUnit.new()
	ship.params = params
	ship.team = CombatUnit.TEAM_HOSTILE
	ship.heading = 0.0
	var flak_mount: WeaponMount = null
	for cfg in params.mount_configs:
		var mount := WeaponMount.new()
		mount.initialize(cfg)
		ship.mounts.append(mount)
		if cfg.weapon_type == WeaponMountParams.WeaponType.NAVAL_FLAK:
			flak_mount = mount
	var bullets := BulletManager.new()
	ship.bullet_manager = bullets
	var target := Aircraft.new()
	target.params = AircraftParams.new()
	target.team = CombatUnit.TEAM_PLAYER
	target.global_position = Vector2(0.0, -3000.0 * CombatUnit.PIXELS_PER_METER)
	target.heading = PI * 0.5
	target.speed = 250.0
	target.altitude = 5500.0
	_spawned.append_array([ship, bullets, target])
	CombatUnit.all_units = [ship, target]
	seed(20260804)

	ship._update_subsystems(1.0 / 60.0)
	_check(flak_mount != null and is_equal_approx(flak_mount.hp, 30.0),
		"Flak 原位继承被替换 CIWS 的 30 HP")
	_check(bullets._airburst_shells.size() == 1 and flak_mount.flak_remaining == 2
			and is_equal_approx(flak_mount.fire_cooldown, NavalWeapons.NAVAL_FLAK_BURST_COOLDOWN),
		"捕获目标后首弹立即出膛并冻结余下两发，6s 冷却从炮组开始计时")
	_check(bullets._bullets.is_empty()
			and bullets._airburst_shells[0]["source"] == ship,
		"舰载 Flak 走 airburst 管线且不生成 CIWS 拦截弹")

	ship._update_subsystems(0.24)
	ship._update_subsystems(0.02)
	ship._update_subsystems(0.25)
	_check(bullets._airburst_shells.size() == 3 and flak_mount.flak_remaining == 0,
		"后两发按 0.25s 组内间隔完成三连发")
	ship._update_subsystems(5.48)
	_check(bullets._airburst_shells.size() == 3,
		"6s 组间冷却结束前不得开始下一组")
	CombatUnit.all_units = []
	randomize()

func _test_visual_scale() -> void:
	print("── F. 统一视觉尺度 ──")
	var fighter := Aircraft.new()
	fighter.params = AircraftParams.new()
	fighter.altitude = 5500.0
	var bomber := Aircraft.new()
	bomber.params = load("res://resources/enemy_tu160.tres")
	bomber.set_meta("silhouette", "bomber")
	bomber.altitude = 5500.0
	_spawned.append_array([fighter, bomber])
	var fighter_extent := 36.0 * AircraftRenderer.visual_model_scale(fighter)
	var bomber_extent := 70.0 * AircraftRenderer.visual_model_scale(bomber)
	_check(bomber_extent > fighter_extent,
		"Tu-160 视觉轮廓大于普通战斗机")
	_check(is_equal_approx(AircraftRenderer.altitude_base_scale(fighter), 1.0), "MID 高度倍率为 1.0")


func _test_artillery_analytic_rail() -> void:
	print("── G. 气氛火炮解析式轨道 ──")
	var unit: GroundUnit = AtmosphereArtilleryScript.new()
	unit.max_ground_speed = 3.0
	var start := Vector2(120.0, -80.0)
	var axis := Vector2(0.6, -0.8).normalized()
	unit.global_position = start
	unit.call("configure_rail", start, axis, 350.0, 45.0)
	_spawned.append(unit)
	var center: Vector2 = unit.get("rail_center")
	var lateral := Vector2(-axis.y, axis.x)
	var max_ellipse_error := 0.0
	var max_step := 0.0
	var previous := unit.global_position
	for i in range(36000): # 10 分钟 @ 60Hz：覆盖多次窄端转弯且不靠真实帧率。
		unit._update_movement(1.0 / 60.0)
		var rel := unit.global_position - center
		var nx := rel.dot(axis) / 350.0
		var ny := rel.dot(lateral) / 45.0
		max_ellipse_error = maxf(max_ellipse_error, absf(nx * nx + ny * ny - 1.0))
		max_step = maxf(max_step, unit.global_position.distance_to(previous))
		previous = unit.global_position
	var phase := float(unit.get("rail_phase"))
	var tangent := -axis * sin(phase) * 350.0 + lateral * cos(phase) * 45.0
	var tangent_heading := atan2(tangent.x, -tangent.y)
	_check(is_equal_approx(unit.max_ground_speed, 3.0), "轨道速度固定为 3m/s")
	_check(max_ellipse_error < 0.00001, "10 分钟位置始终严格落在椭圆轨道上")
	_check(max_step < 0.04, "逐帧位移连续，无 waypoint 过冲或端点跳变")
	_check(phase >= 0.0 and phase < TAU and unit.global_position.is_finite(),
		"相位循环有界且无累计漂移/非有限坐标")
	_check(absf(angle_difference(unit.heading, tangent_heading)) < 0.0001,
		"车体朝向连续贴合轨道切线")
