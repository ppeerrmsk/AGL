extends RefCounted

const UNIT_SCRIPT := preload("res://scripts/survivor/land_carrier_unit.gd")
const BOSS_SCRIPT := preload("res://scripts/survivor/land_carrier_boss.gd")
const FA18_PARAMS: AircraftParams = preload("res://resources/enemy_fa18.tres")
const BASE_PARAMS: AircraftParams = preload("res://resources/aa_gun_params.tres")

var _pass := 0
var _fail := 0


class FakeRoot:
	extends Node
	var _spawner: Node
	var spawned: Array[Aircraft] = []

	func _init() -> void:
		_spawner = self

	func _create_enemy(_etype: int, pos: Vector2, heading_deg: float) -> Aircraft:
		var ac := Aircraft.new()
		ac.params = FA18_PARAMS.duplicate(true)
		ac.initial_heading_deg = heading_deg
		add_child(ac)
		ac.global_position = pos
		spawned.append(ac)
		return ac


func run() -> void:
	print("\n════════ 陆地航母测试 ════════")
	_test_identity_contract()
	_test_hull_and_damage_contract()
	_test_real_deck_aircraft_contract()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_identity_contract() -> void:
	var train := BossRegistry.instantiate("ARMORED_TRAIN")
	var carrier := BossRegistry.instantiate("LAND_CARRIER")
	_check("列车与陆地航母是两个独立 Boss id", train != null and carrier != null
		and train.get_script() != carrier.get_script())
	_check("LAND_CARRIER 使用独立 encounter", carrier != null
		and carrier.get_script() == BOSS_SCRIPT)
	_check("航空队节拍为 4 驻机、首波 2、120s 补充、总上限 8",
		BOSS_SCRIPT.INITIAL_PARKED == 4 and BOSS_SCRIPT.INITIAL_LAUNCH == 2
		and BOSS_SCRIPT.PERIODIC_LAUNCH_S == 120.0
		and BOSS_SCRIPT.TOTAL_AIRWING_CAP == 8)
	_check("沙漠列车与 The Crucible 池未被陆地航母替换",
		BossRegistry.MAP_POOLS.get("desert_railway_preview", []) \
		== ["ARMORED_TRAIN", "THE_CRUCIBLE"])


func _test_hull_and_damage_contract() -> void:
	var unit = UNIT_SCRIPT.new()
	unit.params = BASE_PARAMS.duplicate(true)
	unit.params.max_hp = 1800.0
	unit.hp = 1800.0
	_check("连续舰体是宽厚 620x280 而非十五节列车", UNIT_SCRIPT.HULL_LENGTH_PX == 620.0
		and UNIT_SCRIPT.HULL_WIDTH_PX == 280.0 and not ("route" in unit))
	unit.configure_patrol(Vector2(19000.0, 14500.0))
	var spawn_pos: Vector2 = unit.global_position
	var first_waypoint: Vector2 = unit.waypoints[0]
	_check("边界外锚点会把陆地航母钳入可接近区域",
		MapBoundary.is_safe_inside(spawn_pos, UNIT_SCRIPT.SPAWN_EDGE_MARGIN_PX), str(spawn_pos))
	var spawn_forward := Vector2(sin(unit.heading), -cos(unit.heading))
	var first_leg_direction := spawn_pos.direction_to(first_waypoint)
	_check("开局首段向地图中心推进 1400px",
		is_equal_approx(spawn_pos.distance_to(first_waypoint), UNIT_SCRIPT.INITIAL_INGRESS_PX)
		and first_waypoint.length() < spawn_pos.length()
		and spawn_forward.dot(first_leg_direction) >= 0.999,
		"spawn=%s first=%s" % [spawn_pos, first_waypoint])
	_check("甲板定义四个真实停机位", UNIT_SCRIPT.PARK_OFFSETS.size() == 4)
	unit.take_missile_damage(100.0)
	_check("装甲舰体按实际导弹伤害扣血", is_equal_approx(unit.hp, 1700.0),
		"hp=%.1f" % unit.hp)
	unit.free()


func _test_real_deck_aircraft_contract() -> void:
	var root := FakeRoot.new()
	var unit = UNIT_SCRIPT.new()
	unit.params = BASE_PARAMS.duplicate(true)
	unit.params.max_hp = 1800.0
	unit.team = CombatUnit.TEAM_HOSTILE
	unit.configure_patrol(Vector2(2000.0, 1500.0))
	root.add_child(unit)
	var parked: int = unit.spawn_parked_aircraft(root, 4)
	_check("甲板生成四架真实 Aircraft", parked == 4 and unit.parked_aircraft_count() == 4
		and root.spawned.size() == 4)
	var all_frozen := true
	var all_parented := true
	for ac in root.spawned:
		all_frozen = all_frozen and ac.process_mode == Node.PROCESS_MODE_DISABLED
		all_parented = all_parented and ac.get_meta(&"parent_carrier", null) == unit
	_check("驻机冻结并登记母舰", all_frozen and all_parented)
	unit.global_position += Vector2(300.0, -120.0)
	unit.heading = deg_to_rad(35.0)
	unit.rotation = unit.heading
	unit._physics_process(0.0)
	var max_deck_error := 0.0
	for ac in root.spawned:
		var offset: Vector2 = ac.get_meta(&"park_offset", Vector2.ZERO)
		max_deck_error = maxf(max_deck_error,
			ac.global_position.distance_to(unit._local_to_world(offset)))
	_check("航母移动转向时驻机锁在甲板", max_deck_error <= 0.01,
		"max_error=%.3f" % max_deck_error)
	var launched: Array = unit.launch_parked_aircraft(2)
	var launch_ok: bool = launched.size() == 2 and unit.parked_aircraft_count() == 2
	for ac in launched:
		launch_ok = launch_ok and ac.process_mode == Node.PROCESS_MODE_INHERIT \
			and not ac.has_meta(&"parent_carrier") and ac.altitude == 100.0
	_check("接战首波两架从甲板解除停机起飞", launch_ok)
	unit.arm_mounts(root, null, null)
	_check("陆地航母拥有八个真实防空挂点", unit._mounts.size() == 8)
	unit._start_destroy()
	_check("主体摧毁立即清空甲板驻机与挂点缓存",
		unit._parked_aircraft.is_empty() and unit._mounts.is_empty())
	root.free()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])
