extends RefCounted
## 真实 DockPoint 信号、正式 UI 提交和跨帧终态；只省略整个地图/刷怪器初始化。

class FixtureMode:
	extends "res://scripts/survivor/survivor_mode.gd"
	var formal := false
	func _ready() -> void:
		# 与正式 SurvivorMode 开局一致，清理前一个场景/同步单测的演出时间请求。
		Presentation.clear_all()
		process_mode = Node.PROCESS_MODE_DISABLED
	func _exit_tree() -> void:
		pass # 测试宿主只拥有本 fixture，不重置其它 gauntlet 场景的全局状态。
	func archive_enabled() -> bool:
		return formal

var _fail := 0
var _pass := 0
const POINTS := {&"gladiator": 8, &"knight": 8, &"schemer": 8}

func run(host: Node) -> int:
	var owned_before := MetaShop._owned.duplicate(true)
	var player_before: Variant = AircraftRenderer.player_ref
	MetaShop._owned.clear() # 只改内存；不买商品、不保存，结束恢复。
	for branch in ["wingman", "evolution", "repair_level", "repair_axes", "repair_end",
			"repair_locked", "repair_equipped", "repair_placeholder", "wingman_locked", "wingman_full"]:
		await _run_branch(host, branch)
	await _carrier_uses(host)
	await _growth_settlement(host)
	MetaShop._owned = owned_before
	AircraftRenderer.player_ref = player_before if is_instance_valid(player_before) else null
	print("[DockDecision] pass=%d fail=%d" % [_pass, _fail])
	return _fail

func _fixture(host: Node, id: StringName, level: int, points: Dictionary) -> FixtureMode:
	var mode := FixtureMode.new()
	mode._aircraft_scene = preload("res://scenes/aircraft.tscn")
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	mode.add_child(camera)
	var bullets := BulletManager.new()
	bullets.name = "BulletManager"
	mode.add_child(bullets)
	var missiles := MissileManager.new()
	missiles.name = "MissileManager"
	mode.add_child(missiles)
	host.add_child(mode)
	var node := EvolutionSystem.node_of(id)
	var profile := AircraftDB.get_profile(StringName(node["profile"]))
	mode._player_profile = profile
	mode._player_profile_id = profile.id
	var ac := Aircraft.new()
	ac.params = profile.base_params.duplicate(true)
	SurvivorPlayableSetup.deep_dup_weapons(ac.params)
	SurvivorPlayableSetup.apply(ac, profile, false)
	ac.team = CombatUnit.TEAM_PLAYER
	mode.add_child(ac)
	ac.set_meta("evo_node", id)
	ac.set_meta("profile_id", profile.id)
	mode.player_aircraft = ac
	mode.survivor_player = SurvivorPlayer.new()
	mode.add_child(mode.survivor_player)
	mode.survivor_player.aircraft = ac
	mode.survivor_player.level = level
	mode.survivor_player.axis_points = points.duplicate()
	mode._ensure_player_squad()
	mode._spawn_reward_wingman()
	for member in mode._squad_members_alive():
		member.take_damage(20.0, null, "test")
	return mode

func _land(mode: FixtureMode, counts: Dictionary, kind: String = "airfield") -> DockPoint:
	var dock := DockPoint.new()
	dock.dock_kind = kind
	dock.player = mode.player_aircraft
	mode.add_child(dock)
	dock.docked.connect(func(_value: DockPoint) -> void: counts["dock"] += 1)
	dock.docked.connect(mode._on_dock_docked)
	mode.player_aircraft.speed = 0.0
	mode.player_aircraft.g_load = 1.0
	dock._process(DockPoint.HOLD_SEC + 0.01)
	return dock

func _run_branch(host: Node, branch: String) -> void:
	var id: StringName = &"x90" if branch == "repair_end" else (
		&"mig21f13" if branch == "repair_placeholder" else &"f16")
	var level := 1 if branch.begins_with("repair_") and branch not in ["repair_axes", "repair_end"] else 26
	var mode := _fixture(host, id, level, {} if branch == "repair_axes" else POINTS)
	var signature := SurvivorData.signature_upgrade_for_aircraft(id)
	var uid := String(signature.get("id", ""))
	if branch == "repair_equipped":
		mode._apply_upgrade_choice(signature)
	if branch == "wingman_full":
		for i in range(7):
			mode._spawn_reward_wingman()
	var before := mode._squad_members_alive()
	var hp_before: Array[float] = []
	for member in before:
		hp_before.append(member.hp)
	var counts := {"dock": 0, "evolution": 0, "repair": 0, "wingman": 0}
	var dock := _land(mode, counts)
	# all 的同步测试耗时会进入首帧 delta，Timer 可能当帧到期；先跨过布局帧。
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	await host.get_tree().create_timer(0.25, true, false, true).timeout
	var ui := mode._evolution_ui
	_check(counts.dock == 1 and dock.is_spent() and mode._dock_settlement_open,
		branch + ": 正式减速停靠信号到达末尾并消耗机场")
	_check(mode._squad_members_alive().size() == before.size() and _hp_same(before, hp_before),
		branch + ": 打开面板尚未维修或增员")
	ui.evolution_chosen.connect(func(_id: StringName) -> void: counts["evolution"] += 1)
	ui.repair_chosen.connect(func() -> void: counts["repair"] += 1)
	ui.wingman_chosen.connect(func() -> void: counts["wingman"] += 1)
	# 不依赖 UI 禁用：直接伪造错误分支 signal，权威层也必须拒绝。
	var has_exit := EvolutionSystem.has_available_exit(id, level, mode.survivor_player.axis_points)
	if has_exit:
		ui.repair_chosen.emit()
	else:
		ui.evolution_chosen.emit(&"f35")
	_check(not mode._dock_decision_committed and _hp_same(before, hp_before),
		branch + ": 错误整备分支拒绝且无奖励副作用")
	mode._on_settlement_closed()
	_check(mode._dock_settlement_open, branch + ": 无决策关闭不能绕过互斥")
	if branch in ["repair_locked", "wingman_locked"]:
		# 在正式 signal 打开后打开权限检查，避免 fixture 写入生涯/图鉴。
		mode.formal = true
	if branch in ["wingman_locked", "wingman_full"]:
		ui.wingman_chosen.emit()
		_check(mode._dock_settlement_open and not mode._dock_decision_committed
			and mode._squad_members_alive().size() == before.size() and _hp_same(before, hp_before)
			and mode.survivor_player.weapon_inventory.is_empty(), branch + ": 不增员、不维修、不发武器兜底")
		mode.formal = false
	if branch == "wingman":
		ui._wingman_confirm.pressed.emit()
		_check(mode._squad_members_alive().size() == before.size() + 1 and _hp_same(before, hp_before)
			and mode._current_evolution_node_id() == id and mode.upgrade_stacks.is_empty(),
			"僚机选择仅增加一架，旧机 HP/机型/专属不变")
	elif has_exit:
		# 换型后还要重放永久生命增益，维修必须读最终上限。
		mode.player_aircraft.set_meta("head_on_perma_hp_gained", 17.0)
		var target := StringName(EvolutionSystem.exits_of(id)[0]["id"])
		ui._on_tree_node_selected(target)
		ui._evo_confirm.pressed.emit()
		_check(mode._current_evolution_node_id() == target and _full_hp(before)
			and mode._squad_members_alive().size() == before.size()
			and not mode.upgrade_stacks.has(uid), branch + ": 换型重放后全队满血，不增员或领取专属")
	else:
		ui._repair_confirm.pressed.emit()
		var granted := branch not in ["repair_locked", "repair_placeholder"]
		_check(_full_hp(before) and mode._current_evolution_node_id() == id
			and mode._squad_members_alive().size() == before.size()
			and int(mode.upgrade_stacks.get(uid, 0)) == (1 if granted else 0),
			branch + ": 完整维修且专属许可/占位/已有层数正确")
	_check(not mode._dock_settlement_open and mode._dock_decision_committed
		and not mode.is_paused_for_upgrade, branch + ": 权威事务关闭并恢复游戏")
	var count_after := mode._squad_members_alive().size()
	var stacks_after := mode.upgrade_stacks.duplicate(true)
	var node_after := mode._current_evolution_node_id()
	await host.get_tree().create_timer(0.6, true, false, true).timeout
	_check(not host.get_tree().paused and is_equal_approx(Engine.time_scale, 1.0)
		and not ui.visible, branch + ": 退场后 SceneTree 和时间倍率确实恢复 (paused=%s scale=%.3f visible=%s)" % [
			host.get_tree().paused, Engine.time_scale, ui.visible])
	ui.wingman_chosen.emit()
	ui.repair_chosen.emit()
	ui.evolution_chosen.emit(&"f35")
	mode._on_settlement_closed()
	dock.docked.emit(dock)
	_check(mode._squad_members_alive().size() == count_after and mode.upgrade_stacks == stacks_after
		and mode._current_evolution_node_id() == node_after and not mode._dock_settlement_open,
		branch + ": 跨帧重复提交与已消耗机场信号均不重复发奖")
	_check(counts.wingman > 0 and counts.repair > 0 and counts.evolution > 0,
		branch + ": 所有正式信号确实执行到测试观察者")
	var freed_dock: Variant = dock
	dock.queue_free()
	await host.get_tree().process_frame
	mode._on_dock_docked(freed_dock)
	_check(not mode._dock_settlement_open, branch + ": 已释放停靠点晚到实参安全返回")
	mode.formal = false
	mode.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	_check(not is_instance_valid(ui) and not is_instance_valid(dock), branch + ": 退出后面板/停靠点释放")

func _carrier_uses(host: Node) -> void:
	var mode := _fixture(host, &"f16", 1, POINTS)
	mode._zone_data = ZoneData.new(Callable(), false, true)
	mode._zone_data.carrier_uses_left = 2
	var counts := {"dock": 0}
	var dock := _land(mode, counts, "carrier")
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	await host.get_tree().create_timer(0.25, true, false, true).timeout
	mode._evolution_ui._repair_confirm.pressed.emit()
	await host.get_tree().create_timer(0.6, true, false, true).timeout
	dock.docked.emit(dock)
	_check(not mode._dock_settlement_open and mode._zone_data.carrier_uses_left == 1,
		"航母同次着陆迟到信号不消耗第二次机会")
	counts.dock -= 1 # 该次是主动注入的迟到信号；后续仍核对两次真实着陆。
	dock.player.position = Vector2(dock.radius * 2.0, 0)
	dock._process(0.1)
	dock.player.position = Vector2.ZERO
	dock._process(DockPoint.HOLD_SEC + 0.01)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	await host.get_tree().create_timer(0.25, true, false, true).timeout
	mode._evolution_ui._wingman_confirm.pressed.emit()
	_check(counts.dock == 2 and mode._zone_data.carrier_uses_left == 0
		and mode._squad_members_alive().size() == 3, "航母两次停靠分别决策并扣次")
	dock.docked.emit(dock)
	_check(not mode._dock_settlement_open and mode._zone_data.carrier_uses_left == 0,
		"航母次数耗尽后拒绝迟到停靠")
	await host.get_tree().create_timer(0.6, true, false, true).timeout
	_check(not host.get_tree().paused and is_equal_approx(Engine.time_scale, 1.0),
		"航母两次退场后恢复真实游戏时间")
	mode.queue_free()
	await host.get_tree().process_frame

func _growth_settlement(host: Node) -> void:
	var mode := _fixture(host, &"f16", 26, POINTS)
	var growth := EvolutionGrowthBenchmark.new()
	growth._mode = mode
	growth.route_nodes = ["f16", "f35"]
	await growth._try_fixed_route_evolution()
	_check(growth._route_index == 1 and mode._current_evolution_node_id() == &"f35"
		and _full_hp(mode._squad_members_alive()), "成长基准经过正式停靠决策完成进化和完整维修")
	await host.get_tree().create_timer(0.6, true, false, true).timeout
	_check(not host.get_tree().paused and not mode._evolution_ui.visible,
		"成长基准结算后世界继续运行，入场不覆盖退场")
	mode.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame

func _hp_same(members: Array, values: Array[float]) -> bool:
	for i in range(members.size()):
		if not is_equal_approx(members[i].hp, values[i]):
			return false
	return true

func _full_hp(members: Array) -> bool:
	return members.all(func(ac: Aircraft) -> bool: return is_equal_approx(ac.hp, ac.params.max_hp))

func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("[DockDecision] %s %s" % ["PASS" if ok else "FAIL", label])
