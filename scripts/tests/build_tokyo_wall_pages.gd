extends RefCounted
## 按真实目录页持有屋顶/墙，避免全区墙与局部切面各自退役。
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Components := preload("res://scripts/tests/build_tokyo_mesh_components.gd")
const Cross := preload("res://scripts/tests/build_tokyo_cross_lod_components.gd")
const Manifest := preload("res://scripts/rendering/tokyo_component_manifest.gd")
const CATALOG_SHA := "1599032b993a21cf1f733b39408a462f84ff0504664744cc92e0954e05344452"
const NORTH_CATALOG_SHA := "bccdd77db85e42d9ac258b9ca6497557fcb34b1e5ac3703fb805fd541099b827"
var _pages: Dictionary = {}
var _physical: Dictionary = {}
var _output := ""


func visit(entry: Dictionary, roofs: ArrayMesh, walls: ArrayMesh, components: Dictionary) -> bool:
	if FileAccess.get_sha256(entry.path) != entry.sha256:
		return false
	var full: Resource = ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if full == null or not full.valid() or not Join.conserved(full.meshes[0],[roofs,walls]):
		return false
	var roof_faces := Split.centers(roofs).size()
	var wall_faces := Split.centers(walls).size()
	var original: Dictionary = components[entry.path]
	var row := {"canonical_identity":full.stream_identity(),"full_low_bounds":full.meshes[0].get_aabb(),
		"full_low_faces":int(entry.triangles[0]),"roof_faces":roof_faces,"wall_faces":wall_faces,
		"original_low":original.mapping[0],"original_low_bytes":original.components[original.mapping[0][0]].bytes,
		"children":PackedStringArray(),"cuts":entry.get("cuts",PackedFloat32Array())}
	if row.full_low_faces != roof_faces + wall_faces:
		return false
	if wall_faces > 0:
		var key := (Cross.mesh_key(roofs,0)+Cross.mesh_key(walls,0)).sha256_text()
		var path := _output.path_join("components/"+key+".res")
		if not _physical.has(path):
			# 保存双槽组件不能留下指向临时屋顶res的外部依赖。
			var saved := Components._save([roofs.duplicate(true),walls.duplicate(true)],key,path)
			if saved.is_empty():
				return false
			_physical[path] = saved
		var reloaded: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if reloaded == null or not reloaded.valid() or not Join.conserved(full.meshes[0],reloaded.meshes):
			return false
		row["component"] = path
		row["split_bytes"] = _physical[path].bytes
	else:
		# 不为无墙页增加节点、资源或运行时分支；接线时直接复用原逻辑页。
		row["component"] = ""
		row["split_bytes"] = row.original_low_bytes
	_pages[entry.path] = row
	var children: Array = entry.get("children",[])
	if not children.is_empty():
		if children.size() != 4:
			return false
		var roof_parts := Split.split(roofs,entry.cuts)
		var wall_parts := Split.split(walls,entry.cuts)
		if not Join.conserved(roofs,roof_parts) or not Join.conserved(walls,wall_parts):
			return false
		var child_wall_faces := 0
		for index in 4:
			if not visit(children[index],roof_parts[index],wall_parts[index],components):
				return false
			row.children.append(children[index].path)
			child_wall_faces += int(_pages[children[index].path].wall_faces)
		if child_wall_faces != wall_faces:
			return false
	return true


func run(root: String, output: String) -> int:
	var north := OS.get_environment("AGL_TOKYO_WALL_PAGES_NORTH")=="1"
	var northwest := OS.get_environment("AGL_TOKYO_WALL_PAGES_NORTHWEST")=="1"
	var directory := "r193-native-full-a" if north else "r185-native-full-a"
	var catalog_sha := NORTH_CATALOG_SHA if north else CATALOG_SHA
	var catalog_path := root.path_join("r185-native-full-a/catalog.res")
	var bundle_path := root.path_join("r185-wall-bundle-a/report.json")
	var bundle_sha := "a95f8a4c300f62b3f49f7cbcb697279ad960c7043fcfc4357ad9f437ce327156"
	var full_sha := "73595e06940db7984160e9951abae4c8821be5f4f05cb26a4e7be73ef4599843"
	var wall_faces := 2689
	if north:
		catalog_path=root.path_join(directory+"/catalog.res")
		bundle_path=root.path_join("r192-wall-bundle-a/report.json")
		bundle_sha="779d01fdc1f3545d5140fdb92ab65f62c60350c1f0c32eae1bf22bc477bf0973"
		full_sha="8275da392426de266fead17981c0be7d3e094267d5e785751b91d695e35bd044"
		wall_faces=3313
	if northwest:
		directory="r204-northwest-catalog-a"
		catalog_path=root.path_join(directory+"/catalog.res")
		catalog_sha=preload("res://scripts/tests/build_tokyo_northwest_walls.gd").CATALOG_SHA
		bundle_path=root.path_join("r205-wall-bundle-a/report.json")
		bundle_sha="26d5bd721176ff1ba8d954230995614251351a3b39e77ac688b550a5f5dc439c"
		wall_faces=5287
		if OS.get_environment("AGL_TOKYO_NORTHWEST_COMBINED")=="1":
			directory="r212-northwest-catalog-a"
			catalog_path=root.path_join(directory+"/catalog.res")
			catalog_sha=preload("res://scripts/tests/build_tokyo_northwest_walls.gd").COMBINED_CATALOG_SHA
			bundle_path=root.path_join("r213-wall-bundle-a/report.json")
			bundle_sha="7027fd6a4a96432936aee8833bc2146d17ba4496c672533418e1f9705725729b"
			wall_faces=8645
	if not Components.Builder.valid_sample_output(root.path_join(directory),output) or FileAccess.get_sha256(catalog_path) != catalog_sha or FileAccess.get_sha256(bundle_path) != bundle_sha:
		return 1
	var catalog: Resource = load(catalog_path)
	if catalog == null or not catalog.valid():
		return 1
	var source_manifest := Manifest.read(root.path_join(directory+"/components/manifest.bin"),catalog,catalog_sha)
	var bundle: Variant = JSON.parse_string(FileAccess.get_file_as_string(bundle_path))
	if source_manifest.is_empty() or not bundle is Dictionary or not bundle.get("partition_proven",false):
		return 1
	if (northwest and bundle.get("catalog_sha256")!=catalog_sha) or (not northwest and bundle.get("full_report_sha256")!=full_sha):
		return 1
	if FileAccess.get_sha256(bundle.walls.path) != bundle.walls.sha256 or bundle.rows.size() != 11:
		return 1
	var walls: ArrayMesh = load(bundle.walls.path)
	if walls == null or Split.centers(walls).size() != wall_faces:
		return 1
	_output = output
	_pages.clear()
	_physical.clear()
	DirAccess.make_dir_recursive_absolute(output.path_join("components"))
	var configurations: Dictionary = {}
	for item: Dictionary in bundle.rows:
		var name: String = item.configuration
		if configurations.has(name) or not catalog.configurations.has(name) or FileAccess.get_sha256(item.roofs.path) != item.roofs.sha256:
			return 1
		var roofs: ArrayMesh = load(item.roofs.path)
		if roofs == null or not visit(catalog.configurations[name][11],roofs,walls,source_manifest.pages):
			return 1
		configurations[name] = catalog.configurations[name][11].path
		print("[R186 wall pages] ",name," partition/reload/cuts=true")
	var affected := 0
	var physical_bytes := 0
	for row: Dictionary in _pages.values():
		affected += int(row.wall_faces > 0)
	for descriptor: Dictionary in _physical.values():
		physical_bytes += int(descriptor.bytes)
	var manifest := {"schema":1,"catalog_sha256":catalog_sha,"bundle_sha256":FileAccess.get_sha256(bundle_path),
		"pages":_pages,"physical":_physical,"configurations":configurations,
		"requires_atomic_wall_owner":true,"runtime_integrated":false}
	var file := FileAccess.open(output.path_join("manifest.bin"),FileAccess.WRITE)
	if file == null:
		return 1
	file.store_var(manifest,false)
	file.close()
	file = FileAccess.open(output.path_join("manifest.bin"),FileAccess.READ)
	if file == null or file.get_var(false) != manifest:
		return 1
	file.close()
	file = FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify({"pages":_pages.size(),"affected_pages":affected,"physical_components":_physical.size(),
		"physical_bytes":physical_bytes,"manifest_sha256":FileAccess.get_sha256(output.path_join("manifest.bin")),
		"partition_and_reload_proven":true,"runtime_integrated":false},"  "))
	file.close()
	print("[R186 wall pages] pages=",_pages.size()," affected=",affected," physical=",_physical.size()," bytes=",physical_bytes)
	return 0


static func cut_cost(paths: PackedStringArray, manifest: Dictionary, split: bool) -> Dictionary:
	var costs: Dictionary = {}
	for path: String in paths:
		var row: Dictionary = manifest.pages[path]
		var key: String = row.component if split and not row.component.is_empty() else row.original_low[0]
		var amount: int = row.split_bytes if split else row.original_low_bytes
		if costs.has(key) and int(costs[key]) != amount:
			return {}
		costs[key] = amount
	var total := 0
	for amount: int in costs.values():
		total += amount
	return {"bytes":total,"physical":costs.size()}


static func audit(input: String, output: String) -> int:
	var north := OS.get_environment("AGL_TOKYO_WALL_PAGES_NORTH")=="1"
	var catalog_sha := NORTH_CATALOG_SHA if north else CATALOG_SHA
	var expected_walls := 3313 if north else 2689
	if OS.get_environment("AGL_TOKYO_WALL_PAGES_NORTHWEST")=="1":
		catalog_sha=preload("res://scripts/tests/build_tokyo_northwest_walls.gd").CATALOG_SHA
		expected_walls=5287
		if OS.get_environment("AGL_TOKYO_NORTHWEST_COMBINED")=="1":
			catalog_sha=preload("res://scripts/tests/build_tokyo_northwest_walls.gd").COMBINED_CATALOG_SHA
			expected_walls=8645
	if FileAccess.file_exists(output):
		return 1
	var file := FileAccess.open(input,FileAccess.READ)
	if file == null:
		return 1
	var manifest: Variant = file.get_var(false)
	file.close()
	if not manifest is Dictionary or manifest.get("catalog_sha256") != catalog_sha:
		return 1
	var rows: Array = []
	var cuts: Array[PackedStringArray] = []
	for configuration: String in manifest.configurations:
		var paths := PackedStringArray([manifest.configurations[configuration]])
		var depth := 0
		while not paths.is_empty():
			var next := PackedStringArray()
			var walls := 0
			var wall_nodes := 0
			for path: String in paths:
				var page: Dictionary = manifest.pages[path]
				next.append_array(page.children)
				walls += int(page.wall_faces)
				wall_nodes += int(page.wall_faces > 0)
			if walls != expected_walls or depth > 2:
				return 1
			rows.append({"configuration":configuration,"depth":depth,"pages":paths.size(),"wall_faces":walls,
				"extra_wall_nodes":wall_nodes,"before":cut_cost(paths,manifest,false),"paired":cut_cost(paths,manifest,true)})
			cuts.append(paths)
			paths = next
			depth += 1
	var union_rows: Array = []
	for a in cuts.size():
		for b in range(a,cuts.size()):
			var paths := cuts[a].duplicate()
			paths.append_array(cuts[b])
			union_rows.append({"a":a,"b":b,"before":cut_cost(paths,manifest,false),"paired":cut_cost(paths,manifest,true)})
	file = FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify({"manifest_sha256":FileAccess.get_sha256(input),"cuts":rows,"unions":union_rows,
		"scope":"parent11 low layer only; no full-map runtime or frame-time proof","fail":0},"  "))
	file.close()
	print("[R186 cut budget] cuts=",cuts.size()," unions=",union_rows.size()," wall faces conserved=",expected_walls)
	return 0
