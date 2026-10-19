extends RefCounted
const Page := preload("res://scripts/rendering/tokyo_shared_page.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")


static func run(catalog_path: String, output: String) -> int:
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		return 1
	var catalog: Resource = load(catalog_path)
	if catalog == null or not catalog.valid():
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array[Dictionary] = []
	for parent in 16:
		if not _pair(catalog.configurations.lod2_full[parent], catalog.configurations.lod2_guarded[parent], catalog, output, rows):
			return 1
		print("[R68 shared build] parent=", parent, " pages=", rows.size())
	if rows.size() != 208:
		return 1
	var file := FileAccess.open(output.path_join("manifest.bin"), FileAccess.WRITE)
	file.store_var({"schema": 1, "catalog_sha256": FileAccess.get_sha256(catalog_path), "rows": rows,
		"collision_sha256": catalog.collision_sha256, "owners_sha256": catalog.owners_sha256, "production_enabled": false})
	file.close()
	var json := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	json.store_string(JSON.stringify(rows, "\t"))
	json.close()
	return 0


static func _pair(full: Dictionary, guarded: Dictionary, catalog: Resource, output: String, rows: Array[Dictionary]) -> bool:
	var page := Page.new()
	var sources: Array[Resource] = []
	var old_bytes := 0
	for entry: Dictionary in [full, guarded]:
		if FileAccess.get_sha256(entry.path) != entry.sha256:
			return false
		var source: Resource = ResourceLoader.load(entry.path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if source == null or not source.valid() or source.stream_identity() != catalog.descriptors[entry.path].canonical_identity:
			return false
		sources.append(source)
		var slots := PackedInt32Array()
		for mesh: ArrayMesh in source.meshes:
			var slot := -1
			for n in page.meshes.size():
				if same_mesh(mesh, page.meshes[n]):
					slot = n
					break
			if slot < 0:
				slot = page.meshes.size()
				page.meshes.append(mesh)
				page.mesh_bytes.append(Builder.mesh_bytes(mesh))
				page.geometry_bytes += page.mesh_bytes[-1]
			slots.append(slot)
		page.variants[source.configuration] = {"identity": source.stream_identity(), "slots": slots, "path": entry.path, "sha256": entry.sha256}
		old_bytes += source.geometry_bytes
	page.source_hash = (str(full.sha256) + str(guarded.sha256)).sha256_text()
	if not page.valid() or page.geometry_bytes > old_bytes:
		return false
	var name_value := "parent_%02d.res" % int(full.parent_id) if int(full.cell_id) == -1 else "page_%03d.res" % int(full.cell_id)
	var target := output.path_join(name_value)
	if ResourceSaver.save(page, target, ResourceSaver.FLAG_COMPRESS) != OK:
		return false
	var saved: Resource = ResourceLoader.load(target, "", ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null or not saved.valid() or saved.stream_identity() != page.stream_identity():
		return false
	for dependency: String in ResourceLoader.get_dependencies(target):
		if not dependency.ends_with(".gd"):
			return false
	var actual_bytes := 0
	for n in saved.meshes.size():
		if Builder.mesh_bytes(saved.meshes[n]) != saved.mesh_bytes[n]:
			return false
		actual_bytes += saved.mesh_bytes[n]
	if actual_bytes != saved.geometry_bytes:
		return false
	var faces: Array = []
	for source: Resource in sources:
		var meshes: Array[ArrayMesh] = saved.variant_meshes(source.configuration)
		var counts := PackedInt32Array()
		for kind in 3:
			if not same_mesh(meshes[kind], source.meshes[kind]):
				return false
			counts.append(Indexed.triangles(meshes[kind]))
		faces.append(counts)
	rows.append({"path": target, "sha256": FileAccess.get_sha256(target), "parent": full.parent_id, "cell": full.cell_id,
		"old_bytes": old_bytes, "bytes": saved.geometry_bytes, "pool_count": saved.meshes.size(), "faces": faces,
		"maps": [saved.variants.lod2_full.slots, saved.variants.lod2_guarded.slots],
		"canonical_identity": saved.stream_identity()})
	var children: Array = full.get("children", [])
	if children.size() != guarded.get("children", []).size():
		return false
	for n in children.size():
		if not _pair(children[n], guarded.children[n], catalog, output, rows):
			return false
	return true


static func same_mesh(a: ArrayMesh, b: ArrayMesh) -> bool:
	return a.get("_surfaces") == b.get("_surfaces") and a.get_aabb() == b.get_aabb() \
		and a.custom_aabb == b.custom_aabb and a.get_blend_shape_count() == 0 and b.get_blend_shape_count() == 0
