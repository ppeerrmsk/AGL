extends RefCounted
## 独立进程读取最终索引/原生包；来源全集、原高、固定层与全局归属门。
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Index := preload("res://scripts/rendering/tokyo_cell_index.gd")
const Same := preload("res://scripts/tests/audit_tokyo_region_sample.gd")
const Native := preload("res://scripts/tests/build_tokyo_regional_native.gd")


static func run(directory: String, root: String) -> int:
	var registry_path := root.path_join("ownership.json")
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(registry_path))
	var digest := FileAccess.get_sha256(registry_path)
	var batch := Native.read_batch(registry,digest)
	if batch.is_empty():
		return 1
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("batch_manifest.json" if batch.partial else "manifest.json")))
	var routes := Native.read_routes(root,registry,digest)
	if routes.is_empty() or report.registry_sha256!=digest or report.regions.size()!=batch.regions.size() \
			or report.get("source_routes",routes)!=routes:
		return 1
	if batch.partial and report.get("batch")!=batch:
		return 1
	var global_owners: Dictionary = {}
	var regions: Array = []
	for region: String in batch.regions:
		var matched: Array = report.regions.filter(func(row: Dictionary) -> bool: return row.region==region)
		if matched.size()!=1:
			return 1
		var records: Dictionary = {}
		var source_path := root.path_join(region).path_join("city.json")
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
		var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(String(routes[region].source).path_join("city.json")))
		if Native.Gate.validate(data,original,registry,region,digest).is_empty():
			return 1
		for name_value: String in ["city.json","ground.json"]:
			if FileAccess.get_sha256(String(routes[region].source).path_join(name_value))!=registry.inputs[region][name_value]:
				return 1
		if FileAccess.get_sha256(root.path_join(region).path_join("ground.json"))!=registry.inputs[region]["ground.json"]:
			return 1
		for raw: Dictionary in data.buildings:
			records[raw.id]=raw
		var saved: Resource = ResourceLoader.load(matched[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		var old_index: Resource = ResourceLoader.load(routes[region].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if old_index==null or not old_index.valid() or old_index.source_hash!=registry.inputs[region]["city.json"]+":"+registry.inputs[region]["ground.json"]:
			return 1
		var expected_ids := PackedStringArray()
		for identity: String in records:
			if registry.assignments[identity].owner!=region:
				expected_ids.append(identity)
		expected_ids.sort()
		if saved==null or saved.valid() or not saved.valid(digest) or saved.regional_id!=region or saved.regional_nonowner_ids!=expected_ids \
				or saved.bounds!=old_index.bounds or saved.source_count!=records.size() or saved.source_hash!=FileAccess.get_sha256(source_path)+":"+registry.inputs[region]["ground.json"]:
			return 1
		var seen: Dictionary = {}
		var faces := PackedInt64Array([0,0,0,0,0,0,0])
		var removed := PackedInt64Array([0,0,0,0,0,0,0])
		var checked := 0
		for entry: Dictionary in saved.cells:
			var previous: Dictionary = old_index.cells[entry.id]
			if entry.fixed!=previous.fixed or entry.fixed_bytes!=previous.fixed_bytes or entry.fixed_triangles!=previous.fixed_triangles or entry.bounds!=previous.bounds or entry.content_bounds!=previous.content_bounds or entry.max_height_px!=previous.max_height_px:
				return 1
			var fixed: Resource = ResourceLoader.load(entry.fixed,"",ResourceLoader.CACHE_MODE_IGNORE)
			if not fixed.valid() or fixed.triangles!=entry.fixed_triangles or fixed.geometry_bytes!=entry.fixed_bytes:
				return 1
			for slot in 7:
				var descriptor: Dictionary = entry.mid if slot==6 else entry.levels[slot]
				var prior: Dictionary = previous.mid if slot==6 else previous.levels[slot]
				var rows: Array = matched[0].rows.filter(func(row: Dictionary) -> bool: return row.cell==entry.id and row.slot==slot)
				if rows.size()!=1 or rows[0].path!=descriptor.path or rows[0].source!=prior.path or FileAccess.get_sha256(descriptor.path)!=rows[0].sha256 or FileAccess.get_sha256(prior.path)!=rows[0].source_sha256:
					return 1
				var cell: Resource = ResourceLoader.load(descriptor.path,"",ResourceLoader.CACHE_MODE_IGNORE)
				var old: Resource = ResourceLoader.load(prior.path,"",ResourceLoader.CACHE_MODE_IGNORE)
				if not cell.valid() or cell.source_ids!=old.source_ids or cell.height_hash!=old.height_hash or cell.bounds!=old.bounds or cell.triangles!=descriptor.triangles or cell.geometry_bytes!=descriptor.bytes or Array(cell.detail_counts)!=descriptor.counts:
					return 1
				var height_lines := PackedStringArray()
				for identity: String in cell.source_ids:
					var raw: Dictionary = records[identity]
					height_lines.append("%s:%.6f:%.6f" % [identity,raw.height_m,raw.min_height_m])
					if slot==0:
						if seen.has(identity):
							return 1
						seen[identity]=true
						if identity not in expected_ids:
							if global_owners.has(identity):
								return 1
							global_owners[identity]=region
				if cell.height_hash!="\n".join(height_lines).sha256_text() or old.triangles-cell.triangles!=rows[0].removed_faces or cell.detail_counts[3]<old.detail_counts[3]:
					return 1
				var byte_count := 0
				var face_count := 0
				for kind in cell.meshes.size():
					byte_count+=Builder.mesh_bytes(cell.meshes[kind])
					face_count+=preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(cell.meshes[kind])
					if rows[0].removed_faces==0 and not Same.same_mesh(cell.meshes[kind],old.meshes[kind]):
						return 1
				if cell.precision_original!=null:
					byte_count+=Builder.mesh_bytes(cell.precision_original)
				if byte_count!=cell.geometry_bytes or face_count!=cell.triangles:
					return 1
				faces[slot]+=cell.triangles
				removed[slot]+=old.triangles-cell.triangles
				checked+=1
		if seen.size()!=records.size():
			return 1
		regions.append({"region":region,"checked_building_archives":checked,"fixed_unchanged":16,"sources":seen.size(),"nonowners":expected_ids.size(),"faces":Array(faces),"removed_faces":Array(removed)})
	if global_owners!=report.owner_ids:
		return 1
	var expected_count := 0
	for identity: String in registry.assignments:
		if batch.regions.has(registry.assignments[identity].owner):
			expected_count+=1
			if global_owners.get(identity,"")!=registry.assignments[identity].owner:
				return 1
	if global_owners.size()!=expected_count:
		return 1
	for family: Dictionary in registry.families:
		if not batch.regions.has(family.owner):
			continue
		for identity: String in family.members:
			if global_owners.get(identity,"")!=family.owner:
				return 1
	var output := directory.path_join("batch_saved_audit.json" if batch.partial else "saved_audit.json")
	if FileAccess.file_exists(output):
		return 1
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"regions":regions,"unique_owners":global_owners.size(),"families":registry.families.size(),"registry_sha256":digest,"fail":0,"canonical_ready":false,"partial":batch.partial}))
	file.close()
	print("[Regional native saved audit] ",regions," owners=",global_owners.size()," families=",registry.families.size()," fail=0")
	return 0


static func compare_previous(current_dir: String, previous_dir: String, output: String) -> int:
	if not Builder.valid_sample_output(current_dir,output.get_base_dir()) or FileAccess.file_exists(output):
		return 1
	var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(current_dir.path_join("manifest.json")))
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(previous_dir.path_join("manifest.json")))
	var rows: Array = []
	var different_files := 0
	for region: String in ["north_coast","yokohama"]:
		var new_rows: Array = current.regions.filter(func(row: Dictionary) -> bool: return row.region==region)
		var old_rows: Array = previous.regions.filter(func(row: Dictionary) -> bool: return row.region==region)
		if new_rows.size()!=1 or old_rows.size()!=1 or new_rows[0].nonowners!=old_rows[0].nonowners:
			return 1
		for row: Dictionary in new_rows[0].rows:
			var matching: Array = old_rows[0].rows.filter(func(item: Dictionary) -> bool: return item.cell==row.cell and item.slot==row.slot)
			if matching.size()!=1 or row.source!=matching[0].source or row.source_sha256!=matching[0].source_sha256 \
					or FileAccess.get_sha256(row.path)!=row.sha256 or FileAccess.get_sha256(matching[0].path)!=matching[0].sha256:
				return 1
			var fresh: Resource = ResourceLoader.load(row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var old: Resource = ResourceLoader.load(matching[0].path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if fresh==null or old==null or not fresh.valid() or not old.valid():
				return 1
			for key: String in ["schema_version","cell_id","level","bounds","geometry_bytes","triangles","source_ids","height_hash","detail_counts","precision_max_scale","precision_triangles"]:
				if fresh.get(key)!=old.get(key):
					return 1
			for kind in 2:
				if not Same.same_mesh(fresh.meshes[kind],old.meshes[kind]) or fresh.meshes[kind].get("_surfaces")!=old.meshes[kind].get("_surfaces"):
					return 1
			if (fresh.precision_original==null)!=(old.precision_original==null):
				return 1
			if fresh.precision_original!=null and (not Same.same_mesh(fresh.precision_original,old.precision_original) \
					or fresh.precision_original.get("_surfaces")!=old.precision_original.get("_surfaces")):
				return 1
			different_files+=int(row.sha256!=matching[0].sha256)
			rows.append({"region":region,"cell":row.cell,"slot":row.slot,"current":row.path,"current_sha256":row.sha256,"previous":matching[0].path,"previous_sha256":matching[0].sha256})
	if rows.size()!=224:
		return 1
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"rows":rows,"different_file_hashes":different_files,"packed_surfaces_equal":true,
		"decoded_arrays_equal":true,"properties_equal":true,"current_manifest_sha256":FileAccess.get_sha256(current_dir.path_join("manifest.json")),
		"previous_manifest_sha256":FileAccess.get_sha256(previous_dir.path_join("manifest.json"))}))
	file.close()
	print("[Regional stable previous] archives=",rows.size()," different_file_hashes=",different_files," packed_and_decoded_equal=true fail=0")
	return 0
