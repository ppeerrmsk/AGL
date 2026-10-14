extends RefCounted
## 独立重载：内部叶逐角不变，新增边界不碰正式楼，父子三层守恒后才迁移显示凭据。
const Builder := preload("res://scripts/tests/build_tokyo_boundary_tree.gd")
const Assembly := preload("res://scripts/tests/build_tokyo_boundary_catalog.gd")
const Coverage := preload("res://scripts/experiments/tokyo_source_coverage.gd")
var _old: Dictionary={}
var _new: Dictionary={}
var _paths: Dictionary={}
var _nodes: Dictionary={}
var _game: Dictionary={}
var _failed:=false
var _checked:=0
var _boundary_leaves:=0


func verify(old: Dictionary, current: Dictionary, load_unchanged: bool = true) -> Array[ArrayMesh]:
	var empty: Array[ArrayMesh]=[]
	if old.parent_id!=current.parent_id or old.cell_id!=current.cell_id or old.children.size()!=current.children.size():
		_failed=true;return empty
	_paths[old.path]=current.path
	if old.path==current.path:
		if _old.pages[old.path]!=_new.pages[current.path]: _failed=true
		for n in old.children.size(): verify(old.children[n],current.children[n],false)
		return Builder.meshes(_new.pages[current.path],_new.physical) if load_unchanged else empty
	var loaded:=Builder.meshes(_new.pages[current.path],_new.physical)
	if loaded.size()!=3: _failed=true;return empty
	_checked+=1
	if current.children.is_empty():
		var node: Dictionary=_nodes.get(int(current.cell_id),{})
		if node.is_empty(): _failed=true;return empty
		var coordinates: PackedStringArray=String(node.tile).split("_")
		var boundary: bool=int(coordinates[1])==15 or int(coordinates[2])==0
		if boundary:
			_boundary_leaves+=1
			# 每个正式楼都保留原包逐面凭据；边界不授予任何新source token。
			for kind in 2:
				if loaded[kind].get_surface_count()==0: continue
				var box: AABB=loaded[kind].get_aabb()
				var footprint:=Rect2(box.position.x,box.position.z,box.size.x,box.size.z)
				if not Builder.Guard.inspect_bounds(footprint,_game.entries).get("standalone_merge_allowed",false):
					_failed=true;return empty
		else:
			var previous:=Builder.meshes(_old.pages[old.path],_old.physical)
			if previous.size()!=3: _failed=true;return empty
			for kind in 3:
				if Builder.ComponentTree.Read.corner_digest(previous[kind])!=Builder.ComponentTree.Read.corner_digest(loaded[kind]):
					_failed=true;return empty
	else:
		var pieces: Array=[]
		for n in current.children.size():
			var child:=verify(old.children[n],current.children[n])
			if child.size()!=3: _failed=true;return empty
			pieces.append(child)
		for kind in 3:
			var inputs: Array[ArrayMesh]=[]
			for child: Array in pieces: inputs.append(child[kind])
			if not Builder.ComponentTree.Join.conserved(loaded[kind],inputs):
				_failed=true;return empty
	return loaded


func token(value: String) -> String:
	var split:=value.rfind(":")
	if split<0 or not _paths.has(value.substr(0,split)):
		_failed=true;return ""
	return String(_paths[value.substr(0,split)])+value.substr(split)


func run(path: String, digest: String) -> int:
	if not Builder.Root.binding_valid({"path":path,"sha256":digest}): return 1
	var input: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not input is Dictionary or input.get("schema")!=1: return 1
	for name: String in ["catalog","components","baseline_catalog","baseline_components","baseline_coverage","hierarchy"]:
		if not Builder.Root.binding_valid(input.get(name)): return 1
	if input.hierarchy.sha256!=Assembly.Boundary.HIERARCHY_SHA: return 1
	var catalog: Resource=ResourceLoader.load(input.catalog.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var baseline: Resource=ResourceLoader.load(input.baseline_catalog.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if catalog==null or baseline==null or not catalog.valid() or not baseline.valid() \
		or not Assembly.Boundary.full_grid(catalog.full_grid) or catalog.collision_sha256!=baseline.collision_sha256 \
		or catalog.owners_sha256!=baseline.owners_sha256: return 1
	var config:=str(input.get("configuration",""))
	if not catalog.configurations.has(config): return 1
	if Assembly.Components.read(input.components.path,catalog,input.catalog.sha256).is_empty() \
		or Assembly.Components.read(input.baseline_components.path,baseline,input.baseline_catalog.sha256).is_empty(): return 1
	_old=Assembly.read_value(input.baseline_components.path)
	_new=Assembly.read_value(input.components.path)
	var old_data: Variant=Assembly.read_value(input.baseline_coverage.path)
	if not old_data is Dictionary or old_data.get("verified")!=true or old_data.get("catalog_sha256")!=input.baseline_catalog.sha256 \
		or old_data.get("configuration")!=config or old_data.get("collision_sha256")!=catalog.collision_sha256 \
		or old_data.get("owners_sha256")!=catalog.owners_sha256 or old_data.get("sources",{}).size()!=189 \
		or old_data.get("pages",{}).size()!=4432: return 1
	_game=Builder.Guard.read_source()
	if _game.is_empty() or _game.source_sha256!=Builder.Root.Contract.GAME_SHA or _game.collision_sha256!=catalog.collision_sha256: return 1
	var hierarchy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.hierarchy.path))
	for node: Dictionary in hierarchy.nodes.values():
		if int(node.depth)==3: _nodes[int(node.cell)]=node
	if _nodes.size()!=4096: return 1
	for parent in 16:
		verify(baseline.configurations[config][parent],catalog.configurations[config][parent],false)
		if _failed: return 1
	# 允许同批已完成的完整重建根；复用根必须仍遍历全部4432身份，496边缘叶全部重验。
	if _paths.size()!=4432 or _checked<549 or _checked>1939 or _boundary_leaves!=496: return 1
	var data: Dictionary=old_data.duplicate(true)
	data.verified=false
	data.catalog_sha256=input.catalog.sha256
	data.pages={}
	for previous: String in old_data.pages:
		var current: String=_paths[previous]
		var row: Dictionary=old_data.pages[previous].duplicate(true)
		row.identity=catalog.descriptors[current].canonical_identity
		row.sha256=var_to_bytes(_new.pages[current]).hex_encode().sha256_text()
		var leaf_paths: PackedStringArray=row.leaves
		for n in leaf_paths.size(): leaf_paths[n]=_paths[leaf_paths[n]]
		row.leaves=leaf_paths
		for kind in 2:
			var tokens: PackedStringArray=row.tokens[kind]
			for n in tokens.size(): tokens[n]=token(tokens[n])
			row.tokens[kind]=tokens
		var cell:=int(row.identity.cell)
		if _nodes.has(cell):
			var tile:=String(_nodes[cell].tile).split("_")
			if int(tile[1])==15 or int(tile[2])==0:
				if not row.tokens[0].is_empty() or not row.tokens[1].is_empty(): return 1
		data.pages[current]=row
	for source: int in data.sources:
		var tokens: PackedStringArray=data.sources[source]
		for n in tokens.size(): tokens[n]=token(tokens[n])
		data.sources[source]=tokens
	if _failed: return 1
	data["boundary_derivation"]={"input_sha256":digest,"baseline_sha256":input.baseline_coverage.sha256,
		"checked_saved_pages":_checked,"retained_leaf_corners_equal":true,"ancestor_layers_conserved":true}
	data.verified=true
	var roots: Dictionary={}
	var leaves: Dictionary={}
	for root: Dictionary in catalog.configurations[config]: roots[root.path]={"identity":data.pages[root.path].identity,"layers":3}
	for logical: String in data.pages:
		if data.pages[logical].leaves.size()==1: leaves[logical]={"identity":data.pages[logical].identity,"layers":3}
	for cut: Dictionary in [roots,leaves]:
		if Coverage.covered_sources(data,cut,config,catalog.collision_sha256,input.catalog.sha256).size()!=189: return 1
	var output:=str(input.get("output",""))
	if not output.is_absolute_path() or output.get_base_dir()!=path.get_base_dir() or FileAccess.file_exists(output): return 1
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_var(data,false);file.close()
	if Assembly.read_value(output)!=data: return 1
	print("[Boundary coverage] ",config," saved_pages=",_checked," sources=189 verified independent geometry")
	return 0
