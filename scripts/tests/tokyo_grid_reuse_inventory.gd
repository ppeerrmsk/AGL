extends RefCounted
## 复用已保存的格网产物，不将另一来源的面数守恒移植为正式来源资格。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")

static func run(input: Dictionary) -> int:
	var binding: Dictionary=input.grid_reuse_inventory
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var file := FileAccess.open(binding.path,FileAccess.READ)
	if file==null:return 1
	var source: Dictionary=file.get_var(false);file.close()
	var config: String=input.configuration
	if not source.configurations.has(config):return 1
	var tree_rows: Dictionary={};var stack: Array=source.configurations[config].roots.duplicate()
	while not stack.is_empty():
		var node: Dictionary=stack.pop_back()
		if not node.get("children",[]).is_empty():stack.append_array(node.children)
		else:tree_rows[node.path]=node
	var candidates: Dictionary={};var batches: Array=[];var checked_paths: Dictionary={}
	var directories := DirAccess.get_directories_at(input.batch_root)
	directories.sort()
	for directory: String in directories:
		if not directory.begins_with("tokyo-current-grid-lod5-"):continue
		var report_path: String=input.batch_root.path_join(directory).path_join("report.json")
		if not FileAccess.file_exists(report_path):continue
		var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report_path))
		if report.get("configuration")!=config or not report.get("geometry_roundtrip_verified",false):continue
		var batch_binding: Dictionary=report.batch
		if FileAccess.get_sha256(batch_binding.path)!=batch_binding.sha256:return 1
		file=FileAccess.open(batch_binding.path,FileAccess.READ)
		if file==null:return 1
		var batch: Dictionary=file.get_var(false);file.close()
		if batch.get("configuration")!=config or not batch.get("geometry_roundtrip_verified",false) or batch.get("grid_world")!=512.0:return 1
		batches.append(batch_binding)
		for row: Dictionary in batch.rows:
			if not tree_rows.has(row.source):continue
			if row.source_components!=source.pages[row.source].components:continue
			var layer := int(row.layer)
			if layer not in [0,1]:return 1
			if row.owners.size()!=int(tree_rows[row.source].triangles[layer]):return 1
			var key: String=row.source+"#"+str(layer)
			if candidates.has(key):return 1
			for component: Dictionary in row.components:
				if checked_paths.has(component.path):
					if checked_paths[component.path]!=component.sha256:return 1
				else:
					if FileAccess.get_sha256(component.path)!=component.sha256:return 1
					checked_paths[component.path]=component.sha256
			candidates[key]={"batch":batch_binding,"source":row.source,"layer":layer,"faces":row.owners.size(),"components":row.components}
	var reused: Array=[];var missing: Array=[];var zero := 0
	var leaves: Array=source.configurations[config].leaves
	for i in leaves.size():
		var path: String=leaves[i];var faces: PackedInt32Array=tree_rows[path].triangles
		var layers: Array=[];var incomplete := false
		for layer in 2:
			if faces[layer]==0:continue
			var key := path+"#"+str(layer)
			if not candidates.has(key):incomplete=true
			else:layers.append(candidates[key])
		if incomplete:missing.append({"leaf_index":i,"source":path,"faces":[faces[0],faces[1]]})
		elif layers.is_empty():zero+=1
		else:reused.append({"leaf_index":i,"source":path,"layers":layers})
	if FileAccess.file_exists(input.output):return 1
	file=FileAccess.open(input.output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"source":binding,"configuration":config,"batches":batches,"reused":reused,"missing":missing,
		"zero_building_leaves":zero,"verified_output_paths":checked_paths.size(),"complete_building_layer_coverage":missing.is_empty(),
		"ground_covered":false,"runtime_integrated":false,"limitations":"Reuse proves bound prior conservation plus current component identity, face count and output file SHA. No new visual acceptance; ground excluded."},"\t"));file.close()
	print("Tokyo grid reuse: reused=",reused.size()," empty=",zero," missing=",missing.size()," verified_paths=",checked_paths.size())
	return 0
