extends RefCounted

## 未关注战区最简模拟：激活矩阵与 100+ 潜在成员不得进入实体层。

var _pass := 0
var _fail := 0

class ViewMode extends Node2D:
	var observed := false
	func is_world_pos_visible(_pos: Vector2, _radius: float = 0.0) -> bool:
		return observed

class SpawnProbe extends ZoneMission:
	var calls := 0
	func _spawn_zone_units(zone_id: StringName, _zone: Dictionary) -> void:
		calls += 1
		_spawned_zones[zone_id] = []


func run() -> void:
	print("\n════════ 未关注战区最简模拟 ════════")
	_test_activation_matrix()
	_test_hundred_plus_latent_population()
	_test_camera_observation()
	_test_strategic_ingress()
	_test_road_index_equivalence()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_activation_matrix() -> void:
	_check("远处普通 AVAILABLE 保持 LATENT",
		not ZoneMission.zone_simulation_should_activate(
			ZoneData.State.AVAILABLE, 2, 5000.0, 1200.0))
	_check("普通 SELECTED 在远处也进入 LIVE",
		ZoneMission.zone_simulation_should_activate(
			ZoneData.State.SELECTED, 2, 5000.0, 1200.0))
	_check("未选择但进入圆内会进入 LIVE",
		ZoneMission.zone_simulation_should_activate(
			ZoneData.State.AVAILABLE, 1, 1199.0, 1200.0))
	_check("3★全局威胁公开即进入 LIVE",
		ZoneMission.zone_simulation_should_activate(
			ZoneData.State.AVAILABLE, 3, 50000.0, 1200.0))
	_check("LOCKED/CLEARED 不得激活",
		not ZoneMission.zone_simulation_should_activate(
			ZoneData.State.LOCKED, 3, 0.0, 1200.0)
		and not ZoneMission.zone_simulation_should_activate(
			ZoneData.State.CLEARED, 3, 0.0, 1200.0))


func _test_hundred_plus_latent_population() -> void:
	var potential_members := 0
	var live_members := 0
	for _zone_index in range(12):
		var roster_size := 10
		potential_members += roster_size
		if ZoneMission.zone_simulation_should_activate(
				ZoneData.State.AVAILABLE, 2, 20000.0, 3500.0):
			live_members += roster_size
	_check("120 名潜在普通战区成员全部停留在战略层",
		potential_members == 120 and live_members == 0)


func _test_camera_observation() -> void:
	var zones := ZoneData.new(Callable(), false, true)
	for zone in zones.get_zone_definitions():
		zones.set_state(zone["id"], ZoneData.State.LOCKED)
	zones.set_state(&"E", ZoneData.State.AVAILABLE)
	zones.set_mission_type(&"E", "ground")
	zones._difficulties[&"E"] = 2
	zones._rewards[&"E"] = {"id": "view_probe"}
	var mode := ViewMode.new()
	var player := Aircraft.new()
	player.position = zones.get_zone_center(&"E") + Vector2(30000.0, 0.0)
	var mission := SpawnProbe.new()
	mission.mode = mode
	mission._zones = zones
	mission._player = player
	mission._ensure_spawned_for_active_zones()
	_check("未观察远区仍无目标和广播计时", mission.calls == 0 and mission._spawn_lead_timers.is_empty())
	mode.observed = true
	mission._ensure_spawned_for_active_zones()
	_check("镜头看到远处未选地面任务时立即准备，不等玩家或广播", mission.calls == 1)
	_check("观察准备不自动触发任务或发奖励", mission._triggered_zones.is_empty() and mission._completed_zones.is_empty())
	mission._ensure_spawned_for_active_zones()
	_check("反复观察只生成一次", mission.calls == 1)
	var refreshed := mission.refresh_active_zones_for_level(&"A")
	_check("别处完成任务不会重刷镜头里的目标", not refreshed.has(&"E") and mission._spawned_zones.has(&"E"))
	mode.observed = false
	mission._ensure_spawned_for_active_zones()
	_check("镜头移开不撤销已生成内容", mission._spawned_zones.has(&"E"))
	mission.free()
	player.free()
	mode.free()

func _test_strategic_ingress() -> void:
	var zones := ZoneData.new(Callable(), false, true)
	for zone in zones.get_zone_definitions():
		zones.set_state(zone["id"], ZoneData.State.LOCKED)
	zones.set_state(&"E", ZoneData.State.AVAILABLE)
	zones.set_mission_type(&"E", "squadron")
	zones._difficulties[&"E"] = 1
	var mode := ViewMode.new()
	var player := Aircraft.new()
	player.position = Vector2(80000, 80000)
	var mission := SpawnProbe.new()
	mission.mode = mode
	mission._player = player
	mission._zones = zones
	var center := zones.get_zone_center(&"E")
	mission._ensure_spawned_for_active_zones()
	var edge := mission._planned_flight_position(&"E", center, 1800.0)
	mission._ensure_spawned_for_active_zones(4.0)
	var inbound := mission._planned_flight_position(&"E", center, 1800.0)
	_check("无人观察四秒：零实体，航路向战区推进 500px",
		mission.calls == 0 and is_equal_approx(edge.distance_to(inbound), 500.0)
		and inbound.distance_to(center) < edge.distance_to(center))
	var follower := mission._planned_flight_position(&"E", center, 1800.0, 2)
	_check("第二梯队与先头队保留在途间距", is_equal_approx(follower.distance_to(inbound), 960.0))
	# 镜头仍在远处，只有玩家沿航线接近；在目标区外同样能截获敌机。
	var distant := player.position
	player.position = inbound
	mission._ensure_spawned_for_active_zones()
	_check("离开目标区的途中进入雷达也能接续真机", mission.calls == 1)
	player.position = distant
	mode.observed = true
	mission.prepare_visible_zones()
	_check("转镜头不重置起飞时刻或重复推进", mission.calls == 1 and
		inbound.is_equal_approx(mission._planned_flight_position(&"E", center, 1800.0)))
	mission._triggered_zones[&"E"] = true
	var hostile := Aircraft.new()
	hostile.team = CombatUnit.TEAM_HOSTILE
	mission._spawned_zones[&"E"] = [hostile]
	var spawner := SurvivorSpawner.new()
	spawner.mode = mode
	spawner.player_aircraft = player
	spawner.zone_mission = mission
	var previous_director := EncounterDirector._active
	var director := EncounterDirector.new(spawner)
	_check("远方已触发任务允许旅途增援", not mission.mission_reserves_reinforcements())
	_check("正式导演最终准入也允许远方任务空档补队", director.global_admission(1.0, 1).get("admitted", false))
	hostile.position = player.position + Vector2(6000.0, 0.0)
	hostile.speed = 300.0
	hostile.heading = -PI * 0.5
	_check("18 秒内迎头进入接敌圈的任务队提前占位", mission.mission_reserves_reinforcements())
	_check("正式导演在预计接敌前同步预留", director.global_admission(1.0, 1).get("reason", "") == "mission_reserved")
	hostile.set_meta("zone_ingress", true)
	_check("未接敌的任务在途机计为半份预计压力", director._derive_state(hostile, 0.0) == EncounterDirector.PressureState.APPROACHING)
	hostile.heading = PI * 0.5
	_check("相同距离但向外飞行时允许派队", not mission.mission_reserves_reinforcements())
	hostile.position = player.position
	_check("任务敌军抵近才预留交战空间", mission.mission_reserves_reinforcements())
	hostile.free()
	_check("已释放的目标不占增援名额", not mission.mission_reserves_reinforcements())
	zones.set_mission_type(&"E", "bomber_escort")
	_check("专属护送仍保留自己的追兵节奏", mission.mission_reserves_reinforcements())
	mission.reset_zone(&"E")
	_check("重开战区丢弃上一轮航路", mission._flight_plans.is_empty())
	director.shutdown()
	EncounterDirector._active = previous_director
	spawner.free()
	mission.free()
	player.free()
	mode.free()

func _test_road_index_equivalence() -> void:
	var mission := ZoneMission.new()
	var points := PackedVector2Array([Vector2(-1200.0, -512.0), Vector2(1200.0, 512.0), Vector2(1200.0, 512.0), Vector2(-900.0, 1300.0)])
	mission._index_spawn_road_path(points)
	mission._spawn_road_index_ready = true
	var matched := true
	var samples := 0
	for x in range(-1600, 1601, 80):
		for y in range(-1600, 1601, 80):
			var p := Vector2(x, y)
			var expected := true
			for i in range(points.size() - 1):
				if mission._point_segment_distance(p, points[i], points[i + 1]) < ZoneMission.MIN_ROAD_DISTANCE_PX:
					expected = false
			matched = matched and mission._far_from_roads(p) == expected
			samples += 1
	_check("道路网格与原精确距离逐点一致（负坐标、长线、零长线，%d 点）" % samples, matched)
	mission.free()

func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
