extends RefCounted
## 只提取认证源的地表槽；不改来源几何、不授予正式加载资格。
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")

static func run(input: Dictionary) -> int:
	var binding: Dictionary=input.build_ground_components
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var output: String=input.output
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var rows: Array=[]
	for candidate: Dictionary in report.samples[0].native:
		if candidate.request!="lod5_full": continue
		for entry: Dictionary in candidate.costs.entries:
			if entry.grid or not entry.surfaces.is_empty(): continue
			var path: String=entry.mapping[2][0]
			var slot := int(entry.mapping[2][1])
			var source: Dictionary=entry.components[path]
			# JSON数值恢复为身份合同的整数，不能拿解析后的float字典直接比资源身份。
			for field: String in ["schema","slots"]: source.canonical_identity[field]=int(source.canonical_identity[field])
			print("[Tokyo ground components] source=",path," slot=",slot)
			if FileAccess.get_sha256(path)!=source.sha256: return 1
			var resource: Resource=load(path)
			if resource==null or not resource.valid() or resource.stream_identity()!=source.canonical_identity: return 1
			var mesh: ArrayMesh=resource.meshes[slot]
			var component := Component.new()
			component.source_hash=var_to_bytes([source.sha256,slot,"ground_only"]).hex_encode().sha256_text()
			component.geometry_bytes=Packed.decoded_bytes(mesh)
			component.mesh_bytes=PackedInt32Array([component.geometry_bytes]);component.meshes=[mesh]
			var target := output.path_join("ground_%02d.res"%rows.size())
			if not component.valid() or ResourceSaver.save(component,target,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
			var copy: Resource=ResourceLoader.load(target,"",ResourceLoader.CACHE_MODE_IGNORE)
			if not copy is Component or not copy.valid() or copy.stream_identity()!=component.stream_identity(): return 1
			if Packed.corner_digest(mesh)!=Packed.corner_digest(copy.meshes[0]) or mesh.get_aabb()!=copy.meshes[0].get_aabb(): return 1
			rows.append({"page":entry.path,"source":source,"slot":slot,"source_page_bytes":entry.bytes,"faces":entry.faces,"binding":{"path":target,"sha256":FileAccess.get_sha256(target),"bytes":component.geometry_bytes,"canonical_identity":component.stream_identity()},"roundtrip_verified":true})
	if rows.is_empty(): return 1
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"source_report":binding,"rows":rows,"runtime_integrated":false},"\t"));file.close()
	print("[Tokyo ground components] saved and verified=",rows.size())
	return 0
