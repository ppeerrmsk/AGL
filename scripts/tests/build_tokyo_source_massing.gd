extends RefCounted
## 已审计低楼候选的实际分页接合；保留旧证明，未改两层与保留面逐通道验证。
const Override := preload("res://scripts/rendering/tokyo_partition_override.gd")
const Attach := preload("res://scripts/tests/tokyo_partition_attach_probe.gd")
const Adapter := preload("res://scripts/rendering/tokyo_partition_catalog.gd")
const Boundary := preload("res://scripts/tests/build_tokyo_boundary_tree.gd")
const Assembly := preload("res://scripts/rendering/tokyo_component_page.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Read := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Review := preload("res://scripts/tests/tokyo_tagged_low_cut_review.gd")
const Save := preload("res://scripts/tests/build_tokyo_lossless_leaf_partitions.gd")


static func split_depth(input: Dictionary) -> int:
	var value: Variant=input.get("split_depth",2)
	if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").integer(value): return -1
	return int(value) if int(value) in [1,2,3,4] else -1


static func run(input: Dictionary, digest: String) -> int:
	# 完整来源可能大于原来的单叶；允许恢复合适的离线粒度，不放宽显示门。
	var depth := split_depth(input)
	if depth<0: return 1
	var package := Override.json_binding(input.get("source_massing_package"))
	var batch := Override.json_binding(input.get("candidates"))
	var exported := Override.json_binding(batch.get("source_report"))
	var poses := Override.json_binding(input.get("poses"))
	var output: String=input.get("output","")
	if package.is_empty() or batch.is_empty() or exported.is_empty() or poses.get("poses",[]).is_empty() \
		or exported.get("package_sha256")!=input.source_massing_package.sha256 \
		or not batch.get("rows") is Array or batch.rows.is_empty() or batch.rows.size()>32 \
		or not exported.get("rows") is Array or exported.rows.size()!=batch.rows.size() \
		or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.get("native",{})): return 1
	var prior: Dictionary=package.native.get("partition_override",{})
	var attachment := Override.json_binding(prior.get("input"))
	var proof := Override.json_binding(prior.get("proof"))
	if attachment.is_empty() or proof.is_empty() or exported.catalog_sha256!=native.catalog_sha: return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var saved_faces := 0
	var new_rows: Array=[]
	var seen: Dictionary={}
	for index in batch.rows.size():
		var request: Dictionary=batch.rows[index]
		var source: Dictionary=request.source
		if source!=exported.rows[index] or source.get("no_game_sources")!=true or source.get("current_tree_unchanged")!=true: return 1
		var configuration: String=source.configuration
		if configuration not in ["lod4_full","lod5_full"] or seen.has(source.target): return 1
		seen[source.target]=true
		var original := Attach.find_entry(native.catalog.configurations[configuration],source.target)
		var current := Attach.find_entry(native._partition_roots.get(configuration,native.catalog.configurations[configuration]),source.target)
		if original.is_empty() or current!=original or not Attach.no_game_sources(original,native,configuration) \
			or source.tree_sha256!=var_to_bytes(original).hex_encode().sha256_text() \
			or not Override.identity_matches(native.pages[source.target].canonical_identity,source.identity): return 1
		var candidate := Override.json_binding(request.candidate)
		# 相邻完整来源可使用各自已绑定的合并计划；没有逐项计划时兼容原单计划批次。
		var plan: Variant=request.get("plan",batch.get("plan"))
		if Override.json_binding(plan).is_empty(): return 1
		if candidate.is_empty() or candidate.get("source",{}).get("sha256")!=source.exports[1].sha256 \
			or candidate.get("plan",{})!=plan \
			or candidate.get("producer_sha256")!=batch.producer_sha256 \
			or candidate.get("formal_footprints_excluded")!=true or candidate.get("high_buildings_unchanged")!=true: return 1
		var partition_plan: Dictionary={}
		if request.has("partition_plan"):
			partition_plan=Override.json_binding(request.partition_plan)
			if partition_plan.get("schema")!=1 or partition_plan.get("split_depth")!=depth \
				or partition_plan.get("candidate_sha256")!=request.candidate.sha256 \
				or partition_plan.get("tree_sha256")!=source.tree_sha256 \
				or not partition_plan.get("cuts") is Dictionary \
				or partition_plan.cuts.size()!=(1<<depth)-1: return 1
		var row: Dictionary=native.pages[source.target]
		var original_meshes := Boundary.meshes(row,row.components)
		if original_meshes.size()!=3: return 1
		var matches: Array=[]
		for kind in 3:
			var restored := Review.mesh(source.exports[kind])
			if restored==null: return 1
			matches.append(Join.conserved(original_meshes[kind],[restored]))
		if false in matches: return 1
		var low := Review.mesh(candidate.geometry)
		if low==null: return 1
		low=Review.preserve_known(original_meshes[1],low,candidate.geometry,candidate.keep_mask)
		if low==null or Count.triangles(low)!=int(candidate.geometry.faces) \
			or Count.triangles(original_meshes[1])-Count.triangles(low)!=int(candidate.faces_saved): return 1
		var meshes: Array[ArrayMesh]=[original_meshes[0],low,original_meshes[2]]
		var seed := {"path":"source_root","children":[],"triangles":[],"boxes":[],"bytes":0}
		for mesh: ArrayMesh in meshes:
			seed.triangles.append(Count.triangles(mesh));seed.boxes.append(mesh.get_aabb());seed.bytes+=Read.decoded_bytes(mesh)
		var directory := output.path_join("source_%02d"%index)
		var writer := preload("res://scripts/tests/tokyo_partition_page_writer.gd").new()
		writer.output=directory.path_join("components")
		var splitter := preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
		splitter.branching=2;splitter.page_sink=writer.emit
		splitter.split_plan=partition_plan.get("cuts",{})
		var tree := splitter._split(seed,meshes,depth)
		if splitter.failed or splitter.conserved_splits!=3*((1<<depth)-1): return 1
		var binding := writer.finish(tree,digest)
		if binding.is_empty(): return 1
		binding.configuration=configuration
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
		for kind in 3:
			if not Join.conserved(meshes[kind],[restored.meshes[kind]]): return 1
		attachment.attachments.append({"configuration":configuration,"partition":packed,"original_native":source.target})
		var evidence := {"configuration":configuration,"target":source.target,"identity":source.identity,
			"tree_sha256":source.tree_sha256,"original_layers_equal":matches,"untouched_layers_equal":[true,true],
			"no_game_sources":true,"conserved_splits":splitter.conserved_splits,"candidate":request.candidate,
			"faces_saved":candidate.faces_saved,"retained_channels_verified":true,"split_depth":depth}
		if request.has("partition_plan"): evidence["partition_plan"]=request.partition_plan
		proof.rows.append(evidence);new_rows.append(evidence);saved_faces+=int(candidate.faces_saved)
		print("[source massing] ",configuration," cell=",source.identity.cell," saved=",candidate.faces_saved)
	attachment.output=output.path_join("proof.json")
	attachment.erase("export_actual")
	attachment["source_massing_input_sha256"]=digest
	var input_binding := Save.save_json(output.path_join("attachments.json"),attachment)
	if input_binding.is_empty(): return 1
	proof.input_sha256=input_binding.sha256
	var proof_binding := Save.save_json(attachment.output,proof)
	if proof_binding.is_empty(): return 1
	package.native.partition_override={"input":input_binding,"proof":proof_binding}
	var verified := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not verified.read(package.native): return 1
	var cuts: Dictionary={}
	for configuration in ["lod4_full","lod5_full"]:
		cuts[configuration]=Attach.cuts(verified._partition_roots[configuration],poses.poses,"")
		for cut: Dictionary in cuts[configuration]:
			cut.erase("new_pages")
			if not cut.within_budget:
				print("[source massing] cost rejected ",cut);return 1
	var package_binding := Save.save_json(output.path_join("package.json"),package)
	if package_binding.is_empty(): return 1
	return 0 if not Save.save_json(output.path_join("report.json"),{"input_sha256":digest,"new_sources":new_rows,
		"faces_saved_across_lods":saved_faces,"cuts":cuts,"package":package_binding,"runtime_verified":false,
		"visual_accepted":false,"performance_accepted":false}).is_empty() else 1
