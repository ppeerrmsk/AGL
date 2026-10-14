extends "res://scripts/tests/build_tokyo_block_catalog.gd"
## 四片目录内精确替换北岸远档；检查候选，不改变默认或放宽像素门。
const Far := preload("res://scripts/tests/build_tokyo_far_clusters.gd")
const Diff := preload("res://scripts/experiments/tokyo_packed_mesh_difference.gd")
const Repack := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const SOURCE_SHA := "1346748dcf5a4f4471b16791ff1249748569dff252246951f4a393382b924e4a"
const OLD_SHA := "211edc566564d87923e6717096e59eb89878e6427145a590187aec9b27022070"
const NEW_SHA := "ed07ec604717a2461ff5c073ce1de4de2cf7295c0cf8b4469a52b78aa9a36b37"
const BOUNDARY_SHA := "31c8673f95ccd199a2c08a9bb818972811dc8e3b0d868648b198f4fb1c51f5aa"


static func recipe(near: bool = false) -> Dictionary:
	if near:
		return {"directory":"r139-native-b","source_sha": "3f3842acb66ddb133cc1738dbaf775fb09f4ddbb7d2df13f8f7b0677f2aaca92",
			"old":"r111-district24wide-a-native","old_sha":"bdecc4138cc658e60dae295543af95ed080a7446ad0114003a2831fa6ddb9c3c",
			"new":"r142-district24street45-native-b","new_sha":"f94da98b499bba5ccf5a524a8d36f8056c522a9bb0a109626a64d55a3f4e79a6",
			"level":5,"configuration":"lod5_full","profile":"district24street45","scale":5.0,"limit":64,"removed":743,"saved":139694}
	return {"directory":"r135-native-a","source_sha":SOURCE_SHA,"old":"r102-far6-a-native","old_sha":OLD_SHA,
		"new":"r138-street6-native-a","new_sha":NEW_SHA,"level":2,"configuration":"lod2_full","profile":"street6","scale":0.3888,"limit":96,"removed":115,"saved":19472}


static func selected(configuration: String, parent: int, near: bool = false) -> bool:
	return configuration==("lod5_full" if near else "lod2_full") and parent>=8 and parent<=15


static func valid_rows(rows: Variant, near: bool = false) -> bool:
	var rules := recipe(near)
	if not rows is Array or rows.size()!=8:
		return false
	var seen: Dictionary = {}
	for row: Variant in rows:
		if not row is Dictionary or row.get("block_profile")!=rules.profile or row.get("level")!=rules.level or row.get("max_scale")!=rules.scale:
			return false
		var parent: Variant = row.get("cell_id")
		if typeof(parent) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(parent)) or float(parent)!=int(parent) or not selected(rules.configuration,int(parent),near) or seen.has(int(parent)):
			return false
		seen[int(parent)]=true
	return true


static func replace_low(current: ArrayMesh, previous: ArrayMesh, candidate: ArrayMesh) -> Dictionary:
	var remainder := Diff.subtract(current,previous)
	if remainder.is_empty() or not Diff.conserved(current,remainder.mesh,previous):
		return {}
	var changed := Repack.repack(Join.join([remainder.mesh,candidate]))
	if not Join.conserved(changed,[remainder.mesh,candidate]):
		return {}
	return {"mesh":changed,"remainder":remainder.mesh}


static func without_transferred(mesh: ArrayMesh, removed: ArrayMesh) -> Dictionary:
	var delta := Diff.subtract(mesh,removed)
	return delta if not delta.is_empty() and Diff.conserved(mesh,delta.mesh,removed) else {}


static func disjoint_transferred(groups: Array, moved: Dictionary) -> bool:
	for group: Dictionary in groups:
		for identity: String in group.ids:
			if moved.has(identity):
				return false
	return true


static func inputs(base: String, near: bool = false) -> Dictionary:
	var rules := recipe(near)
	var source_path := base.path_join(rules.directory+"/catalog.res")
	var old_path := base.path_join(rules.old+"/manifest.json")
	var new_path := base.path_join(rules.new+"/manifest.json")
	var boundary_path := base.path_join("r126-boundary-b/manifest.json")
	if FileAccess.get_sha256(source_path)!=rules.source_sha or FileAccess.get_sha256(old_path)!=rules.old_sha or FileAccess.get_sha256(new_path)!=rules.new_sha or FileAccess.get_sha256(boundary_path)!=BOUNDARY_SHA:
		return {}
	var boundary: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(boundary_path))
	var transferred: Array = boundary.rows.filter(func(row: Dictionary) -> bool: return row.configuration==rules.configuration and row.parent==11)
	if boundary.get("fail",1)!=0 or boundary.moved_sources.size()!=34 or transferred.size()!=1 or transferred[0].removed_faces[0]!=rules.removed:
		return {}
	var removal: Dictionary = transferred[0].removed
	if FileAccess.get_sha256(removal.path)!=removal.sha256:
		return {}
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_path))
	var changed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(new_path))
	if old.get("fail",1)!=0 or changed.get("fail",1)!=0 or not valid_rows(changed.get("rows"),near):
		return {}
	var rows: Dictionary = {}
	for row: Dictionary in old.rows:
		if row.level==rules.level:
			rows[int(row.cell_id)]={"old":row}
	if rows.size()!=8:
		return {}
	for row: Dictionary in changed.rows:
		var parent := int(row.cell_id)
		if not rows.has(parent) or rows[parent].has("new"):
			return {}
		rows[parent]["new"]=row
		for item: Dictionary in [row,rows[parent].old]:
			if FileAccess.get_sha256(item.path)!=item.sha256 or FileAccess.get_sha256(item.source)!=item.source_sha256 or FileAccess.get_sha256(item.plan)!=item.plan_sha256:
				return {}
		var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(row.plan))
		if Far.group_limit(contract)!=rules.limit or contract.profile!=rules.profile or contract.max_scale!=rules.scale or contract.source_sha256!=Far.CITY_HASH:
			return {}
		var previous: Dictionary = rows[parent].old
		if row.source!=previous.source or row.source_sha256!=previous.source_sha256 or row.max_scale!=previous.max_scale:
			return {}
		if not disjoint_transferred(row.groups,boundary.moved_sources) or not disjoint_transferred(previous.groups,boundary.moved_sources):
			return {}
		rows[parent]["boundary"]=removal.path if parent==11 else ""
	return rows


func run(base: String, output: String) -> int:
	var near := OS.get_environment("AGL_TOKYO_STREET_NEAR_CATALOG")=="1"
	var rules := recipe(near)
	var source_dir := base.path_join(rules.directory)
	if not Far.Builder.valid_sample_output(source_dir,output):
		return 1
	var pairs := inputs(base,near)
	if pairs.is_empty():
		print("[Street catalog rejected] input identity")
		return 1
	var original: Resource = ResourceLoader.load(source_dir.path_join("catalog.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	if original==null or not original.valid() or Manifest.read(source_dir.path_join("components/manifest.bin"),original,rules.source_sha).is_empty():
		return 1
	_catalog=original.duplicate(true)
	_out=output
	var input := FileAccess.open(source_dir.path_join("components/manifest.bin"),FileAccess.READ)
	_components=input.get_var(false)
	input.close()
	DirAccess.make_dir_recursive_absolute(output.path_join("components"))
	var rows: Array = []
	for parent: int in pairs:
		var pair: Dictionary = pairs[parent]
		var entry: Dictionary = original.configurations[rules.configuration][parent]
		var current := _load(entry)
		var previous: Resource = ResourceLoader.load(pair.old.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var candidate: Resource = ResourceLoader.load(pair.new.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if current==null or previous==null or candidate==null or not previous.valid() or not candidate.valid() \
				or previous.cell_id!=parent or candidate.cell_id!=parent or previous.level!=rules.level or candidate.level!=rules.level \
				or previous.source_ids!=candidate.source_ids or previous.height_hash!=candidate.height_hash or not Shared.same_mesh(previous.meshes[1],candidate.meshes[1]):
			return 1
		var transferred := ArrayMesh.new()
		if not str(pair.boundary).is_empty():
			var removal: Resource = ResourceLoader.load(pair.boundary,"",ResourceLoader.CACHE_MODE_IGNORE)
			if removal==null or not removal.valid():
				return 1
			transferred=removal.meshes[0]
		var old_owned := without_transferred(previous.meshes[0],transferred)
		var new_owned := without_transferred(candidate.meshes[0],transferred)
		if old_owned.is_empty() or new_owned.is_empty():
			print("[Street catalog rejected] transferred source mismatch parent=",parent)
			return 1
		var replacement := replace_low(current.meshes[0],old_owned.mesh,new_owned.mesh)
		if replacement.is_empty():
			print("[Street catalog rejected] exact low source subtraction parent=",parent)
			return 1
		var saved_faces := Far.Indexed.triangles(current.meshes[0])-Far.Indexed.triangles(replacement.mesh)
		if saved_faces!=int(pair.old.after)-int(pair.new.after) or saved_faces<=0:
			return 1
		var context := {"out":output.path_join(rules.configuration),"configuration":rules.configuration,"level":rules.level,"parent_id":parent,
			"collision_sha256":original.collision_sha256,"owners_sha256":original.owners_sha256,"game_sources":current.game_sources,
			"source_hash":(current.source_hash+rules.new_sha+"r139-street-low-only").sha256_text(),"audit":false}
		DirAccess.make_dir_recursive_absolute(context.out)
		var changed := _replace(entry,replacement.mesh,context)
		if changed.is_empty():
			return 1
		_catalog.configurations[rules.configuration][parent]=changed
		rows.append({"parent":parent,"before":Array(entry.triangles),"after":Array(changed.triangles),"saved":saved_faces,
			"remaining_faces":Far.Indexed.triangles(replacement.remainder),"old_north":pair.old.path,"new_north":pair.new.path})
		print("[Street catalog] parent=",parent," saved=",saved_faces," other_region_faces=",Far.Indexed.triangles(replacement.remainder))
	return _finish(original,base,rows,near)


func _finish(original: Resource, base: String, rows: Array, near: bool = false) -> int:
	var rules := recipe(near)
	for configuration: String in Catalog.CONFIGURATIONS:
		for parent in 16:
			if not selected(configuration,parent,near) and _catalog.configurations[configuration][parent]!=original.configurations[configuration][parent]:
				return 1
	var destination := _out.path_join("catalog.res")
	if not _catalog.valid() or _catalog.regional_extension!=original.regional_extension or ResourceSaver.save(_catalog,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or not saved.valid() or saved.configurations!=_catalog.configurations or saved.descriptors!=_catalog.descriptors:
		return 1
	var digest := FileAccess.get_sha256(destination)
	for configuration: String in Catalog.CONFIGURATIONS:
		var input := FileAccess.open(base.path_join(rules.directory+"/coverage-"+configuration+".bin"),FileAccess.READ)
		var previous: Dictionary = input.get_var(false)
		input.close()
		if previous.catalog_sha256!=rules.source_sha or not previous.verified or previous.sources.size()!=48 or previous.pages.size()!=208:
			return 1
		var coverage := rewrite_coverage(previous,_changes,digest)
		if coverage.is_empty():
			return 1
		var file := FileAccess.open(_out.path_join("coverage-"+configuration+".bin"),FileAccess.WRITE)
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
	file.store_string(JSON.stringify({"fail":0,"rows":rows,"changes":_changes,"source_catalog_sha256":rules.source_sha,"old_manifest_sha256":rules.old_sha,"new_manifest_sha256":rules.new_sha,
		"catalog_sha256":digest,"boundary_manifest_sha256":BOUNDARY_SHA,"changed_pages":_changes.size(),"logical":_catalog.descriptors.size(),"physical":physical.size(),"production_enabled":false,"visual_acceptance":false}))
	file.close()
	print("[Street catalog] complete changed=",_changes.size()," fail=0")
	return 0


static func audit(directory: String, near: bool = false) -> int:
	var base := directory.get_base_dir()
	var rules := recipe(near)
	var pairs := inputs(base,near)
	if pairs.is_empty():
		return 1
	var before: Resource = ResourceLoader.load(base.path_join(rules.directory+"/catalog.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	var after: Resource = ResourceLoader.load(directory.path_join("catalog.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	if before==null or after==null or not before.valid() or not after.valid() or before.regional_extension!=after.regional_extension \
			or before.collision_sha256!=after.collision_sha256 or before.owners_sha256!=after.owners_sha256:
		return 1
	var digest := FileAccess.get_sha256(directory.path_join("catalog.res"))
	var data := Manifest.read(directory.path_join("components/manifest.bin"),after,digest)
	if data.is_empty():
		return 1
	var counts := {"pages":0,"saved":0,"remaining":0,"changes":{}}
	for configuration: String in Catalog.CONFIGURATIONS:
		for parent in 16:
			var old: Dictionary = before.configurations[configuration][parent]
			var current: Dictionary = after.configurations[configuration][parent]
			if not selected(configuration,parent,near):
				if old!=current:
					return 1
				continue
			var source: Resource = ResourceLoader.load(old.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var old_north: Resource = ResourceLoader.load(pairs[parent].old.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var new_north: Resource = ResourceLoader.load(pairs[parent].new.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if source==null or old_north==null or new_north==null or not source.valid() or not old_north.valid() or not new_north.valid():
				return 1
			var transferred := ArrayMesh.new()
			if not str(pairs[parent].boundary).is_empty():
				var removal: Resource = ResourceLoader.load(pairs[parent].boundary,"",ResourceLoader.CACHE_MODE_IGNORE)
				if removal==null or not removal.valid():
					return 1
				transferred=removal.meshes[0]
			var old_owned := Diff.subtract(old_north.meshes[0],transferred)
			var new_owned := Diff.subtract(new_north.meshes[0],transferred)
			if old_owned.is_empty() or new_owned.is_empty() or not Diff.conserved(old_north.meshes[0],old_owned.mesh,transferred) or not Diff.conserved(new_north.meshes[0],new_owned.mesh,transferred):
				return 1
			var remaining := Diff.subtract(source.meshes[0],old_owned.mesh)
			if remaining.is_empty() or not Diff.conserved(source.meshes[0],remaining.mesh,old_owned.mesh):
				return 1
			counts.remaining+=Far.Indexed.triangles(remaining.mesh)
			var expected := Join.join([remaining.mesh,new_owned.mesh])
			if not _audit_entry(old,current,expected,data,counts):
				return 1
			counts.saved+=int(old.triangles[0])-int(current.triangles[0])
		var input := FileAccess.open(base.path_join(rules.directory+"/coverage-"+configuration+".bin"),FileAccess.READ)
		var old_coverage: Dictionary = input.get_var(false)
		input.close()
		input=FileAccess.open(directory.path_join("coverage-"+configuration+".bin"),FileAccess.READ)
		var coverage: Dictionary = input.get_var(false)
		input.close()
		if coverage!=rewrite_coverage(old_coverage,counts.changes,digest):
			return 1
		if coverage.catalog_sha256!=digest or not coverage.verified or coverage.sources.size()!=48 or coverage.pages.size()!=old_coverage.pages.size() \
				or coverage.collision_sha256!=before.collision_sha256 or coverage.owners_sha256!=before.owners_sha256:
			return 1
		for path: String in coverage.pages:
			if not after.descriptors.has(path) or coverage.pages[path].sha256!=FileAccess.get_sha256(path) or coverage.pages[path].identity!=after.descriptors[path].canonical_identity:
				return 1
	if counts.pages!=168 or counts.saved!=rules.saved or counts.remaining<=0:
		return 1
	# 全部未改描述符仍必须来自旧目录；变化页已逐组件独立重载。
	for path: String in after.descriptors:
		if before.descriptors.has(path) and after.descriptors[path]!=before.descriptors[path]:
			return 1
	var output := directory.path_join("saved_audit.json")
	if FileAccess.file_exists(output):
		return 1
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"catalog_sha256":digest,"changed_pages":counts.pages,"saved_faces":counts.saved,"remaining_region_faces":counts.remaining,
		"high_fixed_unchanged":true,"other_configurations_unchanged":true,"game_sources":48,"coverage_configurations":11,"visual_acceptance":false}))
	file.close()
	print("[Street saved audit] pages=",counts.pages," saved=",counts.saved," retained=",counts.remaining," fail=0")
	return 0


static func _audit_entry(old: Dictionary, current: Dictionary, expected: ArrayMesh, data: Dictionary, counts: Dictionary) -> bool:
	if old.cell_id!=current.cell_id or old.ancestor_id!=current.ancestor_id or old.key!=current.key or old.get("cuts",[])!=current.get("cuts",[]) \
			or old.get("children",[]).size()!=current.get("children",[]).size() or FileAccess.get_sha256(old.path)!=old.sha256 or FileAccess.get_sha256(current.path)!=current.sha256:
		return false
	var a: Resource = ResourceLoader.load(old.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var b: Resource = ResourceLoader.load(current.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if a==null or b==null or not a.valid() or not b.valid() or a.game_sources!=b.game_sources or not Join.conserved(b.meshes[0],[expected]):
		return false
	for kind in [1,2]:
		if not Shared.same_mesh(a.meshes[kind],b.meshes[kind]):
			return false
	var row: Dictionary = data.pages[current.path]
	if b.stream_identity()!=row.canonical_identity or b.geometry_bytes!=row.bytes or b.triangles!=row.triangles or b.game_sources!=row.game_sources:
		return false
	for kind in 3:
		var path: String = row.mapping[kind][0]
		var part: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if part==null or not part.valid() or part.stream_identity()!=row.components[path].canonical_identity or not Join.conserved(b.meshes[kind],[part.meshes[row.mapping[kind][1]]]):
			return false
	counts.pages+=1
	counts.changes[old.path]={"path":current.path,"sha256":current.sha256,"old_identity":a.stream_identity(),"identity":b.stream_identity()}
	if not old.get("children",[]).is_empty():
		var pieces := Split.split(expected,old.cuts)
		if not Join.conserved(expected,pieces):
			return false
		for n in 4:
			if not _audit_entry(old.children[n],current.children[n],pieces[n],data,counts):
				return false
	return true
