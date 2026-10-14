extends RefCounted
const Read := preload("res://scripts/tests/build_tokyo_grid_dependencies.gd")
const Stream := preload("res://scripts/rendering/tokyo_hlod_stream.gd")
const Assembly := preload("res://scripts/rendering/tokyo_component_page.gd")


static func run(parent: Node, input: Dictionary) -> int:
	var binding: Variant=input.get("grid_stream")
	var output: String=input.get("output","")
	if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").binding(binding): return 1
	if FileAccess.get_sha256(binding.path)!=binding.sha256 or not output.is_absolute_path() or FileAccess.file_exists(output): return 1
	var audit: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not audit is Dictionary or not audit.get("all_complete",false): return 1
	var descriptors: Dictionary={}
	var counts := PackedInt32Array([0,0])
	var groups: Dictionary={}
	for record: Dictionary in audit.rows:
		var joined: Variant=Read.read(record.joined)
		if not joined is Dictionary: return 1
		for page: Dictionary in joined.pages:
			var kind := int(String(page.key).get_slice(":",0))
			if kind<0 or kind>1: return 1
			if counts[kind]>=4 and not input.get("grouped",false): continue
			counts[kind]+=1
			var identity := {"format":"tokyo_grid_view","schema":1,"configuration":"lod5_full","source":binding.sha256,"component":page.canonical_identity.source,"layer":kind}
			var component := {"path":page.path,"sha256":page.sha256,"bytes":page.bytes,"canonical_identity":page.canonical_identity}
			descriptors["grid/"+page.sha256]={"canonical_identity":identity,"bytes":page.bytes,"faces":page.faces,"box":page.box,"components":{page.path:component}}
			var cell := String(page.key).substr(2)
			if not groups.has(cell): groups[cell]=[null,null]
			groups[cell][kind]=descriptors["grid/"+page.sha256]
			if input.get("segmented",false):
				var children: Array=[]
				for origin: Dictionary in page.origins:
					var part: Dictionary=origin.component
					var part_identity := {"format":"tokyo_grid_view","schema":1,"configuration":"lod5_full","source":binding.sha256,"component":part.canonical_identity.source,"layer":kind}
					children.append({"canonical_identity":part_identity,"components":{part.path:part},"bytes":part.bytes,"faces":origin.faces,"box":part.box})
				groups[cell][kind]=children
	if input.get("grouped",false):
		descriptors.clear()
		for cell: String in groups:
			var views: Array=groups[cell]
			if views[0]==null or views[1]==null: continue
			if input.get("segmented",false):
				var bindings: Dictionary={}
				var identities: Array=[[],[]]
				var total := 0
				for kind in 2:
					for child: Dictionary in views[kind]:
						bindings.merge(child.components)
						total+=int(child.bytes)
						identities[kind].append(child.canonical_identity)
				descriptors["grid/"+cell]={"canonical_identity":{"format":"tokyo_grid_view","schema":3,"configuration":"lod5_full","source":binding.sha256,"layers":identities},"views":views,"components":bindings,"bytes":total}
				if descriptors.size()==4: break
				continue
			var components: Dictionary=views[0].components.duplicate()
			components.merge(views[1].components)
			var identity := {"format":"tokyo_grid_view","schema":2,"configuration":"lod5_full","source":binding.sha256,"layers":[views[0].canonical_identity,views[1].canonical_identity]}
			descriptors["grid/"+cell]={"canonical_identity":identity,"views":views,"components":components,"bytes":int(views[0].bytes)+int(views[1].bytes)}
			if descriptors.size()==4: break
		if descriptors.size()!=4: return 1
	elif counts!=PackedInt32Array([4,4]): return 1
	var owner := Node.new()
	parent.add_child(owner)
	var stream := Stream.new()
	parent.add_child(stream)
	stream.configure(owner,descriptors)
	var wanted := PackedStringArray(descriptors.keys())
	stream.request(wanted,PackedStringArray())
	var deadline := Time.get_ticks_msec()+30000
	var ready := false
	while Time.get_ticks_msec()<deadline:
		ready=true
		for path: String in wanted:
			if stream.resource(path)==null: ready=false
		if ready or not stream.summary().failures.is_empty(): break
		await parent.get_tree().process_frame
	var fail := int(not ready)
	var refs: Array[WeakRef]=[]
	if ready:
		for path: String in wanted:
			if input.get("grouped",false): fail+=inspect_group(stream,descriptors[path],path,refs)
			else: fail+=inspect(stream,descriptors[path],path,refs)
	var bound_nodes := 0
	if ready and input.get("grouped",false):
		var bound := inspect_binding(owner,stream,wanted,input.get("segmented",false),refs)
		bound_nodes=bound.nodes
		fail+=int(bound.fail)
		await parent.get_tree().process_frame
	if ready and input.get("segmented",false): fail+=subset_registry_checks(stream,descriptors[wanted[0]])
	var summary := stream.summary()
	var stream_ref: WeakRef=weakref(stream)
	owner.queue_free()
	deadline=Time.get_ticks_msec()+15000
	await parent.get_tree().process_frame
	while is_instance_valid(stream_ref.get_ref()) and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	var retained := 0
	for reference: WeakRef in refs: retained+=int(is_instance_valid(reference.get_ref()))
	fail+=int(is_instance_valid(stream_ref.get_ref()) or retained>0)
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	var report := {"fail":fail,"validated":wanted.size() if ready else 0,"bound_nodes":bound_nodes,"retained":retained,"summary":summary,"map_visual_verified":false,"runtime_installed":false}
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("[Tokyo grid stream] ",report)
	return fail


static func subset_registry_checks(stream: Node, source: Dictionary) -> int:
	var row := source.duplicate(true)
	row.components={};row.bytes=0
	for kind in 2:
		row.views[kind]=[row.views[kind][0]]
		row.canonical_identity.layers[kind]=[row.views[kind][0].canonical_identity]
		row.components.merge(row.views[kind][0].components)
		row.bytes+=int(row.views[kind][0].bytes)
	var key := "grid-subset/"+JSON.stringify(row.canonical_identity).sha256_text()
	var fail := int(not stream.register_grid_subset(key,row))
	fail+=int(not stream.register_grid_subset(key,row) or stream.resource(key)==null)
	var altered := row.duplicate(true);altered.bytes+=1
	fail+=int(stream.register_grid_subset(key,altered))
	fail+=int(stream.register_grid_subset("grid-subset/wrong",row))
	# 双层引用在同一逻辑视图内只展开认证物理片；旧请求和pins不能被回收。
	fail+=int(stream._paths(PackedStringArray([key,key])).size()!=row.components.size())
	stream.request(PackedStringArray([key]),PackedStringArray())
	fail+=int(not stream.retire_grid_subsets(PackedStringArray()).is_empty())
	stream.request(PackedStringArray(),PackedStringArray([key]))
	fail+=int(not stream.retire_grid_subsets(PackedStringArray()).is_empty())
	stream.request(PackedStringArray(),PackedStringArray())
	fail+=int(not stream.retire_grid_subsets(PackedStringArray([key])).is_empty())
	fail+=int(stream.retire_grid_subsets(PackedStringArray())!=PackedStringArray([key]))
	fail+=int(stream._logical.has(key) or stream._expanded_paths.has(key) or stream._views.has(key))
	# 用不同的有效来源身份检查有界元数据；不加载新物理资源。
	var accepted := 0
	for n in stream.GRID_SUBSET_LIMIT+1:
		var variant := row.duplicate(true)
		var stamp := str(n).sha256_text()
		variant.canonical_identity.source=stamp
		for kind in 2:
			variant.views[kind][0].canonical_identity.source=stamp
			variant.canonical_identity.layers[kind]=[variant.views[kind][0].canonical_identity]
		var path := "grid-subset/"+JSON.stringify(variant.canonical_identity).sha256_text()
		accepted+=int(stream.register_grid_subset(path,variant))
	fail+=int(accepted!=stream.GRID_SUBSET_LIMIT or stream._grid_subsets.size()!=stream.GRID_SUBSET_LIMIT)
	stream.retire_grid_subsets(PackedStringArray())
	fail+=int(not stream._grid_subsets.is_empty())
	return fail


static func inspect_binding(owner: Node, stream: Node, wanted: PackedStringArray, segmented: bool, refs: Array[WeakRef]) -> Dictionary:
	# 同步检查返回后再await，避免测试协程的迭代器保留最后一个网格。
	var overlay := preload("res://scripts/rendering/tokyo_hlod_overlay.gd").new()
	owner.add_child(overlay)
	overlay.set_process(false)
	overlay._city=Node3D.new()
	overlay.add_child(overlay._city)
	var formal := ShaderMaterial.new()
	formal.shader=Shader.new()
	formal.shader.code=preload("res://scripts/rendering/tokyo_hlod_surface.gd").native_code()
	var high := formal.duplicate() as ShaderMaterial
	high.set_shader_parameter("facade_detail",true)
	var expected: Array=[]
	for path: String in wanted:
		var page: Resource=stream.resource(path)
		if page==null: return {"fail":1,"nodes":overlay._nodes.size()}
		for kind in 2:
			var meshes: Array=page.layer_meshes[kind] if segmented else [page.meshes[kind]]
			for mesh: ArrayMesh in meshes: expected.append([mesh,high if kind==1 else formal])
		overlay._bind_native_entry(page,{"mask":[true,true,false]},formal,high)
	var fail := int(overlay._nodes.size()!=expected.size())
	for n in mini(overlay._nodes.size(),expected.size()):
		var instance: MeshInstance3D=overlay._nodes[n]
		fail+=int(instance.mesh!=expected[n][0] or instance.material_override!=expected[n][1])
		refs.append(weakref(instance))
	return {"fail":fail,"nodes":overlay._nodes.size()}


static func inspect_group(stream: Node, row: Dictionary, path: String, refs: Array[WeakRef]) -> int:
	var page: Resource=stream.resource(path)
	var fail := int(page.stream_identity()!=row.canonical_identity or page.geometry_bytes!=row.bytes)
	refs.append(weakref(page))
	var loaded: Dictionary={}
	for physical: String in row.components: loaded[physical]=stream._cache.get(physical)
	for kind in 2:
		var children: Array=row.views[kind] if row.canonical_identity.schema==3 else [row.views[kind]]
		for n in children.size():
			var physical: String=children[n].components.keys()[0]
			var component: Resource=loaded[physical]
			if component==null: return fail+1
			var mesh: ArrayMesh=page.layer_meshes[kind][n] if row.canonical_identity.schema==3 else page.meshes[kind]
			fail+=int(mesh!=component.meshes[0])
			refs.append(weakref(mesh))
	fail+=int(page.meshes[2].get_surface_count()!=0)
	var missing := loaded.duplicate()
	missing.erase(missing.keys()[0])
	fail+=int(Assembly.assemble(row,missing)!=null)
	var bad := row.duplicate(true)
	bad.bytes+=1
	fail+=int(Assembly.assemble(bad,loaded)!=null)
	bad=row.duplicate(true)
	bad.views.reverse()
	fail+=int(Assembly.assemble(bad,loaded)!=null)
	if row.canonical_identity.schema==3:
		bad=row.duplicate(true)
		bad.views[0].append(bad.views[0][0])
		bad.canonical_identity.layers[0].append(bad.canonical_identity.layers[0][0])
		bad.bytes+=int(bad.views[0][0].bytes)
		fail+=int(Assembly.assemble(bad,loaded)!=null) # 重复片不能双计身份或费用。
	return fail


static func inspect(stream: Node, row: Dictionary, path: String, refs: Array[WeakRef]) -> int:
	var page: Resource=stream.resource(path)
	var fail := int(page.stream_identity()!=row.canonical_identity or page.meshes.size()!=3 or page.geometry_bytes!=row.bytes)
	refs.append(weakref(page))
	for kind in 3:
		var mesh: ArrayMesh=page.meshes[kind]
		refs.append(weakref(mesh))
		if kind!=row.canonical_identity.layer: fail+=int(mesh.get_surface_count()!=0)
	var physical_path: String=row.components.keys()[0]
	var component: Resource=stream._cache.get(physical_path)
	if component==null: return fail+1
	fail+=int(page.meshes[row.canonical_identity.layer]!=component.meshes[0])
	# 真实物理对象用于错层/错面数反例，避免空载入提前拒绝掩盖断言。
	fail+=int(Assembly.assemble(row,{})!=null)
	var bad := row.duplicate(true)
	bad.canonical_identity.layer=2
	fail+=int(Assembly.assemble(bad,{physical_path:component})!=null)
	bad=row.duplicate(true)
	bad.faces+=1
	fail+=int(Assembly.assemble(bad,{physical_path:component})!=null)
	return fail
