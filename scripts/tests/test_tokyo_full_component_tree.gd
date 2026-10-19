extends RefCounted
const ComponentTree := preload("res://scripts/tests/build_tokyo_full_component_tree.gd")
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")


static func run(output: String, hierarchy_path: String) -> int:
	if output.is_empty() or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output) \
			or FileAccess.get_sha256(hierarchy_path)!=ComponentTree.Contract.HIERARCHY_SHA:
		return 1
	var hierarchy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(hierarchy_path))
	var nodes: Dictionary={}
	var leaves: Dictionary={}
	for key: String in hierarchy.nodes:
		var node: Dictionary=hierarchy.nodes[key]
		if node.parent!=0:continue
		nodes[key]=node
		if node.depth==3:
			var meshes: Array[ArrayMesh]=[ArrayMesh.new(),ArrayMesh.new(),ArrayMesh.new()]
			leaves[key]=meshes
	var keys: Array=leaves.keys()
	keys.sort()
	for index in [0,255]:
		var node: Dictionary=nodes[keys[index]]
		for kind in 3:
			var builder:=Geometry.new()
			var x:=float(node.bounds[0])
			var z:=float(node.bounds[1])
			var y:=15.8 if kind==1 else 0.0
			builder.triangle(Vector3(x,y,z),Vector3(x+1,y,z),Vector3(x,y,z+1),Color(0.4,0.5,0.6))
			leaves[keys[index]][kind]=builder.mesh()
	var context: Dictionary={"parent":0,"configuration":"lod5_full","output":output.path_join("lod5"),
		"fixed_output":output.path_join("fixed"),"source_hash":"a".repeat(64),"fixed_source":"b".repeat(64),
		"collision_sha256":ComponentTree.Contract.COLLISION_SHA,"owners_sha256":"c".repeat(64),"game_sources":PackedInt32Array([82])}
	# 缺叶/错树必须在创建目录前拒绝，不能留下看似可用的残缺树。
	var broken:=leaves.duplicate()
	broken.erase(keys[0])
	if not ComponentTree.build(broken,nodes,context).is_empty() or DirAccess.dir_exists_absolute(context.output):return 1
	var first:=ComponentTree.build(leaves,nodes,context)
	if first.is_empty() or first.pages.size()!=277 or first.physical.size()!=831:return 1
	var catalog:=Catalog.new()
	catalog.schema_version=2
	catalog.collision_sha256=context.collision_sha256
	catalog.owners_sha256=context.owners_sha256
	catalog.descriptors=first.descriptors
	var seen: Dictionary={}
	if not ComponentTree.Contract.entry_valid(first.root,"lod5_full",0,-1,-1,catalog,seen) or seen.size()!=277:return 1
	if first.root.triangles!=PackedInt32Array([2,2,2]):return 1
	var fixed_hashes: Dictionary={}
	for path: String in first.physical:
		if path.begins_with(context.fixed_output):fixed_hashes[path]=first.physical[path].sha256
	if fixed_hashes.size()!=277:return 1
	context.configuration="lod4_full"
	context.output=output.path_join("lod4")
	context.source_hash="d".repeat(64)
	var second:=ComponentTree.build(leaves,nodes,context)
	if second.is_empty() or second.physical.size()!=831 or second.root.triangles!=first.root.triangles:return 1
	for path: String in fixed_hashes:
		if second.physical[path].sha256!=fixed_hashes[path] or FileAccess.get_sha256(path)!=fixed_hashes[path]:return 1
	for logical: String in first.pages:
		if FileAccess.file_exists(logical):return 1
	var stats: Dictionary={"passed":true,"fixture_only":true,"nodes_per_configuration":277,"configurations":2,
		"fixed_components_shared":277,"canonical_ready":false,"installed":false,"source_coverage_proven":false}
	var file:=FileAccess.open(output.path_join("test-result.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(stats,"",true,true))
	file.close()
	print("[Full component tree] saved=554 nodes fixed_shared=277 packed_reload=true schema2_identity=true fixture_only=true")
	return 0
