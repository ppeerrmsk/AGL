extends RefCounted
## 正式原生叶无损二分；旧替换保留，新来源独立回读证明。
const Override := preload("res://scripts/rendering/tokyo_partition_override.gd")
const Attach := preload("res://scripts/tests/tokyo_partition_attach_probe.gd")
const Adapter := preload("res://scripts/rendering/tokyo_partition_catalog.gd")
const Boundary := preload("res://scripts/tests/build_tokyo_boundary_tree.gd")
const Assembly := preload("res://scripts/rendering/tokyo_component_page.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")


static func save_json(path: String, value: Dictionary) -> Dictionary:
	if FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return {}
	file.store_string(JSON.stringify(value,"\t"));file.close()
	return {"path":path,"sha256":FileAccess.get_sha256(path)}


static func valid_leaf_plan(value: Variant, tree: Dictionary, depth: int) -> bool:
	if depth<1 or depth>8 or tree.is_empty() or not value is Dictionary: return false
	if value.get("split_depth")!=depth or value.get("tree_sha256")!=var_to_bytes(tree).hex_encode().sha256_text() \
		or not value.get("cuts") is Dictionary or value.cuts.size()!=(1<<depth)-1: return false
	var paths: Array[String]=[tree.path]
	for level in depth:
		var children: Array[String]=[]
		for path: String in paths:
			if preload("res://scripts/tests/tokyo_native_refinement_probe.gd").planned_cut(value.cuts,path).is_empty(): return false
			children.append(path+"/probe_0");children.append(path+"/probe_1")
		paths=children
	return true


static func run(input: Dictionary, digest: String) -> int:
	var branch_cells: Variant=input.get("branch_cells",[])
	var branch_targets: Variant=input.get("branch_targets",[])
	if not input.get("preserve_game_sources",false) is bool or not input.get("defer_spatial_validation",false) is bool: return 1
	var preserve_game: bool=input.get("preserve_game_sources",false)
	var defer_spatial: bool=input.get("defer_spatial_validation",false)
	var formal_expected: Variant=input.get("formal_expected",{})
	if not formal_expected is Dictionary or (preserve_game and formal_expected.is_empty()): return 1
	if not branch_cells is Array or branch_cells.size()>16 or not branch_targets is Array or branch_targets.size()>128 \
		or (not branch_cells.is_empty() and not branch_targets.is_empty()): return 1
	var seen_targets: Dictionary={}
	for target: Variant in branch_targets:
		if not target is String or target.is_empty() or seen_targets.has(target): return 1
		seen_targets[target]=true
	var regional: bool=not branch_cells.is_empty() or not branch_targets.is_empty()
	for cell: Variant in branch_cells:
		if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").integer(cell) or int(cell)<0: return 1
	# JSON 数字读为 float；Array.has 不做数值类型转换，先规范化再匹配目录里的 int。
	for index in branch_cells.size(): branch_cells[index]=int(branch_cells[index])
	var requested_depth: Variant=input.get("split_depth",1)
	# 深度只控制离线候选树，显示仍由原16页/24万面门判定；每层照常逐角守恒。
	if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").integer(requested_depth) or int(requested_depth)<1 or int(requested_depth)>(8 if regional else 4): return 1
	var split_depth := int(requested_depth)
	var split_balance := String(input.get("split_balance","median"))
	var requested_aspect: Variant=input.get("split_aspect",1.0)
	if split_balance not in ["median","area","sah"] or typeof(requested_aspect) not in [TYPE_INT,TYPE_FLOAT]: return 1
	var split_aspect := float(requested_aspect)
	if not is_finite(split_aspect) or split_aspect<0.25 or split_aspect>4.0: return 1
	var package := Override.json_binding(input.get("lossless_leaf_package"))
	var poses := Override.json_binding(input.get("poses"))
	var output: String=input.get("output","")
	if package.is_empty() or not poses.get("poses") is Array or poses.poses.is_empty() \
		or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.get("native",{})): return 1
	for target: String in branch_targets:
		if not native.pages.has(target): return 1
		var configuration: String=native.pages[target].get("canonical_identity",{}).get("configuration","")
		if configuration not in ["lod4_full","lod5_full"]: return 1
		var original := Attach.find_entry(native.catalog.configurations[configuration],target)
		var current := Attach.find_entry(native._partition_roots.get(configuration,native.catalog.configurations[configuration]),target)
		if original!=current or not refinable_source(original,native,configuration,[],branch_targets,preserve_game): return 1
	var leaf_plans: Dictionary={}
	if input.has("leaf_split_plans"):
		var bound_plans := Override.json_binding(input.leaf_split_plans)
		if bound_plans.get("schema")!=1 or not bound_plans.get("plans") is Dictionary or bound_plans.plans.is_empty(): return 1
		leaf_plans=bound_plans.plans
		for target: String in leaf_plans:
			if not native.pages.has(target): return 1
			var configuration: String=native.pages[target].canonical_identity.get("configuration","")
			if configuration not in ["lod4_full","lod5_full"]: return 1
			var original := Attach.find_entry(native.catalog.configurations[configuration],target)
			var source_depth: Variant=leaf_plans[target].get("split_depth") if leaf_plans[target] is Dictionary else null
			if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").integer(source_depth) or int(source_depth)>split_depth: return 1
			if original.is_empty() or not refinable_source(original,native,configuration,branch_cells,branch_targets,preserve_game) or not valid_leaf_plan(leaf_plans[target],original,int(source_depth)): return 1
	var prior: Dictionary=package.native.get("partition_override",{})
	var attachment := Override.json_binding(prior.get("input"))
	var proof := Override.json_binding(prior.get("proof"))
	# 未做过分区的正式底座可以从空证据开始；损坏的既有接合不能降级为空。
	if not package.native.has("partition_override"):
		attachment={"attachments":[]}
		proof={"catalog_sha256":native.catalog_sha,"rows":[],"runtime_integrated":false}
	# 可安装包仅保存接合身份和守恒证明，迁址时不携带旧制作机位；不能假定poses存在。
	# 若仍携带旧机位则全部复验，非法类型必须在写资源之前拒绝。
	var prior_poses: Variant=attachment.get("poses",[])
	if not prior_poses is Array: return 1
	if attachment.is_empty() or proof.is_empty() or DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var new_rows: Array=[]
	var saved_page_count := 0
	if not input.get("probe_only",false) is bool: return 1
	var probe_only: bool=input.get("probe_only",false)
	var probe_rows: Array=[]
	var probe_failures := 0
	for configuration in ["lod4_full","lod5_full"]:
		var probe := preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
		probe.branching=2
		probe.current_roots=true
		probe.refine_branches=regional
		probe.split_balance=split_balance;probe.split_aspect=split_aspect
		probe.leaf_split_plans=leaf_plans
		probe.eligible_leaf=refinable_source.bind(native,configuration,branch_cells,branch_targets,preserve_game)
		for pose: Dictionary in poses.poses:
			var cut := probe.select(native,Vector2(pose.center[0],pose.center[1]),float(pose.scale),
				float(pose.rotation),Vector2(1600,900),configuration,split_depth)
			probe_rows.append({"pose":pose,"configuration":configuration,"faces":cut.get("triangles",-1),"bytes":cut.get("bytes",-1),"pages":cut.get("active",-1),"refined_sources":probe.refined_leaves,"within_budget":not probe.failed and cut.get("within_budget",false)})
			if probe_only: probe_rows[-1]["entries"]=cut.get("entries",[])
			var progress := FileAccess.open(output.path_join("progress.json"),FileAccess.WRITE)
			if progress!=null:
				progress.store_string(JSON.stringify({"stage":"probe","configuration":configuration,"checked":probe_rows.size(),"fail":probe_failures,"refined_sources":probe.refined_leaves}));progress.close()
			if not probe_only and (probe.failed or cut.is_empty()): return 1
			if probe.failed or cut.is_empty() or not cut.within_budget:
				print("[lossless leaf] rejected pose=",pose," configuration=",configuration," faces=",cut.get("triangles",-1)," bytes=",cut.get("bytes",-1)," pages=",cut.get("active",-1))
				probe_failures+=1
				if not probe_only and not defer_spatial: return 1
		if probe_only:
			var cache_file := FileAccess.open(output.path_join(configuration+"_trees.bin"),FileAccess.WRITE)
			if cache_file==null: return 1
			cache_file.store_var({"input_sha256":digest,"source_catalog_sha256":native.catalog_sha,"trees":probe._cache});cache_file.close()
			if save_json(output.path_join(configuration+"_plans.json"),{"schema":1,"plans":probe.recorded_plans}).is_empty(): return 1
			continue
		for refined: Dictionary in probe._cache.values():
			var target: String=refined.path
			var original := Attach.find_entry(native.catalog.configurations[configuration],target)
			if not refinable_source(original,native,configuration,branch_cells,branch_targets,preserve_game):
				print("[lossless leaf] source not refinable: ",target);return 1
			# 不覆盖此前替换的子树，两份证据不能争夺同一正式来源。
			var current: Array=native._partition_roots.get(configuration,native.catalog.configurations[configuration])
			if Attach.find_entry(current,target).is_empty():
				print("[lossless leaf] source already replaced: ",target);return 1
			var row: Dictionary=native.pages[target]
			var meshes := Boundary.meshes(row,row.components)
			if meshes.size()!=3: return 1
			var directory := output.path_join(configuration+"_"+target.sha256_text())
			var writer := preload("res://scripts/tests/tokyo_partition_page_writer.gd").new()
			writer.output=directory.path_join("components")
			var splitter := preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
			splitter.branching=2;splitter.page_sink=writer.emit
			splitter.split_balance=split_balance;splitter.split_aspect=split_aspect
			splitter.split_plan=leaf_plans.get(target,{}).get("cuts",{})
			# 原生目录用PackedInt32Array，独立分区协议用Array[int]；仅转换元数据容器。
			var seed := original.duplicate()
			seed.triangles=Array(original.triangles)
			var source_depth := int(leaf_plans.get(target,{}).get("split_depth",split_depth))
			var tree := splitter._split(seed,meshes,source_depth)
			# 面积分割可以提前产生空叶；对实际二叉树逐分支核守恒，不能假设每层都满。
			if splitter.failed or writer.pages.size()<3 or splitter.conserved_splits!=3*((writer.pages.size()-1)/2): return 1
			saved_page_count+=writer.pages.size()
			var binding := writer.finish(tree,digest)
			if binding.is_empty(): return 1
			binding.configuration=configuration
			print("[lossless leaf] emitted ",target," nodes=",writer.pages.size())
			var check_file := FileAccess.open(binding.path,FileAccess.READ)
			var check_data: Dictionary=check_file.get_var(false)
			check_file.close()
			if Adapter.normalize(check_data,binding).is_empty():
				print("[lossless leaf] normalization rejected ",tree)
				return 1
			var packed_dir := directory.path_join("packed")
			if preload("res://scripts/tests/repack_tokyo_partition.gd").run({"repack_partition":binding,"output":packed_dir},digest)!=0: return 1
			var packed_report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(packed_dir.path_join("report.json")))
			var packed: Dictionary=packed_report.partition
			var file := FileAccess.open(packed.path,FileAccess.READ)
			if file==null: return 1
			var data: Variant=file.get_var(false);file.close()
			if not data is Dictionary: return 1
			var normalized := Adapter.normalize(data,packed)
			if normalized.is_empty(): return 1
			var loaded: Dictionary={}
			for part: Dictionary in normalized.pages[normalized.tree.path].components.values():
				if FileAccess.get_sha256(part.path)!=part.sha256: return 1
				loaded[part.path]=ResourceLoader.load(part.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var restored := Assembly.assemble(normalized.pages[normalized.tree.path],loaded)
			if restored==null: return 1
			var matches: Array=[]
			for kind in 3: matches.append(Join.conserved(meshes[kind],[restored.meshes[kind]]))
			if false in matches: return 1
			attachment.attachments.append({"configuration":configuration,"partition":packed,"original_native":target})
			var evidence := {"configuration":configuration,"target":target,"identity":row.canonical_identity,
				"tree_sha256":var_to_bytes(original).hex_encode().sha256_text(),"original_layers_equal":matches,
				"untouched_layers_equal":[matches[0],matches[2]],"no_game_sources":Attach.no_game_sources(original,native,configuration),
				"lossless_all_layers":true,"conserved_splits":splitter.conserved_splits,"split_depth":source_depth}
			if not evidence.no_game_sources:
				var certificate := preload("res://scripts/tests/build_tokyo_partition_coverage.gd").new()
				var certified := certificate.build(native,original,normalized,packed.sha256,formal_expected.get(configuration,{}),directory.path_join("formal_coverage.bin"))
				if certified.is_empty(): return 1
				evidence["formal_coverage"]=certified
			if leaf_plans.has(target): evidence["leaf_split_plan"]=input.leaf_split_plans
			proof.rows.append(evidence);new_rows.append(evidence)
	if probe_only:
		var report := {"input_sha256":digest,"probe_only":true,"fail":probe_failures,"cuts":probe_rows,"branch_cells":branch_cells,"branch_targets":branch_targets,"split_depth":split_depth,"split_balance":split_balance,"split_aspect":split_aspect}
		return 1 if save_json(output.path_join("report.json"),report).is_empty() else int(probe_failures>0)
	if new_rows.is_empty(): return 1
	attachment.output=output.path_join("proof.json")
	attachment.erase("export_actual")
	attachment["lossless_generation_input_sha256"]=digest
	var input_binding := save_json(output.path_join("attachments.json"),attachment)
	if input_binding.is_empty(): return 1
	proof.input_sha256=input_binding.sha256
	var proof_binding := save_json(attachment.output,proof)
	if proof_binding.is_empty(): return 1
	package.native.partition_override={"input":input_binding,"proof":proof_binding}
	var verified := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not verified.read(package.native): return 1
	var cuts: Dictionary={}
	var all_poses: Array=prior_poses.duplicate()
	all_poses.append_array(poses.poses)
	var failed_cuts := 0
	for configuration in ["lod4_full","lod5_full"]:
		cuts[configuration]=Attach.cuts(verified._partition_roots[configuration],all_poses,"")
		for cut: Dictionary in cuts[configuration]:
			# 此处为多份分区联合切面，不使用单一分区摘要的命中计数。
			cut.erase("new_pages")
			if not cut.within_budget:
				failed_cuts+=1
				if not defer_spatial: return 1
	var package_binding := save_json(output.path_join("package.json"),package)
	if package_binding.is_empty(): return 1
	var report := {"input_sha256":digest,"new_leaves":new_rows.size(),"new_pages":saved_page_count,"split_depth":split_depth,"split_balance":split_balance,"split_aspect":split_aspect,
		"branch_cells":branch_cells,"branch_targets":branch_targets,"new_source_proofs":new_rows,"full_map_cuts":cuts,"package":package_binding,
		"geometry_conserved":true,"runtime_verified":false,"performance_accepted":false,
		"failed_cuts":failed_cuts,"spatial_accepted":failed_cuts==0,"preserve_game_sources":preserve_game}
	return 0 if not save_json(output.path_join("report.json"),report).is_empty() else 1


static func refinable(entry: Dictionary, native: RefCounted, configuration: String) -> bool:
	# 分区覆盖层的逻辑页没有原生coverage条目；不可冒充未经替换的正式叶。
	var original := Attach.find_entry(native.catalog.configurations[configuration],entry.path)
	if original.is_empty(): return false
	if not original.children.is_empty(): return false
	return Attach.no_game_sources(original,native,configuration)


static func refinable_source(entry: Dictionary, native: RefCounted, configuration: String, branch_cells: Array, branch_targets: Array = [], preserve_game_sources: bool = false) -> bool:
	if branch_cells.is_empty() and branch_targets.is_empty(): return refinable(entry,native,configuration)
	if entry.is_empty() or not native.pages.has(entry.path): return false
	var identity: Dictionary=native.pages[entry.path].get("canonical_identity",{})
	# 明确指定的原生区域整体重新分桶，避免保留旧叶边界使16页先被碎片占满。
	# 正式楼与已替换子树仍不得纳入；运行时消费原协议和原预算。
	if identity.get("configuration","")!=configuration: return false
	if not branch_targets.is_empty():
		if entry.path not in branch_targets: return false
	elif int(identity.parent)!=1 or int(identity.cell) not in branch_cells: return false
	var original := Attach.find_entry(native.catalog.configurations[configuration],entry.path)
	return not original.is_empty() and original==entry and (preserve_game_sources or Attach.no_game_sources(original,native,configuration))
