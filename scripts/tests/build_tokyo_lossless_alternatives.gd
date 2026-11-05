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


static func run(input: Dictionary, digest: String) -> int:
	var package := Override.json_binding(input.get("lossless_alternatives_package"))
	var poses := Override.json_binding(input.get("poses"))
	var plan := Override.json_binding(input.get("variants_plan"))
	var output: String=input.get("output","")
	var split_depth := 4
	if package.is_empty() or not poses.get("poses") is Array or poses.poses.is_empty() \
		or not plan.get("sources") is Dictionary or plan.sources.is_empty() or not plan.get("variants") is Array \
		or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.get("native",{})): return 1
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
	for target: String in plan.sources:
		if not native.pages.has(target): return 1
		var configuration: String=native.pages[target].canonical_identity.configuration
		if configuration not in ["lod4_full","lod5_full"]: return 1
		var original := Attach.find_entry(native.catalog.configurations[configuration],target)
		if original.is_empty() or not original.children.is_empty() or not Attach.no_game_sources(original,native,configuration): return 1
		var used := {}
		for variant_id: Variant in plan.sources[target]:
			if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").integer(variant_id) or int(variant_id)<0 or int(variant_id)>=plan.variants.size() or used.has(int(variant_id)): return 1
			used[int(variant_id)]=true
			var variant: Dictionary=plan.variants[int(variant_id)]
			var split_balance: String=variant.get("balance","")
			var split_aspect := float(variant.get("aspect",0.0))
			if split_balance not in ["median","area","sah"] or not is_finite(split_aspect) or split_aspect<0.25 or split_aspect>4.0: return 1
			var row: Dictionary=native.pages[target]
			var meshes := Boundary.meshes(row,row.components)
			if meshes.size()!=3: return 1
			var directory := output.path_join(configuration+"_"+target.sha256_text()+"_v"+str(int(variant_id)))
			var writer := preload("res://scripts/tests/tokyo_partition_page_writer.gd").new()
			writer.output=directory.path_join("components")
			var splitter := preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
			splitter.branching=2;splitter.page_sink=writer.emit
			splitter.split_balance=split_balance
			splitter.split_aspect=split_aspect
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
			evidence["variant_plan"]=input.variants_plan
			evidence["variant_id"]=int(variant_id)
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
	package.native.partition_override={"input":input_binding,"proof":proof_binding,"preserve_source_roots":true,"allow_lossless_alternatives":true}
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
