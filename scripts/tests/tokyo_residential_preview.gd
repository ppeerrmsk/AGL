extends RefCounted
## 独立原生资产预览，不替代游戏LOD、材质或性能验收。
const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Subset := preload("res://scripts/tests/build_tokyo_path_lod.gd")


static func blocks_mesh(blocks: Array) -> ArrayMesh:
	var builder := Factory.new()
	for block: Dictionary in blocks:
		for face: Array in block.roof:
			var p: Array[Vector3] = []
			for v: Array in face:
				p.append(Vector3(v[0],block.height,v[1]))
			if (p[1]-p[0]).cross(p[2]-p[0]).y < 0:
				builder.triangle(p[0],p[2],p[1],Color("a1aaa0"))
			else:
				builder.triangle(p[0],p[1],p[2],Color("a1aaa0"))
		for ring: Array in block.rings:
			for i in ring.size():
				var a := Vector3(ring[i][0],0,ring[i][1])
				var b := Vector3(ring[(i+1)%ring.size()][0],0,ring[(i+1)%ring.size()][1])
				builder.quad(a,b,b+Vector3.UP*block.height,a+Vector3.UP*block.height,Color("69766f"))
	return builder.mesh()


static func retained_mesh(mesh: ArrayMesh, polygons: Array, region: Rect2 = Rect2(-6300,-2350,340,310)) -> ArrayMesh:
	var shapes: Array[PackedVector2Array] = []
	for ring: Array in polygons:
		var shape := PackedVector2Array()
		for p: Array in ring:
			shape.append(Vector2(p[0],p[1]))
		shapes.append(shape)
	var result := preload("res://scripts/tests/tokyo_residential_selection.gd").partition(mesh,shapes,region)
	if result.is_empty():
		return null
	print("[R153 whole selection] groups=",result.groups," selected=",result.selected," removed_faces=",result.removed_faces)
	return result.kept


static func export_kept(mesh: ArrayMesh, output: String) -> int:
	var payload := export_payload(mesh)
	if payload.is_empty():
		return 1
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		return 1
	file.store_buffer(payload.positions)
	file.close()
	file=FileAccess.open(output+".attributes",FileAccess.WRITE)
	if file==null:
		return 1
	file.store_buffer(payload.attributes)
	file.close()
	return 0


static func export_attributes(mesh: ArrayMesh, output: String) -> int:
	var payload := export_payload(mesh)
	if payload.is_empty():
		return 1
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		return 1
	file.store_buffer(payload.attributes)
	file.close()
	return 0


static func export_payload(mesh: ArrayMesh) -> Dictionary:
	if mesh==null or mesh.get_surface_count()>1:
		return {}
	if mesh.get_surface_count()==0:
		return {"positions":PackedByteArray(),"attributes":PackedByteArray()}
	var arrays := mesh.surface_get_arrays(0)
	if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array or not arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
		return {}
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	if normals.size()!=vertices.size() or colors.size()!=vertices.size():
		return {}
	var points := PackedFloat32Array()
	var values := PackedFloat32Array()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	if count%3!=0:
		return {}
	for corner in count:
		var index := indices[corner] if not indices.is_empty() else corner
		if index<0 or index>=vertices.size():
			return {}
		var p := vertices[index]
		var n := normals[index]
		var c := colors[index]
		points.append_array(PackedFloat32Array([p.x,p.y,p.z]))
		values.append_array(PackedFloat32Array([p.x,p.y,p.z,n.x,n.y,n.z,c.r,c.g,c.b,c.a]))
	return {"positions":points.to_byte_array(),"attributes":values.to_byte_array()}


static func run(parent: Node, root: String, output: String) -> int:
	var southwest := OS.get_environment("AGL_TOKYO_RESIDENTIAL_SOUTHWEST")=="1"
	if southwest:
		for suffix: String in ["NORTHWEST_EXPORT", "SOUTH", "NORTHWEST_WEST", "NORTHWEST_EAST", "OUTER_WEST", "NORTH_SEAM", "NORTH_LEFT", "NORTH_RIGHT"]:
			if OS.get_environment("AGL_TOKYO_RESIDENTIAL_"+suffix)=="1":
				return 1
		if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST")!="1":
			return 1
	var south := OS.get_environment("AGL_TOKYO_RESIDENTIAL_SOUTH")=="1"
	if south and OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_EXPORT")=="1":
		return 1
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_MATRIX") == "1":
		return northwest_matrix(root, output)
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_EXPORT") == "1":
		return export_northwest(root, output)
	var northwest := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST") == "1"
	var northwest_west := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_WEST") == "1"
	var northwest_east := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_EAST") == "1"
	var outer_west := OS.get_environment("AGL_TOKYO_RESIDENTIAL_OUTER_WEST") == "1"
	var north_seam := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_SEAM") == "1"
	var north_left := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_LEFT") == "1"
	var north_right := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_RIGHT") == "1"
	if south and (not northwest or northwest_west or northwest_east or outer_west or north_seam or north_left or north_right):
		return 1
	if north_right and (not northwest or north_left or north_seam or outer_west or northwest_west or northwest_east):
		return 1
	if north_left and (not northwest or north_seam or outer_west or northwest_west or northwest_east):
		return 1
	if north_seam and (not northwest or outer_west or northwest_west or northwest_east):
		return 1
	if outer_west and (not northwest or northwest_west or northwest_east):
		return 1
	if ((northwest_west or northwest_east) and not northwest) or (northwest_west and northwest_east):
		return 1
	var north := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH")=="1"
	var west := OS.get_environment("AGL_TOKYO_RESIDENTIAL_WEST")=="1"
	var road := OS.get_environment("AGL_TOKYO_RESIDENTIAL_WEST_ROAD")=="1"
	west = west or road
	if (north and west) or (northwest and (north or west)):
		return 1
	var directory := "r178-west-b" if west else "r152-residential-c"
	if road:
		directory = "r179-west-road-b"
	if north:
		directory = "r190-north-road-b"
	if northwest:
		directory = "r198-northwest-blocks-a"
	if northwest_west:
		directory = "r209-northwest-west-blocks-a"
	if northwest_east:
		directory = "r215-northwest-east-blocks-a"
	if outer_west:
		directory = "r228-outer-west-north-blocks-a"
	if north_seam:
		directory = "r242-north-seam-blocks-a"
	if north_left:
		directory = "r257-north-left-blocks-a"
	if north_right:
		directory = "r270-north-right-blocks-a"
	if south:
		directory = "r293-south-blocks-b"
	var path := root.path_join(directory+"/plan.json")
	if southwest:
		directory="r307-southwest-blocks-a"
		path=root.path_join(directory+"/plan.json")
	var expected := "a5c87fa9d4875934b961687e8d84724e2b1bddc532b242bcce791e5ded9dab92" if west else "448380aec118c0bbdbf6225c5c1a39f47364030441ab50bb7fb6ee096e904857"
	if road:
		expected = "7753c022092757e8859f4d4250fb990553a5a85d29991c312789813f2ffd456e"
	if north:
		expected = "b22719d71b4060a889f8594c8608959ad1538a814b2bac82d79aeb2d2a60388a"
	if northwest:
		expected = "5eccbf4dc5e169d025c524ff4a432110065358f1fe54636cdb92e205b1d5c8e3"
	if northwest_west:
		expected = "2a98d784a96835c2a6a4916e71568a697c8af3c97aec494a3f581a382264f7a7"
	if northwest_east:
		expected = "784f42d8e13003ed3938cf6df6a6dd26b2a83aaf1d9008a3a5e03e7d91b5d591"
	if outer_west:
		expected = "9f7c27ebce36567f59db1a81576a8b719837d264552e8e25adb8b05b8021d3a1"
	if north_seam:
		expected = "7702028eee7e0a359c7ad8a694bf77db046469e99fd6aa50794aa9b9c056568f"
	if north_left:
		expected = "ee3e6547a8a0ef1d69a8419f9f025818de6ec206266f11a14dec31907fd3a9fb"
	if north_right:
		expected = "ac8b693797f4ca229bc2c2425ee23c0cc5f8f78b2e093eed3cf4b0ce66863955"
	if south:
		expected = "b6a0511a2e0a2da4252f044dbde1dc72c930fd7e74e2420c8c5a2f943084a025"
	if southwest:
		expected="a4297d68828ce676fca2442af006cf2183bddac713d9d9ce9b8da2e15d4ae1a5"
	if DisplayServer.get_name()=="headless" or DirAccess.dir_exists_absolute(output) or FileAccess.get_sha256(path)!=expected:
		return 1
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var source_path := root.path_join("r143-native-a/lod5_full/parent_11.res")
	if northwest:
		source_path = root.path_join("r198-northwest-native-source-a/layer_0.res")
	if outer_west:
		source_path = root.path_join("r228-outer-west-native-source-a/layer_0.res")
	if north_seam:
		source_path = root.path_join("r242-north-seam-native-source-a/layer_0.res")
	if north_left:
		source_path = root.path_join("r257-north-left-native-source-a/layer_0.res")
	if north_right:
		source_path = root.path_join("r270-north-right-native-source-a/layer_0.res")
	if southwest:
		source_path=root.path_join("r307-southwest-native-source-a/layer_0.res")
	if FileAccess.get_sha256(source_path)!=plan.source_sha256:
		return 1
	var page: Variant = load(source_path)
	if northwest:
		var source_manifest_path := root.path_join("r198-northwest-native-source-a/manifest.json")
		if outer_west:
			source_manifest_path = root.path_join("r228-outer-west-native-source-a/manifest.json")
		if north_seam:
			source_manifest_path = root.path_join("r242-north-seam-native-source-a/manifest.json")
		if north_left:
			source_manifest_path = root.path_join("r257-north-left-native-source-a/manifest.json")
		if north_right:
			source_manifest_path = root.path_join("r270-north-right-native-source-a/manifest.json")
		if southwest:
			source_manifest_path=root.path_join("r307-southwest-native-source-a/manifest.json")
		if FileAccess.get_sha256(source_manifest_path) != plan.source_manifest_sha256:
			return 1
		var source_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_manifest_path))
		var meshes: Array[ArrayMesh] = []
		for layer in 3:
			var mesh_path := source_manifest_path.get_base_dir().path_join("layer_%d.res" % layer)
			if FileAccess.get_sha256(mesh_path) != source_manifest.layers[layer].mesh_sha256:
				return 1
			var mesh: ArrayMesh = load(mesh_path)
			if mesh == null:
				return 1
			meshes.append(mesh)
		page = {"meshes":meshes}
	var selection_path := root.path_join(directory+"/selection.json")
	var selection_sha := "7c03bc67fa34715fe6e9bfef68788fa272bc728a39e1ab5de7cae778acee4e7c" if road else "743548cac3b2e6f991f6351e334454f226da60533cf57044197cc67eb8e71c1d"
	if north:
		selection_sha = "aa75c630c8d81132c515c3f87d6c7aebff55dafa7aadd53e50a29bce9eac5a85"
	if northwest:
		selection_sha = "7be206980ed8fdc600a65b0772cc89cf8ef665a6cce66f4bc622f108011f9add"
	if northwest_west:
		selection_sha = "2bfb252d4d3cac14d524122f8fc61fc47f5cb6081a264c9bbcec20aaac4de99a"
	if northwest_east:
		selection_sha = "52daf068c03e4953347eab31589caa20eae823cc4e8ffb894d9748669649c2ad"
	if outer_west:
		selection_sha = "7af88c4064dc479ca45efd41f0ec98476931a71ddbec823df9ed527cf8c82b87"
	if north_seam:
		selection_sha = "298b997a2d90a43d6f45cc3fcd1941bb17a8ea06a8c75c9e1b26679d2ab64402"
	if north_left:
		selection_sha = "b00575af8e2ce9f3713afe974f494a3d704acd9d59880891c6f9af5e037e281f"
	if north_right:
		selection_sha = "10dc96d2e3f14ab4086fde03df9d158252024566d5617a8f2d8b6a481052dee9"
	if south:
		selection_sha = "f03789ceb536ebffed5e59af14cfaa46f02c94c145bdbcb3a65042bd566f0bc7"
	if southwest:
		selection_sha="82e2224a58673c43da3efbe17f67451a79898b33831dfad1ad3bdd9a25965f6b"
	if (west or north or northwest) and FileAccess.get_sha256(selection_path)!=selection_sha:
		return 1
	var selection: Array = JSON.parse_string(FileAccess.get_file_as_string(selection_path))
	var selected_count := 1896 if northwest_west else (1542 if northwest else (205 if north else (707 if road else (484 if west else 466))))
	if northwest_east:
		selected_count=2181
	if outer_west:
		selected_count=2614
	if north_seam:
		selected_count=1142
	if north_left:
		selected_count=1259
	if north_right:
		selected_count=537
	if south:
		selected_count=780
		var guard := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")
		var game_source: Dictionary = guard.read_source()
		if game_source.is_empty():
			return 1
		var checked: Dictionary = guard.inspect_bounds(Rect2(-6990,-2980,460,220),game_source.entries)
		if checked.is_empty() or not checked.standalone_merge_allowed:
			return 1
		print("[R294 gameplay guard] accepted=",game_source.entries.size()," contacts=",checked.contacts," source_sha=",game_source.source_sha256)
	if southwest:
		selected_count=4850
		var guard := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")
		var game_source: Dictionary = guard.read_source()
		if game_source.is_empty():
			return 1
		var checked: Dictionary = guard.inspect_bounds(Rect2(-8290,-2690,980,980),game_source.entries)
		print("[R308 gameplay guard] ",checked," source_sha=",game_source.source_sha256)
		if checked.is_empty() or not checked.standalone_merge_allowed:
			return 1
	if page==null or (not northwest and not page.valid()) or selection.size()!=selected_count:
		return 1
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_MATRIX") in ["1", "source"]:
		if west or north or northwest:
			return 1 # 新区域只做资产预览，不混入旧矩阵配方。
		return matrix(root,output,selection,OS.get_environment("AGL_TOKYO_RESIDENTIAL_MATRIX")=="source")
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1200,900)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.far=2000
	var center := Vector3(-6675,0,-2325) if west else Vector3(-6130,0,-2195)
	if north:
		center = Vector3(-6196,0,-2548)
	if northwest:
		center = Vector3(-6755,0,-3200)
	if northwest_west:
		center = Vector3(-7140,0,-3200)
	if northwest_east:
		center = Vector3(-6415,0,-3200)
	if outer_west:
		center = Vector3(-7800,0,-3520)
	if north_seam:
		center = Vector3(-7300,0,-4470)
	if north_left:
		center = Vector3(-8050,0,-3875)
	if north_right:
		center = Vector3(-6550,0,-4390)
	if south:
		center = Vector3(-6760,0,-2870)
	if southwest:
		center=Vector3(-7800,0,-2200)
	camera.position=center+Vector3(0,800,200)
	camera.look_at(center,Vector3.UP)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	var applied: Material = material
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_LIT")=="1":
		var lit := ShaderMaterial.new()
		lit.shader=preload("res://resources/shaders/tokyo_volume_surface.gdshader")
		applied=lit
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees=Vector3(-50,-35,0)
		sun.light_energy=0.8
		sun.shadow_enabled=false
		viewport.add_child(sun)
	var nodes: Array[MeshInstance3D] = []
	for mesh: ArrayMesh in page.meshes:
		var node := MeshInstance3D.new()
		node.mesh=mesh
		node.material_override=applied
		viewport.add_child(node)
		nodes.append(node)
	var addition := MeshInstance3D.new()
	addition.material_override=applied
	viewport.add_child(addition)
	var region := Rect2(-6800,-2450,250,250) if west else Rect2(-6300,-2350,340,310)
	if road or north or northwest:
		region = Rect2(plan.region[0],plan.region[1],plan.region[2]-plan.region[0],plan.region[3]-plan.region[1])
	var kept := retained_mesh(page.meshes[0],selection,region)
	DirAccess.make_dir_recursive_absolute(output)
	if kept==null or export_kept(kept,output.path_join("kept.bin"))!=0:
		viewport.queue_free()
		await parent.get_tree().process_frame
		return 1
	var fail := 0
	for distance: int in [700,450,260]:
		camera.size=distance
		for variant: int in [-1,0,1]:
			nodes[0].mesh=page.meshes[0] if variant==-1 else kept
			addition.mesh=null if variant==-1 else blocks_mesh(plan.variants[variant].blocks)
			for frame in 3:
				await RenderingServer.frame_post_draw
			fail += int(viewport.get_texture().get_image().save_png(output.path_join("view_%d_variant_%d.png"%[distance,variant]))!=OK)
	viewport.queue_free()
	await parent.get_tree().process_frame
	print("[R152 residential asset preview] captures=9 fail=",fail," game_lod_evidence=false")
	return fail


static func matrix(root: String, output: String, polygons: Array, original_source: bool = false) -> int:
	var path := root.path_join("r150-native-a/catalog.res")
	if FileAccess.get_sha256(path)!="b2590118e3073a24099ee1b661a89238a796d6c4069d71122238246e7fc620d9":
		return 1
	var catalog: Resource = load(path)
	if catalog==null or not catalog.valid():
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array = []
	for name: String in catalog.configurations:
		var entry: Dictionary = catalog.configurations[name][11]
		if FileAccess.get_sha256(entry.path)!=entry.sha256:
			return 1
		var page: Resource = load(entry.path)
		if page==null or not page.valid() or page.parent_id!=11:
			return 1
		# 区外重建必须从未删减来源裁切；kept仅供历史反例与区内保留使用。
		var kept: ArrayMesh = page.meshes[0] if original_source else retained_mesh(page.meshes[0],polygons)
		var filename := name+("-original.bin" if original_source else "-kept.bin")
		if kept==null or export_kept(kept,output.path_join(filename))!=0:
			return 1
		rows.append({"configuration":name,"source_sha256":entry.sha256,"kept_sha256":FileAccess.get_sha256(output.path_join(filename)),"file":filename,"attributes_sha256":FileAccess.get_sha256(output.path_join(filename+".attributes"))})
	var file := FileAccess.open(output.path_join("matrix.json"),FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify({"catalog_sha256":FileAccess.get_sha256(path),"rows":rows,"runtime_integrated":false,"original_source":original_source}))
	file.close()
	return 0


static func export_northwest(root: String, output: String, level: int = 5, middle: bool = false) -> int:
	var index_path := root.path_join("r197-northwest-native-e/index.res")
	var expected := "62dfca0fca35809b466d5ca532bc90cc32ca6ea4360c5e248b5168642eb9d6be"
	var source_count := 8216
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_RIGHT_EXPORT") == "1":
		if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_LEFT_EXPORT") == "1" or OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_SEAM_EXPORT") == "1" or OS.get_environment("AGL_TOKYO_RESIDENTIAL_OUTER_WEST_EXPORT") == "1":
			return 1
		index_path = root.path_join("r268-north-right-native-a/index.res")
		expected = "4fa67221657f9e0486f36c01ae1954a5e96c1f04856598ba91a54d181975ed3b"
		source_count = 1276
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_LEFT_EXPORT") == "1":
		if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_SEAM_EXPORT") == "1" or OS.get_environment("AGL_TOKYO_RESIDENTIAL_OUTER_WEST_EXPORT") == "1":
			return 1
		index_path = root.path_join("r256-north-left-native-a/index.res")
		expected = "9a13d404d19c175c83a5607dc75277f7b3f3c74d9eec1154a278e2c515233b9b"
		source_count = 2697
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_SEAM_EXPORT") == "1":
		if OS.get_environment("AGL_TOKYO_RESIDENTIAL_OUTER_WEST_EXPORT") == "1":
			return 1
		index_path = root.path_join("r241-north-seam-native-a/index.res")
		expected = "1ceffdc517a410e36f10245fa3da7e966a78f116ec9a3b7e3c0cd9acc69a3f17"
		source_count = 3339
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_OUTER_WEST_EXPORT") == "1":
		index_path = root.path_join("r227-outer-west-native-a/index.res")
		expected = "a3f50687ef16da436272fa650c325a6992276168c3e9dac7731da1d54efe4dfc"
		source_count = 5525
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_SOUTHWEST_EXPORT") == "1":
		for flag: String in ["NORTH_RIGHT", "NORTH_LEFT", "NORTH_SEAM", "OUTER_WEST"]:
			if OS.get_environment("AGL_TOKYO_RESIDENTIAL_"+flag+"_EXPORT") == "1":
				return 1
		index_path = root.path_join("r305-southwest-native-a/index.res")
		expected = "a83a00ad6197491c39402e2ab9572d4ec667e018980fcf3f28c49eeba379ebe1"
		source_count = 5774
	return export_index(index_path, expected, source_count, output, level, middle)


static func export_index(index_path: String, expected: String, source_count: int, output: String, level: int = 5, middle: bool = false) -> int:
	# 批次与旧区域共用同一原生保存/重载/属性守恒流程。
	if expected.length() != 64 or not expected.is_valid_hex_number() or source_count < 0 or level < 0 or level > 5 or (middle and level != 4) or output.is_empty() or DirAccess.dir_exists_absolute(output) or FileAccess.get_sha256(index_path) != expected:
		return 1
	var index: Resource = ResourceLoader.load(index_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if index == null or not index.valid() or index.source_count != source_count or index.cells.size() != 16:
		return 1
	var layers: Array = [[], [], []]
	var sources: Array[Dictionary] = []
	for entry: Dictionary in index.cells:
		var descriptor: Dictionary = entry.mid if middle else entry.levels[level]
		var near_path: String = descriptor.path
		var near: Resource = ResourceLoader.load(near_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var fixed: Resource = ResourceLoader.load(entry.fixed, "", ResourceLoader.CACHE_MODE_IGNORE)
		if near == null or fixed == null or not near.valid() or not fixed.valid() or near.meshes.size() != 2 or fixed.meshes.size() != 1:
			return 1
		if near.triangles != descriptor.triangles or fixed.triangles != entry.fixed_triangles:
			return 1
		layers[0].append(near.meshes[0])
		layers[1].append(near.meshes[1])
		layers[2].append(fixed.meshes[0])
		sources.append({"near":near_path,"near_sha256":FileAccess.get_sha256(near_path),"fixed":entry.fixed,"fixed_sha256":FileAccess.get_sha256(entry.fixed)})
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		return 1
	var rows: Array[Dictionary] = []
	for layer in 3:
		var inputs: Array[ArrayMesh] = []
		inputs.assign(layers[layer])
		var joined := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd").join(inputs)
		if not preload("res://scripts/experiments/tokyo_packed_mesh_join.gd").conserved(joined, inputs):
			return 1
		var path := output.path_join("layer_%d.res" % layer)
		if ResourceSaver.save(joined, path, ResourceSaver.FLAG_COMPRESS) != OK:
			return 1
		var restored: ArrayMesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if restored == null or not preload("res://scripts/experiments/tokyo_packed_mesh_join.gd").conserved(restored, inputs):
			return 1
		var binary := output.path_join("layer_%d.bin" % layer)
		if export_kept(restored, binary) != 0:
			return 1
		rows.append({"layer":layer,"mesh_sha256":FileAccess.get_sha256(path),"file":binary.get_file(),"sha256":FileAccess.get_sha256(binary),"attributes_sha256":FileAccess.get_sha256(binary+".attributes")})
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify({"index_sha256":expected,"sources":sources,"layers":rows,"source_hash":index.source_hash,"configuration":"mid4" if middle else "lod%d_full" % level,"read_only_sources":true,"runtime_integrated":false}))
	file.close()
	print("[Northwest native export] cells=16 layers=3 packed_conserved=true fail=0")
	return 0


static func northwest_matrix(root: String, output: String) -> int:
	var southwest := OS.get_environment("AGL_TOKYO_RESIDENTIAL_SOUTHWEST")=="1"
	var south := OS.get_environment("AGL_TOKYO_RESIDENTIAL_SOUTH")=="1"
	var selection_path := root.path_join("r198-northwest-blocks-a/selection.json")
	var west := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_WEST")=="1"
	var east := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_EAST")=="1"
	var outer := OS.get_environment("AGL_TOKYO_RESIDENTIAL_OUTER_WEST")=="1"
	var north_seam := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_SEAM")=="1"
	var north_left := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_LEFT")=="1"
	var north_right := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_RIGHT")=="1"
	if southwest != (OS.get_environment("AGL_TOKYO_RESIDENTIAL_SOUTHWEST_EXPORT")=="1"):
		return 1
	if southwest and (south or west or east or outer or north_seam or north_left or north_right or OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST")!="1"):
		return 1
	if south and (west or east or outer or north_seam or north_left or north_right or OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST")!="1"):
		return 1
	if (north_right and (north_left or north_seam or outer or east or west)) or north_right != (OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_RIGHT_EXPORT")=="1"):
		return 1
	if (north_left and (north_seam or outer or east or west)) or north_left != (OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_LEFT_EXPORT")=="1"):
		return 1
	if (north_seam and (outer or east or west)) or north_seam != (OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_SEAM_EXPORT")=="1"):
		return 1
	if (east and west) or (outer and (east or west)) or outer != (OS.get_environment("AGL_TOKYO_RESIDENTIAL_OUTER_WEST_EXPORT")=="1"):
		return 1
	var index_sha := "a3f50687ef16da436272fa650c325a6992276168c3e9dac7731da1d54efe4dfc" if outer else "62dfca0fca35809b466d5ca532bc90cc32ca6ea4360c5e248b5168642eb9d6be"
	var selection_sha := "7be206980ed8fdc600a65b0772cc89cf8ef665a6cce66f4bc622f108011f9add"
	var selected_count := 1542
	var region := Rect2(-6980,-3410,450,420)
	var reusable: Array = []
	if southwest:
		index_sha="a83a00ad6197491c39402e2ab9572d4ec667e018980fcf3f28c49eeba379ebe1"
		selection_path=root.path_join("r307-southwest-blocks-a/selection.json")
		selection_sha="82e2224a58673c43da3efbe17f67451a79898b33831dfad1ad3bdd9a25965f6b"
		selected_count=4850
		region=Rect2(-8290,-2690,980,980)
		var guard := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")
		var game_source: Dictionary = guard.read_source()
		if game_source.is_empty():
			return 1
		var inspected: Dictionary = guard.inspect_bounds(region,game_source.entries)
		if inspected.is_empty() or not inspected.standalone_merge_allowed:
			return 1
	if south:
		selection_path=root.path_join("r293-south-blocks-b/selection.json")
		selection_sha="f03789ceb536ebffed5e59af14cfaa46f02c94c145bdbcb3a65042bd566f0bc7"
		selected_count=780
		region=Rect2(-6990,-2980,460,220)
	if north_right:
		index_sha="4fa67221657f9e0486f36c01ae1954a5e96c1f04856598ba91a54d181975ed3b"
		selection_path=root.path_join("r270-north-right-blocks-a/selection.json")
		selection_sha="10dc96d2e3f14ab4086fde03df9d158252024566d5617a8f2d8b6a481052dee9"
		selected_count=537
		region=Rect2(-6790,-4690,480,980)
	if north_left:
		index_sha="9a13d404d19c175c83a5607dc75277f7b3f3c74d9eec1154a278e2c515233b9b"
		selection_path=root.path_join("r257-north-left-blocks-a/selection.json")
		selection_sha="b00575af8e2ce9f3713afe974f494a3d704acd9d59880891c6f9af5e037e281f"
		selected_count=1259
		region=Rect2(-8290,-4040,480,330)
	if north_seam:
		index_sha="1ceffdc517a410e36f10245fa3da7e966a78f116ec9a3b7e3c0cd9acc69a3f17"
		selection_path=root.path_join("r242-north-seam-blocks-a/selection.json")
		selection_sha="298b997a2d90a43d6f45cc3fcd1941bb17a8ea06a8c75c9e1b26679d2ab64402"
		selected_count=1142
		region=Rect2(-7790,-4690,980,440)
	if outer:
		selection_path=root.path_join("r228-outer-west-north-blocks-a/selection.json")
		selection_sha="7af88c4064dc479ca45efd41f0ec98476931a71ddbec823df9ed527cf8c82b87"
		selected_count=2614
		region=Rect2(-8290,-3690,980,340)
	if west:
		selection_path=root.path_join("r209-northwest-west-blocks-a/selection.json")
		selection_sha="2bfb252d4d3cac14d524122f8fc61fc47f5cb6081a264c9bbcec20aaac4de99a"
		selected_count=1896
		region=Rect2(-7290,-3690,300,980)
	if east:
		selection_path=root.path_join("r215-northwest-east-blocks-a/selection.json")
		selection_sha="52daf068c03e4953347eab31589caa20eae823cc4e8ffb894d9748669649c2ad"
		selected_count=2181
		region=Rect2(-6520,-3690,210,980)
	if west or east or south:
		var existing_path := root.path_join("r199-northwest-matrix-a/matrix.json")
		if FileAccess.get_sha256(existing_path)!="dfc5155ed097bed15331cdaffc9b91e124e35395745090c5662d04c7fad78fec":
			return 1
		var existing: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(existing_path))
		reusable=existing.rows
		if reusable.size()!=7:
			return 1
	if output.is_empty() or DirAccess.dir_exists_absolute(output) or FileAccess.get_sha256(selection_path) != selection_sha:
		return 1
	var selection: Array = JSON.parse_string(FileAccess.get_file_as_string(selection_path))
	if selection.size() != selected_count or DirAccess.make_dir_recursive_absolute(output) != OK:
		return 1
	var rows: Array[Dictionary] = []
	for slot in 7:
		var level := slot if slot < 6 else 4
		var name := "mid4" if slot == 6 else "lod%d_full" % slot
		var source_dir := output.path_join(name)
		# 已完整导出的近档仅复用，避免覆盖或再生成同一资产。
		if west or east or south:
			if reusable[slot].configuration!=name:
				return 1
			source_dir=reusable[slot].source_directory
			if FileAccess.get_sha256(source_dir.path_join("manifest.json"))!=reusable[slot].source_manifest_sha256:
				return 1
		elif slot == 5:
			source_dir = root.path_join("r228-outer-west-native-source-a" if outer else "r198-northwest-native-source-a")
			if north_seam:
				source_dir=root.path_join("r242-north-seam-native-source-a")
			if north_left:
				source_dir=root.path_join("r257-north-left-native-source-a")
			if north_right:
				source_dir=root.path_join("r270-north-right-native-source-a")
			if southwest:
				source_dir=root.path_join("r307-southwest-native-source-a")
		elif export_northwest(root, source_dir, level, slot == 6) != 0:
			return 1
		var source_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_dir.path_join("manifest.json")))
		if source_manifest.get("index_sha256", "") != index_sha or source_manifest.get("configuration", "") != name:
			return 1
		var mesh_path := source_dir.path_join("layer_0.res")
		if FileAccess.get_sha256(mesh_path) != source_manifest.layers[0].mesh_sha256:
			return 1
		var original: ArrayMesh = ResourceLoader.load(mesh_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var kept := retained_mesh(original, selection, region)
		if kept == null or export_kept(kept, output.path_join(name+"-kept.bin")) != 0:
			return 1
		var kept_path := output.path_join(name+"-kept.res")
		if ResourceSaver.save(kept, kept_path, ResourceSaver.FLAG_COMPRESS) != OK:
			return 1
		var restored: ArrayMesh = ResourceLoader.load(kept_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if restored == null or not preload("res://scripts/experiments/tokyo_packed_mesh_join.gd").conserved(restored, [kept]):
			return 1
		rows.append({"configuration":name,"source_directory":source_dir,"source_manifest_sha256":FileAccess.get_sha256(source_dir.path_join("manifest.json")),"original_faces":preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(original),"kept_faces":preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(kept),"kept_sha256":FileAccess.get_sha256(kept_path),"kept_binary_sha256":FileAccess.get_sha256(output.path_join(name+"-kept.bin"))})
	var file := FileAccess.open(output.path_join("matrix.json"),FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify({"rows":rows,"source_index_sha256":index_sha,"selection_sha256":FileAccess.get_sha256(selection_path),"runtime_integrated":false,"fail":0}))
	file.close()
	print("[Northwest matrix] configurations=7 fail=0")
	return 0
