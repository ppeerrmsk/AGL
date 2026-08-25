extends Node

## 跨帧终态回归门：必须让真实节点进入 SceneTree、queue_free、再越过后续帧与缓存 tick。
## 单纯验证公式/状态字段不能替代这里的对象生命周期顺序。

const STRATEGIC_TARGET_SCENE := preload("res://scenes/strategic_target.tscn")
const SUPER_CANNON_SCRIPT := preload("res://scripts/survivor/tier3_super_cannon_part.gd")

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
	_explosion_host = FakeExplosionHost.new()
	_explosion_host.add_to_group("explosion_vfx")
	add_child(_explosion_host)
	await _test_bomber_cache_after_target_free()
	await _test_bomber_cache_after_controller_free()
	await _test_bomber_retire_with_freed_members()
	await _test_zone_completion_after_deferred_free()
	await _test_conquered_garrison_retire_after_offscreen_grace()
	await _test_zone_failure_after_deferred_free()
	await _test_super_cannon_destroy_after_deferred_free()
	await _test_ace_music_cleanup_after_deferred_free()
	await _test_all_damage_kinds_enter_aircraft_crash()
	await _test_unified_aircraft_breakup()
	await _test_hit_location_crash_response()
	await _test_large_aircraft_structural_breakup()
	print("[LifecycleGauntlet] result pass=%d fail=%d" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)

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
	mission.fail_zone(&"A", "lifecycle_probe")
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

func _test_ace_music_cleanup_after_deferred_free() -> void:
	var mode := FakeAceMusicMode.new()
	add_child(mode)
	var director := FakeAceMusicDirector.new()
	director.mode = mode
	var event := AceReinforcementEvent.new()
	event.director = director
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

	var freed_mode: Variant = await _freed(mode)
	director.mode = freed_mode
	var late_event := AceReinforcementEvent.new()
	late_event.director = director
	late_event._ace_music_started = true
	late_event._finish()
	await get_tree().process_frame
	_check(not late_event._ace_music_started,
		"Mode queue_free 后跨下一帧清理仍安全释放王牌 BGM 所有权")


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
