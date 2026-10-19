extends RefCounted
## R57远档候选：真实LOD原形重建后才合并；源/标高/地表和原形备用不动。
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Palette := preload("res://scripts/experiments/tokyo_palette.gd")
const Signature := preload("res://scripts/tests/tokyo_mesh_signature.gd")
const Duplicates := preload("res://scripts/experiments/tokyo_duplicate_outline.gd")
const Levels := preload("res://scripts/rendering/tokyo_volume_archive.gd")
const Cluster := preload("res://scripts/tests/build_tokyo_cluster_pages.gd")
const CITY_HASH := "ccdb340925d2646d98eaa873055951d46e095198dec20b057774354a5633a170"
var _records: Dictionary = {}
var _suppressed: Dictionary = {}


func run(root: String, output: String) -> int:
	if DirAccess.dir_exists_absolute(output):
		return 1
	var city_path := root.path_join("r30-area-source-b/north_coast/city.json")
	if FileAccess.get_sha256(city_path) != CITY_HASH:
		return 1
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(city_path))
	_suppressed = Duplicates.suppressed(city.buildings)
	for raw: Dictionary in city.buildings:
		_records[str(raw.id)] = raw
	var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res").duplicate(true)
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array[Dictionary] = []
	var levels := selected_levels(OS.get_environment("AGL_TOKYO_FAR_CLUSTER_LEVELS"))
	if levels.is_empty():
		return 1
	for level in levels:
		var prefix := OS.get_environment("AGL_TOKYO_FAR_CLUSTER_PLAN_PREFIX")
		var plan_path := root.path_join(("r57-far-clusters" if prefix.is_empty() else prefix) + "-%d-b.json" % level)
		var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
		if plan.source_sha256 != CITY_HASH or not is_equal_approx(plan.max_scale, maximum_scale(level)) or group_limit(plan) == 0 or not plan.has("prepared_barrier_rejected"):
			return 1
		if level == 4 and plan.get("profile", "") not in ["mid4", "mid6"]:
			return 1
		var accepted := 0
		var saved_total := 0
		for entry: Dictionary in catalog.cells:
			if entry.region != "north_coast":
				continue
			var source_path: String = entry.levels[level].path
			var source: Resource = ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE)
			var converted := _convert(source, plan)
			if converted.is_empty():
				return 1
			var result: Resource = source.duplicate(false)
			var meshes: Array[ArrayMesh] = [converted.mesh, source.meshes[1]]
			result.meshes = meshes
			result.triangles = 0
			result.geometry_bytes = 0
			Builder.finish(result)
			if not result.valid() or result.triangles > source.triangles or result.geometry_bytes > source.geometry_bytes:
				return 1
			accepted += converted.groups.size()
			saved_total += source.triangles - result.triangles
			var path := output.path_join("cell_%02d_lod_%d.res" % [source.cell_id, level])
			if ResourceSaver.save(result, path, ResourceSaver.FLAG_COMPRESS) != OK:
				return 1
			var saved: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if saved == null or not saved.valid() or Signature.of_mesh(saved.meshes[0]) != Signature.of_mesh(result.meshes[0]) \
					or Signature.of_mesh(saved.meshes[1]) != Signature.of_mesh(source.meshes[1]) or saved.height_hash != source.height_hash \
					or saved.source_ids != source.source_ids or saved.meshes[1].get("_surfaces") != source.meshes[1].get("_surfaces"):
				return 1
			if source.precision_original != null and Signature.of_mesh(saved.precision_original) != Signature.of_mesh(source.precision_original):
				return 1
			rows.append({"cell_id": source.cell_id, "level": level, "path": path, "sha256": FileAccess.get_sha256(path),
				"source": source_path, "source_sha256": FileAccess.get_sha256(source_path), "bytes": result.geometry_bytes,
				"before": source.triangles, "after": result.triangles, "groups": converted.groups,
				"max_scale": plan.max_scale, "plan_sha256": FileAccess.get_sha256(plan_path), "plan":plan_path,
				"block_profile":plan.get("profile","") if int(plan.get("schema",1))==2 else ""})
			entry.levels[level].path = path
			entry.levels[level].bytes = result.geometry_bytes
			entry.levels[level].triangles = result.triangles
			print("[R57 far bake] cell=", source.cell_id, " level=", level, " groups=", converted.groups.size(), " before=", source.triangles, " after=", result.triangles)
		if plan.get("cost_model", "") == "native_lod" and (accepted != plan.groups.size() or saved_total != int(plan.faces_saved)):
			return 1
	if not catalog.valid() or ResourceSaver.save(catalog, output.path_join("index.res"), ResourceSaver.FLAG_COMPRESS) != OK:
		return 1
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "production_enabled": false, "fail": 0}, "\t"))
	file.close()
	print("[R57 far bake] COMPLETE pages=", rows.size(), " fail=0")
	return 0


static func selected_levels(value: String) -> Array[int]:
	if value.is_empty():
		return [1,2]
	var result: Array[int] = []
	for token: String in value.split(","):
		if token not in ["1","2","3","4","5"] or int(token) in result:
			return []
		result.append(int(token))
	return result


static func maximum_scale(level: int) -> float:
	# 最细候选不能套用LOD3容差；静态候选只覆盖当前正式相机最大倍率。
	return 5.0 if level==5 else (float(Levels.CUTS[level])*1.08 if level in [1,2,3,4] else 0.0)


func _convert(source: Resource, plan: Dictionary, packed_palette: bool = true) -> Dictionary:
	var maximum := group_limit(plan)
	if maximum == 0:
		return {}
	var local: Dictionary = {}
	for identity: String in source.source_ids:
		local[identity] = true
	var replacements: Dictionary = {}
	var groups: Array[Dictionary] = []
	for group: Dictionary in plan.groups:
		if group.ids.size() < 2 or group.ids.size() > maximum or group.outer.size() < int(plan.get("min_vertices",3)) or group.triangles.size() % 3 != 0:
			return {}
		var valid := true
		var detail := 2
		var old_faces := 0
		var originals: Array = []
		for identity: String in group.ids:
			if not local.has(identity) or not _records.has(identity) or _suppressed.has(identity):
				valid = false
				break
			var raw: Dictionary = _records[identity]
			if not eligible(raw) or raw.height_m != group.height_m or raw.get("kind", "urban") != group.get("kind", "urban"):
				valid = false
				break
			var source_detail := Builder.detail_level(raw, Levels.SCALES[source.level], true)
			detail = mini(detail, source_detail)
			var prepared := record_for(raw, source.level, source_detail)
			old_faces += Cluster.face_count(prepared.rings[0], source_detail)
			# 变化范围来自实际远档原轮廓，不是已被area_lod替代的全细节轮廓。
			originals.append_array(prepared.rings[0].outer)
		if not valid:
			continue
		var ring := {"outer": group.outer, "holes": [], "triangles": group.triangles}
		var saved_faces := old_faces - Cluster.face_count(ring, detail)
		# 原生成本计划必须与最终使用的屋顶/墙面完全一致，不能回退为估算通过。
		if plan.get("cost_model", "") == "native_lod" and int(group.get("faces_saved", -1)) != saved_faces:
			return {}
		if saved_faces <= 0:
			continue
		var first: String = group.ids[0]
		var record: Dictionary = _records[first].duplicate()
		record.rings = [ring]
		groups.append({"ids": group.ids, "height_px": float(group.height_m) * 0.5, "original": originals, "candidate": group.outer})
		for identity: String in group.ids:
			if replacements.has(identity):
				return {}
			replacements[identity] = {"emit": identity == first, "record": record, "detail": detail}
	var before := Geometry.new()
	var after := Geometry.new()
	for identity: String in source.source_ids:
		var raw: Dictionary = _records[identity]
		if raw.height_source != "fallback" or raw.get("defer_render", false) or not raw.get("render_outline", true) or _suppressed.has(identity):
			continue
		var detail := Builder.detail_level(raw, Levels.SCALES[source.level], true)
		var record := record_for(raw, source.level, detail)
		Factory._add_ring_building(before, record, float(raw.height_m) * 0.5, detail)
		if replacements.has(identity):
			var replacement: Dictionary = replacements[identity]
			if replacement.emit:
				Factory._add_ring_building(after, replacement.record, float(raw.height_m) * 0.5, replacement.detail)
		else:
			Factory._add_ring_building(after, record, float(raw.height_m) * 0.5, detail)
	var reference := Palette.recolor(Indexed.pack(before.mesh())) if packed_palette else before.mesh()
	if Signature.of_mesh(reference) != Signature.of_mesh(source.meshes[0]):
		push_error("[Bench] R57 original low layer reconstruction differs cell=%d level=%d" % [source.cell_id, source.level])
		return {}
	return {"mesh": Palette.recolor(Indexed.pack(after.mesh())) if packed_palette else after.mesh(), "groups": groups}


static func group_limit(plan: Dictionary) -> int:
	if int(plan.get("schema",1))==1:
		return 8 if int(plan.get("max_group",8))==8 else 0
	if int(plan.get("schema",0))!=2 or plan.get("strategy")!="street_blocks":
		return 0
	var profiles := {"gentle":{"max_group":16,"grid":48,"max_span":60,"max_vertices":12,"occupied_error_px":2.0,"area_error":0.35,"roads":"all"},
		"street6":{"max_group":96,"grid":128,"max_span":160,"min_vertices":4,"max_vertices":8,"closure_steps":4,"occupied_error_px":6.0,"area_error":1.0,"roads":"structural","grouping":"road_components","link_gap":12.0},
		"street8":{"max_group":96,"grid":128,"max_span":160,"min_vertices":4,"max_vertices":8,"closure_steps":4,"occupied_error_px":8.0,"area_error":1.0,"roads":"structural","grouping":"road_components","link_gap":12.0},
		"far8wide":{"max_group":96,"grid":128,"max_span":160,"min_vertices":4,"max_vertices":8,"closure_steps":4,"occupied_error_px":8.0,"area_error":1.0,"roads":"structural"},
		"far12wide":{"max_group":96,"grid":128,"max_span":160,"min_vertices":4,"max_vertices":8,"closure_steps":4,"occupied_error_px":12.0,"area_error":1.0,"roads":"structural"},
		"mid4":{"max_group":48,"grid":64,"max_span":80,"max_vertices":8,"occupied_error_px":4.0,"area_error":0.80,"roads":"structural"},
		"mid6":{"max_group":48,"grid":64,"max_span":80,"max_vertices":8,"occupied_error_px":6.0,"area_error":0.80,"roads":"structural"},
		"far4":{"max_group":64,"grid":96,"max_span":120,"max_vertices":8,"occupied_error_px":4.0,"area_error":1.0,"roads":"structural"},
		"far6":{"max_group":64,"grid":96,"max_span":120,"max_vertices":8,"occupied_error_px":6.0,"area_error":1.0,"roads":"structural"},
		"blocks":{"max_group":32,"grid":64,"max_span":80,"max_vertices":8,"occupied_error_px":3.0,"area_error":0.60,"roads":"structural"},
		"district6":{"max_group":48,"grid":64,"max_span":80,"max_vertices":8,"occupied_error_px":6.0,"area_error":0.80,"roads":"structural"},
		"district8":{"max_group":48,"grid":64,"max_span":80,"max_vertices":8,"occupied_error_px":8.0,"area_error":0.80,"roads":"structural"},
		"district12":{"max_group":48,"grid":64,"max_span":80,"max_vertices":8,"occupied_error_px":12.0,"area_error":0.80,"roads":"structural"},
		"district16":{"max_group":48,"grid":64,"max_span":80,"max_vertices":8,"occupied_error_px":16.0,"area_error":0.80,"roads":"structural"},
		"district20":{"max_group":48,"grid":64,"max_span":80,"min_vertices":4,"max_vertices":8,"occupied_error_px":20.0,"area_error":0.80,"roads":"structural"},
		"district24":{"max_group":48,"grid":64,"max_span":80,"min_vertices":4,"max_vertices":8,"occupied_error_px":24.0,"area_error":0.80,"roads":"structural"},
		"district20wide":{"max_group":64,"grid":96,"max_span":120,"min_vertices":4,"max_vertices":8,"closure_steps":4,"occupied_error_px":20.0,"area_error":0.80,"roads":"structural"},
		"district24wide":{"max_group":64,"grid":96,"max_span":120,"min_vertices":4,"max_vertices":8,"closure_steps":4,"occupied_error_px":24.0,"area_error":0.80,"roads":"structural"},
		"district24street":{"max_group":64,"grid":96,"max_span":120,"min_vertices":4,"max_vertices":8,"closure_steps":4,"occupied_error_px":24.0,"area_error":0.80,"roads":"structural","grouping":"road_components","link_gap":12.0}}
	profiles["district24street45"]=profiles.district24street.duplicate(true)
	profiles["street_solid"]={"max_group":256,"grid":128,"max_span":240,"min_vertices":4,"max_vertices":8,"closure_steps":4,"occupied_error_px":80.0,"area_error":2.0,"roads":"structural","grouping":"road_components","link_gap":12.0}
	if plan.get("profile")=="street_solid" and plan.get("max_scale")!=5.0: return 0
	profiles.district24street45["shape_policy"]={"min_angle_degrees":45,"max_aspect":4,"min_edge_px":0.5}
	if plan.get("profile") in ["district6","district8","district12","district16","district20","district24","district20wide","district24wide","district24street","district24street45"] and plan.get("max_scale")!=5.0:
		return 0
	if plan.get("profile") in ["mid4","mid6"] and plan.get("max_scale")!=1.5552:
		return 0
	if plan.get("max_scale")==1.5552 and plan.get("profile") not in ["mid4","mid6"]:
		return 0
	if plan.get("profile") in ["far4","far6","far8wide","far12wide","street6","street8"] and plan.get("max_scale") not in [0.1944,0.3888]:
		return 0
	if not profiles.has(plan.get("profile")):
		return 0
	var expected: Dictionary = profiles[plan.profile]
	for key: String in expected:
		if key=="shape_policy":
			# JSON数值是float，不能以Dictionary的严格类型比较拒绝等值合同。
			var policy: Variant = plan.get(key)
			if not policy is Dictionary or policy.size()!=expected[key].size():
				return 0
			for field: String in expected[key]:
				if typeof(policy.get(field)) not in [TYPE_INT,TYPE_FLOAT] or policy[field]!=expected[key][field]:
					return 0
			continue
		if plan.get(key)!=expected[key]:
			return 0
	return int(expected.max_group)


static func record_for(raw: Dictionary, level: int, detail: int) -> Dictionary:
	var record := raw.duplicate()
	if detail == 2:
		if raw.get("area_lod", {}).has(str(level)):
			record.rings = raw.area_lod[str(level)].rings
		elif raw.get("footprint_lod", {}).has(str(level)):
			record.rings = raw.footprint_lod[str(level)].rings
	return record


static func eligible(raw: Dictionary) -> bool:
	var tags: Dictionary = raw.get("source_tags", {})
	if tags.get("building", "") == "roof" or tags.get("building:part", "") == "roof":
		return false
	if raw.get("height_source", "") != "fallback" or float(raw.get("height_m", 0)) <= 0 or float(raw.height_m) > 24 \
			or float(raw.get("min_height_m", 0)) != 0 or raw.get("defer_render", false) or not raw.get("render_outline", true) \
			or raw.get("is_part", false) or not raw.get("parents", []).is_empty() or not raw.get("parts", []).is_empty() \
			or raw.get("roof_shape", "flat") != "flat" or raw.has("roof_volume") or raw.get("rings", []).size() != 1:
		return false
	var ring: Dictionary = raw.rings[0]
	return ring.get("holes", []).is_empty() and ring.get("inset_triangles", []).is_empty() and ring.get("panel_triangles", []).is_empty()
