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


## 累加一段代码的 µs 耗时
func tick(name: String, us: int) -> void:
	if not enabled:
		return
	_window_us[name] = int(_window_us.get(name, 0)) + us
	_window_calls[name] = int(_window_calls.get(name, 0)) + 1


## 累加每帧计数（如 radar pair evaluations / draw calls）
func count(name: String, n: int = 1) -> void:
	if not enabled:
		return
	_window_counts[name] = int(_window_counts.get(name, 0)) + n


## 写入瞬时值（不累加，覆盖）
func set_value(name: String, v: Variant) -> void:
	_values[name] = v


func get_value(name: String, default_v: Variant = null) -> Variant:
	return _values.get(name, default_v)


## 每帧推进窗口；满 1 秒把累加值快照
func _process(delta: float) -> void:
	_window_elapsed += delta
	_frames_in_window += 1
	if _window_elapsed >= WINDOW_S:
		_snap_us = _window_us.duplicate()
		_snap_calls = _window_calls.duplicate()
		_snap_counts = _window_counts.duplicate()
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
	return lines


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
