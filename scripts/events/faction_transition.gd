class_name FactionTransition
extends RefCounted

## 动态阵营转换的原子事务（spec dynamic-faction-conversion）。
## 调用者只负责转换后的行为；旧阵营留下的目标、锁定、编队和弹药 IFF 在这里统一清理。

const META_IN_PROGRESS: StringName = &"_faction_transition_in_progress"
const META_NEUTRALIZED: StringName = &"faction_neutralized"


static func convert(unit: CombatUnit, to_team: int, reason_id: String,
		source: CombatUnit = null) -> bool:
	if unit == null or not is_instance_valid(unit) or unit.is_destroyed:
		return false
	if unit.team == to_team or unit.has_meta(META_IN_PROGRESS):
		return false
	var old_team := unit.team
	unit.set_meta(META_IN_PROGRESS, true)

	_detach_old_combat_state(unit)
	_reassign_in_flight_weapons(unit, to_team)
	unit.team = to_team
	unit.is_mission_target = false
	unit.set_meta(META_NEUTRALIZED, true)
	unit.set_meta("category", "ally" if to_team == CombatUnit.TEAM_ALLY else "converted")
	unit.set_meta("token_cost", 0)
	unit.set_meta("skip_far_cleanup", true)
	if unit is Aircraft:
		(unit as Aircraft).refresh_faction_visuals()

	unit.remove_meta(META_IN_PROGRESS)
	unit.faction_changed.emit(old_team, to_team, reason_id)
	EventLogger.log_event("FACTION", unit.callsign,
		"%d -> %d reason=%s source=%s" % [old_team, to_team, reason_id,
		_source_name(source)])
	return true


static func _detach_old_combat_state(unit: CombatUnit) -> void:
	# 先清除全场对本单位的缓存目标，再处理本单位自身火控。
	# escort_guards / flock_members 是 Array[Aircraft]；不能把静态类型为
	# CombatUnit 的 unit 直接交给 TypedArray.erase，否则 Godot 4.7 会逐次报类型错误。
	var aircraft_unit: Aircraft = null
	if unit is Aircraft:
		aircraft_unit = unit as Aircraft
	CombatUnit.release_target_refs(unit)
	for other in CombatUnit.all_units:
		if other == null or not is_instance_valid(other):
			continue
		other.radar_targets.erase(unit)
		other.locked_by.erase(unit)
		if other is Aircraft:
			var other_ac := other as Aircraft
			other_ac.engaging_me.erase(unit.get_instance_id())
			if aircraft_unit != null:
				other_ac.escort_guards.erase(aircraft_unit)
				other_ac.flock_members.erase(aircraft_unit)
	unit.radar_targets.clear()
	unit.locked_by.clear()
	unit.is_locked = false
	unit.incoming_lock_progress = 0.0

	if aircraft_unit == null:
		return
	var ac := aircraft_unit
	ac.commanded_target = null
	ac.secondary_combat_target = null
	ac.secondary_radar_targets.clear()
	ac.engaging_me.clear()
	ac.escort_guards.clear()
	ac.flock_members.clear()
	ac.clear_combat_target()
	ac.clear_formation()
	var ai: AIController = ac._get_ai_controller()
	if ai == null:
		return
	if ai.squad != null:
		ai.squad.remove_member(ac)
	ai.squad = null
	ai.squad_index = -1
	ai.orbit_squad_leader = false
	ai.shield_leader = false
	ai.set_event_directive(null)
	ai._current_target = null


static func _reassign_in_flight_weapons(unit: CombatUnit, new_team: int) -> void:
	var missile_manager = unit.get("missile_manager") if "missile_manager" in unit else null
	if missile_manager != null and is_instance_valid(missile_manager):
		for child in missile_manager.get_children():
			if not child is Missile:
				continue
			var missile := child as Missile
			if missile.source == unit:
				missile.team = new_team
				if is_instance_valid(missile.target) \
						and not CombatUnit.teams_hostile(new_team, missile.target.team):
					missile.target = null
					missile.has_guidance = false
			if missile.target == unit and not CombatUnit.teams_hostile(missile.team, new_team):
				missile.target = null
				missile.has_guidance = false
	var bullet_manager = unit.get("bullet_manager") if "bullet_manager" in unit else null
	if bullet_manager != null and is_instance_valid(bullet_manager) \
			and bullet_manager.has_method("reassign_projectiles_from"):
		bullet_manager.reassign_projectiles_from(unit, new_team)


static func _source_name(source: CombatUnit) -> String:
	if source == null or not is_instance_valid(source):
		return "none"
	return source.callsign if source.callsign != "" else source.name
