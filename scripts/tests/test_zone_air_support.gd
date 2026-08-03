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


class StubDirector extends RefCounted:
	var mode: Node2D
	var player: Aircraft
	var spawner: SurvivorSpawner


func run() -> void:
	print("\n════════ 战区友军空中支援 ════════")
	_test_support_count()
	_test_activation_gate_and_once()
	_test_ally_contract_and_air_only_targeting()
	_test_ground_support_targeting_and_a10_loadout()
	_test_third_party_reward_isolation()
	_test_egress_lifecycle()
	_test_ace_f15_spawn_factory()
	_test_ace_f15_intercept_support()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════\n")


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
	_check("对空 ACTIVE 后登记独立支援队", mission._support_flights.size() == 2)
	_check("对空支援按星级使用 F-86",
		String(mission._support_flights[1]["support_kind"]) == "fighter")

	var zone_c := zones.get_zone_by_id(&"C")
	zones.debug_set_available(&"C")
	zones.set_mission_type(&"C", "naval")
	mission._start_air_support_if_needed(&"C", zone_c)
	_check("对舰任务不登记支援", mission._support_flights.size() == 2)
	var zone_d := zones.get_zone_by_id(&"D")
	zones.debug_set_available(&"D")
	zones.set_mission_type(&"D", "airfield")
	mission._start_air_support_if_needed(&"D", zone_d)
	_check("机场任务不登记 A-10 支援", mission._support_flights.size() == 2)

	dummy_spawner.free()
	mission.free()


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
	player.kill_heal_amount = 25.0
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
	_check("实际生成两机已优先锁定王牌",
		event._ally_support[0].combat_target == enemy_ace
		and event._ally_support[1].combat_target == enemy_ace)

	event._finish()
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
