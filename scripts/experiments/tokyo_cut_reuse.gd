extends RefCounted
## 保留已加载/在途切面前，证明无重叠、无缺块，且当前实际提交不增加。
const Select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
const Hierarchy := preload("res://scripts/rendering/tokyo_hierarchical_overlay.gd")
const Pair := preload("res://scripts/experiments/tokyo_cluster_cut.gd")


static func incremental_parents(parents: Array[Dictionary], current: PackedStringArray, descriptors: Dictionary) -> Array[Dictionary]:
	var base := Hierarchy.union_bytes(current,PackedStringArray(),descriptors)
	var result: Array[Dictionary] = []
	if base>96*1024*1024:
		return result
	for parent: Dictionary in parents:
		result.append(_incremental_entry(parent,current,descriptors,base))
	return result


static func _incremental_entry(entry: Dictionary, current: PackedStringArray, descriptors: Dictionary, base: int) -> Dictionary:
	var result := entry.duplicate()
	var total := Hierarchy.union_bytes(Pair.paths([entry]),current,descriptors)
	# 未知/冲突组件的保守失败值不能通过减去base伪装成合法小增量。
	result.bytes = total-base if total<=96*1024*1024 and total>=base else 96*1024*1024+1
	if entry.has("children"):
		result.children = []
		for child: Dictionary in entry.children:
			result.children.append(_incremental_entry(child,current,descriptors,base))
	return result


static func corresponding_cut(entries: Array[Dictionary], parents: Array[Dictionary]) -> Array[Dictionary]:
	# 只翻译同空间分割身份；可见覆盖/联合驻留仍由消费者独立验证。
	var result: Array[Dictionary] = []
	var keys: Dictionary = {}
	for entry: Dictionary in entries:
		if not entry.has("parent_id") or not entry.has("cell_id"):
			return []
		var found := _corresponding(entry,parents)
		if found.is_empty() or keys.has(found.key):
			return []
		keys[found.key] = true
		result.append(found)
	return result


static func _corresponding(source: Dictionary, candidates: Array) -> Dictionary:
	for candidate: Dictionary in candidates:
		if candidate.parent_id == source.parent_id and candidate.cell_id == source.cell_id \
				and candidate.get("ancestor_id",-1) == source.get("ancestor_id",-1):
			return candidate
		var child := _corresponding(source,candidate.get("children",[]))
		if not child.is_empty():
			return child
	return {}


static func covers(entries: Array[Dictionary], parents: Array[Dictionary], context: Dictionary) -> bool:
	if entries.is_empty() or entries.size() > 16:
		return false
	var keys: Dictionary = {}
	for entry: Dictionary in entries:
		if not entry.has("key") or keys.has(entry.key):
			return false
		keys[entry.key] = true
	var remaining := keys.duplicate()
	for parent: Dictionary in parents:
		if not _validate(parent, keys, remaining, false):
			return false
	if not remaining.is_empty():
		return false
	for parent: Dictionary in parents:
		if not _covered(parent, keys, context):
			return false
	return true


static func _validate(entry: Dictionary, keys: Dictionary, remaining: Dictionary, ancestor_selected: bool) -> bool:
	var selected := keys.has(entry.key)
	if selected and ancestor_selected:
		return false
	if selected:
		remaining.erase(entry.key)
	for child: Dictionary in entry.get("children", []):
		if not _validate(child, keys, remaining, ancestor_selected or selected):
			return false
	return true


static func _covered(entry: Dictionary, keys: Dictionary, context: Dictionary) -> bool:
	if keys.has(entry.key):
		return true
	if int(Select.visible(entry, context.view, context.canvas, context.logical, context.roof, context.shadow).faces) == 0:
		return true
	if not entry.has("children"):
		return false
	for child: Dictionary in entry.children:
		if not _covered(child, keys, context):
			return false
	return true


static func faces(entries: Array[Dictionary], context: Dictionary, native: Dictionary) -> int:
	var count := 0
	for entry: Dictionary in entries:
		if not native.has(entry.key):
			return 2147483647
		count += int(Select.visible(native[entry.key], context.view, context.canvas,
			context.logical, context.roof, context.shadow).faces)
	return count
