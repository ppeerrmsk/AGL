extends RefCounted
## 完整规范烘焙后，把原生/固定/游戏补面接成真实原叶三层组件树。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Native := preload("res://scripts/tests/build_tokyo_full_native_leaves.gd")
const ComponentTree := preload("res://scripts/tests/build_tokyo_full_component_tree.gd")
const FullBake := preload("res://scripts/tests/bake_tokyo_full_grid_configuration.gd")


static func fixed_routes(root: Dictionary) -> PackedInt32Array:
	var result:=PackedInt32Array()
	if root.get("sources",[]).size()!=256 or root.get("faces",[]).is_empty():return result
	var cursor:=0
	for leaf in 256:
		var spans: Variant=root.sources[leaf].get("ranges")
		if not spans is Array or spans.size()!=1:return PackedInt32Array()
		var span: Dictionary=spans[0]
		var count:=int(span.get("triangles",-1))
		if span.get("kind")!=0 or span.get("first_triangle")!=cursor or count<0 or count!=span.triangles:return PackedInt32Array()
		result.resize(cursor+count)
		for face in range(cursor,cursor+count):result[face]=leaf
		cursor+=count
	return result if cursor==root.faces[0] else PackedInt32Array()


static func compose(native: Array[ArrayMesh], fixed: ArrayMesh, addition: ArrayMesh, routes: Array[PackedInt32Array], fixed_owners: PackedInt32Array, game_owners: PackedInt32Array) -> Array:
	if native.size()!=2 or routes.size()!=2:return []
	var layers: Array=[]
	for kind in 4:
		var mesh: ArrayMesh=native[kind] if kind<2 else (fixed if kind==2 else addition)
		var owners: PackedInt32Array=routes[kind] if kind<2 else (fixed_owners if kind==2 else game_owners)
		if mesh==null:return []
		var pieces:=Native.Split.partition(mesh,owners,256)
		if pieces.size()!=256 or not Native.conserved(mesh,pieces,owners):return []
		layers.append(pieces)
	var leaves: Array=[]
	for leaf in 256:
		var high:=Root.Join.join([layers[1][leaf],layers[3][leaf]])
		if not Root.Join.conserved(high,[layers[1][leaf],layers[3][leaf]]):return []
		var meshes: Array[ArrayMesh]=[layers[0][leaf],high,layers[2][leaf]]
		leaves.append(meshes)
	return leaves


static func run(input: String, digest: String, output: String, fixed_output: String) -> int:
	if not Root.binding_valid({"path":input,"sha256":digest}) or not output.is_absolute_path() or not fixed_output.is_absolute_path() \
			or DirAccess.dir_exists_absolute(output):return 1
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if not config is Dictionary or config.get("schema")!=1 or config.get("native_routes",[]).size()!=2:return 1
	for key: String in ["plan","bundle","audit_proof","independent_audit","schedule","root_manifest","fixed_manifest","hierarchy","game_routes","game_route_manifest"]:
		if not Root.binding_valid(config.get(key)):return 1
	if config.hierarchy.sha256!=Root.Contract.HIERARCHY_SHA:return 1
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.plan.path))
	var proof: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.audit_proof.path))
	var independent: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.independent_audit.path))
	var schedule: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.schedule.path))
	var root: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.root_manifest.path))
	var fixed_root: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.fixed_manifest.path))
	var game_manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.game_route_manifest.path))
	var parent:=int(config.get("parent",-1))
	if parent<0 or parent>=16 or parent!=config.parent or not FullBake.valid(plan) or not proof.get("passed",false) \
			or proof.get("plan_sha256")!=config.plan.sha256 or proof.get("bundle_sha256")!=config.bundle.sha256 \
			or proof.get("independent_sha256")!=config.independent_audit.sha256 or not independent.get("passed",false) \
			or not schedule.get("passed",false) or schedule.get("owners",[]).size()!=189 \
			or schedule.get("collision_sha256")!=plan.collision_sha256 or schedule.get("game_source_sha256")!=plan.game_source_sha256 \
			or root.get("parent_id")!=parent or root.get("configuration")!=plan.configuration.name \
			or fixed_root.get("parent_id")!=parent or fixed_root.get("configuration")!="fixed" \
			or root.get("sources",[]).size()!=256 or fixed_root.get("sources",[]).size()!=256 \
			or root.get("fail",1)!=0 or fixed_root.get("fail",1)!=0 \
			or not game_manifest.get("passed",false) or game_manifest.get("owners")!=config.schedule or game_manifest.get("hierarchy")!=config.hierarchy:
		return 1
	var selected: Dictionary={}
	for row: Dictionary in schedule.configurations:
		if row.name==plan.configuration.name:selected=row
	if selected.is_empty() or selected.get("plan_sha256")!=config.plan.sha256 or selected.get("parts",[]).size()!=16:return 1
	var game_row: Dictionary={}
	for row: Dictionary in game_manifest.rows:
		if row.configuration==plan.configuration.name:game_row=row
	if game_row.is_empty() or game_row.get("plan")!=config.plan or game_row.get("route")!=config.game_routes:return 1
	if not Root.binding_valid(root.component) or not Root.binding_valid(fixed_root.component):return 1
	var bundle: Resource=ResourceLoader.load(config.bundle.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var original: Resource=ResourceLoader.load(root.component.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var ground: Resource=ResourceLoader.load(fixed_root.component.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if bundle==null or original==null or ground==null or bundle.plan_sha256!=config.plan.sha256 \
			or bundle.collision_sha256!=plan.collision_sha256 or not original.valid() or not ground.valid() \
			or original.meshes.size()!=2 or ground.meshes.size()!=1:return 1
	var native: Array[ArrayMesh]=[original.meshes[0],original.meshes[1]]
	var routes: Array[PackedInt32Array]=[PackedInt32Array(),PackedInt32Array()]
	var kinds: Dictionary={}
	for route: Dictionary in config.native_routes:
		var kind:=int(route.get("kind",-1))
		if kind<0 or kind>1 or kind!=route.kind or kinds.has(kind) or not Root.binding_valid(route):return 1
		kinds[kind]=true
		var descriptor: Dictionary={}
		for item: Dictionary in plan.meshes:
			if item.parent_id==parent and item.kind==kind:descriptor=item
		if descriptor.is_empty() or descriptor.id!=route.mesh_id or descriptor.path!=root.component.path or descriptor.source_sha256!=root.component.sha256:return 1
		for n in bundle.descriptors.size():
			if bundle.descriptors[n].id==descriptor.id:
				if bundle.descriptors[n]!=descriptor:return 1
				native[kind]=bundle.meshes[n]
		var raw:=FileAccess.get_file_as_bytes(route.path)
		routes[kind].resize(raw.size())
		for n in raw.size():routes[kind][n]=raw[n]
		if routes[kind].size()!=route.baked:return 1
	# 游戏补面先按固定根分组；再按各根原叶分组，保留全局Baker的墙→屋面顺序。
	var raw_game:=FileAccess.get_file_as_bytes(config.game_routes.path)
	if raw_game.size()%2!=0 or raw_game.size()/2!=game_row.faces:return 1
	var parent_owners:=PackedInt32Array()
	var leaf_owners:=PackedInt32Array()
	for n in raw_game.size()/2:
		var owner:=raw_game.decode_u16(n*2)
		if owner>=4096:return 1
		parent_owners.append(owner/256)
		if owner/256==parent:leaf_owners.append(owner%256)
	var additions:=Native.Split.partition(bundle.addition,parent_owners,16)
	if additions.size()!=16 or not Native.conserved(bundle.addition,additions,parent_owners):return 1
	var pieces:=compose(native,ground.meshes[0],additions[parent],routes,fixed_routes(fixed_root),leaf_owners)
	if pieces.size()!=256:return 1
	var hierarchy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.hierarchy.path))
	var nodes: Dictionary={}
	var leaf_keys: Dictionary={}
	for key: String in hierarchy.nodes:
		var node: Dictionary=hierarchy.nodes[key]
		if node.parent!=parent:continue
		nodes[key]=node
		if node.depth==3:leaf_keys[str(node.tile)+":"+str(int(node.source_cell))]=key
	var leaves: Dictionary={}
	var game_leaves: Array=game_manifest.leaves.get(str(parent),[])
	if game_leaves.size()!=256:return 1
	for leaf in 256:
		var row: Dictionary=root.sources[leaf]
		if fixed_root.sources[leaf].tile!=row.tile or fixed_root.sources[leaf].cell!=row.cell \
				or game_leaves[leaf].tile!=row.tile or game_leaves[leaf].cell!=row.cell:return 1
		var key: String=leaf_keys.get(str(row.tile)+":"+str(int(row.cell)),"")
		if key.is_empty() or leaves.has(key):return 1
		leaves[key]=pieces[leaf]
	var sources:=PackedInt32Array(selected.parts[parent].expected)
	var context: Dictionary={"parent":parent,"configuration":plan.configuration.name,"output":output,"fixed_output":fixed_output,
		"source_hash":(str(config.plan.sha256)+str(schedule.owners_sha256)+str(fixed_root.component.sha256)).sha256_text(),
		"fixed_source":fixed_root.component.sha256,"collision_sha256":plan.collision_sha256,"owners_sha256":schedule.owners_sha256,"game_sources":sources}
	var result:=ComponentTree.build(leaves,nodes,context)
	if result.is_empty():return 1
	var file:=FileAccess.open(output.path_join("provenance.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"input_sha256":digest,"parent":parent,"configuration":plan.configuration.name,
		"nodes":277,"fixed_included":true,"gameplay_additions_included":true,"saved_components":true,"source_coverage_proven":false,"installed":false},"",true,true))
	file.close()
	return 0
