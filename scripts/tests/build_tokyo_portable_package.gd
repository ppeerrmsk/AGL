extends RefCounted
## 已逐面认证的完整目录离线迁址。输出待拷贝清单，不提前写正式目录或启用默认。
const Paths := preload("res://scripts/tests/tokyo_portable_paths.gd")
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Components := preload("res://scripts/rendering/tokyo_component_manifest.gd")
const Coverage := preload("res://scripts/experiments/tokyo_source_coverage.gd")
const TARGET := "res://resources/maps/tokyo_full/"


static func read_values(path: String) -> Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {}
	var value: Variant=file.get_var(false)
	file.close()
	return value if value is Dictionary else {}


static func save_values(path: String, data: Dictionary) -> bool:
	if FileAccess.file_exists(path):return false
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	file.store_var(data,false)
	file.close()
	return read_values(path)==data


static func run(input: String, digest: String, output: String) -> int:
	if not Root.binding_valid({"path":input,"sha256":digest}) or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output):return 1
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if not config is Dictionary or not Root.binding_valid(config.get("completion")):return 1
	var complete: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.completion.path))
	if complete.get("source_coverage_proven")!=true or complete.get("coverage",[]).size()!=11:return 1
	for key: String in ["catalog","components","catalog_proof"]:
		if not Root.binding_valid(complete.get(key)):return 1
	var original: Resource=ResourceLoader.load(complete.catalog.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if not original is Catalog or original.schema_version!=2 or not original.valid():return 1
	if Components.read(complete.components.path,original,complete.catalog.sha256).is_empty():return 1
	var manifest:=read_values(complete.components.path)
	var source_root: String=config.get("source_root","")
	if not source_root.is_absolute_path() or not source_root.ends_with("/") or "/../" in source_root:return 1
	var paths: Dictionary={}
	for path: String in original.descriptors:
		var identity: Dictionary=original.descriptors[path].canonical_identity
		paths[path]=TARGET+"logical/%s/p%d_c%d.logical"%[identity.configuration,identity.parent,identity.cell]
	var copies: Array=[]
	var disk_bytes:=0
	for path: String in manifest.physical:
		if not path.begins_with(source_root) or "/../" in path or not path.ends_with(".res"):return 1
		var relative: String="components/"+path.trim_prefix(source_root)
		paths[path]=TARGET+relative
		var item: Dictionary=manifest.physical[path]
		if not Catalog.FullGrid.digest(item.get("sha256")):return 1
		var file:=FileAccess.open(path,FileAccess.READ)
		if file==null:return 1
		var size:=file.get_length()
		file.close()
		disk_bytes+=size
		copies.append({"source":path,"relative":relative,"sha256":item.sha256,"disk_bytes":size})
	# 拒绝路径碰撞或覆盖token的一对多迁址，所有值作逆变换逐项相等。
	for value: Dictionary in [original.configurations,original.descriptors,manifest]:
		if not Paths.reversible(value,paths):return 1
	var catalog: Resource=original.duplicate(true)
	catalog.configurations=Paths.rewrite(original.configurations,paths)
	catalog.descriptors=Paths.rewrite(original.descriptors,paths)
	if not catalog.valid() or DirAccess.make_dir_recursive_absolute(output)!=OK:return 1
	var catalog_path:=output.path_join("catalog.res")
	if ResourceSaver.save(catalog,catalog_path,ResourceSaver.FLAG_COMPRESS)!=OK:return 1
	var saved: Resource=ResourceLoader.load(catalog_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or not saved.valid() or saved.configurations!=catalog.configurations or saved.descriptors!=catalog.descriptors or saved.full_grid!=original.full_grid:return 1
	var catalog_sha:=FileAccess.get_sha256(catalog_path)
	var relocated: Dictionary=Paths.rewrite(manifest,paths)
	relocated.catalog_sha256=catalog_sha
	var components_path:=output.path_join("components.bin")
	if not save_values(components_path,relocated) or Components.read(components_path,saved,catalog_sha).is_empty():return 1
	var evidence: Array=[]
	var names: Dictionary={}
	for item: Dictionary in complete.coverage:
		var name: String=item.get("configuration","")
		if name not in Catalog.CONFIGURATIONS or names.has(name) or not Root.binding_valid(item.get("file")) or not Root.binding_valid(item.get("proof")):return 1
		names[name]=true
		var original_data:=read_values(item.file.path)
		if original_data.get("verified")!=true or original_data.get("configuration")!=name or original_data.get("catalog_sha256")!=complete.catalog.sha256 \
				or original_data.get("owners_sha256")!=catalog.owners_sha256 or original_data.get("collision_sha256")!=catalog.collision_sha256 \
				or original_data.get("pages",{}).size()!=4432 or original_data.get("sources",{}).size()!=189 or not Paths.reversible(original_data,paths):return 1
		var data: Dictionary=Paths.rewrite(original_data,paths)
		data.catalog_sha256=catalog_sha
		var cut: Dictionary={}
		for old_path: String in original_data.pages:
			if not paths.has(old_path) or original_data.pages[old_path].identity!=original.descriptors[old_path].canonical_identity:return 1
			if original_data.pages[old_path].sha256!=var_to_bytes(manifest.pages[old_path]).hex_encode().sha256_text():return 1
			var path: String=paths[old_path]
			data.pages[path].sha256=var_to_bytes(relocated.pages[path]).hex_encode().sha256_text()
			if data.pages[path].leaves.size()==1 and data.pages[path].leaves[0]==path:cut[path]={"identity":data.pages[path].identity,"layers":3}
		if Coverage.covered_sources(data,cut,name,catalog.collision_sha256,catalog_sha).size()!=189:return 1
		var relative: String="coverage_"+name+".bin"
		var path:=output.path_join(relative)
		if not save_values(path,data):return 1
		evidence.append({"configuration":name,"source_sha256":item.file.sha256,"relative":relative,"sha256":FileAccess.get_sha256(path)})
	var inventory: Dictionary={"schema":1,"input_sha256":digest,"source_completion":config.completion,
		"target":TARGET,"catalog_sha256":catalog_sha,"components_sha256":FileAccess.get_sha256(components_path),
		"coverage":evidence,"copies":copies,"geometry_disk_bytes":disk_bytes,"paths_reversible":true,
		"geometry_copy_verified":false,"installed":false,"visual_pass":false,"performance_pass":false}
	var file:=FileAccess.open(output.path_join("inventory.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(inventory,"",true,true))
	file.close()
	print("[Portable package] metadata relocated; components=",copies.size()," geometry_disk_bytes=",disk_bytes," original_geometry_unchanged=true NOT_INSTALLED")
	return 0
