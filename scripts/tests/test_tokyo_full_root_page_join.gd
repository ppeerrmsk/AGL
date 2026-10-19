extends RefCounted
const Pages := preload("res://scripts/tests/build_tokyo_full_grid_root_pages.gd")
const Fixture := preload("res://scripts/tests/test_tokyo_full_grid_root.gd")


static func checks() -> bool:
	if Pages.run("","","","")!=1 or Pages.FullBake.run("","","")!=1:return false
	var plan: Dictionary={"passed":true,"camera_independent":true,"source_order_independent":true,"grid":1.0/1024.0,
		"collision_sha256":Pages.Root.Contract.COLLISION_SHA,"game_source_sha256":Pages.Root.Contract.GAME_SHA,
		"configuration":{"name":"lod5_full"},"parents":[],"meshes":[],"expected":[]}
	for parent in 16:
		plan.parents.append({"parent_id":parent})
		for kind in 2:plan.meshes.append({"id":parent*2+kind,"parent_id":parent,"kind":kind})
	for source in 189:plan.expected.append({"source_id":source})
	if not Pages.FullBake.valid(plan):return false
	for field: String in ["passed","camera_independent","source_order_independent"]:
		var broken:=plan.duplicate(true)
		broken[field]=false
		if Pages.FullBake.valid(broken):return false
	var broken:=plan.duplicate(true)
	broken.partial=true
	if Pages.FullBake.valid(broken):return false
	broken=plan.duplicate(true)
	broken.meshes[1].kind=0
	if Pages.FullBake.valid(broken):return false
	broken=plan.duplicate(true)
	broken.expected[1].source_id=0
	if Pages.FullBake.valid(broken):return false
	var native: Array[ArrayMesh]=[Pages.Root.Join.join([Fixture.triangle(0,false),Fixture.triangle(100,true)]),Fixture.triangle(200,false)]
	var fixed:=Fixture.triangle(300,true)
	var addition:=Pages.Root.Join.join([Fixture.triangle(400,false),Fixture.triangle(500,true)])
	var routes: Array[PackedInt32Array]=[PackedInt32Array([0,255]),PackedInt32Array([1])]
	var leaves:=Pages.compose(native,fixed,addition,routes,PackedInt32Array([2]),PackedInt32Array([1,255]))
	if leaves.size()!=256:return false
	var totals:=PackedInt32Array([0,0,0])
	for leaf: Array in leaves:
		for kind in 3:totals[kind]+=Pages.Root.Indexed.triangles(leaf[kind])
	if totals!=PackedInt32Array([2,3,1]) or Pages.Root.Indexed.triangles(leaves[1][1])!=2 \
			or Pages.Root.Indexed.triangles(leaves[255][0])!=1 or Pages.Root.Indexed.triangles(leaves[2][2])!=1:return false
	if not Pages.compose(native,fixed,addition,routes,PackedInt32Array([2]),PackedInt32Array([256,0])).is_empty():return false
	var root: Dictionary={"faces":[3],"sources":[]}
	var cursor:=0
	for leaf in 256:
		var count:=1 if leaf==0 else (2 if leaf==255 else 0)
		root.sources.append({"ranges":[{"kind":0,"first_triangle":cursor,"triangles":count}]})
		cursor+=count
	if Pages.fixed_routes(root)!=PackedInt32Array([0,255,255]):return false
	root.sources[7].ranges[0].first_triangle=9
	if not Pages.fixed_routes(root).is_empty():return false
	return true
