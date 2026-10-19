extends RefCounted
## 保存姿态的真实同步预测器重放；不伪造缓存、显示提交或Visual资格。

static func run(native: RefCounted, package: Dictionary, input: Dictionary) -> int:
	var binding: Dictionary=input.prefetch_replay
	if not native.Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var evidence: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var overlay := preload("res://scripts/rendering/tokyo_hlod_overlay.gd").new()
	overlay._native=native;overlay._geometry=native.pages;overlay.display_budget=192*1024*1024
	for item: Dictionary in package.catalogs:
		var catalog: Dictionary=native.Contract.read(item.path,item.sha256)
		if catalog.is_empty(): overlay.free();return 1
		catalog["range"]=item.range
		if item.has("prefer_native_above"): catalog["prefer_native_above"]=item.prefer_native_above
		overlay._catalogs.append(catalog)
	overlay._foundation=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").plan(overlay._catalogs,overlay.display_budget,true)
	if input.get("handoff_feasibility",false):
		var rows: Array=[]
		for plan: Dictionary in evidence.handoff_trace.plans:
			if int(plan.ms)<14902 or int(plan.ms)>15120: continue
			var scale_value := float(plan.scale)
			var cut: Dictionary=native.select(vector(plan.center),scale_value,0.0,Vector2(1600,900),native.ground_configuration(scale_value),overlay.display_budget)
			var foundations: Array=[]
			for index: int in overlay._foundation.get("layers",{}):
				var layer: Dictionary=overlay._foundation.layers[index]
				var fixed: Dictionary=preload("res://scripts/rendering/tokyo_hlod_foundation.gd").select(overlay._catalogs[index],layer.entries,vector(plan.center),scale_value,0.0,Vector2(1600,900),overlay.display_budget)
				if not fixed.is_empty(): foundations.append(index)
			rows.append({"ms":plan.ms,"scale":scale_value,"native_exists":not cut.is_empty(),"native_within_budget":cut.get("within_budget",false),"native_pages":cut.get("active",0),"native_faces":cut.get("triangles",0),"native_bytes":cut.get("bytes",0),"foundation_options":foundations})
			var layer_faces: Array[int]=[0,0,0]
			var costs: Array=[]
			for entry: Dictionary in cut.get("entries",[]):
				var visible_faces: Array[int]=[0,0,0]
				for kind in 3:
					if entry.mask[kind]: visible_faces[kind]=int(entry.triangles[kind])
					if kind<2 and entry.has("piece_indices"):
						visible_faces[kind]=0
						for n: int in entry.piece_indices[kind]: visible_faces[kind]+=int(native.pages[entry.path].views[kind][n].faces)
					layer_faces[kind]+=visible_faces[kind]
				if visible_faces[0]+visible_faces[1]+visible_faces[2]!=int(entry.faces): overlay.free();return 1
				costs.append({"path":entry.path,"layers":visible_faces,"faces":entry.faces,"bytes":entry.bytes})
			rows[-1]["layer_faces"]=layer_faces
			rows[-1]["entry_costs"]=costs
			if layer_faces[0]+layer_faces[1]+layer_faces[2]!=int(cut.get("triangles",0)): overlay.free();return 1
		var output := FileAccess.open(input.output,FileAccess.WRITE)
		if output==null: overlay.free();return 1
		output.store_string(JSON.stringify({"diagnostic_only":true,"runtime_acceptance":false,"page_limit":native.Contract.native_page_limit(),"display_budget":overlay.display_budget,"rows":rows},"\t"));output.close()
		overlay.free()
		return 0 if rows.size()==5 else 1
	var target: Dictionary={}
	for snapshot: Dictionary in evidence.wasd.snapshots:
		if int(snapshot.ms)==15120: target=snapshot
	if target.is_empty(): overlay.free();return 1
	var rows: Array=[]
	var nodes: Dictionary={}
	var stack: Array=[]
	for roots: Array in native._partition_roots.values(): stack.append_array(roots)
	while not stack.is_empty():
		var node: Dictionary=stack.pop_back()
		nodes[node.path]=node
		stack.append_array(node.get("children",[]))
	for plan: Dictionary in evidence.handoff_trace.plans:
		if int(plan.ms)<14902 or int(plan.ms)>15120: continue
		overlay._pan_velocity=vector(plan.pan);overlay._zoom_rate=float(plan.zoom_rate)
		var started := Time.get_ticks_usec()
		var predicted: Dictionary=overlay._predict_prefetch(vector(plan.center),float(plan.scale),0.0,Vector2(1600,900))
		var physical: Dictionary={}
		for key: String in predicted.get("keys",[]):
			if not native.pages.has(key): overlay.free();return 1
			physical.merge(native.pages[key].components)
		var missing: Array=[]
		var bytes := 0
		for part: Dictionary in physical.values(): bytes+=int(part.bytes)
		for part: Dictionary in target.target_status.missing_meshes:
			if not physical.has(part.path): missing.append(part.path)
		rows.append({"ms":plan.ms,"scale":plan.scale,"predict_usec":Time.get_ticks_usec()-started,"catalog":predicted.get("catalog",-99),"logical_pages":predicted.get("keys",[]).size(),"physical_count":physical.size(),"physical_bytes":bytes,"missing_target_components":missing,"keys":predicted.get("keys",[])})
		var expanded := physical.duplicate()
		var frontier: Array=[]
		for key: String in predicted.get("keys",[]):
			if nodes.has(key): frontier.append(nodes[key])
		var expansion: Array=[]
		for depth in [1,2]:
			var next: Array=[]
			for node: Dictionary in frontier:
				for child: Dictionary in node.get("children",[]):
					next.append(child)
					if native.pages.has(child.path): expanded.merge(native.pages[child.path].components)
			frontier=next
			var expanded_bytes := 0
			for part: Dictionary in expanded.values(): expanded_bytes+=int(part.bytes)
			var still_missing: Array=[]
			for part: Dictionary in target.target_status.missing_meshes:
				if not expanded.has(part.path): still_missing.append(part.path)
			expansion.append({"depth":depth,"bytes":expanded_bytes,"extra_bytes":expanded_bytes-bytes,"missing":still_missing})
		rows[-1]["bounded_descendants"]=expansion
		# 不读取后续真实姿态来生成候选；固定四个前瞻点只使用当前速度与缩放率。
		var swept := physical.duplicate()
		var samples: Array=[]
		for horizon: float in [0.05,0.10,0.15,0.20]:
			var future_scale := clampf(float(plan.scale)*exp(clampf(float(plan.zoom_rate)*horizon,-0.7,0.7)),0.0973,5.0)
			var future_center: Vector2=vector(plan.center)+overlay.Handoff.pan_lead(vector(plan.pan),future_scale,horizon,Vector2(1600,900))
			var configuration: String=native.ground_configuration(future_scale)
			var cut: Dictionary=native.select(future_center,future_scale,0.0,Vector2(1600,900),configuration,192*1024*1024)
			if cut.get("within_budget",false):
				for key: String in cut.get("keys",[]): swept.merge(native.pages[key].components)
			var sample_missing: Array=[]
			for part: Dictionary in target.target_status.missing_meshes:
				if not swept.has(part.path): sample_missing.append(part.path)
			var swept_bytes := 0
			for part: Dictionary in swept.values(): swept_bytes+=int(part.bytes)
			samples.append({"horizon":horizon,"within_budget":cut.get("within_budget",false),"bytes":swept_bytes,"extra_bytes":swept_bytes-bytes,"missing":sample_missing})
		rows[-1]["bounded_future_cuts"]=samples
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null: overlay.free();return 1
	file.store_string(JSON.stringify({"diagnostic_only":true,"resident_state_replayed":false,"runtime_acceptance":false,"rows":rows},"\t"));file.close()
	overlay.free()
	return 0 if rows.size()==5 else 1


static func vector(value: String) -> Vector2:
	var parts := value.trim_prefix("(").trim_suffix(")").split(",")
	return Vector2(float(parts[0]),float(parts[1]))
