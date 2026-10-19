extends RefCounted
## Crucible 内部的完全体控制器；不创建第二个结算事件。

const Rules = preload("res://scripts/survivor/orion_fire_control.gd")
const Config = preload("res://scripts/survivor/orion_airframe_config.gd")
const FangLaser = preload("res://scripts/survivor/orion_fang_laser.gd")
const WeaponOverlay = preload("res://scripts/survivor/orion_weapon_overlay.gd")
const TEAM := CombatUnit.TEAM_FREE_FOR_ALL_BASE + 18

var active := false
var engaged := false
var defeated := false
var body_id: int = 0
var member_ids: Array[int] = []
var lasers: Array = []
var lock_ids: Array[int] = []
var rail_lines: Array[Dictionary] = []
var intercept_flashes: Array[Dictionary] = []
var _player_id: int = 0
var _missile_manager_id: int = 0
var _overlay_id: int = 0
var _candidate_rows: Array[Dictionary] = []
var _previous_positions: Dictionary = {}
var _owned_missile_ids: Array[int] = []
var _scan_timer := 0.0
var _clock := 0.0
var _admm_phase := 0 # 0 冷却，1 锁定，2 发射
var _admm_timer := 0.0
var _lock_duration := 0.0
var _launch_time := 0.0
var _last_launch_time := -INF
var _last_launch_by_target: Dictionary = {}
var _launch_queue: Array[Dictionary] = []
var _rail_cooldown := 10.0 # 首轮优先呈现 ADMM；避免双炮把第一次齐射推迟到八秒以后。
var _rail_elapsed := -1.0
var _rail_target_id: int = 0
var _rail_fired := 0
var _rail_aims: Dictionary = {}
var _launch_block_until := 0.0
var _regrouping := false
var _fang_returning: Dictionary = {}
var _admm: MissileParams
var _railgun: RailgunEquipment


func spawn(create_enemy: Callable, player: Aircraft, manager: MissileManager,
		position: Vector2, heading: float) -> bool:
	_player_id = player.get_instance_id()
	_missile_manager_id = manager.get_instance_id()
	_admm = Config.make_admm()
	_railgun = RailgunEquipment.new()
	_railgun.damage = 45.0
	_railgun.hit_radius_px = 8.0
	for index in range(3):
		var offset := Vector2.ZERO if index == 0 else Vector2(-220.0 if index == 1 else 220.0, 180.0)
		var raw: Variant = create_enemy.call(SurvivorSpawner.EnemyType.CRE,
			position + offset.rotated(heading), rad_to_deg(heading))
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is Aircraft:
			cleanup(true)
			return false
		var ac := raw as Aircraft
		ac.params = Config.make_airframe(index > 0)
		ac.hp = ac.params.max_hp
		ac.altitude = 5500.0
		ac.target_altitude = 5500.0
		ac.team = TEAM
		ac.callsign = "ORION" if index == 0 else "FANG-%d" % index
		ac.params.display_name = ac.callsign
		ac.no_pilot = true
		ac.has_radio_voice = false
		ac.equipment_state.clear()
		ac.flares_remaining = 2 if index == 0 else 0
		ac.enable_flare_reload = index == 0
		ac.set_meta("enemy_type", "orion_final_form" if index == 0 else "orion_fang")
		ac.set_meta("silhouette", "orion_final_form" if index == 0 else "orion_fang")
		ac.set_meta("skip_far_cleanup", true)
		ac.set_meta("no_kill_reward", true)
		ac.set_meta("faction_conversion_locked", true)
		ac.set_meta("crucible_high_lod", true)
		ac.set_meta("token_cost", 0)
		var ai := ac._get_ai_controller()
		if ai != null:
			ai.skill_level = 1.0
			ai.composure = 1.0
			ai.focus = 1.0
			ai.situational_awareness = 1.0
			ai.self_preservation = 0.0
			ai.ai_tick_divisor = 1
			ai._scaling_class_cached = AIController.AIScaleClass.IMMUNE
			ai.enable_combat = false
		member_ids.append(ac.get_instance_id())
		if index == 0:
			body_id = ac.get_instance_id()
		else:
			var laser := FangLaser.new()
			laser.setup(ac, 1.5 * float(index - 1))
			lasers.append(laser)
	var overlay := WeaponOverlay.new()
	overlay.name = "OrionWeaponOverlay"
	overlay.z_index = 100
	manager.get_parent().add_child(overlay)
	_overlay_id = overlay.get_instance_id()
	active = true
	return true


func engage() -> void:
	engaged = true
	_scan_timer = 3.0
	_admm_timer = 3.0


func set_player_ref(player: Aircraft) -> void:
	_player_id = player.get_instance_id() if is_instance_valid(player) else 0


func body() -> Aircraft:
	return _aircraft(body_id)


func get_members() -> Array:
	var result: Array = []
	for uid in member_ids:
		var ac := _aircraft(uid)
		if ac != null:
			result.append(ac)
	return result


func update(delta: float) -> void:
	if not active:
		return
	var host := body()
	if host == null or host.is_destroyed:
		defeated = true
		cleanup(false)
		return
	if not engaged:
		return
	_clock += delta
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.5
		_scan_targets(host)
		_cancel_invalid_slots(host)
		_update_flight_orders(host)
	_update_rail(host, delta)
	_update_admm(host, delta)
	# 共用一份帧前位置表，两个光剑都能检查同一条完整位移轨迹。
	var units: Array = CombatUnit.all_units.duplicate()
	var missiles: Array = Missile.active_missiles.duplicate()
	for index in range(intercept_flashes.size() - 1, -1, -1):
		intercept_flashes[index]["life"] -= delta
		if intercept_flashes[index]["life"] <= 0.0:
			intercept_flashes.remove_at(index)
	for laser in lasers:
		laser.update(delta, units, missiles, _previous_positions)
		for point: Vector2 in laser.intercept_points:
			if intercept_flashes.size() >= 32:
				intercept_flashes.pop_front()
			intercept_flashes.append({"position": point, "life": 0.2})
	_previous_positions.clear()
	for collection: Array in [units, missiles]:
		for raw: Variant in collection:
			if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is Node2D:
				_previous_positions[raw.get_instance_id()] = raw.global_position
	for index in range(rail_lines.size() - 1, -1, -1):
		rail_lines[index]["life"] -= delta
		if rail_lines[index]["life"] <= 0.0:
			rail_lines.remove_at(index)
	_present_weapons()


func cleanup(remove_actors: bool) -> void:
	active = false
	engaged = false
	lock_ids.clear()
	_launch_queue.clear()
	_last_launch_by_target.clear()
	_candidate_rows.clear()
	_previous_positions.clear()
	_fang_returning.clear()
	_rail_aims.clear()
	_rail_target_id = 0
	_rail_elapsed = -1.0
	rail_lines.clear()
	intercept_flashes.clear()
	for laser in lasers:
		laser.stop()
	for uid in _owned_missile_ids:
		var raw: Variant = instance_from_id(uid)
		if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is Missile:
			raw.destroy_from_intercept(false)
	_owned_missile_ids.clear()
	for uid in member_ids:
		var ac := _aircraft(uid)
		if ac == null:
			continue
		var ai := ac._get_ai_controller()
		if ai != null:
			ai.enable_combat = false
		if remove_actors:
			ac.queue_free()
	_player_id = 0
	_missile_manager_id = 0
	var overlay: Variant = instance_from_id(_overlay_id) if _overlay_id != 0 else null
	if typeof(overlay) == TYPE_OBJECT and is_instance_valid(overlay):
		overlay.queue_free()
	_overlay_id = 0


func _scan_targets(host: Aircraft) -> void:
	_candidate_rows.clear()
	for raw: Variant in CombatUnit.all_units:
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is Aircraft:
			continue
		var ac := raw as Aircraft
		if ac.is_destroyed or not host.is_hostile_to(ac) or ac.is_lock_immune():
			continue
		var distance := host.global_position.distance_to(ac.global_position)
		if distance > Rules.RANGE_PX or (not host.flat_altitude and absf(host.altitude - ac.altitude) > 5000.0):
			continue
		var priority := 0 if ac.has_meta("crucible_profile") else (2 if ac.team in [CombatUnit.TEAM_PLAYER, CombatUnit.TEAM_ALLY] else 1)
		_candidate_rows.append({"id": ac.get_instance_id(), "priority": priority, "distance": distance})


func _update_admm(host: Aircraft, delta: float) -> void:
	_admm_timer -= delta
	if _admm_phase == 0 and _admm_timer <= 0.0:
		lock_ids = Rules.allocate_salvo(_candidate_rows)
		if lock_ids.is_empty():
			_admm_timer = 0.5
			return
		_prune_missiles()
		if _owned_missile_ids.size() + lock_ids.size() > Rules.MAX_SALVO:
			lock_ids.clear()
			_admm_timer = 0.5
			return
		_admm_phase = 1
		_admm_timer = Rules.lock_duration(lock_ids)
		_lock_duration = _admm_timer
	elif _admm_phase == 1 and _admm_timer <= 0.0 \
			and _rail_elapsed < 0.0 and _clock >= _launch_block_until:
		_prune_missiles()
		if _owned_missile_ids.size() + lock_ids.size() > Rules.MAX_SALVO:
			return
		_launch_queue = Rules.launch_schedule(lock_ids)
		_launch_time = 0.0
		_last_launch_time = -INF
		_last_launch_by_target.clear()
		_admm_phase = 2
	elif _admm_phase == 2:
		_launch_time += delta
		while not _launch_queue.is_empty() and float(_launch_queue[0]["time"]) <= _launch_time:
			var next_id := int(_launch_queue[0]["id"])
			if _clock - _last_launch_time < Rules.LAUNCH_INTERVAL \
					or _clock - float(_last_launch_by_target.get(next_id, -INF)) < Rules.SAME_TARGET_INTERVAL:
				break
			_prune_missiles()
			if _owned_missile_ids.size() >= Rules.MAX_SALVO:
				break
			var shot: Dictionary = _launch_queue.pop_front()
			var target := _aircraft(int(shot["id"]))
			if target == null or target.is_destroyed or target.is_lock_immune() \
					or not host.is_hostile_to(target) \
					or host.global_position.distance_to(target.global_position) > Rules.RANGE_PX \
					or (not host.flat_altitude and absf(host.altitude - target.altitude) > 5000.0):
				continue
			var raw: Variant = instance_from_id(_missile_manager_id)
			if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is MissileManager:
				continue
			var missile: Missile = raw.spawn_missile(host, target, _admm)
			if missile != null:
				AudioManager.play_sfx_2d("missile_launch", host.global_position)
				missile.vls_locked_point = target.global_position
				_owned_missile_ids.append(missile.get_instance_id())
				_last_launch_time = _clock
				_last_launch_by_target[next_id] = _clock
		if _launch_queue.is_empty():
			lock_ids.clear()
			_admm_phase = 0
			_admm_timer = Rules.SALVO_COOLDOWN
			_regrouping = true


func _update_rail(host: Aircraft, delta: float) -> void:
	_rail_cooldown -= delta
	if _rail_elapsed < 0.0:
		if _rail_cooldown > 0.0 or _admm_phase == 2 or _candidate_rows.is_empty():
			return
		for row in _candidate_rows:
			var target := _aircraft(int(row["id"]))
			if target == null or target.is_destroyed:
				continue
			var offset := target.global_position - host.global_position
			if offset.length() > 3000.0 \
					or absf(wrapf(atan2(offset.x, -offset.y) - host.heading, -PI, PI)) > deg_to_rad(12.0):
				continue
			_rail_target_id = target.get_instance_id()
			_rail_elapsed = 0.0
			_rail_fired = 0
			_rail_aims.clear()
			break
		return
	_rail_elapsed += delta
	var target := _aircraft(_rail_target_id)
	for index in range(2):
		var fire_at := 2.0 + float(index) * 0.45
		if not _rail_aims.has(index) and _rail_elapsed >= fire_at - 0.8:
			if target == null or target.is_destroyed:
				_rail_aims[index] = Vector2(sin(host.heading), -cos(host.heading))
			else:
				var velocity := Vector2(sin(target.heading), -cos(target.heading)) * target.speed * CombatUnit.PIXELS_PER_METER
				_rail_aims[index] = (target.global_position + velocity * 0.8 - host.global_position).normalized()
		if index == _rail_fired and _rail_elapsed >= fire_at:
			var direction: Vector2 = _rail_aims[index]
			var start := host.global_position + Vector2(-10.0 if index == 0 else 10.0, 0.0).rotated(host.heading)
			var end := start + direction * 3000.0
			_railgun._apply_hitscan_damage(host, start, end)
			rail_lines.append({"start": start, "end": end, "life": 0.25})
			_rail_fired += 1
	if _rail_fired >= 2:
		_rail_elapsed = -1.0
		_rail_target_id = 0
		_rail_aims.clear()
		_rail_cooldown = 10.0
		_launch_block_until = _clock + 1.5


func _update_flight_orders(host: Aircraft) -> void:
	var plan := Rules.allocate_salvo(_candidate_rows)
	var target := _aircraft(plan[0]) if not plan.is_empty() else _aircraft(_player_id)
	var ai := host._get_ai_controller()
	if ai != null and target != null and not target.is_destroyed:
		var away := host.global_position - target.global_position
		if away.length() < 1800.0:
			_regrouping = true
		if _regrouping and away.length() >= 1800.0 and away.length() <= 2600.0:
			_regrouping = false
		if _regrouping or away.length() > 2600.0:
			if away.length_squared() < 1.0:
				away = Vector2(sin(host.heading), -cos(host.heading))
			var position := MapBoundary.clamp_inside(target.global_position + away.normalized() * 2200.0, 1200.0)
			var directive := AIDirective.fly_to(position, AIDirective.OnArrival.RELEASE, 250.0)
			directive.owner_event = weakref(self)
			directive.priority = 50
			directive.params["target_speed"] = AircraftPhysics.effective_corner_speed_kmh(host)
			directive.params["speed_cap_kmh"] = AircraftPhysics.effective_corner_speed_kmh(host)
			ai.set_event_directive(directive)
		else:
			ai.set_event_directive(null)
		ai.enable_combat = true
		ai.acquire_target(target, AIController.TargetSource.TS_BOSS, "ORION fire control")
		ai.enter_engage_state()
	for index in range(1, member_ids.size()):
		var fang := _aircraft(member_ids[index])
		if fang == null or fang.is_destroyed:
			continue
		var destination := host.global_position \
			+ Vector2(-220.0 if index == 1 else 220.0, 180.0).rotated(host.heading)
		# 超出护卫带优先归队；近带内才选择导弹或敌机切线。
		var leash_distance := fang.global_position.distance_to(host.global_position)
		if leash_distance >= 1600.0:
			_fang_returning[member_ids[index]] = true
		elif leash_distance <= 700.0:
			_fang_returning.erase(member_ids[index])
		if not _fang_returning.has(member_ids[index]):
			var best_time := 2.5
			for raw: Variant in Missile.active_missiles:
				if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is Missile:
					continue
				var missile := raw as Missile
				if not missile.is_active or not CombatUnit.teams_hostile(fang.team, missile.team):
					continue
				var offset := fang.global_position - missile.global_position
				var velocity := Vector2(sin(missile.heading), -cos(missile.heading)) * missile.speed * CombatUnit.PIXELS_PER_METER
				var time := offset.dot(velocity) / maxf(velocity.length_squared(), 1.0)
				if offset.length() <= 1800.0 and time > 0.0 and time < best_time:
					best_time = time
					destination = missile.global_position + velocity * time
			if best_time == 2.5 and target != null \
					and fang.global_position.distance_to(target.global_position) <= Rules.BEAM_LENGTH:
				destination = target.global_position
		var fang_ai := fang._get_ai_controller()
		if fang_ai != null:
			var directive := AIDirective.fly_to(destination, AIDirective.OnArrival.RELEASE, 100.0)
			directive.priority = 50
			directive.owner_event = weakref(self)
			fang_ai.set_event_directive(directive)


func _cancel_invalid_slots(host: Aircraft) -> void:
	var canceled: Dictionary = {}
	for uid in lock_ids:
		var ac := _aircraft(uid)
		if ac == null or ac.is_destroyed or ac.is_lock_immune() or not host.is_hostile_to(ac) \
				or host.global_position.distance_to(ac.global_position) > Rules.RANGE_PX \
				or (not host.flat_altitude and absf(host.altitude - ac.altitude) > 5000.0):
			canceled[uid] = true
	for index in range(lock_ids.size() - 1, -1, -1):
		if canceled.has(lock_ids[index]):
			lock_ids.remove_at(index)
	for index in range(_launch_queue.size() - 1, -1, -1):
		if canceled.has(int(_launch_queue[index]["id"])):
			_launch_queue.remove_at(index)


func _prune_missiles() -> void:
	for index in range(_owned_missile_ids.size() - 1, -1, -1):
		var raw: Variant = instance_from_id(_owned_missile_ids[index])
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is Missile \
				or not raw.is_active:
			_owned_missile_ids.remove_at(index)


func _present_weapons() -> void:
	var overlay: Variant = instance_from_id(_overlay_id) if _overlay_id != 0 else null
	if typeof(overlay) != TYPE_OBJECT or not is_instance_valid(overlay):
		return
	var locks: Array[Dictionary] = []
	var repetitions: Dictionary = {}
	var lock_elapsed := _lock_duration - maxf(_admm_timer, 0.0)
	for uid in lock_ids:
		repetitions[uid] = int(repetitions.get(uid, 0)) + 1
	for uid: int in repetitions:
		var ac := _aircraft(uid)
		if ac == null or ac.is_destroyed:
			continue
		var count := mini(int(repetitions[uid]), maxi(0, 1 + floori((lock_elapsed - Rules.LOCK_BASE) / Rules.LOCK_REPEAT)))
		var progress := clampf(lock_elapsed / Rules.LOCK_BASE, 0.0, 1.0) if count == 0 \
			else clampf(fmod(maxf(lock_elapsed - Rules.LOCK_BASE, 0.0), Rules.LOCK_REPEAT) / Rules.LOCK_REPEAT, 0.0, 1.0)
		locks.append({"position": ac.global_position, "count": count, "progress": progress, "alpha": 0.8})
	var beams: Array[Dictionary] = []
	for laser in lasers:
		if laser.source_id != 0 and laser.phase != FangLaser.Phase.COOLDOWN:
			beams.append({"start": laser.beam_start, "end": laser.beam_end,
				"active": laser.phase == FangLaser.Phase.ACTIVE})
	var host := body()
	if host != null:
		if _rail_elapsed >= 0.0:
			var target := _aircraft(_rail_target_id)
			for index in range(_rail_fired, 2):
				var direction := Vector2(sin(host.heading), -cos(host.heading))
				if _rail_aims.has(index):
					direction = _rail_aims[index]
				elif target != null:
					direction = (target.global_position - host.global_position).normalized()
				var start := host.global_position + Vector2(-10.0 if index == 0 else 10.0, 0.0).rotated(host.heading)
				beams.append({"start": start, "end": start + direction * 3000.0, "active": false})
	overlay.present(locks, beams, rail_lines.duplicate(), intercept_flashes.duplicate())


static func _aircraft(uid: int) -> Aircraft:
	var raw: Variant = instance_from_id(uid) if uid != 0 else null
	if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is Aircraft:
		return null
	var ac := raw as Aircraft
	return null if ac.is_queued_for_deletion() else ac
