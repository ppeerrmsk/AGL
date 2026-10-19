extends RefCounted
## 汇总全部实物组件树；目录只是流送入口，尚须逐面coverage才允许正式采用。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Components := preload("res://scripts/rendering/tokyo_component_manifest.gd")


static func run(input: String, digest: String, output: String) -> int:
	if not Root.binding_valid({"path":input,"sha256":digest}) or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output):return 1
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if not config is Dictionary or config.get("schema")!=1:return 1
	for key: String in ["completion","full_input","schedule"]:
		if not Root.binding_valid(config.get(key)):return 1
	var complete: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.completion.path))
	var whole: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.full_input.path))
	var schedule: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.schedule.path))
	if not complete.get("component_trees_complete",false) or complete.get("configurations",[]).size()!=11 \
			or whole.get("tiles_complete")!=256 or whole.get("tiles",[]).size()!=256 \
			or whole.get("source_grid",{}).get("sha256")!=Root.Contract.GRID_SHA or whole.get("ownership",{}).get("sha256")!=Root.Contract.REGIONAL_SHA \
			or not schedule.get("passed",false) or not schedule.get("source_order_independent",false) or schedule.get("owners",[]).size()!=189 \
			or schedule.get("collision_sha256")!=Root.Contract.COLLISION_SHA or schedule.get("game_source_sha256")!=Root.Contract.GAME_SHA:return 1
	var catalog:=Catalog.new()
	catalog.schema_version=2
	catalog.collision_sha256=schedule.collision_sha256
	catalog.owners_sha256=schedule.owners_sha256
	catalog.full_grid={"grid_sha256":Root.Contract.GRID_SHA,"layout_sha256":Root.Contract.LAYOUT_SHA,
		"hierarchy_sha256":Root.Contract.HIERARCHY_SHA,"regional_registry_sha256":Root.Contract.REGIONAL_SHA,
		"game_owners_sha256":schedule.owners_sha256,"input_manifest_sha256":config.full_input.sha256,
		"tile_count":256,"source_count":2859809,"game_source_count":189,"game_source_sha256":Root.Contract.GAME_SHA,"bounds":Root.Contract.BOUNDS}
	var pages: Dictionary={}
	var physical: Dictionary={}
	for group: Dictionary in complete.configurations:
		var name: String=group.get("configuration","")
		if name not in Catalog.CONFIGURATIONS or catalog.configurations.has(name) or group.get("roots",[]).size()!=16 or not Root.binding_valid(group.get("bundle_proof")):return 1
		var bundle_proof: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(group.bundle_proof.path))
		if not bundle_proof.get("passed",false):return 1
		var roots: Array=[]
		for binding: Dictionary in group.roots:
			if binding.get("parent")!=roots.size():return 1
			for key: String in ["manifest","provenance","proof"]:
				if not Root.binding_valid(binding.get(key)):return 1
			var evidence: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.proof.path))
			var provenance: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.provenance.path))
			if evidence.get("exit",-1)!=0 or provenance.get("configuration")!=name or provenance.get("parent")!=roots.size() \
					or not provenance.get("fixed_included",false) or not provenance.get("gameplay_additions_included",false) or not provenance.get("saved_components",false):return 1
			var file:=FileAccess.open(binding.manifest.path,FileAccess.READ)
			if file==null:return 1
			var tree: Variant=file.get_var(false)
			file.close()
			if not tree is Dictionary or tree.get("pages",{}).size()!=277 or tree.get("descriptors",{}).size()!=277:return 1
			for path: String in tree.pages:
				if pages.has(path) or catalog.descriptors.has(path) or not tree.descriptors.has(path):return 1
				pages[path]=tree.pages[path]
				catalog.descriptors[path]=tree.descriptors[path]
			for path: String in tree.physical:
				if physical.has(path) and physical[path]!=tree.physical[path]:return 1
				physical[path]=tree.physical[path]
			roots.append(tree.root)
		catalog.configurations[name]=roots
	if not catalog.valid() or pages.size()!=4432*11:return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK:return 1
	var catalog_path:=output.path_join("catalog.res")
	if ResourceSaver.save(catalog,catalog_path,ResourceSaver.FLAG_COMPRESS)!=OK:return 1
	var saved: Resource=ResourceLoader.load(catalog_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or not saved.valid() or saved.configurations!=catalog.configurations or saved.descriptors!=catalog.descriptors or saved.full_grid!=catalog.full_grid:return 1
	var manifest: Dictionary={"schema":2,"catalog_sha256":FileAccess.get_sha256(catalog_path),"configurations":PackedStringArray(Catalog.CONFIGURATIONS),
		"pages":pages,"physical":physical,"production_enabled":false}
	var manifest_path:=output.path_join("components.bin")
	var file:=FileAccess.open(manifest_path,FileAccess.WRITE)
	if file==null:return 1
	file.store_var(manifest,false)
	file.close()
	if Components.read(manifest_path,saved,manifest.catalog_sha256).is_empty():return 1
	file=FileAccess.open(output.path_join("provenance.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"input_sha256":digest,"catalog_sha256":manifest.catalog_sha256,
		"components_sha256":FileAccess.get_sha256(manifest_path),"pages":pages.size(),"physical":physical.size(),"source_coverage_proven":false,"installed":false},"",true,true))
	file.close()
	print("[Full catalog] pages=",pages.size()," physical=",physical.size()," saved_metadata=true coverage_pending=true")
	return 0
