extends RefCounted
## 显示折线固定弧长参数；不修改预测积分、终点或飞行权威。
const POINT_COUNT := 91


static func resample(points: PackedVector2Array, healths: PackedFloat32Array,
		count: int = POINT_COUNT) -> Dictionary:
	var result := PackedVector2Array()
	var energy := PackedFloat32Array()
	if points.is_empty():
		return {"points": result, "healths": energy}
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		lengths.append(lengths[-1] + points[i - 1].distance_to(points[i]))
	var segment := 1
	for i in range(maxi(2, count)):
		var distance := lengths[-1] * float(i) / float(maxi(2, count) - 1)
		while segment < points.size() - 1 and lengths[segment] < distance:
			segment += 1
		var b := mini(segment, points.size() - 1)
		var a := maxi(0, b - 1)
		var weight := clampf((distance - lengths[a]) / maxf(lengths[b] - lengths[a], 0.0001), 0.0, 1.0)
		result.append(points[a].lerp(points[b], weight))
		var ha := healths[a] if a < healths.size() else 1.0
		var hb := healths[b] if b < healths.size() else ha
		energy.append(lerpf(ha, hb, weight))
	result[-1] = points[-1]
	return {"points": result, "healths": energy}


## 只寻找已经飞过的近端，避免跳到远期回环。显示起点始终锁定同帧机体。
static func anchored(points: PackedVector2Array, healths: PackedFloat32Array,
		origin: Vector2) -> Dictionary:
	if points.size() < 2:
		return resample(points, healths)
	var best_segment := 0
	var best_weight := 0.0
	var best_distance := INF
	for i in range(mini(16, points.size() - 1)):
		var edge := points[i + 1] - points[i]
		var weight := clampf((origin - points[i]).dot(edge) / maxf(edge.length_squared(), 0.0001), 0.0, 1.0)
		var distance := origin.distance_squared_to(points[i].lerp(points[i + 1], weight))
		if distance < best_distance:
			best_distance = distance
			best_segment = i
			best_weight = weight
	var tail := PackedVector2Array([origin])
	var ha := healths[best_segment] if best_segment < healths.size() else 1.0
	var hb := healths[best_segment + 1] if best_segment + 1 < healths.size() else ha
	var energy := PackedFloat32Array([lerpf(ha, hb, best_weight)])
	for i in range(best_segment + 1, points.size()):
		if tail[-1].distance_squared_to(points[i]) < 0.0001:
			continue
		tail.append(points[i])
		energy.append(healths[i] if i < healths.size() else 1.0)
	return resample(tail, energy)


static func tip_direction(points: PackedVector2Array) -> Vector2:
	if points.size() < 2:
		return Vector2.ZERO
	for i in range(points.size() - 2, -1, -1):
		var edge := points[-1] - points[i]
		if edge.length_squared() >= 0.25:
			return edge.normalized()
	return Vector2.ZERO
