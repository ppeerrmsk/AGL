extends RefCounted
## 固定格离线资源制作；复用正式地表平面与既有网格导入，不授予覆盖资格。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Reader := preload("res://scripts/tests/tokyo_tagged_low_cut_review.gd")
const Ground := preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd")


static func run(input: Dictionary) -> int:
	var binding: Variant=input.get("grid_resources")
	var building_binding: Variant=input.get("buildings")
	for item: Variant in [binding,building_binding]:
		if not Contract.binding(item) or FileAccess.get_sha256(item.path)!=item.sha256: return 1
	var ground: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var buildings: Variant=JSON.parse_string(FileAccess.get_file_as_string(building_binding.path))
	if not ground is Dictionary or not buildings is Dictionary: return 1
	if ground.get("building_grid_sha256")!=building_binding.sha256: return 1
	if not ground.get("rows") is Array or not buildings.get("rows") is Array: return 1
	var output: String=input.get("output","")
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var rows: Array=[]
	for row: Dictionary in buildings.rows:
		var mesh := Reader.mesh(row)
		if mesh==null: return 1
		var path := output.path_join("building_%03d.res" % rows.size())
		if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
		var restored: ArrayMesh=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var originals: Array[ArrayMesh]=[mesh]
		if restored==null or not preload("res://scripts/experiments/tokyo_packed_mesh_join.gd").conserved(restored,originals): return 1
		rows.append({"path":path,"sha256":FileAccess.get_sha256(path),"cell":row.cell,"layer":row.layer,"faces":row.faces})
	var surfaces: Array=[]
	for row: Dictionary in ground.rows:
		if not Contract.numbers(row.get("footprint"),4) or not Contract.numbers(row.get("uv_bounds"),4): return 1
		var b: Array=row.footprint
		var u: Array=row.uv_bounds
		var mesh := Ground.plane(Rect2(b[0],b[1],b[2]-b[0],b[3]-b[1]),Rect2(u[0],u[1],u[2]-u[0],u[3]-u[1]))
		var path := output.path_join("ground_%03d.res" % surfaces.size())
		if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
		var restored: ArrayMesh=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if restored==null or restored.get_surface_count()!=1: return 1
		var before := mesh.surface_get_arrays(0)
		var after := restored.surface_get_arrays(0)
		for channel: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_INDEX]:
			if before[channel]!=after[channel]: return 1
		var saved := row.duplicate(true)
		saved["mesh"]={"path":path,"sha256":FileAccess.get_sha256(path)}
		surfaces.append(saved)
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"schema":1,"candidate_only":true,"runtime_integrated":false,"visual_accepted":false,
		"source_ground":binding,"source_buildings":building_binding,"buildings":rows,"ground_surfaces":surfaces,
		"saved_readback":true,"whole_map_complete":false},"\t"))
	file.close()
	print("[Tokyo grid resources] buildings=%d ground_surfaces=%d saved_readback=true" % [rows.size(),surfaces.size()])
	return 0
