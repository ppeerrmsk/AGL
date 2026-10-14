extends RefCounted
## 显式R139候选：目标几何不变，仅复用统一LOD2近景备用，原流送器仍拥有资源。
const SOURCE_SHA := "3f3842acb66ddb133cc1738dbaf775fb09f4ddbb7d2df13f8f7b0677f2aaca92"
const NEAR_SOURCE_SHA := "f4139942c2708b515de82aa32f48c1de1f7cac6fe7b2eab37d9eee9047e2bc85"
const Reuse := preload("res://scripts/experiments/tokyo_cut_reuse.gd")
const Pair := preload("res://scripts/experiments/tokyo_cluster_cut.gd")
const Hierarchy := preload("res://scripts/rendering/tokyo_hierarchical_overlay.gd")


static func family(entries: Array[Dictionary], descriptors: Dictionary, fallback: bool = false) -> String:
	var result := ""
	if entries.is_empty():
		return result
	for entry: Dictionary in entries:
		var selected: Dictionary = entry.get("fallback",{}) if fallback else entry
		var identity: Dictionary = descriptors.get(selected.get("path",""),{}).get("canonical_identity",{})
		var name_value := str(identity.get("configuration",""))
		if name_value.is_empty() or (not result.is_empty() and result!=name_value):
			return ""
		result=name_value
	return result


static func choose(planned: Array[Dictionary], current: Array[Dictionary], parents: Array[Dictionary],
		descriptors: Dictionary, pinned: PackedStringArray, context: Dictionary, budget: int) -> Array[Dictionary]:
	if budget<=0 or budget>96*1024*1024 or parents.is_empty() or family(planned,descriptors)!="lod1_full" \
			or family(current,descriptors) not in ["lod1_full","lod2_full"] or family(current,descriptors,true)!="lod2_guarded":
		return []
	var original_bytes := Hierarchy.union_bytes(Pair.paths(planned),pinned,descriptors)
	if original_bytes<=budget:
		return []
	var candidate := Reuse.corresponding_cut(planned,parents)
	if candidate.size()!=planned.size() or family(candidate,descriptors,true)!="lod2_guarded" or not Reuse.covers(candidate,parents,context):
		return []
	for index in candidate.size():
		var entry: Dictionary = candidate[index]
		if entry.path!=planned[index].path:
			return []
		var identity: Dictionary = descriptors[entry.path].canonical_identity
		var backup: Dictionary = descriptors[entry.fallback.path].canonical_identity
		for key: String in ["collision","owners","game_sources","parent","cell","ancestor"]:
			if not identity.has(key) or typeof(identity[key])!=typeof(backup.get(key)) or identity[key]!=backup.get(key):
				return []
	var combined := Hierarchy.union_bytes(Pair.paths(candidate),pinned,descriptors)
	return candidate if combined<=budget and combined<original_bytes else []


static func near_choice(planned: Array[Dictionary], parents: Array[Dictionary], descriptors: Dictionary,
		context: Dictionary, budget: int, native: Dictionary = {}) -> Array[Dictionary]:
	# 使用原配对中的完整精细备用；不另求一次树，不复制几何或修改LOD4 mid。
	if budget<=0 or budget>96*1024*1024 or family(planned,descriptors)!="lod4_full" \
			or family(planned,descriptors,true)!="lod5_full":
		return []
	var candidate := Pair.original_cut(planned)
	if not Reuse.covers(candidate,parents,context):
		return []
	var old_faces := 0
	var new_faces := 0
	for n in candidate.size():
		var old: Dictionary = descriptors[planned[n].path]
		var fine: Dictionary = descriptors[candidate[n].path]
		for key: String in ["collision","owners","game_sources","parent","cell","ancestor"]:
			var identity: Dictionary = old.canonical_identity
			var other: Dictionary = fine.canonical_identity
			if not identity.has(key) or typeof(identity[key])!=typeof(other.get(key)) or identity[key]!=other.get(key):
				return []
		if not native.has(planned[n].key) or not native.has(candidate[n].key):
			return []
		old_faces+=int(Reuse.Select.visible(native[planned[n].key],context.view,context.canvas,context.logical,context.roof,context.shadow).faces)
		new_faces+=int(Reuse.Select.visible(native[candidate[n].key],context.view,context.canvas,context.logical,context.roof,context.shadow).faces)
	var original_bytes := Hierarchy.union_bytes(Pair.paths(planned),PackedStringArray(),descriptors)
	var selected_bytes := Hierarchy.union_bytes(Pair.paths(candidate),PackedStringArray(),descriptors)
	return candidate if new_faces>0 and new_faces<old_faces and selected_bytes<=budget and selected_bytes<=original_bytes else []


static func native_index(entries: Array) -> Dictionary:
	# 几何包络在配置树，descriptor只负责身份/物理驻留；不能混用两个权威。
	var result := {}
	for entry: Dictionary in entries:
		result[entry.key]=entry
		result.merge(native_index(entry.get("children",[])))
	return result
