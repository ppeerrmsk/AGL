extends "res://scripts/tests/build_tokyo_block_catalog.gd"
## 远档仅省略亚像素步道；全部道路/水绿地角点以及近档原形不改。
const Diff := preload("res://scripts/experiments/tokyo_packed_mesh_difference.gd")
const Repack := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const SOURCE_SHA := "8ff1181df0020df6f595f4174b470cc8a688a91d56771a7312f97fcf1243ba9b"
const SELECTED := ["lod0_full","lod1_full","lod2_full"]


func run(root: String, output: String) -> int:
	if not Components.Builder.valid_sample_output(root.path_join("r129-native-d"),output):
		return 1
	var source_path := root.path_join("r129-native-d/catalog.res")
	if FileAccess.get_sha256(source_path)!=SOURCE_SHA:
		return 1
	var original: Resource = load(source_path)
	if original==null or not original.valid():
		return 1
	var component_path := root.path_join("r129-native-d/components/manifest.bin")
	if Manifest.read(component_path,original,SOURCE_SHA).is_empty():
		return 1
	var file := FileAccess.open(component_path,FileAccess.READ)
	_components=file.get_var(false)
	file.close()
	_catalog=original.duplicate(true)
	_out=output
	DirAccess.make_dir_recursive_absolute(output.path_join("components"))
	var rows: Array = []
	var parts: Dictionary = {}
	for configuration: String in SELECTED:
		for parent in 16:
			var entry: Dictionary = original.configurations[configuration][parent]
			var source := _load(entry)
			if source==null:
				return 1
			if not parts.has(parent):
				parts[parent]=partition(source.meshes[2])
			var split: Dictionary = parts[parent]
			if split.is_empty() or not Diff.conserved(source.meshes[2],split.kept,split.removed) or Indexed.triangles(split.removed)<=0:
				return 1
			var context := {"out":output.path_join(configuration),"configuration":configuration,"level":int(configuration.substr(3,1)),"parent_id":parent,
				"collision_sha256":original.collision_sha256,"owners_sha256":original.owners_sha256,"game_sources":source.game_sources,
				"source_hash":(source.source_hash+"r130-path-detail-0.31104px").sha256_text(),"audit":false}
			DirAccess.make_dir_recursive_absolute(context.out)
			var changed := _replace_layer(entry,split.kept,context,2)
			if changed.is_empty():
				return 1
			_catalog.configurations[configuration][parent]=changed
			rows.append({"configuration":configuration,"parent":parent,"before":Array(entry.triangles),"after":Array(changed.triangles),
				"removed":Indexed.triangles(split.removed),"before_bytes":entry.bytes,"after_bytes":changed.bytes})
			print("[Path LOD] ",configuration," parent=",parent," fixed=",entry.triangles[2]," -> ",changed.triangles[2])
	return _finish_catalog(original,root,rows)


static func partition(mesh: ArrayMesh) -> Dictionary:
	if not Diff.supported(mesh):
		return {}
	if mesh.get_surface_count()==0:
		return {"kept":mesh,"removed":ArrayMesh.new()}
	var data := Repack._read(mesh)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colors.size()!=vertices.size():
		return {}
	var selected := PackedInt32Array()
	var kept := PackedInt32Array()
	var height: float = PackedFloat32Array([0.22])[0]
	var color := Color("9c9d8d")
	for first in range(0,data.indices.size(),3):
		var path := true
		for offset in 3:
			var id: int = data.indices[first+offset]
			path=path and vertices[id].y==height and colors[id]==color
		var target: PackedInt32Array = selected if path else kept
		# PackedArray是值类型，切勿把append到局部副本误当已更改原桶。
		target.append_array(data.indices.slice(first,first+3))
		if path:
			selected=target
		else:
			kept=target
	var a := subset(mesh,kept)
	var b := subset(mesh,selected)
	return {"kept":a,"removed":b} if Diff.conserved(mesh,a,b) else {}


static func subset(mesh: ArrayMesh, indices: PackedInt32Array) -> ArrayMesh:
	if indices.is_empty():
		return ArrayMesh.new()
	var surface: Dictionary = mesh.get("_surfaces")[0].duplicate()
	surface.format=int(surface.format)|Mesh.ARRAY_FORMAT_INDEX
	surface.index_count=indices.size()
	var stride := RenderingServer.mesh_surface_get_format_index_stride(surface.format,surface.vertex_count)
	var packed := PackedByteArray()
	packed.resize(indices.size()*stride)
	for n in indices.size():
		if stride==2:
			packed.encode_u16(n*2,indices[n])
		else:
			packed.encode_u32(n*4,indices[n])
	surface.index_data=packed
	var result := ArrayMesh.new()
	result.set("_surfaces",[surface])
	return Repack.repack(result)


func _finish_catalog(original: Resource, root: String, rows: Array) -> int:
	for configuration: String in Catalog.CONFIGURATIONS:
		if configuration not in SELECTED and _catalog.configurations[configuration]!=original.configurations[configuration]:
			return 1
	var destination := _out.path_join("catalog.res")
	if not _catalog.valid() or ResourceSaver.save(_catalog,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or not saved.valid() or saved.descriptors!=_catalog.descriptors or saved.configurations!=_catalog.configurations:
		return 1
	var digest := FileAccess.get_sha256(destination)
	for configuration: String in Catalog.CONFIGURATIONS:
		var file := FileAccess.open(root.path_join("r129-native-d/coverage-"+configuration+".bin"),FileAccess.READ)
		var previous: Dictionary = file.get_var(false)
		file.close()
		if previous.catalog_sha256!=SOURCE_SHA or not previous.verified or previous.pages.size()!=208 or previous.sources.size()!=48:
			return 1
		var coverage := rewrite_coverage(previous,_changes,digest)
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
	var file := FileAccess.open(component_path,FileAccess.WRITE)
	file.store_var(_components)
	file.close()
	if Manifest.read(component_path,_catalog,digest).is_empty():
		return 1
	file=FileAccess.open(_out.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"source_catalog_sha256":SOURCE_SHA,"catalog_sha256":digest,"rows":rows,
		"changed_pages":_changes.size(),"logical":_catalog.descriptors.size(),"physical":physical.size(),"production_enabled":false}))
	file.close()
	print("[Path LOD] complete changed=",_changes.size()," fail=0")
	return 0


static func audit(directory: String) -> int:
	var source_path := directory.get_base_dir().path_join("r129-native-d/catalog.res")
	var destination := directory.path_join("catalog.res")
	if FileAccess.get_sha256(source_path)!=SOURCE_SHA:
		return 1
	var before: Resource = load(source_path)
	var after: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
	if before==null or after==null or not before.valid() or not after.valid() or before.regional_extension!=after.regional_extension:
		return 1
	var digest := FileAccess.get_sha256(destination)
	var data := Manifest.read(directory.path_join("components/manifest.bin"),after,digest)
	if data.is_empty():
		return 1
	var counts := {"pages":0,"removed":0}
	for configuration: String in Catalog.CONFIGURATIONS:
		if configuration in SELECTED:
			for parent in 16:
				if not _audit_entry(before.configurations[configuration][parent],after.configurations[configuration][parent],data,counts):
					return 1
		elif before.configurations[configuration]!=after.configurations[configuration]:
			return 1
		var file := FileAccess.open(directory.path_join("coverage-"+configuration+".bin"),FileAccess.READ)
		var coverage: Dictionary = file.get_var(false)
		file.close()
		if coverage.catalog_sha256!=digest or not coverage.verified or coverage.sources.size()!=48 or coverage.pages.size()!=208 \
				or coverage.collision_sha256!=before.collision_sha256 or coverage.owners_sha256!=before.owners_sha256:
			return 1
		for path: String in coverage.pages:
			if coverage.pages[path].sha256!=FileAccess.get_sha256(path) or coverage.pages[path].identity!=after.descriptors[path].canonical_identity:
				return 1
	if counts.pages!=624 or counts.removed!=32954*3:
		return 1
	var output := directory.path_join("saved_audit.json")
	if FileAccess.file_exists(output):
		return 1
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"catalog_sha256":digest,"changed_pages":counts.pages,"root_faces_removed":counts.removed,
		"coverage_configurations":11,"game_sources":48,"all_buildings_unchanged":true,"guarded_near_unchanged":true,"visual_acceptance":false}))
	file.close()
	print("[Path LOD saved audit] pages=",counts.pages," root_removed=",counts.removed," fail=0")
	return 0


static func _audit_entry(old: Dictionary, current: Dictionary, data: Dictionary, counts: Dictionary) -> bool:
	if old.cell_id!=current.cell_id or old.ancestor_id!=current.ancestor_id or old.key!=current.key \
			or old.get("cuts",[])!=current.get("cuts",[]) or old.get("children",[]).size()!=current.get("children",[]).size() \
			or FileAccess.get_sha256(old.path)!=old.sha256 or FileAccess.get_sha256(current.path)!=current.sha256:
		return false
	var a: Resource = ResourceLoader.load(old.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var b: Resource = ResourceLoader.load(current.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if a==null or b==null or not a.valid() or not b.valid() or a.game_sources!=b.game_sources:
		return false
	var parts := partition(a.meshes[2])
	if parts.is_empty() or not Join.conserved(b.meshes[2],[parts.kept]):
		return false
	for kind in [0,1]:
		if not Shared.same_mesh(a.meshes[kind],b.meshes[kind]):
			return false
	var row: Dictionary = data.pages[current.path]
	if b.stream_identity()!=row.canonical_identity or b.geometry_bytes!=row.bytes or b.triangles!=row.triangles or b.game_sources!=row.game_sources:
		return false
	for kind in 3:
		var path: String = row.mapping[kind][0]
		var part: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if part==null or not part.valid() or part.stream_identity()!=row.components[path].canonical_identity \
				or not Join.conserved(b.meshes[kind],[part.meshes[row.mapping[kind][1]]]):
			return false
	counts.pages+=1
	if int(old.cell_id)<0:
		counts.removed+=Indexed.triangles(parts.removed)
	for n in old.get("children",[]).size():
		if not _audit_entry(old.children[n],current.children[n],data,counts):
			return false
	return true
