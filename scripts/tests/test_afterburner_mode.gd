extends RefCounted

const SurvivorModeScript := preload("res://scripts/survivor/survivor_mode.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 加力模式 v6 验收 ════════")
	_test_state_machine_and_manual_cancel()
	_test_roguelite_skill_unification()
	_test_weak_squad_snapshot_cleanup()
	_test_status_bar_feedback()
	_test_input_command_classification()
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_pass, _fail])


func _test_state_machine_and_manual_cancel() -> void:
	var fixture := _make_squad_fixture()
	var leader: Aircraft = fixture["leader"]
	var wingman: Aircraft = fixture["wingman"]
	var charge := AfterburnerCharge.new()
	charge.charge = 4.0

	_check("有能量时可启动且 Squad 快照全队生效",
		charge.activate(leader) and charge.is_active()
		and leader.is_afterburner_mode_active() and wingman.is_afterburner_mode_active())
	var speed_before := leader.speed
	var target_speed_before := leader.target_speed_kmh
	var charge_before := charge.charge
	_check("手动世界指令从统一入口取消并转入充能",
		charge.cancel_for_manual_command() and not charge.is_active()
		and charge.is_available() and not leader.is_afterburner_mode_active()
		and not wingman.is_afterburner_mode_active() and not leader.evasion_mode)
	_check("取消不重写当前速度、目标速度或剩余能量",
		is_equal_approx(leader.speed, speed_before)
		and is_equal_approx(leader.target_speed_kmh, target_speed_before)
		and is_equal_approx(charge.charge, charge_before))
	charge.update(1.0)
	_check("取消后的下一驱动帧按基线开始充能",
		is_equal_approx(charge.charge, charge_before + AfterburnerCharge.CHARGE_RATE))
	_check("充能态取消为幂等 no-op", not charge.cancel_for_manual_command())
	_free_fixture(fixture)


func _test_roguelite_skill_unification() -> void:
	var fixture := _make_squad_fixture()
	var leader: Aircraft = fixture["leader"]
	var wingman: Aircraft = fixture["wingman"]
	for member in [leader, wingman]:
		member.params.gun = GunParams.new()
		member.params.gun.max_ammo = 100
		member.params.missile = MissileParams.new()
		member.params.missile.max_count = 2
		member.ammo = 0
		member.missiles_remaining = 0
		member.evasion_modifiers["cruise_speed_mult"] = 1.4
		member.evasion_modifiers["weapon_cd_mult"] = 0.5
		member.evasion_overstock_interval = 1.0
		member.evasion_stealth_active = true
		member.ab_gun_regen_per_sec = 25.0

	var charge := AfterburnerCharge.new()
	_check("肉鸽联动样本可启动", charge.activate(leader))
	_check("全队超频加力与蓄势狂暴同拍生效",
		is_equal_approx(AircraftPhysics.effective_max_speed_kmh(leader), 2520.0)
		and is_equal_approx(AircraftPhysics.effective_max_speed_kmh(wingman), 2520.0)
		and is_equal_approx(leader.cd_rate("weapon"), 2.0)
		and is_equal_approx(wingman.cd_rate("weapon"), 2.0))
	for member in [leader, wingman]:
		member._update_evasion(2.1)
		AircraftWeapons.update_gun(member, 1.0)
	_check("弹仓过载/雾隐机动/加力供弹覆盖长机与僚机",
		leader.missiles_remaining == 1 and wingman.missiles_remaining == 1
		and leader._in_evasion_stealth and wingman._in_evasion_stealth
		and leader.ammo == 25 and wingman.ammo == 25)
	_check("TORP 与 WMN 共用窗口载荷门",
		AircraftWeapons.afterburner_payload_enabled(leader)
		and AircraftWeapons.afterburner_payload_enabled(wingman))

	charge.deactivate(&"skill_test")
	_check("退出窗口对称收回全队技能与派生状态",
		not leader.is_afterburner_mode_active() and not wingman.is_afterburner_mode_active()
		and not leader._in_evasion_stealth and not wingman._in_evasion_stealth
		and is_equal_approx(leader.cd_rate("weapon"), 1.0)
		and is_equal_approx(wingman.cd_rate("weapon"), 1.0))
	leader.is_afterburner = true
	leader.params.loyal_wingman = LoyalWingmanParams.new()
	leader.ammo = 0
	AircraftWeapons.update_gun(leader, 1.0)
	AircraftWeapons.update_loyal_wingman(leader, 0.0)
	_check("物理 AB 不冒充肉鸽加力技能或专属载荷",
		leader.ammo == 0 and leader._alive_drones.is_empty()
		and not AircraftWeapons.afterburner_payload_enabled(leader))
	_free_fixture(fixture)


func _test_weak_squad_snapshot_cleanup() -> void:
	var fixture := _make_squad_fixture()
	var leader: Aircraft = fixture["leader"]
	var wingman: Aircraft = fixture["wingman"]
	var charge := AfterburnerCharge.new()
	_check("弱引用会话可启动", charge.activate(leader))
	wingman.free()
	fixture["wingman"] = null
	charge.update(0.1)
	charge.deactivate(&"test_cleanup")
	_check("成员释放后仍能对称退出且不残留强会话引用",
		not charge.is_active() and charge._member_refs.is_empty()
		and charge._leader_ref == null and not leader.is_afterburner_mode_active())
	_free_fixture(fixture)


func _test_status_bar_feedback() -> void:
	var ac := _make_aircraft("STATUS")
	var ids: Array[StringName] = []
	for entry in AircraftRenderer.status_label_entries(ac):
		ids.append(StringName(entry.get("id", &"")))
	_check("未加力时状态栏不伪造提示", &"afterburner" not in ids)
	ac.set_afterburner_mode_active(true)
	ids.clear()
	var label := ""
	for entry in AircraftRenderer.status_label_entries(ac):
		ids.append(StringName(entry.get("id", &"")))
		if StringName(entry.get("id", &"")) == &"afterburner":
			label = String(entry.get("text", ""))
	_check("加力激活时状态栏显示明确 AFTERBURNER 行",
		&"afterburner" in ids and label == "AFTERBURNER")
	ac.free()


func _test_input_command_classification() -> void:
	_check("位置/攻击轮盘命令会取消加力",
		SurvivorModeScript._wheel_command_steers_aircraft("regroup")
		and SurvivorModeScript._wheel_command_steers_aircraft("assault"))
	_check("纯战术开关不误取消加力",
		not SurvivorModeScript._wheel_command_steers_aircraft("auto_engage")
		and not SurvivorModeScript._wheel_command_steers_aircraft("formation"))


func _make_squad_fixture() -> Dictionary:
	var leader := _make_aircraft("LEAD")
	var wingman := _make_aircraft("WING")
	var squad := Squad.new()
	squad.leader = leader
	squad.members = [leader, wingman]
	_bind_squad(leader, squad, true)
	_bind_squad(wingman, squad, false)
	return {"leader": leader, "wingman": wingman, "squad": squad}


func _make_aircraft(callsign: String) -> Aircraft:
	var ac := Aircraft.new()
	ac.params = AircraftParams.new()
	ac.params.max_hp = 100.0
	ac.params.max_speed = 1800.0
	ac.params.cruise_speed = 900.0
	ac.params.acceleration = 50.0
	ac.hp = 100.0
	ac.callsign = callsign
	ac.speed = 320.0
	ac.target_speed_kmh = 1500.0
	ac.team = CombatUnit.TEAM_PLAYER
	return ac


func _bind_squad(ac: Aircraft, squad: Squad, manual: bool) -> void:
	var ai := AIController.new()
	ai.aircraft = ac
	ai.squad = squad
	ai.manual_control = manual
	ac.add_child(ai)
	ac._ai_ref = ai


func _free_fixture(fixture: Dictionary) -> void:
	for key in ["leader", "wingman"]:
		var value: Variant = fixture.get(key)
		if typeof(value) == TYPE_OBJECT and is_instance_valid(value):
			(value as Aircraft).free()


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ ", label)
	else:
		_fail += 1
		print("  ✗ ", label)
