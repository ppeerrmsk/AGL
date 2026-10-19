extends RefCounted
## 只制作北岸完整近档低层父包，先证实无损节省，不改目录或任何流送入口。
const Reindex := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")


static func run(catalog_path: String, output: String) -> int:
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		return 1
	var catalog: Resource = load(catalog_path)
	if catalog==null or not catalog.valid():
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array = []
	for id in range(8,16):
		var entry: Dictionary = catalog.configurations.lod5_full[id]
		if FileAccess.get_sha256(entry.path)!=entry.sha256:
			return 1
		var page: Resource = ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if page==null or not page.valid() or page.stream_identity()!=catalog.descriptors[entry.path].canonical_identity:
			return 1
		var mesh: ArrayMesh = page.meshes[0]
		var before := Reindex.decoded_bytes(mesh)
		var digest := Reindex.corner_digest(mesh)
		var packed := Reindex.repack(mesh)
		var destination := output.path_join("north_%02d_low.res" % id)
		if ResourceSaver.save(packed,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
			return 1
		var saved: ArrayMesh = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
		if saved==null or Reindex.corner_digest(saved)!=digest or saved.get_aabb()!=mesh.get_aabb() or saved.custom_aabb!=mesh.custom_aabb \
				or saved.surface_get_material(0)!=mesh.surface_get_material(0) or Reindex.decoded_bytes(saved)>before:
			return 1
		rows.append({"parent":id,"source":entry.path,"source_sha256":entry.sha256,"output":destination,"sha256":FileAccess.get_sha256(destination),
			"before_bytes":before,"after_bytes":Reindex.decoded_bytes(saved),"before_vertices":mesh.surface_get_array_len(0),"after_vertices":saved.surface_get_array_len(0),
			"ordered_corners_sha256":digest,"triangles":entry.triangles[0]})
		print("[R88 reindex] ",rows[-1])
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"catalog_sha256":FileAccess.get_sha256(catalog_path),"rows":rows,"fail":0,"production_enabled":false},"\t"))
	file.close()
	return 0
