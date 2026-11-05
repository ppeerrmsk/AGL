extends Node2D
## 对锋干扰与范围 JAM 走正式入口，验证跨帧结算与玩家小队归因。
const BossPhaseTests := preload("res://scripts/tests/test_boss_phase.gd")

func _ready() -> void:
	call_deferred("_run_focused")

func _run_focused() -> void:
	var failures := await run(self)
	AudioManager.request_quit(0 if failures == 0 else 1)

static func run(host: Node) -> int:
	var world := BossPhaseTests.StubMode.new()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	host.add_child(world)
	var saved_units := CombatUnit.all_units.duplicate()
	CombatUnit.all_units.clear()
	var leader := _aircraft(world, "Leader", Vector2.ZERO, CombatUnit.TEAM_PLAYER)
	var wing := _aircraft(world, "Wing", Vector2(1500, 0), CombatUnit.TEAM_PLAYER)
	var ordinary := _aircraft(world, "MQ-109", Vector2(0, -500))
	var swarm := _aircraft(world, "MQ-110", Vector2(1500, -500))
	var laser := _aircraft(world, "MQ-111", Vector2(1550, -500))
	var rail := _aircraft(world, "MQ-112", Vector2(1600, -500))
	var elite := _aircraft(world, "MQ-X", Vector2(1650, -500))
	var outside := _aircraft(world, "MQ-109", Vector2(8000, 0))
	for ac in [swarm, laser, rail, elite]:
		ac.set_meta("no_kill_reward", true)
	outside.apply_status(StatusEffects.JAM, 9.0)
	var sp := SurvivorPlayer.new()
	world.add_child(sp)
	sp.aircraft = leader
	sp.level = 1
	var spawner := SurvivorSpawner.new()
	world.add_child(spawner)
	spawner.mode = world
	spawner.survivor_player = sp
	spawner.player_aircraft = leader
	var event := {"kills": 0}
	var on_kill := func(_a, _b, kind, _d, _e, _f):
		if kind == "jam_execute": event.kills += 1
	EventLogger.kill_recorded.connect(on_kill)
	var failed := 0
	SurvivorSkillRuntime.sync_team_state({}, null)
	AOEBroadcast.apply_status_in_radius(ordinary.position, 50.0, CombatUnit.TEAM_HOSTILE,
		StatusEffects.JAM, 3.0, leader, Color.WHITE, true)
	failed += _check(ordinary.has_status(StatusEffects.JAM) and not ordinary.is_destroyed, "未获技能只施加 JAM")
	ordinary.remove_status(StatusEffects.JAM)
	SurvivorSkillRuntime.sync_team_state({"invasion_algorithm": 1}, null)
	for pair in [[leader, ordinary], [wing, swarm]]:
		var source: Aircraft = pair[0]
		var target: Aircraft = pair[1]
		source.head_on_jam_threshold = 1.0
		source.radar_targets[target] = 2.0
		target.heading = PI
		source._update_evasion(1.1)
		failed += _check(target.is_destroyed and int(target.get_meta("kill_attacker_id", -1)) == source.get_instance_id(), "对锋干扰击落与来源归因 " + source.params.display_name)
	var hits := AOEBroadcast.apply_status_in_radius(swarm.position, 200.0, CombatUnit.TEAM_HOSTILE,
		StatusEffects.JAM, 3.0, wing, Color.WHITE, true)
	failed += _check(hits == 3 and laser.is_destroyed and rail.is_destroyed, "范围内 MQ-111/112 坠毁")
	failed += _check(elite.has_status(StatusEffects.JAM) and not elite.is_destroyed, "MQ-X 只受 JAM")
	failed += _check(outside.has_status(StatusEffects.JAM) and not outside.is_destroyed, "范围外已受干扰的 MQ 存活")
	await host.get_tree().process_frame
	await host.get_tree().create_timer(0.25).timeout
	spawner._detect_kills()
	spawner._detect_kills()
	failed += _check(event.kills == 4 and spawner.kill_count == 4, "四次处决各派发和结算一次")
	failed += _check(sp.total_xp_gained == SurvivorSpawner.XP_PER_KILL_UAV + 8, "只获得普通 MQ-109 的一份经验")
	EventLogger.kill_recorded.disconnect(on_kill)
	SurvivorSkillRuntime.reset_team_state()
	world.queue_free()
	await host.get_tree().process_frame
	CombatUnit.all_units.assign(saved_units)
	print("[InvasionAlgorithm] completed fail=%d" % failed)
	return failed

static func _aircraft(world: Node2D, model: String, pos: Vector2, team: int = CombatUnit.TEAM_HOSTILE) -> Aircraft:
	var ac := Aircraft.new()
	ac.params = preload("res://resources/default_fighter.tres").duplicate(true)
	ac.params.display_name = model
	ac.team = team
	ac.position = pos
	if team == CombatUnit.TEAM_HOSTILE:
		ac.set_meta("enemy_type", "uav")
	world.add_child(ac)
	if not CombatUnit.all_units.has(ac):
		CombatUnit.all_units.append(ac)
	return ac

static func _check(ok: bool, label: String) -> int:
	print("[InvasionAlgorithm] %s %s" % ["PASS" if ok else "FAIL", label])
	return 0 if ok else 1
