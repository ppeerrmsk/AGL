extends RefCounted
## 只按完整原生包络细分，不裁楼；每次替换保留全部可见子块，最多16块。
const Overlay := preload("res://scripts/rendering/tokyo_cells_overlay.gd")


static func visible(entry: Dictionary, view: Rect2, canvas: Transform2D, logical: Vector2,
		roof: Vector2, shadow: Vector2) -> Dictionary:
	var result := entry.duplicate()
	var faces := 0
	var mask: Array[bool] = []
	for kind in 3:
		var seen := false
		# 空层保留 false 掩码，但不再计算不会用于相交判断的投影包络。
		if int(entry.triangles[kind]) > 0:
			var bounds := Overlay.projected_layer_bounds(entry.boxes[kind], roof, shadow)
			seen = Overlay.intersects_view(bounds, view, canvas, logical)
		mask.append(seen)
		faces += int(entry.triangles[kind]) if seen else 0
	result["mask"] = mask
	result["faces"] = faces
	return result


static func choose(parents: Array[Dictionary], view: Rect2, canvas: Transform2D, logical: Vector2,
		roof: Vector2, shadow: Vector2, cap: int = 16) -> Dictionary:
	assert(cap > 0 and cap <= 16)
	var selected: Array[Dictionary] = []
	for parent: Dictionary in parents:
		var entry := visible(parent, view, canvas, logical, roof, shadow)
		if entry.faces > 0:
			selected.append(entry)
	assert(selected.size() <= cap, "root working set must fit without dropping geometry")
	while true:
		var best := -1
		var best_score := 0.0
		var best_children: Array[Dictionary] = []
		for n in selected.size():
			var entry: Dictionary = selected[n]
			if not entry.has("children") or entry.children.is_empty():
				continue
			var children: Array[Dictionary] = []
			var faces := 0
			for child: Dictionary in entry.children:
				var candidate := visible(child, view, canvas, logical, roof, shadow)
				if candidate.faces > 0:
					children.append(candidate)
					faces += int(candidate.faces)
			var growth := children.size() - 1
			if selected.size() + growth > cap:
				continue
			var score := float(int(entry.faces) - faces) / maxi(1, growth)
			if score > best_score:
				best = n
				best_score = score
				best_children = children
		if best < 0:
			break
		selected.remove_at(best)
		selected.append_array(best_children)
	var total_faces := 0
	var total_bytes := 0
	for entry: Dictionary in selected:
		total_faces += int(entry.faces)
		total_bytes += int(entry.bytes)
	return {"entries": selected, "triangles": total_faces, "bytes": total_bytes, "active": selected.size(),
		"within_budget": total_bytes <= 96 * 1024 * 1024 and total_faces <= 240000}
