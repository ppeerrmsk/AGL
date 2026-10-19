extends RefCounted
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Shared := preload("res://scripts/tests/build_tokyo_shared_pages.gd")


static func run(directory: String, catalog_path: String, output: String) -> int:
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		return 1
	var file := FileAccess.open(directory.path_join("manifest.bin"), FileAccess.READ)
	if file == null:
		return 1
	var input: Dictionary = file.get_var(false)
	file.close()
	if input.catalog_sha256 != FileAccess.get_sha256(catalog_path) or input.rows.size() != 208:
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var manifest := {"schema": 1, "catalog_sha256": input.catalog_sha256, "pages": {}, "physical": {}, "production_enabled": false}
	for row: Dictionary in input.rows:
		if FileAccess.get_sha256(row.path) != row.sha256:
			return 1
		var bundle: Resource = ResourceLoader.load(row.path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if bundle == null or not bundle.valid():
			return 1
		var full: Array[ArrayMesh] = bundle.variant_meshes("lod2_full")
		var guard: Array[ArrayMesh] = bundle.variant_meshes("lod2_guarded")
		if full[1] != guard[1] or full[2] != guard[2]:
			return 1
		var stem: String = row.path.get_file().get_basename()
		var common: Array[ArrayMesh] = [full[1], full[2]]
		var shared := _save(common, bundle.source_hash + "common", output.path_join(stem + "_common.res"))
		var full_low: Array[ArrayMesh] = [full[0]]
		var first := _save(full_low, bundle.source_hash + "full", output.path_join(stem + "_full.res"))
		var second := first
		if full[0] != guard[0]:
			var guard_low: Array[ArrayMesh] = [guard[0]]
			second = _save(guard_low, bundle.source_hash + "guard", output.path_join(stem + "_guard.res"))
		if shared.is_empty() or first.is_empty() or second.is_empty():
			return 1
		for component: Dictionary in [shared, first, second]:
			manifest.physical[component.path] = component
		for configuration: String in bundle.variants:
			var info: Dictionary = bundle.variants[configuration]
			if FileAccess.get_sha256(info.path) != info.sha256:
				return 1
			var source: Resource = ResourceLoader.load(info.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if source == null or source.stream_identity() != info.identity:
				return 1
			var low: Dictionary = first if configuration.ends_with("full") else second
			var components := {str(low.path): low, str(shared.path): shared}
			if int(low.bytes) + int(shared.bytes) != source.geometry_bytes:
				return 1
			manifest.pages[info.path] = {"bytes": source.geometry_bytes, "canonical_identity": info.identity,
				"components": components, "mapping": [[low.path, 0], [shared.path, 0], [shared.path, 1]],
				"game_sources": source.game_sources, "triangles": source.triangles}
	if manifest.pages.size() != 416:
		return 1
	file = FileAccess.open(output.path_join("manifest.bin"), FileAccess.WRITE)
	file.store_var(manifest)
	file.close()
	print("[R69 components] logical=", manifest.pages.size(), " physical=", manifest.physical.size())
	return 0


static func _save(meshes: Array[ArrayMesh], source: String, path: String) -> Dictionary:
	var item := Component.new()
	item.meshes = meshes
	item.source_hash = source.sha256_text()
	for mesh: ArrayMesh in meshes:
		var amount := Builder.mesh_bytes(mesh)
		item.mesh_bytes.append(amount)
		item.geometry_bytes += amount
	if not item.valid() or ResourceSaver.save(item, path, ResourceSaver.FLAG_COMPRESS) != OK:
		return {}
	var saved: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null or not saved.valid() or saved.stream_identity() != item.stream_identity():
		return {}
	for n in meshes.size():
		if not Shared.same_mesh(meshes[n], saved.meshes[n]) or Builder.mesh_bytes(saved.meshes[n]) != saved.mesh_bytes[n]:
			return {}
	for dependency: String in ResourceLoader.get_dependencies(path):
		if not dependency.ends_with(".gd"):
			return {}
	return {"path": path, "bytes": saved.geometry_bytes, "canonical_identity": saved.stream_identity(), "sha256": FileAccess.get_sha256(path)}
