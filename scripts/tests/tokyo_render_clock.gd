extends RefCounted
## 无引擎对象/信号依赖的单调时钟规则；FPS硬门无需加载后端诊断器。


static func partition(begin: int, pre: int, post: int, next: int) -> PackedInt64Array:
	if begin <= 0 or pre < begin or post < pre or next < post:
		return PackedInt64Array()
	return PackedInt64Array([pre - begin, post - pre, next - post, next - begin])


static func frame_within_budget(usec: int) -> bool:
	return usec > 0 and usec <= 1000000.0 / 60.0


static func diagnostic_cap(requested: String, refresh_hz: float) -> int:
	# 仅显式呈现对照；未知刷新率、低于硬门或并未留余量均拒绝。
	if requested.is_empty(): return 0
	if not requested.is_valid_int() or not is_finite(refresh_hz): return -1
	var limit := requested.to_int()
	return limit if limit > 60 and limit <= 1000 and float(limit) < refresh_hz else -1


static func percentiles_usec(samples: PackedInt64Array) -> Dictionary:
	if samples.is_empty():
		return {}
	var sorted := samples.duplicate()
	sorted.sort()
	if sorted[0] <= 0:
		return {}
	var result := {"samples": sorted.size(), "method": "nearest_rank", "max_ms": sorted[-1] / 1000.0}
	for percentile in [50, 95, 99]:
		var index := maxi(0, ceili(sorted.size() * percentile / 100.0) - 1)
		result["p%d_ms" % percentile] = sorted[index] / 1000.0
	return result


static func retain_slowest(records: Array[Dictionary], sample: Dictionary, capacity: int = 32) -> bool:
	# 固定上限，不按时间先后截断；后来的真正长帧仍须保留完整阶段。
	if capacity <= 0 or int(sample.get("wall_us", 0)) <= 0 or records.size() > capacity:
		return false
	if records.size() < capacity:
		records.append(sample)
		return true
	var smallest := 0
	for index in range(1, records.size()):
		if int(records[index].wall_us) < int(records[smallest].wall_us):
			smallest = index
	if int(sample.wall_us) <= int(records[smallest].wall_us):
		return false
	records[smallest] = sample
	return true
