## 加力模式队级状态机（spec afterburner-mode）。
##
## 资源、激活会话与对称清理只住在这里；调用方只负责驱动 update、转发 E 键或
## 在玩家世界指令前调用 cancel_for_manual_command。激活成员使用 Squad 权威列表的
## 弱引用快照，既不扫描全场，也不跨帧强持有 Aircraft（SEAM-019）。
class_name AfterburnerCharge
extends RefCounted

signal phase_changed(active: bool, reason: StringName)

enum Phase { CHARGING, ACTIVE }

const CHARGE_MAX: float = 6.0
const CHARGE_RATE: float = 0.2
const DRAIN_RATE: float = 1.0
const KILL_CHARGE: float = 0.8
const SIG_SU34_HEAL_PER_SEC: float = 2.0

var charge: float = CHARGE_MAX
var phase: Phase = Phase.CHARGING

## 720 批技能修正：队级账本一次投影，不逐机叠加。
var kill_charge_bonus: float = 0.0
var duration_mult: float = 1.0

var _leader_ref: WeakRef
var _member_refs: Array[WeakRef] = []
var _storm_i_spent: float = 0.0
var _storm_i_triggered: bool = false


func update(delta: float, rate_mult: float = 1.0, storm_ii_active: bool = false,
		bonus_recharge_per_sec: float = 0.0) -> void:
	var bonus_rate := maxf(bonus_recharge_per_sec, 0.0)
	if phase == Phase.ACTIVE:
		var consumed := 0.0 if storm_ii_active else _effective_drain() * delta
		charge -= consumed
		_storm_i_spent += consumed
		_update_active_member_effects(delta)
		charge = minf(charge + bonus_rate * delta, CHARGE_MAX)
		if charge <= 0.0:
			charge = 0.0
			deactivate(&"depleted")
		return

	var recharge_mult := SkillHooks.STORM_II_RECHARGE_MULT if storm_ii_active else 1.0
	charge = minf(charge + (
		CHARGE_RATE * maxf(rate_mult, 0.0) * recharge_mult + bonus_rate) * delta,
		CHARGE_MAX)


func on_kill_charge() -> void:
	charge = minf(charge + KILL_CHARGE + kill_charge_bonus, CHARGE_MAX)


## E 键统一开关。返回 true 只表示本次成功进入 ACTIVE。
func toggle(leader: Aircraft) -> bool:
	if is_active():
		deactivate(&"toggle")
		return false
	return activate(leader)


func activate(leader: Aircraft) -> bool:
	if not is_available() or not _valid_aircraft(leader):
		return false

	phase = Phase.ACTIVE
	_storm_i_spent = 0.0
	_storm_i_triggered = false
	_capture_members(leader)
	_set_window_members_active(true)

	## 复用 AI 规避几何与护卫广播，但加力状态权威仍是本模块，不是 evasion_mode。
	leader.set_evasion_mode(true, true)
	if leader.callsign != "" and leader.can_speak_on_radio():
		EventLogger.afterburner_engaged.emit(leader.callsign, leader.team)
	EventLogger.log_event("AFTERBURNER", leader._log_name(),
		"activate charge=%.1fs squad=%d" % [charge, _member_refs.size()])
	phase_changed.emit(true, &"activate")
	return true


## 玩家世界指令的唯一取消入口。只退出模式并开始充能；刻意不写 speed、
## target_speed_kmh、is_afterburner 或物理积分状态，保留取消当帧的速度与动力学连续性。
func cancel_for_manual_command() -> bool:
	if not is_active():
		return false
	deactivate(&"manual_command")
	return true


## E 提前关闭、玩家指令取消、能量耗尽与场景清理共用同一对称出口。
func deactivate(reason: StringName = &"shutdown") -> void:
	if not is_active():
		return
	phase = Phase.CHARGING
	_set_window_members_active(false)
	var leader := _leader()
	if _valid_aircraft(leader):
		leader.set_evasion_mode(false)
		EventLogger.log_event("AFTERBURNER", leader._log_name(),
			"deactivate reason=%s charge=%.1fs" % [reason, charge])
	_clear_activation()
	phase_changed.emit(false, reason)


func is_active() -> bool:
	return phase == Phase.ACTIVE


func is_available() -> bool:
	return phase == Phase.CHARGING and charge > 0.0


func is_full() -> bool:
	return phase == Phase.CHARGING and charge >= CHARGE_MAX


func ratio() -> float:
	return clampf(charge / CHARGE_MAX, 0.0, 1.0)


func remaining_seconds() -> float:
	return charge / _effective_drain()


func _effective_drain() -> float:
	return DRAIN_RATE / maxf(duration_mult, 0.01)


func _capture_members(leader: Aircraft) -> void:
	_clear_activation()
	_leader_ref = weakref(leader)
	var squad := leader.squad_ref()
	var candidates: Array[Aircraft] = []
	if squad != null:
		candidates.assign(squad.members)
	else:
		candidates.append(leader)
	for member in candidates:
		if not _valid_aircraft(member) or member.team != leader.team or member.is_drone:
			continue
		_member_refs.append(weakref(member))
	if _member_refs.is_empty():
		_member_refs.append(weakref(leader))


func _set_window_members_active(enabled: bool) -> void:
	for member_ref in _member_refs:
		var value: Variant = member_ref.get_ref()
		if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
			continue
		var member := value as Aircraft
		if member != null:
			# 清理边界也覆盖已进入 destroyed 终态、但尚未释放的成员。
			member.set_afterburner_mode_active(enabled)


func _update_active_member_effects(delta: float) -> void:
	for member in _live_members():
		if not _storm_i_triggered and _storm_i_spent >= SkillHooks.STORM_I_CHARGE_SPENT \
				and SkillHooks.has_skill(member, SkillHooks.SKILL_STORM_I):
			member.apply_status(StatusEffects.OVERLOAD, SkillHooks.STORM_I_OVERLOAD_DURATION)
		if member.sig_su34_active and member.params != null:
			member.hp = minf(
				member.hp + SIG_SU34_HEAL_PER_SEC * delta, member.params.max_hp)
	if not _storm_i_triggered and _storm_i_spent >= SkillHooks.STORM_I_CHARGE_SPENT:
		_storm_i_triggered = true


func _live_members() -> Array[Aircraft]:
	var result: Array[Aircraft] = []
	for member_ref in _member_refs:
		var value: Variant = member_ref.get_ref()
		if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
			continue
		var member := value as Aircraft
		if _valid_aircraft(member):
			result.append(member)
	return result


func _leader() -> Aircraft:
	if _leader_ref == null:
		return null
	var value: Variant = _leader_ref.get_ref()
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null
	return value as Aircraft


func _clear_activation() -> void:
	_leader_ref = null
	_member_refs.clear()
	_storm_i_spent = 0.0
	_storm_i_triggered = false


static func _valid_aircraft(value: Variant) -> bool:
	return typeof(value) == TYPE_OBJECT and is_instance_valid(value) \
		and value is Aircraft and not (value as Aircraft).is_destroyed
