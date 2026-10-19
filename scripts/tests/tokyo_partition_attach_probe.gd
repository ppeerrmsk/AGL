extends RefCounted
## 接合前回读正式组件；不凭地理范围或旧覆盖摘要宣称新分区已认证。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Assembly := preload("res://scripts/rendering/tokyo_component_page.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")


static func find_entry(entries: Array, path: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.path==path: return entry
		var found := find_entry(entry.children,path)
		if not found.is_empty(): return found
	return {}


static func no_game_sources(entry: Dictionary, native: RefCounted, configuration: String) -> bool:
	var row: Dictionary=native.coverage[configuration].pages[entry.path]
	if not row.tokens[0].is_empty() or not row.tokens[1].is_empty(): return false
	if not native.pages[entry.path].game_sources.is_empty(): return false
	for child: Dictionary in entry.children:
		if not no_game_sources(child,native,configuration): return false
	return true


static func run(input: Dictionary, digest: String) -> int:
	if not input.get("attach_native") is Dictionary or not input.get("attachments") is Array: return 1
	var output: String=input.get("output","")
	if not output.is_absolute_path() or FileAccess.file_exists(output): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(input.attach_native): return 1
	var rows: Array=[]
	var export_root: String=input.get("export_actual","")
	if not export_root.is_empty():
		if not export_root.is_absolute_path() or DirAccess.dir_exists_absolute(export_root): return 1
		if DirAccess.make_dir_recursive_absolute(export_root)!=OK: return 1
	for request: Dictionary in input.attachments:
		var configuration: String=request.get("configuration","")
		var target := ""
		for path: String in native.pages:
			var identity: Dictionary=native.pages[path].canonical_identity
			if identity.configuration==configuration and identity.parent==2 and identity.cell==97 and identity.ancestor==8:
				if not target.is_empty(): return 1
				target=path
		if target.is_empty(): return 1
		var entry := find_entry(native.catalog.configurations[configuration],target)
		if entry.is_empty(): return 1
		var loaded: Dictionary={}
		for key: String in native.pages[target].components:
			var binding: Dictionary=native.pages[target].components[key]
			if FileAccess.get_sha256(key)!=binding.sha256: return 1
			loaded[key]=ResourceLoader.load(key,"",ResourceLoader.CACHE_MODE_IGNORE)
		var page := Assembly.assemble(native.pages[target],loaded)
		if page==null or not request.get("original_layers") is Array or request.original_layers.size()!=3: return 1
		var matches: Array=[]
		var faces: Array=[]
		var exports: Array=[]
		if not export_root.is_empty() and DirAccess.make_dir_recursive_absolute(export_root.path_join(configuration))!=OK: return 1
		for kind in 3:
			var binding: Dictionary=request.original_layers[kind]
			if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
			var original: Resource=ResourceLoader.load(binding.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if not original is ArrayMesh: return 1
			matches.append(Join.conserved(page.meshes[kind],[original]))
			faces.append([Count.triangles(page.meshes[kind]),Count.triangles(original)])
			if not export_root.is_empty():
				var mesh_path := export_root.path_join(configuration).path_join("layer_%d.res"%kind)
				var attributes_path := mesh_path+".attributes"
				if ResourceSaver.save(page.meshes[kind],mesh_path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
				var restored: Resource=ResourceLoader.load(mesh_path,"",ResourceLoader.CACHE_MODE_IGNORE)
				if not restored is ArrayMesh or not Join.conserved(page.meshes[kind],[restored]): return 1
				if preload("res://scripts/tests/tokyo_residential_preview.gd").export_attributes(restored,attributes_path)!=0: return 1
				exports.append({"path":attributes_path,"sha256":FileAccess.get_sha256(attributes_path),
					"mesh":{"path":mesh_path,"sha256":FileAccess.get_sha256(mesh_path)}})
		rows.append({"configuration":configuration,"target":target,"identity":native.pages[target].canonical_identity,
			"tree_sha256":var_to_bytes(entry).hex_encode().sha256_text(),"original_layers_equal":matches,"faces":faces,
			"no_game_sources":no_game_sources(entry,native,configuration),"exports":exports})
		if request.has("partition"):
			var binding: Dictionary=request.partition
			if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
			var partition_file := FileAccess.open(binding.path,FileAccess.READ)
			if partition_file==null: return 1
			var partition: Variant=partition_file.get_var(false)
			partition_file.close()
			if not partition is Dictionary: return 1
			var normalizer := preload("res://scripts/rendering/tokyo_partition_catalog.gd")
			var normalized := normalizer.normalize(partition,binding)
			if normalized.is_empty(): return 1
			var parts: Dictionary={}
			for layer: Dictionary in normalized.pages[normalized.tree.path].components.values():
				if FileAccess.get_sha256(layer.path)!=layer.sha256: return 1
				parts[layer.path]=ResourceLoader.load(layer.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var candidate := Assembly.assemble(normalized.pages[normalized.tree.path],parts)
			if candidate==null: return 1
			rows[-1]["untouched_layers_equal"]=[Join.conserved(page.meshes[0],[candidate.meshes[0]]),Join.conserved(page.meshes[2],[candidate.meshes[2]])]
			var roots := normalizer.replace(native.catalog.configurations[configuration],target,normalized.tree)
			rows[-1]["full_map_cuts"]=cuts(roots,input.poses,binding.sha256)
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"input_sha256":digest,"catalog_sha256":native.catalog_sha,"rows":rows,"runtime_integrated":false},"\t"))
	file.close()
	for row: Dictionary in rows:
		if false in row.original_layers_equal or not row.no_game_sources: return 1
		if row.has("untouched_layers_equal"):
			if false in row.untouched_layers_equal: return 1
			for cut: Dictionary in row.full_map_cuts:
				if not cut.within_budget or cut.new_pages==0: return 1
	return 0


static func cuts(roots: Array[Dictionary], poses: Array, partition_sha: String) -> Array:
	var result: Array=[]
	var projection := preload("res://scripts/experiments/volume_projection.gd")
	for pose: Dictionary in poses:
		var size := Vector2(1600,900)
		var canvas := Transform2D(float(pose.rotation),Vector2.ZERO).scaled(Vector2.ONE*float(pose.scale))
		canvas.origin=size*.5-canvas*Vector2(pose.center[0],pose.center[1])
		var inverse := canvas.affine_inverse()
		var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
		for corner in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*corner)
		var ray := projection.ground_basis(canvas,deg_to_rad(38)).inverse()*projection.camera_basis(canvas,deg_to_rad(38)).z
		var cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd").choose(roots,view,canvas,size,-Vector2(ray.x,ray.z)/ray.y,Vector2.ZERO,16)
		var new_pages := 0
		for entry: Dictionary in cut.entries: new_pages+=int(entry.path.begins_with(partition_sha+":"))
		result.append({"pose":pose,"faces":cut.triangles,"bytes":cut.bytes,"pages":cut.active,"within_budget":cut.within_budget,"new_pages":new_pages})
	return result
