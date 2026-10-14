extends RefCounted
## 已认可块面移入全图owner：不再次简化，不重新提取，不改变高楼或固定层。
const Transfer := preload("res://scripts/tests/build_tokyo_owned_region_blocks.gd")
const Native := preload("res://scripts/tests/build_tokyo_regional_native.gd")
const Same := preload("res://scripts/tests/audit_tokyo_region_sample.gd")
const Guard := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")


static func run(config_path: String, expected_sha: String) -> int:
	if expected_sha.length()!=64 or FileAccess.get_sha256(config_path)!=expected_sha:
		return 1
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	var root := str(config.get("root",""))
	var output := str(config.get("output",""))
	if not Native.Builder.valid_sample_output(root,output) or DirAccess.dir_exists_absolute(output):
		return 1
	for name: String in ["manifest","audit"]:
		if FileAccess.get_sha256(str(config.get(name,"")))!=config.get(name+"_sha256"):
			return 1
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.manifest))
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.audit))
	var digest := str(manifest.get("registry_sha256",""))
	if digest.length()!=64 or audit.get("registry_sha256")!=digest or audit.get("fail",1)!=0 or not audit.get("partial",false) \
			or audit.get("regions",[]).size()!=manifest.get("regions",[]).size() or config.get("candidates",{}).size()!=manifest.regions.size():
		return 1
	var gameplay := Guard.read_source()
	if gameplay.is_empty():
		return 1
	var result := {"registry_sha256":digest,"regions":[],"fail":0,"partial":true,"canonical_ready":false,
		"native_manifest_sha256":config.manifest_sha256,"native_audit_sha256":config.audit_sha256,
		"collision_sha256":gameplay.collision_sha256,"game_source_sha256":gameplay.source_sha256}
	for row: Dictionary in manifest.regions:
		var name := str(row.region)
		var candidate_binding: Dictionary = config.candidates.get(name,{})
		var source_path := str(manifest.source_routes[name].index)
		var candidate_path := str(candidate_binding.get("index",""))
		var report_path := candidate_path.get_base_dir().path_join("candidate_report.json")
		if FileAccess.get_sha256(candidate_path)!=candidate_binding.get("index_sha256") or FileAccess.get_sha256(report_path)!=candidate_binding.get("report_sha256"):
			return 1
		var candidate_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path))
		if candidate_report.get("fail",1)!=0 or candidate_report.get("rows",[]).size()!=7 or candidate_report.get("source_index_sha256")!=FileAccess.get_sha256(source_path):
			return 1
		var selected_slots: Array[bool] = []
		for slot in 7:
			var cost: Dictionary = candidate_report.rows[slot]
			if cost.configuration!=("mid4" if slot==6 else "lod%d_full" % slot):
				return 1
			selected_slots.append(int(cost.result_faces)<=int(cost.original_faces))
		var full: Resource = ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var owned: Resource = ResourceLoader.load(row.index,"",ResourceLoader.CACHE_MODE_IGNORE)
		var candidate: Resource = ResourceLoader.load(candidate_path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if full==null or owned==null or candidate==null or not full.valid() or not owned.valid(digest) or not candidate.valid() \
				or owned.regional_id!=name or full.source_hash!=candidate.source_hash or full.source_count!=candidate.source_count or full.source_count!=owned.source_count:
			return 1
		var bounds: Rect2 = candidate.bounds
		for entry: Dictionary in candidate.cells:
			bounds=bounds.merge(entry.content_bounds)
		if not Guard.preserved_merge_allowed(bounds,gameplay,candidate_report.get("gameplay_protection",{})):
			return 1
		var target: Resource = owned.duplicate(true)
		var directory := output.path_join(name)
		DirAccess.make_dir_recursive_absolute(directory)
		var saved_rows: Array = []
		var before := PackedInt64Array([0,0,0,0,0,0,0])
		var after := before.duplicate()
		for id in target.cells.size():
			var entry: Dictionary = target.cells[id]
			if candidate.cells[id].fixed!=full.cells[id].fixed or entry.fixed!=full.cells[id].fixed:
				return 1
			entry.content_bounds=(entry.content_bounds as Rect2).merge(candidate.cells[id].content_bounds)
			for slot in 7:
				var original_descriptor: Dictionary = full.cells[id].mid if slot==6 else full.cells[id].levels[slot]
				var candidate_descriptor: Dictionary = candidate.cells[id].mid if slot==6 else candidate.cells[id].levels[slot]
				var descriptor: Dictionary = entry.mid if slot==6 else entry.levels[slot]
				var original_page: Resource = ResourceLoader.load(original_descriptor.path,"",ResourceLoader.CACHE_MODE_IGNORE)
				var owned_page: Resource = ResourceLoader.load(descriptor.path,"",ResourceLoader.CACHE_MODE_IGNORE)
				var candidate_page: Resource = ResourceLoader.load(candidate_descriptor.path,"",ResourceLoader.CACHE_MODE_IGNORE)
				var changed := Transfer.transfer(original_page,owned_page,candidate_page if selected_slots[slot] else original_page,true)
				if changed==null:
					push_error("[Full owned blocks] exact transfer failed %s cell=%d slot=%d" % [name,id,slot])
					return 1
				changed.bounds=entry.content_bounds
				var path := directory.path_join("cell_%02d_slot_%d.res" % [id,slot])
				if ResourceSaver.save(changed,path,ResourceSaver.FLAG_COMPRESS)!=OK:
					return 1
				var saved: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
				if saved==null or not saved.valid() or saved.source_ids!=owned_page.source_ids or saved.height_hash!=owned_page.height_hash or saved.detail_counts!=owned_page.detail_counts:
					return 1
				for kind in 2:
					if not Same.same_mesh(changed.meshes[kind],saved.meshes[kind]):
						return 1
				before[slot]+=owned_page.triangles
				after[slot]+=saved.triangles
				descriptor.path=path
				descriptor.bytes=saved.geometry_bytes
				descriptor.triangles=saved.triangles
				saved_rows.append({"cell":id,"slot":slot,"path":path,"sha256":FileAccess.get_sha256(path),"triangles":saved.triangles})
		for slot in 7:
			if after[slot]>before[slot]:
				return 1
		var index_path := directory.path_join("index.res")
		if not target.valid(digest) or ResourceSaver.save(target,index_path,ResourceSaver.FLAG_COMPRESS)!=OK:
			return 1
		var reloaded: Resource = ResourceLoader.load(index_path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if reloaded==null or not reloaded.valid(digest) or reloaded.regional_nonowner_ids!=owned.regional_nonowner_ids:
			return 1
		result.regions.append({"region":name,"index":index_path,"index_sha256":FileAccess.get_sha256(index_path),"rows":saved_rows,"before":Array(before),"after":Array(after),"block_slots":selected_slots})
		print("[Full owned blocks] ",name," saved=",saved_rows.size()," before=",before," after=",after)
	var file := FileAccess.open(output.path_join("batch_blocks_manifest.json"),FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify(result))
	file.close()
	return 0
