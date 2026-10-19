extends RefCounted
## 只重绑定经过身份和面数证明的格网行，保留原批次追溯，不复制网格。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")

static func run(input: Dictionary) -> int:
	for binding: Dictionary in [input.rebind_grid,input.reuse,input.repairs]:
		if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var file := FileAccess.open(input.rebind_grid.path,FileAccess.READ)
	if file==null:return 1
	var snapshot: Dictionary=file.get_var(false);file.close()
	var reuse: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.reuse.path))
	var repairs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.repairs.path))
	if reuse.source!=input.rebind_grid or repairs.source!=input.rebind_grid:return 1
	if repairs.reuse_inventory_sha256!=input.reuse.sha256 or not repairs.all_missing_building_leaves_generated:return 1
	var bindings: Array=reuse.batches.duplicate()
	for row: Dictionary in repairs.rows:bindings.append(row.batch)
	var config: String=reuse.configuration
	if config!="lod5_full":return 1
	var nodes: Dictionary={};var stack: Array=snapshot.configurations[config].roots.duplicate()
	while not stack.is_empty():
		var node: Dictionary=stack.pop_back()
		if not node.get("children",[]).is_empty():stack.append_array(node.children)
		else:nodes[node.path]=node
	var leaves: Array=snapshot.configurations[config].leaves
	var indices: Dictionary={};var costs: Array[int]=[]
	for i in leaves.size():
		indices[leaves[i]]=i
		costs.append(int(nodes[leaves[i]].triangles[0])+int(nodes[leaves[i]].triangles[1]))
	var chosen: Dictionary={};var verified: Dictionary={};var origin_bindings: Array=[]
	for binding: Dictionary in bindings:
		if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
		file=FileAccess.open(binding.path,FileAccess.READ)
		if file==null:return 1
		var batch: Dictionary=file.get_var(false);file.close()
		if batch.configuration!=config or not batch.geometry_roundtrip_verified or batch.grid_world!=512.0:return 1
		origin_bindings.append(binding)
		for row_index in batch.rows.size():
			var original: Dictionary=batch.rows[row_index]
			if not nodes.has(original.source):continue
			var page: Dictionary=snapshot.pages[original.source]
			if original.source_components!=page.components:continue
			if original.game_sources!=page.get("game_sources",[]):return 1
			var layer := int(original.layer)
			if layer not in [0,1] or original.owners.size()!=int(nodes[original.source].triangles[layer]):return 1
			var key: String=original.source+"#"+str(layer)
			if chosen.has(key):return 1
			if original.components.size()!=original.cells.size():return 1
			for owner: int in original.owners:
				if owner<0 or owner>=original.components.size():return 1
			for descriptor: Dictionary in original.components:
				if verified.has(descriptor.path):
					if verified[descriptor.path]!=descriptor.sha256:return 1
				else:
					if FileAccess.get_sha256(descriptor.path)!=descriptor.sha256:return 1
					verified[descriptor.path]=descriptor.sha256
			var row := original.duplicate()
			row["leaf_index"]=indices[row.source]
			row["original_batch"]=binding;row["original_row"]=row_index
			chosen[key]=row
	var rows: Array=[];var faces := 0;var groups: Dictionary={}
	for path: String in leaves:
		for layer in 2:
			var expected := int(nodes[path].triangles[layer])
			var key := path+"#"+str(layer)
			if expected==0:
				if chosen.has(key):return 1
				continue
			if not chosen.has(key):return 1
			var row: Dictionary=chosen[key];rows.append(row);faces+=row.owners.size()
			for cell: Vector2i in row.cells:groups["%d:%d:%d"%[layer,cell.x,cell.y]]=true
	var total := 0
	for amount: int in costs:total+=amount
	if faces!=total or rows.size()!=chosen.size():return 1
	var output: String=input.output
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:return 1
	var result := {"schema":1,"snapshot":input.rebind_grid,"configuration":config,"first":0,"count":leaves.size(),
		"leaf_face_costs":costs,"grid_world":512.0,"rows":rows,"faces":faces,"geometry_roundtrip_verified":true,
		"original_batches":origin_bindings,"rebound_component_identity_verified":true,"runtime_integrated":false,"ground_integrated":false}
	var path := output.path_join("batch.bin")
	file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return 1
	file.store_var(result,false);file.close()
	file=FileAccess.open(path,FileAccess.READ)
	if file==null:return 1
	var restored: Variant=file.get_var(false);file.close()
	if restored!=result:return 1
	var audit := {"configuration":config,"expected_leaves":leaves.size(),"completed_faces":faces,"all_batches_complete":true,
		"rows":[{"first":0,"count":leaves.size(),"batch":{"path":path,"sha256":FileAccess.get_sha256(path)}}],
		"total_groups":groups.size(),"verified_outputs":verified.size(),"row_count":rows.size(),"ground_integrated":false,"runtime_integrated":false,
		"limitations":"Original conservation evidence retained via bound original batches; rebind verifies formal identity, coverage, counts and output hashes. No new mesh generation or visual qualification."}
	file=FileAccess.open(output.path_join("audit.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(audit,"\t"));file.close()
	print("Tokyo formal grid rebound: leaves=",leaves.size()," faces=",faces," groups=",groups.size()," paths=",verified.size())
	return 0
