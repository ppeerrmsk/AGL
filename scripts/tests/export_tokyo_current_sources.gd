extends RefCounted
## 保存当前完整树及实际组件引用，供全图格网制作；不回退旧目录，也不加载所有网格。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")


static func run(input: Dictionary) -> int:
	if input.has("source_inventory"): return inventory(input)
	var binding: Variant=input.get("current_sources")
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var package: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var output: String=input.get("output","")
	if not package is Dictionary or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.get("native",{})): return 1
	var configurations: Dictionary={}
	var pages: Dictionary={}
	var summaries: Dictionary={}
	for configuration: String in ["lod4_full","lod5_full"]:
		var roots: Array=native._partition_roots.get(configuration,native.catalog.configurations[configuration])
		var stack: Array=roots.duplicate()
		var seen: Dictionary={}
		var leaves: Array[String]=[]
		var faces := PackedInt64Array([0,0,0])
		var formal := 0
		while not stack.is_empty():
			var entry: Dictionary=stack.pop_back()
			if seen.has(entry.path) or not native.pages.has(entry.path): return 1
			seen[entry.path]=true
			pages[entry.path]=native.pages[entry.path]
			if not entry.get("children",[]).is_empty():
				stack.append_array(entry.children)
				continue
			leaves.append(entry.path)
			for kind in 3: faces[kind]+=int(entry.triangles[kind])
			if not pages[entry.path].get("game_sources",[]).is_empty(): formal+=1
		# 完整原生树和当前地表合同分别保留；不能强制把所有地面拉回高面数几何。
		configurations[configuration]={"roots":roots,"leaves":leaves,"coverage":native.coverage[configuration]}
		summaries[configuration]={"roots":roots.size(),"nodes":seen.size(),"leaves":leaves.size(),"leaf_faces":Array(faces),"formal_source_leaves":formal}
	var data := {"schema":1,"package":binding,"catalog_sha256":native.catalog_sha,
		"configurations":configurations,"pages":pages,"ground":native.ground,
		"runtime_integrated":false,"geometry_content_verified":false}
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var path := output.path_join("sources.bin")
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return 1
	file.store_var(data,false);file.close()
	file=FileAccess.open(path,FileAccess.READ)
	if file==null: return 1
	var restored: Variant=file.get_var(false)
	file.close()
	if restored!=data: return 1
	file=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"source_package":binding,"snapshot":{"path":path,"sha256":FileAccess.get_sha256(path)},
		"configurations":summaries,"ground_rows":native.ground.get("rows",{}).size(),
		"roundtrip_equal":true,"geometry_content_verified":false,"runtime_integrated":false},"\t"))
	file.close()
	print("[Tokyo current sources] ",summaries," saved_readback=true")
	return 0


static func inventory(input: Dictionary) -> int:
	var snapshots: Array[Dictionary]=[]
	for binding: Dictionary in [input.source_inventory,input.compare_sources]:
		if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
		var file := FileAccess.open(binding.path,FileAccess.READ)
		if file==null:return 1
		var data: Variant=file.get_var(false);file.close()
		if not data is Dictionary or data.get("schema")!=1:return 1
		snapshots.append(data)
	var current: Dictionary=snapshots[0];var previous: Dictionary=snapshots[1]
	var rows: Array[Dictionary]=[];var summaries: Dictionary={}
	for configuration: String in ["lod4_full","lod5_full"]:
		var old_components: Dictionary={}
		for key: String in previous.configurations[configuration].leaves:
			var page: Dictionary=previous.pages[key]
			for path: String in page.components:old_components[path]=page.components[path]
		var stack: Array=current.configurations[configuration].roots.duplicate()
		var reused := 0;var changed := 0
		while not stack.is_empty():
			var node: Dictionary=stack.pop_back()
			if not node.get("children",[]).is_empty():stack.append_array(node.children);continue
			var page: Dictionary=current.pages[node.path]
			var reusable := true
			for path: String in page.components:
				if old_components.get(path)!=page.components[path]:reusable=false
			if reusable:reused+=1
			else:changed+=1
			var box: AABB=node.boxes[0]
			for kind in [1,2]:box=box.merge(node.boxes[kind])
			rows.append({"configuration":configuration,"source":node.path,"triangles":Array(node.triangles),
				"bounds":[box.position.x,box.position.z,box.end.x,box.end.z],"components":page.components,
				"game_sources":page.get("game_sources",[]),"all_components_reusable":reusable})
		summaries[configuration]={"same_component_leaves":reused,"changed_component_leaves":changed}
	if FileAccess.file_exists(input.output):return 1
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"source":input.source_inventory,"compare":input.compare_sources,
		"source_package":current.package,"rows":rows,"summaries":summaries,
		"limitations":"Descriptor identity reuse only, not grid-output coverage or geometry revalidation. Bounds merge stored layer boxes.",
		"runtime_integrated":false},"\t"));file.close()
	print("Tokyo source inventory: ",summaries)
	return 0
