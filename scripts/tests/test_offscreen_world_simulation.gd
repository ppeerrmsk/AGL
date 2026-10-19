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
