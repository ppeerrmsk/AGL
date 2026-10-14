extends RefCounted
## ORION 无状态火控规则；输入只含纯值，不把跨帧对象传进排序/几何函数。

const UNLOCK_KILLS := 10
const FIRST_WAVE := 16
const ARRIVAL_DELAY := 8.0
const MIN_SALVO := 10
const MAX_SALVO := 16
const LOCK_BASE := 2.0
const LOCK_REPEAT := 0.45
const LAUNCH_INTERVAL := 0.12
const SAME_TARGET_INTERVAL := 0.75
const SALVO_COOLDOWN := 12.0
const RANGE_PX := 4400.0
const BEAM_LENGTH := 1400.0
const BEAM_RADIUS := 6.0
const BEAM_WARNING := 0.8
const BEAM_DURATION := 6.0
const BEAM_COOLDOWN := 5.0
const BEAM_DAMAGE := 10.0
const REENTRY_GAP := 0.20


static func eligible(prior_cre_kills: int) -> bool:
	return prior_cre_kills >= UNLOCK_KILLS


static func should_arrive(enabled: bool, started: bool, wave: int,
		elapsed: float, live_aces: int) -> bool:
	return enabled and not started and wave >= FIRST_WAVE \
		and (elapsed >= ARRIVAL_DELAY or live_aces == 0)


## 返回目标 instance_id 的有界计划。玩家至多占两个首轮槽，余槽优先 ACE。
static func allocate_salvo(candidates: Array[Dictionary]) -> Array[int]:
	var groups: Array = [[], [], []]
	var seen: Dictionary = {}
	for row in candidates:
		var id := int(row.get("id", 0))
		if id <= 0 or seen.has(id):
			continue
		seen[id] = true
		groups[clampi(int(row.get("priority", 1)), 0, 2)].append(row)
	for group in groups:
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var da := float(a.get("distance", 0.0))
			var db := float(b.get("distance", 0.0))
			return da < db if not is_equal_approx(da, db) else int(a.id) < int(b.id))
	var selected: Array[int] = []
	var reserved := mini(2, groups[2].size()) if not groups[0].is_empty() else 0
	for group_index in range(groups.size()):
		var group: Array = groups[group_index]
		var cap := MAX_SALVO - reserved if group_index < 2 else MAX_SALVO
		for row in group:
			var id := int(row.id)
			if selected.size() < cap and not selected.has(id):
				selected.append(id)
	if selected.is_empty():
		return selected
	var repeat_pool: Array[int] = []
	for row in groups[0]:
		if selected.has(int(row.id)):
			repeat_pool.append(int(row.id))
	if repeat_pool.is_empty():
		repeat_pool.assign(selected)
	var repeat_index := 0
	while selected.size() < MIN_SALVO:
		selected.append(repeat_pool[repeat_index % repeat_pool.size()])
		repeat_index += 1
	return selected


static func lock_duration(plan: Array[int]) -> float:
	var counts: Dictionary = {}
	var largest := 1
	for id in plan:
		counts[id] = int(counts.get(id, 0)) + 1
		largest = maxi(largest, int(counts[id]))
	return LOCK_BASE + LOCK_REPEAT * float(largest - 1)


## 用就绪时间排列，允许不同目标交错；同一目标永不压缩至全局间隔。
static func launch_schedule(plan: Array[int]) -> Array[Dictionary]:
	var pending := plan.duplicate()
	var next_by_target: Dictionary = {}
	var now := 0.0
	var result: Array[Dictionary] = []
	while not pending.is_empty():
		var chosen := 0
		var earliest := INF
		for i in range(pending.size()):
			var ready := maxf(now, float(next_by_target.get(pending[i], 0.0)))
			if ready < earliest:
				earliest = ready
				chosen = i
		var id: int = pending[chosen]
		pending.remove_at(chosen)
		result.append({"id": id, "time": earliest})
		next_by_target[id] = earliest + SAME_TARGET_INTERVAL
		now = earliest + LAUNCH_INTERVAL
	return result


static func point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


## 同时考虑弹体位移和光束扫动；端点靠近以及边交叉均建立实际接触。
static func swept_beam_hit(previous: Vector2, current: Vector2,
		a0: Vector2, b0: Vector2, a1: Vector2, b1: Vector2, radius: float) -> bool:
	if Geometry2D.segment_intersects_segment(previous, current, a0, b0) != null \
		or Geometry2D.segment_intersects_segment(previous, current, a1, b1) != null:
		return true
	var hull := Geometry2D.convex_hull(PackedVector2Array([a0, b0, a1, b1]))
	if hull.size() >= 3:
		if Geometry2D.is_point_in_polygon(previous, hull) \
			or Geometry2D.is_point_in_polygon(current, hull):
			return true
	for edge in [[a0, b0], [a1, b1], [a0, a1], [b0, b1]]:
		if Geometry2D.segment_intersects_segment(previous, current, edge[0], edge[1]) != null:
			return true
		if point_segment_distance(previous, edge[0], edge[1]) <= radius \
			or point_segment_distance(current, edge[0], edge[1]) <= radius \
			or point_segment_distance(edge[0], previous, current) <= radius \
			or point_segment_distance(edge[1], previous, current) <= radius:
			return true
	return false
