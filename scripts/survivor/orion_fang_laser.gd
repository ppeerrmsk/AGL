extends RefCounted
## 单架 FANG 的预警、光剑和接触节拍。所有跨帧目标只存实例 ID。

const Rules = preload("res://scripts/survivor/orion_fire_control.gd")
const HitResolver = preload("res://scripts/weapon_hit_resolver.gd")
enum Phase { COOLDOWN, WARNING, ACTIVE }

var phase: int = Phase.COOLDOWN
var remaining: float = 0.0
var source_id: int = 0
var beam_start := Vector2.ZERO
var beam_end := Vector2.ZERO
var _previous_start := Vector2.ZERO
var _previous_end := Vector2.ZERO
var _had_beam := false
var _clock := 0.0
var _contacts: Dictionary = {}
var intercept_points: Array[Vector2] = []


func setup(source: Aircraft, stagger: float) -> void:
	source_id = source.get_instance_id()
	remaining = stagger


func stop() -> void:
	source_id = 0
	phase = Phase.COOLDOWN
	_had_beam = false
	_contacts.clear()
	intercept_points.clear()


func update(delta: float, units: Array, missiles: Array,
		previous_positions: Dictionary) -> void:
	intercept_points.clear()
	var raw: Variant = instance_from_id(source_id) if source_id != 0 else null
	if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is Aircraft:
		stop()
		return
	var source := raw as Aircraft
	if source.is_destroyed or source.is_queued_for_deletion():
		stop()
		return
	_clock += delta
	remaining -= delta
	if remaining <= 0.0:
		match phase:
			Phase.COOLDOWN:
				phase = Phase.WARNING
				remaining = Rules.BEAM_WARNING
			Phase.WARNING:
				phase = Phase.ACTIVE
				remaining = Rules.BEAM_DURATION
				_had_beam = false
			Phase.ACTIVE:
				phase = Phase.COOLDOWN
				remaining = Rules.BEAM_COOLDOWN
				_contacts.clear()
	beam_start = source.global_position
	beam_end = beam_start + Vector2(sin(source.heading), -cos(source.heading)) * Rules.BEAM_LENGTH
	if not _had_beam:
		_previous_start = beam_start
		_previous_end = beam_end
	if phase == Phase.ACTIVE:
		for candidate: Variant in units:
			if typeof(candidate) != TYPE_OBJECT or not is_instance_valid(candidate) \
					or not candidate is Aircraft:
				continue
			var unit := candidate as Aircraft
			if unit.is_destroyed or not source.is_hostile_to(unit) \
					or not HitResolver.can_accept_unit_hit(unit, "laser"):
				continue
			if not source.flat_altitude and not unit.flat_altitude \
					and absf(source.altitude - unit.altitude) > 200.0:
				continue
			var uid := unit.get_instance_id()
			var previous: Vector2 = previous_positions.get(uid, unit.global_position)
			if not Rules.swept_beam_hit(previous, unit.global_position,
					_previous_start, _previous_end, beam_start, beam_end, Rules.BEAM_RADIUS + BulletManager.HIT_RADIUS):
				continue
			var contact: Dictionary = _contacts.get(uid, {})
			var entered: bool = contact.is_empty() \
				or (float(contact.get("outside_since", -1.0)) >= 0.0 \
					and _clock - float(contact["outside_since"]) >= Rules.REENTRY_GAP)
			if entered or _clock >= float(contact.get("next_hit", 0.0)):
				HitResolver.resolve_unit_hit(unit, Rules.BEAM_DAMAGE, source, "laser",
					unit.global_position, beam_end - beam_start)
				contact["next_hit"] = _clock + 1.0
			contact["last_seen"] = _clock
			contact["outside_since"] = -1.0
			_contacts[uid] = contact
		for candidate: Variant in missiles:
			if typeof(candidate) != TYPE_OBJECT or not is_instance_valid(candidate) \
					or not candidate is Missile:
				continue
			var missile := candidate as Missile
			if not missile.is_active or not CombatUnit.teams_hostile(source.team, missile.team):
				continue
			if not source.flat_altitude and absf(source.altitude - missile.altitude) > 200.0:
				continue
			var previous: Vector2 = previous_positions.get(missile.get_instance_id(), missile.global_position)
			if Rules.swept_beam_hit(previous, missile.global_position,
					_previous_start, _previous_end, beam_start, beam_end, Rules.BEAM_RADIUS):
				var point := Geometry2D.get_closest_point_to_segment(missile.global_position, beam_start, beam_end)
				if missile.destroy_from_intercept(false) and intercept_points.size() < 16:
					intercept_points.append(point)
	# 身份表只保留仍可能连续接触的记录，不随整场击坠数增长。
	for uid: int in _contacts.keys():
		if float(_contacts[uid]["last_seen"]) < _clock \
				and float(_contacts[uid].get("outside_since", -1.0)) < 0.0:
			_contacts[uid]["outside_since"] = _clock
		if float(_contacts[uid].get("outside_since", -1.0)) >= 0.0 \
				and _clock - float(_contacts[uid]["outside_since"]) >= Rules.REENTRY_GAP:
			_contacts.erase(uid)
	_previous_start = beam_start
	_previous_end = beam_end
	_had_beam = phase == Phase.ACTIVE
