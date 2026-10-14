extends RefCounted
## 街坊候选接既有规范目录；只有低层逐面同源、游戏楼凭据不受影响才替换。
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Spatial := preload("res://scripts/tests/build_tokyo_canonical_spatial.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Shared := preload("res://scripts/tests/build_tokyo_shared_pages.gd")
const Components := preload("res://scripts/tests/build_tokyo_mesh_components.gd")
const Cross := preload("res://scripts/tests/build_tokyo_cross_lod_components.gd")
const Manifest := preload("res://scripts/rendering/tokyo_component_manifest.gd")
var _catalog: Resource
var _components: Dictionary
var _changes: Dictionary = {}
var _out := ""


func run(root: String, output: String) -> int:
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		return 1
	_out = output
	_changes.clear()
	var inputs := input_paths(root,OS.get_environment("AGL_TOKYO_BLOCK_LOD3")=="1",OS.get_environment("AGL_TOKYO_BLOCK_LOD5")=="1",OS.get_environment("AGL_TOKYO_BLOCK_DISTRICT8")=="1",OS.get_environment("AGL_TOKYO_BLOCK_FAR6")=="1",OS.get_environment("AGL_TOKYO_BLOCK_DISTRICT16")=="1",OS.get_environment("AGL_TOKYO_BLOCK_MID6")=="1",OS.get_environment("AGL_TOKYO_BLOCK_DISTRICT24WIDE")=="1")
	if inputs.is_empty():
		return 1
	var catalog_path: String = inputs.catalog
	var old_sha := FileAccess.get_sha256(catalog_path)
	var original: Resource = load(catalog_path)
	var manifest_path: String = inputs.components
	if original == null or not original.valid() or Manifest.read(manifest_path,original,old_sha).is_empty():
		return 1
	_catalog = original.duplicate(true)
	var file := FileAccess.open(manifest_path,FileAccess.READ)
	_components = file.get_var(false)
	file.close()
	var plan_path: String = inputs.plan
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	var profile: String = inputs.get("profile","blocks")
	if plan.get("fail",-1)!=0 or not valid_plan_rows(plan.get("rows",[]),inputs.levels,profile):
		return 1
	var baseline: Dictionary = {}
	if profile in ["far6","district16","district24wide"]:
		var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(inputs.baseline))
		if not previous is Dictionary or previous.get("fail",-1)!=0:
			return 1
		baseline=matched_baseline_rows(plan.rows,previous.get("rows",[]),profile)
		if baseline.is_empty():
			return 1
	DirAccess.make_dir_recursive_absolute(output.path_join("components"))
	var saved_faces := 0
	for item: Dictionary in plan.rows:
		if item.get("block_profile")!=profile or FileAccess.get_sha256(item.path)!=item.sha256 or FileAccess.get_sha256(item.source)!=item.source_sha256:
			return 1
		if profile in ["district8","far6","district16","mid6","district24wide"]:
			if FileAccess.get_sha256(str(item.get("plan","")))!=str(item.get("plan_sha256","")):
				return 1
			var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(item.plan))
			if not contract is Dictionary or contract.get("profile")!=profile or contract.get("max_scale")!=item.max_scale or preload("res://scripts/tests/build_tokyo_far_clusters.gd").group_limit(contract)!=(64 if profile in ["far6","district24wide"] else 48):
				return 1
		var name_value := "lod%d_full" % int(item.level)
		var parent := int(item.cell_id)
		var entry: Dictionary = original.configurations[name_value][parent]
		var old_page := _load(entry)
		var source: Resource = ResourceLoader.load(item.source,"",ResourceLoader.CACHE_MODE_IGNORE)
		var candidate: Resource = ResourceLoader.load(item.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if old_page==null or source==null or candidate==null or not source.valid() or not candidate.valid():
			return 1
		if source.level!=int(item.level) or candidate.level!=source.level or source.cell_id!=parent or candidate.cell_id!=parent \
				or candidate.source_ids!=source.source_ids or candidate.height_hash!=source.height_hash \
				or not Shared.same_mesh(candidate.meshes[1],source.meshes[1]) \
				or not is_equal_approx(float(item.max_scale),preload("res://scripts/tests/build_tokyo_far_clusters.gd").maximum_scale(int(item.level))):
			return 1
		var current: Resource = source
		if profile=="mid6":
			# 规范LOD4继承R44轻概括，不是R34原形；先证明R44原形与新候选原形同源。
			var old_catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r44_lod_pages/full/index.res")
			if old_catalog==null or not old_catalog.valid():
				return 1
			var old_entry: Dictionary = old_catalog.parents[parent]
			current=ResourceLoader.load(old_entry.building,"",ResourceLoader.CACHE_MODE_IGNORE)
			var raw_old: Resource = ResourceLoader.load(old_entry.get("cluster_original",old_entry.building),"",ResourceLoader.CACHE_MODE_IGNORE)
			if current==null or raw_old==null or not current.valid() or not raw_old.valid() or not middle_source_chain(raw_old,current,source):
				return 1
		if profile in ["far6","district16","district24wide"]:
			var old: Dictionary = baseline["%d:%d"%[int(item.level),parent]]
			if FileAccess.get_sha256(old.path)!=old.sha256:
				return 1
			current=ResourceLoader.load(old.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if current==null or not current.valid() or current.level!=source.level or current.cell_id!=parent or current.source_ids!=source.source_ids or current.height_hash!=source.height_hash or not Shared.same_mesh(current.meshes[1],source.meshes[1]):
				return 1
		if not Join.conserved(old_page.meshes[0],[current.meshes[0]]):
			push_error("R79 canonical low differs from candidate source: "+entry.path)
			return 1
		var context := {"out":output.path_join(name_value),"configuration":name_value,"level":int(item.level),"parent_id":parent,
			"collision_sha256":_catalog.collision_sha256,"owners_sha256":_catalog.owners_sha256,"game_sources":old_page.game_sources,
			"source_hash":(old_page.source_hash+str(item.sha256)+"r79-blocks").sha256_text(),"audit":false}
		DirAccess.make_dir_recursive_absolute(context.out)
		var changed := _replace(entry,candidate.meshes[0],context)
		if changed.is_empty():
			return 1
		_catalog.configurations[name_value][parent] = changed
		saved_faces += int(entry.triangles[0])-int(changed.triangles[0])
		print("[R79 build] configuration=",name_value," parent=",parent," low_before=",entry.triangles[0]," low_after=",changed.triangles[0])
	# 继承已验远档；只有计划声明的配置可以改变，guarded和其他区域仍逐条同值。
	for configuration: String in Catalog.CONFIGURATIONS:
		for parent in original.configurations[configuration].size():
			var allowed := false
			for level: int in inputs.levels:
				allowed = allowed or (configuration=="lod%d_full" % level and parent>=8 and parent<=15)
			if not allowed and _catalog.configurations[configuration][parent]!=original.configurations[configuration][parent]:
				return 1
	var destination := output.path_join("catalog.res")
	if not _catalog.valid() or ResourceSaver.save(_catalog,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or not saved.valid() or saved.configurations!=_catalog.configurations or saved.descriptors!=_catalog.descriptors:
		return 1
	var new_sha := FileAccess.get_sha256(destination)
	for configuration: String in Catalog.CONFIGURATIONS:
		file = FileAccess.open(str(inputs.coverage_prefix)+configuration+".bin",FileAccess.READ)
		var previous: Dictionary = file.get_var(false)
		file.close()
		if previous.catalog_sha256!=old_sha or not previous.verified or previous.pages.size()!=208 or previous.sources.size()!=48:
			return 1
		for path: String in previous.pages:
			if previous.pages[path].identity!=original.descriptors[path].canonical_identity:
				return 1
		var rewritten := rewrite_coverage(previous,_changes,new_sha)
		if rewritten.is_empty():
			return 1
		file = FileAccess.open(output.path_join("coverage-"+configuration+".bin"),FileAccess.WRITE)
		file.store_var(rewritten)
		file.close()
	_components.catalog_sha256 = new_sha
	var used: Dictionary = {}
	for row: Dictionary in _components.pages.values():
		for path: String in row.components:
			used[path] = _components.physical[path]
	_components.physical = used
	var component_path := output.path_join("components/manifest.bin")
	file = FileAccess.open(component_path,FileAccess.WRITE)
	file.store_var(_components)
	file.close()
	if Manifest.read(component_path,_catalog,new_sha).is_empty():
		return 1
	if preload("res://scripts/tests/export_tokyo_ao.gd").run(destination,output.path_join("ao-source.json"),str(inputs.get("ao_region","")))!=0:
		return 1
	file = FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"changed_pages":_changes.size(),"logical":_catalog.descriptors.size(),"physical":used.size(),
		"saved_root_faces":saved_faces,"catalog_sha256":new_sha,"source_catalog_sha256":old_sha,"block_manifest_sha256":FileAccess.get_sha256(plan_path),
		"unchanged_guarded":true,"production_enabled":false,"inputs":inputs},"\t"))
	file.close()
	print("[R79 build] COMPLETE changed=",_changes.size()," saved_root_faces=",saved_faces," fail=0")
	return 0


static func input_paths(root: String, near_blocks: bool, finest_blocks: bool = false, district: bool = false, far_blocks: bool = false, strong_district: bool = false, middle_district: bool = false, wide_district: bool = false) -> Dictionary:
	if wide_district:
		if near_blocks or finest_blocks or district or far_blocks or strong_district or middle_district:
			return {}
		return {"catalog":root.path_join("r109-native-b/catalog.res"),"components":root.path_join("r109-native-b/components/manifest.bin"),
			"coverage_prefix":root.path_join("r109-native-b/coverage-"),"plan":root.path_join("r111-district24wide-a-native/manifest.json"),
			"baseline":root.path_join("r106-district16-a-native/manifest.json"),"levels":[5],"profile":"district24wide","ao_region":"north_density"}
	if middle_district:
		if near_blocks or finest_blocks or district or far_blocks or strong_district:
			return {}
		return {"catalog":root.path_join("r107-native-a/catalog.res"),"components":root.path_join("r107-native-a/components/manifest.bin"),
			"coverage_prefix":root.path_join("r107-native-a/coverage-"),"plan":root.path_join("r108-mid6-a-native/manifest.json"),
			"levels":[4],"profile":"mid6","ao_region":"north_density"}
	if strong_district:
		if near_blocks or finest_blocks or district or far_blocks:
			return {}
		return {"catalog":root.path_join("r103-native-a/catalog.res"),"components":root.path_join("r103-native-a/components/manifest.bin"),
			"coverage_prefix":root.path_join("r103-native-a/coverage-"),"plan":root.path_join("r106-district16-a-native/manifest.json"),
			"baseline":root.path_join("r92-district8-a-native/manifest.json"),"levels":[5],"profile":"district16","ao_region":"north_density"}
	if far_blocks:
		if near_blocks or finest_blocks or district:
			return {}
		return {"catalog":root.path_join("r93-native-a/catalog.res"),"components":root.path_join("r93-native-a/components/manifest.bin"),
			"coverage_prefix":root.path_join("r93-native-a/coverage-"),"plan":root.path_join("r102-far6-a-native/manifest.json"),
			"baseline":root.path_join("r78-blocks-native-a/manifest.json"),"levels":[1,2],"profile":"far6","ao_region":"north_density"}
	if district and not finest_blocks:
		return {}
	if finest_blocks:
		if near_blocks:
			return {}
		return {"catalog":root.path_join("r85-native-a/catalog.res"),"components":root.path_join("r85-native-a/components/manifest.bin"),
			"coverage_prefix":root.path_join("r85-native-a/coverage-"),"plan":root.path_join("r92-district8-a-native/manifest.json" if district else "r88-blocks-a-native/manifest.json"),"levels":[5],"ao_region":"north_density","profile":"district8" if district else "blocks"}
	return {"catalog":root.path_join("r79-native-a/catalog.res" if near_blocks else "r54-catalog-a.res"),
		"components":root.path_join("r79-native-a/components/manifest.bin" if near_blocks else "r72-components-a/manifest.bin"),
		"coverage_prefix":root.path_join("r79-native-a/coverage-" if near_blocks else "r62-coverage-b-"),
		"plan":root.path_join("r84-blocks-a-native/manifest.json" if near_blocks else "r78-blocks-native-a/manifest.json"),
		"levels":[3] if near_blocks else [1,2]}


static func valid_plan_rows(rows: Array, levels: Array, profile: String = "blocks") -> bool:
	if profile not in ["blocks","district8","far6","district16","mid6","district24wide"] or (profile in ["district8","district16","district24wide"] and levels!=[5]) or (profile=="far6" and levels!=[1,2]) or (profile=="mid6" and levels!=[4]) or (4 in levels and profile!="mid6"):
		return false
	if rows.size()!=8*levels.size() or levels.is_empty():
		return false
	var seen: Dictionary = {}
	for item: Variant in rows:
		if not item is Dictionary or item.get("block_profile")!=profile:
			return false
		var level: Variant = item.get("level")
		var parent: Variant = item.get("cell_id")
		if not typeof(level) in [TYPE_INT,TYPE_FLOAT] or not typeof(parent) in [TYPE_INT,TYPE_FLOAT]:
			return false
		if not is_finite(float(level)) or not is_finite(float(parent)) or level!=int(level) or parent!=int(parent):
			return false
		if not int(level) in levels or int(parent)<8 or int(parent)>15:
			return false
		var key := "%d:%d" % [int(level),int(parent)]
		if seen.has(key):
			return false
		seen[key] = true
	return true


static func matched_baseline_rows(rows: Array, previous: Array, profile: String = "far6") -> Dictionary:
	# 当前合并版和新合并版必须追溯到相同原始父包，不能把旧合并当作原形。
	if profile not in ["far6","district16","district24wide"]:
		return {}
	var levels := [1,2] if profile=="far6" else [5]
	var old_profile := "district16" if profile=="district24wide" else ("district8" if profile=="district16" else "blocks")
	if not valid_plan_rows(rows,levels,profile) or not valid_plan_rows(previous,levels,old_profile):
		return {}
	var result: Dictionary = {}
	for row: Dictionary in previous:
		result["%d:%d"%[int(row.level),int(row.cell_id)]]=row
	for row: Dictionary in rows:
		var old: Dictionary = result["%d:%d"%[int(row.level),int(row.cell_id)]]
		for key: String in ["source","source_sha256","max_scale"]:
			if not row.has(key) or row[key]!=old.get(key):
				return {}
	return result


static func middle_source_chain(original: Resource, current: Resource, source: Resource) -> bool:
	if original==null or current==null or source==null or source.level!=4 or source.meshes.size()!=2:
		return false
	for page: Resource in [original,current]:
		if page.level!=4 or page.cell_id!=source.cell_id or page.source_ids!=source.source_ids or page.height_hash!=source.height_hash or page.meshes.size()!=2:
			return false
		if not Shared.same_mesh(page.meshes[1],source.meshes[1]):
			return false
	return Join.conserved(original.meshes[0],[source.meshes[0]])


func _load(entry: Dictionary) -> Resource:
	if FileAccess.get_sha256(entry.path)!=entry.sha256:
		return null
	var page: Resource = ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	return page if page!=null and page.valid() and page.stream_identity()==_catalog.descriptors[entry.path].canonical_identity else null


func _replace(entry: Dictionary, low: ArrayMesh, context: Dictionary) -> Dictionary:
	return _replace_layer(entry,low,context,0)


func _replace_layer(entry: Dictionary, mesh: ArrayMesh, context: Dictionary, layer: int) -> Dictionary:
	if layer not in [0,2]:
		return {}
	var source := _load(entry)
	if source==null:
		return {}
	var meshes: Array[ArrayMesh] = [source.meshes[0],source.meshes[1],source.meshes[2]]
	meshes[layer]=mesh
	var result := Spatial._page(meshes,entry.cell_id,entry.ancestor_id,context)
	if result.is_empty():
		return {}
	var saved: Resource = ResourceLoader.load(result.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved.game_sources!=source.game_sources:
		return {}
	for kind in 3:
		if kind!=layer and not Shared.same_mesh(saved.meshes[kind],source.meshes[kind]):
			return {}
	var old_identity: Dictionary = _catalog.descriptors[entry.path].canonical_identity
	_catalog.descriptors.erase(entry.path)
	_catalog.descriptors[result.path] = {"bytes":saved.geometry_bytes,"canonical_identity":saved.stream_identity()}
	result["key"] = entry.key
	_changes[entry.path] = {"path":result.path,"sha256":result.sha256,"identity":saved.stream_identity(),"old_identity":old_identity}
	var row: Dictionary = _components.pages[entry.path].duplicate(true)
	var key := Cross.mesh_key(mesh,layer)
	var path := _out.path_join("components/%d_"%layer+key+".res")
	if not _components.physical.has(path):
		var descriptor := Components._save([mesh],key,path)
		if descriptor.is_empty():
			return {}
		_components.physical[path] = descriptor
	row.mapping[layer] = [path,0]
	row.components = {}
	for mapping: Array in row.mapping:
		row.components[mapping[0]] = _components.physical[mapping[0]]
	row.bytes = saved.geometry_bytes
	row.triangles = saved.triangles
	row.canonical_identity = saved.stream_identity()
	if not Manifest.valid_row(row,_catalog.descriptors[result.path],_components.physical):
		return {}
	_components.pages.erase(entry.path)
	_components.pages[result.path] = row
	if not entry.get("children",[]).is_empty():
		result["cuts"] = entry.cuts
		result["children"] = []
		var pieces := Split.split(mesh,entry.cuts)
		if not Join.conserved(mesh,pieces):
			return {}
		for n in 4:
			var child := _replace_layer(entry.children[n],pieces[n],context,layer)
			if child.is_empty():
				return {}
			result.children.append(child)
	return result


static func remap_tokens(tokens: PackedStringArray, changes: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	for token: String in tokens:
		var split := token.rfind(":")
		if split<1 or token.substr(split+1) not in ["0","1"]:
			return PackedStringArray()
		var path := token.substr(0,split)
		result.append(str(changes[path].path)+token.substr(split) if changes.has(path) else token)
	return result


static func rewrite_coverage(input: Dictionary, changes: Dictionary, catalog_sha: String) -> Dictionary:
	var result := input.duplicate(true)
	result.catalog_sha256 = catalog_sha
	result.pages = {}
	for path: String in input.pages:
		var row: Dictionary = input.pages[path].duplicate(true)
		var target := path
		if changes.has(path):
			if row.identity!=changes[path].old_identity or not row.tokens[0].is_empty():
				return {}
			target = changes[path].path
			row.identity = changes[path].identity
			row.sha256 = changes[path].sha256
		for n in row.leaves.size():
			if changes.has(row.leaves[n]):
				row.leaves[n] = changes[row.leaves[n]].path
		for kind in 2:
			var tokens := remap_tokens(row.tokens[kind],changes)
			if tokens.size()!=row.tokens[kind].size():
				return {}
			row.tokens[kind] = tokens
		if result.pages.has(target):
			return {}
		result.pages[target] = row
	for id: int in result.sources:
		var tokens := remap_tokens(result.sources[id],changes)
		if tokens.size()!=result.sources[id].size():
			return {}
		result.sources[id] = tokens
	return result
