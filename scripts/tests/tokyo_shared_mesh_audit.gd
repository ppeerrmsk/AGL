extends RefCounted
## 离线分批实物摘要；严格逐数组相同才可共享，不授予加载或性能资格。
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")


static func run(native: RefCounted, input: Dictionary) -> int:
	var records: Dictionary={}
	for key: String in native._grid_fine:
		for kind in 2:
			for child: Dictionary in native._grid_fine[key][kind]:
				if child.components.size()!=1: return 1
				var path: String=child.components.keys()[0]
				if not register(records,path,0,kind,child.components[path],"near"): return 1
	var stack: Array=native._partition_roots.get("lod4_full",native.catalog.configurations.lod4_full).duplicate()
	while not stack.is_empty():
		var node: Dictionary=stack.pop_back()
		if not node.get("children",[]).is_empty():
			stack.append_array(node.children);continue
		var page: Dictionary=native.pages[node.path]
		if not page.has("mapping") or page.mapping.size()!=3: return 1
		for kind in 2:
			if int(node.triangles[kind])==0: continue
			var path: String=page.mapping[kind][0]
			if not register(records,path,int(page.mapping[kind][1]),kind,page.components[path],"middle"): return 1
	var keys: Array=records.keys();keys.sort()
	var manifest := HashingContext.new();manifest.start(HashingContext.HASH_SHA256)
	for key: String in keys: manifest.update(var_to_bytes([key,records[key]]))
	var manifest_sha := manifest.finish().hex_encode()
	if input.has("mesh_share_manifest") and input.mesh_share_manifest!=manifest_sha: return 1
	var start := int(input.get("mesh_share_start",0))
	var count := int(input.get("mesh_share_count",256))
	if start<0 or start>=keys.size() or count<1 or count>32768: return 1
	var stop := mini(keys.size(),start+count)
	var actual_stop := start
	var started := Time.get_ticks_msec()
	var rows: Array=[]
	var last_path := ""
	var resource: Resource
	for i in range(start,stop):
		# 不延长wrapper超时：批次到时保存已核范围，下一批从实际终点继续。
		if i>start and Time.get_ticks_msec()-started>=150000: break
		var row: Dictionary=records[keys[i]]
		if row.path!=last_path:
			resource=null
			if FileAccess.get_sha256(row.path)!=row.binding.sha256: return 1
			resource=ResourceLoader.load(row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if resource==null or not resource.valid() or resource.stream_identity()!=row.binding.canonical_identity: return 1
			last_path=row.path
		if row.slot<0 or row.slot>=resource.meshes.size(): return 1
		var mesh: ArrayMesh=resource.meshes[row.slot]
		var fingerprint := mesh_sha(mesh,int(row.kind))
		if fingerprint.is_empty(): return 1
		rows.append({"key":keys[i],"path":row.path,"source_sha256":row.binding.sha256,"slot":row.slot,"kind":row.kind,
			"sets":row.sets,"geometry_sha256":fingerprint,"mesh_bytes":Packed.decoded_bytes(mesh),"surfaces":mesh.get_surface_count()})
		actual_stop=i+1
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"schema":1,"manifest_sha256":manifest_sha,"total":keys.size(),"start":start,"stop":actual_stop,
		"batch_complete":actual_stop==stop,"all_records_checked":start==0 and actual_stop==keys.size(),"rows":rows,
		"runtime_shared":false,"savings_verified":false,"scope":"exact ordered arrays and material-free semantics; no approximate or vertex-set equivalence"},"\t"))
	file.close()
	return 0


static func register(records: Dictionary, path: String, slot: int, kind: int, binding: Dictionary, set_name: String) -> bool:
	var key := "%s#%d/%d" % [path,slot,kind]
	if records.has(key):
		if records[key].binding!=binding: return false
		if set_name not in records[key].sets: records[key].sets.append(set_name)
	else: records[key]={"path":path,"slot":slot,"kind":kind,"binding":binding,"sets":[set_name]}
	return true


static func mesh_sha(mesh: ArrayMesh, kind: int) -> String:
	if mesh==null or mesh.get_blend_shape_count()!=0 or mesh.shadow_mesh!=null: return ""
	var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes([kind,mesh.custom_aabb,mesh.get_surface_count()]))
	for surface in mesh.get_surface_count():
		# 材质由既有layer绑定；带资源内材质或附加LOD者须另立完整比较合同。
		if mesh.surface_get_material(surface)!=null: return ""
		var raw: Dictionary=mesh.get("_surfaces")[surface]
		if not raw.get("lods",[]).is_empty(): return ""
		hash.update(var_to_bytes([mesh.surface_get_primitive_type(surface),mesh.surface_get_format(surface),mesh.surface_get_arrays(surface)]))
	return hash.finish().hex_encode()
