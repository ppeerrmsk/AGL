extends RefCounted
## 血色骑士真实伤害、击杀快照与跨帧奖励；focused 与 all 共用。
var _pass := 0
var _fail := 0
var _completed := 0

class TestMode extends Node2D:
	var upgrade_stacks: Dictionary = {"headon_xp": 1}
	var _player_profile = null
	var _bench_mode := true
	var _tutorial = null
	var boss_phase := false
	var afterburner_charge := AfterburnerCharge.new()
	func is_boss_phase() -> bool: return boss_phase
	func archive_enabled() -> bool: return false

func run(host: Node) -> int:
	var saved_units := CombatUnit.all_units.duplicate()
	var saved_player: Variant = AircraftRenderer.player_ref
	_test_catalog()
	for kind in ["gun", "missile", "qmaam", "rocket", "laser", "railgun", "aoe"]:
		await _air_case(host, {"kind": kind})
	for options in [
		{"skill": false}, {"active": false}, {"expired": true},
		{"active": false, "first_kill": true}, {"natural": true},
		{"natural": true, "skill": false}, {"colocated": true},
		{"wing": true}, {"wing": true, "active": false},
		{"switch": true}, {"free_killer": true}, {"no_reward": true},
		{"boss": true}, {"team": CombatUnit.TEAM_ALLY},
		{"victim_team": CombatUnit.TEAM_PLAYER}, {"no_consumers": true},
	]:
		await _air_case(host, options)
	await _surface_case(host)
	_check(_completed == 24, "全部 24 个真实终态案例运行到末尾")
	CombatUnit.all_units.clear()
	for raw in saved_units:
		if is_instance_valid(raw): CombatUnit.all_units.append(raw)
	AircraftRenderer.player_ref = saved_player if is_instance_valid(saved_player) else null
	print("[BloodlustHeadOn] pass=%d fail=%d completed=%d" % [_pass, _fail, _completed])
	return _fail

func _test_catalog() -> void:
	var card := SurvivorData.upgrade_by_id("bloodlust_head_on")
	_check(not card.is_empty() and SurvivorData.get_rarity(card) == SurvivorData.Rarity.ADVANCED,
		"正式表先进级")
	_check(card.get("axis") == "knight" and not card.has("scope") and card.get("max_stacks") == 1,
		"骑士轴全队单层")
	_check(SurvivorDebugSkills.debug_skill_ids().has("bloodlust_head_on")
		and SurvivorDebugSkills.debug_can_force_upgrade(card, 0)
		and not SurvivorDebugSkills.debug_can_force_upgrade(card, 1), "F4 覆盖并尊重单层")
	_check((card.get("requires_skill", []) as Array).has("berserk_virus")
		and SurvivorData.status_notes_of(card).has(StatusEffects.BLOODLUST), "来源前置与嗜血脚注")
	var params := AircraftParams.new()
	_check(not SurvivorData.is_upgrade_available_for(card, &"f86", params, {}), "无嗜血来源不进普通池")
	for source in card.requires_skill:
		_check(SurvivorData.is_upgrade_available_for(card, &"f86", params, {source: 1}), "来源可解锁 " + source)
	for controlled in [true, false]:
		var projected := SurvivorSkillCatalog.effective_stacks_for_machine([card],
			{"bloodlust_head_on": 1}, [], controlled)
		var replay := SurvivorSkillCatalog.replay_layers_for_machine([card],
			{"bloodlust_head_on": 1}, [], controlled)
		_check(projected.get("bloodlust_head_on", 0) == 1 and replay.size() == 1,
			"切控投影与晚入队/换机重放 controlled=%s" % controlled)
	var freed := Aircraft.new()
	freed.free()
	_check(not SkillHooks.bloodlust_counts_as_head_on(freed, null)
		and not SkillHooks.bloodlust_counts_as_head_on(42, "aircraft"), "入口拒绝已释放及非对象实参")

func _air_case(host: Node, opts: Dictionary) -> void:
	var label := str(opts)
	var world := TestMode.new()
	host.add_child(world)
	var sp := SurvivorPlayer.new()
	world.add_child(sp)
	sp.set_process(false)
	sp.level = 1
	var killer := _aircraft(world, int(opts.get("team", CombatUnit.TEAM_PLAYER)), Vector2.ZERO)
	var leader := killer
	if bool(opts.get("wing", false)):
		leader = _aircraft(world, CombatUnit.TEAM_PLAYER, Vector2(-6000, 0))
		leader.apply_status(StatusEffects.BLOODLUST, 9.0)
	sp.aircraft = leader
	AircraftRenderer.player_ref = leader
	var stacks: Dictionary = {}
	if not bool(opts.get("no_consumers", false)):
		stacks = {"skill_head_on_perma_hp": 1, "skill_head_on_aoe_fear": 1}
	else:
		world.upgrade_stacks.clear()
	if bool(opts.get("skill", true)): stacks["bloodlust_head_on"] = 1
	if bool(opts.get("first_kill", false)): stacks["skill_kill_bloodlust"] = 1
	killer.set_meta("upgrade_stacks", stacks)
	for uid in stacks: sp.apply_upgrade_to(killer, SurvivorData.upgrade_by_id(uid))
	if bool(opts.get("active", true)): killer.apply_status(StatusEffects.BLOODLUST, 9.0)
	if bool(opts.get("expired", false)):
		StatusEffects.update(killer, 10.0)
	var pos := Vector2(4000, 0)
	if bool(opts.get("natural", false)):
		pos = Vector2(0, -500)
	if bool(opts.get("colocated", false)): pos = Vector2.ZERO
	var victim := _aircraft(world, int(opts.get("victim_team", CombatUnit.TEAM_HOSTILE)), pos)
	if bool(opts.get("natural", false)): victim.heading = PI
	var witness := _aircraft(world, CombatUnit.TEAM_HOSTILE, pos + Vector2(100, 0))
	var ally := _aircraft(world, CombatUnit.TEAM_PLAYER, pos + Vector2(200, 0))
	CombatUnit.all_units = [killer, victim, witness, ally]
	if leader != killer: CombatUnit.all_units.append(leader)
	world.boss_phase = bool(opts.get("boss", false))
	victim.set_meta("no_kill_reward", bool(opts.get("no_reward", false)))
	var spawner := SurvivorSpawner.new()
	world.add_child(spawner)
	spawner.mode = world
	spawner.survivor_player = sp
	spawner.player_aircraft = leader
	var event := {"kills": 0}
	var on_kill := func(_a, _b, _c, _d, _e, _f): event["kills"] += 1
	EventLogger.kill_recorded.connect(on_kill)
	var expected_conversion := bool(opts.get("skill", true)) and bool(opts.get("active", true)) \
		and not bool(opts.get("expired", false)) and killer.is_player_squad() \
		and victim.team == CombatUnit.TEAM_HOSTILE
	var expected_head_on := expected_conversion or bool(opts.get("natural", false))
	var expected_growth := 5.0 if expected_head_on and not bool(opts.get("no_reward", false)) \
		and not bool(opts.get("no_consumers", false)) else 0.0
	victim.take_damage(1000.0, killer, str(opts.get("kind", "missile")))
	_check(victim.is_destroyed and event.kills == 1 and not victim.has_meta("_pending_attacker"),
		"真实致死信号/归因清理 " + label)
	_check(bool(victim.get_meta(SkillHooks.BLOODLUST_HEAD_ON_META, false)) == expected_conversion,
		"致死瞬间快照 " + label)
	_check(is_equal_approx(killer.params.max_hp, 100.0 + expected_growth), "骑士心脏独立一次 " + label)
	_check(witness.has_status(StatusEffects.FEAR) == (expected_head_on and not bool(opts.get("no_consumers", false)))
		and not ally.has_status(StatusEffects.FEAR), "寒颤仅敌方且需持有 " + label)
	if bool(opts.get("first_kill", false)):
		_check(killer.has_status(StatusEffects.BLOODLUST) and not expected_conversion, "第一杀授予嗜血不追溯")
	victim.take_damage(1000.0, killer, "aoe")
	_check(event.kills == 1, "重复伤害不重复派发 " + label)
	EventLogger.kill_recorded.disconnect(on_kill)
	# 跨过状态更新与死亡后的帧：经验只读快照，不再读攻击者状态。
	StatusEffects.update(killer, 20.0)
	var switched := bool(opts.get("switch", false)) or bool(opts.get("free_killer", false))
	if switched:
		sp.aircraft = ally
		spawner.player_aircraft = ally
		AircraftRenderer.player_ref = ally
	if bool(opts.get("free_killer", false)):
		CombatUnit.all_units.erase(killer)
		killer.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().create_timer(0.25).timeout
	spawner._detect_kills()
	var rewards_allowed := not bool(opts.get("no_reward", false)) and not world.boss_phase \
		and int(opts.get("team", 0)) != CombatUnit.TEAM_ALLY and victim.team == CombatUnit.TEAM_HOSTILE
	var xp_expected := (72 if expected_head_on and not bool(opts.get("no_consumers", false)) else 48) \
		if rewards_allowed else 0
	_check(sp.total_xp_gained == xp_expected, "延迟经验快照/禁奖励 " + label)
	if is_instance_valid(killer):
		var base_growth := 5.0 if expected_head_on and leader == killer and not switched \
			and not bool(opts.get("no_reward", false)) and victim.team == CombatUnit.TEAM_HOSTILE else 0.0
		_check(is_equal_approx(killer.params.max_hp, 100.0 + expected_growth + base_growth), "基础成长归实际操控机 " + label)
	spawner._detect_kills()
	_check(sp.total_xp_gained == xp_expected, "重复结算经验不重发 " + label)
	if bool(opts.get("free_killer", false)):
		_check(not is_instance_valid(killer), "来源真实释放后消费到末尾")
	CombatUnit.all_units.clear()
	AircraftRenderer.player_ref = null
	world.queue_free()
	await host.get_tree().process_frame
	_completed += 1

func _surface_case(host: Node) -> void:
	var world := Node2D.new()
	host.add_child(world)
	var killer := _aircraft(world, CombatUnit.TEAM_PLAYER, Vector2.ZERO)
	killer.set_meta("upgrade_stacks", {"bloodlust_head_on": 1, "skill_head_on_perma_hp": 1})
	killer.apply_status(StatusEffects.BLOODLUST, 9.0)
	var ground := GroundUnit.new()
	ground.team = CombatUnit.TEAM_HOSTILE
	world.add_child(ground)
	ground.set_physics_process(false)
	ground.hp = 100.0
	var ship := NavalUnit.new()
	ship.params = NavalParams.new()
	ship.team = CombatUnit.TEAM_HOSTILE
	world.add_child(ship)
	ship.set_physics_process(false)
	ship.hull_hp_max = 100.0
	ship.hull_hp = 100.0
	_check(not SkillHooks.bloodlust_counts_as_head_on(killer, ground)
		and not SkillHooks.bloodlust_counts_as_head_on(killer, ship), "地面海上类型拒绝")
	ground.take_damage(1000.0, killer, "missile")
	ship.take_damage(1000.0, killer, "missile")
	await host.get_tree().process_frame
	_check(ground.is_destroyed and ship.is_destroyed and killer.params.max_hp == 100.0
		and not ground.has_meta(SkillHooks.BLOODLUST_HEAD_ON_META)
		and not ship.has_meta(SkillHooks.BLOODLUST_HEAD_ON_META), "地面海上真实死亡不转换")
	world.queue_free()
	await host.get_tree().process_frame
	_completed += 1

func _aircraft(world: Node2D, team: int, pos: Vector2) -> Aircraft:
	var ac := Aircraft.new()
	ac.params = load("res://resources/default_fighter.tres").duplicate(true)
	ac.params.max_hp = 100.0
	ac.params.armor = 0.0
	ac.params.gun = null
	ac.params.missile = null
	ac.team = team
	ac.position = pos
	world.add_child(ac)
	ac.process_mode = Node.PROCESS_MODE_DISABLED
	ac.hp = 100.0
	ac.heading = 0.0
	ac.altitude = 5500.0
	ac.no_pilot = false
	return ac

func _check(ok: bool, label: String) -> void:
	if ok: _pass += 1
	else: _fail += 1
	print("[BloodlustHeadOn] %s %s" % ["PASS" if ok else "FAIL", label])
