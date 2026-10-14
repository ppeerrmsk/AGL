extends "res://scripts/survivor/survivor_mode.gd"
## opt-in 场景装配器：复用正式飞行/雷达/武器，战局资源与UI由独立模块拥有。
const LedgerScript := preload("res://scripts/rts/war_ledger.gd")
const PanelScript := preload("res://scripts/rts/war_command_panel.gd")
const SECTORS: Array[Vector2] = [Vector2(-2200, 3200), Vector2(600, 3200), Vector2(3400, 3200)]
const SECTOR_RADIUS := 1600.0
var war := LedgerScript.new()
var ace_squads: Array[Squad] = []
var active_ace := 0
var control: Array[int] = [-1, -1, -1]
var command_panel: TacticalMap
var markers: Array[Dictionary] = []
var _war_ready := false
var _war_accum := 0.0
var _enemy_next := 22.0
var _enemy_batches := 0
var _unit_serial := 0
var peak_population := 0
var peak_missiles := 0
var _sectors_overlay: Node2D

func _ready() -> void:
	# 不写全局模式判断；独立场景复用预览基座，阻止生存刷怪、功勋和Boss时钟。
	get_tree().set_meta("map_preview_only", true)
	get_tree().set_meta("survivor_map_id", "default")
	get_tree().set_meta("survivor_aircraft_resource", "res://resources/playable_f14.tres")
	for key in ["boss_debug_mode", "boss_debug_id", "boss_debug_scenario", "ugc_map_path", "bench_mode", "bench_scenario", "bench_duration"]:
		if get_tree().has_meta(key):
			get_tree().remove_meta(key)
	super._ready()
	# 复用已有阴影几何缓存；可见集/颜色/偏移变化仍由渲染器失效。
	if is_instance_valid(_building_renderer):
		_building_renderer.cache_shadow_geometry = true
		_building_renderer.redraw_roof_error_px = 0.5
	_sectors_overlay = preload("res://scripts/rts/war_sector_overlay.gd").new()
	_sectors_overlay.z_index = -1
	add_child(_sectors_overlay)
	hud._warzone_timer_panel.hide()
	# 不沿用暂停地图的UI生命周期。
	if _tactical_map != null:
		_tactical_map.queue_free()
		_tactical_map = null
	survivor_player.set_process(false)
	survivor_player.level = 21
	for member: Aircraft in _squad_members_alive():
		EvolutionSystem.evolve(member, &"f22", member != player_aircraft, false)
		_prepare_ace(member, 0)
	_final_war_place_primary_squad(Vector2(-1700, 5600), 0.0)
	ace_squads.append(_squad)
	ace_squads.append(null) # 第二队仅保存后备名额，玩家下令后才实例化。
	# 已有长机没有自主AI；补上后保持manual，移交时才接管。
	var primary_ai := _ensure_pilot(player_aircraft)
	primary_ai.manual_control = true
	for lane in [0, 2]:
		_spawn_air(true, lane, 4, float(lane) * 220.0)
	_spawn_ground(1, 0)
	_spawn_ground(1, 2)
	war.dispatched.connect(_on_dispatch)
	war.ended.connect(_on_war_ended)
	command_panel = PanelScript.new()
	add_child(command_panel)
	command_panel.setup(Rect2(-5200, -2000, 11600, 11600), player_aircraft, null, self)
	_tactical_map = command_panel
	_camera_ctrl.set_follow_target(player_aircraft)
	_camera_ctrl.target_zoom = 0.13
	_camera_ctrl._base_zoom = 0.13
	camera.zoom = Vector2.ONE * 0.13
	_war_ready = true
	_publish_snapshot()
	command_panel.refresh()

func _prepare_ace(ac: Aircraft, index: int) -> void:
	ac.team = CombatUnit.TEAM_PLAYER
	ac.invulnerable = false
	ac.callsign = "%s-%02d" % ["SPEAR" if index == 0 else "SABRE", ac.squad_slot]
	ac.set_meta("skip_far_cleanup", true)
	ac.set_meta("war_ace", index)
	# 只施加独立机体属性型预设，避免单玩家全局技能在切队后复制。
	if ac.params.gun != null:
		ac.params.gun.bullet_damage *= 1.25
	ac.params.max_hp *= 1.35
	ac.hp = ac.params.max_hp
	war.register_unit(ac, 0, 10.0)

func _ensure_pilot(ac: Aircraft) -> AIController:
	var ai := _get_ai(ac)
	if ai == null:
		ai = AIController.new()
		ai.aircraft = ac
		ac.add_child(ai)
	ai.skill_level = 1.0
	ai.composure = 1.0
	ai.enable_combat = true
	ai.evade_missiles = true
	ai.waypoints = PackedVector2Array([SECTORS[active_ace * 2], Vector2(600, 5000)])
	return ai

func _set_patrol(members: Array[Aircraft], center: Vector2) -> void:
	for ac: Aircraft in members:
		var ai := _get_ai(ac)
		if ai != null:
			ai.waypoints = PackedVector2Array([center + Vector2(-500, 0), center + Vector2(500, 400)])
			ai.current_waypoint_index = 0

func _spawn_air(hostile: bool, sector: int, count: int, offset := 0.0) -> void:
	_unit_serial += 1
	var team_id := CombatUnit.TEAM_HOSTILE if hostile else CombatUnit.TEAM_ALLY
	var type_id := SurvivorSpawner.EnemyType.FA18E
	if hostile:
		type_id = SurvivorSpawner.EnemyType.SU57 if _unit_serial % 2 == 0 else SurvivorSpawner.EnemyType.F22
	var pos := Vector2(SECTORS[sector].x + offset, -900 if hostile else 7300)
	var members := _final_war_spawn_regular_squad(type_id, count, pos,
		180.0 if hostile else 0.0, team_id, "R%02d" % _unit_serial)
	_set_patrol(members, SECTORS[sector])
	for ac: Aircraft in members:
		war.register_unit(ac, 1 if hostile else 0, 4.0)

func _terrain_position(origin: Vector2, land: bool) -> Vector2:
	# 一次性有界搜索；保留完整船体离岸裕量，不在tick内调用。
	for ring in range(25):
		for angle in range(16):
			var pos := origin + Vector2.from_angle(float(angle) * TAU / 16.0) * float(ring) * 160.0
			if not _map_boundary.get_world_rect().has_point(pos):
				continue
			if MapGeography.is_on_land(pos) != land:
				continue
			var valid := true
			for d in [Vector2(240, 0), Vector2(-240, 0), Vector2(0, 240), Vector2(0, -240)]:
				if MapGeography.is_on_land(pos + d) != land:
					valid = false
			if valid:
				return pos
	return Vector2.INF

func _spawn_ship(side: int, sector: int, destroyer: bool, reinforcement := false) -> bool:
	var origin := Vector2(SECTORS[sector].x, 1200 if side == 1 else 5300)
	if reinforcement:
		_unit_serial += 1
		origin = Vector2(SECTORS[sector].x + float(_unit_serial % 3) * 320.0, 7600)
	var pos := _terrain_position(origin, false)
	if pos == Vector2.INF:
		return false
	var ship := _final_war_spawn_ship(_ddg_params if destroyer else _ffg_params,
		preload("res://scripts/naval/destroyer_ship.gd") if destroyer else preload("res://scripts/naval/frigate_ship.gd"),
		pos, 180.0 if side == 1 else 0.0,
		CombatUnit.TEAM_HOSTILE if side == 1 else CombatUnit.TEAM_ALLY)
	war.register_unit(ship, side, 20.0)
	if reinforcement:
		var destination := _terrain_position(Vector2(SECTORS[sector].x, 5300), false)
		var clear_route := destination != Vector2.INF
		for i in range(33):
			if clear_route and MapGeography.is_on_land(pos.lerp(destination, float(i) / 32.0)):
				clear_route = false
		if clear_route:
			ship.waypoints = PackedVector2Array([destination])
	return true

func _spawn_ground(side: int, sector: int) -> void:
	var pos := _terrain_position(Vector2(SECTORS[sector].x, 800 if side == 1 else 6000), true)
	if pos == Vector2.INF:
		return
	var unit := _sam_scene.instantiate() as SAMUnit
	unit.params = _sam_params.duplicate(true)
	unit.team = CombatUnit.TEAM_HOSTILE if side == 1 else CombatUnit.TEAM_ALLY
	unit.position = pos
	unit.bullet_manager = bullet_manager
	unit.missile_manager = missile_manager
	add_child(unit)
	war.register_unit(unit, side, 6.0)

func _on_dispatch(kind: String, sector: int, _request_id: int) -> void:
	if kind == "ace":
		_deploy_second_ace(sector)
	elif kind == "frigate":
		if not _spawn_ship(0, sector, false, true):
			war.refund(kind)
	else:
		_spawn_air(false, sector, int(LedgerScript.PACKAGES[kind].count))

func _deploy_second_ace(sector: int) -> void:
	if ace_squads[1] != null:
		return
	var members := _final_war_spawn_player_squad(&"su57", Vector2(SECTORS[sector].x, 7300), 0.0)
	if members.is_empty():
		war.refund("ace")
		return
	ace_squads[1] = _get_ai(members[0]).squad
	for i in range(members.size()):
		members[i].squad_slot = i + 1
		_prepare_ace(members[i], 1)
	_set_patrol(members, SECTORS[sector])

func switch_ace(index: int) -> bool:
	if not war.active or index < 0 or index >= ace_squads.size() or index == active_ace:
		return false
	var sq := ace_squads[index]
	if sq == null:
		return false
	sq.cleanup()
	var candidate: Variant = sq.leader
	if typeof(candidate) != TYPE_OBJECT or not is_instance_valid(candidate) \
			or not candidate is Aircraft or candidate.is_destroyed:
		return false
	_squad_cmd.cancel()
	_ensure_pilot(player_aircraft).manual_control = false
	_squad = sq
	active_ace = index
	_switch_player_to(candidate as Aircraft)
	_player_profile_id = StringName(str(player_aircraft.get_meta("profile_id", "")))
	_player_profile = AircraftDB.get_profile(_player_profile_id)
	return true

func _physics_process(delta: float) -> void:
	if not _war_ready or not war.active:
		return
	super._physics_process(delta)
	if not war.active:
		return
	_war_accum += delta
	if _war_accum < 0.5:
		return
	var step := _war_accum
	_war_accum = 0.0
	_publish_snapshot()
	war.tick(step, control)
	if not war.active:
		return
	_enemy_next -= step
	if _enemy_next <= 0.0 and _enemy_batches < 8 \
			and war.live_count(1) + 4 <= LedgerScript.SIDE_CAP \
			and war.living_units().size() + 4 <= LedgerScript.LIVE_CAP:
		_spawn_air(true, _enemy_batches % 3, 4)
		_enemy_batches += 1
		_enemy_next = 22.0
	for sq: Squad in ace_squads:
		if sq != null:
			sq.cleanup()
	command_panel.refresh()

func _publish_snapshot() -> void:
	markers.clear()
	var counts := [[0, 0], [0, 0], [0, 0]]
	var units := war.living_units()
	peak_population = maxi(peak_population, units.size())
	peak_missiles = maxi(peak_missiles, missile_manager.get_child_count())
	for unit: CombatUnit in units:
		var side := 1 if unit.team == CombatUnit.TEAM_HOSTILE else 0
		markers.append({"pos": unit.global_position, "side": side})
		for i in range(3):
			if unit.global_position.distance_squared_to(SECTORS[i]) <= SECTOR_RADIUS * SECTOR_RADIUS:
				counts[i][side] += 1
	for i in range(3):
		var difference: int = counts[i][0] - counts[i][1]
		control[i] = 0 if difference >= 2 else (1 if difference <= -2 else -1)
	if _sectors_overlay != null:
		_sectors_overlay.set_sectors(SECTORS, control)

func _unhandled_input(event: InputEvent) -> void:
	if command_panel != null and command_panel.is_open():
		return
	super._unhandled_input(event)

func _try_takeover_after_leader_down() -> bool:
	return false

func _on_squad_leader_changed(_new_leader: Aircraft) -> void:
	# 本原型遵守操控机阵亡即失败，不能靠自动换帅消除死亡。
	pass

func _on_player_died() -> void:
	war.finish(false)

func _on_player_leveled_up(_new_level: int) -> void:
	pass

func _spawn_starting_wingmen(profile: PlayableAircraft) -> void:
	var preset := profile.duplicate() as PlayableAircraft
	preset.wingman_count = 3
	super._spawn_starting_wingmen(preset)

func _migrate_ace_field_upgrades(_prev: Aircraft, _next: Aircraft) -> void:
	# 预设加成属于机体；切换操控不迁移。
	pass

func _on_war_ended(won: bool) -> void:
	is_game_over = true
	_set_hard_brake(false)
	command_panel.show_result(won)
	process_mode = Node.PROCESS_MODE_DISABLED

func _exit_tree() -> void:
	war.shutdown()
	ace_squads.clear()
	super._exit_tree()
