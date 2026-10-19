extends RefCounted
## 旧规范父包的边界迁移准备；不伪造完成的规范目录，也不覆盖旧目录。
const Diff := preload("res://scripts/experiments/tokyo_packed_mesh_difference.gd")
const Far := preload("res://scripts/tests/build_tokyo_far_clusters.gd")
const Components := preload("res://scripts/tests/build_tokyo_mesh_components.gd")
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")


static func target_meshes(records: Array, configuration: String) -> Array[ArrayMesh]:
	var low := Far.Geometry.new()
	var high := Far.Geometry.new()
	var level := int(configuration.substr(3,1))
	for raw: Dictionary in records:
		var scale_value: float = 1.0 if configuration=="lod4_mid" and raw.height_source=="fallback" else Far.Levels.SCALES[level]
		var detail := Far.Builder.detail_level(raw,scale_value,true)
		var prepared := raw if configuration.ends_with("guarded") else Far.record_for(raw,level,detail)
		Far.Factory._add_ring_building(low if raw.height_source=="fallback" else high,prepared,float(raw.height_m)*0.5,detail)
	return [Far.Palette.recolor(low.mesh()),Far.Palette.recolor(high.mesh())]


func run() -> int:
	var source_root := OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_SOURCE")
	var output := OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_OUT")
	if not Far.Builder.valid_sample_output(source_root,output):
		return 1
	var base := source_root.get_base_dir()
	var old_path := base.path_join("r24-owned-source-b/ownership.json")
	var new_path := source_root.path_join("ownership.json")
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_path))
	var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(new_path))
	var moved: Dictionary = {}
	for identity: String in old.assignments:
		if not current.assignments.has(identity):
			return 1
		if old.assignments[identity].owner!=current.assignments[identity].owner:
			if current.assignments[identity].owner!="west_residential":
				return 1
			moved[identity]=old.assignments[identity].owner
	if moved.size()!=34:
		return 1
	var north_path := base.path_join("r30-area-source-b/north_coast/city.json")
	var south_path := base.path_join("r10c-roof-source/city.json")
	if FileAccess.get_sha256(north_path)!=Far.CITY_HASH or FileAccess.get_sha256(south_path)!=old.inputs.yokohama["city.json"]:
		return 1
	var records: Dictionary = {}
	for pair: Array in [[north_path,"north_coast"],[south_path,"yokohama"]]:
		var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(pair[0]))
		for raw: Dictionary in city.buildings:
			if moved.get(raw.id,"")==pair[1]:
				if records.has(raw.id) or raw.get("defer_render",false) or not raw.get("render_outline",true) or raw.get("roof_shape","flat")!="flat":
					return 1
				records[raw.id]=raw
	if records.size()!=moved.size():
		return 1
	var index: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	var parent_records: Dictionary = {}
	var seen: Dictionary = {}
	for cell: Dictionary in index.cells:
		var archive: Resource = load(cell.levels[5].path)
		var selected: Array = []
		for identity: String in archive.source_ids:
			if not records.has(identity):
				continue
			if seen.has(identity):
				return 1
			selected.append(records[identity])
			seen[identity]=cell.id
		if not selected.is_empty():
			parent_records[cell.id]=selected
	if seen.size()!=34:
		return 1
	# mid仍使用R44旧合并组：它也必须不包含要转移的来源。
	var middle: Resource = load("res://resources/maps/tokyo_volume_preview/r44_lod_pages/mid/index.res")
	for parent: Dictionary in middle.parents:
		for identity: String in parent.get("cluster_sources",PackedStringArray()):
			if moved.has(identity):
				print("[Tokyo boundary transfer] mid cluster affected: ",identity)
				return 1
	var catalog_path := base.path_join("r112-native-a/catalog.res")
	var catalog: Resource = load(catalog_path)
	if catalog==null or not catalog.valid():
		return 1
	var report := {"source_catalog":catalog_path,"source_catalog_sha256":FileAccess.get_sha256(catalog_path),
		"old_registry_sha256":FileAccess.get_sha256(old_path),"new_registry_sha256":FileAccess.get_sha256(new_path),
		"moved_sources":moved,"source_parents":seen,"rows":[],"canonical_ready":false,"production_enabled":false,"fail":0}
	DirAccess.make_dir_recursive_absolute(output)
	for configuration: String in Catalog.CONFIGURATIONS:
		for parent: int in parent_records:
			var entry: Dictionary = catalog.configurations[configuration][parent]
			if FileAccess.get_sha256(entry.path)!=entry.sha256:
				return 1
			var page: Resource = ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if page==null or not page.valid() or page.stream_identity()!=catalog.descriptors[entry.path].canonical_identity:
				return 1
			var removed := target_meshes(parent_records[parent],configuration)
			var remaining: Array[ArrayMesh] = []
			var counts: Array[int] = []
			for kind in 2:
				var result := Diff.subtract(page.meshes[kind],removed[kind])
				if result.is_empty() or not Diff.conserved(page.meshes[kind],result.mesh,removed[kind]):
					push_error("[Tokyo boundary transfer] native source differs %s parent=%d kind=%d" % [configuration,parent,kind])
					return 1
				remaining.append(result.mesh)
				counts.append(result.removed)
			var directory := output.path_join(configuration)
			DirAccess.make_dir_recursive_absolute(directory)
			var stem := "parent_%02d" % parent
			var source: String = report.source_catalog_sha256+report.new_registry_sha256+configuration+str(parent)
			var residual := Components._save(remaining,source+"remaining",directory.path_join(stem+"_remaining.res"))
			var delta := Components._save(removed,source+"removed",directory.path_join(stem+"_removed.res"))
			if residual.is_empty() or delta.is_empty():
				return 1
			report.rows.append({"configuration":configuration,"parent":parent,"original":entry.path,"original_sha256":entry.sha256,
				"original_identity":page.stream_identity(),"remaining":residual,"removed":delta,"removed_faces":counts,
				"game_sources":Array(page.game_sources),"fixed_unchanged":true})
			print("[Tokyo boundary transfer] ",configuration," parent=",parent," removed=",counts)
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	print("[Tokyo boundary transfer] roots=",parent_records.size()," variants=",report.rows.size()," sources=",seen.size()," fail=0")
	return 0


static func audit(directory: String, root: String) -> int:
	var output := directory.path_join("saved_audit.json")
	if FileAccess.file_exists(output):
		return 1
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	if report.get("fail",1)!=0 or report.get("canonical_ready",true) or report.rows.size()!=22 \
			or FileAccess.get_sha256(report.source_catalog)!=report.source_catalog_sha256 \
			or FileAccess.get_sha256(root.path_join("ownership.json"))!=report.new_registry_sha256 \
			or FileAccess.get_sha256(root.get_base_dir().path_join("r24-owned-source-b/ownership.json"))!=report.old_registry_sha256:
		print("[Boundary audit rejected] source identity")
		return 1
	var catalog: Resource = load(report.source_catalog)
	var game := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd").read_source()
	if catalog==null or not catalog.valid() or game.is_empty() or game.collision_sha256!=catalog.collision_sha256:
		print("[Boundary audit rejected] catalog/game identity")
		return 1
	var checked: Dictionary = {}
	var totals: Dictionary = {}
	var byte_totals: Dictionary = {}
	for row: Dictionary in report.rows:
		var key := "%s:%d" % [row.configuration,int(row.parent)]
		if checked.has(key) or row.configuration not in Catalog.CONFIGURATIONS or int(row.parent) not in [3,11]:
			print("[Boundary audit rejected] duplicate row ",key)
			return 1
		checked[key]=true
		var entry: Dictionary = catalog.configurations[row.configuration][int(row.parent)]
		if row.original!=entry.path or row.original_sha256!=entry.sha256 or FileAccess.get_sha256(entry.path)!=entry.sha256:
			print("[Boundary audit rejected] original path/sha ",key)
			return 1
		var original: Resource = ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if original==null or not original.valid() or original.stream_identity()!=catalog.descriptors[entry.path].canonical_identity \
				or PackedInt32Array(row.game_sources)!=original.game_sources:
			print("[Boundary audit rejected] original native identity ",key)
			return 1
		var meshes: Array[Resource] = []
		for field: String in ["remaining","removed"]:
			var info: Dictionary = row[field]
			if FileAccess.get_sha256(info.path)!=info.sha256:
				print("[Boundary audit rejected] component sha ",key," ",field)
				return 1
			var saved: Resource = ResourceLoader.load(info.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if saved==null or not saved.valid() or saved.meshes.size()!=2 or saved.source_hash!=info.canonical_identity.source or saved.geometry_bytes!=int(info.bytes):
				print("[Boundary audit rejected] component identity ",key," ",field)
				return 1
			meshes.append(saved)
		var removed_faces := 0
		var remaining_bytes := 0
		for kind in 2:
			var remaining: ArrayMesh = meshes[0].meshes[kind]
			var delta: ArrayMesh = meshes[1].meshes[kind]
			if not Diff.conserved(original.meshes[kind],remaining,delta) \
					or Far.Builder.mesh_bytes(remaining)!=meshes[0].mesh_bytes[kind] or Far.Builder.mesh_bytes(delta)!=meshes[1].mesh_bytes[kind]:
				print("[Boundary audit rejected] conservation/bytes ",key," kind=",kind)
				return 1
			var faces := Far.Indexed.triangles(delta)
			if faces!=int(row.removed_faces[kind]):
				print("[Boundary audit rejected] removed face count ",key," kind=",kind)
				return 1
			removed_faces+=faces
			remaining_bytes+=Far.Builder.mesh_bytes(remaining)
			if delta.get_surface_count()>0:
				var box := delta.get_aabb()
				var protection := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd").inspect_bounds(Rect2(box.position.x,box.position.z,box.size.x,box.size.z),game.entries)
				if protection.is_empty() or not protection.standalone_merge_allowed:
					print("[Boundary audit rejected] gameplay overlap ",key," kind=",kind," ",protection)
					return 1
		if remaining_bytes>Far.Builder.mesh_bytes(original.meshes[0])+Far.Builder.mesh_bytes(original.meshes[1]):
			print("[Boundary audit rejected] residual bytes increase ",key)
			return 1
		totals[key]=removed_faces
		byte_totals[key]=remaining_bytes
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"variants":checked.size(),"components":checked.size()*2,"removed_faces":totals,
		"remaining_bytes":byte_totals,"gameplay_overlap":0,"collision_sha256":game.collision_sha256,"canonical_ready":false}))
	file.close()
	print("[Tokyo boundary saved audit] variants=",checked.size()," components=",checked.size()*2," gameplay_overlap=0 fail=0")
	return 0
