extends RefCounted
## 三层正式源格网目录；逐源核面数与物理身份，不授予同屏预算或运行时资格。
const Read := preload("res://scripts/tests/build_tokyo_grid_dependencies.gd")

static func run(input: Dictionary) -> int:
	var bindings: Array=input.joined_layers_catalog
	var output: String=input.output
	if bindings.size()!=2 or not output.is_absolute_path() or FileAccess.file_exists(output):return 1
	var snapshot_binding: Dictionary={}
	var pages: Array=[]
	var keys: Dictionary={}
	var physical: Dictionary={}
	var source_faces: Dictionary={}
	var totals: Array[int]=[0,0,0]
	var bytes_total := 0
	for binding: Dictionary in bindings:
		var data: Variant=Read.read(binding)
		if not data is Dictionary or not data.get("geometry_roundtrip_verified",false):return 1
		if snapshot_binding.is_empty():snapshot_binding=data.snapshot
		if snapshot_binding!=data.snapshot or data.first!=0 or data.count!=data.total_groups:return 1
		for page: Dictionary in data.pages:
			if keys.has(page.key) or FileAccess.get_sha256(page.path)!=page.sha256:return 1
			keys[page.key]=true
			var parts: PackedStringArray=page.key.split(":")
			if parts.size()!=3:return 1
			var layer := int(parts[0])
			if layer<0 or layer>2:return 1
			var offset := 0
			for origin: Dictionary in page.origins:
				if origin.layer!=layer or origin.first_face!=offset:return 1
				if not source_faces.has(origin.source):source_faces[origin.source]=[0,0,0]
				source_faces[origin.source][layer]+=int(origin.faces)
				offset+=int(origin.faces)
			if offset!=int(page.faces):return 1
			var identity := var_to_bytes(page.canonical_identity).hex_encode()
			if physical.has(identity):
				if physical[identity]!=[page.sha256,page.bytes]:return 1
			else:
				physical[identity]=[page.sha256,page.bytes]
				bytes_total+=int(page.bytes)
			totals[layer]+=offset
			var box: AABB=page.box
			pages.append({"key":page.key,"layer":layer,"cell":[int(parts[1]),int(parts[2])],
				"path":page.path,"sha256":page.sha256,"canonical_identity":page.canonical_identity,
				"faces":page.faces,"bytes":page.bytes,"bounds":[box.position.x,box.position.y,box.position.z,box.end.x,box.end.y,box.end.z]})
	var snapshot: Variant=Read.read(snapshot_binding)
	if not snapshot is Dictionary:return 1
	var leaves := 0
	var stack: Array=snapshot.configurations.lod5_full.roots.duplicate()
	while not stack.is_empty():
		var node: Dictionary=stack.pop_back()
		if not node.get("children",[]).is_empty():stack.append_array(node.children);continue
		leaves+=1
		var actual: Array=source_faces.get(node.path,[0,0,0])
		for layer in 3:
			if int(actual[layer])!=int(node.triangles[layer]):return 1
		source_faces.erase(node.path)
	if not source_faces.is_empty() or leaves!=snapshot.configurations.lod5_full.leaves.size():return 1
	var result := {"snapshot":snapshot_binding,"joined_inputs":bindings,"pages":pages,"leaf_count":leaves,
		"layer_faces":totals,"physical_resources":physical.size(),"geometry_bytes_deduplicated":bytes_total,
		"source_layer_faces_verified":true,"runtime_integrated":false,"display_budget_verified":false}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(result));file.close()
	var restored: Variant=JSON.parse_string(FileAccess.get_file_as_string(output))
	if not restored is Dictionary or restored.pages.size()!=pages.size():return 1
	print("[Tokyo joined layers] leaves=",leaves," pages=",pages.size()," faces=",totals," deduplicated_bytes=",bytes_total)
	return 0
