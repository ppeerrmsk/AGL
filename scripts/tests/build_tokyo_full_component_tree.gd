extends RefCounted
## 完整原叶三层几何到277节点组件树。逻辑页只存身份，不另写重复几何归档。
const Components := preload("res://scripts/tests/build_tokyo_mesh_components.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Read := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Same := preload("res://scripts/tests/build_tokyo_shared_pages.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Page := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")
const Contract := preload("res://scripts/rendering/tokyo_full_grid_contract.gd")
const Manifest := preload("res://scripts/rendering/tokyo_component_manifest.gd")


static func emit(meshes: Array[ArrayMesh], node: Dictionary, context: Dictionary, report: Dictionary) -> Dictionary:
	if meshes.size()!=3 or not Contract.coordinates_valid(int(node.parent),int(node.cell),int(node.ancestor)):
		return {}
	var page := Page.new()
	page.schema_version=2
	page.configuration=context.configuration
	page.level=int(page.configuration.substr(3,1))
	page.parent_id=int(node.parent)
	page.cell_id=int(node.cell)
	page.ancestor_id=int(node.ancestor)
	page.source_hash=context.source_hash
	page.collision_sha256=context.collision_sha256
	page.owners_sha256=context.owners_sha256
	page.game_sources=context.game_sources
	var logical: String = context.output.path_join(node.key+".logical")
	var row := {"components":{},"mapping":[],"game_sources":page.game_sources,"triangles":0,"bytes":0}
	var boxes: Array = []
	var counts := PackedInt32Array()
	for kind in 3:
		var original: ArrayMesh=meshes[kind]
		if original==null or original.get_surface_count()>1:
			return {}
		var mesh := Read.repack(original)
		if Read.corner_digest(mesh)!=Read.corner_digest(original) or mesh.get_aabb()!=original.get_aabb():
			return {}
		# fixed几何只依赖完整固定源和节点身份，跨11配置物理共享；既有文件必须逐角一致。
		var directory: String = context.fixed_output if kind==2 else context.output
		var path := directory.path_join(node.key+"_layer_%d.res" % kind)
		var source: String = context.fixed_source if kind==2 else context.source_hash
		source += ":"+node.key+":"+str(kind)
		var component: Dictionary = {}
		if FileAccess.file_exists(path):
			if kind!=2:
				return {}
			var saved: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if saved==null or not saved.valid() or saved.meshes.size()!=1 or saved.source_hash!=source.sha256_text() \
					or not Same.same_mesh(mesh,saved.meshes[0]) or saved.geometry_bytes!=Read.decoded_bytes(mesh):
				return {}
			component={"path":path,"bytes":saved.geometry_bytes,"canonical_identity":saved.stream_identity(),"sha256":FileAccess.get_sha256(path)}
		else:
			component=Components._save([mesh],source,path)
		if component.is_empty():
			return {}
		page.meshes.append(mesh)
		page.geometry_bytes+=int(component.bytes)
		var faces:=Indexed.triangles(mesh)
		page.triangles+=faces
		boxes.append(mesh.get_aabb())
		counts.append(faces)
		row.components[path]=component
		row.mapping.append([path,0])
		report.physical[path]=component
	if not page.valid():
		return {}
	row.bytes=page.geometry_bytes
	row.triangles=page.triangles
	row["canonical_identity"]=page.stream_identity()
	var descriptor: Dictionary={"bytes":page.geometry_bytes,"canonical_identity":page.stream_identity()}
	if not Manifest.valid_row(row,descriptor,report.physical) or report.pages.has(logical):
		return {}
	report.pages[logical]=row
	report.descriptors[logical]=descriptor
	return {"path":logical,"parent_id":page.parent_id,"cell_id":page.cell_id,"ancestor_id":page.ancestor_id,
		"level":page.level,"bytes":page.geometry_bytes,"boxes":boxes,"triangles":counts,"children":[]}


static func build(leaves: Dictionary, nodes: Dictionary, context: Dictionary) -> Dictionary:
	# 调用者必须在完整R51/R52及保存后审计后提供三层叶。这里只证明分页守恒，不授予coverage。
	if leaves.size()!=256 or nodes.size()!=277 or DirAccess.dir_exists_absolute(context.output):
		return {}
	var parent:=int(context.parent)
	var expected_keys: Dictionary={}
	var depths: Array=[[],[],[],[]]
	for key: String in nodes:
		var node: Dictionary=nodes[key]
		var depth:=int(node.get("depth",-1))
		if node.get("key")!=key or node.get("parent")!=parent or depth<0 or depth>3 \
				or not Contract.coordinates_valid(parent,int(node.get("cell",-2)),int(node.get("ancestor",-2))):
			return {}
		var expected:=Contract.children(int(node.cell),parent)
		if not node.get("children") is Array or node.children.size()!=expected.size():
			return {}
		for n in expected.size():
			var child: Variant=nodes.get(node.children[n])
			if not child is Dictionary or child.get("cell")!=expected[n].x or child.get("ancestor")!=expected[n].y:
				return {}
		depths[depth].append(key)
		if depth==3:expected_keys[key]=true
	if depths[0].size()!=1 or depths[1].size()!=4 or depths[2].size()!=16 or depths[3].size()!=256 or expected_keys.size()!=leaves.size():
		return {}
	for key: String in leaves:
		if not expected_keys.has(key) or not leaves[key] is Array or leaves[key].size()!=3:
			return {}
	if DirAccess.make_dir_recursive_absolute(context.output)!=OK or DirAccess.make_dir_recursive_absolute(context.fixed_output)!=OK:
		return {}
	var report: Dictionary={"pages":{},"descriptors":{},"physical":{},"root":{},"canonical_ready":false,"installed":false}
	var ready: Dictionary=leaves.duplicate()
	var entries: Dictionary={}
	for depth in [3,2,1,0]:
		depths[depth].sort()
		for key: String in depths[depth]:
			var node: Dictionary=nodes[key]
			var meshes: Array[ArrayMesh]=[]
			if depth==3:
				meshes.assign(ready[key])
			else:
				for kind in 3:
					var pieces: Array[ArrayMesh]=[]
					for child_key: String in node.children:
						if not ready.has(child_key):return {}
						pieces.append(ready[child_key][kind])
					var joined:=Join.join(pieces)
					if joined==null or not Join.conserved(joined,pieces):return {}
					meshes.append(joined)
			var entry:=emit(meshes,node,context,report)
			if entry.is_empty():return {}
			for child_key: String in node.children:
				entry.children.append(entries[child_key])
				ready.erase(child_key)
			entries[key]=entry
			ready[key]=meshes
			if depth==0:report.root=entry
	if report.pages.size()!=277 or report.descriptors.size()!=277 or ready.size()!=1:
		return {}
	var path: String=context.output.path_join("manifest.bin")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return {}
	file.store_var(report,false)
	file.close()
	file=FileAccess.open(path,FileAccess.READ)
	if file==null:return {}
	var saved: Variant=file.get_var(false)
	file.close()
	if saved!=report:return {}
	return report
