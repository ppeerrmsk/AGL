extends RefCounted
## 验证已安装候选的真实加载依赖；制作来源注记不是运行时依赖。
static func run(input: Dictionary) -> int:
	var helper := preload("res://scripts/rendering/tokyo_partition_override.gd")
	var inventory := helper.json_binding(input.get("verify_incremental_package"))
	var output: String=input.get("output","")
	if inventory.is_empty() or not output.is_absolute_path() or FileAccess.file_exists(output): return 1
	var target: String=inventory.get("target","")
	if not target.begins_with("res://resources/maps/tokyo_playable/") or ".." in target or not target.ends_with("/"): return 1
	var package := helper.json_binding(inventory.get("package"))
	if package.is_empty(): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.native): return 1
	var checked := 0
	var images := 0
	for row: Dictionary in inventory.copies:
		var relative: String=row.relative
		if relative.is_absolute_path() or ".." in relative: return 1
		var path := target+relative
		if FileAccess.get_sha256(path)!=row.sha256: return 1
		if not path.ends_with(".res"): continue
		var resource: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if resource==null: return 1
		if resource is Image:
			if resource.is_empty(): return 1
			images+=1
		elif not resource.has_method("valid") or not bool(resource.call("valid")): return 1
		checked+=1
	# 只接受项目内新候选或既有正式M20，不能靠原tmp文件仍在来蒙混过关。
	var physical: Dictionary={}
	for page: Dictionary in native.pages.values():
		for path: String in page.components: physical[path]=true
	for path: String in native.ground.textures: physical[path]=true
	for path: String in physical:
		if not path.begins_with(target) and not path.begins_with("res://resources/maps/tokyo_playable/m20/"): return 1
		if not FileAccess.file_exists(path): return 1
	var report := {"fail":0,"resources_loaded":checked,"images_loaded":images,"physical_dependencies":physical.size(),
		"ground_rows":native.ground.rows.size(),"ground_limits":native.ground.limits,"partition_pages":native._partition_pages.size(),
		"package":inventory.package,"default_changed":false,"performance_sample":false}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("[Tokyo installed dependencies] ",JSON.stringify(report))
	return 0
