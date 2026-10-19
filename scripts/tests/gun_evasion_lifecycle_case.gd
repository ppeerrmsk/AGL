extends RefCounted
## 真实 SceneTree 飞行 + 来源终态；独立场景与全量生命周期门复用。
var _fail := 0
var _pass := 0

func run(host: Node, visual: bool = false) -> int:
	var radio := {"count": 0}
	var on_evasion := func(_callsign: String, _team: int) -> void: radio["count"] += 1
	EventLogger.evasion_started.connect(on_evasion)
	var old_player: Variant = AircraftRenderer.player_ref
	var old_units := CombatUnit.all_units.duplicate()
	var world := Node2D.new()
	host.add_child(world)
	var bullets := BulletManager.new()
	world.add_child(bullets)
	var leader := _aircraft(world, CombatUnit.TEAM_PLAYER, Vector2(120, -400), "LEAD")
	var wing := _aircraft(world, CombatUnit.TEAM_PLAYER, Vector2.ZERO, "WING")
	var threat := _aircraft(world, CombatUnit.TEAM_HOSTILE, Vector2(0, 350), "TAIL")
	var target := _aircraft(world, CombatUnit.TEAM_HOSTILE, Vector2(1100, -900), "TARGET")
	target.invulnerable = true
	wing.bullet_manager = bullets
	threat.bullet_manager = bullets
	AircraftRenderer.player_ref = leader
	CombatUnit.all_units = [leader, wing, threat, target]
	var ai := AIController.new()
	ai.aircraft = wing
	ai.enable_combat = true
	ai.squad = Squad.new()
	ai.squad.leader = leader
	ai.squad.members = [leader, wing]
	ai.squad_index = 1
	wing.add_child(ai)
	wing._ai_ref = ai
	wing.use_tactical_planner = true
	wing.set_formation_target(leader, Vector2(100, 100))
	wing.commanded_target = target
	ai.acquire_target(target, AIController.TargetSource.TS_COMMANDED, "gun lifecycle")
	threat.set_combat_target(wing)
	threat.weapon_mode = Aircraft.WeaponMode.GUN
	threat._update_gun_threat_indicator(1.0 / 60.0)
	_check(wing._gun_tailed_attacker_id == threat.get_instance_id(), "正式敌机威胁更新向僚机发布 ID")
	# 真实父 Aircraft 与子 AI 自动 tick，不能靠只调用 helper 的绿灯代替飞行。
	wing.set_physics_process(true)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	_check(ai._gun_evasion.active and ai.is_evading(), "真实 AI 分发进入机炮规避")
	_check(int(radio["count"]) > 0, "正式规避入口发出无线电事件信号")
	_check(not wing.formation_mode and wing.commanded_target == target, "父层退出编队且保留命令")
	if visual:
		var camera := Camera2D.new()
		camera.position = Vector2(200, -100)
		camera.zoom = Vector2(0.75, 0.75)
		world.add_child(camera)
		camera.make_current()
	var max_turn := 0.0
	var max_bullets := 0
	var start_hp := wing.hp
	for frame in range(90):
		# 同一正式机炮执行器、真实弹丸与碰撞；威胁炮手固定机位便于复现。
		threat._update_gun_threat_indicator(1.0 / 60.0)
		AircraftCombatTracking.update_combat(threat, 1.0 / 60.0)
		AircraftWeapons.update_gun(threat, 1.0 / 60.0)
		max_bullets = maxi(max_bullets, bullets.total_bullet_count())
		await host.get_tree().physics_frame
		max_turn = maxf(max_turn, absf(angle_difference(0.0, wing.heading)))
		if visual and frame == 45:
			await host.get_tree().process_frame
			var screenshot := OS.get_environment("TEMP").path_join("agl-gun-evasion-visual.png")
			var saved := host.get_viewport().get_texture().get_image().save_png(screenshot)
			_check(saved == OK, "Visual 截图保存成功")
			print("[GunEvasionVisual] screenshot=%s" % screenshot)
	_check(max_turn > 0.08, "真实飞行产生可测急转（非只改状态）")
	_check(max_bullets > 0, "专项包含真实机炮出弹")
	print("[GunEvasionFlight] turn_deg=%.2f bullets_peak=%d damage_taken=%.2f" % [rad_to_deg(max_turn), max_bullets, start_hp - wing.hp])
	if visual:
		await host.get_tree().create_timer(2.0).timeout
	# 重新建立真实咬尾，让终态发生在规避持有来源 ID 的过程中。
	wing.set_physics_process(false)
	ai.set_physics_process(false)
	wing.position = Vector2.ZERO
	wing.heading = 0.0
	wing.bank_angle = 0.0
	threat.position = Vector2(0, 350)
	threat.heading = 0.0
	threat.weapon_mode = Aircraft.WeaponMode.GUN
	threat.ammo = 100
	threat.combat_target = wing
	ai._gun_evasion.cooldown = 0.0
	if ai.is_evading(): MissileEvasion.exit_evade(ai)
	ai._gun_evasion.cooldown = 0.0
	threat._update_gun_threat_indicator(1.0 / 60.0)
	ai._gun_evasion.tick(ai, 0.05)
	_check(ai._gun_evasion.active, "来源终态前确实持有活跃规避")
	threat.take_damage(10000.0, wing, "missile")
	_check(threat.is_destroyed, "攻击者经过真实伤害进入死亡终态")
	var source_value: Variant = threat
	threat.queue_free()
	await host.get_tree().process_frame
	for i in range(9):
		ai._physics_process_impl(0.05)
		await host.get_tree().physics_frame
	_check(not is_instance_valid(source_value) and not ai._gun_evasion.active and not ai.is_evading()
		and wing._gun_tailed_attacker_id == 0 and not wing._intent_slots.has(ControlIntent.SOURCE_EVADE), "跨释放帧及下一缓存周期后清理 ID/模态/意图")
	_check(ai._current_target == target and wing.commanded_target == target, "来源释放后消费者执行到末尾且保留原任务")
	# 长机被毁时取消本机自保，不让失效编队引用被解引用。
	var next_threat := _aircraft(world, CombatUnit.TEAM_HOSTILE, Vector2(0, 350), "TAIL2")
	next_threat.combat_target = wing
	next_threat.weapon_mode = Aircraft.WeaponMode.GUN
	wing.report_gun_tailed(next_threat)
	ai._gun_evasion.cooldown = 0.0
	ai._gun_evasion.tick(ai, 0.05)
	_check(ai._gun_evasion.active, "长机终态前自保已激活")
	leader.take_damage(10000.0, next_threat, "missile")
	ai._physics_process_impl(0.05)
	_check(not ai._gun_evasion.active and not ai.is_evading(), "长机真实死亡后取消自保")
	EventLogger.evasion_started.disconnect(on_evasion)
	world.queue_free()
	await host.get_tree().process_frame
	CombatUnit.all_units.assign(old_units)
	AircraftRenderer.player_ref = old_player if is_instance_valid(old_player) else null
	print("[GunEvasionLifecycle] pass=%d fail=%d" % [_pass, _fail])
	return _fail

func _aircraft(world: Node2D, team: int, pos: Vector2, callsign: String) -> Aircraft:
	var ac := Aircraft.new()
	ac.params = load("res://resources/default_fighter.tres").duplicate(true)
	SurvivorPlayableSetup.deep_dup_weapons(ac.params)
	ac.params.gun = load("res://resources/weapons/enemy_gun_v5.tres").duplicate()
	ac.params.missile = null
	ac.params.armor = 0.0
	ac.params.gun.spread_angle = 0.0
	ac.team = team
	ac.position = pos
	ac.callsign = callsign
	ac.set_physics_process(false)
	world.add_child(ac)
	ac.set_physics_process(false)
	ac.heading = 0.0
	ac.speed = 180.0
	ac.altitude = 5500.0
	ac.target_altitude = 5500.0
	ac.hp = 100.0
	ac.ammo = 100
	ac.bullet_dodge_chance = 0.0
	if team == CombatUnit.TEAM_PLAYER:
		ac.survivor_bullet_damage_cap = 5.0
		ac.bullet_damage_taken_mult = 0.6
	return ac

func _check(ok: bool, label: String) -> void:
	if ok: _pass += 1
	else: _fail += 1
	print("[GunEvasionLifecycle] %s %s" % ["PASS" if ok else "FAIL", label])
