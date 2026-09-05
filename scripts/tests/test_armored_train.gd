extends RefCounted

## 沙漠关底聚焦契约：真实铁路中心线、十四节超长编组、尾段递进破坏、功能退场、
## 断节加速、电磁炮 AOE 与逃脱终态。

const TrainUnitScript = preload("res://scripts/survivor/armored_train_unit.gd")
const TrainBossScript = preload("res://scripts/survivor/armored_train_boss.gd")

var _pass := 0
var _fail := 0


class FailedEncounter:
	extends BossEncounter
	func has_failed() -> bool:
		return true
	func failure_reason() -> String:
		return "armored_train_escaped"


class ModeProbe:
	extends Node
	var _zone_data = null
	var failure_calls := 0
	var last_reason := ""
	func on_boss_failure(_event, reason: String) -> void:
		failure_calls += 1
		last_reason = reason
	func on_boss_event_finished(_event) -> void:
		pass


class DirectorProbe:
	extends RefCounted
	var mode: Node
	var player = null


func run() -> void:
	print("\n════════ 沙漠装甲列车测试 ════════")
	_test_registry_contract()
	_test_map_railway_contract()
	_test_route_progression()
	_test_articulated_train_contract()
	_test_arrival_ingress_contract()
	_test_tail_first_damage_and_speed()
	_test_segment_function_loss()
	_test_railgun_aoe_contract()
	_test_railgun_broadside_lock_then_charge()
	_test_escape_terminal()
	_test_event_failure_priority()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_registry_contract() -> void:
	var desert_pool: Array = BossRegistry.MAP_POOLS.get("desert_railway_preview", [])
	_check("沙漠池包含装甲列车", "ARMORED_TRAIN" in desert_pool)
	var encounter := BossRegistry.instantiate("ARMORED_TRAIN")
	_check("Registry 可实例化列车 encounter", encounter != null
		and encounter.get_script() == TrainBossScript)
	_check("默认 encounter 不误报失败", encounter != null and not encounter.has_failed())


func _test_map_railway_contract() -> void:
	var doc := MapDocument.load_from("res://resources/maps/desert_railway_preview.aglmap")
	var route: PackedVector2Array = TrainBossScript.train_route()
	var railway: Dictionary = doc.railways[0] if doc != null and not doc.railways.is_empty() else {}
	_check("列车路线读取地图 railway SSOT", doc != null and doc.railways.size() == 1
		and route.size() == railway.get("points", []).size())
	_check("铁路声明来自正式底图醒目双线走廊而非抽象对角线",
		str(railway.get("source", "")) == "desert_basemap_primary_rail_corridor"
		and float(railway.get("strategic_lod_max_error_px", INF)) <= 3.0)
	_check("路线贴合横贯战区的可见主铁路并在 Newman 前收束", route.size() == 22
		and route[0].x < -19000.0 and route[-1].is_equal_approx(Vector2(7576.0, 1803.0))
		and route[-1].y - route[0].y > 11000.0,
		"start=%s end=%s" % [route[0] if not route.is_empty() else Vector2.ZERO,
			route[-1] if not route.is_empty() else Vector2.ZERO])


func _test_route_progression() -> void:
	var train = TrainUnitScript.new()
	train.configure_route(PackedVector2Array([Vector2.ZERO, Vector2(100.0, 0.0)]))
	train._update_movement(0.6)
	_check("首段 420km/h 按 0.5px/m 匀速", is_equal_approx(train.global_position.x, 35.0),
		"x=%.2f" % train.global_position.x)
	var expected_progress: float = 35.0 / train._current_travel_limit_px()
	_check("逃脱进度包含当前车尾完整驶离距离",
		is_equal_approx(train.route_progress, expected_progress),
		"progress=%.3f" % train.route_progress)
	train.free()


func _test_articulated_train_contract() -> void:
	var train = TrainUnitScript.new()
	var route: PackedVector2Array = TrainBossScript.train_route()
	train.configure_route(route)
	train._update_movement(60.0)
	var max_bogie_error := 0.0
	for p in train._module_bogie_world_positions:
		max_bogie_error = maxf(max_bogie_error, _distance_to_polyline(p, route))
	var heading_span := 0.0
	for h in train._module_world_headings:
		heading_span = maxf(heading_span,
			absf(angle_difference(float(train._module_world_headings[0]), float(h))))
	_check("固定十四节且每节长度为旧版两倍", TrainUnitScript.SEGMENT_COUNT == 14
		and is_equal_approx(TrainUnitScript.SEGMENT_LENGTH_PX, 236.0)
		and is_equal_approx(TrainUnitScript.SEGMENT_WIDTH_PX, 84.0)
		and TrainUnitScript.SEGMENT_LENGTH_PX >= TrainUnitScript.SEGMENT_WIDTH_PX * 2.75
		and is_equal_approx(TrainUnitScript.TOTAL_LENGTH_PX, 3538.0)
		and TrainUnitScript.COUPLER_GAP_PX >= 16.0)
	_check("每节前后转向架双点严格贴轨", max_bogie_error <= 0.01,
		"max_bogie_error=%.3f" % max_bogie_error)
	_check("活动车钩允许各节在弯道独立改变航向", heading_span > deg_to_rad(0.2),
		"span_deg=%.2f" % rad_to_deg(heading_span))
	train.free()


func _test_arrival_ingress_contract() -> void:
	var world := Node2D.new()
	var train = TrainUnitScript.new()
	world.add_child(train)
	train.configure_route(TrainBossScript.train_route())
	train.arm_segments(world, null, null)
	train.begin_arrival_ingress()
	var start_distance: float = train._traveled_px
	var tail := train.segment_at(TrainUnitScript.REAR_GUARD_INDEX)
	_check("进场态在硬暂停下保持编组控制器运行且十四节不可交战",
		train.arrival_ingress_active
		and train.process_mode == Node.PROCESS_MODE_ALWAYS
		and train.is_arrival_fully_inside()
		and tail != null and tail.is_lock_immune() and not tail.damageable)
	train._update_movement(TrainUnitScript.ARRIVAL_DURATION_S * 0.5)
	_check("进场沿铁路前进并由 330km/h 轻度加速",
		train._traveled_px > start_distance
		and train.arrival_speed_kmh() > TrainUnitScript.ARRIVAL_START_SPEED_KMH
		and train.arrival_speed_kmh() < TrainUnitScript.ARRIVAL_END_SPEED_KMH)
	train._update_railgun(10.0)
	_check("PRE_STAGE 进场不允许电磁炮提前锁定或蓄力",
		train._railgun_state == TrainUnitScript.RailgunState.IDLE
		and train._railgun_target_id == 0)
	train.finish_arrival_ingress()
	var targetable_count := 0
	var damageable_count := 0
	for index in range(TrainUnitScript.SEGMENT_COUNT):
		var segment := train.segment_at(index)
		if segment != null and not segment.is_lock_immune() and segment.is_mission_target:
			targetable_count += 1
		if segment != null and bool(segment.get("damageable")):
			damageable_count += 1
	_check("演出结束整列已入图并恢复尾段接战权限",
		not train.arrival_ingress_active and train.is_arrival_fully_inside()
		and train.process_mode == Node.PROCESS_MODE_INHERIT
		and tail.damageable and not tail.is_lock_immune()
		and targetable_count == TrainUnitScript.SEGMENT_COUNT
		and damageable_count == 1
		and is_equal_approx(train.current_speed_kmh(),
			TrainUnitScript.ARRIVAL_END_SPEED_KMH))
	world.free()


func _test_tail_first_damage_and_speed() -> void:
	var world := Node2D.new()
	var train = TrainUnitScript.new()
	world.add_child(train)
	train.configure_route(PackedVector2Array([Vector2.ZERO, Vector2(5000.0, 0.0)]))
	train.arm_segments(world, null, null)
	var locomotive := train.segment_at(0)
	var tail := train.segment_at(TrainUnitScript.REAR_GUARD_INDEX)
	var locomotive_hp: float = locomotive.hp
	locomotive.take_damage(999.0, null, "gun")
	_check("全车可锁定，但非尾段伤害入口 fail-closed",
		is_equal_approx(locomotive.hp, locomotive_hp)
		and not locomotive.is_lock_immune() and locomotive.is_mission_target
		and not locomotive.can_accept_new_hit("gun"))
	tail.take_missile_damage(100.0)
	_check("暴露尾段按实际导弹伤害结算", is_equal_approx(tail.hp, 40.0))
	tail.take_damage(40.0, null, "gun")
	var next := train.segment_at(TrainUnitScript.TAIL_BATTERY_INDEX)
	var detached_position: Vector2 = tail.global_position
	tail._physics_process(0.1)
	_check("尾段打断后脱离，紧邻前段转为新弱点", tail.is_destroyed
		and tail.detached and tail.global_position.distance_to(detached_position) > 0.1
		and train.active_tail_index() == TrainUnitScript.TAIL_BATTERY_INDEX
		and next.damageable and not locomotive.damageable
		and not locomotive.is_lock_immune())
	_check("每打断一段剩余整车加速 60km/h",
		is_equal_approx(train.current_speed_kmh(), 480.0))
	world.free()


func _test_segment_function_loss() -> void:
	var world := Node2D.new()
	var train = TrainUnitScript.new()
	world.add_child(train)
	train.configure_route(PackedVector2Array([Vector2.ZERO, Vector2(5000.0, 0.0)]))
	train.arm_segments(world, null, null)
	var hp_sum := 0.0
	for value in TrainUnitScript.SEGMENT_HP:
		hp_sum += value
	_check("十四节主题与总 HP 契约完整", TrainUnitScript.SEGMENT_NAMES.size() == 14
		and is_equal_approx(hp_sum, TrainUnitScript.TOTAL_MAX_HP))
	for index in range(TrainUnitScript.REAR_GUARD_INDEX, 0, -1):
		var segment := train.segment_at(index)
		segment.take_damage(segment.hp, null, "gun")
	_check("电磁炮段打断后 AOE 功能立即失效",
		not train.segment_function_active(TrainUnitScript.RAILGUN_INDEX)
		and train._railgun_state == TrainUnitScript.RailgunState.IDLE)
	_check("仅剩车头时达到十三次加速上限", train.active_tail_index() == 0
		and is_equal_approx(train.current_speed_kmh(), TrainUnitScript.MAX_SPEED_KMH))
	var head := train.segment_at(0)
	head.take_damage(head.hp, null, "gun")
	_check("最后车头打断才触发整列击毁", train.is_destroyed)
	world.free()


func _test_railgun_aoe_contract() -> void:
	_check("列车电磁炮复用海岸巨炮 180px AOE/45伤害契约",
		is_equal_approx(TrainUnitScript.RAILGUN_AOE_RADIUS_PX,
			Tier3SuperCannonPart.AOE_RADIUS_PX)
		and is_equal_approx(TrainUnitScript.RAILGUN_AOE_DAMAGE,
			Tier3SuperCannonPart.AOE_DAMAGE)
		and is_equal_approx(TrainUnitScript.RAILGUN_WARNING_S,
			Tier3SuperCannonPart.WARNING_S))
	var train = TrainUnitScript.new()
	var inside := Aircraft.new()
	var outside := Aircraft.new()
	inside.team = CombatUnit.TEAM_PLAYER
	outside.team = CombatUnit.TEAM_PLAYER
	inside.hp = 100.0
	outside.hp = 100.0
	inside.global_position = Vector2(500.0, 80.0)
	outside.global_position = Vector2(500.0, 100.0)
	var saved_units := CombatUnit.all_units
	CombatUnit.all_units = [inside, outside]
	train._railgun_shot_start = Vector2.ZERO
	train._railgun_shot_end = Vector2(1000.0, 0.0)
	train._fire_railgun_snapshot()
	_check("电磁炮预警线结束后只对带内目标同拍 AOE",
		is_equal_approx(inside.hp, 55.0) and is_equal_approx(outside.hp, 100.0))
	CombatUnit.all_units = saved_units
	inside.free()
	outside.free()
	train.free()


func _test_railgun_broadside_lock_then_charge() -> void:
	var world := Node2D.new()
	var train = TrainUnitScript.new()
	world.add_child(train)
	train.configure_route(PackedVector2Array([Vector2.ZERO, Vector2(0.0, -10000.0)]))
	train.arm_segments(world, null, null)
	var origin: Vector2 = train._railgun_world_position()
	_check("电磁炮左右侧舷均可锁定，车头车尾保持射界禁区",
		train.railgun_side_for_position(origin + Vector2(4000.0, 0.0)) == 1
		and train.railgun_side_for_position(origin + Vector2(-4000.0, 0.0)) == -1
		and train.railgun_side_for_position(origin + Vector2(0.0, -4000.0)) == 0
		and train.railgun_side_for_position(origin + Vector2(0.0, 4000.0)) == 0)
	var target := Aircraft.new()
	target.team = CombatUnit.TEAM_PLAYER
	target.callsign = "BROADSIDE-PROBE"
	target.global_position = origin + Vector2(3000.0, 0.0)
	var saved_units := CombatUnit.all_units
	CombatUnit.all_units = [target]
	train._railgun_cooldown_s = 0.0
	train._railgun_heading = PI * 0.5
	train._update_railgun(0.01)
	_check("侧舷目标对准后先进入锁定而非直接蓄力",
		train._railgun_state == TrainUnitScript.RailgunState.LOCKING
		and is_equal_approx(train._railgun_lock_s, TrainUnitScript.RAILGUN_LOCK_S))
	train._update_railgun(0.5)
	_check("锁定时间未满时不生成危险带",
		train._railgun_state == TrainUnitScript.RailgunState.LOCKING
		and train._railgun_shot_start == Vector2.ZERO)
	train._update_railgun(0.51)
	_check("锁定完成后才锁存侧舷射线并开始蓄力",
		train._railgun_state == TrainUnitScript.RailgunState.CHARGING
		and train._railgun_shot_start.x > origin.x
		and is_equal_approx(train._railgun_warning_s, TrainUnitScript.RAILGUN_WARNING_S))
	CombatUnit.all_units = saved_units
	target.free()
	world.free()


func _test_escape_terminal() -> void:
	var train = TrainUnitScript.new()
	var fired := [false]
	train.route_finished.connect(func() -> void: fired[0] = true)
	train.configure_route(PackedVector2Array([Vector2.ZERO, Vector2(10.0, 0.0)]))
	var escape_s := train._current_travel_limit_px() \
		/ (TrainUnitScript.BASE_SPEED_KMH / 3.6 * GameConstants.PIXELS_PER_METER) + 1.0
	train._update_movement(escape_s)
	_check("当前车尾完整驶离后才进入逃脱态", train.escaped and fired[0] and not train.is_destroyed)
	var escaped_pos: Vector2 = train.global_position
	train._update_movement(1.0)
	_check("逃脱终态保持且不回头", train.global_position == escaped_pos)
	train.free()


func _test_event_failure_priority() -> void:
	var mode := ModeProbe.new()
	var director := DirectorProbe.new()
	director.mode = mode
	var event := BossEncounterEvent.new(Vector2.ZERO, 0.0, "desert_railway_preview")
	event.director = director
	event.encounter = FailedEncounter.new()
	event.encounter.active = false
	event.active = true
	event._was_active = true
	event.phase = BossEncounterEvent.Phase.ENGAGED
	event._update(0.016)
	_check("逃脱失败先于 active 下降胜利沿", mode.failure_calls == 1
		and mode.last_reason == "armored_train_escaped" and not event.active)
	mode.free()


func _distance_to_polyline(point: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in range(maxi(line.size() - 1, 0)):
		var closest := Geometry2D.get_closest_point_to_segment(point, line[i], line[i + 1])
		best = minf(best, point.distance_to(closest))
	return best


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])
