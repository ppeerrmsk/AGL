extends RefCounted
## 普通僚机机炮自保；不持有 Object 缓存，不扫描全场，公共 EVADE 生命周期仍由 MissileEvasion 管理。

const CHECK_INTERVAL := 1.0 / 3.0
const MIN_COMMIT := 0.6
const SAFE_DELAY := 0.35
const MAX_DURATION := 3.0
const REENTER_DELAY := 0.8
const BREAK_DISTANCE_PX := 1600.0

var active := false
var elapsed := 0.0
var safe_time := 0.0
var check_timer := 0.0
var cooldown := 0.0
var direction := Vector2.ZERO
var _threat_valid := false

func eligible(ai: AIController) -> bool:
	var ac := ai.aircraft
	if not is_instance_valid(ac) or not ac.is_player_squad():
		return false
	var cobra := ac.get_maneuver()
	var herbst := ac.get_herbst()
	return not ac.is_destroyed \
		and not ai.manual_control and not ai.simple_ai and not ai.kamikaze_intercept \
		and ai._directive == null and not ai.is_boss_attacker() \
		and (cobra == null or not cobra.is_active) and (herbst == null or not herbst.is_active) \
		and not ac.is_active_special_maneuver() and not ac.is_afterburner_mode_active() \
		and ai.squad != null and is_instance_valid(ai.squad.leader) \
		and not ai.squad.leader.is_destroyed and ai.squad.leader != ac

func source(ac: Aircraft) -> Aircraft:
	if ac._gun_tailed_attacker_id == 0:
		return null
	var raw: Variant = instance_from_id(ac._gun_tailed_attacker_id)
	if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is Aircraft:
		return null
	return raw as Aircraft

## 首次有效上报后下一 AI tick 即响应，不等低频全场扫描。
func tick(ai: AIController, delta: float) -> bool:
	cooldown = maxf(0.0, cooldown - delta)
	if ai._evading or cooldown > 0.0 or ai._evade_reenter_cd > 0.0 or not eligible(ai):
		return false
	var threat := source(ai.aircraft)
	if threat == null or not ai.aircraft.gun_tailed_active() \
		or not AircraftWeapons.is_gun_tailed_by(threat, ai.aircraft):
		return false
	var ac := ai.aircraft
	var right := Vector2(cos(ac.heading), sin(ac.heading))
	var side := signf(ac.bank_angle)
	if absf(ac.bank_angle) <= 0.05:
		side = signf(right.dot(ai.squad.leader.global_position - ac.global_position))
	if is_zero_approx(side):
		side = 1.0 if ac.get_instance_id() % 2 == 0 else -1.0
	direction = right * side
	MissileEvasion.enter_evade(ai)
	active = true
	elapsed = 0.0
	safe_time = 0.0
	check_timer = 0.0
	_threat_valid = true
	ai.reset_tactical_plan()
	EventLogger.log_event("GUN_EVADE", ac._log_name(), "enter source=%s" % threat._log_name())
	_submit(ai)
	return true

func process(ai: AIController, delta: float) -> void:
	if not eligible(ai):
		MissileEvasion.exit_evade(ai, false)
		return
	elapsed += delta
	var threat := source(ai.aircraft)
	# 已毁/已释放的威胁无需等最短承诺或缓存周期。
	if threat == null or threat.is_destroyed:
		MissileEvasion.exit_evade(ai)
		return
	check_timer -= delta
	if check_timer <= 0.0:
		check_timer = CHECK_INTERVAL
		_threat_valid = AircraftWeapons.is_gun_tailed_by(threat, ai.aircraft)
	safe_time = 0.0 if _threat_valid else safe_time + delta
	if elapsed >= MAX_DURATION or (elapsed >= MIN_COMMIT and safe_time >= SAFE_DELAY):
		MissileEvasion.exit_evade(ai)
		return
	_submit(ai)

func _submit(ai: AIController) -> void:
	var ci := ControlIntent.new()
	ci.pursuit_pos = ai.aircraft.global_position + direction * BREAK_DISTANCE_PX
	ci.target_speed_kmh = AircraftPhysics.effective_corner_speed_kmh(ai.aircraft)
	ci.afterburner = 1
	ai.aircraft.submit_intent(ControlIntent.SOURCE_EVADE, ci)

## 退出、导弹接管、手控/directive 接管共用；只清自己拥有的状态。
func clear(ai: AIController) -> void:
	if not active:
		return
	active = false
	cooldown = REENTER_DELAY
	elapsed = 0.0
	safe_time = 0.0
	check_timer = 0.0
	direction = Vector2.ZERO
	_threat_valid = false
	if is_instance_valid(ai.aircraft):
		ai.aircraft._gun_tailed_attacker_id = 0
		ai.reset_tactical_plan()
		EventLogger.log_event("GUN_EVADE", ai.aircraft._log_name(), "exit")
