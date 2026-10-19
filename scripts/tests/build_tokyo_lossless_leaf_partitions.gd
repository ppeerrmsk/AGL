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
	if depth not in [1,2,3,4] or tree.is_empty() or not value is Dictionary: return false
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
	var requested_depth: Variant=input.get("split_depth",1)
	# 深度只控制离线候选树，显示仍由原16页/24万面门判定；每层照常逐角守恒。
	if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").integer(requested_depth) or int(requested_depth) not in [1,2,3,4]: return 1
	var split_depth := int(requested_depth)
	var package := Override.json_binding(input.get("lossless_leaf_package"))
	var poses := Override.json_binding(input.get("poses"))
	var output: String=input.get("output","")
	if package.is_empty() or not poses.get("poses") is Array or poses.poses.is_empty() \
		or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.get("native",{})): return 1
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
			if original.is_empty() or not refinable(original,native,configuration) or not valid_leaf_plan(leaf_plans[target],original,split_depth): return 1
	var prior: Dictionary=package.native.get("partition_override",{})
	var attachment := Override.json_binding(prior.get("input"))
	var proof := Override.json_binding(prior.get("proof"))
	# 可安装包仅保存接合身份和守恒证明，迁址时不携带旧制作机位；不能假定poses存在。
	# 若仍携带旧机位则全部复验，非法类型必须在写资源之前拒绝。
	var prior_poses: Variant=attachment.get("poses",[])
	if not prior_poses is Array: return 1
	if attachment.is_empty() or proof.is_empty() or DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var new_rows: Array=[]
	for configuration in ["lod4_full","lod5_full"]:
		var probe := preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
		probe.branching=2
		probe.current_roots=true
		probe.leaf_split_plans=leaf_plans
		probe.eligible_leaf=refinable.bind(native,configuration)
		for pose: Dictionary in poses.poses:
			var cut := probe.select(native,Vector2(pose.center[0],pose.center[1]),float(pose.scale),
				float(pose.rotation),Vector2(1600,900),configuration,split_depth)
			if probe.failed or cut.is_empty() or not cut.within_budget:
				print("[lossless leaf] rejected pose=",pose," configuration=",configuration," faces=",cut.get("triangles",-1)," bytes=",cut.get("bytes",-1)," pages=",cut.get("active",-1))
				return 1
		for refined: Dictionary in probe._cache.values():
			var target: String=refined.path
			var original := Attach.find_entry(native.catalog.configurations[configuration],target)
			if original.is_empty() or not original.children.is_empty() \
				or not Attach.no_game_sources(original,native,configuration):
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
			splitter.split_plan=leaf_plans.get(target,{}).get("cuts",{})
			# 原生目录用PackedInt32Array，独立分区协议用Array[int]；仅转换元数据容器。
			var seed := original.duplicate()
			seed.triangles=Array(original.triangles)
			var tree := splitter._split(seed,meshes,split_depth)
			if splitter.failed or splitter.conserved_splits!=3*((1<<split_depth)-1): return 1
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
				"untouched_layers_equal":[matches[0],matches[2]],"no_game_sources":true,
				"lossless_all_layers":true,"conserved_splits":splitter.conserved_splits}
			if leaf_plans.has(target): evidence["leaf_split_plan"]=input.leaf_split_plans
			proof.rows.append(evidence);new_rows.append(evidence)
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
	for configuration in ["lod4_full","lod5_full"]:
		cuts[configuration]=Attach.cuts(verified._partition_roots[configuration],all_poses,"")
		for cut: Dictionary in cuts[configuration]:
			# 此处为多份分区联合切面，不使用单一分区摘要的命中计数。
			cut.erase("new_pages")
			if not cut.within_budget: return 1
	var package_binding := save_json(output.path_join("package.json"),package)
	if package_binding.is_empty(): return 1
	var report := {"input_sha256":digest,"new_leaves":new_rows.size(),"new_pages":new_rows.size()*((1<<(split_depth+1))-1),"split_depth":split_depth,
		"new_source_proofs":new_rows,"full_map_cuts":cuts,"package":package_binding,
		"geometry_conserved":true,"runtime_verified":false,"performance_accepted":false}
	return 0 if not save_json(output.path_join("report.json"),report).is_empty() else 1


static func refinable(entry: Dictionary, native: RefCounted, configuration: String) -> bool:
	# 分区覆盖层的逻辑页没有原生coverage条目；不可冒充未经替换的正式叶。
	var original := Attach.find_entry(native.catalog.configurations[configuration],entry.path)
	if original.is_empty() or not original.children.is_empty(): return false
	return Attach.no_game_sources(original,native,configuration)
