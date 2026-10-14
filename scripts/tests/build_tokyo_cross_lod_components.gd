extends RefCounted
## 全组合逐页制作，不持有完整目录几何；内容摘要命中后仍核对原生数组。
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Components := preload("res://scripts/tests/build_tokyo_mesh_components.gd")
const Shared := preload("res://scripts/tests/build_tokyo_shared_pages.gd")
const Manifest := preload("res://scripts/rendering/tokyo_component_manifest.gd")


static func mesh_key(mesh: ArrayMesh, kind: int) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes([kind, mesh.get("_surfaces"), mesh.get_aabb(), mesh.custom_aabb]))
	return hash.finish().hex_encode()


static func run(catalog_path: String, output: String) -> int:
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		return 1
	var catalog: Resource = load(catalog_path)
	if catalog == null or not catalog.valid():
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var manifest := {"schema":2,"catalog_sha256":FileAccess.get_sha256(catalog_path),"configurations":PackedStringArray(Catalog.CONFIGURATIONS),"pages":{},"physical":{},"production_enabled":false}
	var sources: Dictionary = {}
	for configuration: String in Catalog.CONFIGURATIONS:
		for root: Dictionary in catalog.configurations[configuration]:
			_collect(root,sources)
	var total_original := 0
	var unique_bytes := 0
	var per_kind := [0,0,0]
	var reused := [0,0,0]
	var count := 0
	for path: String in sources:
		var entry: Dictionary = sources[path]
		if FileAccess.get_sha256(path) != entry.sha256:
			return 1
		var page: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if page == null or not page.valid() or page.stream_identity() != catalog.descriptors[path].canonical_identity:
			return 1
		var parts: Dictionary = {}
		var mapping: Array = []
		for kind in 3:
			var key := mesh_key(page.meshes[kind],kind)
			var target := output.path_join("%d_%s.res" % [kind,key])
			if not manifest.physical.has(target):
				var meshes: Array[ArrayMesh] = [page.meshes[kind]]
				var descriptor := Components._save(meshes,key,target)
				if descriptor.is_empty():
					return 1
				manifest.physical[target] = descriptor
				unique_bytes += int(descriptor.bytes)
				per_kind[kind] += 1
			else:
				var saved: Resource = ResourceLoader.load(target,"",ResourceLoader.CACHE_MODE_IGNORE)
				if saved == null or not saved.valid() or saved.stream_identity() != manifest.physical[target].canonical_identity or not Shared.same_mesh(page.meshes[kind],saved.meshes[0]):
					return 1
				reused[kind] += 1
			parts[target] = manifest.physical[target]
			mapping.append([target,0])
		var row := {"bytes":page.geometry_bytes,"canonical_identity":page.stream_identity(),"components":parts,"mapping":mapping,"game_sources":page.game_sources,"triangles":page.triangles}
		if not Manifest.valid_row(row,catalog.descriptors[path],manifest.physical):
			return 1
		manifest.pages[path] = row
		total_original += int(page.geometry_bytes)
		count += 1
		if count % 208 == 0:
			print("[R72 build] logical=",count," physical=",manifest.physical.size()," unique_bytes=",unique_bytes)
	var manifest_path := output.path_join("manifest.bin")
	var file := FileAccess.open(manifest_path,FileAccess.WRITE)
	file.store_var(manifest)
	file.close()
	if Manifest.read(manifest_path,catalog,manifest.catalog_sha256).is_empty():
		return 1
	var report := {"logical":count,"physical":manifest.physical.size(),"physical_per_kind":per_kind,"reused_per_kind":reused,"original_all_pages_bytes":total_original,"unique_all_components_bytes":unique_bytes,"metadata_bytes":FileAccess.get_file_as_bytes(manifest_path).size(),"catalog_sha256":manifest.catalog_sha256,"manifest_sha256":FileAccess.get_sha256(manifest_path),"fail":0}
	file = FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("[R72 build] COMPLETE ",report)
	return 0


static func _collect(entry: Dictionary, output: Dictionary) -> void:
	output[entry.path] = entry
	for child: Dictionary in entry.get("children",[]):
		_collect(child,output)
