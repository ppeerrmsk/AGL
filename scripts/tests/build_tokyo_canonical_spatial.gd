extends RefCounted
## R52单组合离线空间包；只读旧来源，输出独立目录，不启动运行时流送。
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Spatial := preload("res://scripts/tests/build_tokyo_spatial_pages.gd")
const Baker := preload("res://scripts/tests/bake_tokyo_shared_roofs.gd")
const Page := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")


static func run() -> int:
	var plan_path := OS.get_environment("AGL_TOKYO_SPATIAL_PLAN")
	var schedule: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	var name_value := OS.get_environment("AGL_TOKYO_SPATIAL_CONFIG")
	var out := OS.get_environment("AGL_TOKYO_SPATIAL_OUT").path_join(name_value)
	var source_directory := OS.get_environment("AGL_TOKYO_SPATIAL_SOURCE")
	var bundle_directory := OS.get_environment("AGL_TOKYO_SPATIAL_BUNDLES")
	var audit := OS.get_environment("AGL_TOKYO_SPATIAL_AUDIT") == "1"
	if not schedule.get("passed", false) or (not audit and DirAccess.dir_exists_absolute(out)):
		return 1
	var row: Dictionary = {}
	for entry: Dictionary in schedule.configurations:
		if entry.name == name_value:
			row = entry
	if row.is_empty():
		return 1
	var input: String = source_directory.path_join(row.file)
	if FileAccess.get_sha256(input) != row.plan_sha256:
		return 1
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input))
	var bundle_path := bundle_directory.path_join(name_value + ".res")
	var bundle_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bundle_directory.path_join("build_manifest.json")))
	var bundle_verified := false
	for entry: Dictionary in bundle_manifest.rows:
		if entry.name == name_value:
			bundle_verified = int(entry.fail) == 0 and entry.plan_sha256 == row.plan_sha256 and entry.bundle_sha256 == FileAccess.get_sha256(bundle_path)
	if not bundle_verified or int(bundle_manifest.fail) != 0:
		return 1
	var bundle: Resource = ResourceLoader.load(bundle_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if bundle == null or bundle.plan_sha256 != row.plan_sha256 or bundle.collision_sha256 != schedule.collision_sha256:
		return 1
	var layout: Resource = load("res://resources/maps/tokyo_volume_preview/r40_pages/index.res")
	var original: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	var additions: Array[ArrayMesh] = []
	var expected: Dictionary = {}
	for entry: Dictionary in plan.expected:
		expected[int(entry.source_id)] = entry
	for part: Dictionary in row.parts:
		if int(part.parent_id) != additions.size():
			return 1
		var subset := {"expected": [], "triangles": []}
		for id: float in part.expected:
			subset.expected.append(expected[int(id)])
		for id: float in part.triangles:
			subset.triangles.append(plan.triangles[int(id)])
		additions.append(Baker._addition(subset))
	if additions.size() != 16 or not Join.conserved(bundle.addition, additions):
		push_error("Spatial additions duplicate or omit original R51 packed faces")
		return 1
	if not audit:
		DirAccess.make_dir_recursive_absolute(out)
	var report := {"configuration": name_value, "plan_sha256": row.plan_sha256,
		"schedule_sha256": FileAccess.get_sha256(plan_path), "owners_sha256": schedule.owners_sha256,
		"collision_sha256": schedule.collision_sha256, "parents": [], "fail": 0, "production_enabled": false}
	for parent in 16:
		var native: Array[ArrayMesh] = [null, null]
		for descriptor: Dictionary in plan.meshes:
			if int(descriptor.parent_id) != parent:
				continue
			if FileAccess.get_sha256(descriptor.path) != descriptor.source_sha256:
				return 1
			var kind := int(descriptor.kind)
			var resource: Resource = ResourceLoader.load(descriptor.path)
			native[kind] = resource.precision_original if bool(descriptor.precision_guarded) and kind == 0 else resource.meshes[kind]
			for index in bundle.descriptors.size():
				if int(bundle.descriptors[index].id) == int(descriptor.id):
					native[kind] = bundle.meshes[index]
		if native[0] == null or native[1] == null:
			return 1
		var high := Join.join([native[1], additions[parent]])
		if not Join.conserved(high, [native[1], additions[parent]]):
			return 1
		var fixed_path: String = original.cells[parent].fixed
		var fixed: Resource = ResourceLoader.load(fixed_path)
		var meshes: Array[ArrayMesh] = [native[0], high, fixed.meshes[0]]
		var context := {"out": out, "configuration": name_value, "level": int(plan.configuration.level),
			"parent_id": parent, "collision_sha256": schedule.collision_sha256, "owners_sha256": schedule.owners_sha256,
			"source_hash": (str(row.plan_sha256) + str(schedule.owners_sha256) + FileAccess.get_sha256(fixed_path)).sha256_text(),
			"game_sources": PackedInt32Array(row.parts[parent].expected), "audit": audit}
		var root := _page(meshes, -1, -1, context)
		if root.is_empty():
			return 1
		root["cuts"] = layout.parents[parent].cuts
		root["children"] = []
		var pieces := _split(meshes, root.cuts)
		if pieces.is_empty():
			return 1
		for child in 4:
			var child_meshes: Array[ArrayMesh] = [pieces[0][child], pieces[1][child], pieces[2][child]]
			var entry := _page(child_meshes, parent * 4 + child, -1, context)
			if entry.is_empty():
				return 1
			var old: Dictionary = layout.parents[parent].children[child]
			if old.has("children") and not old.children.is_empty():
				entry["cuts"] = old.cuts
				entry["children"] = []
				var leaves := _split(child_meshes, old.cuts)
				if leaves.is_empty():
					return 1
				for leaf in 4:
					var leaf_meshes: Array[ArrayMesh] = [leaves[0][leaf], leaves[1][leaf], leaves[2][leaf]]
					var leaf_entry := _page(leaf_meshes, 64 + int(entry.cell_id) * 4 + leaf, entry.cell_id, context)
					if leaf_entry.is_empty():
						return 1
					entry.children.append(leaf_entry)
			root.children.append(entry)
		report.parents.append(root)
		print("[Tokyo canonical spatial] audit=", audit, " configuration=", name_value, " parent=", parent, " faces=", root.triangles, " bytes=", root.bytes)
	var destination := out.path_join("audit_manifest.bin" if audit else "manifest.bin")
	if audit:
		var previous := FileAccess.open(out.path_join("manifest.bin"), FileAccess.READ)
		if previous == null or var_to_bytes(previous.get_var()) != var_to_bytes(report):
			return 1
		previous.close()
	if FileAccess.file_exists(destination):
		return 1
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_var(report)
	file.close()
	print("[Tokyo canonical spatial] COMPLETE audit=", audit, " configuration=", name_value, " parents=16 fail=0")
	return 0


static func _split(meshes: Array[ArrayMesh], cut: PackedFloat32Array) -> Array:
	var result: Array = []
	for mesh: ArrayMesh in meshes:
		var pieces := Split.split(mesh, cut)
		if not Join.conserved(mesh, pieces):
			push_error("Spatial child packed oriented faces are not conserved")
			return []
		result.append(pieces)
	return result


static func _page(meshes: Array[ArrayMesh], cell: int, ancestor: int, context: Dictionary) -> Dictionary:
	var descriptor := Spatial.descriptor(meshes)
	var page := Page.new()
	page.configuration = context.configuration
	page.level = context.level
	page.parent_id = context.parent_id
	page.cell_id = cell
	page.ancestor_id = ancestor
	page.source_hash = context.source_hash
	page.owners_sha256 = context.owners_sha256
	page.collision_sha256 = context.collision_sha256
	page.game_sources = context.game_sources
	page.meshes = meshes
	page.geometry_bytes = descriptor.bytes
	for count: int in descriptor.triangles:
		page.triangles += count
	if not page.valid():
		return {}
	var name_value := "parent_%02d.res" % page.parent_id if cell == -1 else "page_%03d.res" % cell
	var path: String = str(context.out).path_join(name_value)
	if not context.audit:
		if FileAccess.file_exists(path) or ResourceSaver.save(page, path, ResourceSaver.FLAG_COMPRESS) != OK:
			return {}
	var saved: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null or not saved.valid():
		return {}
	# 保存包不得通过外部网格引用暗中载入整份旧父包，绕过解码字节预算。
	for dependency: String in ResourceLoader.get_dependencies(path):
		if not dependency.ends_with(".gd"):
			push_error("Canonical page has an external non-script dependency: " + dependency)
			return {}
	for key: String in ["configuration", "level", "parent_id", "cell_id", "ancestor_id", "source_hash", "owners_sha256", "collision_sha256", "game_sources", "geometry_bytes", "triangles"]:
		if saved.get(key) != page.get(key):
			return {}
	for kind in 3:
		if not Baker._same_arrays(saved.meshes[kind], meshes[kind]) or saved.meshes[kind].get_aabb() != meshes[kind].get_aabb():
			return {}
	descriptor.merge({"path": path, "sha256": FileAccess.get_sha256(path), "parent_id": page.parent_id,
		"cell_id": cell, "ancestor_id": ancestor, "level": page.level, "page": true})
	return descriptor
