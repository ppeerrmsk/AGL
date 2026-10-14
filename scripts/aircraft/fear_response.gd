class_name FearResponse
extends RefCounted

## 受害者持有：来源、控制权、保护期与加力来源。免疫成功拒绝时不创建任何副作用。
const PROTECTION_S := 3.0
const SAMPLE_S := 0.1
const COLOR := Color("b05cff")
var source_ref: WeakRef
var source_team := -1
var source_position := Vector2.ZERO
var escape_direction := Vector2.UP
var protection_s := 0.0
var sample_s := 0.0
var active := false
var held_altitude := 0.0
var _intent := ControlIntent.new()

static func aircraft(value: Variant) -> Aircraft:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null
	return value as Aircraft

static func controlled(value: Variant) -> bool:
	var ac := aircraft(value)
	return ac != null and not ac.is_destroyed and ac.fear_response != null \
		and ac.fear_response.active and ac.has_status(StatusEffects.FEAR)

static func eligible(value: Variant) -> bool:
	var ac := aircraft(value)
	return ac != null and not ac.is_destroyed and ac.is_player_squad() \
		and not ac.no_pilot and not ac.is_drone and not ac.has_meta(&"fear_immune") \
		and not ac.sig_status_immune and not ac.has_status(StatusEffects.FEAR) \
		and not ac.has_meta(CombatUnit.META_PRESENTATION_ACTOR_ACTIVE) \
		and (ac.fear_response == null or ac.fear_response.protection_s <= 0.0)

static func apply(target: Variant, source: Variant, duration: float = 5.0) -> bool:
	var ac := aircraft(target)
	var emitter := aircraft(source)
	if not eligible(ac) or emitter == null or emitter.is_destroyed \
			or not ac.is_hostile_to(emitter) or duration <= 0.0:
		return false
	ac.apply_status(StatusEffects.FEAR, duration, "no_refresh")
	if not ac.has_status(StatusEffects.FEAR):
		return false
	if ac.fear_response == null:
		ac.fear_response = FearResponse.new()
	var state: FearResponse = ac.fear_response
	state.source_ref = weakref(emitter)
	state.source_team = emitter.team
	state.source_position = emitter.global_position
	state.escape_direction = Vector2(sin(emitter.heading), -cos(emitter.heading))
	state.held_altitude = ac.altitude
	state.active = true
	state.sample_s = 0.0
	ac.status_fear_active = true
	ac.set_afterburner_mode_active(true, &"fear")
	state.enforce(ac)
	ac.show_tactic_popup(ac.tr("POPUP_FEAR_CONTROL"))
	EventLogger.log_event("FEAR", ac.callsign, "source=%s duration=%.1f" % [emitter.callsign, duration])
	return true

func update(ac: Aircraft, delta: float) -> void:
	if not active:
		protection_s = maxf(0.0, protection_s - delta)
		return
	if ac.is_destroyed or not ac.is_player_squad() \
			or ac.has_meta(CombatUnit.META_PRESENTATION_ACTOR_ACTIVE):
		clear(ac, false)
		return
	if not ac.has_status(StatusEffects.FEAR):
		clear(ac, true)
		return
	# 正常电池窗口自行结算；仅强制来源时复用相同的 Su-34 加力回血数值。
	if ac.sig_su34_active and not ac._afterburner_manual_source and ac.params != null:
		ac.hp = minf(ac.hp + AfterburnerCharge.SIG_SU34_HEAL_PER_SEC * delta, ac.params.max_hp)
	sample_s -= delta
	if sample_s <= 0.0:
		sample_s = SAMPLE_S
		var emitter := aircraft(source_ref.get_ref() if source_ref != null else null)
		if emitter != null and not emitter.is_destroyed and emitter.team == source_team:
			source_position = emitter.global_position
		else:
			source_ref = null

func enforce(ac: Aircraft) -> void:
	if not active:
		return
	ac.hard_brake = false
	ac.brake_steer_input = 0.0
	ac.clear_formation()
	var cobra := ac.get_maneuver()
	if cobra != null:
		cobra.phase = CobraManeuver.Phase.NONE
		cobra.visual_offset = 0.0
	var herbst := ac.get_herbst()
	if herbst != null:
		herbst.phase = HerbstManeuver.Phase.NONE
		herbst.visual_offset = 0.0
	# 只取消已占据控制权的机动，不发“机动完成”奖励，不回写旧位置/速度。
	ac._active_special = Aircraft.ActiveSpecialManeuver.NONE
	ac._active_special_heading_offset = 0.0
	ac._active_special_roll_visual = 0.0
	ac._active_special_pitch_visual = 0.0
	ac._active_special_queued_altitude = INF
	ac.target_altitude = held_altitude
	var away := ac.global_position - source_position
	if away.length_squared() > 0.001:
		escape_direction = away.normalized()
	_intent.pursuit_pos = escape_point(ac.global_position, source_position, escape_direction)
	_intent.target_speed_kmh = AircraftPhysics.effective_max_speed_kmh(ac)
	_intent.afterburner = 0 if ac.status_slow_active else 1
	ac.submit_intent(ControlIntent.SOURCE_FEAR, _intent)

static func escape_point(pos: Vector2, source: Vector2, fallback: Vector2) -> Vector2:
	var away := (pos - source).normalized() if pos.distance_squared_to(source) > 0.001 else fallback
	var desired := pos + away * 1500.0
	var bounded := MapBoundary.clamp_inside(desired, 300.0)
	if bounded.distance_squared_to(desired) < 0.01:
		return desired
	# 边缘避让：有限 16 方位选最大脱离距离；同分优先沿原逃逸方向，避免顶墙。
	var best := bounded
	var best_score := -INF
	for i in range(16):
		var direction := away.rotated(TAU * float(i) / 16.0)
		var candidate := MapBoundary.clamp_inside(pos + direction * 1500.0, 300.0)
		var score := candidate.distance_squared_to(source) + direction.dot(away) * 0.01
		if candidate.distance_squared_to(pos) > 100.0 and score > best_score:
			best_score = score
			best = candidate
	return best

func clear(ac: Aircraft, protect: bool = true) -> void:
	active = false
	source_ref = null
	protection_s = PROTECTION_S if protect else 0.0
	ac.remove_status(StatusEffects.FEAR)
	ac.status_fear_active = false
	ac.withdraw_intent(ControlIntent.SOURCE_FEAR)
	ac.set_afterburner_mode_active(false, &"fear")
	ac.target_position = Vector2.INF
	ac.reset_tactical_plan_state()

static func obscure(item: Variant, observer: Variant = null) -> bool:
	var viewer: Variant = observer if observer != null else AircraftRenderer.player_ref
	return controlled(viewer) or controlled(item)

static func seconds(value: Variant) -> float:
	var ac := aircraft(value)
	return float(ac.status_effects.get(StatusEffects.FEAR, 0.0)) if ac != null else 0.0
