extends Node

## 跨帧终态回归门：必须让真实节点进入 SceneTree、queue_free、再越过后续帧与缓存 tick。
## 单纯验证公式/状态字段不能替代这里的对象生命周期顺序。

const STRATEGIC_TARGET_SCENE := preload("res://scenes/strategic_target.tscn")
const SUPER_CANNON_SCRIPT := preload("res://scripts/survivor/tier3_super_cannon_part.gd")
const ARMORED_TRAIN_SCRIPT := preload("res://scripts/survivor/armored_train_unit.gd")

class FakeAceMusicMode:
	extends Node
	var begin_calls := 0
	var end_calls := 0

	func begin_ace_battle_music() -> bool:
		begin_calls += 1
		return true

	func end_ace_battle_music() -> void:
		end_calls += 1

class FakeAceMusicDirector:
	extends RefCounted
	var mode: Variant = null
	var player: Variant = null

class FakeExplosionHost:
	extends Node
	var flashes: Array[Dictionary] = []
	var airframe_waves: Array[Dictionary] = []

	func spawn_flash(pos: Vector2, heading: float = 0.0, scale: float = 1.0) -> void:
		flashes.append({"pos": pos, "heading": heading, "scale": scale})

	func spawn_airframe_wave(pos: Vector2, heading: float,
			half_length_px: float, half_span_px: float, scale: float = 1.0,
			route: int = -1, initial_delay: float = 0.0) -> void:
		airframe_waves.append({
			"pos": pos,
			"heading": heading,
			"half_length_px": half_length_px,
			"half_span_px": half_span_px,
			"scale": scale,
			"route": route,
			"initial_delay": initial_delay,
		})

class FakeZoneVisibilityMode:
	extends Node2D
	var everything_visible := true

	func is_world_pos_visible(_pos: Vector2, _extra_radius: float = 0.0) -> bool:
		return everything_visible

var _pass: int = 0
var _fail: int = 0
var _explosion_host: FakeExplosionHost

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	_fail += await preload("res://scripts/tests/dock_decision_case.gd").new().run(self)
	_fail += await preload("res://scripts/tests/tactical_canvas_case.gd").run(self)
	_fail += await preload("res://scripts/tests/unit_status_case.gd").new().run(self)
	_fail += await preload("res://scripts/tests/squad_ownership_case.gd").run(self)
	_explosion_host = FakeExplosionHost.new()
	_explosion_host.add_to_group("explosion_vfx")
	add_child(_explosion_host)
	_fail += await preload("res://scripts/tests/visual_redraw_queue_case.gd").run(self)
	_fail += await preload("res://scripts/tests/tokyo_map_planning_case.gd").run(self)
	await _test_bomber_cache_after_target_free()
	_fail += await preload("res://scripts/tests/orion_lifecycle_case.gd").new().run(self)
	_fail += await preload("res://scripts/tests/fear_cone_case.gd").new().run(self)
	_fail += await preload("res://scripts/tests/debug_spawn_lifecycle_case.gd").run(self)
	_fail += await preload("res://scripts/tests/invasion_algorithm_case.gd").run(self)
	var bloodlust_case: RefCounted = load("res://scripts/tests/bloodlust_head_on_case.gd").new()
	_fail += await bloodlust_case.run(self)
	var gun_case: RefCounted = load("res://scripts/tests/gun_evasion_lifecycle_case.gd").new()
	_fail += await gun_case.run(self)
	await _test_bomber_cache_after_controller_free()
	await _test_bomber_retire_with_freed_members()
	await _test_bomber_priority_after_player_death()
	await _test_zone_completion_after_deferred_free()
	await _test_conquered_garrison_retire_after_offscreen_grace()
	await _test_retired_ground_after_real_damage()
	await _test_zone_failure_after_deferred_free()
	await _test_super_cannon_destroy_after_deferred_free()
	await _test_armored_train_segment_break_after_deferred_free()
	await _test_ace_music_cleanup_after_deferred_free()
	await _test_sensor_release_with_freed_target_caches()
	await _test_all_damage_kinds_enter_aircraft_crash()
	await _test_unified_aircraft_breakup()
	await _test_hit_location_crash_response()
	await _test_large_aircraft_structural_breakup()
	var volume_case: RefCounted = load("res://scripts/tests/volume_world_lifecycle_case.gd").new()
	_fail += await volume_case.run(self)
	var desert_preload_case: RefCounted = load("res://scripts/tests/desert_preload_lifecycle_case.gd").new()
	_fail += await desert_preload_case.run(self)
	var tokyo_case: RefCounted = load("res://scripts/tests/tokyo_volume_lifecycle_case.gd").new()
	var ocean_case: RefCounted = load("res://scripts/tests/ocean_volume_lifecycle_case.gd").new()
	_fail += await ocean_case.run(self)
	_fail += await tokyo_case.run(self)
	var tokyo_cells_case: RefCounted = load("res://scripts/tests/tokyo_cells_lifecycle_case.gd").new()
	_fail += await tokyo_cells_case.run(self)
	_fail += await preload("res://scripts/tests/test_tokyo_tile_ground.gd").lifecycle(self)
	_fail += await preload("res://scripts/tests/test_tokyo_low_walls.gd").lifecycle(self)
	_fail += await preload("res://scripts/tests/raster_capacity_lifecycle_case.gd").run(self)
	var war_case = load("res://scripts/tests/full_war_runner.gd").new()
	war_case.auto_run = false
	add_child(war_case)
	_fail += await war_case.run_checks()
	war_case.queue_free()
	await get_tree().process_frame
	# 退出音频门必须最后运行；终态后拒绝新播放，不能恢复为可游玩状态。
	_fail += await preload("res://scripts/tests/audio_shutdown_case.gd").run(self)
	print("[LifecycleGauntlet] result pass=%d fail=%d" % [_pass, _fail])
	AudioManager.request_quit(0 if _fail == 0 else 1)

func _new_zone_mission() -> ZoneMission:
	var mission := ZoneMission.new()
	mission.name = "LifecycleZoneMission"
	mission.set_physics_process(false)
	add_child(mission)
	var zones := ZoneData.new(Callable(), false, true)
	for zone_any in ZoneData.ZONES:
		var zone: Dictionary = zone_any
		var zone_id := StringName(zone["id"])
		zones.set_state(zone_id, ZoneData.State.LOCKED)
		# 本 gauntlet 只验终态生命周期；预登记空生成快照，避免完成判定顺带启动
		# 依赖 SurvivorMode owner 的下一战区生成。正式生成链由各专项覆盖。
		mission._spawned_zones[zone_id] = []
	for airfield_id in ZoneData.AIRFIELD_IDS:
		zones.set_state(airfield_id, ZoneData.State.LOCKED)
	zones.set_state(&"A", ZoneData.State.AVAILABLE)
	mission._zones = zones
	return mission

func _new_target() -> StrategicTarget:
	var target := STRATEGIC_TARGET_SCENE.instantiate() as StrategicTarget
	target.team = CombatUnit.TEAM_HOSTILE
	add_child(target)
	return target

func _new_controller() -> BomberMission:
	var controller := BomberMission.new()
	controller.set_physics_process(false)
	add_child(controller)
	return controller

func _freed(value: Node) -> Variant:
	var retained: Variant = value
	value.queue_free()
	await get_tree().process_frame
	_check(not is_instance_valid(retained), "queue_free 已越过帧并释放对象")
	return retained

func _destroyed_target_value() -> Variant:
	var target := _new_target()
	target.take_bomber_damage(9999.0, CombatUnit.TEAM_PLAYER, null)
	_check(target.is_destroyed, "战略目标经正式轰炸伤害入口进入 destroyed 终态")
	return await _freed(target)

func _base_run(target_value: Variant, controller_value: Variant) -> Dictionary:
	return {
		"target": target_value,
		"controller": controller_value,
		"interceptors": [],
		"route_progress": 0.0,
		"player_intervened": false,
	}

func _test_bomber_cache_after_target_free() -> void:
	var mission := _new_zone_mission()
	var target_value: Variant = await _destroyed_target_value()
	var controller := _new_controller()
	mission._bomber_escort_runs[&"A"] = _base_run(target_value, controller)
	mission._update_bomber_escort_caches(ZoneMission.BOMBER_ESCORT_CACHE_TICK_S)
	var status := mission._zones.get_mission_status(&"A")
	_check(status.get("target_hp", -1.0) == 0.0,
		"目标释放后缓存 tick 仍能生成安全状态快照")
	mission._retire_bomber_run(&"A")
	mission.free()

func _test_bomber_cache_after_controller_free() -> void:
	var mission := _new_zone_mission()
	var target := _new_target()
	var controller_value: Variant = await _freed(_new_controller())
	mission._bomber_escort_runs[&"A"] = _base_run(target, controller_value)
	mission._update_bomber_escort_caches(ZoneMission.BOMBER_ESCORT_CACHE_TICK_S)
	var status := mission._zones.get_mission_status(&"A")
	_check(String(status.get("phase", "")) == "standby",
		"控制器释放后缓存 tick 降级为 standby 而不触发强类型错误")
	mission._retire_bomber_run(&"A")
	target.free()
	mission.free()

func _test_bomber_retire_with_freed_members() -> void:
	var mission := _new_zone_mission()
	var target_value: Variant = await _destroyed_target_value()
	var controller_value: Variant = await _freed(_new_controller())
	var interceptor := Aircraft.new()
	var interceptor_value: Variant = interceptor
	interceptor.free()
	var run := _base_run(target_value, controller_value)
	run["interceptors"] = [interceptor_value]
	mission._bomber_escort_runs[&"A"] = run
	mission._retire_bomber_run(&"A")
	_check(not mission._bomber_escort_runs.has(&"A"),
		"成功/失败/取消共用退役入口能清理全部已释放成员")
	mission.free()

func _test_bomber_priority_after_player_death() -> void:
	# 发射仍经过正式攻击名额门，但不继承前序场景尚未到期的攻击租约。
	var previous_director := EncounterDirector._active
	var director := EncounterDirector.new(null)
	var mission := _new_zone_mission()
	var spawner := SurvivorSpawner.new()
	var controller := _new_controller()
	var bomber := _new_aircraft_for_destruction()
	var backup := _new_aircraft_for_destruction()
	bomber.params = load("res://resources/friendly_b1b.tres").duplicate(true)
	backup.params = bomber.params.duplicate(true)
	bomber.team = CombatUnit.TEAM_ALLY
	backup.team = CombatUnit.TEAM_ALLY
	bomber.position = Vector2(0, -1000)
	backup.position = Vector2(300, -1000)
	var player := _new_aircraft_for_destruction()
	player.team = CombatUnit.TEAM_PLAYER
	player.position = Vector2(0, -1200)
	var shooter := _new_aircraft_for_destruction()
	shooter.team = CombatUnit.TEAM_HOSTILE
	shooter.params = load("res://resources/enemy_mirage3.tres").duplicate(true)
	shooter.params.missile = load("res://resources/weapons/enemy_missile_v4.tres")
	shooter.missiles_remaining = 4
	shooter.weapon_mode = Aircraft.WeaponMode.MISSILE
	shooter.position = Vector2.ZERO
	shooter.heading = 0.0
	shooter.bank_angle = 0.0
	var ai := AIController.new()
	ai.set_physics_process(false)
	shooter.add_child(ai)
	ai.aircraft = shooter
	shooter._ai_ref = ai
	var manager := MissileManager.new()
	manager.set_physics_process(false)
	add_child(manager)
	shooter.missile_manager = manager
	var route := PackedVector2Array([bomber.position, Vector2(0, -5000), Vector2(0, -6000)])
	controller.setup([bomber, backup], [route, route], route[2], null)
	# 保持三机同高，真实武器检查使用正常包线／锁定／稳定窗口。
	player.altitude = bomber.altitude
	backup.altitude = bomber.altitude
	shooter.altitude = bomber.altitude
	mission._spawner = spawner
	mission._player = player
	var run := {"interceptors": [shooter]}
	spawner.assign_bomber_intercept_target(shooter, bomber)
	shooter.radar_targets[bomber] = 10.0
	mission._retarget_bomber_interceptors(run, controller)
	shooter.radar_targets[player] = 10.0
	AircraftWeapons.update_missile(shooter, 0.1)
	_check(manager.count_active_missiles_at(shooter, player) == 1
			and manager.count_active_missiles_at(shooter, bomber) == 0,
		"已锁 B-1B 后玩家近场接敌，正式武器入口真实发射导弹到玩家")
	var destroyed_signals: Array = []
	var on_kill := func(_killer: String, _victim: String, _kind: String,
			_killer_team: int, victim_team: int, _voiced: bool) -> void:
		if victim_team == CombatUnit.TEAM_PLAYER:
			destroyed_signals.append(true)
	EventLogger.kill_recorded.connect(on_kill)
	player.take_damage(99999.0, shooter, "gun")
	EventLogger.kill_recorded.disconnect(on_kill)
	_check(player.is_destroyed and destroyed_signals.size() == 1, "玩家真实致命伤害触发一次死亡信号")
	player.queue_free()
	await get_tree().process_frame
	mission._retarget_bomber_interceptors(run, controller)
	await get_tree().physics_frame
	mission._retarget_bomber_interceptors(run, controller)
	_check(shooter.combat_target == bomber and ai._current_target == bomber
			and ai._directive.params.get("target") == bomber,
		"玩家释放并跨下一次缓存刷新后，旧引用清空且重新指向 B-1B")
	bomber.take_damage(99999.0, shooter, "gun")
	bomber.queue_free()
	await get_tree().process_frame
	mission._retarget_bomber_interceptors(run, controller)
	_check(shooter.combat_target == backup and shooter.get_meta("bomber_intercept_target") == backup,
		"B-1B 真实死亡释放后，消费方执行到末尾并改护送目标为幸存机")
	manager.free()
	controller.free()
	mission.free()
	spawner.free()
	shooter.free()
	backup.free()
	director.shutdown()
	EncounterDirector._active = previous_director

func _test_zone_completion_after_deferred_free() -> void:
	var mission := _new_zone_mission()
	var player := Aircraft.new()
	mission._player = player
	var target_value: Variant = await _destroyed_target_value()
	mission._spawned_zones[&"A"] = [target_value]
	mission._triggered_zones[&"A"] = true
	mission._bomber_escort_runs[&"A"] = _base_run(target_value, null)
	var completed: Array[StringName] = []
	mission.mission_completed.connect(func(zone_id: StringName) -> void:
		completed.append(zone_id))
	mission._physics_process(ZoneMission.BOMBER_ESCORT_CACHE_TICK_S)
	_check(completed == [&"A"] and mission._completed_zones.has(&"A"),
		"任务目标释放后的同一缓存 tick 仍继续完成战区结算")
	mission._retire_bomber_run(&"A")
	player.free()
	mission.free()

func _test_conquered_garrison_retire_after_offscreen_grace() -> void:
	var mode := FakeZoneVisibilityMode.new()
	add_child(mode)
	var mission := _new_zone_mission()
	mission.mode = mode
	var player := Aircraft.new()
	mission._player = player
	var target_value: Variant = await _destroyed_target_value()
	mission._spawned_zones[&"A"] = [target_value]
	mission._triggered_zones[&"A"] = true
	var garrison := Aircraft.new()
	var retained: Variant = garrison
	garrison.params = AircraftParams.new()
	var ai := AIController.new()
	ai.aircraft = garrison
	garrison._ai_ref = ai
	garrison.add_child(ai)
	mode.add_child(garrison)
	mission._garrison_zones[&"A"] = [garrison]
	mission._physics_process(ZoneMission.BOMBER_ESCORT_CACHE_TICK_S)
	_check(mission._completed_zones.has(&"A")
		and bool(garrison.get_meta(&"zone_retiring", false))
		and mission._pending_despawn == [garrison],
		"真实完成判定同 tick 把幸存驻守敌机送入撤离队列")
	mode.everything_visible = false
	mission._flush_pending_despawn(30.0)
	await get_tree().process_frame
	_check(is_instance_valid(retained), "镜头离开不能删除尚在图内的撤离机")
	garrison.global_position = Vector2(MapBoundary.world_half_px() + 1000.0, 0.0)
	mission._flush_pending_despawn(ZoneMission.CONQUERED_RETIRE_OFFSCREEN_GRACE_S)
	await get_tree().process_frame
	_check(not is_instance_valid(retained),
		"攻克撤离机持续离屏后 queue_free 已越过真实下一帧")
	mission._physics_process(ZoneMission.RETIRE_VISIBILITY_CHECK_INTERVAL_S)
	_check(mission._pending_despawn.is_empty(),
		"撤离释放后的下一缓存 tick 无待清理引用残留")
	player.free()
	mission.free()
	mode.free()

func _test_retired_ground_after_real_damage() -> void:
	var mission := _new_zone_mission()
	var mode := FakeZoneVisibilityMode.new()
	add_child(mode)
	mission.mode = mode
	var ground := GroundUnit.new()
	ground.params = AircraftParams.new()
	ground.team = CombatUnit.TEAM_HOSTILE
	mode.add_child(ground)
	var retained: Variant = ground
	var original_hp := ground.hp
	mission._spawned_zones[&"A"] = [ground]
	mission._triggered_zones[&"A"] = true
	var failures: Array[String] = []
	mission.mission_failed.connect(func(_zone: StringName, reason: String) -> void: failures.append(reason))
	mission.fail_zone(&"A", "retirement_lifecycle")
	mode.everything_visible = false
	mission._flush_pending_despawn(30.0)
	await get_tree().process_frame
	_check(is_instance_valid(retained) and ground.hp == original_hp
		and ground.process_mode == Node.PROCESS_MODE_DISABLED
		and failures == ["retirement_lifecycle"] and mission._failed_zones.has(&"A")
		and not mission._spawned_zones.has(&"A") and mission._pending_despawn.is_empty()
		and mission._retained_ground == [ground],
		"真实失败信号只解除任务所有权，地面原实体停止主动运算但不会随离屏删除")
	ground.take_damage(99999.0, null, "gun")
	_check(ground.is_destroyed and ground.process_mode == Node.PROCESS_MODE_INHERIT,
		"留场地面目标经真实伤害进入损毁并恢复死亡处理")
	ground._physics_process(2.1)
	await get_tree().process_frame
	mission._flush_pending_despawn(0.2)
	mission._refresh_retained_ground_views()
	_check(not is_instance_valid(retained) and mission._pending_despawn.is_empty() and mission._retained_ground.is_empty(),
		"留场地面目标真实损毁后跨下一帧与回收 tick 无残留")
	mission.free()
	mode.free()

func _test_zone_failure_after_deferred_free() -> void:
	var mission := _new_zone_mission()
	var target_value: Variant = await _destroyed_target_value()
	var controller_value: Variant = await _freed(_new_controller())
	mission._spawned_zones[&"A"] = [target_value]
	mission._triggered_zones[&"A"] = true
	mission._bomber_escort_runs[&"A"] = _base_run(target_value, controller_value)
	var failures: Array[String] = []
	mission.mission_failed.connect(func(zone_id: StringName, reason: String) -> void:
		failures.append("%s:%s" % [zone_id, reason]))
	mission._flight_plans[&"A"] = {"edge": Vector2.ZERO, "start": 0.0}
	mission.fail_zone(&"A", "lifecycle_probe")
	await get_tree().process_frame
	mission._update_bomber_escort_caches(ZoneMission.BOMBER_ESCORT_CACHE_TICK_S)
	_check(not mission._flight_plans.has(&"A"), "失败跨帧及缓存 tick 后清空旧航线")
	mission._flight_plans[&"A"] = {"edge": Vector2.ZERO, "start": 0.0}
	mission.reset_zone(&"A")
	await get_tree().process_frame
	_check(not mission._flight_plans.has(&"A"), "战区重开跨帧后无上一代航线")
	mission._flight_plans[&"A"] = {"edge": Vector2.ZERO, "start": 0.0}
	mission.cancel_all_zone_missions()
	await get_tree().process_frame
	_check(mission._flight_plans.is_empty(), "取消全部任务后跨帧无战略航线残留")
	_check(failures == ["A:lifecycle_probe"] \
			and not mission._bomber_escort_runs.has(&"A"),
		"失败终态能在对象已释放后完整发信号并清空缓存")
	mission.free()

func _test_super_cannon_destroy_after_deferred_free() -> void:
	var mission := _new_zone_mission()
	var cannon = SUPER_CANNON_SCRIPT.new()
	cannon.configure(&"A")
	cannon.team = CombatUnit.TEAM_HOSTILE
	cannon.hp = 100.0
	cannon.set_meta(&"tier3_threat_source", true)
	add_child(cannon)
	mission._spawned_zones[&"A"] = [cannon]
	var edges: Array[bool] = []
	mission.tier3_threat_changed.connect(func(_zone: StringName, _profile: StringName,
			active: bool) -> void: edges.append(active))
	mission._register_tier3_sources(&"A", &"super_cannon")
	cannon.take_damage(9999.0, null, "lifecycle_probe")
	_check(cannon.is_destroyed and not bool(cannon.get("_threat_enabled")),
		"一体化巨炮经正式伤害入口销毁时底座、炮管与在途效果同拍停用")
	var retained: Variant = cannon
	cannon._update_destroy(3.0)
	await get_tree().process_frame
	_check(not is_instance_valid(retained), "一体化巨炮销毁后 queue_free 已越过真实帧")
	mission._update_tier3_source_states(0.25)
	_check(edges == [true, false],
		"巨炮释放后的来源缓存 tick 仍发出 NEUTRALIZED 权威边沿")
	_check(mission._all_zone_units_destroyed(&"A"),
		"单体巨炮释放后不残留底座 TGT，并允许普通战区完成判定继续")
	mission.free()


func _test_armored_train_segment_break_after_deferred_free() -> void:
	var saved_units := CombatUnit.all_units
	var bullet_manager := Node2D.new()
	add_child(bullet_manager)
	var train = ARMORED_TRAIN_SCRIPT.new()
	add_child(train)
	train.configure_route(PackedVector2Array([
		Vector2.ZERO, Vector2(5000.0, 0.0)]))
	train.arm_segments(self, bullet_manager, null)
	await get_tree().process_frame

	var observer := Aircraft.new()
	observer.params = AircraftParams.new()
	observer.team = CombatUnit.TEAM_PLAYER
	observer.set_physics_process(false)
	add_child(observer)
	var tail: GroundUnit = train.segment_at(ARMORED_TRAIN_SCRIPT.REAR_GUARD_INDEX)
	var next: GroundUnit = train.segment_at(ARMORED_TRAIN_SCRIPT.TAIL_BATTERY_INDEX)
	observer.combat_target = tail
	observer.commanded_target = tail
	var tail_value: Variant = tail
	var tail_mount_value: Variant = train._mounts_by_segment[
		ARMORED_TRAIN_SCRIPT.REAR_GUARD_INDEX][0]
	CombatUnit.all_units = [observer, tail, next]

	tail.take_damage(tail.hp, observer, "gun")
	_check(tail.is_destroyed and bool(tail.get("detached"))
		and bool(next.get("damageable"))
		and train.active_tail_index() == ARMORED_TRAIN_SCRIPT.TAIL_BATTERY_INDEX
		and is_equal_approx(train.current_speed_kmh(), 480.0),
		"列车尾段经正式伤害入口打断时同拍脱离、使前段可打断并让整车加速")
	_check(observer.combat_target == null and observer.commanded_target == null,
		"断节同拍释放玩家 combat/commanded 旧目标引用")

	tail._update_destroy(3.0)
	await get_tree().process_frame
	_check(not is_instance_valid(tail_value) and not is_instance_valid(tail_mount_value),
		"断节车体与所属功能挂点 queue_free 均越过真实下一帧")
	CombatUnit.all_units = [observer, next]
	await get_tree().process_frame
	_check(next.can_accept_new_hit("missile") and next.is_mission_target
		and not next.is_lock_immune(),
		"下一次单位缓存刷新后新尾段可打断，已释放旧尾段无残留")

	train.queue_free()
	observer.queue_free()
	bullet_manager.queue_free()
	await get_tree().process_frame
	CombatUnit.all_units = saved_units

func _test_ace_music_cleanup_after_deferred_free() -> void:
	var mode := FakeAceMusicMode.new()
	add_child(mode)
	var director := FakeAceMusicDirector.new()
	director.mode = mode
	var event := AceReinforcementEvent.new()
	event.director = director
	var owner := AceSupportSquad.new("vulture")
	var owner_probe: WeakRef = weakref(owner)
	var tactics := owner._lancer
	var tactics_probe: WeakRef = weakref(tactics)
	event._squad = owner
	owner = null
	event._begin_ace_battle_music()
	_check(event._ace_music_started and mode.begin_calls == 1,
		"王牌血条浮现时只取得一次专属 BGM 所有权")
	event._begin_ace_battle_music()
	_check(mode.begin_calls == 1, "重复交战 tick 不重启专属 BGM")
	event._finish()
	_check(not event._ace_music_started and mode.end_calls == 1,
		"取消/清理终态归还 BGM 且所有权清零")
	event._finish()
	_check(mode.end_calls == 1, "重复终态不会二次抢回普通歌单")
	await get_tree().process_frame
	_check(event._squad == null and owner_probe.get_ref() == null,
		"王牌事件真实终态释放中队，外部战术引用不会反向保活宿主")
	tactics.enter()
	tactics.update(LancerSquadTactics.TICK_S + 0.1)
	tactics.exit()
	_check(tactics._squad == null and tactics._alive_members().is_empty(),
		"宿主释放后跨下一战术 tick，迟到 enter/update/exit 安全完成")
	tactics = null
	await get_tree().process_frame
	_check(tactics_probe.get_ref() == null, "战术最后引用撤销后立即释放，无循环残留")

	var freed_mode: Variant = await _freed(mode)
	director.mode = freed_mode
	var late_event := AceReinforcementEvent.new()
	late_event.director = director
	late_event._ace_music_started = true
	late_event._finish()
	await get_tree().process_frame
	_check(not late_event._ace_music_started,
		"Mode queue_free 后跨下一帧清理仍安全释放王牌 BGM 所有权")


func _test_sensor_release_with_freed_target_caches() -> void:
	var observer := Aircraft.new()
	observer.team = CombatUnit.TEAM_PLAYER
	observer.params = AircraftParams.new()
	observer.set_physics_process(false)
	add_child(observer)
	var ai := AIController.new()
	ai.aircraft = observer
	observer._ai_ref = ai
	observer.add_child(ai)

	var stale_target := Aircraft.new()
	stale_target.team = CombatUnit.TEAM_HOSTILE
	stale_target.params = AircraftParams.new()
	stale_target.set_physics_process(false)
	add_child(stale_target)
	observer.combat_target = stale_target
	observer.commanded_target = stale_target
	ai._current_target = stale_target
	var stale_value: Variant = stale_target
	stale_target.queue_free()
	await get_tree().process_frame
	var stale_combat_value: Variant = observer.combat_target
	var stale_commanded_value: Variant = observer.commanded_target
	var stale_ai_value: Variant = ai._current_target
	_check(not is_instance_valid(stale_value)
		and typeof(stale_combat_value) == TYPE_OBJECT
		and not is_instance_valid(stale_combat_value)
		and typeof(stale_commanded_value) == TYPE_OBJECT
		and not is_instance_valid(stale_commanded_value)
		and typeof(stale_ai_value) == TYPE_OBJECT
		and not is_instance_valid(stale_ai_value),
		"传感器清理前目标已跨帧释放但三个玩家目标缓存仍持有旧引用")

	# 真实漏判顺序：目标 A 已释放后，另一个目标 B 的隐形沿才触发全队批清理。
	var hidden_target := Aircraft.new()
	hidden_target.team = CombatUnit.TEAM_HOSTILE
	hidden_target.params = AircraftParams.new()
	hidden_target.set_physics_process(false)
	add_child(hidden_target)
	var targets: Array[Aircraft] = [hidden_target]
	var units: Array[CombatUnit] = [observer, hidden_target]
	SensorStealthController.release_player_sensor_refs_batch(
		targets, units, true, "lifecycle gauntlet")
	await get_tree().process_frame
	var combat_value: Variant = observer.combat_target
	var commanded_value: Variant = observer.commanded_target
	var ai_value: Variant = ai._current_target
	_check(typeof(combat_value) == TYPE_NIL
		and typeof(commanded_value) == TYPE_NIL
		and typeof(ai_value) == TYPE_NIL,
		"另一目标进入隐形批处理时安全清除 combat/commanded/AI 三类失效缓存")
	observer.free()
	hidden_target.free()


func _new_aircraft_for_destruction() -> Aircraft:
	var ac := Aircraft.new()
	ac.set_physics_process(false)
	add_child(ac)
	ac.altitude = 3200.0
	ac.speed = 230.0
	ac._trail_ribbon.add_point(ac.global_position, ac.heading, ac.bank_angle)
	return ac


func _test_all_damage_kinds_enter_aircraft_crash() -> void:
	for damage_kind in ["missile", "qmaam", "rocket", "aoe", "gun"]:
		var wave_count_before := _explosion_host.airframe_waves.size()
		var flash_count_before := _explosion_host.flashes.size()
		var ac := _new_aircraft_for_destruction()
		ac.set_meta("_last_damage_kind", damage_kind)
		ac._start_destroy()
		_check(ac.is_destroyed and ac.visible
			and ac._destroy_timer >= Aircraft.FIGHTER_CRASH_DURATION * 0.90
			and ac._destroy_timer <= Aircraft.FIGHTER_CRASH_DURATION * 1.12
			and is_equal_approx(ac._destroy_status_timer, Aircraft.DESTROY_STATUS_HOLD_S),
			"%s 致命保留机体与状态栏并进入完整坠毁" % damage_kind)
		_check(is_equal_approx(ac._destroy_visual_scale, 1.0)
			and is_equal_approx(ac._destroy_visual_alpha, 1.0)
			and not ac._trail_ribbon._trail_data.is_empty(),
			"%s 致命不再同帧缩放归零、渐隐或清除尾迹" % damage_kind)
		_check(_explosion_host.airframe_waves.size() == wave_count_before
			and _explosion_host.flashes.size() == flash_count_before,
			"%s 致命不在死亡原位置排入机体殉爆波" % damage_kind)
		ac._destroy_timer = 0.01
		var retained: Variant = ac
		ac._update_destroy(0.02)
		_check(is_instance_valid(retained)
			and is_equal_approx(ac._destroy_linger_timer,
				AircraftDestruction.POST_BREAKUP_LINGER_S)
			and is_equal_approx(ac._destroy_visual_alpha, 1.0)
			and _explosion_host.airframe_waves.size() == wave_count_before
			and _explosion_host.flashes.size() == flash_count_before + 1,
			"%s 终点爆炸触发帧仍保留清晰机体" % damage_kind)
		ac._update_destroy(AircraftDestruction.POST_BREAKUP_OPAQUE_S)
		_check(is_instance_valid(retained)
			and is_equal_approx(ac._destroy_visual_alpha, 1.0),
			"%s 爆炸后先完整停留且不透明" % damage_kind)
		ac._update_destroy(AircraftDestruction.POST_BREAKUP_LINGER_S)
		await get_tree().process_frame
		_check(not is_instance_valid(retained)
			and _explosion_host.airframe_waves.size() == wave_count_before
			and _explosion_host.flashes.size() == flash_count_before + 1
			and is_equal_approx(float(_explosion_host.flashes.back()["scale"]),
				AircraftDestruction.SMALL_AIRFRAME_BREAKUP_SCALE),
			"%s 仅在坠毁终点播放一次小方框并在保留期后释放" % damage_kind)


func _test_unified_aircraft_breakup() -> void:
	var wave_count_before := _explosion_host.airframe_waves.size()
	var flash_count_before := _explosion_host.flashes.size()
	var ac := _new_aircraft_for_destruction()
	ac.set_meta("_last_damage_kind", "gun")
	ac._start_destroy()
	_check(ac.is_destroyed
		and is_equal_approx(ac._destroy_status_timer, Aircraft.DESTROY_STATUS_HOLD_S)
		and is_equal_approx(ac._destroy_visual_scale, 1.0)
		and is_equal_approx(ac._destroy_visual_alpha, 1.0),
		"任意致命伤害保留 0.85s 共享状态栏并进入失控坠毁")
	ac._update_destroy(0.40)
	_check(ac._destroy_status_timer > 0.44 and ac._destroy_status_timer < 0.46
		and _explosion_host.airframe_waves.size() == wave_count_before
		and _explosion_host.flashes.size() == flash_count_before,
		"状态栏保留阶段只推进坠毁，不提前生成解体爆炸")
	var early_scale := ac._destroy_visual_scale
	_check(early_scale < 1.0 and early_scale > AircraftDestruction.CRASH_MODEL_END_SCALE
		and is_equal_approx(ac._destroy_visual_alpha, 1.0)
		and ac.scale == Vector2.ONE and is_equal_approx(ac.self_modulate.a, 1.0),
		"坠毁前段真实模型开始缩小，但节点与屏幕空间状态栏不继承缩放或透明度")
	ac._update_destroy(1.50)
	_check(ac._destroy_visual_scale < early_scale
		and is_equal_approx(ac._destroy_visual_alpha, 1.0),
		"坠毁后段模型继续缩小但保持完整可见")
	ac._destroy_timer = 0.01
	var retained: Variant = ac
	ac._update_destroy(0.02)
	_check(ac._destroy_breakup_emitted
		and _explosion_host.airframe_waves.size() == wave_count_before
		and _explosion_host.flashes.size() == flash_count_before + 1,
		"普通战斗机坠毁终点恰好播放一次小型普通方框")
	_check(is_equal_approx(ac._destroy_visual_scale,
			AircraftDestruction.CRASH_MODEL_END_SCALE)
		and is_equal_approx(ac._destroy_visual_alpha, 1.0)
		and is_equal_approx(ac._destroy_linger_timer,
			AircraftDestruction.POST_BREAKUP_LINGER_S),
		"坠毁终点爆炸发生时模型保持清晰并开始保留计时")
	_check(ac._trail_ribbon._trail_data.is_empty() and not ac._trail_ribbon.visible,
		"空中解体终点清空尾迹但不移除机体")
	ac._update_destroy(0.45)
	_check(is_instance_valid(retained)
		and ac._destroy_visual_alpha > 0.0 and ac._destroy_visual_alpha < 1.0
		and ac._destroy_visual_scale > AircraftDestruction.POST_BREAKUP_END_SCALE,
		"爆炸后机体继续运动并经过可见渐隐阶段")
	ac._update_destroy(0.45)
	await get_tree().process_frame
	_check(not is_instance_valid(retained),
		"统一坠毁解体在可见保留期后 queue_free 且下一帧无残留对象")


func _test_hit_location_crash_response() -> void:
	var nose := _new_aircraft_for_destruction()
	AircraftDestruction.record_hit(nose, nose.global_position + Vector2(0.0, -100.0))
	_check(nose._last_hit_zone == AircraftDestruction.HIT_NOSE,
		"机鼻真实命中坐标映射到 NOSE 分区")
	nose._start_destroy()
	_check(nose._destroy_descent_mult >= 0.90 * 1.25,
		"机鼻致命伤提高俯冲下坠响应并抑制烟花式乱转")

	var tail := _new_aircraft_for_destruction()
	AircraftDestruction.record_hit(tail, tail.global_position + Vector2(0.0, 100.0))
	_check(tail._last_hit_zone == AircraftDestruction.HIT_TAIL_ENGINE,
		"尾部真实命中坐标映射到 TAIL_ENGINE 分区")
	tail._start_destroy()
	_check(tail._destroy_speed_decay_mult >= 0.85 * 1.65,
		"发动机／尾部致命伤显著加快速度流失")

	var port := _new_aircraft_for_destruction()
	AircraftDestruction.record_hit(port, port.global_position + Vector2(-100.0, 0.0))
	port._start_destroy()
	var starboard := _new_aircraft_for_destruction()
	AircraftDestruction.record_hit(
		starboard, starboard.global_position + Vector2(100.0, 0.0))
	starboard._start_destroy()
	_check(port._last_hit_zone == AircraftDestruction.HIT_PORT_WING
		and starboard._last_hit_zone == AircraftDestruction.HIT_STARBOARD_WING
		and port._destroy_bank_rate <= -1.80
		and starboard._destroy_bank_rate >= 1.80,
		"左右翼致命伤产生方向相反且足够明显的失控侧翻")

	var varied := not is_equal_approx(nose._destroy_timer, tail._destroy_timer) \
		or not is_equal_approx(nose._destroy_spin, tail._destroy_spin) \
		or not is_equal_approx(nose._destroy_move_mult, tail._destroy_move_mult)
	_check(varied, "每架飞机在坠毁开始时冻结独立局部随机参数")
	for ac in [nose, tail, port, starboard]:
		ac.free()


func _test_large_aircraft_structural_breakup() -> void:
	var small_params := AircraftParams.new()
	small_params.visual_length_m = 40.0
	small_params.visual_span_m = 45.0
	small_params.is_unmanned = true
	var drone := _new_aircraft_for_destruction()
	drone.params = small_params
	_check(AircraftDestruction.destruction_size_class(drone) == AircraftDestruction.SIZE_SMALL,
		"无人机即使翼展较大仍固定采用小单位单方框语法")
	drone.free()

	var wave_count_before := _explosion_host.airframe_waves.size()
	var flash_count_before := _explosion_host.flashes.size()
	var bomber := _new_aircraft_for_destruction()
	bomber.set_meta("crash_style", "bomber")
	AircraftDestruction.record_hit(
		bomber, bomber.global_position + Vector2(0.0, 100.0))
	bomber._start_destroy()
	_check(bomber._destroy_size_class == AircraftDestruction.SIZE_LARGE,
		"大型轰炸机进入 large 结构性解体等级")
	bomber._destroy_timer = 0.01
	var retained: Variant = bomber
	bomber._update_destroy(0.02)
	_check(_explosion_host.flashes.size() == flash_count_before
		and _explosion_host.airframe_waves.size() == wave_count_before + 1
		and int(_explosion_host.airframe_waves.back()["route"]) == 2
		and is_instance_valid(retained)
		and is_equal_approx(bomber._destroy_visual_alpha, 1.0),
		"大型飞机结构波触发时保留清晰机体，尾部受击选择尾部回卷路线")
	bomber._update_destroy(AircraftDestruction.POST_BREAKUP_LINGER_S)
	await get_tree().process_frame
	_check(not is_instance_valid(retained),
		"大型飞机结构波完成可见保留后跨下一帧安全释放")

func _check(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		printerr("  ✗ %s" % label)
