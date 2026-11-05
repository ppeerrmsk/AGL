extends Node
## 同一正式战场 A/B，只关闭能力；另定时注入真实来源 FEAR 覆盖多人受控成本。

## 美术压测显式开启：原战斗完整保留，持续绘制一个占屏幕大部分高度的正式锥体。
## 只证明绘制负载；不伪造控制器命中、施法次数或自然触发覆盖。
class VisualLoad extends Node2D:
	var renderer := preload("res://scripts/ui/fear_cone_visual.gd").new()
	var config := SquadFearConeConfig.new()
	var elapsed := 0.0
	var draws := 0

	func _draw() -> void:
		var size := get_viewport_rect().size
		var scale_factor := minf(size.x / 1600.0, size.y / 900.0) * 0.48
		var frame := Transform2D(0.0, Vector2(size.x * 0.5, size.y * 0.87))
		frame = frame.scaled_local(Vector2.ONE * scale_factor)
		renderer.draw(self, frame, config, true, config.emission_s - fposmod(elapsed, config.emission_s))
		draws += 1

var _visual_load: VisualLoad
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
	if enabled and OS.get_environment("AGL_BENCH_FEAR_VISUAL_STRESS") == "1":
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		_visual_load = VisualLoad.new()
		layer.add_child(_visual_load)
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
	if is_instance_valid(_visual_load):
		_visual_load.elapsed += delta
		_visual_load.queue_redraw()
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
	return "fear_probe enabled=%s applications=%d fear_frames=%d peak_feared=%d cone_frames=%d render_probe_draws=%d" % [
		_enabled, _applications, _fear_frames, _peak_feared, _cone_frames,
		_visual_load.draws if is_instance_valid(_visual_load) else 0]

func capture() -> void:
	await RenderingServer.frame_post_draw
	var suffix := "enabled" if _enabled else "baseline"
	get_viewport().get_texture().get_image().save_png("res://bench/results/fear_%s_%s.png" % [BenchRunner.bench_scenario, suffix])

func _exit_tree() -> void:
	if _cone != null: _cone.dispose()
