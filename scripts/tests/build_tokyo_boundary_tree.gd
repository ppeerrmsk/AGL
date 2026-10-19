extends RefCounted
## 边界增量：从正式组件树保留内部叶，只替换已有证明的31片边界。
const ComponentTree := preload("res://scripts/tests/build_tokyo_full_component_tree.gd")
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Guard := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")
const Index := preload("res://scripts/rendering/tokyo_cell_index.gd")


static func collect(entry: Dictionary, result: Dictionary) -> void:
	result[int(entry.cell_id)]=entry
	for child: Dictionary in entry.children: collect(child,result)


static func meshes(row: Dictionary, physical: Dictionary) -> Array[ArrayMesh]:
	var result: Array[ArrayMesh]=[]
	for mapping: Array in row.mapping:
		var binding: Dictionary=physical.get(mapping[0],{})
		if binding.is_empty() or FileAccess.get_sha256(mapping[0])!=binding.sha256: return []
		var component: Resource=ResourceLoader.load(mapping[0],"",ResourceLoader.CACHE_MODE_IGNORE)
		if component==null or not component.valid() or component.stream_identity()!=binding.canonical_identity \
			or component.geometry_bytes!=binding.bytes or int(mapping[1])>=component.meshes.size(): return []
		result.append(component.meshes[int(mapping[1])])
	return result


static func assemble(leaves: Dictionary, nodes: Dictionary, context: Dictionary, previous: Dictionary, data: Dictionary, catalog: Resource) -> Dictionary:
	# 未改变的整个子树直接复用已验证实物；只在发生变化的父级接合处读取其根网格。
	if leaves.size()!=256 or nodes.size()!=277 or previous.size()!=277 or DirAccess.dir_exists_absolute(context.output): return {}
	if DirAccess.make_dir_recursive_absolute(context.output)!=OK or DirAccess.make_dir_recursive_absolute(context.fixed_output)!=OK: return {}
	var report: Dictionary={"pages":{},"descriptors":{},"physical":{},"root":{},"canonical_ready":false,"installed":false,"rebuilt_nodes":0}
	var changed: Dictionary={}
	var entries: Dictionary={}
	var ready: Dictionary={}
	for depth in [3,2,1,0]:
		var keys: Array[String]=[]
		for key: String in nodes:
			if int(nodes[key].depth)==depth: keys.append(key)
		keys.sort()
		for key: String in keys:
			var node: Dictionary=nodes[key]
			var rebuild: bool=leaves[key].size()==3 if depth==3 else false
			for child: String in node.children: rebuild=rebuild or bool(changed[child])
			changed[key]=rebuild
			if not rebuild:
				var entry: Dictionary=previous[int(node.cell)]
				var row: Dictionary=data.pages[entry.path]
				entries[key]=entry
				report.pages[entry.path]=row
				report.descriptors[entry.path]=catalog.descriptors[entry.path]
				for physical: String in row.components: report.physical[physical]=data.physical[physical]
				continue
			var layers: Array[ArrayMesh]=[]
			if depth==3:
				layers.assign(leaves[key])
			else:
				for child: String in node.children:
					if not ready.has(child):
						var loaded:=meshes(data.pages[entries[child].path],data.physical)
						if loaded.size()!=3: return {}
						ready[child]=loaded
				for kind in 3:
					var pieces: Array[ArrayMesh]=[]
					for child: String in node.children: pieces.append(ready[child][kind])
					var joined:=ComponentTree.Join.join(pieces)
					if joined==null or not ComponentTree.Join.conserved(joined,pieces): return {}
					layers.append(joined)
			var entry:=ComponentTree.emit(layers,node,context,report)
			if entry.is_empty(): return {}
			for child: String in node.children:
				entry.children.append(entries[child]);ready.erase(child)
			entries[key]=entry;ready[key]=layers
			report.rebuilt_nodes+=1
			if depth==0: report.root=entry
	if report.pages.size()!=277 or report.descriptors.size()!=277 or report.root.is_empty() or ready.size()!=1 or int(report.rebuilt_nodes) not in [71,123]: return {}
	var destination: String=context.output.path_join("manifest.bin")
	var file:=FileAccess.open(destination,FileAccess.WRITE)
	if file==null: return {}
	file.store_var(report,false);file.close()
	file=FileAccess.open(destination,FileAccess.READ)
	if file==null: return {}
	var restored: Variant=file.get_var(false);file.close()
	return report if restored==report else {}


static func run(path: String, digest: String) -> int:
	if not Root.binding_valid({"path":path,"sha256":digest}): return 1
	var input: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not input is Dictionary or input.get("schema")!=1 or input.get("tiles",{}).size()!=31: return 1
	for name: String in ["catalog","components","hierarchy","registry","boundary_sources"]:
		if not Root.binding_valid(input.get(name)): return 1
	var boundary:=preload("res://scripts/rendering/tokyo_boundary_extent.gd")
	if input.hierarchy.sha256!=boundary.HIERARCHY_SHA or input.registry.sha256!=boundary.REGISTRY_SHA or input.boundary_sources.sha256!=boundary.SOURCE_SHA: return 1
	var parent:=int(input.get("parent",-1))
	var config:=str(input.get("configuration",""))
	var choice:=Root.selection(config)
	if parent not in [0,1,2,3,7,11,15] or choice.is_empty() or config=="fixed": return 1
	var catalog: Resource=ResourceLoader.load(input.catalog.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if catalog==null or not catalog.valid(): return 1
	var file:=FileAccess.open(input.components.path,FileAccess.READ)
	if file==null: return 1
	var component_data: Variant=file.get_var(false)
	file.close()
	if not component_data is Dictionary or component_data.get("catalog_sha256")!=input.catalog.sha256 \
		or ComponentTree.Manifest.read(input.components.path,catalog,input.catalog.sha256).is_empty(): return 1
	var hierarchy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.hierarchy.path))
	var nodes: Dictionary={}
	for key: String in hierarchy.nodes:
		if int(hierarchy.nodes[key].parent)==parent: nodes[key]=hierarchy.nodes[key]
	if nodes.size()!=277: return 1
	var previous: Dictionary={}
	collect(catalog.configurations[config][parent],previous)
	if previous.size()!=277: return 1
	var gameplay:=Guard.read_source()
	if gameplay.is_empty(): return 1
	var indices: Dictionary={}
	var page_hashes: Dictionary={}
	var replacement_count:=0
	var leaves: Dictionary={}
	for key: String in nodes:
		var node: Dictionary=nodes[key]
		if int(node.depth)!=3: continue
		var tile:=str(node.tile)
		var cell:=int(node.source_cell)
		if input.tiles.has(tile):
			if not indices.has(tile):
				var record: Dictionary=input.tiles[tile]
				for name: String in ["index","transfer_manifest"]:
					if not Root.binding_valid(record.get(name)): return 1
				var index: Resource=ResourceLoader.load(record.index.path,"",ResourceLoader.CACHE_MODE_IGNORE)
				var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(record.transfer_manifest.path))
				if not index is Index or not index.valid(input.registry.sha256) or index.regional_id!=tile \
					or report.get("fail",1)!=0 or report.get("registry_sha256")!=input.registry.sha256: return 1
				var matching: Array=report.regions.filter(func(r: Dictionary) -> bool: return r.region==tile)
				if matching.size()!=1 or matching[0].index_sha256!=record.index.sha256: return 1
				var bounds: Rect2=index.bounds
				for entry: Dictionary in index.cells: bounds=bounds.merge(entry.content_bounds)
				# 本次边界不含正式楼；否则必须走完整补面烘焙，不能删除既有游戏几何。
				if not Guard.inspect_bounds(bounds,gameplay.entries).get("standalone_merge_allowed",false): return 1
				for row: Dictionary in matching[0].rows: page_hashes[row.path]=row.sha256
				indices[tile]=index
			var index: Resource=indices[tile]
			var entry: Dictionary=index.cells[cell]
			var b: Rect2=entry.bounds
			if Rect2(node.bounds[0],node.bounds[1],node.bounds[2],node.bounds[3])!=b: return 1
			var descriptor: Dictionary=entry.mid if choice.slot==6 else entry.levels[choice.slot]
			if FileAccess.get_sha256(descriptor.path)!=page_hashes.get(descriptor.path): return 1
			var page: Resource=ResourceLoader.load(descriptor.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var fixed: Resource=ResourceLoader.load(entry.fixed,"",ResourceLoader.CACHE_MODE_IGNORE)
			if page==null or fixed==null or not page.valid() or not fixed.valid() \
				or page.geometry_bytes!=descriptor.bytes or page.triangles!=descriptor.triangles: return 1
			var low: ArrayMesh=page.precision_original if choice.guarded and page.precision_original!=null else page.meshes[0]
			leaves[key]=[low,page.meshes[1],fixed.meshes[0]]
			replacement_count+=1
		else:
			leaves[key]=[]
	if replacement_count not in [64,112] or leaves.size()!=256: return 1
	var old_root: Dictionary=component_data.pages[catalog.configurations[config][parent].path]
	var context: Dictionary={"parent":parent,"configuration":config,"output":input.output,"fixed_output":input.fixed_output,
		"source_hash":digest,"fixed_source":(str(input.boundary_sources.sha256)+str(parent)).sha256_text(),
		"collision_sha256":catalog.collision_sha256,"owners_sha256":catalog.owners_sha256,"game_sources":old_root.game_sources}
	var result:=assemble(leaves,nodes,context,previous,component_data,catalog)
	if result.is_empty(): return 1
	file=FileAccess.open(String(input.output).path_join("incremental-proof.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"input_sha256":digest,"parent":parent,"configuration":config,
		"replaced_leaves":replacement_count,"retained_leaves":256-replacement_count,
		"manifest_sha256":FileAccess.get_sha256(String(input.output).path_join("manifest.bin")),
		"formal_buildings_untouched":true,"saved_roundtrip":true,"installed":false,"coverage_pending":true,
		"rebuilt_nodes":result.rebuilt_nodes,"retained_nodes":277-int(result.rebuilt_nodes)}))
	file.close()
	print("[Boundary tree] parent=",parent," config=",config," replaced=",replacement_count," retained=",256-replacement_count)
	return 0
