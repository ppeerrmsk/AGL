extends RefCounted
## 保存缺口的物理身份账本；不启动流送、不授予全图常驻或性能资格。
static func run(native: RefCounted, package: Dictionary, input: Dictionary) -> int:
	var binding: Dictionary=input.residency_gap_audit
	if not native.Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var evidence: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not evidence is Dictionary or not evidence.get("wasd") is Dictionary: return 1
	var geometry: Dictionary=native.pages.duplicate()
	var textures: Dictionary=native.ground.textures.duplicate()
	var catalogs: Array[Dictionary]=[]
	for item: Dictionary in package.catalogs:
		var catalog: Dictionary=native.Contract.read(item.path,item.sha256)
		if catalog.is_empty(): return 1
		var covered: Dictionary=preload("res://scripts/rendering/tokyo_hlod_coverage.gd").read(package.coverage.path,package.coverage.sha256,catalog)
		if covered.is_empty(): return 1
		for path: String in covered:
			if geometry.has(path) and geometry[path]!=covered[path]: return 1
			geometry[path]=covered[path]
		textures.merge(catalog.textures)
		catalogs.append(catalog)
	var foundation: Dictionary=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").plan(catalogs,192*1024*1024,true)
	if foundation.is_empty(): return 1
	var handoff=preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
	var ledger := {"bytes":0,"meshes":{},"images":{}}
	if not handoff.append_streaming_bundle(ledger,geometry,textures,foundation.meshes,foundation.images,9223372036854775807): return 1
	var base_bytes: int=ledger.bytes
	var physical: Dictionary={}
	for row: Dictionary in geometry.values():
		for path: String in row.get("components",{}):
			var component: Dictionary=row.components[path]
			if physical.has(path) and physical[path]!=component: return 1
			physical[path]=component
	# HLOD的直接物理描述符也必须纳入，不能只数原生逻辑页。
	for path: String in geometry:
		if not geometry[path].has("components"):
			if physical.has(path) and physical[path]!=geometry[path]: return 1
			physical[path]=geometry[path]
	var rows: Array=[]
	var additions: Dictionary={}
	for snapshot: Dictionary in evidence.wasd.snapshots:
		var incremental := 0
		var missing: Array=[]
		for part: Dictionary in snapshot.target_status.missing_meshes:
			var path: String=part.path
			if not physical.has(path): return 1
			var amount: int=physical[path].bytes
			var resident: bool=ledger.meshes.has(path)
			if not resident: incremental+=amount;additions[path]=amount
			missing.append({"path":path,"bytes":amount,"already_resident":resident})
		rows.append({"ms":snapshot.ms,"missing":missing,"additional_bytes":incremental})
	var extra := 0
	for amount: int in additions.values(): extra+=amount
	var all_native := {"bytes":0,"meshes":{},"images":{}}
	if not handoff.append_streaming_bundle(all_native,native.pages,native.ground.textures,PackedStringArray(native.pages.keys()),PackedStringArray(),9223372036854775807): return 1
	# 分开核单一空间表示，不能用包含互斥父子/LOD的全目录总和证明常驻无解。
	var representations: Array=[]
	var lower_foundation: Dictionary=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").plan(catalogs,192*1024*1024,false)
	var lower_ledger := {"bytes":0,"meshes":{},"images":{}}
	if lower_foundation.is_empty() or not handoff.append_streaming_bundle(lower_ledger,geometry,textures,lower_foundation.meshes,lower_foundation.images,9223372036854775807): return 1
	# 中景只保留单叶表示，不把互斥父子节点一起计入。
	var middle_keys := PackedStringArray()
	var middle_stack: Array=native._partition_roots.get("lod4_full",native.catalog.configurations.lod4_full).duplicate()
	while not middle_stack.is_empty():
		var node: Dictionary=middle_stack.pop_back()
		if not node.get("children",[]).is_empty(): middle_stack.append_array(node.children)
		else: middle_keys.append(node.path)
	var middle := {"bytes":0,"meshes":{},"images":{}}
	if not handoff.append_streaming_bundle(middle,native.pages,native.ground.textures,middle_keys,PackedStringArray(),9223372036854775807): return 1
	for building_mode: String in ["coarse","fine","both"]:
		var building_keys := PackedStringArray()
		for key: String in native._grid_entries:
			if building_mode!="fine": building_keys.append(key)
			if building_mode!="coarse": building_keys.append(key+"/fine3")
		var building := {"bytes":0,"meshes":{},"images":{}}
		if not handoff.append_streaming_bundle(building,native.pages,native.ground.textures,building_keys,PackedStringArray(),9223372036854775807): return 1
		for ground_mode: String in ["roots","leaves","all"]:
			var ground_parts: Dictionary={}
			var stack: Array=native._grid_native_ground.duplicate()
			while not stack.is_empty():
				var node: Dictionary=stack.pop_back()
				if ground_mode!="roots" and not node.get("children",[]).is_empty():
					stack.append_array(node.children)
					if ground_mode=="leaves": continue
				var row: Dictionary=native.pages[node.path]
				var parts: Dictionary=row.components
				if row.has("mapping"):
					var path: String=row.mapping[2][0]
					parts={path:row.components[path]}
				for path: String in parts:
					if ground_parts.has(path) and ground_parts[path]!=parts[path]: return 1
					ground_parts[path]=parts[path]
			var combined: Dictionary=building.meshes.duplicate()
			for path: String in ground_parts:
				if combined.has(path) and combined[path]!=ground_parts[path]: return 1
				combined[path]=ground_parts[path]
			var amount := 0
			var extra_to_base := 0
			var extra_to_lower := 0
			for path: String in combined:
				amount+=int(combined[path].bytes)
				if ledger.meshes.has(path):
					if ledger.meshes[path]!=combined[path]: return 1
				else: extra_to_base+=int(combined[path].bytes)
				if lower_ledger.meshes.has(path):
					if lower_ledger.meshes[path]!=combined[path]: return 1
				else: extra_to_lower+=int(combined[path].bytes)
			var middle_extra := 0
			for path: String in middle.meshes:
				if combined.has(path):
					if combined[path]!=middle.meshes[path]: return 1
				elif lower_ledger.meshes.has(path):
					if lower_ledger.meshes[path]!=middle.meshes[path]: return 1
				else: middle_extra+=int(middle.meshes[path].bytes)
			representations.append({"building_mode":building_mode,"ground_mode":ground_mode,"physical_bytes":amount,
				"union_with_lower_and_middle_bytes":int(lower_ledger.bytes)+extra_to_lower+middle_extra,
				"middle_extra_bytes":middle_extra,
				"physical_count":combined.size(),"union_with_foundation_bytes":base_bytes+extra_to_base,
				"union_with_lower_foundation_bytes":int(lower_ledger.bytes)+extra_to_lower,
				"lower_fits_with_reserve":int(lower_ledger.bytes)+extra_to_lower<=4096*1024*1024-96*1024*1024,
				"fits_pool_with_reserve":base_bytes+extra_to_base<=4096*1024*1024-96*1024*1024,
				"display_budget_verified":false})
	var result := {"diagnostic_only":true,"runtime_acceptance":false,"foundation_bytes":base_bytes,
		"middle_single_leaf_bytes":middle.bytes,"middle_logical_pages":middle_keys.size(),"middle_physical_count":middle.meshes.size(),
		"lower_foundation_bytes":lower_ledger.bytes,
		"single_representation_costs":representations,
		"missing_union_bytes":extra,"foundation_plus_missing_bytes":base_bytes+extra,
		"pool_bytes":4096*1024*1024,"handoff_reserve":96*1024*1024,
		"saved_missing_fit":base_bytes+extra<=4096*1024*1024-96*1024*1024,
		"all_native_physical_bytes":all_native.bytes,"all_native_physical_count":all_native.meshes.size(),
		"rows":rows,"scope":"缺件并集可放下不等于全部接替资源或全图可常驻；全原生统计包含互斥LOD/分区候选。"}
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print("[Tokyo residency gap] base=%d missing_union=%d all_native=%d" % [base_bytes,extra,all_native.bytes])
	return 0
