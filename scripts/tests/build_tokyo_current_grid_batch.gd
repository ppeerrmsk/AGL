extends RefCounted
## 完整当前叶按固定格无损分桶；分批制作，不按相机删面，不复制整图常驻。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Check := preload("res://scripts/tests/build_tokyo_full_native_leaves.gd")


static func run_series(input: Dictionary) -> int:
	var jobs: Variant=input.get("current_grid_series")
	if not jobs is Array or jobs.is_empty() or jobs.size()>8: return 1
	for job: Variant in jobs:
		if not job is Dictionary: return 1
		var request: Dictionary=job.duplicate()
		request["current_grid_batch"]=input.get("snapshot")
		if run(request)!=0: return 1
	return 0


static func run(input: Dictionary) -> int:
	var binding: Variant=input.get("current_grid_batch")
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var configuration: String=input.get("configuration","")
	var first: Variant=input.get("first")
	var count: Variant=input.get("count")
	var output: String=input.get("output","")
	var ground_only: bool=input.get("ground_only",false)
	var layers: Array[int]=[0,1]
	if ground_only:layers.assign([2])
	if configuration not in ["lod4_full","lod5_full"] or not Contract.integer(first,0) or not Contract.integer(count,1,256): return 1
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var file := FileAccess.open(binding.path,FileAccess.READ)
	if file==null: return 1
	var snapshot: Variant=file.get_var(false)
	file.close()
	if not snapshot is Dictionary or snapshot.get("schema")!=1 or not snapshot.get("configurations") is Dictionary: return 1
	var config: Dictionary=snapshot.configurations[configuration]
	if int(first)+int(count)>config.leaves.size(): return 1
	var source_costs: Dictionary={}
	var nodes: Array=config.roots.duplicate()
	while not nodes.is_empty():
		var entry: Dictionary=nodes.pop_back()
		if entry.get("children",[]).is_empty():
			var cost := 0
			for layer: int in layers:cost+=int(entry.triangles[layer])
			source_costs[entry.path]=cost
		else: nodes.append_array(entry.children)
	var leaf_face_costs: Array[int]=[]
	for key: String in config.leaves:
		if not source_costs.has(key): return 1
		leaf_face_costs.append(source_costs[key])
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var rows: Array=[]
	var total_faces := 0
	var total_bytes := 0
	var started := Time.get_ticks_msec()
	for index in range(int(first),int(first)+int(count)):
		var key: String=config.leaves[index]
		var page: Dictionary=snapshot.pages[key]
		var loaded: Dictionary={}
		for path: String in page.components:
			if FileAccess.get_sha256(path)!=page.components[path].sha256: return 1
			loaded[path]=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var assembled := preload("res://scripts/rendering/tokyo_component_page.gd").assemble(page,loaded)
		if assembled==null: return 1
		for layer: int in layers:
			var mesh: ArrayMesh=assembled.meshes[layer]
			var centers := Split.centers(mesh)
			if centers.is_empty(): continue
			var cell_ids: Dictionary={}
			var cells: Array[Vector2i]=[]
			var owners := PackedInt32Array()
			for center: Vector2 in centers:
				var cell := Vector2i(floori(center.x/512.0),floori(center.y/512.0))
				if not cell_ids.has(cell):
					cell_ids[cell]=cells.size();cells.append(cell)
				owners.append(cell_ids[cell])
			var pieces := Split.partition(mesh,owners,cells.size())
			if pieces.size()!=cells.size() or not Check.conserved(mesh,pieces,owners): return 1
			var restored: Array[ArrayMesh]=[]
			var outputs: Array=[]
			for part in pieces.size():
				var piece: ArrayMesh=pieces[part]
				var component := Component.new()
				component.source_hash=var_to_bytes([binding.sha256,key,layer,cells[part],Packed.corner_digest(piece)]).hex_encode().sha256_text()
				component.geometry_bytes=Packed.decoded_bytes(piece)
				component.mesh_bytes=PackedInt32Array([component.geometry_bytes]);component.meshes=[piece]
				var path := output.path_join("leaf_%04d_layer%d_cell%d_%d.res" % [index,layer,cells[part].x,cells[part].y])
				if not component.valid() or ResourceSaver.save(component,path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
				var copy: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
				if not copy is Component or not copy.valid() or copy.stream_identity()!=component.stream_identity(): return 1
				restored.append(copy.meshes[0])
				total_bytes+=component.geometry_bytes
				outputs.append({"cell":cells[part],"path":path,"sha256":FileAccess.get_sha256(path),"bytes":component.geometry_bytes,
					"canonical_identity":component.stream_identity(),"box":piece.get_aabb()})
			if not Check.conserved(mesh,restored,owners): return 1
			total_faces+=owners.size()
			rows.append({"source":key,"leaf_index":index,"layer":layer,"source_components":page.components,
				"game_sources":page.get("game_sources",[]),"owners":owners,"cells":cells,"components":outputs})
		if (index-int(first)+1)%16==0: print("[Tokyo current grid] leaves=",index-int(first)+1,"/",count," faces=",total_faces)
	var result := {"schema":1,"snapshot":binding,"configuration":configuration,"first":int(first),"count":int(count),"leaf_face_costs":leaf_face_costs,
		"grid_world":512.0,"rows":rows,"faces":total_faces,"bytes":total_bytes,"elapsed_ms":Time.get_ticks_msec()-started,
		"geometry_roundtrip_verified":true,"runtime_integrated":false,"ground_integrated":false,"layers":layers}
	var path := output.path_join("batch.bin")
	file=FileAccess.open(path,FileAccess.WRITE)
	if file==null: return 1
	file.store_var(result,false);file.close()
	file=FileAccess.open(path,FileAccess.READ)
	if file==null: return 1
	var readback: Variant=file.get_var(false)
	file.close()
	if readback!=result: return 1
	file=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	var summary := result.duplicate()
	summary.erase("rows");summary["batch"]={"path":path,"sha256":FileAccess.get_sha256(path)}
	file.store_string(JSON.stringify(summary,"\t"));file.close()
	print("[Tokyo current grid] saved_readback=true faces=",total_faces," elapsed_ms=",result.elapsed_ms)
	return 0
