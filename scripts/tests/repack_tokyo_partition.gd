extends RefCounted
## 只重打包已审计的页，不重新分桶或重建几何。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Adapter := preload("res://scripts/rendering/tokyo_partition_catalog.gd")
const Assembly := preload("res://scripts/rendering/tokyo_component_page.gd")
const Bundle := preload("res://scripts/rendering/tokyo_partition_bundle.gd")
const Read := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")


static func run(input: Dictionary, digest: String) -> int:
	var binding: Variant=input.get("repack_partition")
	var output: String=input.get("output","")
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256 \
		or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var file := FileAccess.open(binding.path,FileAccess.READ)
	if file==null: return 1
	var data: Variant=file.get_var(false)
	file.close()
	if not data is Dictionary or data.get("schema")!=2: return 1
	var normalized := Adapter.normalize(data,binding)
	if normalized.is_empty() or DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var pages: Dictionary={}
	var total := 0
	for key: String in data.pages:
		var row: Dictionary=normalized.pages[binding.sha256+":"+key]
		var loaded: Dictionary={}
		for part: Dictionary in row.components.values():
			if FileAccess.get_sha256(part.path)!=part.sha256: return 1
			loaded[part.path]=ResourceLoader.load(part.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var original: Resource=Assembly.assemble(row,loaded)
		if original==null: return 1
		var bundle := Bundle.new()
		bundle.source_hash=var_to_bytes([binding.sha256,key,row.components]).hex_encode().sha256_text()
		bundle.meshes=original.meshes
		bundle.geometry_bytes=original.geometry_bytes
		for mesh: ArrayMesh in bundle.meshes: bundle.mesh_bytes.append(Read.decoded_bytes(mesh))
		if not bundle.valid(): return 1
		var path := output.path_join(key.sha256_text()+".res")
		if ResourceSaver.save(bundle,path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
		var restored: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not restored is Bundle or not restored.valid() or restored.stream_identity()!=bundle.stream_identity(): return 1
		var layers: Array=[]
		for kind in 3:
			var mesh: ArrayMesh=restored.meshes[kind]
			var prior: Dictionary=data.pages[key].layers[kind]
			if not Join.conserved(original.meshes[kind],[mesh]) or mesh.get_aabb()!=prior.box \
				or Count.triangles(mesh)!=prior.faces or Read.decoded_bytes(mesh)!=prior.bytes: return 1
			layers.append({"box":mesh.get_aabb(),"faces":Count.triangles(mesh),"bytes":Read.decoded_bytes(mesh)})
		pages[key]={"bytes":bundle.geometry_bytes,"layers":layers,"bundle":{"path":path,
			"sha256":FileAccess.get_sha256(path),"bytes":bundle.geometry_bytes,"canonical_identity":bundle.stream_identity()}}
		total+=bundle.geometry_bytes
	var result: Dictionary=data.duplicate()
	result.schema=3;result.pages=pages
	result["repacked_from"]=binding
	var partition_path := output.path_join("partition.bin")
	file=FileAccess.open(partition_path,FileAccess.WRITE)
	if file==null: return 1
	file.store_var(result,false);file.close()
	file=FileAccess.open(partition_path,FileAccess.READ)
	if file==null: return 1
	var saved: Variant=file.get_var(false)
	file.close()
	var packed_binding := {"path":partition_path,"sha256":FileAccess.get_sha256(partition_path),"configuration":binding.configuration}
	if not saved is Dictionary or saved!=result or Adapter.normalize(saved,packed_binding).is_empty(): return 1
	file=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"input_sha256":digest,"partition":packed_binding,"pages":pages.size(),
		"old_physical_files":pages.size()*3,"new_physical_files":pages.size(),"decoded_bytes":total,
		"geometry_conserved":true,"runtime_verified":false,"performance_accepted":false},"\t"))
	file.close()
	return 0
