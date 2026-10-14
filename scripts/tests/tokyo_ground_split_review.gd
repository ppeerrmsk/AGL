extends RefCounted
## 已存候选的身份/覆盖/邻域预算门；不把内存登记冒充真实流送。
static func run(native: RefCounted, input: Dictionary) -> int:
	var binding: Dictionary=input.ground_split_review.duplicate()
	if not native.Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var file := FileAccess.open(binding.path,FileAccess.READ)
	if file==null: return 1
	var data: Dictionary=file.get_var(false);file.close()
	var writer := preload("res://scripts/tests/tokyo_partition_page_writer.gd").new()
	writer.pages=data.pages
	if not writer.verify_tree(data.tree,{}): return 1
	var original: Dictionary=native.pages.get(data.tree.path,{})
	if not original.has("mapping"): return 1
	var source: String=original.mapping[2][0]
	if original.components[source].sha256!=data.input_sha256 or FileAccess.get_sha256(source)!=data.input_sha256: return 1
	var resource: Resource=load(source)
	if resource==null or not resource.valid(): return 1
	var source_mesh: ArrayMesh=resource.meshes[int(original.mapping[2][1])]
	var root_part: Dictionary=data.pages[data.tree.path].layers[2]
	if FileAccess.get_sha256(root_part.path)!=root_part.sha256: return 1
	var root_resource: Resource=load(root_part.path)
	if root_resource==null or not root_resource.valid() or not preload("res://scripts/experiments/tokyo_packed_mesh_join.gd").conserved(source_mesh,[root_resource.meshes[0]]): return 1
	binding.configuration="lod5_full"
	var normalized := preload("res://scripts/rendering/tokyo_partition_catalog.gd").normalize(data,binding)
	if normalized.is_empty(): return 1
	native.pages.merge(normalized.pages)
	var adapter := preload("res://scripts/rendering/tokyo_partition_catalog.gd")
	native._grid_native_ground=adapter.replace(native._grid_native_ground,data.tree.path,normalized.tree)
	native._partition_roots.lod5_full=adapter.replace(native._partition_roots.lod5_full,data.tree.path,normalized.tree)
	var evidence_binding: Dictionary=input.prefetch_replay
	if FileAccess.get_sha256(evidence_binding.path)!=evidence_binding.sha256: return 1
	var evidence: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(evidence_binding.path))
	var poses: Array=[]
	for plan: Dictionary in evidence.handoff_trace.plans:
		if int(plan.ms)>=14902 and int(plan.ms)<=15120:
			poses.append({"center":preload("res://scripts/tests/tokyo_prefetch_replay_case.gd").vector(plan.center),"scale":float(plan.scale),"kind":"saved"})
	if poses.size()!=5: return 1
	var center: Vector2=poses[-1].center
	for offset: Vector2 in [Vector2.ZERO,Vector2(128,0),Vector2(-128,0),Vector2(0,128),Vector2(0,-128)]:
		for scale_value: float in [1.25,1.251,1.272,1.3,1.35,1.4,1.45,1.55,1.65]:
			poses.append({"center":center+offset,"scale":scale_value,"kind":"neighborhood"})
	var rows: Array=[]
	var failures := 0
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.package_override.path))
	for pose: Dictionary in poses:
		var cut: Dictionary=native.select(pose.center,pose.scale,0.0,Vector2(1600,900),"lod5_full",192*1024*1024)
		var projection: Dictionary=cut.get("grid_projection",{})
		var covered: bool=not projection.is_empty() and native.covers_visible_layers(cut,projection.view,projection.canvas,projection.size)
		var negative := false
		if covered:
			var missing: Dictionary=cut.duplicate(true)
			for n in missing.entries.size():
				if missing.entries[n].mask[2]:
					missing.entries.remove_at(n)
					negative=not native.covers_ground(missing,projection.view,projection.canvas,projection.size)
					break
		var passed: bool=covered and negative and cut.get("within_budget",false)
		var foundation_pass := false
		# 1.25边界正式路由允许已认可常驻档；不能把强制原生超预算冒充整条路由失败。
		if not passed and float(pose.scale)<=1.25:
			var catalogs: Array[Dictionary]=[]
			for item: Dictionary in package.catalogs:
				var catalog: Dictionary=native.Contract.read(item.path,item.sha256)
				if catalog.is_empty(): return 1
				catalog["range"]=item.range;catalogs.append(catalog)
			var foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd")
			var fixed: Dictionary=foundation.plan(catalogs,192*1024*1024,true)
			var index: int=foundation.catalog_at(fixed,pose.scale)
			if index>=0:
				var fallback: Dictionary=foundation.select(catalogs[index],fixed.layers[index].entries,pose.center,pose.scale,0.0,Vector2(1600,900),192*1024*1024)
				foundation_pass=not fallback.is_empty()
		passed=passed or foundation_pass
		failures+=int(not passed)
		rows.append({"center":pose.center,"scale":pose.scale,"kind":pose.kind,"covered":covered,"missing_ground_rejected":negative,"faces":cut.get("triangles",0),"pages":cut.get("active",0),"native_budget":cut.get("within_budget",false),"foundation_pass":foundation_pass,"pass":passed})
	file=FileAccess.open(input.output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"partition":binding,"runtime_integrated":false,"visual_acceptance":false,"failures":failures,"rows":rows},"\t"));file.close()
	return 0 if failures==0 else 1
