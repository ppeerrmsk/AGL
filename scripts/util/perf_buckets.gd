extends Node

## 性能采集桶（AutoLoad）—— 用来定位帧率掉点原因
##
## 设计：
## - tick(name, us)：累加一段代码的 µs 耗时，调用 N 次后给出每帧均值
## - count(name, n)：累加每帧计数（雷达对、各类单位数等）
## - set_value(name, v)：写入瞬时值（"all_units 当前总数"这种快照型指标）
## - 1 秒滚动窗口：每秒把 _window_* 累加值快照到 _snap_*，HUD/F9 dump 读快照
## - 全局开关 `enabled` 控制是否记录；关闭时 tick/count 立即返回
##
## 用法：
##   var _t0 := Time.get_ticks_usec()
##   ... 工作 ...
##   PerfBuckets.tick("radar_locks", Time.get_ticks_usec() - _t0)

const WINDOW_S: float = 1.0
const FRAME_BUDGET_S: float = 1.0 / 60.0
const FRAME_TRACE_MAX_SPIKES: int = 128
const FRAME_TRACE_REPORT_SPIKES: int = 16
const FRAME_TRACE_ENGINE_SAMPLE_STRIDE: int = 30
const FRAME_TRACE_PRE_CONTEXT_FRAMES: int = 120
const FRAME_TRACE_POST_CONTEXT_FRAMES: int = 30
const FRAME_TRACE_MAX_CONTEXT_WINDOWS: int = 8
const RUNTIME_FRAME_HISTORY_SIZE: int = 120
const RUNTIME_HOTSPOT_LIMIT: int = 10
const FRAME_TRACE_ROOT_BUCKETS := [
	"aircraft_phys", "ai_tick", "radar_locks", "ground_phys", "naval_phys",
	"mount_target_phys", "bullet_phys", "missile_phys", "atmosphere_tick",
	"aircraft_draw", "trail_draw", "ground_draw", "naval_draw", "bullet_draw",
	"missile_draw", "missile_trail_draw", "hud_process", "hud_player_draw",
	"hud_grid_draw", "hud_radar_draw", "hud_threat_draw", "event_log",
	"audio_sfx_play", "radio_play", "spawn_enemy",
]

# ── 当前窗口累加 ──
var _window_us: Dictionary = {}     ## bucket_name -> int µs 总和
var _window_calls: Dictionary = {}  ## bucket_name -> int 调用次数
var _window_counts: Dictionary = {} ## name -> int 累加计数（雷达对/帧等）
var _values: Dictionary = {}        ## name -> Variant 瞬时值（last write wins）

# ── 上一个完成窗口的快照（HUD / F9 读这个）──
var _snap_us: Dictionary = {}
var _snap_calls: Dictionary = {}
var _snap_counts: Dictionary = {}

var _window_elapsed: float = 0.0
var _frames_in_window: int = 0
var _last_window_frames: int = 0
var _last_window_seconds: float = 1.0

## 全局开关：关掉之后 tick/count 立即 return，开销可忽略
var enabled: bool = true

# ── F3 运行时性能面板 ──
# 只在面板打开时记录固定长度帧历史，并启用昂贵的细分埋点；关闭后不分配、不排序。
var runtime_panel_enabled: bool = false
var _runtime_frame_history := PackedFloat32Array()
var _runtime_frame_cursor: int = 0
var _runtime_frame_count: int = 0

# ── Bench-only 逐帧尖峰追踪 ──
# 普通游戏恒关闭；开启后只保留超过 60 FPS 帧预算的紧凑摘要，避免追踪器自身制造大数组。
var frame_trace_enabled: bool = false
var _trace_detail_stride: int = 1
var _trace_detail_this_frame: bool = false
var _trace_frame_index: int = 0
var _trace_has_pending_frame: bool = false
var _trace_physics_ticks: int = 0
var _trace_frame_us: Dictionary = {}
var _trace_frame_counts: Dictionary = {}
var _trace_frame_events: Dictionary = {}
var _trace_spikes: Array[Dictionary] = []
var _trace_frames_below_60: int = 0
var _trace_dropped_spikes: int = 0
var _trace_spike_event_counts: Dictionary = {}
var _trace_engine_sample_sum: Dictionary = {}
var _trace_engine_sample_max: Dictionary = {}
var _trace_engine_samples: int = 0
var _trace_frame_deltas_ms := PackedFloat32Array()
var _trace_recent_frames: Array[Dictionary] = []
var _trace_context_windows: Array[Dictionary] = []
var _trace_active_context: Dictionary = {}


## 累加一段代码的 µs 耗时
func tick(name: String, us: int) -> void:
	if not enabled:
		return
	_window_us[name] = int(_window_us.get(name, 0)) + us
	_window_calls[name] = int(_window_calls.get(name, 0)) + 1
	if frame_trace_enabled:
		_trace_frame_us[name] = int(_trace_frame_us.get(name, 0)) + us


## 累加每帧计数（如 radar pair evaluations / draw calls）
func count(name: String, n: int = 1) -> void:
	if not enabled:
		return
	_window_counts[name] = int(_window_counts.get(name, 0)) + n
	if frame_trace_enabled:
		_trace_frame_counts[name] = int(_trace_frame_counts.get(name, 0)) + n


## 写入瞬时值（不累加，覆盖）
func set_value(name: String, v: Variant) -> void:
	_values[name] = v


func get_value(name: String, default_v: Variant = null) -> Variant:
	return _values.get(name, default_v)


func configure_runtime_panel(active: bool) -> void:
	runtime_panel_enabled = active
	_runtime_frame_cursor = 0
	_runtime_frame_count = 0
	if active:
		_runtime_frame_history.resize(RUNTIME_FRAME_HISTORY_SIZE)
		for index in range(RUNTIME_FRAME_HISTORY_SIZE):
			_runtime_frame_history[index] = 0.0
	else:
		_runtime_frame_history.clear()


func detail_capture_enabled() -> bool:
	return runtime_panel_enabled or (frame_trace_enabled and _trace_detail_this_frame)


## 仅由代表性性能 bench 开启；重置上一次场景遗留的追踪状态。
func configure_frame_trace(active: bool) -> void:
	var requested_mode := OS.get_environment("AGL_BENCH_FRAME_TRACE_MODE").strip_edges().to_lower()
	frame_trace_enabled = active and requested_mode != "off"
	# G0 默认用 1/4 细分采样控制观察者效应；根桶、慢帧 delta、事件和引擎快照仍逐帧。
	# 复现单个尖峰需要全部子桶时显式设 AGL_BENCH_FRAME_TRACE_MODE=full。
	_trace_detail_stride = 1 if requested_mode == "full" else 4
	if requested_mode == "sampled":
		var stride_text := OS.get_environment("AGL_BENCH_TRACE_DETAIL_STRIDE").strip_edges()
		_trace_detail_stride = maxi(int(stride_text) if stride_text.is_valid_int() else 4, 2)
	_trace_detail_this_frame = false
	_trace_frame_index = 0
	_trace_has_pending_frame = false
	_trace_physics_ticks = 0
	_trace_frame_us.clear()
	_trace_frame_counts.clear()
	_trace_frame_events.clear()
	_trace_spikes.clear()
	_trace_frames_below_60 = 0
	_trace_dropped_spikes = 0
	_trace_spike_event_counts.clear()
	_trace_engine_sample_sum.clear()
	_trace_engine_sample_max.clear()
	_trace_engine_samples = 0
	_trace_frame_deltas_ms.clear()
	_trace_recent_frames.clear()
	_trace_context_windows.clear()
	_trace_active_context.clear()


## SurvivorMode 在渲染帧开头调用：结算上一帧并开始收集当前帧。
func begin_render_frame(delta: float) -> void:
	if runtime_panel_enabled:
		_record_runtime_frame(delta)
	if not frame_trace_enabled:
		return
	if _trace_has_pending_frame:
		var engine_snapshot: Dictionary = {}
		# 当前 delta 是从上次 _process 开头到本次 _process 开头的真实耗时，必须与期间
		# 收集的桶配对；旧实现误用上次 delta，导致桶/physics 与慢帧整体错位一帧。
		if delta > FRAME_BUDGET_S:
			engine_snapshot = _trace_engine_snapshot()
		_finalize_trace_frame(delta, engine_snapshot)
	_trace_frame_index += 1
	_trace_detail_this_frame = (_trace_frame_index - 1) % _trace_detail_stride == 0
	if _trace_frame_index % FRAME_TRACE_ENGINE_SAMPLE_STRIDE == 0:
		_accumulate_engine_baseline(_trace_engine_snapshot())
	_trace_has_pending_frame = true
	_trace_physics_ticks = 0
	_trace_frame_us.clear()
	_trace_frame_counts.clear()
	_trace_frame_events.clear()


func _record_runtime_frame(delta: float) -> void:
	if _runtime_frame_history.size() != RUNTIME_FRAME_HISTORY_SIZE:
		return
	_runtime_frame_history[_runtime_frame_cursor] = maxf(delta, 0.0)
	_runtime_frame_cursor = (_runtime_frame_cursor + 1) % RUNTIME_FRAME_HISTORY_SIZE
	_runtime_frame_count = mini(_runtime_frame_count + 1, RUNTIME_FRAME_HISTORY_SIZE)


func runtime_frame_stats() -> Dictionary:
	if _runtime_frame_count <= 0:
		return {
			"samples": 0, "avg_ms": 0.0, "p95_ms": 0.0,
			"worst_ms": 0.0, "below_60": 0,
		}
	var samples: Array[float] = []
	var total_s := 0.0
	var worst_s := 0.0
	var below_60 := 0
	for index in range(_runtime_frame_count):
		var sample_s := float(_runtime_frame_history[index])
		samples.append(sample_s)
		total_s += sample_s
		worst_s = maxf(worst_s, sample_s)
		if sample_s > FRAME_BUDGET_S:
			below_60 += 1
	samples.sort()
	var p95_index := clampi(ceili(float(samples.size()) * 0.95) - 1,
		0, samples.size() - 1)
	return {
		"samples": samples.size(),
		"avg_ms": total_s * 1000.0 / float(samples.size()),
		"p95_ms": samples[p95_index] * 1000.0,
		"worst_ms": worst_s * 1000.0,
		"below_60": below_60,
	}


func mark_physics_tick() -> void:
	if frame_trace_enabled:
		_trace_physics_ticks += 1


## 标记低频系统或事件是否与慢帧同帧发生；仅 bench trace 开启时记账。
func mark_frame_event(name: String) -> void:
	if frame_trace_enabled:
		_trace_frame_events[name] = int(_trace_frame_events.get(name, 0)) + 1


func _finalize_trace_frame(delta: float, engine_snapshot: Dictionary) -> void:
	var known_us := _trace_known_root_us()
	var frame_summary := {
		"frame": _trace_frame_index,
		"delta_ms": delta * 1000.0,
		"known_ms": float(known_us) / 1000.0,
		"unaccounted_ms": maxf(delta * 1000.0 - float(known_us) / 1000.0, 0.0),
		"physics_ticks": _trace_physics_ticks,
		"buckets_us": _trace_frame_us.duplicate(),
		"counts": _trace_frame_counts.duplicate(),
		"events": _trace_frame_events.duplicate(),
		"load": _trace_load_snapshot(),
		"engine": engine_snapshot,
	}
	_trace_frame_deltas_ms.append(delta * 1000.0)
	var is_slow := delta > FRAME_BUDGET_S
	if is_slow:
		_trace_frames_below_60 += 1
		for event_name in _trace_frame_events:
			_trace_spike_event_counts[event_name] = int(
				_trace_spike_event_counts.get(event_name, 0)) \
				+ int(_trace_frame_events[event_name])
		if _trace_spikes.size() >= FRAME_TRACE_MAX_SPIKES:
			_trace_dropped_spikes += 1
		else:
			_trace_spikes.append(frame_summary.duplicate(true))
	_update_trace_context(frame_summary, is_slow)
	_trace_recent_frames.append(_compact_trace_frame(frame_summary))
	if _trace_recent_frames.size() > FRAME_TRACE_PRE_CONTEXT_FRAMES:
		_trace_recent_frames.pop_front()


## 每个尖峰簇保留前 120 / 后 30 帧；后续尖峰会延长同一窗口，避免重复保存重叠上下文。
func _update_trace_context(frame_summary: Dictionary, is_slow: bool) -> void:
	var started_now := false
	if is_slow and _trace_active_context.is_empty() \
			and _trace_context_windows.size() < FRAME_TRACE_MAX_CONTEXT_WINDOWS:
		var pre_frames: Array[Dictionary] = []
		for prior in _trace_recent_frames:
			pre_frames.append(prior.duplicate(true))
		_trace_active_context = {
			"start_frame": int(frame_summary["frame"]) - pre_frames.size(),
			"pre_frames": pre_frames.size(),
			"trigger_frames": [int(frame_summary["frame"])],
			"post_remaining": FRAME_TRACE_POST_CONTEXT_FRAMES,
			"frames": pre_frames,
			"complete": false,
		}
		started_now = true
	if _trace_active_context.is_empty():
		return
	var frames: Array = _trace_active_context.get("frames", [])
	frames.append(_compact_trace_frame(frame_summary))
	_trace_active_context["frames"] = frames
	if is_slow:
		var triggers: Array = _trace_active_context.get("trigger_frames", [])
		if not started_now:
			triggers.append(int(frame_summary["frame"]))
		_trace_active_context["trigger_frames"] = triggers
		_trace_active_context["post_remaining"] = FRAME_TRACE_POST_CONTEXT_FRAMES
		return
	var remaining := int(_trace_active_context.get(
		"post_remaining", FRAME_TRACE_POST_CONTEXT_FRAMES)) - 1
	_trace_active_context["post_remaining"] = remaining
	if remaining <= 0:
		_trace_active_context["complete"] = true
		_trace_active_context["end_frame"] = int(frame_summary["frame"])
		_trace_context_windows.append(_trace_active_context)
		_trace_active_context = {}


func _compact_trace_frame(frame_summary: Dictionary) -> Dictionary:
	return {
		"frame": int(frame_summary.get("frame", 0)),
		"delta_ms": float(frame_summary.get("delta_ms", 0.0)),
		"known_ms": float(frame_summary.get("known_ms", 0.0)),
		"physics_ticks": int(frame_summary.get("physics_ticks", 0)),
		"buckets_us": (frame_summary.get("buckets_us", {}) as Dictionary).duplicate(),
		"counts": (frame_summary.get("counts", {}) as Dictionary).duplicate(),
		"events": (frame_summary.get("events", {}) as Dictionary).duplicate(),
		"load": (frame_summary.get("load", {}) as Dictionary).duplicate(),
		"engine": (frame_summary.get("engine", {}) as Dictionary).duplicate(),
	}


func _trace_known_root_us() -> int:
	var total := 0
	for bucket_name in FRAME_TRACE_ROOT_BUCKETS:
		total += int(_trace_frame_us.get(bucket_name, 0))
	return total


func _trace_engine_snapshot() -> Dictionary:
	var snapshot := {
		"nodes": roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": roundi(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"process_us": roundi(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0),
		"physics_us": roundi(
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0),
	}
	var viewport := get_viewport()
	if viewport != null:
		var viewport_rid := viewport.get_viewport_rid()
		snapshot["canvas_objects"] = RenderingServer.viewport_get_render_info(
			viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		snapshot["canvas_primitives"] = RenderingServer.viewport_get_render_info(
			viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		snapshot["canvas_draw_calls"] = RenderingServer.viewport_get_render_info(
			viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	return snapshot


func _accumulate_engine_baseline(snapshot: Dictionary) -> void:
	_trace_engine_samples += 1
	for key in snapshot:
		var value := int(snapshot[key])
		_trace_engine_sample_sum[key] = int(_trace_engine_sample_sum.get(key, 0)) + value
		_trace_engine_sample_max[key] = maxi(int(_trace_engine_sample_max.get(key, 0)), value)


func _trace_engine_baseline_avg() -> Dictionary:
	var averages := {}
	if _trace_engine_samples <= 0:
		return averages
	for key in _trace_engine_sample_sum:
		averages[key] = roundi(float(_trace_engine_sample_sum[key]) / float(_trace_engine_samples))
	return averages


func _trace_load_snapshot() -> Dictionary:
	return {
		"units": int(_values.get("all_units.total", 0)),
		"aircraft": int(_values.get("all_units.aircraft", 0)),
		"naval": int(_values.get("all_units.naval", 0)),
		"ground": int(_values.get("all_units.ground", 0)),
		"mounts": int(_values.get("all_units.mount_target", 0)),
		"bullets": int(_values.get("bullet_count", 0)),
		"bullet_flashes": int(_values.get("bullet_area_flash_count", 0)),
		"missiles": int(_values.get("missile_count", 0)),
		"atm_live": int(_values.get("atmosphere.live_members", 0)),
		"atm_shells": int(_values.get("atmosphere.shells", 0)),
		"atm_flashes": int(_values.get("atmosphere.flashes", 0)),
	}


## 每帧推进窗口；满 1 秒把累加值快照
func _process(delta: float) -> void:
	_window_elapsed += delta
	_frames_in_window += 1
	if _window_elapsed >= WINDOW_S:
		mark_frame_event("perf_rollover")
		# 双缓冲交换：避免每秒 duplicate 三个 Dictionary 产生分配/拷贝尖峰。
		var previous_snap_us := _snap_us
		_snap_us = _window_us
		_window_us = previous_snap_us
		var previous_snap_calls := _snap_calls
		_snap_calls = _window_calls
		_window_calls = previous_snap_calls
		var previous_snap_counts := _snap_counts
		_snap_counts = _window_counts
		_window_counts = previous_snap_counts
		_last_window_frames = _frames_in_window
		_last_window_seconds = _window_elapsed
		_window_us.clear()
		_window_calls.clear()
		_window_counts.clear()
		_window_elapsed = 0.0
		_frames_in_window = 0


## 上一秒窗口内每帧平均 µs
func avg_us_per_frame(name: String) -> float:
	if _last_window_frames <= 0:
		return 0.0
	var total: int = int(_snap_us.get(name, 0))
	return float(total) / float(_last_window_frames)


## 上一秒窗口内每帧平均调用次数
func calls_per_frame(name: String) -> float:
	if _last_window_frames <= 0:
		return 0.0
	return float(int(_snap_calls.get(name, 0))) / float(_last_window_frames)


## 上一秒窗口内每帧平均计数
func avg_count_per_frame(name: String) -> float:
	if _last_window_frames <= 0:
		return 0.0
	return float(int(_snap_counts.get(name, 0))) / float(_last_window_frames)


## HUD 用：紧凑 4-5 行总结
func format_hud_lines() -> Array:
	var lines: Array = []
	# all_units 分类
	var au_total: int = int(_values.get("all_units.total", 0))
	var au_ac: int = int(_values.get("all_units.aircraft", 0))
	var au_nv: int = int(_values.get("all_units.naval", 0))
	var au_gr: int = int(_values.get("all_units.ground", 0))
	var au_mt: int = int(_values.get("all_units.mount_target", 0))
	lines.append("Units %d: ac=%d nav=%d gr=%d mt=%d" % [au_total, au_ac, au_nv, au_gr, au_mt])
	# AI 拥挤度
	var ct: float = float(_values.get("ai.crowd_t", 0.0))
	var nm_div: int = int(_values.get("ai.normal_div_at_base3", 3))
	var ch_div: int = int(_values.get("ai.cheap_div_at_base3", 3))
	lines.append("AI crowd t=%.2f norm÷%d cheap÷%d" % [ct, nm_div, ch_div])
	# 关键 bucket（µs/帧）+ 雷达对计数
	var radar_pairs: float = avg_count_per_frame("radar_pairs")
	lines.append("radar=%.0fµs (%.0f pairs)" % [
		avg_us_per_frame("radar_locks"), radar_pairs])
	lines.append("ai_tick=%.0fµs naval_dr=%.0fµs" % [
		avg_us_per_frame("ai_tick"), avg_us_per_frame("naval_draw")])
	lines.append("ac_dr=%.0fµs ac_phys=%.0fµs" % [
		avg_us_per_frame("aircraft_draw"), avg_us_per_frame("aircraft_phys")])
	lines.append("trail_dr=%.0fµs mt_phys=%.0fµs" % [
		avg_us_per_frame("trail_draw"), avg_us_per_frame("mount_target_phys")])
	lines.append("proj b=%d m=%d bdr=%.0fµs mph=%.0fµs" % [
		int(_values.get("bullet_count", 0)), int(_values.get("missile_count", 0)),
		avg_us_per_frame("bullet_draw"), avg_us_per_frame("missile_phys")])
	return lines


## F3 面板读取的当前引擎/RenderingServer 快照。调用方以 4 Hz 采样，禁止逐帧调用。
func runtime_engine_snapshot() -> Dictionary:
	var snapshot := _trace_engine_snapshot()
	snapshot["fps"] = Performance.get_monitor(Performance.TIME_FPS)
	snapshot["static_memory_mb"] = float(OS.get_static_memory_usage()) / 1048576.0
	snapshot["static_memory_peak_mb"] = \
		float(OS.get_static_memory_peak_usage()) / 1048576.0
	snapshot["resources"] = roundi(
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	snapshot["orphan_nodes"] = roundi(
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	snapshot["physics_2d_active"] = roundi(
		Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS))
	snapshot["physics_2d_pairs"] = roundi(
		Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS))
	snapshot["physics_2d_islands"] = roundi(
		Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT))
	return snapshot


func ranked_runtime_hotspots(limit: int = RUNTIME_HOTSPOT_LIMIT) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if _last_window_frames <= 0:
		return entries
	for bucket_name in _snap_us:
		var per_frame_us := avg_us_per_frame(String(bucket_name))
		if per_frame_us <= 0.0:
			continue
		entries.append({"name": String(bucket_name), "us": per_frame_us})
	entries.sort_custom(_sort_runtime_hotspot_desc)
	if entries.size() > limit:
		entries.resize(limit)
	return entries


## F3 用详细面板。CPU 桶可能是父子嵌套关系，只用于定位，不允许横向求和。
func format_detailed_hud_lines() -> Array[String]:
	var lines: Array[String] = []
	var frame := runtime_frame_stats()
	var engine := runtime_engine_snapshot()
	var samples := int(frame.get("samples", 0))
	lines.append("性能分析 [F3]  最近 %d/%d 渲染帧  明细采集:%s" % [
		samples, RUNTIME_FRAME_HISTORY_SIZE, "ON" if runtime_panel_enabled else "off"])
	lines.append("FPS %5.1f | 帧 %.2fms avg / %.2fms p95 / %.2fms worst | <60 %d" % [
		float(engine.get("fps", 0.0)), float(frame.get("avg_ms", 0.0)),
		float(frame.get("p95_ms", 0.0)), float(frame.get("worst_ms", 0.0)),
		int(frame.get("below_60", 0))])
	lines.append("引擎监视(不可相加)  process %.2fms  physics %.2fms | Canvas draw %d  obj %d  prim %d" % [
		float(engine.get("process_us", 0)) / 1000.0,
		float(engine.get("physics_us", 0)) / 1000.0,
		int(engine.get("canvas_draw_calls", 0)), int(engine.get("canvas_objects", 0)),
		int(engine.get("canvas_primitives", 0))])
	lines.append("2D物理  active %d  collision pairs %d  islands %d" % [
		int(engine.get("physics_2d_active", 0)), int(engine.get("physics_2d_pairs", 0)),
		int(engine.get("physics_2d_islands", 0))])

	lines.append("运算根桶  飞机 %.2f  AI %.2f  雷达锁定 %.2f  子弹 %.2f  导弹 %.2f  地面 %.2f  舰船 %.2f ms" % [
		_bucket_ms("aircraft_phys"), _bucket_ms("ai_tick"), _bucket_ms("radar_locks"),
		_bucket_ms("bullet_phys"), _bucket_ms("missile_phys"), _bucket_ms("ground_phys"),
		_bucket_ms("naval_phys")])
	lines.append("飞机物理细分  planner %.2f  kine %.2f  weapon %.2f  evade %.2f  misc %.2f ms" % [
		_bucket_ms("ac_phys.combat.planner"), _bucket_ms("ac_phys.kine"),
		_bucket_ms("ac_phys.wpn"), _bucket_ms("ac_phys.evade"),
		_bucket_prefix_ms("ac_phys.misc.")])
	lines.append("绘制CPU  飞机 %.2f [标签 %.2f 覆盖 %.2f 图标 %.2f 特效 %.2f] ms" % [
		_bucket_ms("aircraft_draw"), _bucket_ms("aircraft_draw.labels"),
		_bucket_ms("aircraft_draw.overlays"), _bucket_ms("aircraft_draw.icon"),
		_bucket_ms("aircraft_draw.effects")])
	lines.append("绘制CPU  尾迹 %.2f  导弹体 %.2f  导弹尾迹 %.2f  子弹 %.2f  舰船 %.2f  地面 %.2f ms" % [
		_bucket_ms("trail_draw"), _bucket_ms("missile_draw"),
		_bucket_ms("missile_trail_draw"), _bucket_ms("bullet_draw"),
		_bucket_ms("naval_draw"), _bucket_ms("ground_draw")])
	lines.append("HUD CPU  总更新 %.2f  玩家仪表 %.2f  网格 %.2f  雷达绘制 %.2f  威胁层 %.2f ms" % [
		_bucket_ms("hud_process"), _bucket_ms("hud_player_draw"),
		_bucket_ms("hud_grid_draw"), _bucket_ms("hud_radar_draw"),
		_bucket_ms("hud_threat_draw")])
	lines.append("系统CPU  舰载武器 %.2f  气氛 %.2f  音效 %.2f  无线电 %.2f  日志 %.2f  生成 %.2f ms" % [
		_bucket_ms("naval_weapons"), _bucket_ms("atmosphere_tick"),
		_bucket_ms("audio_sfx_play"), _bucket_ms("radio_play"),
		_bucket_ms("event_log"), _bucket_ms("spawn_enemy")])

	lines.append("单位  total %d | aircraft %d  naval %d  ground %d  mounts %d | BOSS %s | AI crowd %.2f div %d/%d" % [
		int(_values.get("all_units.total", 0)), int(_values.get("all_units.aircraft", 0)),
		int(_values.get("all_units.naval", 0)), int(_values.get("all_units.ground", 0)),
		int(_values.get("all_units.mount_target", 0)),
		"PHASE" if int(_values.get("boss.phase", 0)) > 0 else "off",
		float(_values.get("ai.crowd_t", 0.0)),
		int(_values.get("ai.normal_div_at_base3", 3)),
		int(_values.get("ai.cheap_div_at_base3", 3))])
	lines.append("弹丸/VFX  bullets %d [visual %d]  missiles %d  flashes %d | atmosphere live %d shells %d flashes %d" % [
		int(_values.get("bullet_count", 0)), int(_values.get("visual_bullet_count", 0)),
		int(_values.get("missile_count", 0)), int(_values.get("bullet_area_flash_count", 0)),
		int(_values.get("atmosphere.live_members", 0)), int(_values.get("atmosphere.shells", 0)),
		int(_values.get("atmosphere.flashes", 0))])
	lines.append("调用量/帧  radar pairs %.1f  missile labels %.1f warnings %.1f  skill %.1f  radio %.1f  sfx %.1f  log %.1f" % [
		avg_count_per_frame("radar_pairs"), avg_count_per_frame("missile_labels_drawn"),
		avg_count_per_frame("missile_warnings_drawn"), avg_count_per_frame("skill_events"),
		avg_count_per_frame("radio_requests"),
		avg_count_per_frame("audio_sfx_requests"), avg_count_per_frame("event_log_calls")])
	lines.append("内存/对象  static %.1f / peak %.1f MiB | objects %d  resources %d  nodes %d  orphan %d" % [
		float(engine.get("static_memory_mb", 0.0)),
		float(engine.get("static_memory_peak_mb", 0.0)), int(engine.get("objects", 0)),
		int(engine.get("resources", 0)), int(engine.get("nodes", 0)),
		int(engine.get("orphan_nodes", 0))])

	var hotspots := ranked_runtime_hotspots()
	var first_parts := PackedStringArray()
	var second_parts := PackedStringArray()
	for index in range(hotspots.size()):
		var entry: Dictionary = hotspots[index]
		var part := "%s %.2f" % [String(entry["name"]), float(entry["us"]) / 1000.0]
		if index < 5:
			first_parts.append(part)
		else:
			second_parts.append(part)
	lines.append("热点CPU(ms/帧, 父子桶可重叠)  %s" % (
		" | ".join(first_parts) if not first_parts.is_empty() else "等待完整1秒窗口"))
	if not second_parts.is_empty():
		lines.append("热点续  %s" % " | ".join(second_parts))
	lines.append("F9 导出完整桶与慢帧报告；面板自身计入 HUD/Canvas 数值")
	return lines


func _bucket_ms(name: String) -> float:
	return avg_us_per_frame(name) / 1000.0


func _bucket_prefix_ms(prefix: String) -> float:
	var total_us := 0.0
	for bucket_name in _snap_us:
		if String(bucket_name).begins_with(prefix):
			total_us += avg_us_per_frame(String(bucket_name))
	return total_us / 1000.0


static func _sort_runtime_hotspot_desc(a: Dictionary, b: Dictionary) -> bool:
	return float(a["us"]) > float(b["us"])


## F9 dump 用：完整快照
func format_full_dump() -> String:
	var s := "=== PERF SNAPSHOT (last %.2fs, %d frames) ===\n" % [_last_window_seconds, _last_window_frames]
	s += "all_units total=%s ac=%s nav=%s gr=%s mt=%s\n" % [
		_values.get("all_units.total", 0),
		_values.get("all_units.aircraft", 0),
		_values.get("all_units.naval", 0),
		_values.get("all_units.ground", 0),
		_values.get("all_units.mount_target", 0),
	]
	s += "AI crowd_t=%.3f normal_div_at_base3=%s cheap_div_at_base3=%s\n" % [
		float(_values.get("ai.crowd_t", 0.0)),
		_values.get("ai.normal_div_at_base3", 3),
		_values.get("ai.cheap_div_at_base3", 3),
	]
	s += "projectiles bullets=%s missiles=%s flashes=%s\n" % [
		_values.get("bullet_count", 0),
		_values.get("missile_count", 0),
		_values.get("bullet_area_flash_count", 0),
	]
	# 各 bucket 时间
	var names: Array = _snap_us.keys()
	names.sort()
	s += "Buckets (sorted):\n"
	for n in names:
		var total_us: int = int(_snap_us.get(n, 0))
		var calls: int = int(_snap_calls.get(n, 0))
		var per_f: float = (float(total_us) / float(_last_window_frames)) if _last_window_frames > 0 else 0.0
		s += "  %s: total=%dµs calls=%d per_frame=%.0fµs\n" % [n, total_us, calls, per_f]
	# 计数
	if _snap_counts.size() > 0:
		var cnames: Array = _snap_counts.keys()
		cnames.sort()
		s += "Counts (per-frame avg):\n"
		for n in cnames:
			var total: int = int(_snap_counts.get(n, 0))
			var per_f: float = (float(total) / float(_last_window_frames)) if _last_window_frames > 0 else 0.0
			s += "  %s: total=%d per_frame=%.1f\n" % [n, total, per_f]
	s += "=== END PERF SNAPSHOT ===\n"
	return s


## Bench 结果用：最慢 16 帧 + 事件相关性；不进入普通 HUD/F9 路径。
func format_frame_trace_dump() -> String:
	if not frame_trace_enabled:
		return ""
	var s := "=== FRAME SPIKE TRACE (budget %.3fms) ===\n" % (FRAME_BUDGET_S * 1000.0)
	s += "completed_frames=%d below60=%d captured=%d dropped=%d\n" % [
		maxi(_trace_frame_index - 1, 0), _trace_frames_below_60,
		_trace_spikes.size(), _trace_dropped_spikes]
	s += "detail_stride=%d\n" % _trace_detail_stride
	var frame_percentiles := _trace_frame_percentiles()
	s += "frame_ms p95=%.3f p99=%.3f max=%.3f\n" % [
		float(frame_percentiles.get("p95", 0.0)),
		float(frame_percentiles.get("p99", 0.0)),
		float(frame_percentiles.get("max", 0.0))]
	var event_names: Array = _trace_spike_event_counts.keys()
	event_names.sort()
	var event_parts := PackedStringArray()
	for event_name in event_names:
		event_parts.append("%s=%d" % [event_name, int(_trace_spike_event_counts[event_name])])
	s += "spike_event_hits: %s\n" % (", ".join(event_parts) if not event_parts.is_empty() else "none")
	s += "engine_baseline samples=%d stride=%d avg=[%s] max=[%s]\n" % [
		_trace_engine_samples, FRAME_TRACE_ENGINE_SAMPLE_STRIDE,
		_format_trace_map(_trace_engine_baseline_avg(), 10),
		_format_trace_map(_trace_engine_sample_max, 10)]
	var ranked: Array[Dictionary] = _trace_spikes.duplicate()
	ranked.sort_custom(_sort_spike_desc)
	var class_counts: Dictionary = {}
	var attributed_spikes := 0
	for spike in ranked:
		var spike_class := _trace_spike_class(spike)
		class_counts[spike_class] = int(class_counts.get(spike_class, 0)) + 1
		if spike_class in [&"physics_catchup", &"script_hotspot", &"canvas_pressure"]:
			attributed_spikes += 1
	var attributed_pct := 0.0
	if not ranked.is_empty():
		attributed_pct = float(attributed_spikes) * 100.0 / float(ranked.size())
	s += "conservative_attribution=%d/%d (%.1f%%) classes=[%s]\n" % [
		attributed_spikes, ranked.size(), attributed_pct,
		_format_trace_map(class_counts, 10)]
	for i in range(mini(ranked.size(), FRAME_TRACE_REPORT_SPIKES)):
		var spike: Dictionary = ranked[i]
		s += "  #%02d frame=%d class=%s delta=%.3fms known=%.3fms unaccounted=%.3fms physics=%d buckets=[%s] counts=[%s] events=[%s] load=[%s] engine=[%s]\n" % [
			i + 1, int(spike["frame"]), _trace_spike_class(spike),
			float(spike["delta_ms"]),
			float(spike["known_ms"]), float(spike["unaccounted_ms"]),
			int(spike["physics_ticks"]), _format_trace_map(spike["buckets_us"], 6, "us"),
			_format_trace_map(spike["counts"], 5), _format_trace_map(spike["events"], 5),
			_format_trace_map(spike["load"], 10), _format_trace_map(spike["engine"], 10)]
	var context_windows := _trace_context_windows.duplicate(true)
	if not _trace_active_context.is_empty():
		context_windows.append(_trace_active_context.duplicate(true))
	s += "context_windows=%d pre_limit=%d post_target=%d\n" % [
		context_windows.size(), FRAME_TRACE_PRE_CONTEXT_FRAMES,
		FRAME_TRACE_POST_CONTEXT_FRAMES]
	for window_index in range(context_windows.size()):
		var window: Dictionary = context_windows[window_index]
		var frames: Array = window.get("frames", [])
		s += "  window=%d start=%d end=%d pre_frames=%d triggers=[%s] complete=%s frames=%d\n" % [
			window_index + 1, int(window.get("start_frame", 0)),
			int(window.get("end_frame", frames.back().get("frame", 0) if not frames.is_empty() else 0)),
			int(window.get("pre_frames", 0)),
			_format_trace_values(window.get("trigger_frames", [])),
			str(bool(window.get("complete", false))), frames.size()]
		for context_frame in frames:
			var context: Dictionary = context_frame
			var delta_ms := float(context.get("delta_ms", 0.0))
			var marker := "!" if delta_ms > FRAME_BUDGET_S * 1000.0 else "."
			s += "    %s f=%d dt=%.3f known=%.3f phys=%d buckets=[%s] events=[%s] engine=[%s]\n" % [
				marker, int(context.get("frame", 0)), delta_ms,
				float(context.get("known_ms", 0.0)), int(context.get("physics_ticks", 0)),
				_format_trace_map(context.get("buckets_us", {}), 4, "us"),
				_format_trace_map(context.get("events", {}), 4),
				_format_trace_map(context.get("engine", {}), 6)]
	s += "=== END FRAME SPIKE TRACE ===\n"
	return s


func _trace_frame_percentiles() -> Dictionary:
	if _trace_frame_deltas_ms.is_empty():
		return {"p95": 0.0, "p99": 0.0, "max": 0.0}
	var sorted := Array(_trace_frame_deltas_ms)
	sorted.sort()
	return {
		"p95": float(sorted[clampi(ceili(sorted.size() * 0.95) - 1, 0, sorted.size() - 1)]),
		"p99": float(sorted[clampi(ceili(sorted.size() * 0.99) - 1, 0, sorted.size() - 1)]),
		"max": float(sorted.back()),
	}


## 只把有直接证据的三类计入归因率；零物理 tick 只能标记候选，不冒充已证明根因。
func _trace_spike_class(spike: Dictionary) -> StringName:
	var delta_ms := float(spike.get("delta_ms", 0.0))
	var known_ms := float(spike.get("known_ms", 0.0))
	var physics_ticks := int(spike.get("physics_ticks", 0))
	if physics_ticks >= 2:
		return &"physics_catchup"
	if delta_ms > 0.0 and known_ms / delta_ms >= 0.5:
		return &"script_hotspot"
	var engine: Dictionary = spike.get("engine", {})
	var baseline := _trace_engine_baseline_avg()
	var draw_calls := int(engine.get("canvas_draw_calls", 0))
	var baseline_draw_calls := int(baseline.get("canvas_draw_calls", 0))
	if baseline_draw_calls > 0 and draw_calls >= baseline_draw_calls + 50 \
			and draw_calls >= roundi(float(baseline_draw_calls) * 1.20):
		return &"canvas_pressure"
	if physics_ticks == 0 and known_ms <= 2.0:
		return &"render_wait_candidate"
	return &"unknown"


static func _format_trace_values(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return ",".join(parts) if not parts.is_empty() else "none"


static func _sort_spike_desc(a: Dictionary, b: Dictionary) -> bool:
	return float(a["delta_ms"]) > float(b["delta_ms"])


static func _sort_trace_entry_desc(a: Dictionary, b: Dictionary) -> bool:
	return int(a["value"]) > int(b["value"])


static func _format_trace_map(values: Dictionary, limit: int, suffix: String = "") -> String:
	if values.is_empty():
		return "none"
	var entries: Array[Dictionary] = []
	for key in values:
		entries.append({"name": String(key), "value": int(values[key])})
	entries.sort_custom(_sort_trace_entry_desc)
	var parts := PackedStringArray()
	for i in range(mini(entries.size(), limit)):
		parts.append("%s=%d%s" % [entries[i]["name"], entries[i]["value"], suffix])
	return ",".join(parts)
