extends RefCounted
## 每个概括包配同空间切面的原LOD5；路径去重与内存仍由同一流送器计数。
const Hierarchy := preload("res://scripts/rendering/tokyo_hierarchical_overlay.gd")
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const MAX_SCALE := 1.5552


static func decorate(entry: Dictionary, original: Dictionary, descriptors: Dictionary) -> Dictionary:
	assert(entry.parent_id == original.parent_id and entry.cell_id == original.cell_id)
	assert(entry.get("cuts", PackedFloat32Array()) == original.get("cuts", PackedFloat32Array()))
	assert(entry.get("ancestor_id", -1) == original.get("ancestor_id", -1))
	var result := entry.duplicate()
	var reference := original.duplicate()
	reference.erase("children")
	result["fallback"] = reference
	result["boxes"] = []
	result["triangles"] = []
	for kind in 3:
		var box: AABB = entry.boxes[kind]
		if int(original.triangles[kind]) > 0:
			box = box.merge(original.boxes[kind]) if int(entry.triangles[kind]) > 0 else original.boxes[kind]
		result.boxes.append(box)
		# fine独有层不能使原形备用块被整个裁掉；提交面数由真实绑定网格另计。
		result.triangles.append(maxi(int(entry.triangles[kind]), int(int(original.triangles[kind]) > 0)))
	var one: Array[Dictionary] = [result]
	result.bytes = Hierarchy.union_bytes(paths(one), PackedStringArray(), descriptors)
	if entry.has("children"):
		assert(entry.children.size() == original.children.size())
		result.children = []
		for n in entry.children.size():
			result.children.append(decorate(entry.children[n], original.children[n], descriptors))
	return result


static func original_cut(entries: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		assert(entry.has("fallback"))
		result.append(entry.fallback)
	return result


static func paths(entries: Array[Dictionary]) -> PackedStringArray:
	var result := Hierarchy.paths_for(entries)
	for entry: Dictionary in entries:
		if not entry.has("fallback"):
			continue
		var one: Array[Dictionary] = [entry.fallback]
		for path: String in Hierarchy.paths_for(one):
			if path not in result:
				result.append(path)
	return result


static func fallback_visible(entry: Dictionary, view: Rect2, canvas: Transform2D, logical: Vector2,
		roof: Vector2, shadow: Vector2) -> bool:
	return entry.has("fallback") and int(Select.visible(entry.fallback, view, canvas, logical, roof, shadow).faces) > 0
