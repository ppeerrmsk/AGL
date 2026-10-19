extends RefCounted
const Native := preload("res://scripts/rendering/tokyo_grid_native.gd")
const Stream := preload("res://scripts/rendering/tokyo_hlod_stream.gd")


static func run(parent: Node, input: Dictionary) -> int:
	if input.has("audit_poses_binding"):
		var binding: Dictionary = input.audit_poses_binding
		if not Native.Contract.binding(binding) or FileAccess.get_sha256(binding.path) != binding.sha256: return 1
		var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(binding.path))
		if not request is Dictionary or not request.get("audit_poses") is Array: return 1
		request.merge(input,true);request.erase("audit_poses_binding")
		return await run(parent,request)
	if input.has("cases"):
		for sample: Dictionary in input.cases:
			var request := input.duplicate();request.erase("cases");request.merge(sample,true)
			if await run(parent,request)!=0: return 1
		return 0
	var output: String=input.get("output","")
	if not output.is_absolute_path() or FileAccess.file_exists(output): return 1
	var dependencies: Variant=Native.read_bound(input.grid_native)
	if not dependencies is Dictionary: return 1
	var snapshot: Variant=Native.read_bound(dependencies.snapshot)
	if not snapshot is Dictionary or FileAccess.get_sha256(snapshot.package.path)!=snapshot.package.sha256: return 1
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(snapshot.package.path))
	var package_binding: Dictionary=snapshot.package
	if input.has("package_override"):
		package_binding=input.package_override
		if not Native.Contract.binding(package_binding) or FileAccess.get_sha256(package_binding.path)!=package_binding.sha256: return 1
		var override: Variant=JSON.parse_string(FileAccess.get_file_as_string(package_binding.path))
		if not override is Dictionary or not override.get("native") is Dictionary or override.native.get("grid_candidate")!=input.grid_native: return 1
		package=override
	package.native["grid_candidate"]=input.grid_native
	if input.has("grid_detail"): package.native["grid_detail"]=input.grid_detail
	if input.has("simplified_ground_binding"): package.native["simplified_ground_candidate"]=input.simplified_ground_binding
	var native := Native.new()
	if not native.read(package.native): return 1
	if input.has("source_trace_rect"):
		var r: Array=input.source_trace_rect
		var area := Rect2(r[0],r[1],r[2],r[3])
		var stack: Array=snapshot.configurations.lod5_full.roots.duplicate()
		var rows: Array=[]
		while not stack.is_empty():
			var entry: Dictionary=stack.pop_back()
			var box: AABB=entry.boxes[0]
			if not area.intersects(Rect2(box.position.x,box.position.z,box.size.x,box.size.z),true): continue
			if not entry.get("children",[]).is_empty():
				stack.append_array(entry.children)
				continue
			rows.append({"source":entry.path,"faces":Array(entry.triangles),"page":snapshot.pages[entry.path]})
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file==null: return 1
		file.store_string(JSON.stringify({"snapshot":dependencies.snapshot,"rows":rows},"\t"));file.close()
		return 0
	if input.has("block_source_match"):
		return preload("res://scripts/tests/tokyo_block_source_match.gd").run(native,input)
	if input.has("roof_detail_candidate") or input.has("block_source_candidate"):
		var block_mode := input.has("block_source_candidate")
		var binding: Dictionary=input.block_source_candidate if block_mode else input.roof_detail_candidate
		if not Native.Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
		var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
		if source.buildings.is_empty(): return 1
		var rows: Array=[]
		for detail in [0,1]:
			var builder := preload("res://scripts/experiments/volume_mesh_factory.gd").new()
			var records: Array=source.buildings
			if block_mode and detail==1:
				records=[]
				for group: Dictionary in source.groups:
					records.append({"height_m":group.height_m,"height_source":"fallback","kind":group.kind,"rings":[{"outer":group.outer,"holes":[],"triangles":group.triangles}]})
			for raw: Dictionary in records:
				preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")._add_ring_building(builder,raw,float(raw.height_m)*0.5,1 if block_mode else detail)
			var mesh: ArrayMesh=builder.mesh()
			var path := output+"."+str(detail)+".res"
			if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
			var copy: ArrayMesh=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
			if copy==null or packed.corner_digest(copy)!=packed.corner_digest(mesh): return 1
			rows.append({"detail":detail,"path":path,"sha256":FileAccess.get_sha256(path),"faces":preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(copy),"bytes":packed.decoded_bytes(copy),"roundtrip_exact":true})
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file==null: return 1
		file.store_string(JSON.stringify({"source":binding,"buildings":source.buildings.size(),"variants":rows,"visual_verified":false,"runtime_integrated":false},"\t"));file.close()
		return 0
	if input.has("component_attribute_export"):
		# 仅离线样件；摘要绑定现有组件，不接入正式显示资格。
		var binding: Dictionary=input.component_attribute_export
		if not Native.Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
		var component: Resource=ResourceLoader.load(binding.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var slot := int(input.get("component_slot",0))
		if component==null or not component.valid() or slot<0 or slot>=component.meshes.size(): return 1
		if not input.has("component_slot") and component.meshes.size()!=1: return 1
		return preload("res://scripts/tests/tokyo_residential_preview.gd").export_attributes(component.meshes[slot],output)
	if input.has("simplified_ground_checks"):
		if not preload("res://scripts/tests/build_tokyo_simplified_ground.gd").rejection_checks(native,input.simplified_ground_checks): return 1
	if input.has("simplified_ground_cost"):
		if not input.get("feasibility_only",false): return 1
		if not preload("res://scripts/tests/build_tokyo_simplified_ground.gd").install_cost_candidate(native,input.simplified_ground_cost): return 1
	if input.has("ground_split_review"):
		return preload("res://scripts/tests/tokyo_ground_split_review.gd").run(native,input)
	if input.has("ground_split_candidate"):
		return preload("res://scripts/tests/tokyo_ground_split_candidate.gd").run(native,package,input)
	if input.has("ground_duplicate_candidate"):
		return preload("res://scripts/tests/tokyo_ground_duplicate_candidate.gd").run(native,input)
	if input.has("prefetch_replay"):
		return preload("res://scripts/tests/tokyo_prefetch_replay_case.gd").run(native,package,input)
	if input.has("residency_gap_audit"):
		return preload("res://scripts/tests/tokyo_residency_gap_audit.gd").run(native,package,input)
	if input.get("spatial_group_audit",false):
		return preload("res://scripts/tests/tokyo_spatial_group_audit.gd").run(native,input)
	if input.get("mesh_share_audit",false):
		return preload("res://scripts/tests/tokyo_shared_mesh_audit.gd").run(native,input)
	if input.has("shared_lod_point"):
		return preload("res://scripts/tests/build_tokyo_shared_lod.gd").run(native,input)
	if input.has("shared_lod_cells"):
		return preload("res://scripts/tests/tokyo_shared_lod_cells.gd").run(input)
	if input.get("feasibility_only",false):
		if input.has("resident_basis"):
			if input.resident_basis not in ["roots","leaves"]: return 1
			native._resident_fine_basis=true
			var basis: Array[Dictionary]=[]
			var stack: Array=native._grid_native_ground.duplicate()
			while not stack.is_empty():
				var node: Dictionary=stack.pop_back()
				if input.resident_basis=="leaves" and not node.get("children",[]).is_empty():
					stack.append_array(node.children);continue
				var flat: Dictionary=node.duplicate();flat.erase("children");basis.append(flat)
			native._grid_native_ground=basis
		# 只调用真实选择/覆盖合同；不加载资源，不授予连续显示或性能资格。
		if input.get("use_native_ground",false):
			# 仅诊断现成原生地表，复用超过烘焙尺度时已有的选择分支。
			native.ground=native.ground.duplicate(true)
			native.ground.limits.lod5_full=0.0
		var catalogs: Array[Dictionary]=[]
		for binding: Dictionary in package.catalogs:
			var catalog := Native.Contract.read(binding.path,binding.sha256)
			if catalog.is_empty(): return 1
			catalogs.append(catalog)
		var foundation_api = preload("res://scripts/rendering/tokyo_hlod_foundation.gd")
		var handoff = preload("res://scripts/rendering/tokyo_hlod_handoff.gd")
		var foundation: Dictionary=foundation_api.plan(catalogs,192*1024*1024,not input.has("resident_basis"))
		var owner := Node.new();parent.add_child(owner)
		var stream := Stream.new();parent.add_child(stream)
		if not stream.configure_hlod(owner,native.pages,native.ground.textures): return 1
		native.subset_stream=weakref(stream);native.subset_geometry=native.pages
		var results: Array=[]
		for pose: Array in input.audit_poses:
			var center := Vector2(pose[0],pose[1])
			var scale_value := float(pose[2])
			var size := Vector2(1600,900)
			var canvas := Transform2D(0.0,Vector2.ZERO).scaled(Vector2.ONE*scale_value)
			canvas.origin=size*0.5-canvas*center
			var view := Rect2(canvas.affine_inverse()*Vector2.ZERO,size/scale_value)
			var index: int=foundation_api.catalog_at(foundation,scale_value)
			var base: Dictionary={} if index<0 else foundation_api.select(catalogs[index],foundation.layers[index].entries,center,scale_value,0.0,size,192*1024*1024)
			var row := {"pose":pose,"foundation_catalog":index,"foundation_pass":not base.is_empty(),"native":[]}
			var saved_ground: Array[Dictionary]=native._grid_ground.duplicate()
			var original_ground: Array[Dictionary]=saved_ground.duplicate()
			var original_native_ground: Array[Dictionary]=native._grid_native_ground.duplicate()
			# 只展开现有守恒子树，不制作资源；根级仅一块时不能冒称已检查分区组合。
			for depth in int(input.get("ground_mix_depth",0)):
				var next_ground: Array[Dictionary]=[]
				var next_native: Array[Dictionary]=[]
				for root: Dictionary in saved_ground:
					if root.get("children",[]).is_empty(): next_ground.append(root)
					else: next_ground.append_array(root.children)
				for root: Dictionary in native._grid_native_ground:
					if root.get("children",[]).is_empty(): next_native.append(root)
					else: next_native.append_array(root.children)
				saved_ground=next_ground;native._grid_native_ground=next_native
			var visible_roots: Array[int]=[]
			var requests: Array=[{"configuration":""},{"configuration":"lod4_full"},{"configuration":"lod5_full"}]
			if input.has("resident_basis"): requests=[{"configuration":"lod5_full"}]
			if input.get("ground_mix",false):
				var projection = preload("res://scripts/experiments/volume_projection.gd")
				var ray: Vector3=projection.ground_basis(canvas,deg_to_rad(38)).inverse()*projection.camera_basis(canvas,deg_to_rad(38)).z
				for n in saved_ground.size():
					if native.Select.visible(saved_ground[n],view,canvas,size,-Vector2(ray.x,ray.z)/ray.y,Vector2.ZERO).faces>0: visible_roots.append(n)
				if visible_roots.size()>6: return 1
				requests=[]
				for mask_value in 1<<visible_roots.size(): requests.append({"configuration":"lod5_full","ground_mask":mask_value})
				row["mixed_roots"]=[]
				for n: int in visible_roots: row.mixed_roots.append(saved_ground[n].path)
			for request: Dictionary in requests:
				var configuration: String=request.configuration
				native._grid_ground=saved_ground.duplicate()
				if request.has("ground_mask"):
					for bit in visible_roots.size():
						if not int(request.ground_mask)&(1<<bit): continue
						var n: int=visible_roots[bit]
						var matched := false
						for original: Dictionary in native._grid_native_ground:
							if original.path==saved_ground[n].path:
								native._grid_ground[n]=original;matched=true;break
						if not matched: return 1
				var cut := native.select(center,scale_value,0.0,size,configuration,192*1024*1024)
				var qualified: bool=handoff.native_qualified(cut,scale_value)
				var covered: bool=not cut.is_empty() and native.covers_visible_layers(cut,view,canvas,size)
				var costs := {"grid_bytes":0,"ground_bytes":0,"grid_faces":0,"ground_faces":0,"entries":[]}
				if input.get("cost_breakdown",false):
					for entry: Dictionary in cut.get("entries",[]):
						var grid: bool=native._grid_entries.has(entry.path) or native._grid_variants.has(entry.path)
						costs["grid_bytes" if grid else "ground_bytes"]+=int(entry.get("bytes",0))
						costs["grid_faces" if grid else "ground_faces"]+=int(entry.get("faces",0))
						costs.entries.append({"path":entry.path,"bytes":entry.get("bytes",0),"faces":entry.get("faces",0),"grid":grid})
						if not grid and input.get("ground_sources",false):
							var source_page: Dictionary=native.pages.get(entry.path,{})
							costs.entries[-1]["components"]=source_page.get("components",{})
							costs.entries[-1]["mapping"]=source_page.get("mapping",[])
							costs.entries[-1]["mask"]=Array(entry.mask)
							costs.entries[-1]["surfaces"]=preload("res://scripts/rendering/tokyo_native_ground.gd").surfaces(entry)
				row.native.append({"request":configuration,"configuration":cut.get("configuration",""),"empty":cut.is_empty(),"qualified":qualified,"covered":covered,"budget":cut.get("within_budget",false),"faces":cut.get("triangles",-1),"bytes":cut.get("bytes",-1),"pages":cut.get("keys",[]).size(),"pass":qualified and covered and cut.get("within_budget",false)})
				if input.has("resident_basis") and cut.is_empty():
					var projection=preload("res://scripts/experiments/volume_projection.gd")
					var ray: Vector3=projection.ground_basis(canvas,deg_to_rad(38)).inverse()*projection.camera_basis(canvas,deg_to_rad(38)).z
					var roof := -Vector2(ray.x,ray.z)/ray.y
					var buildings: Array=native.Query.query(native._grid_index,view,canvas,size,roof,Vector2.ZERO).entries
					var ground_pages := 0
					var ground_faces := 0
					var building_bytes := 0
					for entry: Dictionary in buildings: building_bytes+=int(entry.bytes)
					for entry: Dictionary in native._grid_native_ground:
						var visible: Dictionary=native.Select.visible(entry,view,canvas,size,roof,Vector2.ZERO)
						if visible.faces>0: ground_pages+=1;ground_faces+=int(visible.faces)
					row.native[-1]["empty_diagnostic"]={"building_pages":buildings.size(),"ground_pages":ground_pages,
						"ground_faces":ground_faces,"building_bytes_before_refine":building_bytes,
						"page_gate":buildings.size()+ground_pages>native.Contract.native_page_limit(),
						"byte_gate":building_bytes>192*1024*1024}
				if input.get("cost_breakdown",false): row.native[-1]["costs"]=costs
				if input.get("ground_cost_model",false) and configuration=="lod5_full" and cut.has("grid_projection"):
					var projection: Dictionary=cut.grid_projection
					var building_pages := 0
					var building_faces := 0
					var building_bytes := 0
					for entry: Dictionary in cut.entries:
						if native._grid_entries.has(entry.path) or native._grid_variants.has(entry.path):
							building_pages+=1;building_faces+=int(entry.faces);building_bytes+=int(entry.bytes)
					var roots: Array[Dictionary]=native._grid_native_ground if native._native_ground_only else native._grid_ground
					var solved := native.Cut.solve(roots,view,canvas,size,projection.roof,Vector2.ZERO,Native.Contract.native_page_limit(),false)
					var options: Array=[]
					for state: Dictionary in solved.frontier:
						options.append({"ground_pages":state.active,"ground_faces":state.faces,"ground_bytes":state.bytes,
							"total_pages":state.active+building_pages,"total_faces":state.faces+building_faces,"total_bytes":state.bytes+building_bytes,
							"fits":state.active+building_pages<=Native.Contract.native_page_limit() and state.faces+building_faces<=240000 and state.bytes+building_bytes<=192*1024*1024})
					row.native[-1]["ground_cost_model"]={"fixed_building_pages":building_pages,"fixed_building_faces":building_faces,"options":options,
						"scope":"ground frontier with selected building representation; not global optimality or FPS"}
				if request.has("ground_mask"): row.native[-1]["ground_mask"]=request.ground_mask
				if input.get("ground_frontier",false) and configuration=="lod5_full" and cut.has("grid_projection"):
					var geometry: Dictionary=cut.grid_projection
					var building_faces := 0
					var building_bytes := 0
					var building_pages := 0
					for entry: Dictionary in cut.entries:
						if native._grid_entries.has(entry.path) or native._grid_variants.has(entry.path):
							building_faces+=int(entry.faces);building_bytes+=int(entry.bytes);building_pages+=1
					var choices: Array=[]
					for cap: int in [4,5,6,8]:
						var solved := native.Cut.solve(native._grid_ground,view,canvas,size,geometry.roof,Vector2.ZERO,cap,false)
						var ground_cut := native.Cut.pick(solved,192*1024*1024-building_bytes)
						choices.append({"ground_cap":cap,"ground_faces":ground_cut.triangles,"ground_bytes":ground_cut.bytes,"total_faces":ground_cut.triangles+building_faces,"total_bytes":ground_cut.bytes+building_bytes,"total_pages":ground_cut.active+building_pages,"current_page_cap_pass":ground_cut.active+building_pages<=Native.Contract.native_page_limit()})
					row.native[-1]["ground_frontier"]=choices
				# 每个独立样本回收未请求的临时描述符，避免审计顺序造成容量偏差。
				native.retire_subsets(PackedStringArray())
			native._grid_ground=original_ground;native._grid_native_ground=original_native_ground
			results.append(row)
			print("[Tokyo feasibility] ",pose," foundation=",row.foundation_pass," native=",row.native)
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file==null: return 1
		file.store_string(JSON.stringify({"package":package_binding,"size":[1600,900],"samples":results,"metadata_only":true,"visual_verified":false,"simplified_ground_cost":input.get("simplified_ground_cost",{}),"simplified_quality_verified":false},"\t"));file.close()
		stream.queue_free();owner.queue_free()
		await parent.get_tree().process_frame
		return 0
	if input.get("inventory_only",false):
		# 沿当前认证元数据去重；费用口径复用运行时，不代表OS内存或GPU实测。
		var sets := {"native_leaf5":{},"ground_components5":{},"grid_buildings5":{},"foundation_all":{},"foundation_through_middle":{}}
		for key: String in snapshot.configurations.lod5_full.leaves:
			var row: Dictionary=snapshot.pages[key]
			for path: String in row.components: sets.native_leaf5[path]=int(row.components[path].bytes)
			var ground_path: String=row.mapping[2][0]
			sets.ground_components5[ground_path]=int(row.components[ground_path].bytes)
		for key: String in native._grid_fine:
			for kind in 2:
				for row: Dictionary in native._grid_fine[key][kind]:
					for path: String in row.components: sets.grid_buildings5[path]=int(row.components[path].bytes)
		var catalogs: Array[Dictionary]=[]
		for binding: Dictionary in package.catalogs:
			var catalog := Native.Contract.read(binding.path,binding.sha256)
			if catalog.is_empty(): return 1
			catalogs.append(catalog)
		var foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd").plan(catalogs,192*1024*1024,true)
		if foundation.is_empty(): return 1
		for index: int in foundation.layers:
			for entry: Dictionary in foundation.layers[index].entries:
				var row: Dictionary=catalogs[index].rows[entry.key]
				for part: Dictionary in [row.native_geometry,row.native_texture]:
					var amount := int(part.get("three_copy_charge",part.get("bytes",0)))
					sets.foundation_all[part.path]=amount
					if float(foundation.layers[index].upper)<=0.625: sets.foundation_through_middle[part.path]=amount
		sets["grid_ground_middle"]={}
		for name: String in ["grid_buildings5","ground_components5","foundation_through_middle"]:
			for path: String in sets[name]:
				if sets.grid_ground_middle.has(path) and sets.grid_ground_middle[path]!=sets[name][path]: return 1
				sets.grid_ground_middle[path]=sets[name][path]
		var counts: Dictionary={}
		for name: String in sets:
			var total := 0
			for amount: int in sets[name].values(): total+=amount
			counts[name]={"bytes":total,"physical_resources":sets[name].size(),"within_4_gib":total<=4*1024*1024*1024}
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file==null: return 1
		file.store_string(JSON.stringify({"grid":input.grid_native,"package":package_binding,"snapshot_package":snapshot.package,"sets":counts,"metadata_only":true,"display_coverage_verified":false,"physical_ram_verified":false},"\t"));file.close()
		print("[Tokyo current inventory] ",counts)
		return 0
	var pose: Array=input.get("pose",[-3909.23291015625,-13350.849609375,1.2565825])
	if pose.size()!=3: return 1
	var center := Vector2(pose[0],pose[1])
	var scale_value := float(pose[2])
	var dimensions: Array=input.get("size",[1600,900])
	var size := Vector2(dimensions[0],dimensions[1])
	var canvas := Transform2D(0.0,Vector2.ZERO).scaled(Vector2.ONE*scale_value)
	canvas.origin=size*0.5-canvas*center
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,size/scale_value)
	if input.has("audit_snapshot"):
		# 重放日志保存的目标集合，分类当前裸视野必需片；不冒称恢复了原预测保护带。
		var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.audit_snapshot))
		var sample: Dictionary=report.wasd.snapshots[int(input.get("snapshot_index",0))]
		var missing: Dictionary={}
		for part: Dictionary in sample.target_status.missing_meshes: missing[part.path]=true
		var ray := preload("res://scripts/experiments/volume_projection.gd").ground_basis(canvas,deg_to_rad(38)).inverse()*preload("res://scripts/experiments/volume_projection.gd").camera_basis(canvas,deg_to_rad(38)).z
		var roof := -Vector2(ray.x,ray.z)/ray.y
		var parts: Dictionary={}
		for key: String in sample.target_keys:
			if not native._grid_variants.has(key): continue
			for kind in 2:
				for child: Dictionary in native.pages[key].views[kind]:
					var bounds := preload("res://scripts/rendering/tokyo_cells_overlay.gd").projected_layer_bounds(child.box,roof,Vector2.ZERO)
					var visible := preload("res://scripts/rendering/tokyo_cells_overlay.gd").intersects_view(bounds,view,canvas,size)
					for path: String in child.components: parts[path]={"visible":visible,"bytes":child.bytes,"missing":missing.has(path)}
		var counts := {"components":parts.size(),"visible":0,"offscreen":0,"missing_visible":0,"missing_offscreen":0,"offscreen_bytes":0,"missing_unknown":0}
		for part: Dictionary in parts.values():
			counts["visible" if part.visible else "offscreen"]+=1
			if not part.visible: counts.offscreen_bytes+=int(part.bytes)
			if part.missing: counts["missing_visible" if part.visible else "missing_offscreen"]+=1
		for path: String in missing:
			if not parts.has(path): counts.missing_unknown+=1
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file==null: return 1
		file.store_string(JSON.stringify({"counts":counts,"sample_ms":sample.ms,"pose":pose,"logical_size":dimensions,"current_view_only":true,"guard_reconstructed":false,"runtime_changed":false},"\t"));file.close()
		print("[Tokyo grid pending audit] ",counts)
		return 0
	# 与运行时相同：固定物理目录先配置，随后选择器登记不可变逻辑子集。
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	if not stream.configure_hlod(owner,native.pages,native.ground.textures): owner.queue_free();return 1
	native.subset_stream=weakref(stream);native.subset_geometry=native.pages
	var started := Time.get_ticks_usec()
	var cut := native.select(center,scale_value,0,size,"lod5_full",192*1024*1024)
	var select_usec := Time.get_ticks_usec()-started
	if cut.is_empty() or not cut.within_budget or not native.covers_visible_layers(cut,view,canvas,size): return 1
	var fail := 0
	if input.has("grid_detail"):
		# 全量粗页与真实细片来源资格必须一致；父子同交、错身份不能获得覆盖。
		var coarse: Dictionary={}
		var fine: Dictionary={}
		for key: String in native._grid_entries:
			for kind in 2:
				var view_row: Variant=native.pages[key].views[kind]
				if view_row!=null:
					for path: String in view_row.components: coarse[path]={"identity":view_row.components[path].canonical_identity,"layers":1<<kind}
				for child: Dictionary in native._grid_fine[key][kind]:
					for path: String in child.components: fine[path]={"identity":child.components[path].canonical_identity,"layers":1<<kind}
		var coverage_adapter := preload("res://scripts/experiments/tokyo_grid_coverage.gd")
		var coarse_layers := coverage_adapter.refined_layers(native._grid_refined_data,coarse)
		var fine_layers := coverage_adapter.refined_layers(native._grid_refined_data,fine)
		fail+=int(coarse_layers.is_empty() or fine_layers!=coarse_layers)
		var overlap := fine.duplicate(true)
		var first: String=coarse.keys()[0]
		overlap[first]=coarse[first]
		fail+=int(not coverage_adapter.refined_layers(native._grid_refined_data,overlap).is_empty())
		var forged := fine.duplicate(true)
		forged[forged.keys()[0]].identity={"bad":true}
		fail+=int(not coverage_adapter.refined_layers(native._grid_refined_data,forged).is_empty())
	var descriptor_count := native.pages.size()
	var repeated := native.select(center,scale_value,0,size,"lod5_full",192*1024*1024)
	fail+=int(repeated.keys!=cut.keys or repeated.get("grid_pieces",{})!=cut.get("grid_pieces",{}) or native.pages.size()!=descriptor_count)
	fail+=preload("res://scripts/tests/test_tokyo_hlod_stream.gd").commit_ready_checks()
	fail+=preload("res://scripts/tests/test_tokyo_grid_coverage.gd").checks()
	var missing_rejected := 0
	for n in cut.entries.size():
		var partial := cut.duplicate(true)
		partial.entries.remove_at(n)
		if not native.covered(partial).is_empty(): fail+=1
		if not native.covers_visible_layers(partial,view,canvas,size): missing_rejected+=1
		else: fail+=1
	var missing_pieces := 0
	for n in cut.entries.size():
		var entry: Dictionary=cut.entries[n]
		if not entry.has("piece_indices"): continue
		for kind in 2:
			for part in entry.piece_indices[kind].size():
				var partial := cut.duplicate(true)
				partial.entries[n].piece_indices[kind].remove_at(part)
				if native.covers_visible_layers(partial,view,canvas,size) or not native.covered(partial).is_empty(): fail+=1
				else: missing_pieces+=1
	if not stream.configure_residency(cut.keys,cut.ground_images,384*1024*1024): owner.queue_free();return 1
	stream.request(cut.keys,PackedStringArray())
	stream.request_textures(cut.ground_images,PackedStringArray())
	var ready := false
	var deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		ready=true
		for path: String in cut.keys:
			if stream.resource(path)==null: ready=false
		for path: String in cut.ground_images:
			if stream.texture(path)==null: ready=false
		if ready or not stream.summary().failures.is_empty() or not stream.summary().texture_failures.is_empty(): break
		await parent.get_tree().process_frame
	fail+=int(not ready)
	var nodes := 0
	var committed := 0
	var hidden := 0
	var coarse_handoff_increment := 0
	if ready:
		var overlay := preload("res://scripts/rendering/tokyo_hlod_overlay.gd").new()
		owner.add_child(overlay);overlay.set_process(false)
		overlay._city=Node3D.new();overlay.add_child(overlay._city)
		overlay._stream=stream;overlay._native=native
		overlay._geometry=native.pages;overlay._textures=native.ground.textures
		overlay._target=cut;overlay._target_catalog=-2
		overlay._native_surface=Shader.new()
		overlay._native_surface.code=preload("res://scripts/rendering/tokyo_hlod_surface.gd").native_code()
		overlay._surface=Shader.new()
		overlay._surface.code=preload("res://scripts/rendering/tokyo_hlod_surface.gd").shader_code()
		overlay._height_surface=Shader.new()
		overlay._height_surface.code=preload("res://scripts/rendering/tokyo_ground_height.gd").shader_code()
		overlay._bind_target()
		await parent.get_tree().process_frame
		nodes=overlay._nodes.size();committed=overlay._committed.size();hidden=overlay._native_hidden.size()
		fail+=int(overlay._committed_cut!=cut or committed!=cut.keys.size() or nodes==0)
		if not cut.get("grid_pieces",{}).is_empty():
			var coarse := cut.duplicate(true)
			coarse.keys=PackedStringArray()
			for key: String in cut.keys: coarse.keys.append(native._grid_variants.get(key,{}).get("base",key))
			# 走正式物理联合计费；细片已固定驻留，旧粗块仍须另计，不能视作零成本交接。
			coarse_handoff_increment=overlay._handoff_bytes(coarse,-2)
			fail+=int(coarse_handoff_increment<=0 or coarse_handoff_increment>stream.residency_limit-stream.residency_bytes)
	var summary := stream.summary()
	var old_ground_components_loaded := 0
	if package.native.has("ground_components"):
		var ground_report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(package.native.ground_components.path))
		for row: Dictionary in ground_report.rows:
			old_ground_components_loaded+=int(stream._cache.has(row.source.path))
		fail+=old_ground_components_loaded
	# 显示/固定集被保护时不可退役；切面来源与Stream登记必须一致。
	native.retire_subsets(cut.keys)
	for key: String in cut.keys:
		if key.begins_with("grid-subset/"): fail+=int(not stream._logical.has(key) or not native.pages.has(key))
	var stream_ref: WeakRef=weakref(stream)
	owner.queue_free()
	deadline=Time.get_ticks_msec()+15000
	await parent.get_tree().process_frame
	while is_instance_valid(stream_ref.get_ref()) and Time.get_ticks_msec()<deadline: await parent.get_tree().process_frame
	fail+=int(is_instance_valid(stream_ref.get_ref()))
	var report := {"fail":fail,"select_usec":select_usec,"faces":cut.triangles,"bytes":cut.bytes,"pages":cut.keys.size(),
		"old_ground_components_loaded":old_ground_components_loaded,
		"missing_pieces_rejected":missing_pieces,"refined_cells":cut.get("grid_pieces",{}).size(),
		"coarse_handoff_increment":coarse_handoff_increment,"stable_descriptors":native.pages.size()==descriptor_count,
		"missing_rejected":missing_rejected,"committed":committed,"nodes":nodes,"hidden":hidden,"stream":summary,"visual_verified":false,"f5_installed":false}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("[Tokyo grid native] ",report)
	return fail
