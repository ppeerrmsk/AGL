extends RefCounted
## 只读元数据复算实际选择器；不启动流送、不代表实际提交或帧时间。
static func run(input: Dictionary) -> int:
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	var package := preload("res://scripts/rendering/tokyo_partition_override.gd").json_binding(input.get("handoff_selection_probe"))
	var samples: Variant=input.get("samples")
	var expected: Variant=input.get("expected_components")
	if not input.get("capacity_audit",false) is bool: return 1
	if not input.get("resident_mixed_audit",false) is bool: return 1
	if not input.get("edge_refinement_audit",false) is bool: return 1
	if not input.get("profile_selection",false) is bool: return 1
	if package.is_empty() or not samples is Array or samples.is_empty() or samples.size()>32 \
		or not expected is Array or expected.size()>16:
		print("[handoff selection] invalid input or package binding")
		return 1
	for path: Variant in expected:
		if not path is String: return 1
	for sample: Variant in samples:
		if not sample is Dictionary or not contract.numbers(sample.get("center"),2) \
			or not contract.numbers(sample.get("velocity"),2) or not contract.numbers([sample.get("scale")],1) \
			or float(sample.scale)<=0.0: return 1
		if sample.has("size") and (not contract.numbers(sample.size,2) or float(sample.size[0])<=0.0 or float(sample.size[1])<=0.0): return 1
		if sample.has("resident_components"):
			for field: String in ["resident_components","resident_textures"]:
				var paths: Variant=sample.get(field,[])
				if not paths is Array or paths.size()>16384: return 1
				for path: Variant in paths:
					if not path is String or path.is_empty(): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.get("native",{})):
		print("[handoff selection] native metadata rejected")
		return 1
	var overlay := preload("res://scripts/rendering/tokyo_hlod_overlay.gd").new()
	overlay._native=native
	overlay.display_budget=192*1024*1024
	var results: Array=[]
	var capacities: Array=[]
	var resident_rows: Array=[]
	var mixed_rows: Array=[]
	var refinement_rows: Array=[]
	for sample: Dictionary in samples:
		var center := Vector2(sample.center[0],sample.center[1])
		var scale_value := float(sample.scale)
		var query_size := Vector2(float(sample.get("size",[1600,900])[0]),float(sample.get("size",[1600,900])[1]))
		if input.get("edge_refinement_audit",false):
			var refinement := edge_refinement_audit(native,center,scale_value)
			if refinement.is_empty():
				overlay.free()
				return 1
			refinement_rows.append(refinement)
		if sample.has("resident_components"):
			var meshes: Dictionary={}
			var textures: Dictionary={}
			for path: String in sample.resident_components: meshes[path]=true
			for path: String in sample.get("resident_textures",[]): textures[path]=true
			if input.get("resident_mixed_audit",false):
				var audit := mixed_audit(native,center,scale_value,meshes,textures)
				if audit.is_empty():
					overlay.free()
					return 1
				audit["source_ms"]=sample.get("source_ms",-1)
				mixed_rows.append(audit)
			var resident_cut: Dictionary=native.select(center,scale_value,0.0,Vector2(1600,900),"lod5_full",192*1024*1024,{"meshes":meshes,"textures":textures})
			resident_rows.append({"sample":sample,"within_budget":resident_cut.get("within_budget",false),
				"faces":resident_cut.get("triangles",0),"bytes":resident_cut.get("bytes",0),"active":resident_cut.get("active",0),
				"keys":resident_cut.get("keys",[]),"masks":resident_cut.get("masks",[]),"ground_images":resident_cut.get("ground_images",[]),
				"qualification":overlay.Handoff.native_qualified(resident_cut,scale_value),"runtime_committed":false})
		if input.get("capacity_audit",false):
			var capacity := capacity_audit(native,center,scale_value)
			if capacity.is_empty():
				overlay.free()
				return 1
			capacities.append(capacity)
		overlay._pan_velocity=Vector2(sample.velocity[0],sample.velocity[1])
		var future := center+overlay.Handoff.pan_lead(overlay._pan_velocity,scale_value,0.25,Vector2(1600,900))
		for query: String in ["current_guarded","future_guarded","current_bare"]:
			var future_view := query=="future_guarded"
			for budget in [48*1024*1024,192*1024*1024]:
				var profile: bool=input.get("profile_selection",false)
				var previous_enabled: bool=PerfBuckets.enabled
				var previous_trace: bool=PerfBuckets.frame_trace_enabled
				if profile:
					native._selection_solutions.clear()
					PerfBuckets.enabled=true;PerfBuckets.frame_trace_enabled=true
				var before: Dictionary=PerfBuckets._trace_frame_us.duplicate() if profile else {}
				var builds: int=native.solver_builds
				var started := Time.get_ticks_usec()
				# 裸查询不能先暗跑一次扩区查询；每条记录只度量自身入口。
				var cut: Dictionary=native.select(center,scale_value,0.0,query_size,"lod5_full",budget) if query=="current_bare" else overlay._select_native(future if future_view else center,scale_value,0.0,query_size,"lod5_full",budget,false)
				var elapsed := Time.get_ticks_usec()-started
				var buckets: Dictionary={}
				if profile:
					for key: String in PerfBuckets._trace_frame_us:
						var delta: int=int(PerfBuckets._trace_frame_us[key])-int(before.get(key,0))
						if delta>0: buckets[key]=delta
					PerfBuckets.enabled=previous_enabled;PerfBuckets.frame_trace_enabled=previous_trace
				var parts: Dictionary={}
				for key: String in cut.get("keys",PackedStringArray()): parts.merge(native.pages[key].components)
				var hits: Array=[]
				for path: String in expected:
					if parts.has(path): hits.append(path)
				results.append({"sample":sample,"query":query,"future":future_view,"budget":budget,"within_budget":cut.get("within_budget",false),
					"faces":cut.get("triangles",0),"bytes":cut.get("bytes",0),"guard":cut.get("spatial_guard_px",0),"hits":hits,
					"ground_images":cut.get("ground_images",PackedStringArray()),"profile_selection":profile,"cold_query":profile,
					"selection_wall_usec":elapsed,"solver_builds":native.solver_builds-builds,"profile_us":buckets})
	overlay.free()
	var output: String=input.get("output","")
	return 1 if preload("res://scripts/tests/build_tokyo_lossless_leaf_partitions.gd").save_json(output,
		{"diagnostic_only":true,"retention_disabled":true,"empty_committed_state":true,"rows":results,"capacities":capacities,"resident_rows":resident_rows,"mixed_rows":mixed_rows,"refinement_rows":refinement_rows}).is_empty() else 0


static func edge_refinement_audit(native: RefCounted, center: Vector2, scale_value: float) -> Dictionary:
	# 仅试算未替换且无正式楼来源的叶；旧替换及旧地表绑定完整保留，不写资源。
	var refinement_type := preload("res://scripts/tests/tokyo_native_refinement_probe.gd")
	var production := preload("res://scripts/tests/build_tokyo_lossless_leaf_partitions.gd")
	var ground_type := preload("res://scripts/rendering/tokyo_native_ground.gd")
	var projection := preload("res://scripts/experiments/volume_projection.gd")
	var configuration := "lod5_full"
	if not native._partition_roots.has(configuration) or not native._ground_roots.has(configuration): return {}
	var original: Array=native._partition_roots[configuration]
	var original_ground: Array=native._ground_roots[configuration]
	var before := hash([original,original_ground])
	var size := Vector2(1600,900)
	var canvas := Transform2D.IDENTITY.scaled(Vector2.ONE*scale_value)
	canvas.origin=size*.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,inverse*size-inverse*Vector2.ZERO)
	var ray := projection.ground_basis(canvas,deg_to_rad(38)).inverse()*projection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	var results: Array=[]
	for depth in [0,1,2,3,4]:
		var probe := refinement_type.new()
		probe.branching=2
		probe.current_roots=true
		probe.eligible_leaf=production.refinable.bind(native,configuration)
		var roots: Array[Dictionary]=[]
		var ground_roots: Array[Dictionary]=[]
		for entry: Dictionary in original:
			roots.append(probe._refine(entry,native,view,canvas,size,roof,depth) if depth>0 else entry)
		if probe.failed: return {}
		for entry: Dictionary in roots:
			var adapted: Dictionary=ground_type.tree(entry,native.ground.rows)
			if adapted.is_empty(): return {}
			ground_roots.append(adapted)
		native._partition_roots[configuration]=roots
		native._ground_roots[configuration]=ground_roots
		native._selection_solutions.clear()
		var cut: Dictionary=native.select(center,scale_value,0.0,size,configuration,192*1024*1024)
		var coverage: bool=native.covers_visible_layers(cut,view,canvas,size)
		native._partition_roots[configuration]=original
		native._ground_roots[configuration]=original_ground
		native._selection_solutions.clear()
		var targets: Array=[]
		for refined: Dictionary in probe._cache.values(): targets.append(refined.path)
		var optimistic_roots: Array[Dictionary]=[]
		for entry: Dictionary in ground_roots: optimistic_roots.append(_optimistic_new_ground(entry,targets))
		var lower_bound := preload("res://scripts/experiments/tokyo_spatial_cut.gd").choose(optimistic_roots,view,canvas,size,roof,Vector2.ZERO,16,192*1024*1024)
		var all_ground_roots: Array[Dictionary]=[]
		for entry: Dictionary in ground_roots: all_ground_roots.append(_optimistic_new_ground(entry,targets,true))
		var all_ground_bound := preload("res://scripts/experiments/tokyo_spatial_cut.gd").choose(all_ground_roots,view,canvas,size,roof,Vector2.ZERO,16,192*1024*1024)
		var all_ground_keys: Array=[]
		for entry: Dictionary in all_ground_bound.entries: all_ground_keys.append({"key":entry.path,"mask":entry.mask})
		var guard_bounds: Array=[]
		for guard in [48,96,192]:
			var guarded_canvas := canvas
			guarded_canvas.origin+=Vector2.ONE*guard
			var guarded := preload("res://scripts/experiments/tokyo_spatial_cut.gd").choose(all_ground_roots,view.grow(float(guard)/scale_value),guarded_canvas,size+Vector2.ONE*guard*2,roof,Vector2.ZERO,16,192*1024*1024)
			guard_bounds.append({"guard_px":guard,"faces":guarded.triangles,"pages":guarded.active})
		var layers := [0,0,0]
		var new_ground := 0
		var new_ground_pages := 0
		var page_costs: Array=[]
		for entry: Dictionary in cut.entries:
			for kind in 3:
				if entry.mask[kind]: layers[kind]+=int(entry.triangles[kind])
			var refined_child := false
			for target: String in targets:
				if entry.path.begins_with(target+"/probe_"): refined_child=true
			if refined_child and entry.mask[2]:
				new_ground+=int(entry.triangles[2]);new_ground_pages+=1
			page_costs.append({"key":entry.path,"mask":entry.mask,"triangles":entry.triangles,"refined_child":refined_child})
		results.append({"depth":depth,"faces":cut.triangles,"bytes":cut.bytes,"pages":cut.active,
			"within_budget":cut.within_budget,"coverage":coverage,"refined_targets":targets,
			"conserved_splits":probe.conserved_splits,"keys":cut.keys,"ground_images":cut.ground_images,
			"layer_faces":layers,"page_costs":page_costs,"new_ground_faces":new_ground,
			"new_ground_reselected_face_lower_bound":lower_bound.triangles,
			"all_ground_reselected_face_lower_bound":all_ground_bound.triangles,"all_ground_lower_bound_keys":all_ground_keys,
			"all_ground_guard_bounds":guard_bounds,
			"lower_bound_pages":lower_bound.active,"lower_bound_ignores_all_bytes":true,
			"ideal_new_ground_faces":int(cut.triangles)-new_ground+new_ground_pages*2})
	if before!=hash([native._partition_roots[configuration],native._ground_roots[configuration]]): return {}
	return {"center":[center.x,center.y],"scale":scale_value,"rows":results,"source_unchanged":true,
		"candidate_children_have_no_baked_ground":true,"runtime_integrated":false}


static func _optimistic_new_ground(entry: Dictionary, targets: Array, all_ground: bool=false) -> Dictionary:
	# 仅数学下界：完整重选、保留包络及非地表几何，全部字节成本放宽为零。
	# 不生成虚假纹理、不交给native.select，不把下界可行当作生产可行。
	var result := entry.duplicate()
	result["bytes"]=0
	var triangles: Variant=entry.triangles.duplicate()
	if all_ground: triangles[2]=mini(int(triangles[2]),2)
	for target: String in targets:
		if str(entry.path).begins_with(target+"/probe_"):
			triangles[2]=mini(int(triangles[2]),2)
	result["triangles"]=triangles
	var children: Array[Dictionary]=[]
	for child: Dictionary in entry.get("children",[]): children.append(_optimistic_new_ground(child,targets,all_ground))
	result["children"]=children
	return result


static func mixed_audit(native: RefCounted, center: Vector2, scale_value: float, meshes: Dictionary, textures: Dictionary) -> Dictionary:
	# 仅离线诊断：每个完整节点的两种表示和全部孩子组合都参与同一支配筛选。
	var solver := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
	var cached := preload("res://scripts/rendering/tokyo_hlod_cached_cut.gd")
	var projection := preload("res://scripts/experiments/volume_projection.gd")
	if not native._ground_roots.has("lod5_full") or scale_value>float(native.ground.limits.lod5_full): return {}
	var source_hash := hash([native._partition_roots,native._ground_roots])
	var size := Vector2(1600,900)
	var canvas := Transform2D.IDENTITY.scaled(Vector2.ONE*scale_value)
	canvas.origin=size*.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,inverse*size-inverse*Vector2.ZERO)
	var ray := projection.ground_basis(canvas,deg_to_rad(38)).inverse()*projection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	var context := {"view":view,"canvas":canvas,"size":size,"logical":size,"roof":roof,"shadow":Vector2.ZERO,
		"geometry":native.pages,"meshes":meshes,"textures":textures,"cap":16}
	var raw: Array[Dictionary]=[]
	var hybrid: Array[Dictionary]=[]
	for entry: Dictionary in native._partition_roots.get("lod5_full",native.catalog.configurations.lod5_full): raw.append(cached.native_tree(entry,context))
	for entry: Dictionary in native._ground_roots.lod5_full: hybrid.append(cached.native_tree(entry,context))
	if raw.size()!=hybrid.size(): return {}
	var rows: Array=[]
	for mode: String in ["raw","hybrid","mixed"]:
		var frontier: Array[Dictionary]=[{"entries":[],"active":0,"faces":0,"bytes":0}]
		for index in raw.size(): frontier=solver._combine(frontier,_mixed_frontier(raw[index],hybrid[index],context,mode),16)
		if frontier.is_empty(): return {}
		if mode!="mixed":
			var baseline: Dictionary=solver.solve(raw if mode=="raw" else hybrid,view,canvas,size,roof,Vector2.ZERO,16,false)
			if frontier!=baseline.frontier: return {}
		var cut: Dictionary=solver.pick({"frontier":frontier,"visited":0,"solver_usec":0},192*1024*1024)
		cut=native.decorate(cut,"lod5_full",mode!="raw")
		rows.append({"mode":mode,"faces":cut.triangles,"bytes":cut.bytes,"pages":cut.active,"within_budget":cut.within_budget,
			"keys":cut.keys,"masks":cut.masks,"ground_images":cut.ground_images,
			"coverage":native.covers_visible_layers(cut,view,canvas,size),"frontier_states":frontier.size()})
	if source_hash!=hash([native._partition_roots,native._ground_roots]): return {}
	return {"rows":rows,"baseline_frontiers_exact":true,"source_unchanged":true,"runtime_integrated":false}


static func _mixed_frontier(raw: Dictionary, hybrid: Dictionary, context: Dictionary, mode: String) -> Array[Dictionary]:
	var solver := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
	var select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
	assert(raw.path==hybrid.path and raw.get("children",[]).size()==hybrid.get("children",[]).size())
	var result: Array[Dictionary]=[]
	var options: Array=[raw] if mode=="raw" else ([hybrid] if mode=="hybrid" else [raw,hybrid])
	for entry: Dictionary in options:
		var visible: Dictionary=select.visible(entry,context.view,context.canvas,context.logical,context.roof,context.shadow)
		if visible.faces==0: return [{"entries":[],"active":0,"faces":0,"bytes":0}]
		solver._insert(result,{"entries":[visible],"active":1,"faces":visible.faces,"bytes":visible.bytes})
	if not raw.get("children",[]).is_empty():
		var split: Array[Dictionary]=[{"entries":[],"active":0,"faces":0,"bytes":0}]
		for index in raw.children.size(): split=solver._combine(split,_mixed_frontier(raw.children[index],hybrid.children[index],context,mode),16)
		for state: Dictionary in split: solver._insert(result,state)
	return result


static func capacity_audit(native: RefCounted, center: Vector2, scale_value: float) -> Dictionary:
	# 仅复用当前实际树作容量反事实，不细分/加载网格、不修改正式16页门。
	var projection := preload("res://scripts/experiments/volume_projection.gd")
	var solver := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
	var size := Vector2(1600,900)
	var canvas := Transform2D.IDENTITY.scaled(Vector2.ONE*scale_value)
	canvas.origin=size*.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,inverse*size-inverse*Vector2.ZERO)
	var ray := projection.ground_basis(canvas,deg_to_rad(38)).inverse()*projection.camera_basis(canvas,deg_to_rad(38)).z
	var hybrid: bool=native._ground_roots.has("lod5_full") and scale_value<=float(native.ground.limits.lod5_full)
	var roots: Array=native._ground_roots.lod5_full if hybrid else native._partition_roots.get("lod5_full",native.catalog.configurations.lod5_full)
	var baseline: Dictionary=native.select(center,scale_value,0.0,size,"lod5_full",192*1024*1024)
	var rows: Array=[]
	for cap in [16,24,32]:
		var context := {"view":view,"canvas":canvas,"logical":size,"roof":-Vector2(ray.x,ray.z)/ray.y,"shadow":Vector2.ZERO,"cap":cap,"visited":0}
		var frontier: Array[Dictionary]=[{"entries":[],"active":0,"faces":0,"bytes":0}]
		for entry: Dictionary in roots: frontier=solver._combine(frontier,solver._frontier(entry,context),cap)
		if frontier.is_empty(): return {}
		var cut := solver.pick({"frontier":frontier,"visited":context.visited,"solver_usec":0},192*1024*1024)
		var keys: Array=[]
		var masks: Array=[]
		var layers := [0,0,0]
		var page_costs: Array=[]
		for entry: Dictionary in cut.entries:
			keys.append(entry.path);masks.append(entry.mask)
			var page_layers := [0,0,0]
			for kind in 3:
				if entry.mask[kind]:
					page_layers[kind]=int(entry.triangles[kind])
					layers[kind]+=page_layers[kind]
			page_costs.append({"key":entry.path,"mask":entry.mask,"layer_faces":page_layers,
				"identity":native.pages[entry.path].get("canonical_identity",{}),
				"has_ground_replacement":entry.has("ground_replacement")})
		if cap==native.Contract.native_page_limit():
			if cut.triangles!=baseline.triangles or cut.bytes!=baseline.bytes or cut.active!=baseline.active \
				or PackedStringArray(keys)!=baseline.keys or masks!=baseline.masks: return {}
		rows.append({"cap":cap,"active":cut.active,"faces":cut.triangles,"bytes":cut.bytes,"layer_faces":layers,
			"cost_within_budget":cut.within_budget,"formal_page_gate":int(cut.active)<=16,"keys":keys,"page_costs":page_costs})
	return {"center":[center.x,center.y],"scale":scale_value,"hybrid":hybrid,"baseline_exact":true,"baseline_cap":native.Contract.native_page_limit(),"rows":rows,"runtime_integrated":false}
