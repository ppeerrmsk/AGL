extends RefCounted
## 离线保存并重载；运行时不读大JSON或生成网格。
static func run(source: String, output: String) -> int:
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:
		return 1
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
	if not data is Dictionary or data.get("schema",0)!=2 or data.get("candidates",[]).size()!=3:
		return 1
	var rows: Array = []
	for i in 3:
		var mesh := preload("res://scripts/experiments/tokyo_shoreline_candidate.gd").build(data.candidates[i])
		if mesh==null or float(data.candidates[i].width)!=[2.0,1.0,.35][i]:
			return 1
		var path := output.path_join("shore_%d.res"%i)
		if ResourceSaver.save(mesh,path)!=OK:
			return 1
		var copy: ArrayMesh = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if copy==null or var_to_bytes(copy.surface_get_arrays(0))!=var_to_bytes(mesh.surface_get_arrays(0)):
			return 1
		rows.append({"file":"shore_%d.res"%i,"sha256":FileAccess.get_sha256(path),"faces":mesh.surface_get_array_len(0)/3,"width":data.candidates[i].width})
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema":1,"source_sha":FileAccess.get_sha256(source),"meshes":rows},"\t"))
	file.close()
	print("[R99 shoreline bake] ",rows)
	return 0
