class_name HackedAllyForce
extends RefCounted

## 本局被黑无人机的轻量编队账本。无 process；只在黑入、换帅、退场时改引用。
var _leader: Aircraft = null
var _squad: Squad = Squad.new()
var _members: Array[Aircraft] = []


func set_leader(leader: Aircraft) -> void:
	if leader == null or not is_instance_valid(leader) or leader.is_destroyed:
		return
	_leader = leader
	_squad.leader = leader
	_squad.members.clear()
	_squad.members.append(leader)
	_prune_members()
	for i in range(_members.size()):
		_bind_member(_members[i], i + 1)


func adopt(ac: Aircraft) -> void:
	if ac == null or not is_instance_valid(ac) or ac.is_destroyed or ac in _members:
		return
	_members.append(ac)
	_squad.members.append(ac)
	_bind_member(ac, _members.size())
	ac.set_meta("hacked_ally", true)
	ac.set_meta("no_kamikaze", true)
	ac.tree_exiting.connect(_on_member_exiting.bind(ac.get_instance_id()), CONNECT_ONE_SHOT)
	EventLogger.log_event("FACTION", ac.callsign, "adopted by current leader")


func shutdown() -> void:
	for ac in _members:
		if not is_instance_valid(ac):
			continue
		var ai: AIController = ac._get_ai_controller()
		if ai and ai.squad == _squad:
			ai.squad = null
			ai.squad_index = -1
	_members.clear()
	_squad.members.clear()
	_squad.leader = null
	_leader = null


func _bind_member(ac: Aircraft, squad_index: int) -> void:
	if not is_instance_valid(ac) or ac.is_destroyed:
		return
	if ac not in _squad.members:
		_squad.members.append(ac)
	var ai: AIController = ac._get_ai_controller()
	if ai == null:
		return
	ai.simple_ai = true
	ai.enable_combat = true
	ai.ground_combat_only = false
	ai.orbit_squad_leader = true
	ai.shield_leader = false
	ai.swarm_role_override = -1
	ai.combat_zone_anchor = null
	ai.combat_zone_radius = 0.0
	ai.squad = _squad
	ai.squad_index = squad_index
	ai.set_event_directive(null)
	ai._current_target = null
	ai.enter_patrol_state(false)
	ai.waypoints = PackedVector2Array()
	ac.clear_combat_target()
	ac.clear_formation()


func _prune_members() -> void:
	var live: Array[Aircraft] = []
	for ac in _members:
		if is_instance_valid(ac) and not ac.is_destroyed and not ac.is_queued_for_deletion():
			live.append(ac)
	_members = live


func _on_member_exiting(instance_id: int) -> void:
	for i in range(_members.size() - 1, -1, -1):
		var ac := _members[i]
		if not is_instance_valid(ac) or ac.get_instance_id() == instance_id:
			_members.remove_at(i)
	for i in range(_squad.members.size() - 1, 0, -1):
		var member := _squad.members[i]
		if not is_instance_valid(member) or member.get_instance_id() == instance_id:
			_squad.members.remove_at(i)
