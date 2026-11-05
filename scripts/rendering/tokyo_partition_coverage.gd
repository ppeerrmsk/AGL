extends RefCounted
## 无损正式建筑分区的显示凭据接合；只消费离线逐面认证，不用父页标签推断完整性。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")


static func read(binding: Variant) -> Dictionary:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return {}
	var file := FileAccess.open(binding.path,FileAccess.READ)
	if file==null: return {}
	var value: Variant=file.get_var(false);file.close()
	return value if value is Dictionary else {}


static func token_set(values: PackedStringArray) -> Dictionary:
	var result: Dictionary={}
	for value: String in values: result[value]=true
	return result


static func without(values: PackedStringArray, removed: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for value: String in values:
		if not removed.has(value): result.append(value)
	return result


static func tree_rows(tree: Dictionary, rows: Dictionary, pages: Dictionary) -> Dictionary:
	var path: String=tree.path
	var row: Variant=rows.get(path)
	if not row is Dictionary or not pages.has(path) or row.get("identity")!=pages[path].canonical_identity \
		or not row.get("leaves") is PackedStringArray or not row.get("tokens") is Array or row.tokens.size()!=2: return {}
	for kind in 2:
		if not row.tokens[kind] is PackedStringArray: return {}
	var leaves := PackedStringArray()
	var tokens: Array=[PackedStringArray(),PackedStringArray()]
	var count := 1
	if tree.children.is_empty():
		leaves.append(path)
		for kind in 2:
			if row.tokens[kind].size()>1: return {}
			if not row.tokens[kind].is_empty() and row.tokens[kind][0]!=path+":"+str(kind): return {}
			tokens[kind]=row.tokens[kind]
	else:
		for child: Dictionary in tree.children:
			var checked := tree_rows(child,rows,pages)
			if checked.is_empty(): return {}
			count+=int(checked.count);leaves.append_array(checked.leaves)
			for kind in 2: tokens[kind].append_array(checked.tokens[kind])
	if row.leaves!=leaves or row.tokens!=tokens: return {}
	return {"leaves":leaves,"tokens":tokens,"count":count}


static func apply(base: Dictionary, delta: Dictionary, original: Dictionary, normalized: Dictionary, partition_sha: String, share_unchanged: bool = false) -> Dictionary:
	if delta.get("schema")!=1 or delta.get("partition_sha256")!=partition_sha \
		or delta.get("target")!=original.path or delta.get("tree_sha256")!=var_to_bytes(original).hex_encode().sha256_text() \
		or delta.get("all_channels_conserved")!=true or not delta.get("pages") is Dictionary or not delta.get("sources") is Dictionary: return {}
	for field: String in ["configuration","catalog_sha256","collision_sha256","owners_sha256","plan_sha256"]:
		if delta.get(field)!=base.get(field): return {}
	var expected: Variant=delta.get("expected_faces")
	if not expected is PackedInt32Array or expected.size()!=2 or expected[0]<0 or expected[1]<0 \
		or delta.get("found_faces")!=expected: return {}
	var tree: Dictionary=normalized.tree
	if Array(tree.triangles)!=Array(original.triangles) or tree.boxes!=original.boxes: return {}
	var checked := tree_rows(tree,delta.pages,normalized.pages)
	if checked.is_empty() or int(checked.count)!=delta.pages.size(): return {}
	var old: Variant=base.pages.get(original.path)
	if not old is Dictionary or not old.get("leaves") is PackedStringArray or not old.get("tokens") is Array or old.tokens.size()!=2: return {}
	var old_tokens: Dictionary={}
	var new_tokens: Dictionary={}
	for kind in 2:
		if not old.tokens[kind] is PackedStringArray: return {}
		old_tokens.merge(token_set(old.tokens[kind]))
		new_tokens.merge(token_set(checked.tokens[kind]))
	# 保守来源标签允许出现在无正式面邻页，但不能在迁移时增加或抹掉依赖。
	if expected[0]+expected[1]==0:
		if not old_tokens.is_empty() or not new_tokens.is_empty() or not delta.sources.is_empty(): return {}
	elif old_tokens.is_empty() or new_tokens.is_empty(): return {}
	var affected: Dictionary={}
	for source: Variant in base.sources:
		if not source is int or not base.sources[source] is PackedStringArray: return {}
		for token: String in base.sources[source]:
			if old_tokens.has(token): affected[source]=true;break
	if affected.size()!=delta.sources.size(): return {}
	var claimed: Dictionary={}
	for source: Variant in delta.sources:
		var required: Variant=delta.sources[source]
		if not affected.has(source) or not required is PackedStringArray or required.is_empty() \
			or token_set(required).size()!=required.size(): return {}
		for token: String in required:
			if not new_tokens.has(token): return {}
			claimed[token]=true
	if claimed.size()!=new_tokens.size(): return {}
	# Loading 独占准备期间，未改动的凭据只读共享；后续接合仍先复制要修改的行。
	# 不再为每个局部补丁重复深拷贝全图。普通调用保持完全独立的输出合同。
	var result: Dictionary=base.duplicate(not share_unchanged)
	if share_unchanged:
		result.pages=base.pages.duplicate()
		result.sources=base.sources.duplicate()
	var old_leaves := token_set(old.leaves)
	var removed_paths: Dictionary={}
	var stack: Array=[original]
	while not stack.is_empty():
		var entry: Dictionary=stack.pop_back()
		removed_paths[entry.path]=true
		stack.append_array(entry.children)
	for path: String in removed_paths: result.pages.erase(path)
	for path: String in result.pages:
		var row: Dictionary=result.pages[path]
		var intersection := 0
		for leaf: String in row.leaves: intersection+=int(old_leaves.has(leaf))
		if intersection==0: continue
		# 替换根以上只能是完整祖先；跨越部分旧叶的错误凭据不能蒙混为父页。
		if intersection!=old_leaves.size(): return {}
		if share_unchanged:
			row=row.duplicate(true)
			result.pages[path]=row
		row.leaves=without(row.leaves,old_leaves)
		row.leaves.append_array(checked.leaves)
		for kind in 2:
			row.tokens[kind]=without(row.tokens[kind],token_set(old.tokens[kind]))
			row.tokens[kind].append_array(checked.tokens[kind])
	for path: String in delta.pages:
		if result.pages.has(path): return {}
		result.pages[path]=delta.pages[path].duplicate(true)
	for source: int in affected:
		result.sources[source]=without(result.sources[source],old_tokens)
		result.sources[source].append_array(delta.sources[source])
	return result
