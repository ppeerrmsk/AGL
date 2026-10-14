extends RefCounted
## 新区独立原生基线：保存重载后从原始来源重建，不套用旧北岸常量。
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Levels := preload("res://scripts/rendering/tokyo_volume_archive.gd")
const Far := preload("res://scripts/tests/build_tokyo_far_clusters.gd")
const Cluster := preload("res://scripts/tests/build_tokyo_cluster_pages.gd")


func run(source_dir: String, output: String) -> int:
	var source_path := source_dir.path_join("city.json")
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var index: Resource = ResourceLoader.load(output.path_join("index.res"), "", ResourceLoader.CACHE_MODE_IGNORE)
	if index == null or not index.valid() or index.source_hash != FileAccess.get_sha256(source_path) + ":" + FileAccess.get_sha256(source_dir.path_join("ground.json")):
		return 1
	var raw: Dictionary = {}
	for record: Dictionary in city.buildings:
		if raw.has(String(record.id)):
			return 1
		raw[String(record.id)] = record
	var seen: Dictionary = {}
	var costs: Dictionary = {}
	var checked := 0
	var faces: Dictionary = {}
	for level in 6:
		costs[str(level)] = {"max_scale": Far.maximum_scale(level), "records": {}}
		faces[str(level)] = 0
	for entry: Dictionary in index.cells:
		var fixed: Resource = ResourceLoader.load(entry.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
		if fixed == null or not fixed.valid() or fixed.triangles != entry.fixed_triangles or fixed.geometry_bytes != entry.fixed_bytes:
			return 1
		var identities := PackedStringArray()
		for slot in 7:
			var level: int = slot if slot < 6 else 4
			var descriptor: Dictionary = entry.levels[level] if slot < 6 else entry.mid
			var cell: Resource = ResourceLoader.load(descriptor.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if cell == null or not cell.valid() or cell.triangles != descriptor.triangles or cell.geometry_bytes != descriptor.bytes:
				return 1
			if slot == 0:
				identities = cell.source_ids
				for identity: String in identities:
					if seen.has(identity) or not raw.has(identity):
						return 1
					seen[identity] = entry.id
			elif cell.source_ids != identities:
				return 1
			var low := Geometry.new()
			var known := Geometry.new()
			var height_lines := PackedStringArray()
			for identity: String in identities:
				var record: Dictionary = raw[identity]
				height_lines.append("%s:%.6f:%.6f" % [identity, record.height_m, record.min_height_m])
				if record.get("defer_render", false) or not record.get("render_outline", true):
					continue
				var scale_value: float = 1.0 if slot == 6 and record.height_source == "fallback" else Levels.SCALES[level]
				var detail := Builder.detail_level(record, scale_value, true)
				Factory._add_ring_building(low if record.height_source == "fallback" else known, record, float(record.height_m) * 0.5, detail)
				if slot < 6 and level > 0 and Far.eligible(record):
					costs[str(level)].records[identity] = {"parent": entry.id, "detail": detail, "faces": Cluster.face_count(record.rings[0], detail)}
			if cell.height_hash != "\n".join(height_lines).sha256_text() or not same_mesh(low.mesh(), cell.meshes[0]) or not same_mesh(known.mesh(), cell.meshes[1]):
				push_error("[Tokyo regional sample] source rebuild mismatch cell=%d slot=%d" % [entry.id, slot])
				return 1
			checked += 1
			if slot < 6:
				faces[str(level)] += cell.triangles
	if seen.size() != raw.size() or seen.size() != index.source_count:
		return 1
	costs.erase("0")
	var report := {"source_sha256": FileAccess.get_sha256(source_path), "ground_sha256": FileAccess.get_sha256(source_dir.path_join("ground.json")),
		"levels": costs, "checked_archives": checked, "source_records": seen.size(), "faces_by_level": faces,
		"native_source_rebuild_ok": true, "production_enabled": false, "joined_ready": false, "fail": 0}
	var file := FileAccess.open(output.path_join("native_costs.json"), FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify(report))
	file.close()
	print("[Tokyo regional sample audit] archives=", checked, " sources=", seen.size(), " faces=", faces, " fail=0")
	return 0


static func same_mesh(first: ArrayMesh, second: ArrayMesh) -> bool:
	if first.get_surface_count() != second.get_surface_count():
		return false
	for surface in first.get_surface_count():
		var a := first.surface_get_arrays(surface)
		var b := second.surface_get_arrays(surface)
		for channel in a.size():
			if a[channel] != b[channel]:
				return false
	return true
