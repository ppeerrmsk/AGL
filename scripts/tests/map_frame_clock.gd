extends RefCounted
## 地图bench帧首墙钟；不连接渲染信号、不改VSync，最多保留120000个间隔。
const Clock := preload("res://scripts/tests/tokyo_render_clock.gd")
var previous := 0
var samples := PackedInt64Array()
var below60 := 0
var total := 0
var peak := 0
var count := 0
var slow: Array[Dictionary] = []
var trace := OS.get_environment("AGL_MAP_WALL_TRACE") == "1"


func observe(enabled: bool, now: int = -1) -> void:
	if not enabled:
		previous = 0
		return
	if now < 0:
		now = Time.get_ticks_usec()
	if previous > 0:
		var interval := now - previous
		count += 1
		total += interval
		peak = maxi(peak, interval)
		below60 += int(not Clock.frame_within_budget(interval))
		if trace and not Clock.frame_within_budget(interval):
			Clock.retain_slowest(slow, {"wall_us": interval,
				"frame": PerfBuckets._trace_frame_index,
				"cpu_buckets_us": PerfBuckets._trace_frame_us.duplicate(),
				"counts": PerfBuckets._trace_frame_counts.duplicate(),
				"events": PerfBuckets._trace_frame_events.duplicate()})
		if samples.size() < 120000:
			samples.append(interval)
	previous = now


func report() -> Dictionary:
	var result := Clock.percentiles_usec(samples)
	result.merge({"samples": count, "complete": count == samples.size(), "below60": below60,
		"avg_fps": count * 1000000.0 / maxf(1.0, total), "max_ms": peak / 1000.0,
		"passed": count > 0 and below60 == 0, "slow_records": slow, "trace": trace}, true)
	return result
