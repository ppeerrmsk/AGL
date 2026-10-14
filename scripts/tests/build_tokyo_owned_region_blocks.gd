extends RefCounted
## 将已验街坊造型移入多片唯一归属；任何合并组涉及非owner即拒绝，不猜测拆分造型。
const Native := preload("res://scripts/tests/build_tokyo_regional_native.gd")
const Same := preload("res://scripts/tests/audit_tokyo_region_sample.gd")
const Far := preload("res://scripts/tests/build_tokyo_far_clusters.gd")
const Gameplay := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")
const REGION := "west_residential"


static func valid_config(config: Variant, regions: Array, digest: String) -> bool:
	if not config is Dictionary or config.size()!=9 or config.get("schema")!=1 or config.get("registry_sha256")!=digest \
			or digest.length()!=64 or not config.get("region") is String or not regions.has(config.region):
		return false
	for key: String in ["source","joined","candidate","full","plans","audit"]:
		if not config.get(key) is String or not config[key].is_absolute_path():
			return false
	return true


static func disjoint_groups(groups: Variant, nonowners: PackedStringArray, records: Dictionary) -> bool:
	if not groups is Array:
		return false
	var seen: Dictionary = {}
	for group: Variant in groups:
		if not group is Dictionary or not group.get("ids") is Array or group.ids.size() < 2:
			return false
		for identity: Variant in group.ids:
			if not identity is String or not records.has(identity) or identity in nonowners or seen.has(identity):
				return false
			seen[identity] = true
	return true


static func transfer(full: Resource, owned: Resource, candidate: Resource, allow_cell_redistribution: bool = false) -> Resource:
	if full == null or owned == null or candidate == null or not full.valid() or not owned.valid() or not candidate.valid() \
			or full.source_ids != owned.source_ids or full.source_ids != candidate.source_ids \
			or full.height_hash != owned.height_hash or full.height_hash != candidate.height_hash \
			or full.level != owned.level or full.level != candidate.level or full.cell_id != owned.cell_id or full.cell_id != candidate.cell_id \
			or not Same.same_mesh(full.meshes[1],candidate.meshes[1]):
		return null
	var result: Resource = owned.duplicate(false)
	var meshes: Array[ArrayMesh] = []
	for kind in 2:
		var delta := Native.subtract(full.meshes[kind],owned.meshes[kind])
		if delta.is_empty() or not Native.conserved(full.meshes[kind],owned.meshes[kind],delta.mesh):
			return null
		var changed := Native.subtract(candidate.meshes[kind],delta.mesh)
		if changed.is_empty() or not Native.conserved(candidate.meshes[kind],changed.mesh,delta.mesh):
			return null
		meshes.append(changed.mesh)
	result.meshes = meshes
	# 保留已经去除非owner的原形兜底；切换/突放大不能重新出现重复楼。
	result.geometry_bytes = 0
	result.triangles = 0
	Far.Builder.finish(result)
	if not result.valid() or (not allow_cell_redistribution and (result.triangles > owned.triangles or result.geometry_bytes > owned.geometry_bytes)) \
			or owned.triangles-result.triangles != full.triangles-candidate.triangles:
		return null
	return result


func run() -> int:
	var root := OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_SOURCE")
	var output := OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_OUT")
	if not Far.Builder.valid_sample_output(root,output):
		return 1
	var base := root.get_base_dir()
	var registry_path := root.path_join("ownership.json")
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(registry_path))
	var digest := FileAccess.get_sha256(registry_path)
	var config: Variant = {"schema":1,"registry_sha256":digest,"region":REGION,
		"source":base.path_join("r119-west-source-b"),"joined":base.path_join("r123-owned-native-a"),
		"candidate":base.path_join("r124-west-native-a"),"full":base.path_join("r120-west-native-a"),
		"plans":base.path_join("r121-west-plans-regular"),"audit":base.path_join("r123-owned-native-a/saved_audit.json")}
	var config_path := OS.get_environment("AGL_TOKYO_REGIONAL_BLOCK_CONFIG")
	if not config_path.is_empty():
		config=JSON.parse_string(FileAccess.get_file_as_string(config_path))
	elif registry.get("regions",[]) != ["north_coast","west_residential","yokohama"]:
		return 1
	if not valid_config(config,registry.get("regions",[]),digest):
		return 1
	var region: String = config.region
	var original_dir: String = config.source
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(original_dir.path_join("city.json")))
	var prepared: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(region).path_join("city.json")))
	for filename: String in ["city.json","ground.json"]:
		if FileAccess.get_sha256(original_dir.path_join(filename)) != registry.inputs[region][filename]:
			return 1
	if FileAccess.get_sha256(root.path_join(region).path_join("ground.json")) != registry.inputs[region]["ground.json"]:
		return 1
	var gate := Native.Gate.validate(prepared,original,registry,region,digest)
	var joined_dir: String = config.joined
	var candidate_dir: String = config.candidate
	var full_dir: String = config.full
	var manifest_path := joined_dir.path_join("manifest.json")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var prior_audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.audit))
	var candidate_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(candidate_dir.path_join("manifest.json")))
	var full_index: Resource = load(full_dir.path_join("index.res"))
	var matches: Array = report.regions.filter(func(row: Dictionary) -> bool: return row.region==region)
	if matches.size()!=1 or config.audit!=joined_dir.path_join("saved_audit.json"):
		return 1
	var owned_index: Resource = load(matches[0].index)
	var candidate_index: Resource = load(candidate_dir.path_join("index.res"))
	if gate.is_empty() or report.get("registry_sha256") != digest or prior_audit.get("registry_sha256") != digest or prior_audit.get("fail",1) != 0 \
			or full_index == null or owned_index == null or candidate_index == null or not full_index.valid() or not candidate_index.valid() \
			or owned_index.valid() or not owned_index.valid(digest) or owned_index.regional_id != region or owned_index.regional_nonowner_ids != gate.nonowner_ids \
			or full_index.source_hash != registry.inputs[region]["city.json"]+":"+registry.inputs[region]["ground.json"] \
			or candidate_index.source_hash != full_index.source_hash \
			or owned_index.source_hash != FileAccess.get_sha256(root.path_join(region).path_join("city.json"))+":"+registry.inputs[region]["ground.json"]:
		return 1
	var source := Gameplay.read_source()
	if source.is_empty() or candidate_report.get("source_sha256") != registry.inputs[region]["city.json"] \
			or candidate_report.get("collision_sha256") != source.collision_sha256 or candidate_report.get("game_source_sha256") != source.source_sha256:
		return 1
	var box: Array = candidate_report.gameplay_protection.bounds
	var protection := Gameplay.inspect_bounds(Rect2(box[0],box[1],box[2],box[3]),source.entries)
	if protection.is_empty() or not protection.standalone_merge_allowed:
		return 1
	var converter := Far.new()
	for raw: Dictionary in original.buildings:
		converter._records[raw.id] = raw
	var plans: Dictionary = {}
	var plan_hashes: Dictionary = {}
	for level in range(1,6):
		var path := String(config.plans).path_join("%d.json" % level)
		var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not disjoint_groups(plan.get("groups"),gate.nonowner_ids,converter._records) or plan.source_sha256 != registry.inputs[region]["city.json"] \
				or plan.ground_sha256 != registry.inputs[region]["ground.json"] or plan.native_costs_sha256 != FileAccess.get_sha256(full_dir.path_join("native_costs.json")) \
				or plan.get("source_ownership") != "independent_complete_source" or Far.group_limit(plan) == 0 or not is_equal_approx(plan.max_scale,Far.maximum_scale(level)):
			return 1
		plans[level] = plan
		plan_hashes[str(level)] = FileAccess.get_sha256(path)
	var matched: Array = report.regions.filter(func(row: Dictionary) -> bool: return row.region==region)
	if matched.size() != 1:
		return 1
	var regional: Dictionary = matched[0]
	var target: Resource = owned_index.duplicate(true)
	var directory := output.path_join(region)
	DirAccess.make_dir_recursive_absolute(directory)
	var savings := PackedInt64Array([0,0,0,0,0])
	var group_counts := PackedInt32Array([0,0,0,0,0])
	for entry: Dictionary in target.cells:
		for level in range(1,6):
			var full_path: String = full_index.cells[entry.id].levels[level].path
			var owned_path: String = owned_index.cells[entry.id].levels[level].path
			var candidate_path: String = candidate_index.cells[entry.id].levels[level].path
			var full: Resource = ResourceLoader.load(full_path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var owned: Resource = ResourceLoader.load(owned_path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var candidate: Resource = ResourceLoader.load(candidate_path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var expected := converter._convert(full,plans[level],false)
			if expected.is_empty() or not Same.same_mesh(candidate.meshes[0],expected.mesh):
				return 1
			var result := transfer(full,owned,candidate)
			if result == null:
				return 1
			var destination := directory.path_join("cell_%02d_slot_%d.res" % [entry.id,level])
			if ResourceSaver.save(result,destination,ResourceSaver.FLAG_COMPRESS) != OK:
				return 1
			var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
			if saved == null or not saved.valid() or saved.height_hash != owned.height_hash or saved.source_ids != owned.source_ids or saved.detail_counts != owned.detail_counts:
				return 1
			for kind in 2:
				if not Same.same_mesh(saved.meshes[kind],result.meshes[kind]):
					return 1
			entry.levels[level].path = destination
			entry.levels[level].bytes = saved.geometry_bytes
			entry.levels[level].triangles = saved.triangles
			var rows: Array = regional.rows.filter(func(row: Dictionary) -> bool: return row.cell==entry.id and row.slot==level)
			if rows.size()!=1 or rows[0].path!=owned_path or rows[0].source!=full_path or rows[0].sha256!=FileAccess.get_sha256(owned_path):
				return 1
			rows[0].path=destination
			rows[0].sha256=FileAccess.get_sha256(destination)
			rows[0].removed_faces=full.triangles-saved.triangles
			rows[0].block_faces_saved=owned.triangles-saved.triangles
			savings[level-1]+=owned.triangles-saved.triangles
			group_counts[level-1]+=expected.groups.size()
	for level in range(1,6):
		if savings[level-1]!=int(plans[level].faces_saved) or group_counts[level-1]!=plans[level].groups.size():
			return 1
	var destination := directory.path_join("index.res")
	if target.valid() or not target.valid(digest) or ResourceSaver.save(target,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	regional.index=destination
	report.block_transfer={"region":region,"source_manifest_sha256":FileAccess.get_sha256(manifest_path),
		"source_audit_sha256":FileAccess.get_sha256(config.audit),"candidate_manifest_sha256":FileAccess.get_sha256(candidate_dir.path_join("manifest.json")),
		"plan_hashes":plan_hashes,"savings":Array(savings),"group_counts":Array(group_counts),"gameplay_protection":protection,"nonowner_group_intersections":0}
	var transfers: Dictionary = report.get("block_transfers",{})
	if transfers.has(region):
		return 1
	transfers[region]=report.block_transfer
	report.block_transfers=transfers
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	print("[Tokyo owned region blocks] packages=80 groups=",group_counts," savings=",savings," nonowner_groups=0 fail=0")
	return 0
