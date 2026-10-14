extends RefCounted
const Clock := preload("res://scripts/tests/tokyo_render_clock.gd")
## 仅显式bench诊断：实际时钟阶段，不同步GPU，不修改绘制状态或帧率设置。
var _views: Array[WeakRef] = []
var _backend := false
var _closed := true
var _begin := 0
var _pre := 0
var _post := 0
var _previous_post := 0
var _post_intervals := PackedInt64Array()
var _frame := 0
var _samples := 0
var _invalid := 0
var _below := 0
var _wall_total := 0
var _wall_max := 0
var _latest: Dictionary = {}
var _slow: Array[Dictionary] = []
var _slow_considered := 0
var _gpu_nonzero := 0
var _backend_samples := 0
var _phase_total := PackedInt64Array([0, 0, 0])
var _backend_total: Dictionary = {}
var _backend_peaks: Dictionary = {}
var _clock_anchor: Dictionary = {}
var _capture_path := ""
var _capture_status := "disabled"
const BACKEND_KEYS := ["root_cpu_ms", "root_gpu_ms", "map_cpu_ms", "map_gpu_ms", "aircraft_cpu_ms", "aircraft_gpu_ms", "setup_cpu_ms"]


func setup(root: Viewport, map_view: Viewport, backend: bool, aircraft_view: Variant = null) -> void:
	# 只取一次系统时钟并保留夹逼区间；用于ETL对齐，不把UTC跳变当成帧时长。
	var anchor_before := Time.get_ticks_usec()
	var anchor_utc := roundi(Time.get_unix_time_from_system()*1000000.0)
	var anchor_after := Time.get_ticks_usec()
	_clock_anchor={"pid":OS.get_process_id(),"utc_usec":anchor_utc,
		"ticks_before_usec":anchor_before,"ticks_after_usec":anchor_after,
		"same_frame_gpu_proof":false}
	_capture_path=OS.get_environment("AGL_TOKYO_DRAW_CAPTURE")
	if not _capture_path.is_empty():
		_capture_status="refused_existing"
		if not FileAccess.file_exists(_capture_path) and not FileAccess.file_exists(_capture_path+".ready"):
			var ready := FileAccess.open(_capture_path+".ready",FileAccess.WRITE)
			_capture_status="ready_failed" if ready==null else "waiting"
			if ready!=null:
				ready.store_string(JSON.stringify(_clock_anchor))
				ready.close()
	_views = [weakref(root), weakref(map_view)]
	if typeof(aircraft_view) == TYPE_OBJECT and is_instance_valid(aircraft_view) and aircraft_view is Viewport:
		_views.append(weakref(aircraft_view))
	_backend = backend
	_closed = false
	if backend:
		for reference in _views:
			var view: Variant = reference.get_ref()
			RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	RenderingServer.frame_pre_draw.connect(_before_draw)
	RenderingServer.frame_post_draw.connect(_after_draw)


func begin_frame(delta: float, now_usec: int = -1) -> void:
	if _closed:
		return
	var now := Time.get_ticks_usec() if now_usec < 0 else now_usec
	if not PerfBuckets.frame_trace_enabled:
		_begin = 0
		return
	if _begin > 0:
		var phases := Clock.partition(_begin, _pre, _post, now)
		if phases.is_empty():
			_invalid += 1
		else:
			_samples += 1
			_wall_total += phases[3]
			_wall_max = maxi(_wall_max, phases[3])
			for index in 3:
				_phase_total[index] += phases[index]
			# 在父类结算上一帧之前附到同一个trace frame；均非CPU根桶。
			PerfBuckets.tick("tokyo_map_wall_before_draw", phases[0])
			PerfBuckets.tick("tokyo_map_wall_draw", phases[1])
			PerfBuckets.tick("tokyo_map_wall_after_draw", phases[2])
			PerfBuckets.tick("tokyo_map_wall_total", phases[3])
			_below += int(not Clock.frame_within_budget(phases[3]))
			if not Clock.frame_within_budget(phases[3]) or delta > 1.0 / 60.0:
				_slow_considered += 1
				Clock.retain_slowest(_slow, {"frame": _frame, "engine_delta_ms": delta * 1000.0,
					"begin_ticks_usec":_begin,"pre_ticks_usec":_pre,"post_ticks_usec":_post,"next_ticks_usec":now,
					"before_draw_us": phases[0], "draw_us": phases[1], "after_draw_us": phases[2],
					"wall_us": phases[3], "latest_backend_not_same_frame_proof": _latest.duplicate(),
					"cpu_buckets_us":PerfBuckets._trace_frame_us.duplicate(),
					"events":PerfBuckets._trace_frame_events.duplicate()})
				_capture_draw_spike(phases,now)
	_begin = now
	_pre = 0
	_post = 0
	_frame = PerfBuckets._trace_frame_index + 1


func _capture_draw_spike(phases: PackedInt64Array, now: int) -> void:
	# 只在显式诊断且上一帧已结束后写一次；文件I/O不计入被捕获帧，但会污染后续帧。
	if _capture_status!="waiting" or phases[1]<8000 or Clock.frame_within_budget(phases[3]): return
	if not FileAccess.file_exists(_capture_path+".armed"): return
	_capture_status="refused_existing" if FileAccess.file_exists(_capture_path) else "write_failed"
	if _capture_status=="refused_existing": return
	var file := FileAccess.open(_capture_path,FileAccess.WRITE)
	if file==null: return
	file.store_string(JSON.stringify({"diagnostic_only":true,"subsequent_frames_contaminated":true,
		"clock_anchor":_clock_anchor,"frame":_frame,"begin_ticks_usec":_begin,
		"pre_ticks_usec":_pre,"post_ticks_usec":_post,"next_ticks_usec":now,
		"phases_us":phases,"cpu_buckets_us":PerfBuckets._trace_frame_us.duplicate()}))
	file.close()
	_capture_status="captured"


func _before_draw() -> void:
	if not _closed and _begin > 0:
		_pre = Time.get_ticks_usec()


func _after_draw() -> void:
	if _closed or _begin <= 0:
		return
	_post = Time.get_ticks_usec()
	if _previous_post>0 and _post_intervals.size()<120000:
		_post_intervals.append(_post-_previous_post)
	_previous_post=_post
	if not _backend:
		return
	for index in _views.size():
		var view: Variant = _views[index].get_ref()
		if typeof(view) != TYPE_OBJECT or not is_instance_valid(view):
			close()
			return
		var rid: RID = view.get_viewport_rid()
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		var label: String = ["root", "map", "aircraft"][index]
		_latest[label + "_cpu_ms"] = cpu
		_latest[label + "_gpu_ms"] = gpu
		_gpu_nonzero += int(gpu > 0.0 and is_finite(gpu))
	_latest["setup_cpu_ms"] = RenderingServer.get_frame_setup_time_cpu()
	for key: String in _latest:
		_backend_total[key] = float(_backend_total.get(key, 0.0)) + float(_latest[key])
	_backend_samples += 1
	retain_backend_peaks(_backend_peaks, _latest, _backend_samples, _frame)


static func retain_backend_peaks(peaks: Dictionary, values: Dictionary, sample: int, frame: int) -> void:
	# 后端可能延迟数帧；峰值独立保存读回序号和整份同次数据，不宣称与墙钟帧对齐。
	for key: String in BACKEND_KEYS:
		var raw: Variant = values.get(key)
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)) or float(raw) < 0.0:
			continue
		if not peaks.has(key) or float(raw) > float(peaks[key].value_ms):
			peaks[key] = {"value_ms": float(raw), "readback_sample": sample, "observed_frame": frame, "values": values.duplicate(true)}


func close() -> void:
	if _closed:
		return
	_closed = true
	if RenderingServer.frame_pre_draw.is_connected(_before_draw):
		RenderingServer.frame_pre_draw.disconnect(_before_draw)
	if RenderingServer.frame_post_draw.is_connected(_after_draw):
		RenderingServer.frame_post_draw.disconnect(_after_draw)
	if _backend:
		for reference in _views:
			var view: Variant = reference.get_ref()
			if typeof(view) == TYPE_OBJECT and is_instance_valid(view):
				RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), false)
	_views.clear()


func summary() -> String:
	var backend_means := {}
	for key: String in _backend_total:
		backend_means[key] = float(_backend_total[key]) / maxi(1, _backend_samples)
	return "tokyo_render_trace=" + JSON.stringify({"diagnostic_only": true, "backend": _backend,
		"clock_anchor":_clock_anchor,
		"draw_capture_status":_capture_status,
		"samples": _samples, "invalid_phases": _invalid, "wall_below60": _below,
		"wall_avg_ms": float(_wall_total) / maxf(_samples, 1) / 1000.0,
		"before_draw_avg_ms": _phase_total[0] / maxf(_samples, 1) / 1000.0,
		"draw_signal_avg_ms": _phase_total[1] / maxf(_samples, 1) / 1000.0,
		"after_draw_avg_ms": _phase_total[2] / maxf(_samples, 1) / 1000.0,
		"backend_means_not_same_frame_proof": backend_means,
		"backend_peaks_not_same_frame_proof": _backend_peaks,
		"wall_max_ms": _wall_max / 1000.0, "slow_records": _slow,
		"slow_records_policy": "highest_wall_32", "slow_records_considered": _slow_considered,
		"slow_records_omitted": maxi(0, _slow_considered - _slow.size()),
		"backend_samples": _backend_samples, "gpu_nonzero_view_samples": _gpu_nonzero,
		"max_fps": Engine.max_fps, "vsync_mode": DisplayServer.window_get_vsync_mode(),
		"post_draw_cadence":Clock.percentiles_usec(_post_intervals),
		"renderer": RenderingServer.get_current_rendering_method(), "closed": _closed})
