extends RefCounted

const FactionTransitionScript = preload("res://scripts/events/faction_transition.gd")
const HackedAllyForceScript = preload("res://scripts/survivor/hacked_ally_force.gd")
const AceEventScript = preload("res://scripts/events/ace_reinforcement_event.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 动态阵营转换（事务/黑客/技能互斥） ════════")
	_test_atomic_conversion()
	_test_laser_hack_runtime_conversion()
	_test_squad_cleanup_skips_freed_successor()
	_test_hacked_escort_rebind()
	_test_laser_skill_contract()
	_test_whitetea_arbitration()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _make_aircraft(team: int) -> Aircraft:
	var ac: Aircraft = load("res://scripts/aircraft.gd").new()
	ac.team = team
	ac.params = AircraftParams.new()
	var ai: AIController = load("res://scripts/ai_controller.gd").new()
	ai.aircraft = ac
	ac.add_child(ai)
	return ac


func _test_atomic_conversion() -> void:
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE)
	var observer := _make_aircraft(CombatUnit.TEAM_PLAYER)
	var old_squad := Squad.new()
	old_squad.leader = target
	old_squad.members = [target]
	var target_ai: AIController = target._get_ai_controller()
	target_ai.squad = old_squad
	target_ai.squad_index = 0
	target_ai._current_target = observer
	target.combat_target = observer
	observer.combat_target = target
	observer.commanded_target = target
	observer.radar_targets[target] = 1.0
	observer.escort_guards.append(target)
	observer.flock_members.append(target)
	target.locked_by.append(observer)
	target.is_mission_target = true
	CombatUnit.all_units = [target, observer]
	var signal_count := [0]
	target.faction_changed.connect(func(_old: int, _new: int, _reason: String): signal_count[0] += 1)

	var changed: bool = FactionTransitionScript.convert(target, CombatUnit.TEAM_ALLY, "test")
	_check("首次转换成功", changed, "")
	_check("IFF 转为 ALLY", target.team == CombatUnit.TEAM_ALLY, "")
	_check("任务身份与 token 中和", not target.is_mission_target \
		and int(target.get_meta("token_cost", -1)) == 0, "")
	_check("旧编队解绑", target_ai.squad == null and target not in old_squad.members, "")
	_check("自身火控清空", target.combat_target == null and target_ai._current_target == null, "")
	_check("他方目标/锁定清空", observer.combat_target == null \
		and observer.commanded_target == null and not observer.radar_targets.has(target), "")
	_check("他方强类型护卫/群组缓存清空", target not in observer.escort_guards \
		and target not in observer.flock_members, "")
	_check("faction_changed 只发一次", signal_count[0] == 1, "")
	_check("重复转换幂等", not FactionTransitionScript.convert(target,
		CombatUnit.TEAM_ALLY, "test") and signal_count[0] == 1, "")

	CombatUnit.all_units.clear()
	observer.free()
	target.free()


func _test_laser_hack_runtime_conversion() -> void:
	var source := _make_aircraft(CombatUnit.TEAM_PLAYER)
	var target := _make_aircraft(CombatUnit.TEAM_HOSTILE)
	var observer := _make_aircraft(CombatUnit.TEAM_PLAYER)
	target.set_meta("enemy_type", "uav")
	source.set_meta("upgrade_stacks", {"skill_laser_hack": 1})
	source.combat_target = target
	observer.escort_guards.append(target)
	observer.flock_members.append(target)
	CombatUnit.all_units = [source, target, observer]
	var laser := LaserEquipment.new()
	var ratio: float = laser._advance_hack(source, target, 2.6)
	_check("激光黑客实际完成转换", is_equal_approx(ratio, 1.0) \
		and target.team == CombatUnit.TEAM_ALLY, "")
	_check("激光黑客路径清理强类型缓存", target not in observer.escort_guards \
		and target not in observer.flock_members, "")
	CombatUnit.all_units.clear()
	observer.free()
	target.free()
	source.free()


func _test_squad_cleanup_skips_freed_successor() -> void:
	var old_leader := _make_aircraft(CombatUnit.TEAM_HOSTILE)
	var stale_successor := _make_aircraft(CombatUnit.TEAM_HOSTILE)
	var live_successor := _make_aircraft(CombatUnit.TEAM_HOSTILE)
	var squad := Squad.new()
	squad.leader = old_leader
	squad.members = [old_leader, live_successor]
	squad.leader_successors = [stale_successor, live_successor]
	stale_successor.free()
	old_leader.is_destroyed = true
	squad.cleanup()
	_check("小队清理跳过已释放的继任引用", squad.leader == live_successor, "")
	live_successor.free()
	old_leader.free()


func _test_hacked_escort_rebind() -> void:
	var leader_a := _make_aircraft(CombatUnit.TEAM_PLAYER)
	var leader_b := _make_aircraft(CombatUnit.TEAM_PLAYER)
	var drone := _make_aircraft(CombatUnit.TEAM_ALLY)
	var force = HackedAllyForceScript.new()
	force.set_leader(leader_a)
	force.adopt(drone)
	var ai: AIController = drone._get_ai_controller()
	_check("黑入机保持不可控 ALLY", drone.team == CombatUnit.TEAM_ALLY \
		and not drone.is_player_squad(), "")
	_check("黑入机启用绕长机战斗", ai.simple_ai and ai.enable_combat \
		and ai.orbit_squad_leader and not ai.shield_leader, "")
	_check("初始长机绑定", ai.squad != null and ai.squad.leader == leader_a, "")
	force.set_leader(leader_b)
	_check("切控后改跟新长机", ai.squad.leader == leader_b, "")
	force.shutdown()
	drone.free()
	leader_b.free()
	leader_a.free()


func _test_laser_skill_contract() -> void:
	var damage: Dictionary = {}
	var hack: Dictionary = {}
	for upgrade in SurvivorData.UPGRADES:
		if upgrade.get("id", "") == "skill_laser_damage":
			damage = upgrade
		elif upgrade.get("id", "") == "skill_laser_hack":
			hack = upgrade
	_check("黑客技能已注册且归策士位", not hack.is_empty() \
		and hack.get("axis", "") == "schemer", "")
	_check("两条激光分支双向互斥", damage.get("excludes", []).has("skill_laser_hack") \
		and hack.get("excludes", []).has("skill_laser_damage"), "")
	var laser_params := AircraftParams.new()
	laser_params.equipment.append(LaserEquipment.new())
	_check("取得伤害后黑客不再进池", not SurvivorData.is_upgrade_available_for(
		hack, &"x02", laser_params, {"skill_laser_damage": 1}), "")
	_check("取得黑客后伤害不再进池", not SurvivorData.is_upgrade_available_for(
		damage, &"x02", laser_params, {"skill_laser_hack": 1}), "")
	var mq109 := _make_aircraft(CombatUnit.TEAM_HOSTILE)
	mq109.set_meta("enemy_type", "uav")
	var sentinel := _make_aircraft(CombatUnit.TEAM_HOSTILE)
	sentinel.set_meta("enemy_type", "uav_commander")
	_check("MQ-109 可被黑", LaserEquipment._is_hack_eligible(mq109), "")
	_check("Sentinel 不可被黑", not LaserEquipment._is_hack_eligible(sentinel), "")
	sentinel.free()
	mq109.free()


func _test_whitetea_arbitration() -> void:
	_check("WhiteTea 2→1 触发投降", AceEventScript.should_whitetea_surrender(
		"whitetea", 2, 1, false, false), "")
	_check("同帧全灭不伪造投降", not AceEventScript.should_whitetea_surrender(
		"whitetea", 2, 0, false, false), "")
	_check("其它王牌不投降", not AceEventScript.should_whitetea_surrender(
		"marathon", 2, 1, false, false), "")
	_check("BOSS/撤离阶段不投降", not AceEventScript.should_whitetea_surrender(
		"whitetea", 2, 1, true, false) and not AceEventScript.should_whitetea_surrender(
		"whitetea", 2, 1, false, true), "")


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ ", label, " ", detail)
	else:
		_fail += 1
		printerr("  ✗ ", label, " ", detail)
