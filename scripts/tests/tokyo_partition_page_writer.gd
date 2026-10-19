extends RefCounted
## 候选分页实物保存器；完整通道回读，不继承任何旧页身份或覆盖凭据。
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Read := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
var output := ""
var pages: Dictionary={}


func emit(entry: Dictionary, meshes: Array[ArrayMesh]) -> bool:
	if output.is_empty() or meshes.size()!=3 or pages.has(entry.path): return false
	var directory := output.path_join(str(entry.path).sha256_text())
	if DirAccess.dir_exists_absolute(directory) or DirAccess.make_dir_recursive_absolute(directory)!=OK: return false
	var layers: Array=[]
	var bytes := 0
	for kind in 3:
		var source: ArrayMesh=meshes[kind]
		var path := directory.path_join("layer_%d.res"%kind)
		var component := Component.new()
		var corners := Read.corner_digest(source) if source.get_surface_count()>0 else "empty_mesh".sha256_text()
		component.source_hash=var_to_bytes([corners,Read.decoded_bytes(source),source.get_aabb()]).hex_encode().sha256_text()
		component.geometry_bytes=Read.decoded_bytes(source)
		component.mesh_bytes=PackedInt32Array([component.geometry_bytes])
		component.meshes=[source]
		if not component.valid() or ResourceSaver.save(component,path,ResourceSaver.FLAG_COMPRESS)!=OK: return false
		var loaded: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not loaded is Component or not loaded.valid() or loaded.stream_identity()!=component.stream_identity(): return false
		var restored: ArrayMesh=loaded.meshes[0]
		if restored==null or not Join.conserved(source,[restored]) or restored.get_aabb()!=entry.boxes[kind] \
			or Count.triangles(restored)!=int(entry.triangles[kind]) or Read.decoded_bytes(restored)!=Read.decoded_bytes(source): return false
		bytes+=Read.decoded_bytes(restored)
		layers.append({"path":path,"sha256":FileAccess.get_sha256(path),"faces":Count.triangles(restored),"canonical_identity":loaded.stream_identity(),
			"bytes":Read.decoded_bytes(restored),"box":restored.get_aabb()})
	if bytes!=int(entry.bytes): return false
	pages[entry.path]={"layers":layers,"bytes":bytes}
	return true


func finish(tree: Dictionary, source_sha: String) -> Dictionary:
	var seen: Dictionary={}
	if not verify_tree(tree,seen) or seen.size()!=pages.size(): return {}
	var result := {"schema":2,"input_sha256":source_sha,"tree":tree,"pages":pages,
		"geometry_roundtrip_verified":true,"coverage_verified":false,"runtime_integrated":false}
	var path := output.path_join("partition.bin")
	if FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return {}
	file.store_var(result,false)
	file.close()
	file=FileAccess.open(path,FileAccess.READ)
	if file==null: return {}
	var restored: Variant=file.get_var(false)
	file.close()
	if restored!=result: return {}
	return {"path":path,"sha256":FileAccess.get_sha256(path),"pages":pages.size(),"geometry_roundtrip_verified":true,
		"coverage_verified":false,"runtime_integrated":false}


func verify_tree(entry: Dictionary, seen: Dictionary) -> bool:
	if seen.has(entry.path) or not pages.has(entry.path): return false
	seen[entry.path]=true
	var page: Dictionary=pages[entry.path]
	if page.bytes!=entry.bytes: return false
	for kind in 3:
		if page.layers[kind].faces!=entry.triangles[kind] or page.layers[kind].box!=entry.boxes[kind]: return false
	for child: Dictionary in entry.children:
		if not verify_tree(child,seen): return false
	return true
