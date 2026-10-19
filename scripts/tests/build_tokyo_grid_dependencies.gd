extends RefCounted
## 离线来源层到新格的完整依赖；不把game_sources标签直接转换成隐藏凭据。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")


static func run(input: Dictionary) -> int:
	var binding: Variant=input.get("grid_dependencies")
	var output: String=input.get("output","")
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	if not output.is_absolute_path() or FileAccess.file_exists(output): return 1
	var audit: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not audit is Dictionary or not audit.get("all_complete",false): return 1
	var snapshot_binding: Dictionary={}
	var batches: Dictionary={}
	var consumed: Dictionary={}
	var dependencies: Dictionary={}
	var pages: Dictionary={}
	var total_faces := 0
	for record: Dictionary in audit.rows:
		var joined: Variant=read(record.joined)
		if not joined is Dictionary or not joined.get("geometry_roundtrip_verified",false): return 1
		if snapshot_binding.is_empty(): snapshot_binding=joined.snapshot
		if snapshot_binding!=joined.snapshot: return 1
		for page: Dictionary in joined.pages:
			if pages.has(page.path): return 1
			if FileAccess.get_sha256(page.path)!=page.sha256: return 1
			pages[page.path]={"identity":page.canonical_identity,"sha256":page.sha256,"faces":page.faces,"box":page.box}
			var offset := 0
			for origin: Dictionary in page.origins:
				var batch_path: String=origin.batch.path
				if not batches.has(batch_path):
					var batch: Variant=read(origin.batch)
					if not batch is Dictionary or batch.snapshot!=snapshot_binding: return 1
					batches[batch_path]={"binding":origin.batch,"data":batch}
				if batches[batch_path].binding!=origin.batch: return 1
				var batch: Dictionary=batches[batch_path].data
				if origin.row<0 or origin.row>=batch.rows.size(): return 1
				var row: Dictionary=batch.rows[origin.row]
				if origin.part<0 or origin.part>=row.components.size(): return 1
				if origin.source!=row.source or origin.layer!=row.layer or origin.game_sources!=row.game_sources: return 1
				if origin.component!=row.components[origin.part] or origin.cell!=row.cells[origin.part]: return 1
				var token := "%s:%d:%d" % [batch_path,origin.row,origin.part]
				if consumed.has(token) or origin.first_face!=offset: return 1
				var faces: int=row.owners.count(int(origin.part))
				if faces!=int(origin.faces) or faces<=0: return 1
				consumed[token]=true
				offset+=faces
				if not dependencies.has(row.source): dependencies[row.source]={}
				if not dependencies[row.source].has(row.layer): dependencies[row.source][row.layer]=[]
				dependencies[row.source][row.layer].append({"path":page.path,"identity":page.canonical_identity,"first_face":origin.first_face,"faces":faces})
			if offset!=int(page.faces): return 1
			total_faces+=offset
	if pages.size()!=int(audit.expected_groups) or total_faces!=int(audit.faces): return 1
	for batch_path: String in batches:
		var batch: Dictionary=batches[batch_path].data
		for row_index in batch.rows.size():
			for part in batch.rows[row_index].components.size():
				if not consumed.has("%s:%d:%d" % [batch_path,row_index,part]): return 1
	var snapshot: Variant=read(snapshot_binding)
	if not snapshot is Dictionary: return 1
	var leaves: Array=snapshot.configurations.lod5_full.leaves
	for source: String in dependencies:
		if not leaves.has(source): return 1
	var native_ground: Array=[]
	var textured_ground: Array=[]
	# 正式包可没有候选地表覆盖清单；缺省保持原生地表，不能当成缺层。
	var ground: Variant=snapshot.get("ground",{})
	if not ground is Dictionary:return 1
	var ground_rows: Variant=ground.get("rows",{})
	if not ground_rows is Dictionary:return 1
	var stack: Array=snapshot.configurations.lod5_full.roots.duplicate()
	while not stack.is_empty():
		var entry: Dictionary=stack.pop_back()
		stack.append_array(entry.get("children",[]))
		if not entry.get("children",[]).is_empty(): continue
		for layer in 2:
			var actual := 0
			for dependency: Dictionary in dependencies.get(entry.path,{}).get(layer,[]): actual+=int(dependency.faces)
			if actual!=int(entry.triangles[layer]): return 1
		if int(entry.triangles[2])>0:
			if ground_rows.has(entry.path): textured_ground.append(entry.path)
			else: native_ground.append(entry.path)
	var result := {"schema":1,"snapshot":snapshot_binding,"joined_audit":binding,"configuration":"lod5_full",
		"pages":pages,"dependencies":dependencies,"original_coverage":snapshot.configurations.lod5_full.coverage,
		"native_ground_leaves":native_ground,"textured_ground_leaves":textured_ground,
		"faces":total_faces,"parts":consumed.size(),"source_layers_complete":true,"runtime_integrated":false,"hide_authorized":false}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_var(result,false);file.close()
	if read({"path":output,"sha256":FileAccess.get_sha256(output)})!=result: return 1
	print("[Tokyo grid dependencies] sources=",dependencies.size()," parts=",consumed.size()," faces=",total_faces,
		" native_ground_leaves=",native_ground.size()," textured_ground_leaves=",textured_ground.size()," saved_readback=true")
	return 0


static func read(binding: Variant) -> Variant:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return null
	var file := FileAccess.open(binding.path,FileAccess.READ)
	if file==null: return null
	var result: Variant=file.get_var(false)
	file.close()
	return result
