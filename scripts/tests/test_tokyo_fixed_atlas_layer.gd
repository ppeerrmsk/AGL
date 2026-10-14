extends RefCounted
const Layer := preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd")

class Fixture extends Node3D:
	var _batches: Dictionary = {}
	var _descriptors: Dictionary = {}
	var _canonical_sha := "f4139942c2708b515de82aa32f48c1de1f7cac6fe7b2eab37d9eee9047e2bc85"
	var _materials: Array[ShaderMaterial] = []
	var _stream: Node
	var _viewport: SubViewport
	var _preloaded_ao: RefCounted
	var _tile_ground: RefCounted
	func _add_mesh(mesh: ArrayMesh, material: ShaderMaterial, _shadow: bool) -> MeshInstance3D:
		var node := MeshInstance3D.new()
		node.mesh=mesh
		node.material_override=material
		add_child(node)
		return node


static func checks() -> Array[bool]:
	var results: Array[bool] = []
	results.append(not Layer.borrowed_overlap(13,[]))
	results.append(Layer.borrowed_overlap(13,[Rect2(-4701,-3701,2,2)]))
	results.append(not Layer.borrowed_overlap(13,[Rect2(-4701,-3701,1,1)]))
	results.append(Layer.borrowed_overlap(13,[Rect2(-5000,-4000,2000,2000)]))
	results.append(Layer.borrowed_overlap(13,[Rect2(NAN,0,1,1)]))
	var original := preload("res://resources/shaders/tokyo_volume_surface.gdshader").code
	var ao := preload("res://scripts/experiments/tokyo_baked_ao.gd").make_shader(original,true,true)
	var joint := Layer.shader_code(ao)
	results.append(joint.contains("uniform vec2 fixed_ground_height_range;") and joint.contains("step(receiver, fixed_ground_height_range.y + 0.004)"))
	results.append(not joint.contains("abs(ao_local.y - receiver)") and joint.contains("height_code < 65534.5") and joint.contains("ao_up > 0.99"))
	results.append(Layer.shader_code(ao.replace("abs(ao_local.y - receiver)","0.0")).is_empty())
	results.append(not Layer.shader_code(original).contains("fixed_ground_height_range"))
	results.append(Layer.eligible(.3888,28542,true))
	for scale: float in [0,-1,NAN,INF,.38881]:
		results.append(not Layer.eligible(scale,28542,true))
	results.append(not Layer.eligible(.2,28541,true) and not Layer.eligible(.2,28543,true) and not Layer.eligible(.2,28542,false))
	var data := {"parent":11,"encoding":"bc3_rgba_mips","catalog_sha256":Layer.CATALOG_SHA,"rows":[{"world_step":2,"width":824,"height":504,"conservative_bytes":1668112,"max_scale":.3888,"rectangular_coverage":true,"premultiplied_alpha":true,"native_bounds":[-7300.0,-2700.0,-5660.0,-1700.0],"bounds":[-7304.0,-2704.0,-5656.0,-1696.0],"height_range":[-.35,.58],"file":"fixed_2.bc3","sha256":"a".repeat(64)},{}]}
	results.append(not Layer.manifest_row(JSON.parse_string(JSON.stringify(data)),Layer.CATALOG_SHA).is_empty())
	results.append(Layer.manifest_row(data,"drift").is_empty() and Layer.manifest_row([],Layer.CATALOG_SHA).is_empty())
	var derived: String = preload("res://scripts/rendering/tokyo_canonical_catalog.gd").UNCHANGED_FIXED_LOD12_CATALOGS[1]
	results.append(Layer.manifest_row(data,derived).is_empty()) # 旧目录标签不能直接借用。
	var certified := data.duplicate(true)
	certified.catalog_sha256=derived
	results.append(not Layer.manifest_row(certified,derived).is_empty() and Layer.manifest_row(certified,Layer.CATALOG_SHA).is_empty())
	for field: String in ["world_step","width","height","conservative_bytes","max_scale","rectangular_coverage","premultiplied_alpha","native_bounds","bounds","height_range","file","sha256"]:
		var broken := data.duplicate(true)
		broken.rows[0].erase(field)
		results.append(Layer.manifest_row(broken,Layer.CATALOG_SHA).is_empty())
	var broken := data.duplicate(true)
	broken.rows[0].file="../fixed_2.bc3"
	results.append(Layer.manifest_row(broken,Layer.CATALOG_SHA).is_empty())
	broken=data.duplicate(true)
	broken.rows[0].bounds[0]=NAN
	results.append(Layer.manifest_row(broken,Layer.CATALOG_SHA).is_empty())
	for parent: int in [0,1,3,12,13]:
		var region := Layer.region_contract(parent)
		results.append(Layer.eligible(.3888,int(region.faces),true,parent))
		results.append(not Layer.eligible(.52,int(region.faces),true,parent) and not Layer.eligible(.2,int(region.faces)-1,true,parent))
	results.append(not Layer.eligible(.2,1,true,8))
	results.append(Layer.region_contract(11,"unknown").is_empty())
	var isolated := Layer.region_contract(11)
	isolated.faces=1
	isolated.bounds[0]=0
	results.append(Layer.region_contract(11).faces==28542 and Layer.region_contract(11).bounds[0]==-7300.0)
	results.append(not Layer.eligible(.2,28542,true,11,"unknown"))
	for id: int in [11,12]:
		var count := 28145 if id==11 else 9705
		results.append(Layer.eligible(.2,count,true,id,Layer.RESIDENTIAL_SHA))
		results.append(not Layer.eligible(.2,count,true,id) and not Layer.eligible(.52,count,true,id,Layer.RESIDENTIAL_SHA))
		results.append(not Layer.eligible(.2,int(Layer.region_contract(id).faces),true,id,Layer.RESIDENTIAL_SHA))
	results.append(Layer.RESIDENTIAL_SHA not in preload("res://scripts/rendering/tokyo_canonical_catalog.gd").UNCHANGED_FIXED_LOD12_CATALOGS)
	results.append(Layer.fixed_configuration("lod1_full",Layer.RESIDENTIAL_SHA))
	results.append(not Layer.fixed_configuration("lod1_full",Layer.CATALOG_SHA))
	for configuration: String in ["lod2_guarded","lod3_full","lod3_guarded"]:
		results.append(Layer.fixed_configuration(configuration,Layer.RESIDENTIAL_SHA) and not Layer.fixed_configuration(configuration,Layer.CATALOG_SHA))
	results.append(Layer.eligible(.55,28145,true,11,Layer.RESIDENTIAL_SHA,true))
	results.append(not Layer.eligible(.55001,28145,true,11,Layer.RESIDENTIAL_SHA,true) and not Layer.eligible(.5,9705,true,12,Layer.RESIDENTIAL_SHA,true))
	results.append(Layer.region_contract(11,Layer.CATALOG_SHA,true).is_empty() and Layer.region_contract(11,Layer.RESIDENTIAL_SHA,true).bytes==2205248)
	for configuration: Variant in ["lod0_full","lod1_guarded","lod4_full","lod5_full",null,1]:
		results.append(not Layer.fixed_configuration(configuration,Layer.RESIDENTIAL_SHA))
	results.append(Layer.collection_entries({},derived).is_empty())
	results.append(Layer.collection_entries({"schema":1,"catalog_sha256":derived,"regions":[]},derived).is_empty())
	return results


static func lifecycle(parent: Node) -> int:
	var fixture := Fixture.new()
	parent.add_child(fixture)
	var stream := preload("res://scripts/rendering/tokyo_cell_stream.gd").new()
	stream.configure(fixture,{})
	parent.add_child(stream)
	var layer := Layer.new()
	var ok := stream.reserve_auxiliary(layer.get_instance_id(),Layer.CHARGE)
	layer._stream=weakref(stream)
	layer._texture=ImageTexture.create_from_image(Image.create(4,4,false,Image.FORMAT_RGBA8))
	var texture_ref: WeakRef = weakref(layer._texture)
	layer._node=MeshInstance3D.new()
	fixture.add_child(layer._node)
	var native := MeshInstance3D.new()
	fixture.add_child(native)
	fixture._batches.a={"path":"a","nodes":[null,null,native],"layer_triangles":[0,0,28542]}
	fixture._descriptors.a={"canonical_identity":{"parent":11,"configuration":"lod2_full"}}
	layer.suspend()
	ok=ok and layer.update(fixture,.2,true) and not native.visible and layer._node.visible and layer.stats.faces==2
	layer.suspend()
	fixture._tile_ground=preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd").new()
	fixture._tile_ground._tiles.assign([Rect2(-7301,-2701,2,2)])
	layer.update(fixture,.2,true)
	ok=ok and native.visible and not layer._node.visible and layer.stats.faces==0
	await parent.get_tree().process_frame
	layer.suspend()
	fixture._tile_ground._tiles.assign([Rect2(-7301,-2701,1,1)])
	layer.update(fixture,.2,true)
	ok=ok and not native.visible and layer._node.visible and layer.stats.faces==2
	fixture._tile_ground=null
	layer.suspend()
	ok=ok and native.visible and not layer._node.visible
	ok=ok and layer.update(fixture,.52,true) and native.visible and not layer._node.visible
	fixture._batches.a.layer_triangles[2]=28541
	layer.suspend()
	layer.update(fixture,.2,true)
	ok=ok and native.visible and not layer._node.visible
	fixture._batches.a.layer_triangles[2]=28542
	fixture._descriptors.a.canonical_identity.configuration="lod1_full"
	layer.suspend()
	layer.update(fixture,.2,true)
	ok=ok and native.visible and not layer._node.visible
	fixture._descriptors.a.canonical_identity.configuration="lod2_full"
	layer.suspend()
	layer.update(fixture,.2,true)
	native.free()
	await parent.get_tree().process_frame
	layer.suspend()
	layer.close()
	layer.close()
	await parent.get_tree().process_frame
	ok=ok and texture_ref.get_ref()==null and stream.summary().auxiliary_bytes==0
	stream.close()
	fixture.queue_free()
	await parent.get_tree().process_frame
	print("[R141 fixed atlas lifecycle] pass=",ok)
	return int(not ok)+await collection_lifecycle(parent)+await collection_lifecycle(parent,Layer.RESIDENTIAL_SHA)


static func collection_lifecycle(parent: Node, catalog: String = Layer.CATALOG_SHA) -> int:
	var fixture := Fixture.new()
	parent.add_child(fixture)
	var stream := preload("res://scripts/rendering/tokyo_cell_stream.gd").new()
	stream.configure(fixture,{})
	parent.add_child(stream)
	fixture._stream=stream
	var root := Layer.new()
	var expected_total := 8970096 if catalog==Layer.RESIDENTIAL_SHA else 4018368
	var refs: Array[WeakRef] = []
	var ok := true
	for id: int in [11,0,1,3,12,13]:
		var member: RefCounted = root if id==11 else Layer.new()
		if id!=11:
			root._regions.append(member)
		member._parent=id
		member._catalog_sha=catalog
		member._fine=catalog==Layer.RESIDENTIAL_SHA and id==11
		member._stream=weakref(stream)
		member._node=MeshInstance3D.new()
		fixture.add_child(member._node)
		member._texture=ImageTexture.create_from_image(Image.create(4,4,false,Image.FORMAT_RGBA8))
		refs.append(weakref(member._texture))
		refs.append(weakref(member._node))
		var region := Layer.region_contract(id,catalog,member._fine)
		var charge := int(region.bytes)*3+4096
		ok=stream.reserve_auxiliary(member.get_instance_id(),charge) and ok
		member._state={"parent":id,"ready":true,"pooled_nodes":1,"reserved_bytes":charge}
		member._state["texture_step"]=1 if member._fine else 2
		member._state["catalog_sha256"]=catalog
		var native := MeshInstance3D.new()
		fixture.add_child(native)
		fixture._batches[str(id)]={"path":str(id),"nodes":[null,null,native],"layer_triangles":[0,0,region.faces]}
		fixture._descriptors[str(id)]={"canonical_identity":{"parent":id,"configuration":"lod1_full" if catalog==Layer.RESIDENTIAL_SHA else "lod2_full"}}
	# 同一父区跨两个批次仍应完整替换，不能把单次扫描误做成只取首批。
	var split := MeshInstance3D.new()
	fixture.add_child(split)
	fixture._batches["13"].layer_triangles[2]=4000
	fixture._batches["13b"]={"path":"13b","nodes":[null,null,split],"layer_triangles":[0,0,5566]}
	fixture._descriptors["13b"]=fixture._descriptors["13"].duplicate(true)
	root.suspend()
	ok=root.update(fixture,.2,true) and ok
	ok=ok and root.stats.scan_batches==7 and not split.visible
	ok=ok and root.stats.faces==12 and root.stats.visible_nodes==6 and root.stats.reserved_bytes==expected_total and stream.summary().auxiliary_bytes==expected_total
	var budget_check := preload("res://scripts/tests/tokyo_preloaded_ao_review.gd")
	for member: RefCounted in root.members():
		member._state["warm"]={"state":"ready","reserved_bytes":0,"peak_reserved_bytes":524288}
	root.refresh_stats()
	ok=ok and budget_check.fixed_atlas_bytes(root.stats,false)==expected_total
	var bad_budget := root.stats.duplicate(true)
	bad_budget.regions["0"].reserved_bytes-=1
	ok=ok and budget_check.fixed_atlas_bytes(bad_budget,false)==-1
	bad_budget=root.stats.duplicate(true)
	bad_budget.regions.erase("13")
	ok=ok and budget_check.fixed_atlas_bytes(bad_budget,false)==-1
	if catalog==Layer.RESIDENTIAL_SHA:
		bad_budget=root.stats.duplicate(true)
		bad_budget.regions["11"].catalog_sha256="wrong"
		ok=ok and budget_check.fixed_atlas_bytes(bad_budget,false)==-1
	root.suspend()
	fixture._descriptors["1"].canonical_identity.configuration="lod4_full"
	fixture._batches["3"].layer_triangles[2]-=1
	root.update(fixture,.2,true)
	ok=ok and root.stats.faces==8 and fixture._batches["1"].nodes[2].visible and fixture._batches["3"].nodes[2].visible
	root.suspend()
	fixture._descriptors["11"].canonical_identity.configuration="lod3_guarded"
	root.update(fixture,.5,true)
	ok=ok and root.stats.faces==(2 if catalog==Layer.RESIDENTIAL_SHA else 0)
	root.suspend()
	root.update(fixture,.551,true)
	ok=ok and root.stats.faces==0 and fixture._batches["11"].nodes[2].visible
	root.suspend()
	root.update(fixture,.98,true)
	ok=ok and root.stats.faces==0 and root.stats.scan_batches==0 and split.visible
	for batch: Dictionary in fixture._batches.values():
		ok=ok and batch.nodes[2].visible
	root.suspend()
	root.update(fixture,.2,true)
	fixture._batches["0"].nodes[2].free()
	await parent.get_tree().process_frame
	root.close()
	root.close()
	await parent.get_tree().process_frame
	for ref: WeakRef in refs:
		ok=ok and ref.get_ref()==null
	ok=ok and stream.summary().auxiliary_bytes==0 and root.stats.pooled_nodes==0
	# 显式接入轮次额外验真实六纹理绑定、暖绘中取消、预算中途拒绝整组释放。
	var directory := OS.get_environment("AGL_TOKYO_FIXED_SET_TEST")
	if not directory.is_empty():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("regions.json")))
		fixture._canonical_sha=str(data.get("catalog_sha256"))
		ok=ok and Layer.collection_entries(data,fixture._canonical_sha).size()==6
		for key: String in ["parent","manifest_sha256","directory"]:
			var bad := data.duplicate(true)
			bad.regions[2][key]=null
			ok=ok and Layer.collection_entries(bad,fixture._canonical_sha).is_empty()
		var duplicate := data.duplicate(true)
		duplicate.regions[2]=duplicate.regions[1]
		ok=ok and Layer.collection_entries(duplicate,fixture._canonical_sha).is_empty()
		fixture._viewport=SubViewport.new()
		fixture.add_child(fixture._viewport)
		var material := ShaderMaterial.new()
		material.shader=preload("res://resources/shaders/tokyo_volume_surface.gdshader")
		for index in 6:
			fixture._materials.append(material)
		var real := Layer.new()
		var bound := real.bind(fixture,directory)
		var real_expected := 8970096 if fixture._canonical_sha==Layer.RESIDENTIAL_SHA else 4018368
		ok=ok and bound and real.members().size()==6 and real.stats.reserved_bytes==real_expected
		var actual_refs: Array[WeakRef] = []
		if bound:
			for member: RefCounted in real.members():
				actual_refs.append(weakref(member._texture))
				actual_refs.append(weakref(member._node))
				actual_refs.append(member._warm)
			ok=ok and stream.summary().auxiliary_bytes==real_expected+6*524288
		real.close()
		await parent.get_tree().process_frame
		for ref: WeakRef in actual_refs:
			ok=ok and ref.get_ref()==null
		ok=ok and stream.summary().auxiliary_bytes==0
		var available := 8000000 if fixture._canonical_sha==Layer.RESIDENTIAL_SHA else 2500000
		ok=stream.reserve_auxiliary(987654,100663296-available) and ok
		var rejected := Layer.new()
		ok=ok and not rejected.bind(fixture,directory) and rejected._regions.is_empty() and rejected._texture==null
		await parent.get_tree().process_frame
		ok=ok and stream.summary().auxiliary_bytes==100663296-available
		stream.release_auxiliary(987654)
	stream.close()
	fixture.queue_free()
	await parent.get_tree().process_frame
	print("[R146 fixed collection lifecycle] pass=",ok," real_assets=",not directory.is_empty())
	return int(not ok)
