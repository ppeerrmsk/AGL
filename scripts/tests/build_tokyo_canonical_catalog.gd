extends RefCounted
## R54制作入口：逐包读取已审计来源，目录不得夹带原生几何。
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Page := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")
const Spatial := preload("res://scripts/tests/build_tokyo_spatial_pages.gd")


static func run(directory: String, output: String) -> int:
	if FileAccess.file_exists(output):
		return 1
	var catalog := Catalog.new()
	var original: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	var fixed_hashes := PackedStringArray()
	for cell: Dictionary in original.cells:
		fixed_hashes.append(FileAccess.get_sha256(cell.fixed))
	for configuration: String in Catalog.CONFIGURATIONS:
		var folder := directory.path_join(configuration)
		var path := folder.path_join("manifest.bin")
		var audit := folder.path_join("audit_manifest.bin")
		if not FileAccess.file_exists(audit) or FileAccess.get_sha256(path) != FileAccess.get_sha256(audit):
			return 1
		var input := FileAccess.open(path, FileAccess.READ)
		if input == null:
			return 1
		var report: Dictionary = input.get_var(false)
		input.close()
		if report.get("fail", -1) != 0 or report.get("configuration") != configuration or report.get("parents", []).size() != 16:
			return 1
		if catalog.collision_sha256.is_empty():
			catalog.collision_sha256 = report.collision_sha256
			catalog.owners_sha256 = report.owners_sha256
		if catalog.collision_sha256 != report.collision_sha256 or catalog.owners_sha256 != report.owners_sha256:
			return 1
		var parents: Array[Dictionary] = []
		for id in 16:
			var source := (str(report.plan_sha256) + str(report.owners_sha256) + fixed_hashes[id]).sha256_text()
			var entry := _convert(report.parents[id], folder, configuration, source, catalog)
			if entry.is_empty():
				return 1
			parents.append(entry)
		catalog.configurations[configuration] = parents
		print("[Tokyo canonical catalog] ", configuration, " verified=", catalog.descriptors.size())
	if not catalog.valid() or ResourceSaver.save(catalog, output, ResourceSaver.FLAG_COMPRESS) != OK:
		return 1
	var saved: Resource = ResourceLoader.load(output, "", ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null or not saved.valid() or saved.configurations != catalog.configurations or saved.descriptors != catalog.descriptors:
		return 1
	for dependency: String in ResourceLoader.get_dependencies(output):
		if not dependency.ends_with(".gd"):
			return 1
	print("[Tokyo canonical catalog] COMPLETE packages=2288 configurations=11 geometry_embedded=0 fail=0")
	return 0


static func _convert(row: Dictionary, folder: String, configuration: String, source: String, catalog: Resource) -> Dictionary:
	var path: String = row.path
	if path.simplify_path() != folder.path_join(path.get_file()).simplify_path() or FileAccess.get_sha256(path) != row.sha256:
		return {}
	var page: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not page is Page or not page.valid() or page.configuration != configuration or page.source_hash != source \
			or page.collision_sha256 != catalog.collision_sha256 or page.owners_sha256 != catalog.owners_sha256 \
			or page.parent_id != row.parent_id or page.cell_id != row.cell_id or page.ancestor_id != row.ancestor_id or page.level != row.level:
		return {}
	var actual := Spatial.descriptor(page.meshes)
	if actual.bytes != row.bytes or actual.boxes != row.boxes or actual.triangles != row.triangles or page.geometry_bytes != actual.bytes:
		return {}
	var faces := 0
	for count: int in actual.triangles:
		faces += count
	if faces != page.triangles or catalog.descriptors.has(path):
		return {}
	catalog.descriptors[path] = {"bytes": page.geometry_bytes, "canonical_identity": page.stream_identity()}
	var result := row.duplicate(true)
	result["key"] = configuration + "/" + path.get_file().get_basename()
	if result.has("children"):
		result.children = []
		for child: Dictionary in row.children:
			var converted := _convert(child, folder, configuration, source, catalog)
			if converted.is_empty():
				return {}
			result.children.append(converted)
	return result
