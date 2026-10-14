extends "res://scripts/tests/build_tokyo_regional_catalog.gd"
## 四片沿用当前规范目录，只迁移西边界独栋并合入新片，不重造已验北岸。
const SOURCE_SHA := "8ff1181df0020df6f595f4174b470cc8a688a91d56771a7312f97fcf1243ba9b"
const REGISTRY_SHA := "d35401afb80841508b0d1c6afca4a3d0eb674bacfcac51be801889b6d4cb8abb"
const BLOCK_SHA := "b8e932c95d8b067563066b596fcd0094dfabc2dea2d47430e567598dfe022568"
const RAW_SHA := "5bcc75768ecabe686633ebfcacd0fe200aaeb3dee00ce90d8cf377ad2a8200ac"
var _original: Resource
var _moved_records: Array = []
var _proof: Dictionary = {}
var _base := ""


func _prepare(root: String) -> bool:
	_base=root.get_base_dir()
	var original_path := _base.path_join("r129-native-d/catalog.res")
	var registry_path := root.path_join("ownership.json")
	var source_path := _base.path_join("r134-owned-blocks-both-a/manifest.json")
	var raw_path := _base.path_join("r134-owned-native-a/manifest.json")
	if FileAccess.get_sha256(original_path)!=SOURCE_SHA or FileAccess.get_sha256(registry_path)!=REGISTRY_SHA \
			or FileAccess.get_sha256(source_path)!=BLOCK_SHA or FileAccess.get_sha256(raw_path)!=RAW_SHA:
		return false
	_original=ResourceLoader.load(original_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if _original==null or not _original.valid() or Manifest.read(_base.path_join("r129-native-d/components/manifest.bin"),_original,SOURCE_SHA).is_empty():
		return false
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(registry_path))
	var old_path := _base.path_join("r119-owned-source-a/ownership.json")
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_path))
	if FileAccess.get_sha256(old_path)!=_original.regional_extension.registry_sha256 or registry.assignments.size()!=80511:
		return false
	var moved: Dictionary = {}
	for identity: String in previous.assignments:
		if not registry.assignments.has(identity):
			return false
		if previous.assignments[identity].owner!=registry.assignments[identity].owner:
			if previous.assignments[identity].owner!="west_residential" or registry.assignments[identity].owner!="west_extension":
				return false
			moved[identity]=true
	if moved.size()!=34:
		return false
	var city_path := _base.path_join("r119-west-source-b/city.json")
	if FileAccess.get_sha256(city_path)!=previous.inputs.west_residential["city.json"] or registry.inputs.west_residential!=previous.inputs.west_residential:
		return false
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(city_path))
	_moved_records=[]
	for raw: Dictionary in city.buildings:
		if moved.has(raw.id):
			if raw.get("defer_render",false) or not raw.get("render_outline",true) or raw.get("source_tags",{}).get("roof:shape","flat")!="flat":
				return false
			_moved_records.append(raw)
	if _moved_records.size()!=34:
		return false
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var raw_source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(raw_path))
	for directory: String in ["r134-owned-blocks-both-a","r134-owned-native-a"]:
		var checked: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_base.path_join(directory+"/saved_audit.json")))
		if checked.get("fail",1)!=0 or checked.get("registry_sha256")!=REGISTRY_SHA or checked.get("unique_owners")!=80511:
			return false
	for level in range(1,6):
		var plan_path := _base.path_join("r121-west-plans-regular/%d.json"%level)
		if FileAccess.get_sha256(plan_path)!=source.block_transfers.west_residential.plan_hashes[str(level)]:
			return false
		var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
		for group: Dictionary in plan.groups:
			for identity: String in group.ids:
				if moved.has(identity):
					return false
	_source_hashes={}
	for data: Dictionary in [source,raw_source]:
		if data.get("fail",1)!=0 or data.registry_sha256!=REGISTRY_SHA or data.owner_ids.size()!=80511:
			return false
		var matching: Array = data.regions.filter(func(row: Dictionary) -> bool: return row.region=="west_extension")
		if matching.size()!=1:
			return false
		var index: Resource = ResourceLoader.load(matching[0].index,"",ResourceLoader.CACHE_MODE_IGNORE)
		if index==null or index.valid() or not index.valid(REGISTRY_SHA) or index.regional_id!="west_extension" \
				or index.source_count!=4095 or index.bounds!=Rect2(-7300,-2700,500,1000) or index.regional_nonowner_ids.size()!=23 \
				or index.source_hash!=FileAccess.get_sha256(root.path_join("west_extension/city.json"))+":"+registry.inputs.west_extension["ground.json"]:
			return false
		if data==source:
			_west=index
		else:
			_raw_west=index
		for row: Dictionary in matching[0].rows:
			_source_hashes[row.path]=row.sha256
	var game := Gameplay.read_source()
	var box: Array = source.block_transfers.west_extension.gameplay_protection.bounds
	var guard := Gameplay.inspect_bounds(Rect2(box[0],box[1],box[2],box[3]),game.get("entries",[]))
	if game.is_empty() or game.collision_sha256!=_original.collision_sha256 or guard.is_empty() or not guard.standalone_merge_allowed:
		return false
	var fixed_meshes: Array[ArrayMesh] = []
	for entry: Dictionary in _west.cells:
		var fixed: Resource = ResourceLoader.load(entry.fixed,"",ResourceLoader.CACHE_MODE_IGNORE)
		if fixed==null or not fixed.valid() or fixed.geometry_bytes!=entry.fixed_bytes or fixed.triangles!=entry.fixed_triangles:
			return false
		fixed_meshes.append(Repack.repack(Palette.recolor(fixed.meshes[0])))
	_fixed=Repack.repack(Spatial.Join.join(fixed_meshes))
	_proof={"source_catalog":original_path,"source_catalog_sha256":SOURCE_SHA,"registry_sha256":REGISTRY_SHA,"old_registry_sha256":FileAccess.get_sha256(old_path),
		"source_manifest_sha256":BLOCK_SHA,"raw_manifest_sha256":RAW_SHA,"moved_ids":moved.keys(),"gameplay_protection":guard,"rows":[],"fail":0}
	return true


func run() -> int:
	var root := OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_SOURCE")
	_out=OS.get_environment("AGL_TOKYO_REGIONAL_NATIVE_OUT")
	if not Components.Builder.valid_sample_output(root,_out) or not _prepare(root):
		return 1
	_catalog=_original.duplicate(true)
	var file := FileAccess.open(_base.path_join("r129-native-d/components/manifest.bin"),FileAccess.READ)
	_components=file.get_var(false)
	file.close()
	DirAccess.make_dir_recursive_absolute(_out.path_join("components"))
	DirAccess.make_dir_recursive_absolute(_out.path_join("boundary"))
	for configuration: String in Catalog.CONFIGURATIONS:
		var entry: Dictionary = _original.configurations[configuration][11]
		var previous := _load(entry)
		var removed := Boundary.target_meshes(_moved_records,configuration)
		var west := _west_meshes(configuration)
		if previous==null or west.size()!=3:
			return 1
		var meshes: Array[ArrayMesh] = []
		for kind in 3:
			var remaining: ArrayMesh = previous.meshes[kind]
			if kind<2:
				var delta := Boundary.Diff.subtract(remaining,removed[kind])
				if delta.is_empty() or not Boundary.Diff.conserved(remaining,delta.mesh,removed[kind]):
					push_error("[West extension] exact boundary mismatch "+configuration+" layer="+str(kind))
					return 1
				remaining=delta.mesh
			var joined: Array[ArrayMesh] = [remaining,west[kind]]
			var mesh := Repack.repack(Spatial.Join.join(joined))
			if not Spatial.Join.conserved(mesh,joined):
				return 1
			meshes.append(mesh)
		var removal := Components._save(removed,SOURCE_SHA+REGISTRY_SHA+configuration,_out.path_join("boundary/"+configuration+".res"))
		if removal.is_empty():
			return 1
		var context := {"out":_out.path_join(configuration),"configuration":configuration,"level":int(configuration.substr(3,1)),"parent_id":11,
			"collision_sha256":_original.collision_sha256,"owners_sha256":_original.owners_sha256,"game_sources":previous.game_sources,"audit":false,
			"source_hash":(previous.source_hash+BLOCK_SHA+REGISTRY_SHA+configuration).sha256_text()}
		DirAccess.make_dir_recursive_absolute(context.out)
		var changed := _replace(entry,meshes,context)
		if changed.is_empty():
			return 1
		_catalog.configurations[configuration][11]=changed
		_proof.rows.append({"configuration":configuration,"before":Array(entry.triangles),"after":Array(changed.triangles),"removed":removal,"bytes":changed.bytes})
		print("[West extension] ",configuration," parent=11 before=",entry.triangles," after=",changed.triangles)
	file=FileAccess.open(_out.path_join("boundary_proof.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(_proof))
	file.close()
	_catalog.regional_extension={"region":"west_corridor","bounds":Rect2(-7300,-2700,1000,1000),"source_count":80511,
		"registry_sha256":REGISTRY_SHA,"source_manifest_sha256":BLOCK_SHA,"boundary_manifest_sha256":FileAccess.get_sha256(_out.path_join("boundary_proof.json"))}
	return _finish_extension()


func _finish_extension() -> int:
	for configuration: String in Catalog.CONFIGURATIONS:
		for parent in 16:
			if parent!=11 and _catalog.configurations[configuration][parent]!=_original.configurations[configuration][parent]:
				return 1
	var destination := _out.path_join("catalog.res")
	if not _catalog.valid() or ResourceSaver.save(_catalog,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or not saved.valid() or saved.configurations!=_catalog.configurations or saved.regional_extension!=_catalog.regional_extension:
		return 1
	var digest := FileAccess.get_sha256(destination)
	for configuration: String in Catalog.CONFIGURATIONS:
		var file := FileAccess.open(_base.path_join("r129-native-d/coverage-"+configuration+".bin"),FileAccess.READ)
		var old: Dictionary=file.get_var(false)
		file.close()
		if old.catalog_sha256!=SOURCE_SHA or not old.verified or old.sources.size()!=48:
			return 1
		var coverage := Blocks.rewrite_coverage(old,_changes,digest)
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
	var file := FileAccess.open(_out.path_join("components/manifest.bin"),FileAccess.WRITE)
	file.store_var(_components)
	file.close()
	if Manifest.read(_out.path_join("components/manifest.bin"),_catalog,digest).is_empty():
		return 1
	file=FileAccess.open(_out.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"catalog_sha256":digest,"logical":_catalog.descriptors.size(),"physical":physical.size(),"changed_pages":_changes.size(),
		"extension":_catalog.regional_extension,"source_catalog_sha256":SOURCE_SHA,"production_enabled":false,"runtime_verified":false}))
	file.close()
	print("[West extension] complete changed=",_changes.size()," logical=",_catalog.descriptors.size()," physical=",physical.size()," fail=0")
	return 0


func audit(directory: String) -> int:
	if not _prepare(directory.get_base_dir().path_join("r134-owned-source-a")) or FileAccess.file_exists(directory.path_join("saved_audit.json")):
		return 1
	var catalog: Resource = ResourceLoader.load(directory.path_join("catalog.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	var digest := FileAccess.get_sha256(directory.path_join("catalog.res"))
	if catalog==null or not catalog.valid() or catalog.regional_extension.region!="west_corridor" \
			or catalog.regional_extension.registry_sha256!=REGISTRY_SHA or catalog.regional_extension.source_manifest_sha256!=BLOCK_SHA \
			or catalog.regional_extension.boundary_manifest_sha256!=FileAccess.get_sha256(directory.path_join("boundary_proof.json")):
		return 1
	var data := Manifest.read(directory.path_join("components/manifest.bin"),catalog,digest)
	var proof: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("boundary_proof.json")))
	if data.is_empty() or proof.source_catalog_sha256!=SOURCE_SHA or proof.rows.size()!=11 or proof.moved_ids!=_proof.moved_ids:
		return 1
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
	for configuration: String in Catalog.CONFIGURATIONS:
		for parent in 16:
			if parent!=11 and catalog.configurations[configuration][parent]!=_original.configurations[configuration][parent]:
				return 1
		var old_entry: Dictionary = _original.configurations[configuration][11]
		var old: Resource = ResourceLoader.load(old_entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var current: Resource = ResourceLoader.load(catalog.configurations[configuration][11].path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var expected_removed := Boundary.target_meshes(_moved_records,configuration)
		var west := _west_meshes(configuration)
		var rows: Array = proof.rows.filter(func(row: Dictionary) -> bool: return row.configuration==configuration)
		if rows.size()!=1 or west.size()!=3 or old==null or current==null or current.game_sources!=old.game_sources \
				or FileAccess.get_sha256(rows[0].removed.path)!=rows[0].removed.sha256:
			return 1
		var removed: Resource = ResourceLoader.load(rows[0].removed.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if removed==null or not removed.valid() or removed.meshes.size()!=2:
			return 1
		for kind in 3:
			var reference: ArrayMesh = old.meshes[kind]
			if kind<2:
				if not Spatial.Join.conserved(removed.meshes[kind],[expected_removed[kind]]):
					return 1
				# 独立守恒：旧模型 + 新西 = 新模型 + 被转交的旧副本。
				var left: Array[ArrayMesh] = [reference,west[kind]]
				var right: Array[ArrayMesh] = [current.meshes[kind],removed.meshes[kind]]
				if not Spatial.Join.conserved(Spatial.Join.join(left),right):
					return 1
			elif not Spatial.Join.conserved(current.meshes[kind],[reference,west[kind]]):
				return 1
		var file := FileAccess.open(directory.path_join("coverage-"+configuration+".bin"),FileAccess.READ)
		var coverage: Dictionary=file.get_var(false)
		file.close()
		if coverage.catalog_sha256!=digest or not coverage.verified or coverage.sources.size()!=48 or coverage.pages.size()!=208 \
				or coverage.collision_sha256!=_original.collision_sha256 or coverage.owners_sha256!=_original.owners_sha256:
			return 1
		for path: String in coverage.pages:
			if coverage.pages[path].identity!=catalog.descriptors[path].canonical_identity or FileAccess.get_sha256(path)!=coverage.pages[path].sha256:
				return 1
	var file := FileAccess.open(directory.path_join("saved_audit.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"catalog_sha256":digest,"pages":catalog.descriptors.size(),"physical":physical.size(),"boundary_configurations":11,
		"moved_sources":34,"unchanged_roots_per_configuration":15,"coverage_configurations":11,"game_sources":48,"visual_acceptance":false}))
	file.close()
	print("[West extension audit] pages=",catalog.descriptors.size()," physical=",physical.size()," moved=34 configurations=11 fail=0")
	return 0
