extends RefCounted
## 新固定源单独构建四级组件树；不重烘焙建筑，不生成虚假的三层页或coverage。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Native := preload("res://scripts/tests/build_tokyo_full_native_leaves.gd")
const ComponentTree := preload("res://scripts/tests/build_tokyo_full_component_tree.gd")


static func route_valid(root: Dictionary, removed: PackedInt32Array, raw: PackedByteArray) -> bool:
	if root.get("sources",[]).size()!=256 or root.get("faces",[]).size()!=1: return false
	var previous: int=-1
	for face in removed:
		if face<=previous or face>=root.faces[0]: return false
		previous=face
	var old_cursor:=0
	var new_cursor:=0
	var removal_cursor:=0
	var identities: Dictionary={}
	for leaf in 256:
		var source: Dictionary=root.sources[leaf]
		var identity:=str(source.get("tile"))+":"+str(source.get("cell"))
		if identities.has(identity) or source.get("ranges",[]).size()!=1: return false
		identities[identity]=true
		var span: Dictionary=source.ranges[0]
		var amount:=int(span.get("triangles",-1))
		if span.get("kind")!=0 or amount<0 or amount!=span.triangles or span.get("first_triangle")!=old_cursor: return false
		for face in range(old_cursor,old_cursor+amount):
			if removal_cursor<removed.size() and face==removed[removal_cursor]:
				removal_cursor+=1
			else:
				if new_cursor>=raw.size() or raw[new_cursor]!=leaf: return false
				new_cursor+=1
		old_cursor+=amount
	return old_cursor==root.faces[0] and new_cursor==raw.size() and removal_cursor==removed.size()


static func checks() -> bool:
	if run("","","","")!=1: return false
	var sources: Array=[]
	for leaf in 256:
		sources.append({"tile":"fixture","cell":leaf,"ranges":[{"kind":0,"first_triangle":leaf*2,"triangles":2}]})
	var root: Dictionary={"sources":sources,"faces":[512]}
	var raw:=PackedByteArray()
	for face in 512:
		if face not in [1,255,511]: raw.append(face/2)
	var removed:=PackedInt32Array([1,255,511])
	if not route_valid(root,removed,raw): return false
	if route_valid(root,PackedInt32Array([255,1,511]),raw) or route_valid(root,PackedInt32Array([1,1,511]),raw): return false
	raw[0]=1
	return not route_valid(root,removed,raw) and not route_valid({},PackedInt32Array(),PackedByteArray())


static func run(input: String, digest: String, hierarchy_path: String, output: String) -> int:
	if not Root.binding_valid({"path":input,"sha256":digest}) or FileAccess.get_sha256(hierarchy_path)!=Root.Contract.HIERARCHY_SHA \
			or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if not config is Dictionary or config.get("leaves",[]).size()!=256: return 1
	for key: String in ["original_manifest","native_manifest","native_proof","component","route"]:
		if not Root.binding_valid(config.get(key)): return 1
	var root: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.original_manifest.path))
	var native: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.native_manifest.path))
	var proof: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.native_proof.path))
	var parent:=int(config.get("parent",-1))
	if parent<0 or parent>=16 or parent!=config.parent or root.get("parent_id")!=parent or native.get("parent")!=parent \
			or root.get("component")!=native.get("source") or native.get("component")!=config.component or proof.get("exit",-1)!=0 \
			or not native.get("native_full_attribute_match",false) or not native.get("retained_packed_channels_equal",false) \
			or not native.get("saved_indices_equal",false) or not Root.binding_valid(native.get("removed_ids")): return 1
	var removal_raw:=FileAccess.get_file_as_bytes(native.removed_ids.path)
	if removal_raw.size()!=int(native.removed)*4: return 1
	var removed:=PackedInt32Array()
	for n in removal_raw.size()/4: removed.append(removal_raw.decode_u32(n*4))
	var raw:=FileAccess.get_file_as_bytes(config.route.path)
	if raw.size()!=native.remaining_faces or not route_valid(root,removed,raw): return 1
	var owners:=PackedInt32Array()
	for value in raw: owners.append(value)
	var component: Resource=ResourceLoader.load(config.component.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if component==null or not component.valid() or component.meshes.size()!=1: return 1
	var pieces:=Native.Split.partition(component.meshes[0],owners,256)
	if pieces.size()!=256 or not Native.conserved(component.meshes[0],pieces,owners): return 1
	var hierarchy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(hierarchy_path))
	var nodes: Dictionary={}
	var leaf_keys: Dictionary={}
	var depths: Array=[[],[],[],[]]
	for key: String in hierarchy.nodes:
		var node: Dictionary=hierarchy.nodes[key]
		if node.parent!=parent: continue
		if node.key!=key or not Root.Contract.coordinates_valid(parent,int(node.cell),int(node.ancestor)): return 1
		nodes[key]=node
		depths[int(node.depth)].append(key)
		if node.depth==3: leaf_keys[str(node.tile)+":"+str(int(node.source_cell))]=key
	if nodes.size()!=277 or leaf_keys.size()!=256: return 1
	var ready: Dictionary={}
	for leaf in 256:
		var source: Dictionary=root.sources[leaf]
		var key: String=leaf_keys.get(str(source.tile)+":"+str(int(source.cell)),"")
		if key.is_empty() or ready.has(key): return 1
		ready[key]=pieces[leaf]
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var entries: Dictionary={}
	var physical: Dictionary={}
	for depth in [3,2,1,0]:
		depths[depth].sort()
		for key: String in depths[depth]:
			var node: Dictionary=nodes[key]
			var mesh: ArrayMesh
			if depth==3:
				mesh=ready[key]
			else:
				var children: Array[ArrayMesh]=[]
				for child: String in node.children:
					if not ready.has(child): return 1
					children.append(ready[child])
				mesh=ComponentTree.Join.join(children)
				if mesh==null or not ComponentTree.Join.conserved(mesh,children): return 1
			var packed:=ComponentTree.Read.repack(mesh)
			if packed==null or ComponentTree.Read.corner_digest(packed)!=ComponentTree.Read.corner_digest(mesh) or packed.get_aabb()!=mesh.get_aabb(): return 1
			var saved:=ComponentTree.Components._save([packed],str(config.component.sha256)+":"+key+":2",output.path_join(key+"_layer_2.res"))
			if saved.is_empty(): return 1
			physical[saved.path]=saved
			entries[key]={"component":saved,"bounds":packed.get_aabb(),"triangles":ComponentTree.Indexed.triangles(packed),
				"parent":parent,"cell":int(node.cell),"ancestor":int(node.ancestor),"children":node.children}
			for child: String in node.children: ready.erase(child)
			ready[key]=packed
	if entries.size()!=277 or physical.size()!=277 or ready.size()!=1: return 1
	var report: Dictionary={"input_sha256":digest,"parent":parent,"fixed_source":config.component,
		"nodes":entries,"physical":physical,"actual_native_partition_verified":true,"saved_components":true,"installed":false}
	var path:=output.path_join("manifest.bin")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null: return 1
	file.store_var(report,false); file.close()
	file=FileAccess.open(path,FileAccess.READ)
	if file==null: return 1
	var saved: Variant=file.get_var(false); file.close()
	if saved!=report: return 1
	file=FileAccess.open(output.path_join("provenance.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"parent":parent,"input_sha256":digest,"manifest_sha256":FileAccess.get_sha256(path),
		"nodes":277,"remaining_faces":raw.size(),"actual_native_partition_verified":true,"saved_components":true,
		"building_geometry_rebuilt":false,"installed":false},"",true,true)); file.close()
	print("[Semantic fixed tree] parent=",parent," nodes=277 saved; building geometry untouched")
	return 0
