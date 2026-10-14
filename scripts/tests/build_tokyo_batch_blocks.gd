extends RefCounted
## 精确批次配方，批量复用已认可的块面保存器；不改变正式默认。
const Preview := preload("res://scripts/tests/tokyo_residential_preview.gd")
const Native := preload("res://scripts/tests/build_tokyo_northwest_blocks.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Guard := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")


static func run(root: String) -> int:
	if root.is_empty():
		return 1
	var progress_path := root.path_join("r340-batch-a/progress.json")
	var audit_path := root.path_join("r341-block-audit.json")
	if FileAccess.get_sha256(progress_path)!="c16f589ec0e11543c63240883f45608a46159217fde018e87ee8cd135067126c" or FileAccess.get_sha256(audit_path)!="229c3804b9c6322ec62da3114cc4c54667cc70d175301c1a5bc66f49a3ac21f4":
		return 1
	var progress: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(progress_path))
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(audit_path))
	var failures := 0
	for row: Dictionary in audit.rows:
		var binding: Dictionary = {}
		for source: Dictionary in progress.rows:
			if source.name == row.name and source.native_ready:
				binding=source
		if binding.is_empty():
			return 1
		var result := build_region(root,binding,row)
		failures+=int(result!=0)
		print("[Batch blocks] ",row.name," result=",result)
	return 1 if failures else 0


static func build_region(root: String, binding: Dictionary, audit: Dictionary) -> int:
	var name := str(binding.name)
	if name not in ["west","northwest","southwest","south"]:
		return 1
	var source := root.path_join("r340-"+name+"-native-a/index.res")
	var plan_path := root.path_join("r341-"+name+"-blocks-a/plan.json")
	var selection_path := root.path_join("r341-"+name+"-blocks-a/selection.json")
	var output := root.path_join("r342-"+name+"-blocks-native-a")
	if not Native.Builder.valid_sample_output(root.path_join("r340-"+name+"-source-a"),output) or FileAccess.get_sha256(source)!=binding.index_sha256 or FileAccess.get_sha256(plan_path)!=audit.plan_sha256 or FileAccess.get_sha256(selection_path)!=audit.selection_sha256:
		return 1
	return build_paths(source,plan_path,selection_path,output,int(binding.source_records),audit)


static func build_paths(source: String, plan_path: String, selection_path: String, output: String, source_records: int, audit: Dictionary) -> int:
	# 身份由调用配方先绑定；同一整层矩阵与逐格保存器供区域/全图共用。
	if source.is_empty() or plan_path.is_empty() or selection_path.is_empty() or source_records<=0 or not Native.Builder.valid_sample_output(source.get_base_dir(),output):
		return 1
	var passthrough: bool = audit.get("passthrough",false)==true
	if not passthrough and (int(audit.get("blocks",0))<=0 or int(audit.get("roof_faces",0))<=0 or int(audit.get("wall_faces",0))<=0):
		return 1
	var index: Resource = ResourceLoader.load(source,"",ResourceLoader.CACHE_MODE_IGNORE)
	if index==null or not index.valid() or index.source_count!=source_records:
		return 1
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	var selected: Array = JSON.parse_string(FileAccess.get_file_as_string(selection_path))
	if passthrough and (not Native.valid_passthrough(plan,selected,0,int(audit.get("blocks",-1)),int(audit.get("roof_faces",-1))+int(audit.get("wall_faces",-1))) or int(audit.get("selected_components",-1))!=0):
		return 1
	var region := Rect2(plan.region[0],plan.region[1],plan.region[2]-plan.region[0],plan.region[3]-plan.region[1])
	var bounds: Rect2 = index.bounds
	for entry: Dictionary in index.cells:
		bounds=bounds.merge(entry.content_bounds)
	var game := Guard.read_source()
	var protection: Dictionary = audit.get("gameplay_protection",{})
	if not Guard.preserved_merge_allowed(bounds,game,protection):
		print("[Batch blocks] gameplay protection rejected ",source)
		return 1
	if plan.variants.size()!=1 or float(plan.variants[0].radius)!=8.0 or plan.variants[0].blocks.size()!=int(audit.blocks):
		return 1
	var expected_faces := int(audit.roof_faces)+int(audit.wall_faces)
	if Count.triangles(Preview.blocks_mesh(plan.variants[0].blocks))!=expected_faces:
		return 1
	# 先对整层计算保留矩阵，再由共享保存器逐格验证同一计账。
	var rows: Array[Dictionary] = []
	for slot in 7:
		var inputs: Array[ArrayMesh] = []
		for entry: Dictionary in index.cells:
			var descriptor: Dictionary = entry.mid if slot==6 else entry.levels[slot]
			var page: Resource = ResourceLoader.load(descriptor.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if page==null or not page.valid() or page.triangles!=descriptor.triangles:
				return 1
			inputs.append(page.meshes[0])
		var joined := Join.join(inputs)
		if not Join.conserved(joined,inputs):
			return 1
		var kept := joined if passthrough else Preview.retained_mesh(joined,selected,region)
		if kept==null:
			return 1
		rows.append({"configuration":"mid4" if slot==6 else "lod%d_full" % slot,"original_faces":Count.triangles(joined),"kept_faces":Count.triangles(kept),"result_faces":Count.triangles(kept)+expected_faces})
	var result := Native.build_verified(index,source,plan_path,selection_path,output,region,{"rows":rows},int(audit.blocks),expected_faces,0)
	if result!=0 or protection.is_empty():
		return result
	var report_path := output.path_join("candidate_report.json")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	report["gameplay_protection"]=protection
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify(report))
	file.close()
	return 0
