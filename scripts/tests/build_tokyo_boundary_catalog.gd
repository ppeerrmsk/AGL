extends RefCounted
## 汇总边界增量组件树；沿用内部实物，覆盖证明另行重载校验。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Components := preload("res://scripts/rendering/tokyo_component_manifest.gd")
const Boundary := preload("res://scripts/rendering/tokyo_boundary_extent.gd")


static func paths(entry: Dictionary, result: Array[String]) -> void:
	result.append(entry.path)
	for child: Dictionary in entry.children: paths(child,result)


static func read_value(path: String) -> Variant:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null: return null
	var value: Variant=file.get_var(false)
	file.close()
	return value


static func run(path: String, digest: String) -> int:
	if not Root.binding_valid({"path":path,"sha256":digest}): return 1
	var input: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not input is Dictionary or input.get("schema")!=1 or input.get("trees",[]).size()!=77: return 1
	for name: String in ["catalog","components","hierarchy","layout","registry","boundary_sources"]:
		if not Root.binding_valid(input.get(name)): return 1
	if input.hierarchy.sha256!=Boundary.HIERARCHY_SHA or input.layout.sha256!=Boundary.LAYOUT_SHA \
		or input.registry.sha256!=Boundary.REGISTRY_SHA or input.boundary_sources.sha256!=Boundary.SOURCE_SHA: return 1
	var catalog: Resource=ResourceLoader.load(input.catalog.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if catalog==null or not catalog.valid() or Components.read(input.components.path,catalog,input.catalog.sha256).is_empty(): return 1
	var data: Variant=read_value(input.components.path)
	if not data is Dictionary: return 1
	var seen: Dictionary={}
	for binding: Dictionary in input.trees:
		for field: String in ["input","manifest","proof"]:
			if not Root.binding_valid(binding.get(field)): return 1
		var recipe: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.input.path))
		var proof: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.proof.path))
		var tree: Variant=read_value(binding.manifest.path)
		var config:=str(recipe.get("configuration",""))
		var parent:=int(recipe.get("parent",-1))
		var key:=config+":"+str(parent)
		if seen.has(key) or not catalog.configurations.has(config) or parent not in [0,1,2,3,7,11,15] \
			or recipe.get("catalog")!=input.catalog or recipe.get("components")!=input.components \
			or recipe.get("hierarchy")!=input.hierarchy or recipe.get("registry")!=input.registry \
			or recipe.get("boundary_sources")!=input.boundary_sources \
			or proof.get("input_sha256")!=binding.input.sha256 or proof.get("manifest_sha256")!=binding.manifest.sha256 \
			or proof.get("saved_roundtrip")!=true or proof.get("formal_buildings_untouched")!=true \
			or not tree is Dictionary or tree.get("pages",{}).size()!=277 or tree.get("descriptors",{}).size()!=277: return 1
		seen[key]=true
		var old_paths: Array[String]=[]
		paths(catalog.configurations[config][parent],old_paths)
		if old_paths.size()!=277: return 1
		for previous in old_paths:
			if not data.pages.has(previous) or not catalog.descriptors.has(previous): return 1
			data.pages.erase(previous);catalog.descriptors.erase(previous)
		for logical: String in tree.pages:
			if data.pages.has(logical) or catalog.descriptors.has(logical): return 1
			data.pages[logical]=tree.pages[logical]
			catalog.descriptors[logical]=tree.descriptors[logical]
		for physical: String in tree.physical:
			if data.physical.has(physical) and data.physical[physical]!=tree.physical[physical]: return 1
			data.physical[physical]=tree.physical[physical]
		catalog.configurations[config][parent]=tree.root
	if seen.size()!=77 or data.pages.size()!=48752: return 1
	var used: Dictionary={}
	for row: Dictionary in data.pages.values():
		for physical: String in row.components: used[physical]=data.physical[physical]
	data.physical=used
	catalog.full_grid.layout_sha256=Boundary.LAYOUT_SHA
	catalog.full_grid.hierarchy_sha256=Boundary.HIERARCHY_SHA
	catalog.full_grid.regional_registry_sha256=Boundary.REGISTRY_SHA
	catalog.full_grid.bounds=Boundary.EXPANDED
	catalog.full_grid.source_count=3018595
	catalog.full_grid.input_manifest_sha256=digest
	var output:=str(input.get("output",""))
	if not output.is_absolute_path() or output.get_base_dir()!=path.get_base_dir() or DirAccess.dir_exists_absolute(output) \
		or not catalog.valid() or DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var destination:=output.path_join("catalog.res")
	if ResourceSaver.save(catalog,destination,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
	var restored: Resource=ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
	if restored==null or not restored.valid() or restored.full_grid!=catalog.full_grid or restored.descriptors!=catalog.descriptors: return 1
	data.catalog_sha256=FileAccess.get_sha256(destination)
	var file:=FileAccess.open(output.path_join("components.bin"),FileAccess.WRITE)
	if file==null: return 1
	file.store_var(data,false);file.close()
	if Components.read(output.path_join("components.bin"),restored,data.catalog_sha256).is_empty(): return 1
	file=FileAccess.open(output.path_join("provenance.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"input_sha256":digest,"catalog_sha256":data.catalog_sha256,
		"components_sha256":FileAccess.get_sha256(output.path_join("components.bin")),"saved_roundtrip":true,
		"replaced_roots":77,"retained_roots":99,"coverage_pending":true,"installed":false}))
	file.close()
	return 0
