extends RefCounted
## 三片归属与旧规范目录合流；只重建父3/11，沿用切线与游戏楼分配。
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Blocks := preload("res://scripts/tests/build_tokyo_block_catalog.gd")
const Spatial := preload("res://scripts/tests/build_tokyo_canonical_spatial.gd")
const Components := preload("res://scripts/tests/build_tokyo_mesh_components.gd")
const Manifest := preload("res://scripts/rendering/tokyo_component_manifest.gd")
const Cross := preload("res://scripts/tests/build_tokyo_cross_lod_components.gd")
const Repack := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Palette := preload("res://scripts/experiments/tokyo_palette.gd")
const Boundary := preload("res://scripts/tests/build_tokyo_boundary_transfer.gd")
const Gameplay := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")
var _catalog: Resource
var _components: Dictionary
var _changes: Dictionary = {}
var _out := ""
var _west: Resource
var _raw_west: Resource
var _source_hashes: Dictionary = {}
var _fixed: ArrayMesh


func run() -> int:
	var root := OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_SOURCE")
	_out = OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_OUT")
	if not Components.Builder.valid_sample_output(root,_out):
		return 1
	var base := root.get_base_dir()
	var original_path := base.path_join("r112-native-a/catalog.res")
	var original: Resource = load(original_path)
	var original_sha := FileAccess.get_sha256(original_path)
	var components_path := base.path_join("r112-native-a/components/manifest.bin")
	if original==null or not original.valid() or Manifest.read(components_path,original,original_sha).is_empty():
		return 1
	_catalog=original.duplicate(true)
	var file := FileAccess.open(components_path,FileAccess.READ)
	_components=file.get_var(false)
	file.close()
	var boundary_path := base.path_join("r126-boundary-b/manifest.json")
	var boundary: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(boundary_path))
	var boundary_audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("r126-boundary-b/saved_audit.json")))
	var source_path := base.path_join("r125-owned-blocks-a/manifest.json")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var source_audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base.path_join("r125-owned-blocks-a/saved_audit.json")))
	var registry_sha := FileAccess.get_sha256(root.path_join("ownership.json"))
	if boundary.get("fail",1)!=0 or boundary.get("source_catalog_sha256")!=original_sha or boundary.get("new_registry_sha256")!=registry_sha \
			or boundary_audit.get("fail",1)!=0 or boundary_audit.get("gameplay_overlap",-1)!=0 \
			or source.get("fail",1)!=0 or source.get("registry_sha256")!=registry_sha or source_audit.get("fail",1)!=0 \
			or source_audit.get("registry_sha256")!=registry_sha or source_audit.get("unique_owners")!=76473:
		return 1
	_west=load(base.path_join("r125-owned-blocks-a/west_residential/index.res"))
	_raw_west=load(base.path_join("r123-owned-native-a/west_residential/index.res"))
	if _west==null or _raw_west==null or _west.valid() or not _west.valid(registry_sha) or not _raw_west.valid(registry_sha) \
			or _west.regional_id!="west_residential" or _west.source_hash!=_raw_west.source_hash or _west.bounds!=Rect2(-6800,-2700,500,1000):
		return 1
	for path: String in [source_path,base.path_join("r123-owned-native-a/manifest.json")]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data.registry_sha256!=registry_sha:
			return 1
		for region: Dictionary in data.regions:
			if region.region=="west_residential":
				for row: Dictionary in region.rows:
					_source_hashes[row.path]=row.sha256
	var game := Gameplay.read_source()
	if game.is_empty():
		return 1
	var guard: Dictionary = source.block_transfer.gameplay_protection
	var box: Array = guard.bounds
	var checked := Gameplay.inspect_bounds(Rect2(box[0],box[1],box[2],box[3]),game.entries)
	if game.collision_sha256!=original.collision_sha256 or checked.is_empty() or not checked.standalone_merge_allowed:
		return 1
	var fixed_meshes: Array[ArrayMesh] = []
	for cell: Dictionary in _west.cells:
		var fixed: Resource = ResourceLoader.load(cell.fixed,"",ResourceLoader.CACHE_MODE_IGNORE)
		if fixed==null or not fixed.valid() or fixed.geometry_bytes!=cell.fixed_bytes:
			return 1
		fixed_meshes.append(Repack.repack(Palette.recolor(fixed.meshes[0])))
	_fixed=Repack.repack(Spatial.Join.join(fixed_meshes))
	_catalog.regional_extension={"region":"west_residential","bounds":_west.bounds,"source_count":76473,
		"registry_sha256":registry_sha,"source_manifest_sha256":FileAccess.get_sha256(source_path),"boundary_manifest_sha256":FileAccess.get_sha256(boundary_path)}
	DirAccess.make_dir_recursive_absolute(_out.path_join("components"))
	var roots: Array = []
	for configuration: String in Catalog.CONFIGURATIONS:
		var west := _west_meshes(configuration)
		if west.is_empty():
			return 1
		for parent: int in [3,11]:
			var entry: Dictionary = original.configurations[configuration][parent]
			var rows: Array = boundary.rows.filter(func(row: Dictionary) -> bool: return row.configuration==configuration and int(row.parent)==parent)
			if rows.size()!=1 or rows[0].original_sha256!=entry.sha256 or FileAccess.get_sha256(rows[0].remaining.path)!=rows[0].remaining.sha256 \
					or FileAccess.get_sha256(rows[0].removed.path)!=rows[0].removed.sha256:
				return 1
			var previous := _load(entry)
			var remaining: Resource = ResourceLoader.load(rows[0].remaining.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var removed: Resource = ResourceLoader.load(rows[0].removed.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if previous==null or remaining==null or removed==null or not remaining.valid() or not removed.valid():
				return 1
			var meshes: Array[ArrayMesh] = []
			for kind in 3:
				var mesh: ArrayMesh = previous.meshes[2] if kind==2 else remaining.meshes[kind]
				if kind<2 and not Boundary.Diff.conserved(previous.meshes[kind],mesh,removed.meshes[kind]):
					return 1
				if parent==11:
					var joined: Array[ArrayMesh] = [mesh,west[kind]]
					mesh=Repack.repack(Spatial.Join.join(joined))
					if not Spatial.Join.conserved(mesh,joined):
						return 1
				meshes.append(mesh)
			var context := {"out":_out.path_join(configuration),"configuration":configuration,"level":int(configuration.substr(3,1)),
				"parent_id":parent,"collision_sha256":original.collision_sha256,"owners_sha256":original.owners_sha256,
				"game_sources":previous.game_sources,"audit":false,
				"source_hash":(previous.source_hash+FileAccess.get_sha256(source_path)+FileAccess.get_sha256(boundary_path)+configuration).sha256_text()}
			DirAccess.make_dir_recursive_absolute(context.out)
			var changed := _replace(entry,meshes,context)
			if changed.is_empty():
				return 1
			_catalog.configurations[configuration][parent]=changed
			roots.append({"configuration":configuration,"parent":parent,"before":Array(entry.triangles),"after":Array(changed.triangles),"bytes":changed.bytes})
			print("[Tokyo regional catalog] ",configuration," parent=",parent," faces=",changed.triangles)
	for configuration: String in Catalog.CONFIGURATIONS:
		for parent in 16:
			if parent not in [3,11] and _catalog.configurations[configuration][parent]!=original.configurations[configuration][parent]:
				return 1
	var destination := _out.path_join("catalog.res")
	if not _catalog.valid() or ResourceSaver.save(_catalog,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or not saved.valid() or saved.configurations!=_catalog.configurations or saved.regional_extension!=_catalog.regional_extension:
		return 1
	var digest := FileAccess.get_sha256(destination)
	for configuration: String in Catalog.CONFIGURATIONS:
		file=FileAccess.open(base.path_join("r112-native-a/coverage-"+configuration+".bin"),FileAccess.READ)
		var old_coverage: Dictionary=file.get_var(false)
		file.close()
		if old_coverage.catalog_sha256!=original_sha or not old_coverage.verified or old_coverage.sources.size()!=48:
			return 1
		var coverage := Blocks.rewrite_coverage(old_coverage,_changes,digest)
		if coverage.is_empty():
			return 1
		file=FileAccess.open(_out.path_join("coverage-"+configuration+".bin"),FileAccess.WRITE)
		file.store_var(coverage)
		file.close()
	_components.catalog_sha256=digest
	var physical: Dictionary = {}
	for row: Dictionary in _components.pages.values():
		for path: String in row.components:
			physical[path]=_components.physical[path]
	_components.physical=physical
	var component_path := _out.path_join("components/manifest.bin")
	file=FileAccess.open(component_path,FileAccess.WRITE)
	file.store_var(_components)
	file.close()
	if Manifest.read(component_path,_catalog,digest).is_empty():
		return 1
	file=FileAccess.open(_out.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"roots":roots,"changed_pages":_changes.size(),"logical":_catalog.descriptors.size(),
		"physical":physical.size(),"catalog_sha256":digest,"extension":_catalog.regional_extension,"production_enabled":false,"runtime_verified":false}))
	file.close()
	print("[Tokyo regional catalog] complete pages=",_catalog.descriptors.size()," changed=",_changes.size()," roots=16 fail=0")
	return 0


func audit(directory: String) -> int:
	var path := directory.path_join("catalog.res")
	var catalog: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if catalog==null or not catalog.valid():
		return 1
	var digest := FileAccess.get_sha256(path)
	var data := Manifest.read(directory.path_join("components/manifest.bin"),catalog,digest)
	if catalog.regional_extension.is_empty() or data.is_empty():
		return 1
	var before: Resource = load(directory.get_base_dir().path_join("r112-native-a/catalog.res"))
	var physical: Dictionary = {}
	for logical: String in catalog.descriptors:
		var row: Dictionary = data.pages[logical]
		var page: Resource = ResourceLoader.load(logical,"",ResourceLoader.CACHE_MODE_IGNORE)
		if page==null or not page.valid() or page.stream_identity()!=row.canonical_identity or page.geometry_bytes!=row.bytes or page.triangles!=row.triangles or page.game_sources!=row.game_sources:
			return 1
		for kind in 3:
			var component_path: String = row.mapping[kind][0]
			var component: Resource = ResourceLoader.load(component_path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var expected: Dictionary = row.components[component_path]
			if component==null or not component.valid() or component.stream_identity()!=expected.canonical_identity or component.geometry_bytes!=expected.bytes \
					or not Spatial.Join.conserved(page.meshes[kind],[component.meshes[row.mapping[kind][1]]]):
				return 1
			physical[component_path]=true
	var changed := 0
	for configuration: String in Catalog.CONFIGURATIONS:
		var file := FileAccess.open(directory.path_join("coverage-"+configuration+".bin"),FileAccess.READ)
		var coverage: Dictionary = file.get_var(false)
		file.close()
		if coverage.catalog_sha256!=digest or not coverage.verified or coverage.sources.size()!=48 or coverage.pages.size()!=208 \
				or coverage.collision_sha256!=before.collision_sha256 or coverage.owners_sha256!=before.owners_sha256:
			return 1
		for page_path: String in coverage.pages:
			if coverage.pages[page_path].identity!=catalog.descriptors[page_path].canonical_identity or FileAccess.get_sha256(page_path)!=coverage.pages[page_path].sha256:
				return 1
		for parent in 16:
			if parent in [3,11]:
				changed+=1
			elif catalog.configurations[configuration][parent]!=before.configurations[configuration][parent]:
				return 1
	var output := directory.path_join("saved_audit.json")
	if FileAccess.file_exists(output):
		return 1
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"catalog_sha256":digest,"pages":catalog.descriptors.size(),"physical":physical.size(),"changed_roots":changed,"coverage_configurations":11,"game_sources":48,"visual_acceptance":false}))
	file.close()
	print("[Regional catalog audit] pages=",catalog.descriptors.size()," physical=",physical.size()," fail=0")
	return 0


func _west_meshes(configuration: String) -> Array[ArrayMesh]:
	var index: Resource = _raw_west if configuration.ends_with("guarded") else _west
	var low: Array[ArrayMesh] = []
	var high: Array[ArrayMesh] = []
	for cell: Dictionary in index.cells:
		var descriptor: Dictionary = cell.mid if configuration=="lod4_mid" else cell.levels[int(configuration.substr(3,1))]
		if not _source_hashes.has(descriptor.path) or FileAccess.get_sha256(descriptor.path)!=_source_hashes[descriptor.path]:
			return []
		var page: Resource = ResourceLoader.load(descriptor.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if page==null or not page.valid() or page.triangles!=descriptor.triangles or page.geometry_bytes!=descriptor.bytes:
			return []
		low.append(Repack.repack(Palette.recolor(page.meshes[0])))
		high.append(Repack.repack(Palette.recolor(page.meshes[1])))
	return [Repack.repack(Spatial.Join.join(low)),Repack.repack(Spatial.Join.join(high)),_fixed]


func _load(entry: Dictionary) -> Resource:
	if FileAccess.get_sha256(entry.path)!=entry.sha256:
		return null
	var page: Resource = ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	return page if page!=null and page.valid() and page.stream_identity()==_catalog.descriptors[entry.path].canonical_identity else null


func _replace(entry: Dictionary, meshes: Array[ArrayMesh], context: Dictionary) -> Dictionary:
	var previous := _load(entry)
	if previous==null:
		return {}
	var result := Spatial._page(meshes,entry.cell_id,entry.ancestor_id,context)
	if result.is_empty():
		return {}
	var page: Resource = ResourceLoader.load(result.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if page.game_sources!=previous.game_sources:
		return {}
	var old_identity: Dictionary = _catalog.descriptors[entry.path].canonical_identity
	_catalog.descriptors.erase(entry.path)
	_catalog.descriptors[result.path]={"bytes":page.geometry_bytes,"canonical_identity":page.stream_identity()}
	result.key=entry.key
	_changes[entry.path]={"path":result.path,"sha256":result.sha256,"identity":page.stream_identity(),"old_identity":old_identity}
	var row: Dictionary = _components.pages[entry.path].duplicate(true)
	row.components={}
	for kind in 3:
		var key := Cross.mesh_key(meshes[kind],kind)
		var path := _out.path_join("components/%d_%s.res" % [kind,key])
		if not _components.physical.has(path):
			var single: Array[ArrayMesh] = [meshes[kind]]
			var descriptor := Components._save(single,key,path)
			if descriptor.is_empty():
				return {}
			_components.physical[path]=descriptor
		row.mapping[kind]=[path,0]
		row.components[path]=_components.physical[path]
	row.bytes=page.geometry_bytes
	row.triangles=page.triangles
	row.canonical_identity=page.stream_identity()
	if not Manifest.valid_row(row,_catalog.descriptors[result.path],_components.physical):
		return {}
	_components.pages.erase(entry.path)
	_components.pages[result.path]=row
	if not entry.get("children",[]).is_empty():
		result.cuts=entry.cuts
		result.children=[]
		var pieces := Spatial._split(meshes,entry.cuts)
		if pieces.is_empty():
			return {}
		for child in 4:
			var batch: Array[ArrayMesh] = [pieces[0][child],pieces[1][child],pieces[2][child]]
			var changed := _replace(entry.children[child],batch,context)
			if changed.is_empty():
				return {}
			result.children.append(changed)
	return result
