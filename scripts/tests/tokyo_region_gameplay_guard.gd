extends RefCounted
## 离线样片尚无规范游戏楼补面；保守包围盒门禁止将有游戏楼的区域当普通低层处理。
const SOURCE := "res://resources/maps/yokohama_buildings.json"


static func read_source() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not raw is Dictionary or not raw.get("districts") is Array:
		return {}
	var accepted: Array = []
	var raw_ids: Array[int] = []
	var rejected: Array[int] = []
	for raw_id in raw.districts.size():
		if not raw.districts[raw_id] is Dictionary:
			return {}
		# 与正式加载共用接受顺序，不能用JSON下标冒充运行时source_id。
		var entry: Variant = BuildingRenderer._build_entry_static(raw.districts[raw_id])
		if not entry is Dictionary or entry.is_empty():
			rejected.append(raw_id)
			continue
		accepted.append(entry)
		raw_ids.append(raw_id)
	return {"entries": accepted, "raw_ids": raw_ids, "rejected_raw_ids": rejected,
		"source_sha256": FileAccess.get_sha256(SOURCE),
		"collision_sha256": var_to_bytes(accepted).hex_encode().sha256_text()}


static func inspect_bounds(bounds: Rect2, entries: Array) -> Dictionary:
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return {}
	var contacts: Array[int] = []
	var contained: Array[int] = []
	for id in entries.size():
		if not entries[id] is Dictionary or not entries[id].get("bbox") is Rect2:
			return {}
		var box: Rect2 = entries[id].bbox
		if not box.position.is_finite() or not box.size.is_finite() or box.size.x <= 0.0 or box.size.y <= 0.0:
			return {}
		# 共边也拒绝：不得因中心点在区外而漏掉跨界楼。
		if bounds.intersects(box, true):
			contacts.append(id)
			if bounds.encloses(box):
				contained.append(id)
	return {"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"contacts": contacts, "contained": contained, "standalone_merge_allowed": contacts.is_empty()}


static func protection_data(source: Dictionary) -> Dictionary:
	if source.is_empty() or source.get("entries",[]).is_empty() or source.get("raw_ids",[]).size()!=source.entries.size():
		return {}
	var rows: Array = []
	for id in source.entries.size():
		var entry: Dictionary = source.entries[id]
		var points: Array = []
		for point: Vector2 in entry.footprint:
			points.append([point.x,point.y])
		var bounds: Rect2 = entry.bbox
		rows.append({"source_id":id,"raw_id":source.raw_ids[id],"footprint":points,
			"tri_indices":Array(entry.tri_indices),"height_m":entry.max_real_h,
			"bbox":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]})
	return {"schema":1,"source_sha256":source.source_sha256,"collision_sha256":source.collision_sha256,
		"accepted_to_raw":source.raw_ids,"rejected_raw_ids":source.rejected_raw_ids,"entries":rows}


static func preserved_merge_allowed(bounds: Rect2, source: Dictionary, proof: Dictionary = {}) -> bool:
	if source.is_empty():
		return false
	var inspected := inspect_bounds(bounds,source.entries)
	if inspected.is_empty():
		return false
	if inspected.standalone_merge_allowed:
		return true
	# 相交分片仅认可外部逐几何审计：选中原屋和新增块面均不触碰正式游戏楼。
	if proof.size()!=5 or proof.get("source_sha256")!=source.source_sha256 or proof.get("collision_sha256")!=source.collision_sha256:
		return false
	var digest: Variant = proof.get("mask_sha256")
	if not digest is String or digest.length()!=64 or not digest.is_valid_hex_number():
		return false
	if digest!=JSON.stringify(protection_data(source)).sha256_text():
		return false
	for field: String in ["selected_intersects","blocks_intersects"]:
		if typeof(proof.get(field))!=TYPE_BOOL or proof[field]:
			return false
	return true


static func export_protection(output: String, root: String) -> int:
	root=root.replace("\\","/").simplify_path().trim_suffix("/")
	if not root.is_absolute_path() or not root.ends_with("/tmp/tokyo-bay-volume") or not output.is_absolute_path() \
			or output.simplify_path().get_base_dir()!=root or not output.get_file().begins_with("r358-") or not output.ends_with(".json"):
		return 1
	var data := protection_data(read_source())
	if data.is_empty():
		return 1
	var encoded := JSON.stringify(data)
	var expected: Variant = JSON.parse_string(encoded)
	if FileAccess.file_exists(output):
		return 0 if JSON.parse_string(FileAccess.get_file_as_string(output))==expected else 1
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(encoded)
	file.close()
	if JSON.parse_string(FileAccess.get_file_as_string(output))!=expected:
		return 1
	print("[Game protection] accepted=",data.entries.size()," sha256=",FileAccess.get_sha256(output))
	return 0


static func include_points(bounds: Rect2, points: Variant) -> Dictionary:
	if not points is Array or points.size() < 3:
		return {}
	for point: Variant in points:
		if not point is Array or point.size() != 2 or not typeof(point[0]) in [TYPE_INT, TYPE_FLOAT] or not typeof(point[1]) in [TYPE_INT, TYPE_FLOAT]:
			return {}
		var value := Vector2(float(point[0]), float(point[1]))
		if not value.is_finite():
			return {}
		bounds = bounds.expand(value)
	return {"bounds": bounds}


static func write_audit(output: String, source: Dictionary, root: String) -> int:
	# Shadow的res://不是原工作区；tmp证据根必须由调用者显式传入。
	root = root.replace("\\", "/").simplify_path().trim_suffix("/")
	if not root.is_absolute_path() or root.get_file() != "tokyo-bay-volume" or not output.is_absolute_path() or output.simplify_path().get_base_dir() != root \
			or not output.get_file().begins_with("r124-") or FileAccess.file_exists(output) or source.is_empty():
		return 1
	var regions := {"west_residential": Rect2(-6800,-2700,500,1000),
		"north_coast": Rect2(-6300,-3700,4000,2000), "yokohama": Rect2(-6300,-1700,2000,2000)}
	var report := {"regions": {}, "collision_sha256": source.collision_sha256,
		"game_source_sha256": source.source_sha256, "accepted_count": source.entries.size(),
		"rejected_raw_ids": source.rejected_raw_ids, "accepted_to_raw": source.raw_ids,
		"production_enabled": false, "canonical_migration_complete": false}
	for region: String in regions:
		var inspected := inspect_bounds(regions[region], source.entries)
		if inspected.is_empty():
			return 1
		report.regions[region] = inspected
	var catalog_path := root.path_join("r112-native-a/catalog.res")
	var catalog: Resource = load(catalog_path)
	if catalog == null or not catalog.valid() or catalog.collision_sha256 != source.collision_sha256:
		return 1
	report.catalog_sha256 = FileAccess.get_sha256(catalog_path)
	var coverage_path := root.path_join("r112-native-a/coverage-lod5_full.bin")
	var coverage_file := FileAccess.open(coverage_path, FileAccess.READ)
	if coverage_file == null:
		return 1
	var coverage: Variant = coverage_file.get_var(false)
	coverage_file.close()
	if not coverage is Dictionary or not coverage.get("verified", false) or coverage.get("catalog_sha256") != report.catalog_sha256 \
			or coverage.get("collision_sha256") != source.collision_sha256:
		return 1
	report.current_canonical_source_count = coverage.sources.size()
	report.current_canonical_page_count = coverage.pages.size()
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[Tokyo regional gameplay] accepted=", source.entries.size(), " regions=", report.regions,
		" current_canonical_sources=", report.current_canonical_source_count)
	return 0
