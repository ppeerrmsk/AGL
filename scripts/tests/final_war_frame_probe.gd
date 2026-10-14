extends "res://scripts/survivor/survivor_mode.gd"
## 保持正式FINAL WAR编成，补独立墙钟与显式渲染阶段诊断。
var _frame_clock := preload("res://scripts/tests/map_frame_clock.gd").new()
var _render_trace: RefCounted


func _ready() -> void:
	super._ready()
	if OS.get_environment("AGL_MAP_GPU_TRACE") == "1" and is_instance_valid(_map_features._ocean_volume):
		_render_trace = preload("res://scripts/tests/tokyo_render_trace.gd").new()
		_render_trace.setup(get_viewport(), _map_features._ocean_volume._viewport, true,
			_aircraft_volume_overlay._subviewport if is_instance_valid(_aircraft_volume_overlay) else null)


func _process(delta: float) -> void:
	_frame_clock.observe(_bench_elapsed >= 3.0)
	if _render_trace != null:
		_render_trace.begin_frame(delta)
	super._process(delta)


func _bench_finish_now(summary: String, exit_code: int = 0) -> void:
	if _render_trace != null:
		_render_trace.close()
		summary += _render_trace.summary() + "\n"
	var wall := _frame_clock.report()
	summary += "map_wall_clock=" + JSON.stringify(wall) + "\n"
	if not wall.passed or not summary.contains("frames_below_60=0\n"):
		exit_code = 1
	super._bench_finish_now(summary, exit_code)


func _exit_tree() -> void:
	if _render_trace != null:
		_render_trace.close()
	super._exit_tree()
