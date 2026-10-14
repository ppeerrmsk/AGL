extends RefCounted
const Native := preload("res://scripts/rendering/tokyo_grid_native.gd")
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Check := preload("res://scripts/tests/build_tokyo_full_native_leaves.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Detail := preload("res://scripts/rendering/tokyo_grid_detail.gd")


static func run(input: Dictionary) -> int:
	var binding: Dictionary=input.get("build_grid_detail",{})
	var dependencies: Variant=Native.read_bound(binding)
	if not dependencies is Dictionary: return 1
	var snapshot: Variant=Native.read_bound(dependencies.snapshot)
	if not snapshot is Dictionary or FileAccess.get_sha256(snapshot.package.path)!=snapshot.package.sha256: return 1
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(snapshot.package.path))
	package.native["grid_candidate"]=binding
	var native := Native.new()
	if not native.read(package.native): return 1
	var requested: Dictionary={}
	if input.has("minimum_faces"):
		if not Native.Contract.integer(input.minimum_faces,4096): return 1
		# 按认证全图成本选重片，不围绕某一相机补丁；轻片保留既有资源。
		for key: String in native._grid_fine:
			for kind in 2:
				for view: Dictionary in native._grid_fine[key][kind]:
					if int(view.faces)>=int(input.minimum_faces): requested[view.components.keys()[0]]=true
	else:
		var report_binding: Dictionary=input.get("cost_report",{})
		if not Native.Contract.binding(report_binding) or FileAccess.get_sha256(report_binding.path)!=report_binding.sha256: return 1
		var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report_binding.path))
		for row: Dictionary in report.visible_component_costs: requested[row.path]=true
	if requested.is_empty() or requested.size()>4096: return 1
	print("[Tokyo grid detail] planned parents=",requested.size())
	var output: String=input.get("output","")
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var parents: Dictionary={}
	var children_count := 0
	for key: String in native._grid_fine:
		for kind in 2:
			for view: Dictionary in native._grid_fine[key][kind]:
				var path: String=view.components.keys()[0]
				if not requested.has(path): continue
				var source: Dictionary=view.components[path]
				if FileAccess.get_sha256(path)!=source.sha256: return 1
				var component: Resource=load(path)
				if not component is Component or not component.valid() or component.stream_identity()!=source.canonical_identity: return 1
				var mesh: ArrayMesh=component.meshes[0]
				var ids: Dictionary={}
				var owners := PackedInt32Array()
				for point: Vector2 in Split.centers(mesh):
					var cell := Vector2i(floori(point.x/256.0),floori(point.y/256.0))
					if not ids.has(cell): ids[cell]=ids.size()
					owners.append(int(ids[cell]))
				var pieces := Split.partition(mesh,owners,ids.size())
				if pieces.size()!=ids.size() or not Check.conserved(mesh,pieces,owners): return 1
				var children: Array=[]
				var restored: Array[ArrayMesh]=[]
				for n in pieces.size():
					var child := Component.new()
					child.source_hash=var_to_bytes([source.sha256,256,n,Packed.corner_digest(pieces[n])]).hex_encode().sha256_text()
					child.geometry_bytes=Packed.decoded_bytes(pieces[n]);child.mesh_bytes=PackedInt32Array([child.geometry_bytes]);child.meshes=[pieces[n]]
					var target := output.path_join("part_%03d_%03d.res" % [parents.size(),n])
					if not child.valid() or ResourceSaver.save(child,target,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
					var copy: Resource=ResourceLoader.load(target,"",ResourceLoader.CACHE_MODE_IGNORE)
					if not copy is Component or not copy.valid() or copy.stream_identity()!=child.stream_identity(): return 1
					restored.append(copy.meshes[0]);children_count+=1
					children.append({"binding":{"path":target,"sha256":FileAccess.get_sha256(target),"bytes":child.geometry_bytes,"canonical_identity":child.stream_identity()},"box":pieces[n].get_aabb(),"faces":preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(pieces[n])})
				if not Check.conserved(mesh,restored,owners): return 1
				parents[path]={"binding":source,"faces":view.faces,"box":view.box,"layer":kind,"children":children}
	if parents.size()!=requested.size(): return 1
	var data := {"schema":1,"grid":binding,"grid_world":256.0,"parents":parents,"roundtrip_verified":true}
	if Detail.expand(native._grid_fine,native._grid_refined_data,data,binding).is_empty(): return 1
	# 错父身份、重复子片、总面数篡改必须拒绝。
	for field: String in ["identity","duplicate","faces"]:
		var bad := data.duplicate(true)
		var parent: Dictionary=bad.parents.values()[0]
		if field=="identity": parent.binding.sha256="0".repeat(64)
		elif field=="duplicate": parent.children.append(parent.children[0])
		else: parent.children[0].faces+=1
		if not Detail.expand(native._grid_fine,native._grid_refined_data,bad,binding).is_empty(): return 1
	var file := FileAccess.open(output.path_join("detail.bin"),FileAccess.WRITE)
	if file==null: return 1
	file.store_var(data,false);file.close()
	var result := {"path":output.path_join("detail.bin"),"sha256":FileAccess.get_sha256(output.path_join("detail.bin"))}
	if Native.read_bound(result)!=data: return 1
	file=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"detail":result,"parents":parents.size(),"children":children_count,"roundtrip_verified":true,"negative_checks":3,"runtime_verified":false},"\t"));file.close()
	print("[Tokyo grid detail] parents=",parents.size()," children=",children_count," roundtrip_verified=true")
	return 0
