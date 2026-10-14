extends RefCounted
## 增量迁址：保留已安装M20底座，只准备新增资源清单，不改变默认启动。
const Native := preload("res://scripts/rendering/tokyo_hlod_native.gd")
const Override := preload("res://scripts/rendering/tokyo_partition_override.gd")
const Adapter := preload("res://scripts/rendering/tokyo_partition_catalog.gd")
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Coverage := preload("res://scripts/rendering/tokyo_hlod_coverage.gd")
const Values := preload("res://scripts/tests/build_tokyo_portable_package.gd")
const Paths := preload("res://scripts/tests/tokyo_portable_paths.gd")
var output := ""
var target := ""
var copies: Dictionary={}
var relocated_paths: Dictionary={}


func record(source: String, relative: String) -> Dictionary:
	var sha := FileAccess.get_sha256(source)
	if not Contract.sha(sha) or relative.is_absolute_path() or ".." in relative: return {}
	var row := {"source":source,"relative":relative,"sha256":sha}
	if copies.has(relative) and copies[relative]!=row: return {}
	copies[relative]=row
	return {"path":target+relative,"sha256":sha}


func asset(binding: Dictionary, extension: String) -> Dictionary:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return {}
	if String(binding.path).begins_with("res://resources/maps/tokyo_playable/m20/"): return binding.duplicate()
	if not String(binding.path).is_absolute_path(): return {}
	var moved := record(binding.path,"assets/"+String(binding.sha256)+"."+extension)
	if not moved.is_empty(): relocated_paths[binding.path]=moved.path
	return moved


func json(relative: String, data: Dictionary) -> Dictionary:
	var path := output.path_join(relative)
	if FileAccess.file_exists(path) or DirAccess.make_dir_recursive_absolute(path.get_base_dir())!=OK: return {}
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return {}
	file.store_string(JSON.stringify(data,"\t"));file.close()
	return record(path,relative)


func partition(binding: Dictionary, index: int) -> Dictionary:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return {}
	var data := Values.read_values(binding.path)
	if data.get("schema")!=3 or Adapter.normalize(data,binding).is_empty(): return {}
	var paths: Dictionary={}
	for page: Dictionary in data.pages.values():
		var physical := asset(page.bundle,"res")
		if physical.is_empty(): return {}
		paths[page.bundle.path]=physical.path
	if not Paths.reversible(data,paths): return {}
	var moved: Dictionary=Paths.rewrite(data,paths)
	var relative := "partition_%02d.bin"%index
	var path := output.path_join(relative)
	if not Values.save_values(path,moved): return {}
	var result := record(path,relative)
	if result.is_empty(): return {}
	result.configuration=binding.configuration
	var original := Adapter.normalize(data,binding)
	var normalized := Adapter.normalize(moved,result)
	if normalized.is_empty(): return {}
	for key: String in original.keys:
		if not normalized.keys.has(key): return {}
		relocated_paths[original.keys[key]]=normalized.keys[key]
	return result


func ground(binding: Dictionary, native: RefCounted) -> Dictionary:
	var data := Override.json_binding(binding)
	if data.is_empty() or not data.get("rows") is Dictionary: return {}
	for row: Dictionary in data.rows.values():
		for field: String in ["native_texture","native_height"]:
			if field=="native_height" and not row.has(field): continue
			if not row.get(field) is Dictionary or asset(row[field],"res").is_empty(): return {}
	# 逻辑页身份包含分区摘要；只搬图片而不重绑页键会让地表静默脱离新分区。
	if not Paths.reversible(data,relocated_paths): return {}
	var moved: Dictionary=Paths.rewrite(data,relocated_paths)
	var result := json("ground.json",moved)
	if result.is_empty(): return {}
	var staged := result.duplicate()
	staged.path=output.path_join("ground.json")
	var reader := preload("res://scripts/rendering/tokyo_native_ground.gd")
	var verified := reader.read(staged,Paths.rewrite(native.pages,relocated_paths))
	if verified.is_empty() or verified.rows.size()!=native.ground.rows.size() or verified.limits!=native.ground.limits: return {}
	for configuration: String in verified.limits:
		for entry: Dictionary in native._partition_roots.get(configuration,native.catalog.configurations[configuration]):
			if reader.tree(Paths.rewrite(entry,relocated_paths),verified.rows).is_empty(): return {}
	return result


func build(input: Dictionary, digest: String) -> int:
	var package := Override.json_binding(input.get("incremental_package"))
	var version: String=input.get("version","")
	output=input.get("output","")
	if package.is_empty() or not version.is_valid_identifier() or version.begins_with("_") \
		or version=="m20" or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	target="res://resources/maps/tokyo_playable/"+version+"/"
	if DirAccess.dir_exists_absolute(target): return 1
	var native := Native.new()
	if not native.read(package.get("native",{})): return 1
	var prior: Dictionary=package.native.get("partition_override",{})
	var old_input := Override.json_binding(prior.get("input"))
	var old_proof := Override.json_binding(prior.get("proof"))
	var coverage := Override.json_binding(package.get("coverage"))
	if old_input.is_empty() or old_proof.is_empty() or coverage.is_empty(): return 1
	# 先核全部旧HLOD与来源证明，再迁址；不把有摘要的损坏清单包装成合格包。
	for binding: Dictionary in package.catalogs:
		var catalog := Contract.read(binding.path,binding.sha256)
		if catalog.is_empty() or Coverage.bind(coverage,catalog).is_empty(): return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var requests: Array=[]
	var rows: Array=[]
	for index in old_input.attachments.size():
		var request: Dictionary=old_input.attachments[index]
		var packed := partition(request.partition,index)
		if packed.is_empty(): return 1
		requests.append({"configuration":request.configuration,"partition":packed})
		var evidence: Dictionary=old_proof.rows[index].duplicate(true)
		# 导出原网格只是制作时的辅助输出，不是运行时依赖。
		evidence.erase("exports")
		rows.append(evidence)
	var attachment := json("attachments.json",{"attachments":requests,"migration_source_sha256":prior.input.sha256})
	if attachment.is_empty(): return 1
	var proof := json("proof.json",{"input_sha256":attachment.sha256,"catalog_sha256":native.catalog_sha,
		"rows":rows,"migration_source_sha256":prior.proof.sha256,"runtime_integrated":false})
	if proof.is_empty(): return 1
	package.native.partition_override={"input":attachment,"proof":proof}
	if package.native.has("ground_override"):
		var migrated_ground := ground(package.native.ground_override,native)
		if migrated_ground.is_empty(): return 1
		package.native.ground_override=migrated_ground
	var recipe := asset(package.get("middle_massing_recipe",{}),"json")
	if recipe.is_empty(): return 1
	package.middle_massing_recipe=recipe
	var changed := 0
	for index in package.catalogs.size():
		var binding: Dictionary=package.catalogs[index]
		if String(binding.path).begins_with("res://resources/maps/tokyo_playable/m20/"): continue
		var data := Override.json_binding(binding)
		if data.is_empty() or not data.has("middle_massing_recipe"): return 1
		# 网格与压缩纹理均复用正式实物；原始制作路径只保留为来源注记，运行时不读取。
		for page: Dictionary in data.rows:
			for resource_binding: Dictionary in [page.native_geometry,page.native_texture]:
				if not String(resource_binding.path).begins_with("res://resources/maps/tokyo_playable/m20/") \
					or FileAccess.get_sha256(resource_binding.path)!=resource_binding.sha256: return 1
		data.input_path=recipe.path
		data.middle_massing_recipe=recipe
		var relocated := json("middle.json",data)
		if relocated.is_empty(): return 1
		var normalized := Contract.normalize(data)
		if normalized.is_empty(): return 1
		normalized.identity={"path":relocated.path,"sha256":relocated.sha256,"input_sha256":data.input_sha256}
		var matches := 0
		for item: Dictionary in coverage.catalogs:
			if item.manifest.path==binding.path and item.manifest.sha256==binding.sha256:
				item.manifest=relocated.duplicate();matches+=1
		if matches!=1 or Coverage.bind(coverage,normalized).is_empty(): return 1
		var updated := binding.duplicate()
		updated.path=relocated.path;updated.sha256=relocated.sha256
		package.catalogs[index]=updated
		changed+=1
	if changed!=1: return 1
	var covered := json("coverage.json",coverage)
	if covered.is_empty(): return 1
	package.coverage=covered
	package["candidate_only"]=true
	var installed := json("package.json",package)
	if installed.is_empty(): return 1
	var inventory := {"schema":1,"input_sha256":digest,"target":target,"package":installed,
		"copies":copies.values(),"native_partition_pages":native._partition_pages.size(),
		"partition_count":requests.size(),"base_catalog_sha256":native.catalog_sha,
		"runtime_verified":false,"default_changed":false,"source_package":input.incremental_package}
	# inventory本身不进入拷贝清单，避免自引用摘要。
	return 0 if not json("inventory.json",inventory).is_empty() else 1


static func run(input: Dictionary, digest: String) -> int:
	return load("res://scripts/tests/stage_tokyo_incremental_package.gd").new().build(input,digest)
