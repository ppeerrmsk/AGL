extends RefCounted
## 备用也沿用已验近景街坊；只对低层做精确差集，绝不由远档轮廓伪装近景。
const Blocks := preload("res://scripts/tests/build_tokyo_block_catalog.gd")
const Far := preload("res://scripts/tests/build_tokyo_far_clusters.gd")
const Diff := preload("res://scripts/experiments/tokyo_packed_mesh_difference.gd")
const Repack := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const SOURCE_SHA := "6c9df3270367dbfd67b1b16cb4286b410a831639d6f44420dd55cb44a13a414e"
const PLAN_SHA := "45d17846dd82da0fe958f9a29889903242af735478ce1091e49ec48085870b63"
const MANIFEST_SHA := "bdecc4138cc658e60dae295543af95ed080a7446ad0114003a2831fa6ddb9c3c"


func run() -> int:
	var base := OS.get_environment("AGL_TOKYO_GUARDED_BLOCK_ROOT")
	var output := OS.get_environment("AGL_TOKYO_GUARDED_BLOCK_OUT")
	if not Far.Builder.valid_sample_output(base.path_join("r127-native-a"),output):
		print("[Guarded blocks rejected] output path ",output)
		return 1
	var source_path := base.path_join("r127-native-a/catalog.res")
	var manifest_path := base.path_join("r111-district24wide-a-native/manifest.json")
	var plan_path := base.path_join("r111-district24wide-a-5-b.json")
	var city_path := base.path_join("r30-area-source-b/north_coast/city.json")
	if FileAccess.get_sha256(source_path)!=SOURCE_SHA or FileAccess.get_sha256(manifest_path)!=MANIFEST_SHA \
			or FileAccess.get_sha256(plan_path)!=PLAN_SHA or FileAccess.get_sha256(city_path)!=Far.CITY_HASH:
		print("[Guarded blocks rejected] input digest")
		return 1
	var original: Resource = load(source_path)
	var data := Blocks.Manifest.read(base.path_join("r127-native-a/components/manifest.bin"),original,SOURCE_SHA)
	if original==null or not original.valid() or data.is_empty():
		print("[Guarded blocks rejected] source catalog/components")
		return 1
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	if manifest.get("fail",1)!=0 or not Blocks.valid_plan_rows(manifest.rows,[5],"district24wide") \
			or plan.max_scale!=5.0 or plan.source_sha256!=Far.CITY_HASH or Far.group_limit(plan)!=64:
		print("[Guarded blocks rejected] near plan metadata")
		return 1
	var records: Dictionary = {}
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(city_path))
	for raw: Dictionary in city.buildings:
		records[str(raw.id)]=raw
	var lookup: Dictionary = {}
	for group: Dictionary in plan.groups:
		lookup[str(group.ids[0])]=group
	var writer := Blocks.new()
	writer._catalog=original.duplicate(true)
	var input := FileAccess.open(base.path_join("r127-native-a/components/manifest.bin"),FileAccess.READ)
	writer._components=input.get_var(false)
	input.close()
	writer._out=output
	DirAccess.make_dir_recursive_absolute(output.path_join("components"))
	var rows: Array = []
	for row: Dictionary in manifest.rows:
		var parent := int(row.cell_id)
		var groups: Array = []
		for accepted: Dictionary in row.groups:
			var group: Dictionary = lookup.get(str(accepted.ids[0]),{})
			# JSON报告有十进制尾数截断；比较真实float32网格点，不给轮廓额外误差预算。
			if group.is_empty() or group.ids!=accepted.ids or Far.Factory._points(group.outer)!=Far.Factory._points(accepted.candidate) or group.height_m*0.5!=accepted.height_px:
				print("[Guarded blocks rejected] accepted group mismatch ",accepted.ids[0]," empty=",group.is_empty())
				return 1
			groups.append(group)
		for level in 4:
			var configuration := "lod%d_guarded" % level
			var entry: Dictionary = original.configurations[configuration][parent]
			var source := writer._load(entry)
			var replacement := group_meshes(records,groups,level)
			if source==null or replacement.is_empty():
				print("[Guarded blocks rejected] group contract ",configuration," parent=",parent)
				return 1
			var remaining := Diff.subtract(source.meshes[0],replacement.removed)
			if remaining.is_empty() or not Diff.conserved(source.meshes[0],remaining.mesh,replacement.removed):
				print("[Guarded blocks rejected] exact source subtraction ",configuration," parent=",parent)
				return 1
			var low := Repack.repack(Blocks.Join.join([remaining.mesh,replacement.added]))
			if not Blocks.Join.conserved(low,[remaining.mesh,replacement.added]) or Far.Indexed.triangles(low)>=int(entry.triangles[0]) \
					or Far.Builder.mesh_bytes(low)>Far.Builder.mesh_bytes(source.meshes[0]):
				return 1
			var context := {"out":output.path_join(configuration),"configuration":configuration,"level":level,"parent_id":parent,
				"collision_sha256":original.collision_sha256,"owners_sha256":original.owners_sha256,"game_sources":source.game_sources,
				"source_hash":(source.source_hash+PLAN_SHA+"r129-near-safe-guarded").sha256_text(),"audit":false}
			DirAccess.make_dir_recursive_absolute(context.out)
			var changed := writer._replace(entry,low,context)
			if changed.is_empty():
				return 1
			writer._catalog.configurations[configuration][parent]=changed
			rows.append({"configuration":configuration,"parent":parent,"groups":replacement.groups,"before":Array(entry.triangles),
				"after":Array(changed.triangles),"before_bytes":source.geometry_bytes,"after_bytes":changed.bytes})
			print("[Guarded blocks] ",configuration," parent=",parent," groups=",replacement.groups," low=",entry.triangles[0]," -> ",changed.triangles[0])
	return _save(writer,original,base,rows)


static func group_meshes(records: Dictionary, groups: Array, level: int) -> Dictionary:
	if level not in [0,1,2,3]:
		return {}
	var removed := Far.Geometry.new()
	var added := Far.Geometry.new()
	var used: Dictionary = {}
	var count := 0
	for group: Dictionary in groups:
		if group.get("ids",[]).size()<2 or group.ids.size()>64 or group.get("outer",[]).size()<4 or group.outer.size()>8 \
				or group.get("triangles",[]).is_empty() or group.triangles.size()%3!=0:
			return {}
		var detail := 2
		var before := 0
		for id: String in group.ids:
			if used.has(id) or not records.has(id):
				return {}
			used[id]=true
			var raw: Dictionary = records[id]
			if not Far.eligible(raw) or raw.height_m!=group.get("height_m") or raw.get("kind","urban")!=group.get("kind","urban"):
				return {}
			var member_detail := Far.Builder.detail_level(raw,Far.Levels.SCALES[level],true)
			detail=mini(detail,member_detail)
			before+=Far.Cluster.face_count(raw.rings[0],member_detail)
		var ring := {"outer":group.outer,"holes":[],"triangles":group.triangles}
		if before<=Far.Cluster.face_count(ring,detail):
			continue
		for id: String in group.ids:
			var raw: Dictionary = records[id]
			Far.Factory._add_ring_building(removed,raw,float(raw.height_m)*0.5,Far.Builder.detail_level(raw,Far.Levels.SCALES[level],true))
		var block: Dictionary = records[str(group.ids[0])].duplicate()
		block.rings=[ring]
		Far.Factory._add_ring_building(added,block,float(block.height_m)*0.5,detail)
		count+=1
	return {"removed":Far.Palette.recolor(Far.Indexed.pack(removed.mesh())),"added":Far.Palette.recolor(Far.Indexed.pack(added.mesh())),"groups":count}


static func audit(directory: String) -> int:
	var path := directory.path_join("catalog.res")
	var catalog: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var digest := FileAccess.get_sha256(path)
	var data := Blocks.Manifest.read(directory.path_join("components/manifest.bin"),catalog,digest)
	var source_path := directory.get_base_dir().path_join("r127-native-a/catalog.res")
	if FileAccess.get_sha256(source_path)!=SOURCE_SHA or catalog==null or not catalog.valid() or data.is_empty():
		return 1
	var before: Resource = load(source_path)
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("report.json")))
	if report.get("fail",1)!=0 or report.catalog_sha256!=digest or report.source_catalog_sha256!=SOURCE_SHA or report.plan_sha256!=PLAN_SHA \
			or report.changes.size()!=672 or catalog.regional_extension!=before.regional_extension or catalog.collision_sha256!=before.collision_sha256:
		return 1
	var reverse: Dictionary = {}
	for old: String in report.changes:
		reverse[str(report.changes[old].path)]=old
	var physical: Dictionary = {}
	for logical: String in catalog.descriptors:
		var row: Dictionary = data.pages[logical]
		var page: Resource = ResourceLoader.load(logical,"",ResourceLoader.CACHE_MODE_IGNORE)
		if page==null or not page.valid() or page.stream_identity()!=row.canonical_identity or page.geometry_bytes!=row.bytes or page.triangles!=row.triangles or page.game_sources!=row.game_sources:
			return 1
		for kind in 3:
			var component_path: String = row.mapping[kind][0]
			var component: Resource = ResourceLoader.load(component_path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if component==null or not component.valid() or component.stream_identity()!=row.components[component_path].canonical_identity \
					or not Blocks.Join.conserved(page.meshes[kind],[component.meshes[row.mapping[kind][1]]]):
				return 1
			physical[component_path]=true
		if reverse.has(logical):
			var old: Resource = ResourceLoader.load(reverse[logical],"",ResourceLoader.CACHE_MODE_IGNORE)
			if old==null or not old.valid() or old.game_sources!=page.game_sources:
				return 1
			for kind in [1,2]:
				if not Blocks.Shared.same_mesh(old.meshes[kind],page.meshes[kind]):
					return 1
		elif not before.descriptors.has(logical) or before.descriptors[logical]!=catalog.descriptors[logical]:
			return 1
	for configuration: String in Blocks.Catalog.CONFIGURATIONS:
		for parent in 16:
			if not (configuration.ends_with("guarded") and parent>=8) and catalog.configurations[configuration][parent]!=before.configurations[configuration][parent]:
				return 1
		var file := FileAccess.open(directory.path_join("coverage-"+configuration+".bin"),FileAccess.READ)
		var coverage: Dictionary = file.get_var(false)
		file.close()
		if coverage.catalog_sha256!=digest or not coverage.verified or coverage.sources.size()!=48 or coverage.pages.size()!=208 \
				or coverage.collision_sha256!=before.collision_sha256 or coverage.owners_sha256!=before.owners_sha256:
			return 1
		for page_path: String in coverage.pages:
			if coverage.pages[page_path].identity!=catalog.descriptors[page_path].canonical_identity or coverage.pages[page_path].sha256!=FileAccess.get_sha256(page_path):
				return 1
	var output := directory.path_join("saved_audit.json")
	if FileAccess.file_exists(output):
		return 1
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"catalog_sha256":digest,"pages":catalog.descriptors.size(),"physical":physical.size(),
		"changed_pages":reverse.size(),"high_fixed_unchanged":true,"all_full_mid_unchanged":true,"game_sources":48,"visual_acceptance":false}))
	file.close()
	print("[Guarded saved audit] pages=",catalog.descriptors.size()," physical=",physical.size()," fail=0")
	return 0


func _save(writer: RefCounted, original: Resource, base: String, rows: Array) -> int:
	var output: String = writer._out
	var catalog: Resource = writer._catalog
	for configuration: String in Blocks.Catalog.CONFIGURATIONS:
		for parent in 16:
			if not (configuration.ends_with("guarded") and parent>=8) and catalog.configurations[configuration][parent]!=original.configurations[configuration][parent]:
				return 1
	var destination := output.path_join("catalog.res")
	if not catalog.valid() or ResourceSaver.save(catalog,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or not saved.valid() or saved.configurations!=catalog.configurations or saved.descriptors!=catalog.descriptors or saved.regional_extension!=original.regional_extension:
		return 1
	var digest := FileAccess.get_sha256(destination)
	for configuration: String in Blocks.Catalog.CONFIGURATIONS:
		var input := FileAccess.open(base.path_join("r127-native-a/coverage-"+configuration+".bin"),FileAccess.READ)
		var previous: Dictionary = input.get_var(false)
		input.close()
		if previous.catalog_sha256!=SOURCE_SHA or not previous.verified or previous.sources.size()!=48 or previous.pages.size()!=208:
			return 1
		var coverage := Blocks.rewrite_coverage(previous,writer._changes,digest)
		if coverage.is_empty():
			return 1
		var file := FileAccess.open(output.path_join("coverage-"+configuration+".bin"),FileAccess.WRITE)
		file.store_var(coverage)
		file.close()
	var data: Dictionary = writer._components
	data.catalog_sha256=digest
	var physical: Dictionary = {}
	for row: Dictionary in data.pages.values():
		for path: String in row.components:
			physical[path]=data.physical[path]
	data.physical=physical
	var component_path := output.path_join("components/manifest.bin")
	var file := FileAccess.open(component_path,FileAccess.WRITE)
	file.store_var(data)
	file.close()
	if Blocks.Manifest.read(component_path,catalog,digest).is_empty():
		return 1
	file=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"rows":rows,"changes":writer._changes,"source_catalog_sha256":SOURCE_SHA,"plan_sha256":PLAN_SHA,
		"catalog_sha256":digest,"changed_pages":writer._changes.size(),"logical":catalog.descriptors.size(),"physical":physical.size(),"production_enabled":false}))
	file.close()
	print("[Guarded blocks] complete changed=",writer._changes.size()," fail=0")
	return 0
