extends RefCounted
## 离线全局配对：屏幕无关的含高度保护面积×三角成本；运行时不求解。
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")


static func pair_entries(entries: Array) -> Array:
	assert(entries.size() == 16)
	var layers: Array = []
	for entry: Dictionary in entries:
		var boxes: Array = []
		for slot in [4, 5, 6]:
			var package: Resource = ResourceLoader.load(entry.mid.path if slot == 6 else entry.levels[slot].path, "", ResourceLoader.CACHE_MODE_IGNORE)
			for mesh: ArrayMesh in package.meshes:
				boxes.append({"bounds": mesh.get_aabb(), "triangles": Indexed.triangles(mesh)})
		layers.append(boxes)
	var costs: Array = []
	for a in entries.size():
		var row := PackedFloat64Array()
		row.resize(entries.size())
		for b in range(a + 1, entries.size()):
			for kind in layers[a].size():
				var left: Dictionary = layers[a][kind]
				var right: Dictionary = layers[b][kind]
				var count: int = left.triangles + right.triangles
				if count == 0:
					continue
				var box: AABB = right.bounds if left.triangles == 0 else left.bounds
				if left.triangles > 0 and right.triangles > 0:
					box = box.merge(right.bounds)
				var guard := 2.0 * ((box.position.y + box.size.y) * 1.6 + 8.0)
				row[b] += (box.size.x + guard) * (box.size.z + guard) * count
		costs.append(row)
	var pairs: Array = []
	for pair: Vector2i in solve(costs):
		pairs.append([entries[pair.x], entries[pair.y]])
	return pairs


static func solve(costs: Array) -> Array[Vector2i]:
	assert(not costs.is_empty() and costs.size() <= 16 and costs.size() % 2 == 0)
	var result := _solve_mask((1 << costs.size()) - 1, costs, {})
	return result.pairs


static func _solve_mask(mask: int, costs: Array, cache: Dictionary) -> Dictionary:
	if cache.has(mask):
		return cache[mask]
	var best := {"cost": INF, "pairs": [] as Array[Vector2i]}
	if mask == 0:
		best.cost = 0.0
	else:
		var a := 0
		while (mask & (1 << a)) == 0:
			a += 1
		var remaining := mask ^ (1 << a)
		for b in range(a + 1, costs.size()):
			if (remaining & (1 << b)) == 0:
				continue
			var child := _solve_mask(remaining ^ (1 << b), costs, cache)
			var value: float = child.cost + costs[a][b]
			if value < float(best.cost):
				var pairs: Array[Vector2i] = [Vector2i(a, b)]
				pairs.append_array(child.pairs)
				best = {"cost": value, "pairs": pairs}
	cache[mask] = best
	return best
