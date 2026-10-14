extends RefCounted
## 依据已有叶路由拆分烘焙后的原生层；固定层/游戏补面另行接合，不伪造规范页。
const Split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
const Read := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Components := preload("res://scripts/tests/build_tokyo_mesh_components.gd")
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")


static func conserved(source: ArrayMesh, pieces: Array[ArrayMesh], owners: PackedInt32Array) -> bool:
	if pieces.is_empty():
		return false
	if source.get_surface_count()==0:
		return owners.is_empty() and pieces.all(func(m: ArrayMesh) -> bool: return m.get_surface_count()==0)
	var before := Read._read(source)
	if owners.size()*3!=before.indices.size():
		return false
	var decoded: Array = []
	var cursors := PackedInt32Array()
	cursors.resize(pieces.size())
	for mesh: ArrayMesh in pieces:
		if mesh==null or mesh.get_surface_count()>1:
			return false
		decoded.append({} if mesh.get_surface_count()==0 else Read._read(mesh))
	for face in owners.size():
		var owner := owners[face]
		if owner<0 or owner>=pieces.size() or decoded[owner].is_empty():
			return false
		var after: Dictionary = decoded[owner]
		if (int(before.surface.format)&~Mesh.ARRAY_FORMAT_INDEX)!=(int(after.surface.format)&~Mesh.ARRAY_FORMAT_INDEX) \
				or before.surface.get("material")!=after.surface.get("material") or cursors[owner]+3>after.indices.size():
			return false
		for corner in 3:
			if Read._corner(before,before.indices[face*3+corner])!=Read._corner(after,after.indices[cursors[owner]+corner]):
				return false
		cursors[owner]+=3
	for n in pieces.size():
		if cursors[n]!=(0 if decoded[n].is_empty() else decoded[n].indices.size()):
			return false
	return true


static func run(input: String, digest: String, output: String) -> int:
	if not Root.binding_valid({"path":input,"sha256":digest}) or not output.is_absolute_path() \
			or output.get_base_dir()!=input.get_base_dir() or DirAccess.dir_exists_absolute(output):
		return 1
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(input))
	if not config is Dictionary or not config.get("partial",false) or config.get("layers",[]).size()!=2 or config.get("leaves",[]).size()!=256:
		return 1
	for key: String in ["root_manifest","plan","bundle","audit"]:
		if not Root.binding_valid(config.get(key)):
			return 1
	var audit: Variant = JSON.parse_string(FileAccess.get_file_as_string(config.audit.path))
	var root: Variant = JSON.parse_string(FileAccess.get_file_as_string(config.root_manifest.path))
	if not audit is Dictionary or not audit.get("passed",false) or audit.get("bundle_sha256")!=config.bundle.sha256 \
			or audit.get("plan_sha256")!=config.plan.sha256 or not root is Dictionary or root.get("sources",[]).size()!=256:
		return 1
	for leaf in 256:
		if config.leaves[leaf]!={"tile":root.sources[leaf].tile,"cell":root.sources[leaf].cell}:
			return 1
	var bundle: Resource = ResourceLoader.load(config.bundle.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if bundle==null or bundle.plan_sha256!=config.plan.sha256 or bundle.meshes.size()!=2 or bundle.descriptors.size()!=2:
		return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		return 1
	var rows: Array = []
	var kinds: Dictionary = {}
	for route: Dictionary in config.layers:
		var kind := int(route.get("kind",-1))
		if kind<0 or kind>1 or float(kind)!=float(route.kind) or kinds.has(kind):
			print("[Native leaves] invalid layer identity ",route.get("kind"))
			return 1
		kinds[kind]=true
		if not Root.binding_valid({"path":route.path,"sha256":route.sha256}):
			print("[Native leaves] route digest failed")
			return 1
		var selected := -1
		for n in bundle.descriptors.size():
			if bundle.descriptors[n].id==route.mesh_id and bundle.descriptors[n].kind==route.kind:
				if selected>=0:
					return 1
				selected=n
		if selected<0:
			print("[Native leaves] bundle layer absent ",kind," mesh=",route.mesh_id)
			return 1
		var raw := FileAccess.get_file_as_bytes(route.path)
		var owners := PackedInt32Array()
		owners.resize(raw.size())
		for n in raw.size():
			owners[n]=raw[n]
		if owners.size()!=int(route.baked):
			print("[Native leaves] route length mismatch")
			return 1
		var source: ArrayMesh = bundle.meshes[selected]
		var pieces := Split.partition(source,owners,256)
		if pieces.size()!=256 or not conserved(source,pieces,owners):
			print("[Native leaves] packed partition failed layer=",kind," pieces=",pieces.size()," routes=",owners.size()," source_faces=",Root.Indexed.triangles(source))
			return 1
		for leaf in 256:
			var path := output.path_join("leaf_%03d_layer_%d.res" % [leaf,int(route.kind)])
			if FileAccess.file_exists(path):
				return 1
			var descriptor := Components._save([pieces[leaf]],digest+":"+str(leaf)+":"+str(route.kind),path)
			if descriptor.is_empty():
				return 1
			rows.append({"leaf":leaf,"tile":config.leaves[leaf].tile,"cell":config.leaves[leaf].cell,"kind":route.kind,
				"component":descriptor,"faces":Root.Indexed.triangles(pieces[leaf])})
		print("[Native leaves] layer=",route.kind," original-leaves=256 faces=",owners.size()," conserved=true saved_reload=true")
	var report := {"input_sha256":digest,"rows":rows,"fail":0,"partial":true,"canonical_ready":false,"installed":false,
		"fixed_included":false,"gameplay_additions_included":false}
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify(report,"",true,true))
	file.close()
	return 0
