extends RefCounted
## 正式全图低楼和地表供已有分层烘焙器消费；高楼保持原生资源。
const Payload := preload("res://scripts/tests/tokyo_residential_preview.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")

static func run(input: Dictionary) -> int:
	var binding: Dictionary=input.export_joined_layers
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var output: String=input.output
	if not catalog.get("source_layer_faces_verified",false) or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output):return 1
	var layers: Array=input.get("export_layers",[0,2])
	var selected_keys: Array=input.get("export_keys",[])
	var seen_layers: Dictionary={}
	for layer: Variant in layers:
		if typeof(layer) not in [TYPE_INT,TYPE_FLOAT]:return 1
		if not is_finite(float(layer)) or float(layer)!=floor(float(layer)):return 1
		if int(layer) not in [0,1,2] or seen_layers.has(int(layer)):return 1
		seen_layers[int(layer)]=true
	if layers.is_empty():return 1
	var wanted: Dictionary={}
	for key: Variant in selected_keys:
		if not key is String or wanted.has(key):return 1
		wanted[key]=true
	var found: Dictionary={}
	if DirAccess.make_dir_recursive_absolute(output)!=OK:return 1
	var rows: Array=[]
	var faces: Array[int]=[0,0,0]
	for page: Dictionary in catalog.pages:
		var layer := int(page.layer)
		if not seen_layers.has(layer):continue
		if not wanted.is_empty() and not wanted.has(page.key):continue
		if found.has(page.key) or FileAccess.get_sha256(page.path)!=page.sha256:return 1
		found[page.key]=true
		var resource: Resource=ResourceLoader.load(page.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not resource is Component or not resource.valid() or resource.meshes.size()!=1:return 1
		var identity: Dictionary=page.canonical_identity.duplicate()
		for field: String in ["schema","slots"]:identity[field]=int(identity[field])
		if resource.stream_identity()!=identity or resource.geometry_bytes!=int(page.bytes):return 1
		var payload := Payload.export_payload(resource.meshes[0])
		if payload.is_empty() or payload.attributes.size()!=int(page.faces)*120:return 1
		var path := output.path_join("layer%d_%s.attributes" % [layer,page.key.replace(":","_")])
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file==null:return 1
		file.store_buffer(payload.attributes);file.close()
		var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(payload.attributes)
		var digest := hash.finish().hex_encode()
		if FileAccess.get_sha256(path)!=digest:return 1
		rows.append({"source":page,"path":path,"sha256":digest,"faces":int(page.faces),"layer":layer})
		faces[layer]+=int(page.faces)
		if rows.size()%256==0:print("[Tokyo joined export] pages=",rows.size()," faces=",faces)
	if not wanted.is_empty() and found.size()!=wanted.size():return 1
	if wanted.is_empty():
		for layer: Variant in layers:
			if faces[int(layer)]!=int(catalog.layer_faces[int(layer)]):return 1
	var report := {"catalog":binding,"rows":rows,"layer_faces":faces,"export_layers":layers,"export_keys":selected_keys,
		"full_catalog_scope":wanted.is_empty(),"high_layer_retained_native":true,"runtime_integrated":false}
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(report));file.close()
	print("[Tokyo joined export] complete pages=",rows.size()," faces=",faces)
	return 0
