extends RefCounted
## 离线凸片差集：保留已有同高屋面，仅输出候选屋面尚未覆盖的部分。


static func subtract_all(polygon: PackedVector2Array, cutters: Array) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [polygon]
	for cutter: PackedVector2Array in cutters:
		var next: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in pieces:
			next.append_array(subtract(piece, cutter))
		pieces = next
		if pieces.is_empty():
			break
	return pieces


static func subtract(polygon: PackedVector2Array, cutter: PackedVector2Array) -> Array[PackedVector2Array]:
	assert(cutter.size() == 3)
	var direction := (cutter[1] - cutter[0]).cross(cutter[2] - cutter[0])
	if direction == 0.0:
		return [polygon]
	var box := Rect2(polygon[0], Vector2.ZERO)
	for p: Vector2 in polygon:
		box = box.expand(p)
	var cut_box := Rect2(cutter[0], Vector2.ZERO)
	for p: Vector2 in cutter:
		cut_box = cut_box.expand(p)
	if not box.intersects(cut_box):
		return [polygon]
	var remaining := polygon
	var result: Array[PackedVector2Array] = []
	for edge in 3:
		if remaining.size() < 3:
			break
		var a := cutter[edge]
		var b := cutter[(edge + 1) % 3]
		var outside := half_plane(remaining, a, b, direction > 0.0, false)
		if outside.size() >= 3 and area(outside) > 0.0:
			result.append(outside)
		remaining = half_plane(remaining, a, b, direction > 0.0, true)
	return result


static func half_plane(polygon: PackedVector2Array, a: Vector2, b: Vector2, positive: bool, inside: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	var previous := polygon[-1]
	var previous_side := (b - a).cross(previous - a) * (1.0 if positive else -1.0)
	var previous_keep := previous_side >= 0.0 if inside else previous_side <= 0.0
	for current: Vector2 in polygon:
		var current_side := (b - a).cross(current - a) * (1.0 if positive else -1.0)
		var current_keep := current_side >= 0.0 if inside else current_side <= 0.0
		if previous_keep != current_keep:
			var point := previous.lerp(current, previous_side / (previous_side - current_side))
			if result.is_empty() or result[-1] != point:
				result.append(point)
		if current_keep and (result.is_empty() or result[-1] != current):
			result.append(current)
		previous = current
		previous_side = current_side
		previous_keep = current_keep
	if result.size() > 1 and result[-1] == result[0]:
		result.resize(result.size() - 1)
	return result


static func area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for n in range(1, polygon.size() - 1):
		total += (polygon[n] - polygon[0]).cross(polygon[n + 1] - polygon[0])
	return absf(total) * 0.5
