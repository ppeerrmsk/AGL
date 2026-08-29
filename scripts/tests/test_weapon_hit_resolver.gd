extends RefCounted

const WeaponHitResolverScript = preload("res://scripts/weapon_hit_resolver.gd")

## 武器命中共享边界回归：资格门、跨帧 source、目标类型分派、舰船倍率与归因。

class RejectingUnit extends CombatUnit:
	func can_accept_new_hit(_kind: String) -> bool:
		return false


var _pass: int = 0
var _fail: int = 0


func run() -> void:
	print("\n════════ 武器命中结算验证 ════════")
	_test_generic_damage_and_attribution()
	_test_rejected_hit_is_side_effect_free()
	_test_freed_source_is_sanitized()
	_test_ground_warhead_route()
	_test_naval_hull_multiplier()
	_test_aircraft_gun_route()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("════════════════════════════════\n")


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ %s %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])


func _test_generic_damage_and_attribution() -> void:
	var attacker := CombatUnit.new()
	var target := CombatUnit.new()
	target.hp = 100.0
	var accepted: bool = WeaponHitResolverScript.resolve_unit_hit(
		target, 25.0, attacker, "laser", Vector2(10.0, 20.0))
	_check("通用目标统一扣血并写入归因", accepted and is_equal_approx(target.hp, 75.0)
		and target.get_meta("_pending_attacker", null) == attacker
		and target.get_meta("_last_damage_kind", "") == "laser")
	attacker.free()
	target.free()


func _test_rejected_hit_is_side_effect_free() -> void:
	var attacker := CombatUnit.new()
	var target := RejectingUnit.new()
	target.hp = 100.0
	var accepted: bool = WeaponHitResolverScript.resolve_unit_hit(target, 25.0, attacker, "missile")
	_check("主动机动拒绝命中时无扣血无归因", not accepted
		and is_equal_approx(target.hp, 100.0)
		and not target.has_meta("_pending_attacker")
		and not target.has_meta("_last_damage_kind"))
	attacker.free()
	target.free()


func _test_freed_source_is_sanitized() -> void:
	var expired_source := CombatUnit.new()
	var target := CombatUnit.new()
	expired_source.free()
	var accepted: bool = WeaponHitResolverScript.resolve_unit_hit(target, 10.0, expired_source, "rocket")
	_check("跨帧已释放 source 安全折叠为 null", accepted
		and is_equal_approx(target.hp, 90.0)
		and not target.has_meta("_pending_attacker"))
	target.free()


func _test_ground_warhead_route() -> void:
	var attacker := CombatUnit.new()
	attacker.team = CombatUnit.TEAM_PLAYER
	var target := GroundUnit.new()
	target.hp = 500.0
	var accepted: bool = WeaponHitResolverScript.resolve_unit_hit(target, 1.0, attacker, "missile")
	_check("地面软目标导弹仍走一击必杀入口", accepted and target.is_destroyed
		and is_zero_approx(target.hp)
		and int(target.get_meta("kill_attacker_team", -1)) == CombatUnit.TEAM_PLAYER)
	attacker.free()
	target.free()


func _test_naval_hull_multiplier() -> void:
	var attacker := CombatUnit.new()
	var target := NavalUnit.new()
	target.hull_hp_max = 100.0
	target.hull_hp = 100.0
	var accepted: bool = WeaponHitResolverScript.resolve_unit_hit(
		target, 20.0, attacker, "gun", Vector2.ZERO, Vector2.ZERO, 0.15, true)
	_check("机炮命中舰船保留 0.15 船体倍率", accepted
		and is_equal_approx(target.hull_hp, 97.0)
		and target.get_meta("_pending_attacker", null) == attacker
		and target.get_meta("_last_damage_kind", "") == "gun")
	attacker.free()
	target.free()


func _test_aircraft_gun_route() -> void:
	var target := Aircraft.new()
	target.hp = 100.0
	target.bullet_dodge_chance = 0.0
	var accepted: bool = WeaponHitResolverScript.resolve_unit_hit(
		target, 20.0, null, "gun", Vector2.ZERO, Vector2.RIGHT)
	_check("飞机机炮命中保留专用闪避伤害入口", accepted
		and is_equal_approx(target.hp, 80.0)
		and target.get_meta("_last_damage_kind", "") == "gun")
	target.free()
