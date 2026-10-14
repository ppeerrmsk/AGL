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


static func run(input: Dictionary, digest: String) -> int:
	var package := Override.json_binding(input.get("native_source_export"))
	var output: String=input.get("output","")
	var paths: Variant=input.get("source_paths")
	if package.is_empty() or not paths is Array or paths.size()>32 \
		or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.get("native",{})): return 1
	var source := common_source(native.catalog.configurations.lod5_full,paths)
	if source.is_empty(): return 1
	var identity: Dictionary=native.pages[source.path].canonical_identity
	print("[source export] common source=",identity)
	var targets: Dictionary={}
	# 跨LOD只配对同一树位置；level/source/owners本来随档位变化，各自完整摘要仍独立绑定。
	for configuration in ["lod4_full","lod5_full"]:
		var target := ""
		for key: String in native.pages:
			var actual: Dictionary=native.pages[key].canonical_identity
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
			if not Attach.no_game_sources(entry,native,configuration):
				print("[source export] formal source rejected: ",entry.path);return 1
		targets[configuration]=intact
		print("[source export] preserved prior replacements; intact branches=",intact.size()," ",configuration)
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
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
				"no_game_sources":true,"current_tree_unchanged":true})
			print("[source export] ",configuration," identity=",row.canonical_identity," faces=",entry.triangles)
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"input_sha256":digest,"package_sha256":input.native_source_export.sha256,
		"catalog_sha256":native.catalog_sha,"source_paths":paths,"rows":rows,"runtime_integrated":false},"\t"))
	file.close()
	return 0
