extends RefCounted
## 已认证目录交织成一棵交接选择树；只换资源身份，不重烘焙、不放宽逐页资格。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")

static func build(catalogs: Array[Dictionary], indices: Array[int]) -> Dictionary:
	if indices.size()<2: return {}
	var fine: Dictionary=catalogs[indices[0]]
	var rows := {}
	var limits: Array[float]=[]
	var variants := indices.size()
	for key: String in fine.rows:
		var original: Dictionary=fine.rows[key]
		var depth := int(original.depth)
		var index := int(key.get_slice(":",1))
		for variant: int in variants:
			var catalog: Dictionary=catalogs[indices[variant]]
			if catalog.bounds!=fine.bounds: return {}
			if not catalog.rows.has(key): return {}
			var source: Dictionary=catalog.rows[key]
			if source.bounds!=original.bounds or source.children!=original.children: return {}
			var row := source.duplicate()
			row.depth=depth*variants+variant
			row.parent=int(original.parent) if variant==0 else index
			row.children=original.children if variant==variants-1 else [index]
			row.max_scale=minf(float(source.get("max_scale",INF)),float(catalog.max_scale))
			row["geometry_bounds"]=source.get("geometry_bounds",[])
			rows["%d:%d"%[row.depth,index]]=row
			if not limits.has(float(row.max_scale)): limits.append(float(row.max_scale))
	var roots: Array[Dictionary]=[]
	for root: Dictionary in fine.roots: roots.append(Contract.tree(rows,0,int(String(root.key).get_slice(":",1))))
	# Loading 已建好的包络按页索引；逐页交接不能重建整棵后代树再丢掉 children。
	var leaves := {}
	var pending := roots.duplicate()
	while not pending.is_empty():
		var entry: Dictionary=pending.pop_back()
		pending.append_array(entry.get("children",[]))
		var leaf := entry.duplicate()
		leaf.erase("children")
		leaves[entry.key]=leaf
	# 同一显示档的空间细分树，不沿交织树再枚举另外六个档的组合。
	var spatial_trees := {}
	var ordered := rows.keys()
	ordered.sort_custom(func(a: String,b: String) -> bool: return int(rows[a].depth)>int(rows[b].depth))
	for key: String in ordered:
		var depth := int(rows[key].depth)
		var variant := depth%variants
		var original_key := "%d:%s"%[depth/variants,key.get_slice(":",1)]
		var branch: Dictionary=leaves[key].duplicate()
		var children: Array[Dictionary]=[]
		for child: int in catalogs[indices[variant]].rows[original_key].children:
			children.append(spatial_trees["%d:%d"%[(depth/variants+1)*variants+variant,child]])
		if not children.is_empty(): branch["children"]=children
		spatial_trees[key]=branch
	limits.sort()
	var intervals: Array[Dictionary]=[]
	var lower := 0.0
	for upper: float in limits:
		var qualified: Array[Dictionary]=[]
		for root: Dictionary in roots: qualified.append(Contract.qualified_tree(root,upper))
		intervals.append({"lower":lower,"upper":upper,"roots":qualified})
		lower=upper
	return {"roots":roots,"rows":rows,"bounds":fine.bounds,"min_scale":0.0,"max_scale":fine.max_scale,
		"range":[0.0,fine.max_scale],"transition_only":true,"transition_sources":indices.duplicate(),
		"mixed_scales":true,"transition_intervals":intervals,"transition_leaves":leaves,"transition_spatial_trees":spatial_trees}


static func append_catalogs(catalogs: Array[Dictionary]) -> void:
	var indices: Array[int]=[]
	for index in catalogs.size():
		if not catalogs[index].get("transition_only",false): indices.append(index)
	indices.sort_custom(func(a: int,b: int) -> bool: return float(catalogs[a].max_scale)>float(catalogs[b].max_scale))
	var joined := build(catalogs,indices)
	if not joined.is_empty(): catalogs.append(joined)


static func index_for(catalogs: Array[Dictionary], current: int, successor: int) -> int:
	if current<0 or successor<0: return -1
	if current==successor and catalogs[current].get("transition_only",false): return current
	if catalogs[current].get("transition_sources",[]).has(successor): return current
	for index in catalogs.size():
		var sources: Array=catalogs[index].get("transition_sources",[])
		if sources.has(current) and sources.has(successor): return index
	return -1


static func changes_resources(catalogs: Array[Dictionary], old_index: int, old: Dictionary, index: int, cut: Dictionary) -> bool:
	var previous := {}
	for key: String in old.get("keys",[]):
		var row: Dictionary=catalogs[old_index].rows[key]
		previous[row.native_geometry.path+"|"+row.native_texture.path]=true
	for key: String in cut.get("keys",[]):
		var row: Dictionary=catalogs[index].rows[key]
		if not previous.has(row.native_geometry.path+"|"+row.native_texture.path): return true
	return false


static func scope(catalogs: Array[Dictionary], old_index: int, old: Dictionary, index: int, cut: Dictionary) -> Array[int]:
	var result: Array[int]=[]
	for pair: Array in [[old_index,old],[index,cut]]:
		var catalog_index: int=pair[0]
		if catalog_index<0: continue
		var catalog: Dictionary=catalogs[catalog_index]
		if not catalog.get("transition_only",false):
			if catalog_index not in result: result.append(catalog_index)
			continue
		var sources: Array=catalog.transition_sources
		for key: String in pair[1].get("keys",[]):
			var source: int=sources[int(key.get_slice(":",0))%sources.size()]
			if source not in result: result.append(source)
	return result


static func advance(catalogs: Array[Dictionary], old_index: int, old: Dictionary, destination: int,
		center: Vector2, scale: float, future_scale: float, angle: float, size: Vector2,
		extra_budget: int, costs: Dictionary, work: Dictionary, complete_deadline: bool = false) -> Dictionary:
	# 整档不能同池共存时，仅升级装得下的空间块；其他块保持已绑定的原资源。
	# 旧块守此刻资格，升级块守预测资格；绝不要求所有旧块在第一步就同时升级。
	var index := index_for(catalogs,old_index,destination)
	if index<0 or extra_budget<=0 or costs.is_empty(): return {}
	var catalog: Dictionary=catalogs[index]
	var sources: Array=catalog.transition_sources
	var destination_variant := sources.find(destination)
	if destination_variant<0: return {}
	var roots: Array[Dictionary]=[]
	var old_rows: Array[Dictionary]=[]
	for entry: Dictionary in old.get("entries",[]):
		var key: String=entry.key
		var row: Dictionary=catalogs[old_index].rows[key]
		if not catalogs[old_index].get("transition_only",false):
			key="%d:%s"%[int(row.depth)*sources.size()+sources.find(old_index),key.get_slice(":",1)]
		var kept := entry.duplicate()
		kept["key"]=key;kept["max_scale"]=float(catalog.rows[key].max_scale)
		kept.erase("children")
		if scale>float(kept.max_scale)*1.10: return {}
		roots.append(kept);old_rows.append(catalog.rows[key])
	var order: Array[Dictionary]=[]
	var deadline_views := {}
	for n in roots.size():
		var limit := float(old_rows[n].max_scale)
		var deadline := minf(future_scale,limit*1.10)
		if not deadline_views.has(deadline):
			deadline_views[deadline]=Contract.visible_keys({"entries":roots},center,deadline,angle,size)
		order.append({"index":n,"limit":limit,"visible":roots[n].key in deadline_views[deadline]})
	# 先救最早到期的页；同一期限先准备仍在屏内的块，避免离屏升级挤掉真正接管页。
	# 仅改变原交接顺序，候选仍完整覆盖当前宽视野并通过原资格、页数和物理预算。
	order.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.limit!=b.limit: return a.limit<b.limit
		if a.visible!=b.visible: return a.visible
		return a.index<b.index)
	var batches: Array=[]
	if complete_deadline:
		var earliest: Array[int]=[]
		for item: Dictionary in order:
			if item.limit<future_scale: earliest.append(item.index)
		if earliest.is_empty(): return {}
		batches.append(earliest)
	else:
		for item: Dictionary in order:
			if item.limit<future_scale: batches.append([item.index])
	for batch: Array in batches:
		var trial := roots.duplicate()
		var valid := true
		for n: int in batch:
			var depth := int(old_rows[n].depth)/sources.size()
			var id_value := int(String(roots[n].key).get_slice(":",1))
			var upgraded := Contract.tree(catalog.rows,depth*sources.size()+destination_variant,id_value)
			var only_destination := Contract.transition_roots([upgraded],sources,[destination])
			if only_destination.size()!=1: valid=false;break
			trial[n]=Contract.qualified_tree(only_destination[0],future_scale)
		if not valid: continue
		var incremental: Array[Dictionary]=[]
		for root: Dictionary in trial: incremental.append(Contract.incremental_tree(root,costs))
		var candidate := Contract.select_handoff(catalog,center,scale,angle,size,extra_budget,costs,work,true,scale,incremental)
		if not candidate.is_empty(): candidate["selection_stage"]="incremental_scale"
		if candidate.is_empty() or not candidate.within_budget \
			or not (preload("res://scripts/rendering/tokyo_hlod_handoff.gd").qualified(catalog,candidate,scale) or inherits_grace(catalogs,old_index,old,index,candidate,scale)) \
			or not preload("res://scripts/rendering/tokyo_hlod_handoff.gd").covers_motion_view(catalog,candidate,center,scale,angle,size) \
			or not changes_resources(catalogs,old_index,old,index,candidate): continue
		# 首步可只交接一块；已开始交接后一次完成预测期限内的到期页，避免相邻期限串行等待。
		return {"catalog":index,"cut":candidate}
	# 父页整块升级可能超过联合池，但同档子页仍可共存。先保持清晰度拆页，
	# 释放父页后由既有接续链逐页升级；不可借拆页新增或延长资格宽限。
	for item: Dictionary in order:
		if item.limit>=future_scale: continue
		var n: int=item.index
		var variant := int(old_rows[n].depth)%sources.size()
		var depth := int(old_rows[n].depth)/sources.size()
		var original_key := "%d:%s"%[depth,String(roots[n].key).get_slice(":",1)]
		var original: Dictionary=catalogs[sources[variant]].rows[original_key]
		if original.children.is_empty(): continue
		var trial := roots.duplicate()
		trial.remove_at(n)
		for child: int in original.children:
			var tree := Contract.tree(catalog.rows,(depth+1)*sources.size()+variant,child)
			var same_level := Contract.transition_roots([tree],sources,[sources[variant]])
			for child_root: Dictionary in same_level:
				trial.append(Contract.qualified_tree(child_root,scale))
		if trial.size()>16: continue
		var incremental: Array[Dictionary]=[]
		for root: Dictionary in trial: incremental.append(Contract.incremental_tree(root,costs))
		var candidate := Contract.select_handoff(catalog,center,scale,angle,size,extra_budget,costs,work,true,scale,incremental)
		if candidate.is_empty() or not candidate.within_budget \
			or not preload("res://scripts/rendering/tokyo_hlod_handoff.gd").qualified(catalog,candidate,scale) \
			or not preload("res://scripts/rendering/tokyo_hlod_handoff.gd").covers_motion_view(catalog,candidate,center,scale,angle,size) \
			or not changes_resources(catalogs,old_index,old,index,candidate): continue
		candidate["selection_stage"]="incremental_scale"
		candidate["spatial_partition"]=true
		return {"catalog":index,"cut":candidate}
	return {}


static func inherits_grace(catalogs: Array[Dictionary], old_index: int, old: Dictionary,
		index: int, cut: Dictionary, scale: float) -> bool:
	# 仅允许原样保留已显示的过渡页；新加入的页必须此刻合格，不能借交接重置宽限。
	if old_index<0 or index<0 or cut.get("selection_stage","") not in ["incremental_scale","trim"]: return false
	var displayed := {}
	for key: String in old.get("keys",[]):
		var row: Dictionary=catalogs[old_index].rows[key]
		displayed[row.native_geometry.path+"|"+row.native_texture.path]=true
	var inherited := false
	for key: String in cut.get("keys",[]):
		var row: Dictionary=catalogs[index].rows[key]
		if cut.get("selection_stage","")=="trim" and not displayed.has(row.native_geometry.path+"|"+row.native_texture.path): return false
		var limit := minf(float(row.get("max_scale",INF)),float(catalogs[index].max_scale))
		if scale<=limit: continue
		if scale>limit*1.10: return false
		if not displayed.has(row.native_geometry.path+"|"+row.native_texture.path): return false
		inherited=true
	return inherited


static func compact_display(catalogs: Array[Dictionary], old_index: int, old: Dictionary, destination: int,
		center: Vector2, scale: float, angle: float, size: Vector2, extra_budget: int,
		costs: Dictionary, work: Dictionary) -> Dictionary:
	# 逐空间块换成此刻实际档。每一步保留其余旧块，不能借旧页宽限或超预算整档替换。
	var index := index_for(catalogs,old_index,destination)
	if index<0 or extra_budget<=0 or costs.is_empty(): return {}
	var catalog: Dictionary=catalogs[index]
	var sources: Array=catalog.transition_sources
	var destination_variant := sources.find(destination)
	if destination_variant<0: return {}
	var roots: Array[Dictionary]=[]
	var changes: Array[Dictionary]=[]
	for key: String in old.get("keys",[]):
		var row: Dictionary=catalogs[old_index].rows[key]
		var depth := int(row.depth)/sources.size() if catalogs[old_index].get("transition_only",false) else int(row.depth)
		var current_variant := int(row.depth)%sources.size() if catalogs[old_index].get("transition_only",false) else sources.find(old_index)
		if current_variant<0: return {}
		var id_value := int(key.get_slice(":",1))
		var kept: Dictionary=catalog.transition_leaves["%d:%d"%[depth*sources.size()+current_variant,id_value]]
		roots.append(kept)
		var wanted: Dictionary=catalog.transition_leaves["%d:%d"%[depth*sources.size()+destination_variant,id_value]]
		if float(wanted.max_scale)<scale or int(wanted.bytes)>=int(kept.bytes): continue
		changes.append({"slot":roots.size()-1,"entry":wanted,"saving":int(kept.bytes)-int(wanted.bytes)})
	changes.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.saving>b.saving)
	var best: Dictionary={}
	for change: Dictionary in changes:
		var trial := roots.duplicate()
		trial[int(change.slot)]=change.entry
		var incremental: Array[Dictionary]=[]
		for root: Dictionary in trial: incremental.append(Contract.incremental_tree(root,costs))
		var candidate := Contract.select_handoff(catalog,center,scale,angle,size,extra_budget,costs,work,true,scale,incremental)
		if candidate.is_empty() or not candidate.within_budget or int(candidate.bytes)>=int(old.bytes) \
			or not preload("res://scripts/rendering/tokyo_hlod_handoff.gd").qualified(catalog,candidate,scale) \
			or not preload("res://scripts/rendering/tokyo_hlod_handoff.gd").covers_motion_view(catalog,candidate,center,scale,angle,size): continue
		roots=trial;best=candidate
	if best.is_empty():
		# 同档大父页也可能无法与完整紧凑切面共存。一次只将一个父页替换为
		# 同档空间子树，其他页保持原资源；费用按真实增量算，不能要求整档重载。
		for original: Dictionary in roots.duplicate():
			var slot := -1
			for index_value in roots.size():
				if roots[index_value].key==original.key: slot=index_value;break
			if slot<0: continue
			var branch: Dictionary=catalog.transition_spatial_trees[original.key]
			if branch.get("children",[]).is_empty(): continue
			var trial := roots.duplicate()
			trial.remove_at(slot)
			trial.append_array(branch.children)
			var visible := Contract.visible_keys({"entries":trial},center,scale,angle,size)
			if visible.size()>16: continue
			var incremental: Array[Dictionary]=[]
			for root: Dictionary in trial:
				if root.key in visible: incremental.append(Contract.incremental_tree(root,costs))
			var candidate := Contract.select_handoff(catalog,center,scale,angle,size,extra_budget,costs,work,true,scale,incremental)
			if candidate.is_empty() or not candidate.within_budget or int(candidate.bytes)>=int(old.bytes) \
				or not preload("res://scripts/rendering/tokyo_hlod_handoff.gd").qualified(catalog,candidate,scale) \
				or not preload("res://scripts/rendering/tokyo_hlod_handoff.gd").covers_motion_view(catalog,candidate,center,scale,angle,size): continue
			if best.is_empty() or int(candidate.bytes)<int(best.bytes):
				# 同一旧切面与全部新页一起核增量费用；能同池准备的多个分块合成
				# 一次事务，不让 SPACE 返回串行等待每个父页各自规划、加载、提交。
				best=candidate
				roots.assign(candidate.entries)
	if best.is_empty(): return {}
	best["selection_stage"]="compact_displayed_scale"
	return {"catalog":index,"cut":best}
