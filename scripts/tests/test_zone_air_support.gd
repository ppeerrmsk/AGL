extends RefCounted

## 战区友军支援无头回归：规模、对空/对地限定、ALLY 契约与物理撤离。
## 运行：bench/run.cmd zone_air_support

var _pass := 0
var _fail := 0


class StubMode extends Node2D:
	var upgrade_stacks: Dictionary = {}
	var _player_profile = null
	var _bench_mode := true
	var hud = null
	var _tutorial = null

	func is_boss_phase() -> bool:
		return false

	func archive_enabled() -> bool:
		return false

	func is_world_pos_visible(_pos: Vector2, _extra_radius: float = 0.0) -> bool:
		return false


class VisibleSpawnMode extends Node2D:
	func is_world_pos_visible(_pos: Vector2, _extra_radius: float = 0.0) -> bool:
		return true


class ToggleVisibilityMode extends Node2D:
	var everything_visible := true

	func is_world_pos_visible(_pos: Vector2, _extra_radius: float = 0.0) -> bool:
		return everything_visible


class SpawnProbeMission extends ZoneMission:
	var spawn_calls: Array[StringName] = []

	func _spawn_zone_units(zone_id: StringName, _zone: Dictionary) -> void:
		spawn_calls.append(zone_id)
		_spawned_zones[zone_id] = [RefCounted.new()]


class StubDirector extends RefCounted:
	var mode: Node2D
	var player: Aircraft
	var spawner: SurvivorSpawner


func run() -> void:
	print("\n════════ 战区友军空中支援 ════════")
	_test_visible_spawn_deadlock_recovery()
	_test_hostile_zone_edge_ingress()
	_test_conquered_garrison_egress()
	_test_support_count()
	_test_activation_gate_and_once()
	_test_ally_label_identity()
	_test_ally_contract_and_air_only_targeting()
	_test_ground_support_targeting_and_a10_loadout()
	_test_third_party_reward_isolation()
	_test_merged_weakness_ground_heal()
	_test_egress_lifecycle()
	_test_ace_f15_spawn_factory()
	_test_ace_f15_intercept_support()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════\n")


func _test_visible_spawn_deadlock_recovery() -> void:
	var zones := ZoneData.new(Callable(), false, true)
	for zone in ZoneData.ZONES:
		zones.set_state(zone["id"], ZoneData.State.LOCKED)
	var zone_e := zones.get_zone_by_id(&"E")
	var center: Vector2 = zone_e["center"]
	var radius: float = float(zone_e["radius"])
	var mode := VisibleSpawnMode.new()
	zones.set_mission_type(&"E", "air")

	# 截图回归：任务已选中，玩家停在 E 圈边外约 300m；旧代码会被可见性门永久拦住。
	var selected_player := Aircraft.new()
	selected_player.position = center + Vector2(radius + 150.0, 0.0)
	zones.set_state(&"E", ZoneData.State.AVAILABLE)
	zones.select_zone(&"E")
	zones._rewards[&"E"] = {"id": "spawn_lead_probe"}
	var selected_mission := SpawnProbeMission.new()
	selected_mission.mode = mode
	selected_mission._zones = zones
	selected_mission._player = selected_player
	selected_mission._ensure_spawned_for_active_zones()
	_check("高价值任务先完整等待 6 秒广播前置",
		selected_mission.spawn_calls.is_empty()
		and selected_mission._spawn_lead_timers.has(&"E"))
	selected_mission._ensure_spawned_for_active_zones(ZoneMission.MISSION_SPAWN_RADIO_LEAD_S)
	_check("已选中纯空战并抵达圈边时改走边缘入场，不被可见性门锁死",
		selected_mission.spawn_calls == [&"E"])

	# 一旦进入 LIVE，同生命周期内取消选择也不能把战斗暂停或重抽。
	zones.set_state(&"E", ZoneData.State.AVAILABLE)
	zones.selected_id = &""
	selected_player.position = center + Vector2(radius + 5000.0, 0.0)
	selected_mission._ensure_spawned_for_active_zones()
	_check("已生成战区取消选择后仍保持同一批 LIVE 内容",
		selected_mission.spawn_calls == [&"E"]
		and selected_mission._spawned_zones.has(&"E"))

	# 仍在远处的任务继续守住“不在玩家画面内刷新”铁则。
	selected_mission._spawned_zones.clear()
	selected_mission.spawn_calls.clear()
	zones.select_zone(&"E")
	selected_player.position = center + Vector2(radius
		+ ZoneMission.VISIBLE_SPAWN_RECOVERY_APPROACH_PX + 1.0, 0.0)
	selected_mission._ensure_spawned_for_active_zones()
	selected_mission._ensure_spawned_for_active_zones(ZoneMission.MISSION_SPAWN_RADIO_LEAD_S)
	_check("已选中但尚未抵达时仍禁止画面内生成",
		selected_mission.spawn_calls.is_empty())
	_check("可见性阻塞时保留归零计时器且不重复广播",
		selected_mission._spawn_lead_timers.has(&"E")
		and is_zero_approx(float(selected_mission._spawn_lead_timers[&"E"])))

	# 玩家手动飞入未选中战区也必须能开始任务，不能形成空圈。
	zones.set_state(&"E", ZoneData.State.AVAILABLE)
	zones.selected_id = &""
	selected_player.position = center
	selected_mission._ensure_spawned_for_active_zones()
	_check("手动进入未选中战区时恢复实体生成",
		selected_mission.spawn_calls == [&"E"])

	# 静态任务仍保留原有死锁恢复；本次只改变其中空中驻守队的出生路径。
	selected_mission._spawned_zones.clear()
	selected_mission.spawn_calls.clear()
	selected_mission._spawn_lead_timers.clear()
	zones.set_mission_type(&"E", "ground")
	selected_player.position = center
	selected_mission._ensure_spawned_for_active_zones()
	selected_mission._ensure_spawned_for_active_zones(ZoneMission.MISSION_SPAWN_RADIO_LEAD_S)
	_check("地面/舰船类任务保留既有可见性死锁恢复",
		selected_mission.spawn_calls == [&"E"])

	selected_mission.free()
	selected_player.free()
	mode.free()


func _test_hostile_zone_edge_ingress() -> void:
	var mode := StubMode.new()
	var player := Aircraft.new()
	player.global_position = Vector2(1200.0, 2600.0)
	player.heading = 0.0
	var spawner := SurvivorSpawner.new()
	spawner.mode = mode
	spawner.player_aircraft = player
	var mission := ZoneMission.new()
	mission._spawner = spawner

	var center := Vector2(-2200.0, -1800.0)
	var entry: Vector2 = mission._zone_air_spawn_origin(center)
	_check("战区敌机入口结构性位于地图边界外",
		MapBoundary.distance_to_edge(entry)
			<= -SurvivorData.INGRESS_SPAWN_OUTSET_PX + 0.01)
	var heading_deg: float = ZoneMission._zone_air_heading_deg(entry, center)
	var heading_dir := Vector2(sin(deg_to_rad(heading_deg)),
		-cos(deg_to_rad(heading_deg)))
	_check("战区敌机生成航向指向战区中心",
		heading_dir.dot((center - entry).normalized()) > 0.999)

	var aircraft := Aircraft.new()
	aircraft.global_position = entry
	mission._tag_zone_air_ingress(aircraft, center, 1500.0)
	spawner._tick_zone_air_ingress(aircraft)
	_check("尚未抵达巡逻环时保留远距冻结豁免",
		bool(aircraft.get_meta("zone_ingress", false)))
	aircraft.global_position = center + Vector2(1499.0, 0.0)
	spawner._tick_zone_air_ingress(aircraft)
	_check("抵达巡逻环后撤销远距冻结豁免",
		not aircraft.has_meta("zone_ingress")
		and not aircraft.has_meta("zone_ingress_center")
		and not aircraft.has_meta("zone_ingress_arrive_radius"))

	var mission_source := FileAccess.get_file_as_string(
		"res://scripts/survivor/zone_mission.gd")
	_check("空战 TGT、普通驻守与 Sentinel 驻守均消费同一边缘入口",
		mission_source.count("_zone_air_spawn_origin(center)") >= 3
		and mission_source.count("_tag_zone_air_ingress(") >= 5)

	aircraft.free()
	mission.free()
	spawner.free()
	player.free()
	mode.free()


func _test_conquered_garrison_egress() -> void:
	var mode := ToggleVisibilityMode.new()
	var mission := ZoneMission.new()
	mission.mode = mode
	var enemy := _make_aircraft(CombatUnit.TEAM_HOSTILE, Vector2(1200.0, 800.0))
	enemy.params = AircraftParams.new()
	enemy.params.max_speed = 1400.0
	enemy.is_mission_target = true
	mode.add_child(enemy)
	mission._garrison_zones[&"A"] = [enemy]

	mission._begin_conquered_garrison_egress(&"A")
	var ai := enemy._ai_ref
	var exit_point: Vector2 = ai._directive.params.get("target", Vector2.ZERO)
	_check("攻克后幸存驻守敌机进入真实撤离",
		bool(enemy.get_meta(&"zone_retiring", false))
		and not mission._garrison_zones.has(&"A")
		and mission._pending_despawn == [enemy])
	_check("撤离清目标、脱编队、关闭重新交战并开加力",
		not enemy.is_mission_target and not ai.enable_combat
		and enemy.combat_target == null and enemy.is_afterburner)
	_check("撤离指令直飞最近地图边界外",
		ai._directive != null and ai._directive.combat_disabled
		and ai._directive.priority == ZoneMission.RETIRE_DIRECTIVE_PRIORITY
		and MapBoundary.distance_to_edge(exit_point) < 0.0)

	# 可见期间不允许释放；短暂离屏后重新看见必须把宽限计时清零。
	mission._flush_pending_despawn(ZoneMission.CONQUERED_RETIRE_OFFSCREEN_GRACE_S)
	_check("画面内撤离机不会凭空消失", not enemy.is_queued_for_deletion())
	mode.everything_visible = false
	mission._flush_pending_despawn(1.0)
	mode.everything_visible = true
	mission._flush_pending_despawn(ZoneMission.RETIRE_VISIBILITY_CHECK_INTERVAL_S)
	mode.everything_visible = false
	mission._flush_pending_despawn(1.8)
	_check("重新进入视野会重置离屏宽限", not enemy.is_queued_for_deletion())
	mission._flush_pending_despawn(0.2)
	_check("持续离屏两秒后静默关闭实体",
		enemy.is_queued_for_deletion()
		and bool(enemy.get_meta("xp_granted", false))
		and mission._pending_despawn.is_empty())

	mission.free()
	mode.free()


func _test_support_count() -> void:
	_check("1★ 支援 2 架", ZoneMission.support_count_for_difficulty(1) == 2)
	_check("2★ 支援 3 架", ZoneMission.support_count_for_difficulty(2) == 3)
	_check("3★ 支援 4 架", ZoneMission.support_count_for_difficulty(3) == 4)
	_check("越界星级仍夹在 2~4", ZoneMission.support_count_for_difficulty(99) == 4)


func _test_activation_gate_and_once() -> void:
	var mission := ZoneMission.new()
	var zones := ZoneData.new(Callable())
	var dummy_spawner := SurvivorSpawner.new()
	mission._zones = zones
	mission._spawner = dummy_spawner
	var zone_a := zones.get_zone_by_id(&"A")
	zones.debug_set_available(&"A")
	zones.set_mission_type(&"A", "ground")
	mission._start_air_support_if_needed(&"A", zone_a)
	_check("对地 ACTIVE 后登记一支待入场队", mission._support_flights.size() == 1)
	_check("对地支援固定 2 架 A-10",
		String(mission._support_flights[0]["support_kind"]) == "attack"
		and int(mission._support_flights[0]["support_count"]) == 2)
	mission._start_air_support_if_needed(&"A", zone_a)
	_check("同轮重复触发不生成第二支", mission._support_flights.size() == 1)

	var zone_b := zones.get_zone_by_id(&"B")
	zones.debug_set_available(&"B")
	zones.set_mission_type(&"B", "squadron")
	mission._start_air_support_if_needed(&"B", zone_b)
	_check("对空权益首次 ACTIVE 后登记独立支援队", mission._support_flights.size() == 2)
	_check("对空支援按星级使用 F-86",
		String(mission._support_flights[1]["support_kind"]) == "fighter")

	var zone_f := zones.get_zone_by_id(&"F")
	zones.debug_set_available(&"F")
	zones.set_mission_type(&"F", "ground")
	mission._start_air_support_if_needed(&"F", zone_f)
	_check("同局第二个对地战区不再派支援", mission._support_flights.size() == 2)
	var zone_g := zones.get_zone_by_id(&"G")
	zones.debug_set_available(&"G")
	zones.set_mission_type(&"G", "air")
	mission._start_air_support_if_needed(&"G", zone_g)
	_check("同局第二个对空战区不再派支援", mission._support_flights.size() == 2)

	var zone_e := zones.get_zone_by_id(&"E")
	zones.debug_set_available(&"E")
	zones.set_mission_type(&"E", "naval")
	mission._start_air_support_if_needed(&"E", zone_e)
	_check("对舰任务不登记支援", mission._support_flights.size() == 2)
	var zone_af := zones.get_zone_by_id(&"AF_HANEDA")
	zones.debug_set_available(&"AF_HANEDA")
	zones.set_mission_type(&"AF_HANEDA", "airfield")
	mission._start_air_support_if_needed(&"AF_HANEDA", zone_af)
	_check("机场任务不登记 A-10 支援", mission._support_flights.size() == 2)

	dummy_spawner.free()
	mission.free()


func _test_ally_label_identity() -> void:
	var ally := _make_aircraft(CombatUnit.TEAM_ALLY, Vector2.ZERO)
	ally.params = AircraftParams.new()
	ally.params.display_name = "F-15 Eagle"
	ally.callsign = "Falcon-2"
	_check("绿色友军只缩机名后缀并保留完整呼号",
		AircraftRenderer.ally_identity_label(ally) == "F-15 E Falcon-2")
	ally.callsign = "ALLY-Falcon-2"
	_check("旧 ALLY- 前缀也不会进入标签",
		AircraftRenderer.ally_identity_label(ally) == "F-15 E Falcon-2")
	ally.callsign = "Hound-1"
	_check("剧情固定友军呼号保留全名",
		AircraftRenderer.ally_identity_label(ally) == "F-15 E Hound-1")
	ally.free()


func _test_ally_contract_and_air_only_targeting() -> void:
	var support := _make_aircraft(CombatUnit.TEAM_HOSTILE, Vector2.ZERO)
	support.params = AircraftParams.new()
	AllyForce.convert_aircraft(support)
	support.set_meta("air_targets_only", true)
	_check("转换为第三方 ALLY", support.team == CombatUnit.TEAM_ALLY)
	_check("支援不占 token", int(support.get_meta("token_cost", -1)) == 0)
	_check("支援跳过远距清理", bool(support.get_meta("skip_far_cleanup", false)))

	var ground := GroundUnit.new()
	ground.team = CombatUnit.TEAM_HOSTILE
	var hostile_air := _make_aircraft(CombatUnit.TEAM_HOSTILE, Vector2(100.0, 0.0))
	_check("空中支援拒绝地面目标",
		not support._ai_ref.acquire_target(ground, AIController.TargetSource.TS_DIRECTIVE))
	_check("空中支援接受敌方飞机",
		support._ai_ref.acquire_target(hostile_air, AIController.TargetSource.TS_DIRECTIVE))

	support.free()
	hostile_air.free()
	ground.free()


func _test_ground_support_targeting_and_a10_loadout() -> void:
	var support := _make_aircraft(CombatUnit.TEAM_ALLY, Vector2.ZERO)
	support.set_meta("ground_targets_only", true)
	var ground := GroundUnit.new()
	ground.team = CombatUnit.TEAM_HOSTILE
	var hostile_air := _make_aircraft(CombatUnit.TEAM_HOSTILE, Vector2(100.0, 0.0))
	var hostile_ship := NavalUnit.new()
	hostile_ship.team = CombatUnit.TEAM_HOSTILE
	_check("A-10 支援接受地面单位",
		support._ai_ref.acquire_target(ground, AIController.TargetSource.TS_DIRECTIVE))
	support._ai_ref.release_target(AIController.TargetSource.TS_DIRECTIVE, "test")
	_check("A-10 支援拒绝敌方飞机",
		not support._ai_ref.acquire_target(hostile_air, AIController.TargetSource.TS_DIRECTIVE))
	_check("A-10 支援拒绝舰船",
		not support._ai_ref.acquire_target(hostile_ship, AIController.TargetSource.TS_DIRECTIVE))

	var mission := ZoneMission.new()
	var mode := StubMode.new()
	mission.mode = mode
	var a10 := mission._create_a10_support(Vector2.ZERO, 0.0)
	_check("支援工厂生成 A-10", a10 != null and a10.params.display_name == "A-10")
	_check("支援 A-10 仅保留 GAU-8、无火箭", a10.params.gun != null and a10.params.rocket == null)
	_check("支援 A-10 移除鱼雷", a10.params.torpedo == null)
	_check("支援 A-10 使用 ALLY 且只对地",
		a10.team == CombatUnit.TEAM_ALLY and not a10.attack_air_targets
		and bool(a10.get_meta("ground_targets_only", false)))
	_check("支援 A-10 使用简化对地 AI",
		a10._ai_ref != null and a10._ai_ref.simple_ai and a10._ai_ref.ground_combat_only)

	support.free()
	hostile_air.free()
	hostile_ship.free()
	ground.free()
	mission.free()
	mode.free()


func _test_third_party_reward_isolation() -> void:
	var mode := StubMode.new()
	var spawner := SurvivorSpawner.new()
	spawner.mode = mode
	var player := _make_aircraft(CombatUnit.TEAM_PLAYER, Vector2.ZERO)
	player.params = AircraftParams.new()
	player.params.max_hp = 100.0
	player.hp = 50.0
	mode.upgrade_stacks = {SkillHooks.SKILL_KILL_STATUS_HEAL: 1}
	mode.add_child(player)
	spawner.player_aircraft = player
	var survivor_player := SurvivorPlayer.new()
	survivor_player.level = 5
	survivor_player.aircraft = player
	spawner.survivor_player = survivor_player

	var victim := _make_aircraft(CombatUnit.TEAM_HOSTILE, Vector2(200.0, 0.0))
	victim.params = AircraftParams.new()
	victim.is_destroyed = true
	victim.set_meta("enemy_type", "f86")
	victim.set_meta("kill_attacker_team", CombatUnit.TEAM_ALLY)
	mode.add_child(victim)
	spawner._detect_kills()
	_check("ALLY 击落不给玩家 XP", survivor_player.total_xp_gained == 0)
	_check("ALLY 击落不计玩家击杀数", spawner.kill_count == 0)
	_check("ALLY 击落不触发玩家击杀回血", is_equal_approx(player.hp, 50.0))
	_check("ALLY 击落仍完成尸体结算", bool(victim.get_meta("xp_granted", false)))

	survivor_player.free()
	spawner.free()
	mode.free()


func _test_merged_weakness_ground_heal() -> void:
	var mode := StubMode.new()
	mode.upgrade_stacks = {SkillHooks.SKILL_KILL_STATUS_HEAL: 1}
	var spawner := SurvivorSpawner.new()
	spawner.mode = mode
	var player := _make_aircraft(CombatUnit.TEAM_PLAYER, Vector2.ZERO)
	player.params = AircraftParams.new()
	player.params.max_hp = 100.0
	player.hp = 50.0
	var survivor_player := SurvivorPlayer.new()
	survivor_player.aircraft = player
	spawner.survivor_player = survivor_player
	var victim := GroundUnit.new()
	spawner._kill_heal(victim)
	_check("虐弱合并：普通地面击杀回复 5 HP", is_equal_approx(player.hp, 55.0))
	player.hp = 50.0
	victim.status_effects[StatusEffects.JAM] = 5.0
	spawner._kill_heal(victim)
	_check("虐弱合并：异常地面击杀回复 35 HP", is_equal_approx(player.hp, 85.0))
	victim.free()
	player.free()
	survivor_player.free()
	spawner.free()
	mode.free()


func _test_egress_lifecycle() -> void:
	var mission := ZoneMission.new()
	var support := _make_aircraft(CombatUnit.TEAM_ALLY, Vector2(1000.0, 2000.0))
	support.params = AircraftParams.new()
	support.params.max_speed = 1200.0
	support.hp = 50.0
	var anchor := Node2D.new()
	var flight := {
		"id": 7,
		"zone_id": &"zone_test",
		"phase": ZoneMission.SupportPhase.ON_STATION,
		"members": [support],
		"anchor": anchor,
		"hp_watch": support.hp,
		"reengage_s": 0.0,
	}
	mission._support_flights = [flight]
	mission._active_support_by_zone[&"zone_test"] = 7
	mission._begin_air_support_egress(&"zone_test", "test")

	var active: Dictionary = mission._support_flights[0]
	var exit_point: Vector2 = support._ai_ref.waypoints[0]
	_check("任务结束切换 EGRESS",
		int(active["phase"]) == ZoneMission.SupportPhase.EGRESS)
	_check("同战区活动代际立即释放",
		not mission._active_support_by_zone.has(&"zone_test"))
	_check("撤离时关闭主动交战", not support._ai_ref.enable_combat)
	_check("撤离航点位于地图外", MapBoundary.distance_to_edge(exit_point) < 0.0)
	_check("撤离开启加力并压满速度",
		support.is_afterburner and is_equal_approx(support.target_speed_kmh, 1200.0))

	support.global_position = Vector2(MapBoundary.world_half_px() + 801.0, 0.0)
	_check("飞出边界 800px 后结束生命周期",
		mission._tick_air_support_egress(active, 0.5))
	_check("静默释放前标记不结算 XP", bool(support.get_meta("xp_granted", false)))

	mission.free()
	if is_instance_valid(anchor) and not anchor.is_queued_for_deletion():
		anchor.free()
	if is_instance_valid(support) and not support.is_queued_for_deletion():
		support.free()


func _test_ace_f15_intercept_support() -> void:
	var event := AceReinforcementEvent.new()
	var ace := _make_aircraft(CombatUnit.TEAM_HOSTILE, Vector2.ZERO)
	ace.params = AircraftParams.new()
	var squad := AceSupportSquad.new("marathon")
	squad.members = [ace]
	squad.all_members = [ace]
	squad.active = true
	event._squad = squad

	var f15_a := _make_aircraft(CombatUnit.TEAM_ALLY, Vector2(1000.0, 0.0))
	var f15_b := _make_aircraft(CombatUnit.TEAM_ALLY, Vector2(1100.0, 0.0))
	for ac in [f15_a, f15_b]:
		ac.params = AircraftParams.new()
		ac.params.max_speed = 2000.0
		ac.hp = 60.0
		ac.set_meta("air_targets_only", true)
	event._ally_support = [f15_a, f15_b]
	event._maintain_ally_support_targets()
	_check("王牌截击支援固定 2 架 F-15", AceReinforcementEvent.ALLY_SUPPORT_COUNT == 2)
	_check("两架支援都优先锁定本事件王牌",
		f15_a.combat_target == ace and f15_b.combat_target == ace)
	_check("F-15 支援带只对空硬门",
		bool(f15_a.get_meta("air_targets_only", false))
		and bool(f15_b.get_meta("air_targets_only", false)))

	event._begin_ally_support_egress("test ace defeated")
	_check("王牌终态后 F-15 进入撤离",
		event._ally_support_egressing and not f15_a._ai_ref.enable_combat
		and not f15_b._ai_ref.enable_combat)
	_check("F-15 撤离航点位于地图外",
		MapBoundary.distance_to_edge(f15_a._ai_ref.waypoints[0]) < 0.0
		and MapBoundary.distance_to_edge(f15_b._ai_ref.waypoints[0]) < 0.0)
	_check("F-15 撤离开加力并压满速度",
		f15_a.is_afterburner and f15_b.is_afterburner
		and is_equal_approx(f15_a.target_speed_kmh, 2000.0)
		and is_equal_approx(f15_b.target_speed_kmh, 2000.0))

	f15_a.global_position = Vector2(MapBoundary.world_half_px() + 801.0, 0.0)
	f15_b.global_position = Vector2(MapBoundary.world_half_px() + 801.0, 100.0)
	_check("两架 F-15 飞出边界后结束支援生命周期",
		event._tick_ally_support_egress(0.5))
	_check("F-15 静默撤离不进入击杀结算",
		bool(f15_a.get_meta("xp_granted", false)) and bool(f15_b.get_meta("xp_granted", false)))

	ace.free()
	if is_instance_valid(f15_a) and not f15_a.is_queued_for_deletion():
		f15_a.free()
	if is_instance_valid(f15_b) and not f15_b.is_queued_for_deletion():
		f15_b.free()


func _test_ace_f15_spawn_factory() -> void:
	AceReinforcementEvent.reset_runtime_state()
	var mode := StubMode.new()
	var player := _make_aircraft(CombatUnit.TEAM_PLAYER, Vector2.ZERO)
	player.params = AircraftParams.new()
	mode.add_child(player)
	var survivor_player := SurvivorPlayer.new()
	survivor_player.level = 5
	survivor_player.aircraft = player
	var spawner := SurvivorSpawner.new()
	spawner.setup(mode, player, survivor_player, null, null)

	var enemy_ace := _make_aircraft(CombatUnit.TEAM_HOSTILE, Vector2(2000.0, 0.0))
	enemy_ace.params = AircraftParams.new()
	mode.add_child(enemy_ace)
	var squad := AceSupportSquad.new("marathon")
	squad.members = [enemy_ace]
	squad.all_members = [enemy_ace]
	squad.active = true
	squad.entry_origin_override = Vector2(MapBoundary.world_half_px() + 400.0, 0.0)

	var event := AceReinforcementEvent.new()
	event._squad = squad
	var director := StubDirector.new()
	director.mode = mode
	director.player = player
	director.spawner = spawner
	event.director = director
	event._spawn_ally_support(spawner, player)
	_check("非正式局 fail-open 实际生成两架 F-15", event._ally_support.size() == 2)
	var valid_contract := true
	for ac in event._ally_support:
		valid_contract = valid_contract and ac.team == CombatUnit.TEAM_ALLY \
			and ac.params != null and ac.params.display_name == "F-15" \
			and bool(ac.get_meta("air_targets_only", false)) \
			and int(ac.get_meta("token_cost", -1)) == 0
	_check("实际生成机走 ALLY/只对空/零 token 契约", valid_contract)
	_check("F-15 友军雷达收紧到 3000m",
		event._ally_support.all(func(ac):
			return is_equal_approx(ac.params.radar_range,
				AceReinforcementEvent.ALLY_SUPPORT_RADAR_RANGE_M)))
	_check("友军 Hound 不继承熔炉敌对版 Boss 强化",
		event._ally_support.all(func(ac):
			return ac.params.max_hp < AceTier.MAX_HP \
				and not ac.has_meta(&"ace_boss_grade") \
				and not ac.has_meta(&"crucible_profile")))
	_check("王牌截击支援固定呼号 Hound-1/Hound-2",
		event._ally_support[0].callsign == "Hound-1"
		and event._ally_support[1].callsign == "Hound-2")
	_check("实际生成两机已优先锁定王牌",
		event._ally_support[0].combat_target == enemy_ace
		and event._ally_support[1].combat_target == enemy_ace)

	var second_event := AceReinforcementEvent.new()
	second_event._squad = squad
	second_event.director = director
	second_event._spawn_ally_support(spawner, player)
	_check("同局第二次王牌事件不再派 F-15", second_event._ally_support.is_empty())

	event._finish()
	AceReinforcementEvent.reset_runtime_state()
	_check("新局 reset 恢复王牌 F-15 支援额度",
		not AceReinforcementEvent._ally_support_dispatched_this_run)
	spawner.free()
	survivor_player.free()
	mode.free()


func _make_aircraft(team: int, pos: Vector2) -> Aircraft:
	var ac := Aircraft.new()
	ac.team = team
	ac.global_position = pos
	var ai := AIController.new()
	ai.aircraft = ac
	ac._ai_ref = ai
	ac.add_child(ai)
	return ac


func _check(name: String, got: bool) -> void:
	if got:
		_pass += 1
	else:
		_fail += 1
	print("  %s %s" % ["✓" if got else "✗", name])
