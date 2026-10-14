extends RefCounted
## 西北独立样片：同一块面七档唯一owner，不改变玩法来源或正式地图。
const Preview := preload("res://scripts/tests/tokyo_residential_preview.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Exact := preload("res://scripts/tests/build_tokyo_shared_pages.gd")


static func run(root: String, output: String) -> int:
	var index_path := root.path_join("r197-northwest-native-e/index.res")
	var plan_path := root.path_join("r198-northwest-blocks-a/plan.json")
	var selection_path := root.path_join("r198-northwest-blocks-a/selection.json")
	var west := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_WEST")=="1"
	var east := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTHWEST_EAST")=="1"
	var outer := OS.get_environment("AGL_TOKYO_RESIDENTIAL_OUTER_WEST")=="1"
	var north_seam := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_SEAM")=="1"
	var north_left := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_LEFT")=="1"
	var north_right := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_RIGHT")=="1"
	var south := OS.get_environment("AGL_TOKYO_RESIDENTIAL_SOUTH")=="1"
	var southwest := OS.get_environment("AGL_TOKYO_RESIDENTIAL_SOUTHWEST")=="1"
	if southwest and (south or west or east or outer or north_seam or north_left or north_right):
		return 1
	if south and (west or east or outer or north_seam or north_left or north_right):
		return 1
	if north_right and (north_left or north_seam or outer or east or west):
		return 1
	if north_left and (north_seam or outer or east or west):
		return 1
	if north_seam and (outer or east or west):
		return 1
	if (east and west) or (outer and (east or west)):
		return 1
	var index_sha := "62dfca0fca35809b466d5ca532bc90cc32ca6ea4360c5e248b5168642eb9d6be"
	var plan_sha := "5eccbf4dc5e169d025c524ff4a432110065358f1fe54636cdb92e205b1d5c8e3"
	var selection_sha := "7be206980ed8fdc600a65b0772cc89cf8ef665a6cce66f4bc622f108011f9add"
	var region := Rect2(-6980,-3410,450,420)
	var expected_blocks := 109
	var expected_block_faces := 2747
	if southwest:
		index_path=root.path_join("r305-southwest-native-a/index.res")
		index_sha="a83a00ad6197491c39402e2ab9572d4ec667e018980fcf3f28c49eeba379ebe1"
		plan_path=root.path_join("r307-southwest-blocks-a/plan.json")
		plan_sha="a4297d68828ce676fca2442af006cf2183bddac713d9d9ce9b8da2e15d4ae1a5"
		selection_path=root.path_join("r307-southwest-blocks-a/selection.json")
		selection_sha="82e2224a58673c43da3efbe17f67451a79898b33831dfad1ad3bdd9a25965f6b"
		region=Rect2(-8290,-2690,980,980)
		expected_blocks=585
		expected_block_faces=10463
		var guard := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")
		var gameplay: Dictionary = guard.read_source()
		if gameplay.is_empty() or not guard.inspect_bounds(region,gameplay.entries).get("standalone_merge_allowed",false):
			return 1
	if south:
		index_path=root.path_join("r216-combined-northwest-native-a/index.res")
		index_sha="e1eb3eb1ad4adf1f9fe908bb024cb9f03e830b60df9dd400e9eaabfb82d5e7ed"
		plan_path=root.path_join("r293-south-blocks-b/plan.json")
		plan_sha="b6a0511a2e0a2da4252f044dbde1dc72c930fd7e74e2420c8c5a2f943084a025"
		selection_path=root.path_join("r293-south-blocks-b/selection.json")
		selection_sha="f03789ceb536ebffed5e59af14cfaa46f02c94c145bdbcb3a65042bd566f0bc7"
		region=Rect2(-6990,-2980,460,220)
		expected_blocks=83
		expected_block_faces=1631
		var guard := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd")
		var gameplay: Dictionary = guard.read_source()
		if gameplay.is_empty() or not guard.inspect_bounds(region,gameplay.entries).get("standalone_merge_allowed",false):
			return 1
	if north_right:
		index_path=root.path_join("r268-north-right-native-a/index.res")
		index_sha="4fa67221657f9e0486f36c01ae1954a5e96c1f04856598ba91a54d181975ed3b"
		plan_path=root.path_join("r270-north-right-blocks-a/plan.json")
		plan_sha="ac8b693797f4ca229bc2c2425ee23c0cc5f8f78b2e093eed3cf4b0ce66863955"
		selection_path=root.path_join("r270-north-right-blocks-a/selection.json")
		selection_sha="10dc96d2e3f14ab4086fde03df9d158252024566d5617a8f2d8b6a481052dee9"
		region=Rect2(-6790,-4690,480,980)
		expected_blocks=164
		expected_block_faces=2507
	if north_left:
		index_path=root.path_join("r256-north-left-native-a/index.res")
		index_sha="9a13d404d19c175c83a5607dc75277f7b3f3c74d9eec1154a278e2c515233b9b"
		plan_path=root.path_join("r257-north-left-blocks-a/plan.json")
		plan_sha="ee3e6547a8a0ef1d69a8419f9f025818de6ec206266f11a14dec31907fd3a9fb"
		selection_path=root.path_join("r257-north-left-blocks-a/selection.json")
		selection_sha="b00575af8e2ce9f3713afe974f494a3d704acd9d59880891c6f9af5e037e281f"
		region=Rect2(-8290,-4040,480,330)
		expected_blocks=105
		expected_block_faces=2412
	if north_seam:
		index_path=root.path_join("r241-north-seam-native-a/index.res")
		index_sha="1ceffdc517a410e36f10245fa3da7e966a78f116ec9a3b7e3c0cd9acc69a3f17"
		plan_path=root.path_join("r242-north-seam-blocks-a/plan.json")
		plan_sha="7702028eee7e0a359c7ad8a694bf77db046469e99fd6aa50794aa9b9c056568f"
		selection_path=root.path_join("r242-north-seam-blocks-a/selection.json")
		selection_sha="298b997a2d90a43d6f45cc3fcd1941bb17a8ea06a8c75c9e1b26679d2ab64402"
		region=Rect2(-7790,-4690,980,440)
		expected_blocks=253
		expected_block_faces=4245
	if west:
		index_path=root.path_join("r199-northwest-blocks-native-b/index.res")
		index_sha="ee7ff835d1c0f871a26c5bb0f216b41b3c102c0a8782c17b639c736f456b621c"
		plan_path=root.path_join("r209-northwest-west-blocks-a/plan.json")
		plan_sha="2a98d784a96835c2a6a4916e71568a697c8af3c97aec494a3f581a382264f7a7"
		selection_path=root.path_join("r209-northwest-west-blocks-a/selection.json")
		selection_sha="2bfb252d4d3cac14d524122f8fc61fc47f5cb6081a264c9bbcec20aaac4de99a"
		region=Rect2(-7290,-3690,300,980)
		expected_blocks=232
		expected_block_faces=4577
	if east:
		index_path=root.path_join("r210-combined-northwest-native-a/index.res")
		index_sha="98c54d044d7e0043d948dbb264602eb25b3a0ed22b673fa5ffd0d36833c22aa0"
		plan_path=root.path_join("r215-northwest-east-blocks-a/plan.json")
		plan_sha="784f42d8e13003ed3938cf6df6a6dd26b2a83aaf1d9008a3a5e03e7d91b5d591"
		selection_path=root.path_join("r215-northwest-east-blocks-a/selection.json")
		selection_sha="52daf068c03e4953347eab31589caa20eae823cc4e8ffb894d9748669649c2ad"
		region=Rect2(-6520,-3690,210,980)
		expected_blocks=141
		expected_block_faces=3349
	if outer:
		index_path=root.path_join("r227-outer-west-native-a/index.res")
		index_sha="a3f50687ef16da436272fa650c325a6992276168c3e9dac7731da1d54efe4dfc"
		plan_path=root.path_join("r228-outer-west-north-blocks-a/plan.json")
		plan_sha="9f7c27ebce36567f59db1a81576a8b719837d264552e8e25adb8b05b8021d3a1"
		selection_path=root.path_join("r228-outer-west-north-blocks-a/selection.json")
		selection_sha="7af88c4064dc479ca45efd41f0ec98476931a71ddbec823df9ed527cf8c82b87"
		region=Rect2(-8290,-3690,980,340)
		expected_blocks=249
		expected_block_faces=5103
	var source_directory := "r240-north-seam-source-b" if north_seam else ("r226-outer-west-source-a" if outer else "r194-northwest-source-b")
	if southwest:
		source_directory="r302-southwest-source-b"
	if north_left:
		source_directory="r255-north-left-source-b"
	if north_right:
		source_directory="r255-north-right-source-b"
	if not Builder.valid_sample_output(root.path_join(source_directory), output):
		return 1
	if FileAccess.get_sha256(index_path) != index_sha or FileAccess.get_sha256(plan_path) != plan_sha or FileAccess.get_sha256(selection_path) != selection_sha:
		return 1
	var matrix: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("r229-outer-west-matrix-audit.json" if outer else "r199-matrix-audit.json")))
	var matrix_sha := "f1c8387af138cbd3beec04a3b253325a6db91c89c0e0234ae30b7e39bedf2fb8" if outer else "dfc5155ed097bed15331cdaffc9b91e124e35395745090c5662d04c7fad78fec"
	if southwest:
		var audit_path := root.path_join("r309-southwest-matrix-audit.json")
		if FileAccess.get_sha256(audit_path)!="06e2f7db6f37768e02a421abc2fe7568cdacaca924c277a53e57c43edb7ae2e4":
			return 1
		matrix=JSON.parse_string(FileAccess.get_file_as_string(audit_path))
		matrix_sha="f0c940e9204193d76eada94daa21a8488ef964942c494e0ddd9e20268e50d681"
		var chosen: Array[Dictionary] = []
		for row: Dictionary in matrix.rows:
			if is_equal_approx(float(row.radius),8.0):
				chosen.append(row)
		matrix.rows=chosen
	if south:
		var joint_path := root.path_join("r295-joint-cost.json")
		matrix_sha="0ce5a9befcad21f63d54f51beb9e77a2e73cd06250adf79d125ce8f763493ba1"
		if FileAccess.get_sha256(joint_path)!=matrix_sha:
			return 1
		var joint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(joint_path))
		var expected_rows: Array[Dictionary] = []
		for row: Dictionary in joint.rows:
			expected_rows.append({"configuration":row.configuration,"original_faces":row.old_joint_faces,"kept_faces":int(row.new_joint_faces)-expected_block_faces,"result_faces":row.new_joint_faces})
		matrix={"fail":0,"matrix_sha256":matrix_sha,"rows":expected_rows}
	if north_seam:
		matrix=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("r243-north-seam-matrix-audit.json")))
		matrix_sha="cbbdc77608339f7d2750349a9259f079e5e5956e32a7fb536f1014a01cfd792f"
	if north_left:
		matrix=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("r258-north-left-matrix-audit.json")))
		matrix_sha="93a9f6a635d92471efa7e44ae36294d8d5c51a550bea415411bce39599b8830a"
	if north_right:
		matrix=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("r272-north-right-matrix-audit.json")))
		matrix_sha="7f010b54a8e48e49abbf10f88a802bd98efe185f179c548f4f1c6db9f8788468"
	if matrix.get("fail",1) != 0 or matrix.get("matrix_sha256","") != matrix_sha or matrix.get("rows",[]).size() != 7:
		return 1
	var original_index: Resource = ResourceLoader.load(index_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if west or east:
		var next_path := "r216-east-matrix-audit.json" if east else "r210-west-matrix-audit.json"
		var next_sha := "8da1c3f5071f0033bbecc9a30857db72042e4e822748f12b1e694772e36619d7" if east else "4073a3a9116a003425a47f05b1deef1e3b88e2bdef857127800ae76d41fe6152"
		var next_matrix: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(next_path)))
		if next_matrix.get("fail",1)!=0 or next_matrix.get("matrix_sha256","")!=next_sha or next_matrix.get("rows",[]).size()!=7:
			return 1
		var western: Dictionary = {}
		if east:
			western=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("r210-west-matrix-audit.json")))
			if western.get("fail",1)!=0 or western.get("matrix_sha256","")!="4073a3a9116a003425a47f05b1deef1e3b88e2bdef857127800ae76d41fe6152" or western.get("rows",[]).size()!=7:
				return 1
		# 原始矩阵加旧中央及西侧真实净差；最后仍须逐格实测吻合，不能覆盖旧成品。
		for slot in 7:
			var previous: Dictionary = matrix.rows[slot]
			var current: Dictionary = next_matrix.rows[slot]
			if current.configuration!=previous.configuration or current.original_faces!=previous.original_faces:
				return 1
			var delta := int(previous.result_faces)-int(previous.original_faces)
			if east:
				var old_west: Dictionary = western.rows[slot]
				if old_west.configuration!=previous.configuration or old_west.original_faces!=previous.original_faces:
					return 1
				delta+=int(old_west.result_faces)-int(old_west.original_faces)
			for key: String in ["original_faces","kept_faces","result_faces"]:
				current[key]=int(current[key])+delta
		matrix=next_matrix
	return build_verified(original_index,index_path,plan_path,selection_path,output,region,matrix,expected_blocks,expected_block_faces,0 if southwest else 1)


static func valid_passthrough(plan: Dictionary, selection: Array, variant: int, blocks: int, faces: int) -> bool:
	if plan.get("passthrough")!=true or plan.get("original_components",-1)!=0 or not selection.is_empty() or blocks!=0 or faces!=0:
		return false
	var variants: Variant = plan.get("variants")
	return variants is Array and variant==0 and variants.size()==1 and variants[0] is Dictionary and variants[0].get("blocks")==[] and variants[0].get("parts",-1)==0 and variants[0].get("roof_triangles",-1)==0 and variants[0].get("wall_triangles",-1)==0


static func build_verified(original_index: Resource, index_path: String, plan_path: String, selection_path: String, output: String, region: Rect2, matrix: Dictionary, expected_blocks: int, expected_block_faces: int, variant: int) -> int:
	# 共享保存器；调用方先绑定来源/计划摘要及矩阵，旧区域校验不变。
	if original_index == null or not original_index.valid() or matrix.get("rows",[]).size()!=7 or expected_blocks<0:
		return 1
	var index: Resource = original_index.duplicate(true)
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	var selection: Array = JSON.parse_string(FileAccess.get_file_as_string(selection_path))
	var passthrough := valid_passthrough(plan,selection,variant,expected_blocks,expected_block_faces)
	if expected_blocks==0 and not passthrough:
		return 1
	var groups: Array = []
	for id in 16:
		groups.append([])
	var owners: Array[int] = []
	if variant < 0 or variant >= plan.variants.size():
		return 1
	for block: Dictionary in plan.variants[variant].blocks:
		var bounds := Rect2(Vector2(block.rings[0][0][0],block.rings[0][0][1]),Vector2.ZERO)
		for ring: Array in block.rings:
			for point: Array in ring:
				bounds = bounds.expand(Vector2(point[0],point[1]))
		var owner := -1
		for entry: Dictionary in index.cells:
			if (entry.bounds as Rect2).has_point(bounds.get_center()):
				if owner != -1:
					return 1
				owner = entry.id
		if owner < 0:
			return 1
		owners.append(owner)
		groups[owner].append(block)
		index.cells[owner].content_bounds = (index.cells[owner].content_bounds as Rect2).merge(bounds)
	if owners.size() != expected_blocks or DirAccess.make_dir_recursive_absolute(output) != OK:
		return 1
	var rows: Array[Dictionary] = []
	var saved_count := 0
	for slot in 7:
		var name := "mid4" if slot == 6 else "lod%d_full" % slot
		var original_faces := 0
		var kept_faces := 0
		var block_faces := 0
		var result_faces := 0
		for id in 16:
			var old_entry: Dictionary = original_index.cells[id]
			var descriptor: Dictionary = old_entry.mid if slot == 6 else old_entry.levels[slot]
			var source: Resource = ResourceLoader.load(descriptor.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if source == null or not source.valid() or source.triangles != descriptor.triangles:
				return 1
			var source_sha := FileAccess.get_sha256(descriptor.path)
			var kept: ArrayMesh = source.meshes[0] if passthrough else Preview.retained_mesh(source.meshes[0],selection,region)
			if kept == null:
				print("[Northwest blocks] retention rejected slot=",slot," cell=",id)
				return 1
			var addition := Preview.blocks_mesh(groups[id])
			var joined := kept if passthrough else Join.join([kept,addition])
			if not Join.conserved(joined,[kept,addition]):
				print("[Northwest blocks] join conservation rejected slot=",slot," cell=",id)
				return 1
			var candidate: Resource = source.duplicate(false)
			var candidate_meshes: Array[ArrayMesh] = [joined,source.meshes[1]]
			candidate.meshes = candidate_meshes
			candidate.bounds = index.cells[id].content_bounds
			candidate.triangles = 0
			candidate.geometry_bytes = 0
			Builder.finish(candidate)
			var path := output.path_join("cell_%02d_%s.res" % [id,name])
			if not candidate.valid() or ResourceSaver.save(candidate,path,ResourceSaver.FLAG_COMPRESS) != OK:
				print("[Northwest blocks] save rejected slot=",slot," cell=",id," valid=",candidate.valid())
				return 1
			var restored: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
			# joined已逐三角证明守恒；回读与它逐packed字节一致即可传递该证明。
			if restored == null or not restored.valid() or restored.source_ids != source.source_ids or restored.height_hash != source.height_hash or restored.triangles != candidate.triangles or not Exact.same_mesh(restored.meshes[0],joined) or not Exact.same_mesh(restored.meshes[1],source.meshes[1]) or FileAccess.get_sha256(descriptor.path) != source_sha:
				return 1
			var updated: Dictionary = descriptor.duplicate(true)
			updated.path = path
			updated.triangles = restored.triangles
			updated.bytes = restored.geometry_bytes
			if slot == 6:
				index.cells[id].mid = updated
			else:
				index.cells[id].levels[slot] = updated
			original_faces += Count.triangles(source.meshes[0])
			kept_faces += Count.triangles(kept)
			block_faces += Count.triangles(addition)
			result_faces += Count.triangles(restored.meshes[0])
			saved_count += 1
		var expected: Dictionary = matrix.rows[slot]
		if expected.configuration != name or original_faces != expected.original_faces or kept_faces != expected.kept_faces or block_faces != expected_block_faces or result_faces != expected.result_faces:
			print("[Northwest blocks] matrix mismatch ",name," expected=",expected," actual=",[original_faces,kept_faces,block_faces,result_faces])
			return 1
		rows.append({"configuration":name,"original_faces":original_faces,"kept_faces":kept_faces,"block_faces":block_faces,"result_faces":result_faces})
	if not index.valid() or ResourceSaver.save(index,output.path_join("index.res"),ResourceSaver.FLAG_COMPRESS) != OK:
		return 1
	var restored_index: Resource = ResourceLoader.load(output.path_join("index.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	if restored_index == null or not restored_index.valid() or restored_index.source_hash != original_index.source_hash:
		return 1
	var file := FileAccess.open(output.path_join("candidate_report.json"),FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify({"fail":0,"saved_archives":saved_count,"block_owners":owners,"rows":rows,"index_sha256":FileAccess.get_sha256(output.path_join("index.res")),"source_index_sha256":FileAccess.get_sha256(index_path),"plan_sha256":FileAccess.get_sha256(plan_path),"source_issues_resolved":false,"production_enabled":false,"visual_verified":false}))
	file.close()
	print("[Northwest blocks] saved=",saved_count," added_blocks=",expected_blocks," configurations=7 fail=0")
	return 0
