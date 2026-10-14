extends RefCounted
## 只抑制完全重叠且已有明确总高的估高外壳；源记录与地理/高度身份不变。


static func suppressed(records: Array) -> Dictionary:
	var groups := {}
	for raw: Dictionary in records:
		var key := _eligible_key(raw)
		if key.is_empty():
			continue
		if not groups.has(key):
			groups[key] = []
		groups[key].append(raw)
	var result := {}
	for group: Array in groups.values():
		var known: Array = group.filter(func(raw: Dictionary) -> bool: return raw.get("height_source", "") == "height")
		if known.size() != 1:
			continue
		for raw: Dictionary in group:
			if raw.get("height_source", "") == "fallback" and float(raw.height_m) <= float(known[0].height_m):
				result[String(raw.id)] = String(known[0].id)
	return result


static func _eligible_key(raw: Dictionary) -> String:
	if String(raw.get("id", "")).is_empty() or raw.get("is_part", false) or raw.get("defer_render", false) or not raw.get("render_outline", true):
		return ""
	if not (raw.get("parents", []) as Array).is_empty() or not (raw.get("parts", []) as Array).is_empty():
		return ""
	var height := float(raw.get("height_m", 0))
	if not is_finite(height) or height <= 0 or float(raw.get("min_height_m", 0)) != 0:
		return ""
	if raw.get("roof_shape", "flat") != "flat" or raw.get("source_tags", {}).get("roof:shape", "flat") != "flat":
		return ""
	var rings: Array = raw.get("rings", [])
	if rings.size() != 1 or not (rings[0].get("holes", []) as Array).is_empty():
		return ""
	var key := _ring_key(rings[0].get("outer", []))
	return key if key == _ring_key(raw.get("points", [])) else ""


static func _ring_key(raw: Array) -> String:
	if raw.size() < 3:
		return ""
	var points := PackedVector2Array()
	for point: Array in raw:
		if point.size() != 2 or not is_finite(float(point[0])) or not is_finite(float(point[1])):
			return ""
		points.append(Vector2(point[0], point[1]))
	if Geometry2D.triangulate_polygon(points).is_empty():
		return ""
	# 用源double值生成键，不能经Vector2精度收窄后把近似轮廓误合并。
	var best := ""
	var minimum: Array = raw[0]
	for point: Array in raw:
		if float(point[0]) < float(minimum[0]) or (float(point[0]) == float(minimum[0]) and float(point[1]) < float(minimum[1])):
			minimum = point
	for direction: int in [1, -1]:
		for start in raw.size():
			if raw[start] != minimum:
				continue
			var sequence: Array = []
			for step in raw.size():
				var point: Array = raw[posmod(start + step * direction, raw.size())]
				sequence.append([float(point[0]), float(point[1])])
			var candidate := JSON.stringify(sequence, "", false, true)
			if best.is_empty() or candidate < best:
				best = candidate
	return best
