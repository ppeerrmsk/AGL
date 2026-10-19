extends RefCounted

const Controller = preload("res://scripts/survivor/orion_final_form.gd")
const Laser = preload("res://scripts/survivor/orion_fang_laser.gd")
var _fail := 0
var _signals: Array[String] = []

class VictoryProbe extends BossEncounterEvent:
	var victory_count := 0
	func _on_victory() -> void:
		victory_count += 1
		super._on_victory()


func run(root: Node) -> int:
	var world := Node2D.new()
	root.add_child(world)
	var manager := MissileManager.new()
	world.add_child(manager)
	var player := _aircraft(world, CombatUnit.TEAM_PLAYER, Vector2(0, -1000), "TEST PLAYER")
	var controller := Controller.new()
	var previous_units: Array = CombatUnit.all_units.duplicate()
	_check(controller.spawn(Callable(self, "_create_enemy").bind(world), player, manager,
		Vector2.ZERO, 0.0), "真实三机创建")
	for ac in controller.get_members():
		ac.set_physics_process(false)
	CombatUnit.all_units.assign([player] + controller.get_members())
	controller.engage()
	controller._rail_cooldown = 100.0
	controller.update(0.01)
	_check(controller.lock_ids.is_empty(), "接战前三秒不提前锁定")
	controller.update(3.0)
	_check(controller.lock_ids.size() == 10, "对真实玩家建立十次锁定")
	controller.update(6.1)
	controller.update(0.01)
	_check(controller._owned_missile_ids.size() == 1, "正式管理器生成首发 ADMM")
	var missile: Missile = instance_from_id(controller._owned_missile_ids[0]) as Missile \
		if not controller._owned_missile_ids.is_empty() else null
	if missile != null:
		missile.set_physics_process(false)
		var origin := missile.global_position
		for _i in range(3):
			missile._physics_process(0.016)
		_check(missile.global_position.is_equal_approx(origin), "空射爬升不沿地图北向平移")
		_check(missile.altitude > 5500.0, "垂发使用虚拟高度")
		missile.vls_phase = 2
		missile.age = 2.0
		missile.is_flare_jammed = true
		missile._physics_process(0.016)
		_check(not missile.has_guidance, "主动雷达不绕过诱饵状态")
	var capacity_probe := Controller.new()
	capacity_probe._admm_phase = 1
	capacity_probe.lock_ids.assign(controller.lock_ids)
	var capacity_missiles: Array[Missile] = []
	for _index in range(7):
		var extra := manager.spawn_missile(controller.body(), player, controller._admm)
		extra.set_physics_process(false)
		capacity_missiles.append(extra)
		capacity_probe._owned_missile_ids.append(extra.get_instance_id())
	capacity_probe._update_admm(controller.body(), 0.01)
	_check(capacity_probe._admm_phase == 1 and capacity_probe.lock_ids.size() == 10,
		"7枚在飞时保留十发锁定并等待整轮容量")
	capacity_missiles[0].destroy_from_intercept(false)
	capacity_probe._update_admm(controller.body(), 0.01)
	_check(capacity_probe._admm_phase == 2 and capacity_probe._launch_queue.size() == 10,
		"6枚在飞时完整十发进入发射队列")
	for extra in capacity_missiles:
		extra.destroy_from_intercept(false)
	var fang: Aircraft = controller.get_members()[1]
	fang.global_position = Vector2.ZERO
	fang.heading = 0.0
	player.global_position = Vector2(0, -700)
	var laser: RefCounted = controller.lasers[0]
	laser.phase = Laser.Phase.ACTIVE
	laser.remaining = 6.0
	var units: Array = [player]
	var hp_before := player.hp
	laser.update(0.01, units, [], {})
	_check(is_equal_approx(player.hp, hp_before - 10.0), "光剑通过正式伤害入口扣 10HP")
	laser.update(0.4, units, [], {})
	_check(is_equal_approx(player.hp, hp_before - 10.0), "停留不足一秒不重复扣血")
	laser.update(0.61, units, [], {})
	_check(is_equal_approx(player.hp, hp_before - 20.0), "持续接触每秒扣血")
	var friendly := manager.spawn_missile(controller.body(), player, controller._admm)
	var hostile := manager.spawn_missile(player, fang, controller._admm)
	for projectile in [friendly, hostile]:
		projectile.set_physics_process(false)
		projectile.global_position = Vector2(0, -500)
	laser.update(0.01, [], [friendly, hostile], {})
	_check(friendly.is_active and not hostile.is_active, "真实光剑只拦敌弹，保留 ORION 同阵营弹")
	_check(laser.intercept_points.size() == 1, "真实拦截产生一次可见爆点快照")
	friendly.destroy_from_intercept(false)
	player.team = Controller.TEAM
	controller._cancel_invalid_slots(controller.body())
	_check(controller.lock_ids.is_empty() and controller._launch_queue.is_empty(), "目标变友军后取消全部未射锁定，不暗转目标")
	player.team = CombatUnit.TEAM_PLAYER
	fang.take_damage(10000.0, player, "railgun")
	laser.update(0.1, units, [], {})
	_check(laser.source_id == 0 and laser._contacts.is_empty(), "FANG 真死亡立即收剑并清接触表")
	EventLogger.kill_recorded.connect(_on_kill)
	var encounter := TheCrucibleEncounter.new()
	encounter.active = true
	encounter._engaged = true
	encounter.orion_started = true
	encounter.orion = controller
	encounter._spawned_profile_count = encounter.PROFILE_ORDER.size()
	var event := VictoryProbe.new(Vector2.ZERO, 0.0, "desert")
	event.active = true
	event.encounter = encounter
	event.phase = BossEncounterEvent.Phase.ENGAGED
	event._was_active = true
	_check(not controller.get_members()[2].is_destroyed, "斩首前另一架 FANG 仍存活")
	var host: Aircraft = controller.body()
	host.take_damage(10000.0, player, "railgun")
	_check(host.is_destroyed and _signals.has("ORION"), "本体致死走真实归因信号")
	host.queue_free()
	await root.get_tree().process_frame
	event._update(1.1)
	_check(controller.defeated and not controller.active, "越过释放帧与缓存 tick 后进入终态")
	_check(event.phase == BossEncounterEvent.Phase.VICTORY and not event.active
		and event.victory_count == 1, "正式遭遇事件在 FANG 存活时只胜利一次")
	event._update(0.6)
	_check(event.victory_count == 1, "终态后再次消费不重复胜利")
	event._finish()
	_check(controller.lock_ids.is_empty() and controller._launch_queue.is_empty()
		and controller._owned_missile_ids.is_empty(), "终态取消预警和待射/在途弹")
	controller.cleanup(true)
	controller.cleanup(true)
	await root.get_tree().process_frame
	controller.update(0.6)
	_check(controller._overlay_id == 0, "重复 cleanup 与后续消费者完整返回")
	EventLogger.kill_recorded.disconnect(_on_kill)
	CombatUnit.all_units.clear()
	for raw: Variant in previous_units:
		if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is CombatUnit:
			CombatUnit.all_units.append(raw)
	world.queue_free()
	await root.get_tree().process_frame
	print("[ORION lifecycle] failures=%d" % _fail)
	return _fail


func _create_enemy(_type: int, position: Vector2, heading: float, world: Node2D) -> Aircraft:
	var ac := _aircraft(world, CombatUnit.TEAM_HOSTILE, position, "TEST ENEMY")
	ac.heading = deg_to_rad(heading)
	return ac


func _aircraft(world: Node2D, team: int, position: Vector2, callsign: String) -> Aircraft:
	var ac := Aircraft.new()
	ac.params = preload("res://resources/default_fighter.tres").duplicate(true)
	ac.params.armor = 0.0
	ac.params.gun = null
	ac.params.missile = null
	ac.params.equipment.clear()
	ac.team = team
	ac.position = position
	ac.callsign = callsign
	world.add_child(ac)
	ac.set_physics_process(false)
	ac.altitude = 5500.0
	ac.target_altitude = 5500.0
	ac.flat_altitude = true
	ac.hp = 500.0
	return ac


func _on_kill(_killer: String, victim: String, _weapon: String,
		_killer_team: int, _victim_team: int, _voiced: bool) -> void:
	_signals.append(victim)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fail += 1
	print("[ORION lifecycle] %s %s" % ["PASS" if ok else "FAIL", label])
