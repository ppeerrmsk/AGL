extends RefCounted
## R58离线选组成本来自正式LOD函数及实际父包来源，不另写一套细节阈值。
const Far := preload("res://scripts/tests/build_tokyo_far_clusters.gd")


static func run(root: String, output: String) -> int:
	if FileAccess.file_exists(output):
		return 1
	var path := root.path_join("r30-area-source-b/north_coast/city.json")
	if FileAccess.get_sha256(path) != Far.CITY_HASH:
		return 1
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var suppressed := Far.Duplicates.suppressed(city.buildings)
	var raw: Dictionary = {}
	for record: Dictionary in city.buildings:
		raw[str(record.id)] = record
	var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	var levels: Dictionary = {}
	for level in [1, 2, 3, 4, 5]:
		var records: Dictionary = {}
		for entry: Dictionary in catalog.cells:
			if entry.region != "north_coast":
				continue
			var source: Resource = ResourceLoader.load(entry.levels[level].path, "", ResourceLoader.CACHE_MODE_IGNORE)
			for identity: String in source.source_ids:
				var record: Dictionary = raw[identity]
				if not Far.eligible(record) or suppressed.has(identity):
					continue
				if records.has(identity):
					return 1
				var detail := Far.Builder.detail_level(record, Far.Levels.SCALES[level], true)
				var prepared := Far.record_for(record, level, detail)
				records[identity] = {"parent": source.cell_id, "detail": detail,
					"faces": Far.Cluster.face_count(prepared.rings[0], detail)}
		levels[str(level)] = {"max_scale": Far.maximum_scale(level), "records": records}
		print("[R58 far costs] level=", level, " records=", records.size())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify({"source_sha256": Far.CITY_HASH, "levels": levels}, "\t"))
	file.close()
	return 0
