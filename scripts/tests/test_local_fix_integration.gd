extends RefCounted

## 2026-08-15 本地分叉修复整合契约测试。

class CloudWeather:
	extends Node
	var density: float = 1.0

	func sample_density(_pos: Vector2) -> float:
		return density

	func sample_obscurant_density(_pos: Vector2, _altitude: float) -> float:
		return density


var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 本地修复整合测试 ════════")
	_test_engagement_range_contract()
	_test_radar_capability_gate()
	_test_cd_rate_and_boundary_stability()
	_test_cloud_overload_status_path()
	_test_commander_aura_runtime_fields()
	_test_evasion_motion_runs_once()
	_test_modifier_trace_restores_state()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])


func _params() -> AircraftParams:
	var params := AircraftParams.new()
	params.max_hp = 100.0
	params.max_g = 9.0
	params.max_g_structural = 12.0
	params.roll_rate = 4.0
	params.max_speed = 2000.0
	params.cruise_speed = 900.0
	params.acceleration = 50.0
	params.deceleration = 80.0
	params.stall_speed_base = 220.0
	params.afterburner_thrust_mult = 1.5
	return params


func _aircraft(team: int = CombatUnit.TEAM_PLAYER) -> Aircraft:
	var ac := Aircraft.new()
	ac.team = team
	ac.params = _params()
	ac.hp = ac.params.max_hp
	ac.altitude = 10000.0
	return ac


func _test_engagement_range_contract() -> void:
	var ai := AIController.new()
	var ac := _aircraft()
	var target := _aircraft(CombatUnit.TEAM_HOSTILE)
	ai.aircraft = ac
	_check("独立 AI 不豁免雷达距脱离", not ai.is_range_disengage_exempt())
	ai._squad_free_engaging = true
	_check("自主小队交战豁免雷达距脱离", ai.is_range_disengage_exempt())
	ai._squad_free_engaging = false
	ai._squad_attacking_leader_target = true
	_check("协同小队交战豁免雷达距脱离", ai.is_range_disengage_exempt())
	ai._squad_attacking_leader_target = false
	ac.commanded_target = target
	ai._current_target = target
	_check("玩家点名契约仍豁免", ai.is_range_disengage_exempt())
	ai.free()
	ac.free()
	target.free()


func _test_radar_capability_gate() -> void:
	var params := _params()
	_check("纯机炮/无对空武器不发起主雷达锁定", not params.has_lock_capable_weapon())
	params.secondary_missile = MissileParams.new()
	_check("只有副槽导弹仍不计主雷达能力", not params.has_lock_capable_weapon())
	params.missile = MissileParams.new()
	_check("主 AAM 计入主雷达能力", params.has_lock_capable_weapon())
	params.missile = null
	var railgun := RailgunEquipment.new()
	params.equipment.clear()
	params.equipment.append(railgun)
	_check("railgun 计入主雷达能力", params.has_lock_capable_weapon())
	var laser := LaserEquipment.new()
	laser.can_target_aircraft = false
	params.equipment.clear()
	params.equipment.append(laser)
	_check("对地 laser 不计主雷达能力", not params.has_lock_capable_weapon())
	laser.can_target_aircraft = true
	_check("对空 laser 计入主雷达能力", params.has_lock_capable_weapon())


func _test_cd_rate_and_boundary_stability() -> void:
	var ac := _aircraft()
	ac.evasion_modifiers["weapon_cd_mult"] = 0.5
	ac.evasion_modifiers["flare_cd_mult"] = 0.5
	ac.evasion_modifiers["missile_reload_mult"] = 0.25
	ac.cloud_weapon_cd_mult = 0.5
	ac.cloud_state = 2
	ac._fire_cooldown = 4.0
	ac.set_evasion_mode(true)
	_check("切换模式不改写运行中 CD", is_equal_approx(ac._fire_cooldown, 4.0))
	_check("规避×云中武器 CD rate 乘法叠加", is_equal_approx(ac.cd_rate("weapon"), 4.0))
	_check("规避 flare rate 生效", is_equal_approx(ac.cd_rate("flare"), 2.0))
	_check("规避导弹装填 rate 生效", is_equal_approx(ac.cd_rate("missile_reload"), 4.0))
	ac.set_evasion_mode(false)
	_check("退出模式仍不改写运行中 CD", is_equal_approx(ac._fire_cooldown, 4.0))
	ac.free()


func _test_cloud_overload_status_path() -> void:
	var ac := _aircraft()
	ac.cloud_overload_active = true
	ac.set_meta("upgrade_stacks", {SkillHooks.SKILL_OVERLOAD_TO_BLOODLUST: 1})
	var weather := CloudWeather.new()
	ac._update_cloud_state(0.21, weather)
	_check("云中超载进入 timed status", ac.status_effects.has(StatusEffects.OVERLOAD))
	_check("云中超载触发嗜血联动", ac.status_effects.has(StatusEffects.BLOODLUST))
	var remaining := float(ac.status_effects.get(StatusEffects.OVERLOAD, 0.0))
	weather.density = 0.0
	ac._update_cloud_state(0.21, weather)
	_check("出云不主动删除其它 OVERLOAD 时长",
		ac.status_effects.has(StatusEffects.OVERLOAD)
		and is_equal_approx(float(ac.status_effects[StatusEffects.OVERLOAD]), remaining))
	weather.free()
	ac.free()


func _test_commander_aura_runtime_fields() -> void:
	var commander := _aircraft(CombatUnit.TEAM_HOSTILE)
	var member := _aircraft(CombatUnit.TEAM_HOSTILE)
	member.global_position = Vector2(100.0, 0.0)
	var commander_ai := AIController.new()
	commander_ai.aircraft = commander
	commander.add_child(commander_ai)
	var member_ai := AIController.new()
	member_ai.aircraft = member
	member_ai.aggression = 0.2
	member.add_child(member_ai)
	var squad := Squad.new()
	squad.leader = commander
	squad.members = [commander, member]
	commander_ai.squad = squad
	member_ai.squad = squad
	var aura := CommanderAura.new()
	aura._commander = commander
	var base_max_g := member.params.max_g
	var base_speed := member.params.max_speed
	aura._scan_and_buff()
	_check("光环不改永久 params", is_equal_approx(member.params.max_g, base_max_g)
		and is_equal_approx(member.params.max_speed, base_speed))
	_check("光环写运行时字段", member.aura_buff_owner == commander
		and is_equal_approx(member.aura_max_g_add, CommanderAura.BUFF_MAX_G_ADD)
		and is_equal_approx(AircraftPhysics.base_max_speed_kmh(member),
			base_speed * CommanderAura.BUFF_SPEED_MULT))
	squad.members = [commander]
	aura._scan_and_buff()
	_check("离队后全量重算撤除光环", member.aura_buff_owner == null
		and is_equal_approx(member.aura_speed_mult, 1.0)
		and is_equal_approx(member_ai.aggression, 0.2))
	aura.free()
	commander.free()
	member.free()


func _test_evasion_motion_runs_once() -> void:
	var ac := _aircraft()
	ac.use_tactical_preference = true
	ac.evasion_mode = true
	ac.rear_aura_slow_radius_px = 100.0
	ac.jam_aura_radius_px = 100.0
	ac._update_evasion(0.1)
	_check("双光环下规避走位只推进一次", is_equal_approx(ac._evasion_sway_timer, 0.1))
	ac.free()


func _test_modifier_trace_restores_state() -> void:
	var ac := _aircraft()
	ac.aura_speed_mult = 1.5
	ac.status_overload_active = true
	ac.is_afterburner = true
	var before := [ac.aura_speed_mult, ac.status_overload_active, ac.is_afterburner]
	var rows := ModifierTrace.explain(ac)
	var found_speed := false
	for row in rows:
		if row["stat"] == "max_speed_kmh":
			found_speed = float(row["final"]) > float(row["base"])
			break
	_check("ModifierTrace 能解释速度变化", found_speed)
	_check("ModifierTrace 完整还原运行时状态", is_equal_approx(ac.aura_speed_mult, before[0])
		and ac.status_overload_active == before[1] and ac.is_afterburner == before[2])
	ac.free()
