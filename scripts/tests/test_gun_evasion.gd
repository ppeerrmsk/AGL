extends RefCounted
## 机炮自保行为回归；真实 SceneTree 终态另由 gun_evasion_lifecycle_case 覆盖。
var _pass := 0
var _fail := 0
var root: Node2D
var leader: Aircraft
var wing: Aircraft
var attacker: Aircraft
var target: Aircraft
var ai: AIController

func run() -> void:
	_setup()
	_check(AircraftWeapons.is_gun_tailed_by(attacker, wing), "夹击者具有正式有效火控解")
	wing.report_gun_tailed(attacker)
	_check(ai._gun_evasion.tick(ai, 0.05), "自己攻击 A、被 B 咬尾时主动自保")
	_check(ai.is_evading() and not wing.formation_mode and wing.evasion_mode, "编队退出、共享 EVADE 与武器静默同入")
	_check(wing.commanded_target == target and ai._current_target == target, "命令与目标所有权保留")
	var original_dir: Vector2 = ai._gun_evasion.direction
	wing.bank_angle = -1.0
	MissileEvasion.process_evade(ai, 0.2)
	_check(ai._gun_evasion.direction == original_dir, "坡度变动不会反复换 break 方向")
	wing._resolve_intents(0.05)
	_check(is_equal_approx(wing.target_speed_kmh, AircraftPhysics.effective_corner_speed_kmh(wing))
		and wing.is_afterburner, "意图仲裁提交真实角点速度与加力")
	attacker.global_position = Vector2(0, -1000)
	for i in range(5):
		MissileEvasion.process_evade(ai, 0.2)
	_check(not ai.is_evading() and not wing.evasion_mode and not wing._intent_slots.has(ControlIntent.SOURCE_EVADE), "脱险清模态与 sticky 槽")
	_check(wing.combat_target == target and ai._state == AIController.AIState.ENGAGE, "脱险恢复原攻击对象")
	_check(not ai._gun_evasion.tick(ai, 0.05), "退出冷却阻止立即重入")
	_restart()
	for i in range(31):
		if ai.is_evading():
			MissileEvasion.process_evade(ai, 0.1)
	_check(not ai.is_evading(), "持续咬尾也受 3 秒上限约束")
	_restart()
	ai.manual_control = true
	_check(not ai.is_evading() and not ai._gun_evasion.active and not wing._intent_slots.has(ControlIntent.SOURCE_EVADE), "切控在 setter 当场撤销自保")
	_check(wing.commanded_target == target, "手控接管不丢玩家命令")
	ai.manual_control = false
	_restart()
	var cobra := CobraManeuver.new()
	wing.add_child(cobra)
	cobra._ready()
	_check(cobra.activate(), "通过正式入口启动眼镜蛇机动")
	MissileEvasion.process_evade(ai, 0.05)
	_check(not ai._gun_evasion.active and not ai.is_evading() and cobra.is_active,
		"眼镜蛇接管时只撤机炮规避，不打断特殊机动")
	cobra.free()
	# 下一用例独立验证真实导弹接管，不继承眼镜蛇用例留下的免疫窗口。
	wing.missile_phase_timer = 0.0
	wing._lock_immunity_timer = 0.0
	_restart()
	ai.set_event_directive(AIDirective.new())
	_check(not ai.is_evading() and not ai._gun_evasion.active, "事件 directive 接管当场撤销自保")
	ai.set_event_directive(null)
	_restart()
	var mm := MissileManager.new()
	root.add_child(mm)
	wing.missile_manager = mm
	var missile := Missile.new()
	missile.team = CombatUnit.TEAM_HOSTILE
	missile.target = wing
	missile.position = Vector2(0, 150)
	missile.heading = 0.0
	missile.speed = 1100.0
	missile.is_active = true
	mm.add_child(missile)
	ai.evade_missiles = true
	MissileEvasion.process_evade(ai, 0.05)
	_check(ai.is_evading() and not ai._gun_evasion.active, "真导弹接管且公共 EVADE 不短暂退出")
	missile.free()
	MissileEvasion.exit_evade(ai)
	for invalid in ["front", "range", "altitude", "empty", "manual", "ally", "wrong_target"]:
		_reset_geometry()
		match invalid:
			"front": attacker.position = Vector2(0, -250)
			"range": attacker.position = Vector2(0, 5000)
			"altitude": attacker.altitude = 8000.0
			"empty": attacker.ammo = 0
			"manual": ai.manual_control = true
			"ally": attacker.team = CombatUnit.TEAM_PLAYER
			"wrong_target": attacker.combat_target = leader
		wing.report_gun_tailed(attacker)
		ai._gun_evasion.cooldown = 0.0
		_check(not ai._gun_evasion.tick(ai, 0.05), "非有效咬尾不脱队：%s" % invalid)
	root.free()
	print("[GunEvasion] pass=%d fail=%d" % [_pass, _fail])

func _setup() -> void:
	root = Node2D.new()
	leader = _aircraft(CombatUnit.TEAM_PLAYER, Vector2(100, -400))
	wing = _aircraft(CombatUnit.TEAM_PLAYER, Vector2.ZERO)
	attacker = _aircraft(CombatUnit.TEAM_HOSTILE, Vector2(0, 250))
	target = _aircraft(CombatUnit.TEAM_HOSTILE, Vector2(1000, -1000))
	ai = AIController.new()
	ai.aircraft = wing
	wing._ai_ref = ai
	wing.add_child(ai)
	ai.squad = Squad.new()
	ai.squad.leader = leader
	ai.squad.members = [leader, wing]
	ai.squad_index = 1
	ai.enable_combat = true
	wing.use_tactical_planner = true
	wing.set_formation_target(leader, Vector2(100, 100))
	wing.commanded_target = target
	ai.acquire_target(target, AIController.TargetSource.TS_COMMANDED, "gun evasion test")
	_reset_geometry()

func _aircraft(team: int, pos: Vector2) -> Aircraft:
	var ac := Aircraft.new()
	ac.params = AircraftParams.new()
	ac.params.gun = load("res://resources/weapons/enemy_gun_v5.tres").duplicate()
	ac.team = team
	ac.position = pos
	ac.heading = 0.0
	ac.altitude = 5500.0
	ac.speed = 180.0
	ac.hp = 100.0
	ac.ammo = 100
	root.add_child(ac)
	return ac

func _reset_geometry() -> void:
	ai.manual_control = false
	wing.position = Vector2.ZERO
	wing.heading = 0.0
	attacker.position = Vector2(0, 250)
	attacker.heading = 0.0
	attacker.altitude = wing.altitude
	attacker.team = CombatUnit.TEAM_HOSTILE
	attacker.ammo = 100
	attacker.combat_target = wing
	attacker.weapon_mode = Aircraft.WeaponMode.GUN

func _restart() -> void:
	if ai.is_evading():
		MissileEvasion.exit_evade(ai)
	_reset_geometry()
	ai._gun_evasion.cooldown = 0.0
	wing.report_gun_tailed(attacker)
	ai._gun_evasion.tick(ai, 0.05)

func _check(ok: bool, label: String) -> void:
	if ok: _pass += 1
	else: _fail += 1
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
