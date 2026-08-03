class_name FriendlyAssetAggro
extends RefCounted

## 玩家触发的友方据点牵连交战调度器（spec friendly-asset-aggro）。
##
## 由 survivor_mode 每帧喂 delta，但内部固定 1 Hz 决策；每个 tick 只遍历一次
## CombatUnit 缓存，同时完成据点目标刷新、敌机筛选、配额与重派。

const META_GROUP_ID: StringName = CombatUnit.META_FRIENDLY_ASSET_GROUP
const META_ACTIVE: StringName = CombatUnit.META_FRIENDLY_ASSET_ACTIVE

const KIND_AIRFIELD: StringName = &"airfield"
const KIND_CARRIER: StringName = &"carrier"

const TICK_INTERVAL_S: float = 1.0
const EXIT_GRACE_S: float = 8.0
const PARTICIPATION_RADIUS_PX: float = 6000.0
const AIRFIELD_ENTER_RADIUS_PX: float = 2000.0
const AIRFIELD_EXIT_RADIUS_PX: float = 2500.0
const CARRIER_ENTER_RADIUS_PX: float = 2500.0
const CARRIER_EXIT_RADIUS_PX: float = 3000.0

var _groups: Dictionary = {}  ## StringName → group Dictionary
var _tick_accum: float = 0.0
var _last_summary: String = ""


func reset() -> void:
	for g_any in _groups.values():
		var g: Dictionary = g_any
		_mark_group_targets_active(g, false)
	_groups.clear()
	_tick_accum = 0.0
	_last_summary = ""


func register_airfield(group_id: StringName, anchor_pos: Vector2) -> void:
	_register_group(group_id, KIND_AIRFIELD, anchor_pos, null,
		AIRFIELD_ENTER_RADIUS_PX, AIRFIELD_EXIT_RADIUS_PX)


func register_carrier(group_id: StringName, carrier: NavalUnit) -> void:
	if carrier == null or not is_instance_valid(carrier):
		return
	_register_group(group_id, KIND_CARRIER, carrier.global_position, weakref(carrier),
		CARRIER_ENTER_RADIUS_PX, CARRIER_EXIT_RADIUS_PX)
	carrier.set_meta(META_GROUP_ID, group_id)
	carrier.set_meta(META_ACTIVE, false)


func register_target(group_id: StringName, target: CombatUnit) -> void:
	if not _groups.has(group_id) or target == null or not is_instance_valid(target):
		return
	var g: Dictionary = _groups[group_id]
	var targets: Array = g["targets"]
	if not targets.has(target):
		targets.append(target)
	target.set_meta(META_GROUP_ID, group_id)
	target.set_meta(META_ACTIVE, g["active"] == true)


func unregister_group(group_id: StringName) -> void:
	if not _groups.has(group_id):
		return
	var g: Dictionary = _groups[group_id]
	_mark_group_targets_active(g, false)
	var anchor_ref: WeakRef = g.get("anchor_ref")
	if anchor_ref != null:
		var anchor = anchor_ref.get_ref()
		if is_instance_valid(anchor):
			anchor.set_meta(META_ACTIVE, false)
	_groups.erase(group_id)
	EventLogger.log_event("ASSET", "GroupRemoved", String(group_id))


func tick(delta: float, player: Aircraft, units: Array[CombatUnit]) -> void:
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL_S:
		return
	_tick_accum = fmod(_tick_accum, TICK_INTERVAL_S)
	_step(player, units)


## 纯函数：合格敌机数 H → 所有重叠 ACTIVE 据点共享的分流总配额。
static func quota_for(hostile_count: int) -> int:
	if hostile_count < 2:
		return 0
	return mini(3, maxi(1, floori(float(hostile_count) / 3.0)))


static func group_id_of(target: CombatUnit) -> StringName:
	if target == null or not is_instance_valid(target) or not target.has_meta(META_GROUP_ID):
		return &""
	return StringName(str(target.get_meta(META_GROUP_ID, "")))


func is_group_active(group_id: StringName) -> bool:
	return _groups.has(group_id) and (_groups[group_id] as Dictionary)["active"] == true


func _register_group(group_id: StringName, kind: StringName, anchor_pos: Vector2,
		anchor_ref: WeakRef, enter_radius: float, exit_radius: float) -> void:
	if group_id == &"":
		return
	if _groups.has(group_id):
		var old: Dictionary = _groups[group_id]
		old["kind"] = kind
		old["anchor_pos"] = anchor_pos
		old["anchor_ref"] = anchor_ref
		old["enter_radius"] = enter_radius
		old["exit_radius"] = exit_radius
		return
	_groups[group_id] = {
		"kind": kind,
		"anchor_pos": anchor_pos,
		"anchor_ref": anchor_ref,
		"enter_radius": enter_radius,
		"exit_radius": exit_radius,
		"active": false,
		"outside_s": 0.0,
		"targets": [],
	}


func _step(player: Aircraft, units: Array[CombatUnit]) -> void:
	_update_activation(player)

	# 单次全场扫描：同时刷新动态 MountTarget 与敌机列表。
	var targets_by_group: Dictionary = {}
	for group_key in _groups.keys():
		targets_by_group[group_key] = []
	var hostiles: Array[Aircraft] = []
	for unit in units:
		if unit == null or not is_instance_valid(unit) or unit.is_destroyed:
			continue
		if unit is Aircraft and unit.team == CombatUnit.TEAM_HOSTILE:
			hostiles.append(unit as Aircraft)
		var gid := _resolve_unit_group(unit)
		if gid == &"":
			continue
		var active := is_group_active(gid)
		unit.set_meta(META_GROUP_ID, gid)
		unit.set_meta(META_ACTIVE, active)
		if active and _is_attackable_asset_target(unit):
			(targets_by_group[gid] as Array).append(unit)

	_release_inactive_or_excess(hostiles, targets_by_group)
	var active_targets := _flatten_targets(targets_by_group)
	if active_targets.is_empty():
		_log_summary(hostiles.size(), 0, 0)
		return

	var candidates: Array[Dictionary] = []
	for ac in hostiles:
		var ai := _ai_for(ac)
		if ai == null or not _eligible_attacker(ac, ai):
			continue
		var dist := _distance_to_nearest_active_group(ac.global_position)
		if dist > PARTICIPATION_RADIUS_PX:
			continue
		candidates.append({"ac": ac, "ai": ai, "dist": dist})

	var quota := quota_for(candidates.size())
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_has := _targets_active_asset(a["ai"], targets_by_group)
		var b_has := _targets_active_asset(b["ai"], targets_by_group)
		if a_has != b_has:
			return a_has
		if not is_equal_approx(float(a["dist"]), float(b["dist"])):
			return float(a["dist"]) < float(b["dist"])
		var ai_a: AIController = a["ai"]
		var ai_b: AIController = b["ai"]
		if ai_a.squad_index != ai_b.squad_index:
			return ai_a.squad_index > ai_b.squad_index
		return (a["ac"] as Aircraft).get_instance_id() < (b["ac"] as Aircraft).get_instance_id())

	var assigned: Array[Dictionary] = []
	var target_counts: Dictionary = {}
	for item in candidates:
		if not _targets_active_asset(item["ai"], targets_by_group):
			continue
		if assigned.size() >= quota:
			_release_asset_target(item["ai"], "quota reduced")
			continue
		assigned.append(item)
		var held: CombatUnit = CombatUnit.safe_unit((item["ai"] as AIController)._current_target)
		if held != null:
			target_counts[held.get_instance_id()] = int(target_counts.get(held.get_instance_id(), 0)) + 1

	for item in candidates:
		if assigned.size() >= quota:
			break
		if item in assigned:
			continue
		var target := _pick_target(item["ac"], active_targets, target_counts)
		if target == null:
			break
		var ai: AIController = item["ai"]
		if not ai.acquire_target(target, AIController.TargetSource.TS_ASSET, "friendly asset active"):
			continue
		ai.enter_engage_state()
		ai._target_eval_timer = 0.0
		ai.aircraft.ai_override_pursuit = true
		ai._squad_attacking_leader_target = false
		ai._squad_lateral_role = AIController.SquadRole.NONE
		ai._squad_free_engaging = false
		assigned.append(item)
		target_counts[target.get_instance_id()] = int(target_counts.get(target.get_instance_id(), 0)) + 1
		EventLogger.log_event("ASSET", ac_name(item["ac"]), "assigned %s group=%s" % [
			target.callsign, String(group_id_of(target))])

	_log_summary(candidates.size(), quota, assigned.size())


func _update_activation(player: Aircraft) -> void:
	var player_ok := player != null and is_instance_valid(player) and not player.is_destroyed
	for gid in _groups.keys():
		var g: Dictionary = _groups[gid]
		var anchor := _anchor_position(g)
		if anchor == Vector2.INF:
			if g["active"] == true:
				_set_group_active(gid, false, "anchor gone")
			continue
		if not player_ok:
			if g["active"] == true:
				_set_group_active(gid, false, "player unavailable")
			continue
		var dist: float = player.global_position.distance_to(anchor)
		if g["active"] != true:
			if dist <= float(g["enter_radius"]):
				_set_group_active(gid, true, "player entered")
		else:
			if dist >= float(g["exit_radius"]):
				g["outside_s"] = float(g["outside_s"]) + TICK_INTERVAL_S
				if float(g["outside_s"]) >= EXIT_GRACE_S:
					_set_group_active(gid, false, "player left 8s")
			else:
				g["outside_s"] = 0.0


func _set_group_active(group_id: StringName, active: bool, why: String) -> void:
	if not _groups.has(group_id):
		return
	var g: Dictionary = _groups[group_id]
	if g["active"] == active:
		return
	g["active"] = active
	g["outside_s"] = 0.0
	_mark_group_targets_active(g, active)
	var anchor_ref: WeakRef = g.get("anchor_ref")
	if anchor_ref != null:
		var anchor = anchor_ref.get_ref()
		if is_instance_valid(anchor):
			anchor.set_meta(META_ACTIVE, active)
	EventLogger.log_event("ASSET", "GroupActive" if active else "GroupDormant",
		"%s kind=%s (%s)" % [String(group_id), String(g["kind"]), why])


func _mark_group_targets_active(g: Dictionary, active: bool) -> void:
	var kept: Array = []
	for target in (g["targets"] as Array):
		if target == null or not is_instance_valid(target):
			continue
		target.set_meta(META_ACTIVE, active)
		kept.append(target)
	g["targets"] = kept


func _resolve_unit_group(unit: CombatUnit) -> StringName:
	if unit.has_meta(META_GROUP_ID):
		return StringName(str(unit.get_meta(META_GROUP_ID, "")))
	if unit is MountTarget:
		var mt := unit as MountTarget
		if mt.parent_ship != null and is_instance_valid(mt.parent_ship) \
				and mt.parent_ship.has_meta(META_GROUP_ID):
			return StringName(str(mt.parent_ship.get_meta(META_GROUP_ID, "")))
	return &""


func _is_attackable_asset_target(unit: CombatUnit) -> bool:
	return unit is GroundUnit or unit is MountTarget


func _anchor_position(g: Dictionary) -> Vector2:
	var anchor_ref: WeakRef = g.get("anchor_ref")
	if anchor_ref != null:
		var anchor = anchor_ref.get_ref()
		if not is_instance_valid(anchor) or anchor.is_destroyed:
			return Vector2.INF
		g["anchor_pos"] = anchor.global_position
	return g["anchor_pos"]


func _distance_to_nearest_active_group(pos: Vector2) -> float:
	var best := INF
	for g_any in _groups.values():
		var g: Dictionary = g_any
		if g["active"] != true:
			continue
		var anchor := _anchor_position(g)
		if anchor != Vector2.INF:
			best = minf(best, pos.distance_to(anchor))
	return best


func _ai_for(ac: Aircraft) -> AIController:
	if ac == null or not is_instance_valid(ac):
		return null
	if ac._ai_ref != null and is_instance_valid(ac._ai_ref):
		return ac._ai_ref as AIController
	for child in ac.get_children():
		if child is AIController:
			return child
	return null


func _eligible_attacker(ac: Aircraft, ai: AIController) -> bool:
	if ai.manual_control or ac.get_meta(&"reinf_phase", "") == "egress":
		return false
	var posture := str(ac.get_meta(&"roe_posture", ""))
	if posture == "transit" or posture == "egress":
		return false
	if ai.get_target_source() >= AIController.TargetSource.TS_DIRECTIVE:
		return false
	# 主 BOSS / 中队长不拆。Mother Goose 的单机 hunter UAV 虽各自持有一人 squad，
	# 但不是战术队长，允许作为 adds 被分流。
	if ai.squad != null and is_instance_valid(ai.squad.leader) and ai.squad.leader == ac:
		if str(ac.get_meta(&"category", "")) != "boss_mother_goose_uav":
			return false
	elif str(ac.get_meta(&"category", "")) == "boss":
		return false
	return true


func _targets_active_asset(ai: AIController, targets_by_group: Dictionary) -> bool:
	var target: CombatUnit = CombatUnit.safe_unit(ai._current_target)
	if target == null or target.is_destroyed:
		return false
	var gid := group_id_of(target)
	return gid != &"" and targets_by_group.has(gid) and target in (targets_by_group[gid] as Array) \
		and ai.get_target_source() <= AIController.TargetSource.TS_ASSET


func _release_inactive_or_excess(hostiles: Array[Aircraft], targets_by_group: Dictionary) -> void:
	for ac in hostiles:
		var ai := _ai_for(ac)
		if ai == null or ai.get_target_source() > AIController.TargetSource.TS_ASSET:
			continue
		var target: CombatUnit = CombatUnit.safe_unit(ai._current_target)
		if target == null:
			if ai.get_target_source() == AIController.TargetSource.TS_ASSET:
				ai.release_target(AIController.TargetSource.TS_ASSET, "asset target gone")
			continue
		var gid := group_id_of(target)
		if gid == &"":
			continue
		if not targets_by_group.has(gid) or target not in (targets_by_group[gid] as Array):
			_release_asset_target(ai, "asset dormant or destroyed")
		elif _distance_to_nearest_active_group(ac.global_position) > PARTICIPATION_RADIUS_PX:
			_release_asset_target(ai, "left participation radius")
		elif not _eligible_attacker(ac, ai):
			_release_asset_target(ai, "protected leader or directive")


func _release_asset_target(ai: AIController, why: String) -> void:
	if ai.release_target(AIController.TargetSource.TS_ASSET, why):
		EventLogger.log_event("ASSET", ac_name(ai.aircraft), "released (%s)" % why)


func _flatten_targets(targets_by_group: Dictionary) -> Array[CombatUnit]:
	var result: Array[CombatUnit] = []
	for arr_any in targets_by_group.values():
		for target in (arr_any as Array):
			if target != null and is_instance_valid(target) and not target.is_destroyed:
				result.append(target)
	return result


func _pick_target(attacker: Aircraft, targets: Array[CombatUnit], counts: Dictionary) -> CombatUnit:
	var best: CombatUnit = null
	var best_count := 999999
	var best_dist := INF
	for target in targets:
		var gid := group_id_of(target)
		if not _groups.has(gid):
			continue
		var anchor := _anchor_position(_groups[gid])
		if anchor == Vector2.INF or attacker.global_position.distance_to(anchor) > PARTICIPATION_RADIUS_PX:
			continue
		var count := int(counts.get(target.get_instance_id(), 0))
		var dist := attacker.global_position.distance_to(target.global_position)
		if count < best_count or (count == best_count and dist < best_dist):
			best = target
			best_count = count
			best_dist = dist
	return best


func _log_summary(hostile_count: int, quota: int, assigned: int) -> void:
	var summary := "H=%d Q=%d assigned=%d active_groups=%d" % [
		hostile_count, quota, assigned, _active_group_count()]
	if summary == _last_summary:
		return
	_last_summary = summary
	EventLogger.log_event("ASSET", "Director", summary)


func _active_group_count() -> int:
	var count := 0
	for g_any in _groups.values():
		if (g_any as Dictionary)["active"] == true:
			count += 1
	return count


static func ac_name(ac: Aircraft) -> String:
	if ac == null or not is_instance_valid(ac):
		return "?"
	return ac.callsign if ac.callsign != "" else "Aircraft#%d" % ac.get_instance_id()
