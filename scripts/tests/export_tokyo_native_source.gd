extends RefCounted
## 从实际安装树定位最小共同来源，完整导出两档三层，不从固定视野外推覆盖。
const Attach := preload("res://scripts/tests/tokyo_partition_attach_probe.gd")
const Override := preload("res://scripts/rendering/tokyo_partition_override.gd")
const Boundary := preload("res://scripts/tests/build_tokyo_boundary_tree.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")


static func common_source(roots: Array, paths: Array) -> Dictionary:
	if paths.is_empty(): return {}
	var seen: Dictionary={}
	for path: Variant in paths:
		if not path is String or path.is_empty() or seen.has(path): return {}
		seen[path]=true
	for entry: Dictionary in roots:
		var contains_all := true
		for path: String in paths:
			if Attach.find_entry([entry],path).is_empty(): contains_all=false;break
		if not contains_all: continue
		var child := common_source(entry.children,paths)
		return entry if child.is_empty() else child
	return {}


static func unchanged_sources(original: Dictionary, current: Array) -> Array[Dictionary]:
	var found := Attach.find_entry(current,original.path)
	if not found.is_empty() and original==found: return [original]
	var result: Array[Dictionary]=[]
	for child: Dictionary in original.children:
		result.append_array(unchanged_sources(child,current))
	return result


static func formal_expectations(input: Dictionary, native: RefCounted, output: String) -> Dictionary:
	var requests: Variant=input.get("formal_expected")
	if not requests is Dictionary: return {}
	var result: Dictionary={}
	for configuration: String in ["lod4_full","lod5_full"]:
		var request: Variant=requests.get(configuration)
		if not request is Dictionary: return {}
		var schedule := Override.json_binding(request.get("schedule"))
		var plan := Override.json_binding(request.get("plan"))
		var certified: Dictionary=native.coverage[configuration]
		if schedule.is_empty() or plan.is_empty() or certified.schedule_sha256!=request.schedule.sha256 \
			or certified.plan_sha256!=request.plan.sha256 or plan.get("collision_sha256")!=certified.collision_sha256 \
			or schedule.get("owners_sha256")!=certified.owners_sha256 or plan.get("game_source_sha256")!=certified.game_source_sha256: return {}
		var selected: Dictionary={}
		for row: Dictionary in schedule.get("configurations",[]):
			if row.get("name")==configuration and row.get("plan_sha256")==request.plan.sha256: selected=row
		if selected.is_empty(): return {}
		var audit := preload("res://scripts/tests/build_tokyo_source_coverage.gd").new()
		var expected: Dictionary=audit._expected(plan,selected)
		if audit._fail!=0 or expected.is_empty(): return {}
		var path := output.path_join(configuration+"_formal_expected.bin")
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file==null: return {}
		file.store_var(expected);file.close()
		file=FileAccess.open(path,FileAccess.READ)
		if file==null: return {}
		var restored: Variant=file.get_var(false);file.close()
		if restored!=expected: return {}
		result[configuration]={"path":path,"sha256":FileAccess.get_sha256(path),"plan":request.plan,"schedule":request.schedule}
	return result


static func run(input: Dictionary, digest: String) -> int:
	var package := Override.json_binding(input.get("native_source_export"))
	var output: String=input.get("output","")
	var paths: Variant=input.get("source_paths",[])
	var identities: Variant=input.get("source_identities",[])
	if not input.get("include_game_sources",false) is bool: return 1
	var include_game: bool=input.get("include_game_sources",false)
	if package.is_empty() or not paths is Array or paths.size()>32 \
		or not identities is Array or identities.size()>32 or (not paths.is_empty() and not identities.is_empty()) \
		or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.get("native",{})): return 1
	if identities.is_empty():
		var source := common_source(native.catalog.configurations.lod5_full,paths)
		if source.is_empty(): return 1
		identities=[native.pages[source.path].canonical_identity]
	# 全图审计可显式指定多个互不重叠的来源，仍逐一核对真实目录身份和正式楼保护。
	for identity: Variant in identities:
		if not identity is Dictionary: return 1
		for field: String in ["parent","cell","ancestor"]:
			if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").integer(identity.get(field),-1): return 1
	var targets: Dictionary={}
	# 跨LOD只配对同一树位置；level/source/owners本来随档位变化，各自完整摘要仍独立绑定。
	for configuration in ["lod4_full","lod5_full"]:
		targets[configuration]=[]
		for identity: Dictionary in identities:
			var target := ""
			for key: String in native.pages:
				var actual: Dictionary=native.pages[key].get("canonical_identity",{})
				if actual.get("configuration")==configuration and actual.get("parent",-1)==identity.parent \
					and actual.get("cell",-1)==identity.cell and actual.get("ancestor",-1)==identity.ancestor:
					if not target.is_empty(): return 1
					target=key
			if target.is_empty():
				print("[source export] counterpart missing: ",configuration);return 1
			var original := Attach.find_entry(native.catalog.configurations[configuration],target)
			if original.is_empty(): return 1
			var current: Array=native._partition_roots.get(configuration,native.catalog.configurations[configuration])
			var intact := unchanged_sources(original,current)
			if intact.is_empty(): return 1
			for entry: Dictionary in intact:
				if (not include_game and not Attach.no_game_sources(entry,native,configuration)) or entry in targets[configuration]:
					print("[source export] formal or duplicate source rejected: ",entry.path);return 1
			targets[configuration].append_array(intact)
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	# 只读导出不是允许修改正式楼：同时导出与原覆盖凭据同摘要的逐面期望。
	# 概括构建器仍拒绝 no_game_sources=false；后续仅可走完整无损与覆盖重认证。
	var formal: Dictionary=formal_expectations(input,native,output) if include_game else {}
	if include_game and formal.size()!=2: return 1
	var rows: Array=[]
	for configuration: String in targets:
		for entry: Dictionary in targets[configuration]:
			var row: Dictionary=native.pages[entry.path]
			var meshes := Boundary.meshes(row,row.components)
			if meshes.size()!=3: return 1
			var directory := output.path_join(configuration+"_"+entry.path.sha256_text())
			if DirAccess.make_dir_recursive_absolute(directory)!=OK: return 1
			var exports: Array=[]
			for kind in 3:
				var path := directory.path_join("layer_%d.res"%kind)
				if ResourceSaver.save(meshes[kind],path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
				var restored: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
				if not restored is ArrayMesh or not Join.conserved(meshes[kind],[restored]): return 1
				var attributes := path+".attributes"
				if preload("res://scripts/tests/tokyo_residential_preview.gd").export_attributes(restored,attributes)!=0: return 1
				exports.append({"path":attributes,"sha256":FileAccess.get_sha256(attributes),
					"faces":Count.triangles(restored),"mesh":{"path":path,"sha256":FileAccess.get_sha256(path)}})
			rows.append({"configuration":configuration,"target":entry.path,"identity":row.canonical_identity,
				"tree_sha256":var_to_bytes(entry).hex_encode().sha256_text(),"exports":exports,
				"no_game_sources":Attach.no_game_sources(entry,native,configuration),"current_tree_unchanged":true})
			print("[source export] ",configuration," identity=",row.canonical_identity," faces=",entry.triangles)
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"input_sha256":digest,"package_sha256":input.native_source_export.sha256,
		"catalog_sha256":native.catalog_sha,"source_paths":paths,"rows":rows,"formal_expectations":formal,"runtime_integrated":false},"\t"))
	file.close()
	return 0
