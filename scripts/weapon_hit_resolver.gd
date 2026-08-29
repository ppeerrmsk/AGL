class_name WeaponHitResolver
extends RefCounted
##
## 武器命中结算的共享边界。
##
## 弹丸管理器仍负责碰撞、距离衰减、闪避与表现；本模块只负责：
##   1. 命中资格；2. 跨帧攻击者引用清洗；3. 击杀归因；4. 按目标类型选择伤害入口。
## 保持无状态、无分配，供 BulletManager / MissileManager 的热路径直接调用。


static func can_accept_unit_hit(unit: CombatUnit, kind: String) -> bool:
	return unit != null and is_instance_valid(unit) and not unit.is_destroyed \
		and unit.can_accept_new_hit(kind)


## 返回 false 仅表示目标拒绝命中，或 Aircraft 机炮闪避成功；其它已建立接触返回 true。
static func resolve_unit_hit(unit: CombatUnit, amount: float, source: Variant, kind: String,
		hit_pos: Vector2 = Vector2.INF, incoming_velocity: Vector2 = Vector2.ZERO,
		naval_hull_damage_mult: float = 1.0, naval_can_hit_weak_point: bool = true,
		ambient_tgt_nonlethal: bool = false) -> bool:
	if not can_accept_unit_hit(unit, kind):
		return false

	var attacker: Node = CombatUnit.safe_attacker(source)
	var resolved_hit_pos: Vector2 = unit.global_position if hit_pos == Vector2.INF else hit_pos
	var formal_ground_tgt: bool = unit is GroundUnit and unit.has_meta(&"zone_mission")
	if ambient_tgt_nonlethal and formal_ground_tgt:
		unit.take_atmosphere_damage(amount, attacker, kind)
		return true

	if unit is Aircraft:
		if kind == "gun":
			# take_bullet_damage 只在闪避判定通过后写归因；不能让被闪避弹污染下一次击杀来源。
			return (unit as Aircraft).take_bullet_damage(
				amount, attacker, resolved_hit_pos, incoming_velocity)
		_set_attribution(unit, attacker, kind)
		(unit as Aircraft).take_damage_at(
			amount, resolved_hit_pos, attacker, kind, incoming_velocity)
		return true

	# 特化入口中没有 attacker/kind 形参时，在调用前统一补齐归因元数据。
	_set_attribution(unit, attacker, kind)
	if unit is GroundUnit and kind in ["missile", "qmaam", "aoe"]:
		(unit as GroundUnit).take_missile_damage(amount)
	elif unit is NavalUnit:
		(unit as NavalUnit).take_damage_at(
			amount, resolved_hit_pos, naval_hull_damage_mult, naval_can_hit_weak_point)
	else:
		unit.take_damage_from(amount, attacker, kind)
	return true


static func _set_attribution(unit: CombatUnit, attacker: Node, kind: String) -> void:
	if attacker != null:
		unit.set_meta("_pending_attacker", attacker)
	if kind != "":
		unit.set_meta("_last_damage_kind", kind)
