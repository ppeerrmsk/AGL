extends RefCounted
## 只核既有原生档位的同视野分层成本；预算可用不等于几何清晰度获批。


static func run(input: Dictionary) -> int:
	var binding: Variant=input.get("native_massing_cost")
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	if not contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var output: String=input.get("output","")
	if not output.is_absolute_path() or FileAccess.file_exists(output): return 1
	var poses: Variant=input.get("poses",[[330,-13420,0.8333333333],[330,-13420,1.25],[330,-13420,1.6666666667],[-4300,-3700,0.4166666667],[-4300,-3700,0.75]])
	if not input.get("leaf_audit_only",false) is bool: return 1
	var leaf_only: bool=input.get("leaf_audit_only",false)
	if not poses is Array or poses.is_empty() or poses.size()>(1024 if leaf_only else 32): return 1
	for pose: Variant in poses:
		# 成本审计须覆盖正常近景；资格仍由native_qualified逐档判定，不扩张资源资格。
		if not contract.numbers(pose,3) or float(pose[2])<=0.0 or float(pose[2])>5.0: return 1
	var package: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not package is Dictionary or not package.has("native"): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.native): return 1
	var rows: Array=[]
	var ground_export: String=input.get("ground_export","")
	var wall_export: String=input.get("wall_export","")
	var layer0_export: String=input.get("layer0_export","")
	if int(not ground_export.is_empty())+int(not wall_export.is_empty())+int(not layer0_export.is_empty())>1: return 1
	var export_kind := 0 if not layer0_export.is_empty() else (2 if wall_export.is_empty() else 1)
	if not wall_export.is_empty(): ground_export=wall_export
	if not layer0_export.is_empty(): ground_export=layer0_export
	if leaf_only and not ground_export.is_empty(): return 1
	var exported: Dictionary={}
	# 整树核查与显式来源导出只供离线制作，不改变正式选页。
	var tree_inventory: Dictionary={}
	var tree_entries: Dictionary={}
	if not input.get("partition_ground_inventory",false) is bool: return 1
	var explicit_keys: Variant=input.get("ground_page_keys",[])
	if not explicit_keys is Array or explicit_keys.size()>64: return 1
	if not explicit_keys.is_empty() and (ground_export.is_empty() or export_kind!=2 or leaf_only): return 1
	if input.get("partition_ground_inventory",false) or not explicit_keys.is_empty():
		for configuration: String in ["lod4_full","lod5_full"]:
			var stack: Array=native._partition_roots.get(configuration,[]).duplicate()
			while not stack.is_empty():
				var entry: Dictionary=stack.pop_back()
				stack.append_array(entry.get("children",[]))
				if tree_entries.has(entry.path): return 1
				tree_entries[entry.path]={"entry":entry,"configuration":configuration}
				var children: Array=[]
				for child: Dictionary in entry.get("children",[]): children.append(child.path)
				tree_inventory[entry.path]={"configuration":configuration,"triangles":entry.triangles,
					"children":children,"ground_bound":native.ground.get("rows",{}).has(entry.path)}
	var unique_keys: Dictionary={}
	for key: Variant in explicit_keys:
		if not key is String or not tree_entries.has(key) or unique_keys.has(key): return 1
		if int(tree_entries[key].entry.triangles[2])<=0: return 1
		unique_keys[key]=true
	if not ground_export.is_empty():
		if not ground_export.is_absolute_path() or DirAccess.dir_exists_absolute(ground_export): return 1
		if DirAccess.make_dir_recursive_absolute(ground_export)!=OK: return 1
	for key: String in explicit_keys:
		var row: Dictionary=tree_entries[key]
		if not _export_layer(native,row.entry,row.configuration,2,ground_export,exported): return 1
	for pose: Array in poses:
		if leaf_only:
			rows.append(_leaf_cut(native,pose))
			continue
		for level in [2,3,4,5]:
			var configuration := "lod%d_full" % level
			var cut := native.select(Vector2(pose[0],pose[1]),pose[2],0.0,Vector2(1600,900),configuration,192*1024*1024)
			var layers := [0,0,0]
			for entry: Dictionary in cut.get("entries",[]):
				for kind in 3:
					if entry.mask[kind]: layers[kind]+=int(entry.triangles[kind])
			if layers[0]+layers[1]+layers[2]!=int(cut.get("triangles",0)): return 1
			var stream_bytes := preload("res://scripts/rendering/tokyo_hlod_handoff.gd").streaming_bytes(native.pages,native.ground.get("textures",{}),cut.keys,cut.get("ground_images",PackedStringArray()),int(cut.charges.ground_bytes))
			if stream_bytes<0: return 1
			# 只导出合格档的指定层；墙面与地表独立标记，不改正式cut或资源。
			var export_level := 3 if float(pose[2])<=0.75 else (4 if float(pose[2])<=1.25 else 5)
			if not ground_export.is_empty() and explicit_keys.is_empty() and level==export_level:
				if not preload("res://scripts/rendering/tokyo_hlod_handoff.gd").native_qualified(cut,pose[2]): return 1
				for entry: Dictionary in cut.get("entries",[]):
					if not entry.mask[export_kind] or exported.has(entry.path): continue
					if not _export_layer(native,entry,configuration,export_kind,ground_export,exported): return 1
			rows.append({"pose":pose,"configuration":configuration,"within_budget":cut.get("within_budget",false),
				"qualified":preload("res://scripts/rendering/tokyo_hlod_handoff.gd").native_qualified(cut,pose[2]),
				"triangles":cut.get("triangles",0),"layer_triangles":layers,"bytes":cut.get("bytes",0),"stream_bytes":stream_bytes,"pages":cut.get("active",0),"ground_images":cut.get("ground_images",PackedStringArray()).size()})
	# 去重物理组件的常驻成本；只读描述符，不加载GPU资源，不把压缩磁盘大小当显存。
	var physical: Dictionary={}
	for page: Dictionary in native.pages.values():
		for path: String in page.components:
			var component: Dictionary=page.components[path]
			if physical.has(path) and physical[path]!=component: return 1
			physical[path]=component
	var physical_bytes := 0
	for component: Dictionary in physical.values(): physical_bytes+=int(component.bytes)
	var ground_bytes := 0
	for texture: Dictionary in native.ground.get("textures",{}).values(): ground_bytes+=int(texture.charge)
	var inventory := {"logical_pages":native.pages.size(),"physical_meshes":physical.size(),"physical_mesh_bytes":physical_bytes,
		"ground_textures":native.ground.get("textures",{}).size(),"ground_texture_charge":ground_bytes,"all_native_and_ground_bytes":physical_bytes+ground_bytes,
		"excludes_hlod_foundation":true,"gpu_measured":false}
	var configurations: Dictionary={}
	for configuration: String in native.catalog.configurations:
		var roots: Array=native._partition_roots.get(configuration,native.catalog.configurations[configuration])
		var stack: Array=roots.duplicate()
		var root_parts: Dictionary={}
		var leaf_parts: Dictionary={}
		var all_parts: Dictionary={}
		var root_faces := 0
		var leaf_faces := 0
		var leaves := 0
		for root: Dictionary in roots:
			for faces: int in root.triangles: root_faces+=faces
			root_parts.merge(native.pages[root.path].components,true)
		while not stack.is_empty():
			var entry: Dictionary=stack.pop_back()
			all_parts.merge(native.pages[entry.path].components,true)
			if entry.get("children",[]).is_empty():
				leaves+=1
				for faces: int in entry.triangles: leaf_faces+=faces
				leaf_parts.merge(native.pages[entry.path].components,true)
			else: stack.append_array(entry.children)
		var profile := {"root_faces":root_faces,"leaf_faces":leaf_faces,"leaves":leaves}
		for label: String in ["root","leaf","all"]:
			var parts: Dictionary=root_parts if label=="root" else (leaf_parts if label=="leaf" else all_parts)
			var amount := 0
			for component: Dictionary in parts.values(): amount+=int(component.bytes)
			profile[label+"_mesh_bytes"]=amount
			profile[label+"_mesh_count"]=parts.size()
		configurations[configuration]=profile
	inventory["configurations"]=configurations
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"diagnostic_only":true,"package_sha256":binding.sha256,"rows":rows,"ground_export":exported if export_kind==2 else {},"wall_export":exported if export_kind==1 else {},"layer0_export":exported if export_kind==0 else {},"native_inventory":inventory,"partition_ground_inventory":tree_inventory if input.get("partition_ground_inventory",false) else {},"visual_accepted":false,"runtime_integrated":false},"\t"))
	file.close()
	return 0


static func _export_layer(native: RefCounted, entry: Dictionary, configuration: String, kind: int, directory: String, exported: Dictionary) -> bool:
	var page_row: Dictionary=native.pages[entry.path]
	var loaded: Dictionary={}
	for component_path: String in page_row.components:
		var descriptor: Dictionary=page_row.components[component_path]
		if FileAccess.get_sha256(component_path)!=descriptor.sha256: return false
		loaded[component_path]=ResourceLoader.load(component_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var page := preload("res://scripts/rendering/tokyo_component_page.gd").assemble(page_row,loaded)
	if page==null: return false
	var mesh: ArrayMesh=page.meshes[kind]
	# 混合树的2面不是源网格；导出原始完整通道并验证字节面数。
	var source_faces := int(entry.get("ground_replacement",{}).get("source_faces",entry.triangles[2])) if kind==2 else int(entry.triangles[kind])
	var path := directory.path_join((["layer0_%03d.attributes","wall_%03d.attributes","ground_%03d.attributes"][kind]) % exported.size())
	if preload("res://scripts/tests/tokyo_residential_preview.gd").export_attributes(mesh,path)!=0: return false
	if FileAccess.get_file_as_bytes(path).size()!=source_faces*120: return false
	var box := mesh.get_aabb()
	exported[entry.path]={"path":path,"sha256":FileAccess.get_sha256(path),"triangles":source_faces,
		"bounds":[box.position.x,box.position.z,box.end.x,box.end.z],"height_range":[box.position.y,box.end.y],
		"components":page_row.components,"configuration":configuration,"layer":kind}
	return true


static func _leaf_cut(native: RefCounted, pose: Array) -> Dictionary:
	# 仅诊断固定最细叶切面；不限制叶数、不删除面，也不把候选上限写回正式选择器。
	var projection := preload("res://scripts/experiments/volume_projection.gd")
	var select := preload("res://scripts/experiments/tokyo_spatial_select.gd")
	var size := Vector2(1600,900)
	var canvas := Transform2D.IDENTITY.scaled(Vector2.ONE*float(pose[2]))
	canvas.origin=size*0.5-canvas*Vector2(pose[0],pose[1])
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse*Vector2.ZERO,inverse*size-inverse*Vector2.ZERO)
	var ray := projection.ground_basis(canvas,deg_to_rad(38)).inverse()*projection.camera_basis(canvas,deg_to_rad(38)).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	var stack: Array=native._partition_roots.get("lod5_full",native.catalog.configurations.lod5_full).duplicate()
	var parts: Dictionary={}
	var faces := 0
	var active := 0
	var surfaces := 0
	var layer_faces := [0,0,0]
	var started := Time.get_ticks_usec()
	while not stack.is_empty():
		var entry: Dictionary=stack.pop_back()
		var visible := select.visible(entry,view,canvas,size,roof,Vector2.ZERO)
		if int(visible.faces)==0: continue
		if not entry.get("children",[]).is_empty(): stack.append_array(entry.children);continue
		active+=1
		faces+=int(visible.faces)
		for kind in 3:
			if visible.mask[kind]: surfaces+=1;layer_faces[kind]+=int(entry.triangles[kind])
		parts.merge(native.pages[entry.path].components,true)
	var amount := 0
	for component: Dictionary in parts.values(): amount+=int(component.bytes)
	return {"pose":pose,"configuration":"lod5_full","fixed_leaves":true,"active":active,"surfaces":surfaces,
		"triangles":faces,"layer_triangles":layer_faces,"bytes":amount,"mesh_count":parts.size(),"solver_usec":Time.get_ticks_usec()-started,
		"fits_current_active_cap":active<=16,"fits_current_face_budget":faces<=240000,"fits_current_display_bytes":amount<=192*1024*1024}
