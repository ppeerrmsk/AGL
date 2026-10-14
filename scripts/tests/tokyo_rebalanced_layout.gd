extends RefCounted
## 只生成六区父11共享切分布局；保留全部有向原生几何，不启用运行时。
const Spatial := preload("res://scripts/tests/build_tokyo_canonical_spatial.gd")


static func run(path: String, output: String) -> int:
	var near_only := OS.get_environment("AGL_TOKYO_NEAR_LAYOUT")=="1"
	var expected_sha := "fbb2da6b32b5e3f75c6ad9c91dadcc07725a9805f1b0effb57ec343c590f81c9" if near_only else "3e81e5f839591ac89d4d662163450b36902763f41b9c8539427d6bcdddb075ef"
	if OS.get_environment("AGL_TOKYO_NINE_REGION_LAYOUT")=="1":
		if not near_only:
			return 1
		expected_sha="fc2c255c53372e5f08643a70febfabeb277a8203d4ffe9f394c7bc86a709cb30"
	if OS.get_environment("AGL_TOKYO_SOUTH_LAYOUT")=="1":
		if not near_only or OS.get_environment("AGL_TOKYO_NINE_REGION_LAYOUT")!="1":
			return 1
		expected_sha="5ca41d3e671d5189288a49fdf71561d4c06b943636f465ee553c4f37859c5512"
	if OS.get_environment("AGL_TOKYO_SOUTHWEST_LAYOUT")=="1":
		if not near_only or OS.get_environment("AGL_TOKYO_NINE_REGION_LAYOUT")!="1" or OS.get_environment("AGL_TOKYO_SOUTH_LAYOUT")!="1":
			return 1
		expected_sha="9c96d71f29c964b1174bff22b2d0518cadcf662bbce1b0ae33d7fcd34ddcd8d4"
	if output.is_empty() or FileAccess.file_exists(output) or FileAccess.get_sha256(path)!=expected_sha:
		return 1
	var catalog: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if catalog==null or not catalog.valid():
		return 1
	var entry: Dictionary = catalog.configurations.lod5_full[11]
	if FileAccess.get_sha256(entry.path)!=entry.sha256:
		return 1
	var page: Resource = ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if page==null or not page.valid():
		return 1
	var cut := Spatial.Split.cuts(page.meshes)
	var split := Spatial._split(page.meshes,cut)
	if split.size()!=3:
		return 1
	var children: Array[Dictionary] = []
	var total := 0
	for n in 4:
		var meshes: Array[ArrayMesh] = [split[0][n],split[1][n],split[2][n]]
		var child_cut := Spatial.Split.cuts(meshes)
		var leaves := Spatial._split(meshes,child_cut)
		if leaves.size()!=3:
			return 1
		var costs: Array = []
		for k in 4:
			var leaf: Array[ArrayMesh] = [leaves[0][k],leaves[1][k],leaves[2][k]]
			var descriptor := Spatial.Spatial.descriptor(leaf)
			costs.append(Array(descriptor.triangles))
			for faces: int in descriptor.triangles:
				total+=faces
		children.append({"cell_id":entry.children[n].cell_id,"old_cuts":Array(entry.children[n].cuts),"cuts":Array(child_cut),"leaf_faces":costs})
	if total!=page.triangles:
		return 1
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify({"fail":0,"catalog_sha256":FileAccess.get_sha256(path),"source_path":entry.path,"source_sha256":entry.sha256,"parent":11,"reference_configuration":"lod5_full","old_cuts":Array(entry.cuts),"cuts":Array(cut),"children":children,"faces":total,"packed_conserved":true,"shared_layout_all_lods_required":not near_only,"target_configurations":["lod4_full","lod4_mid","lod5_full"] if near_only else Array(preload("res://scripts/rendering/tokyo_canonical_catalog.gd").CONFIGURATIONS),"catalog_built":false,"visual_verified":false}))
	file.close()
	print("[Rebalanced layout] parent=11 leaves=16 faces=",total," packed_conserved=true fail=0")
	return 0
