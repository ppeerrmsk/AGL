extends Node
## 同一正式战场 A/B，只关闭能力；另定时注入真实来源 FEAR 覆盖多人受控成本。
var _enabled := false
var _members: Array[WeakRef] = []
var _targets: Array[WeakRef] = []
var _cone: SquadFearConeController
var _timer := 0.0
var _applications := 0
var _cone_frames := 0
var _fear_frames := 0
var _peak_feared := 0
var _ready_for_sample := false

func start(mode: Node, enabled: bool) -> void:
	_enabled = enabled
	await get_tree().create_timer(2.0).timeout
	for value: Variant in CombatUnit.all_units:
		var ac := FearResponse.aircraft(value)
		if ac == null or ac.is_destroyed: continue
		if ac.is_player_squad(): _targets.append(weakref(ac))
		elif ac.team == CombatUnit.TEAM_HOSTILE: _members.append(weakref(ac))
	var squad: AceSquad = mode._spawner.get_ace_squad()
	if squad != null and squad.fear_cone != null:
		if not enabled:
			squad.fear_cone.dispose()
			squad.fear_cone = null
			squad.fear_cone_config = null
	elif enabled:
		_cone = SquadFearConeController.new()
		_cone.setup(SquadFearConeConfig.new(), self)
		_cone.start()
	_ready_for_sample = true

func fear_members() -> Array:
	return _live(_members)

func fear_targets() -> Array:
	return _live(_targets)

func fear_enabled() -> bool:
	return _enabled

func _live(refs: Array[WeakRef]) -> Array:
	var result: Array = []
	for ref in refs:
		var ac := FearResponse.aircraft(ref.get_ref())
		if ac != null and not ac.is_destroyed: result.append(ac)
	return result

func _process(delta: float) -> void:
	if not _ready_for_sample: return
	if _cone != null: _cone.update(delta)
	_timer -= delta
	if _timer <= 0.0:
		_timer = 8.2
		var sources := fear_members()
		if _enabled and not sources.is_empty():
			for target in fear_targets():
				if FearResponse.apply(target, sources[0]): _applications += 1
	var feared := 0
	for target in fear_targets():
		if FearResponse.controlled(target): feared += 1
	if feared > 0: _fear_frames += 1
	_peak_feared = maxi(_peak_feared, feared)
	for controller in SquadFearConeController.live_controllers():
		if controller.emitter() != null:
			_cone_frames += 1
			break

func summary() -> String:
	return "fear_probe enabled=%s applications=%d fear_frames=%d peak_feared=%d cone_frames=%d" % [
		_enabled, _applications, _fear_frames, _peak_feared, _cone_frames]

func capture() -> void:
	await RenderingServer.frame_post_draw
	var suffix := "enabled" if _enabled else "baseline"
	get_viewport().get_texture().get_image().save_png("res://bench/results/fear_%s_%s.png" % [BenchRunner.bench_scenario, suffix])

func _exit_tree() -> void:
	if _cone != null: _cone.dispose()
