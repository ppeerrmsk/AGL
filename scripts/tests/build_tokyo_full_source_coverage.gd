extends "res://scripts/tests/build_tokyo_source_coverage.gd"
## 保留原逐面/缺依赖算法；完整目录改读真实组件，不加载不存在的逻辑页文件。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Components := preload("res://scripts/rendering/tokyo_component_manifest.gd")
const Assembly := preload("res://scripts/rendering/tokyo_component_page.gd")
const FullBake := preload("res://scripts/tests/bake_tokyo_full_grid_configuration.gd")
var _component_rows: Dictionary={}
var _fixed_hashes:=PackedStringArray()


func run() -> int:
	var input:=OS.get_environment("AGL_TOKYO_FULL_COVERAGE_INPUT")
	if not Root.binding_valid({"path":input,"sha256":OS.get_environment("AGL_TOKYO_FULL_COVERAGE_SHA")}):return 1
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if not config is Dictionary or config.get("schema")!=1 or config.get("fixed",[]).size()!=16:return 1
	for key: String in ["catalog","components","schedule","plan"]:
		if not Root.binding_valid(config.get(key)):return 1
	if OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG")!=config.catalog.path \
			or OS.get_environment("AGL_TOKYO_COVERAGE_SCHEDULE")!=config.schedule.path \
			or OS.get_environment("AGL_TOKYO_COVERAGE_CONFIG")!=config.configuration \
			or OS.get_environment("AGL_TOKYO_COVERAGE_PLANS")!=config.plans_directory:return 1
	var catalog: Resource=ResourceLoader.load(config.catalog.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.plan.path))
	if catalog==null or catalog.schema_version!=2 or not catalog.valid() or not FullBake.valid(plan) or plan.configuration.name!=config.configuration:return 1
	var manifest:=Components.read(config.components.path,catalog,config.catalog.sha256)
	if manifest.is_empty():return 1
	_component_rows=manifest.pages
	for item: Dictionary in config.fixed:
		if not Root.binding_valid(item):return 1
		_fixed_hashes.append(item.sha256)
	return super.run()


func _fixed_sha(parent: int) -> String:
	return _fixed_hashes[parent] if parent>=0 and parent<_fixed_hashes.size() else ""


func _page_sha(entry: Dictionary) -> String:
	# schema2该字段绑定组件集合的值身份，不冒充logical文件的SHA。
	return var_to_bytes(_component_rows.get(entry.path,{})).hex_encode().sha256_text()


func _read_page(entry: Dictionary, catalog: Resource) -> Resource:
	var row: Dictionary=_component_rows.get(entry.path,{})
	if not Components.valid_row(row,catalog.descriptors.get(entry.path,{}),row.get("components",{})):return null
	var loaded: Dictionary={}
	for path: String in row.components:
		if not Root.binding_valid(row.components[path]):return null
		loaded[path]=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	return Assembly.assemble(row,loaded)


func _audit_cuts(data: Dictionary, catalog: Resource) -> Dictionary:
	var result:=super._audit_cuts(data,catalog)
	var tiles: Dictionary={}
	var mixed: Dictionary={}
	for parent: Dictionary in catalog.configurations[data.configuration]:
		for mid: Dictionary in parent.children:
			for tile: Dictionary in mid.children:
				tiles[tile.path]={"identity":data.pages[tile.path].identity,"layers":3}
		if int(parent.parent_id)%3==0:
			mixed[parent.path]={"identity":data.pages[parent.path].identity,"layers":3}
			continue
		for index in parent.children.size():
			var mid: Dictionary=parent.children[index]
			if index==0:
				mixed[mid.path]={"identity":data.pages[mid.path].identity,"layers":3}
			else:
				for tile_index in mid.children.size():
					var tile: Dictionary=mid.children[tile_index]
					if index==3 or (index==1 and tile_index==0):
						for leaf: Dictionary in tile.children:
							mixed[leaf.path]={"identity":data.pages[leaf.path].identity,"layers":3}
					else:
						mixed[tile.path]={"identity":data.pages[tile.path].identity,"layers":3}
	_check(Coverage.covered_sources(data,tiles,data.configuration,data.collision_sha256,data.catalog_sha256).size()==data.sources.size(),"full-grid 256 tile tier covers every source")
	_check(Coverage.covered_sources(data,mixed,data.configuration,data.collision_sha256,data.catalog_sha256).size()==data.sources.size(),"full-grid mixed four-depth cut covers every source")
	for parent: Dictionary in catalog.configurations[data.configuration]:
		if not mixed.has(parent.path):
			mixed[parent.path]={"identity":data.pages[parent.path].identity,"layers":3}
			_check(Coverage.covered_sources(data,mixed,data.configuration,data.collision_sha256,data.catalog_sha256).is_empty(),"full-grid overlapping ancestor and descendants rejected")
			break
	result["full_tile_cut"]=tiles.size()
	result["mixed_four_depth_cut"]=true
	return result
