class_name SquadFearConeController
extends RefCounted

## 宿主接口：fear_members()、fear_targets()、fear_enabled()；只弱持有宿主。
enum Phase { WAIT, READY, WARNING, EMISSION, STOPPED }
static var registry: Array[WeakRef] = []
var config: SquadFearConeConfig
var phase := Phase.STOPPED
var remaining := 0.0
var exposure: Dictionary = {}
var triggered: Dictionary = {}
var _host: WeakRef
var _emitter: WeakRef
var _last_emitter_id := 0
var _decision_s := 0.0
var _sample_s := 0.0
var _rng := RandomNumberGenerator.new()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# RefCounted 已进入销毁，不能再调自己的实例方法。
		var value: Variant = _emitter.get_ref() if _emitter != null else null
		if typeof(value) == TYPE_OBJECT and is_instance_valid(value):
			value.remove_meta(&"fear_cone_emitting")

func setup(settings: SquadFearConeConfig, host: Object) -> bool:
	if settings == null or not settings.valid():
		push_error("Fear cone: invalid configuration")
		return false
	config = settings.duplicate(true)
	_host = weakref(host)
	_rng.randomize()
	registry.append(weakref(self))
	return true

func start() -> void:
	if config == null or phase != Phase.STOPPED:
		return
	phase = Phase.WAIT
	remaining = config.initial_wait_s

func stop() -> void:
	_release_emitter()
	phase = Phase.STOPPED
	exposure.clear()
	triggered.clear()

func dispose() -> void:
	stop()
	_host = null
	for i in range(registry.size() - 1, -1, -1):
		if registry[i].get_ref() == null or registry[i].get_ref() == self:
			registry.remove_at(i)

func emitter() -> Aircraft:
	return FearResponse.aircraft(_emitter.get_ref() if _emitter != null else null)

func _release_emitter() -> void:
	var ac := emitter()
	if ac != null:
		ac.remove_meta(&"fear_cone_emitting")
	_emitter = null

func _cooldown() -> void:
	_release_emitter()
	exposure.clear()
	triggered.clear()
	phase = Phase.WAIT
	remaining = _rng.randf_range(config.cooldown_min_s, config.cooldown_max_s)

func update(delta: float) -> void:
	if phase == Phase.STOPPED:
		return
	var host: Variant = _host.get_ref() if _host != null else null
	if typeof(host) != TYPE_OBJECT or not is_instance_valid(host) or not host.fear_enabled():
		stop()
		return
	if phase == Phase.WARNING or phase == Phase.EMISSION:
		var ac := emitter()
		if not _visible_candidate(ac):
			_cooldown()
			return
		remaining -= delta
		if remaining <= 0.0:
			if phase == Phase.WARNING:
				phase = Phase.EMISSION
				remaining = config.emission_s
				_sample_s = 0.0
			else:
				_cooldown()
			return
		if phase == Phase.EMISSION:
			_sample_s += delta
			if _sample_s >= 0.1:
				_sample_s = fmod(_sample_s, 0.1)
				_sample(host.fear_targets(), ac)
		return
	remaining -= delta
	if remaining > 0.0:
		return
	phase = Phase.READY
	_decision_s -= delta
	if _decision_s > 0.0:
		return
	_decision_s = 0.5
	_select(host.fear_members(), host.fear_targets())

func _visible_candidate(value: Variant) -> bool:
	var ac := FearResponse.aircraft(value)
	return ac != null and not ac.is_destroyed and not ac.is_cloaked \
		and not ac.is_hidden_from_player_sensors() \
		and not ac.has_meta(CombatUnit.META_PRESENTATION_ACTOR_ACTIVE)

func contains(ac: Aircraft, target: Aircraft) -> bool:
	var offset := target.global_position - ac.global_position
	var length_sq := offset.length_squared()
	if length_sq > pow(config.range_m * CombatUnit.PIXELS_PER_METER, 2):
		return false
	return length_sq < 0.001 or offset.normalized().dot(Vector2(sin(ac.heading), -cos(ac.heading))) \
		>= cos(deg_to_rad(config.angle_deg * 0.5)) - 0.000001

func _select(members: Array, targets: Array) -> bool:
	# 从上次成员之后轮转；单成员时允许再次施放。
	var start_index := 0
	for i in range(members.size()):
		var old := FearResponse.aircraft(members[i])
		if old != null and old.get_instance_id() == _last_emitter_id:
			start_index = i + 1
	for n in range(members.size()):
		var ac := FearResponse.aircraft(members[(start_index + n) % members.size()])
		if not _visible_candidate(ac) or ac.has_meta(&"fear_cone_emitting"):
			continue
		for value: Variant in targets:
			var target := FearResponse.aircraft(value)
			if FearResponse.eligible(target) and target.is_hostile_to(ac) and contains(ac, target):
				_emitter = weakref(ac)
				_last_emitter_id = ac.get_instance_id()
				ac.set_meta(&"fear_cone_emitting", true)
				phase = Phase.WARNING
				remaining = config.warning_s
				exposure.clear()
				triggered.clear()
				return true
	return false

func _sample(targets: Array, ac: Aircraft) -> void:
	var live: Dictionary = {}
	for value: Variant in targets:
		var target := FearResponse.aircraft(value)
		if target == null:
			continue
		var id := target.get_instance_id()
		if not FearResponse.eligible(target) or not target.is_hostile_to(ac) \
				or triggered.has(id) or not contains(ac, target):
			exposure.erase(id)
			continue
		live[id] = true
		exposure[id] = float(exposure.get(id, 0.0)) + 0.1
		if float(exposure[id]) + 0.00001 >= config.exposure_s:
			if FearResponse.apply(target, ac, config.fear_s):
				triggered[id] = true
			exposure.erase(id)
	for id: Variant in exposure.keys():
		if not live.has(id):
			exposure.erase(id)

func debug_cast() -> bool:
	var host: Variant = _host.get_ref() if _host != null else null
	if typeof(host) != TYPE_OBJECT or not is_instance_valid(host) or not host.fear_enabled():
		return false
	if phase == Phase.WARNING or phase == Phase.EMISSION:
		return false
	return _select(host.fear_members(), host.fear_targets())

static func live_controllers() -> Array[SquadFearConeController]:
	var result: Array[SquadFearConeController] = []
	for i in range(registry.size() - 1, -1, -1):
		var value: Variant = registry[i].get_ref()
		if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
			registry.remove_at(i)
		else:
			result.append(value as SquadFearConeController)
	return result
