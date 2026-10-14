extends RefCounted
const Parts := preload("res://scripts/tests/build_tokyo_mesh_components.gd")
const Mapping := preload("res://scripts/rendering/tokyo_low_wall_manifest.gd")
const Binding := preload("res://scripts/rendering/tokyo_low_wall_binding.gd")
const Stream := preload("res://scripts/rendering/tokyo_component_stream.gd")
const Page := preload("res://scripts/rendering/tokyo_canonical_spatial_page.gd")


static func fixture(directory: String = "") -> Dictionary:
	var factory := preload("res://scripts/experiments/volume_mesh_factory.gd").new()
	factory.triangle(Vector3(0,2,0),Vector3(0,2,2),Vector3(2,2,0),Color.WHITE)
	var roof := factory.mesh()
	factory = preload("res://scripts/experiments/volume_mesh_factory.gd").new()
	factory.triangle(Vector3(0,0,0),Vector3(0,2,0),Vector3(2,2,0),Color.WHITE)
	var wall := factory.mesh()
	var physical: Dictionary = {}
	var native: Dictionary = {}
	var keys: Dictionary = {}
	for name_value: String in ["pair","common"]:
		var part := preload("res://scripts/rendering/tokyo_mesh_component.gd").new()
		part.source_hash = name_value.sha256_text()
		part.meshes.assign([roof,wall] if name_value == "pair" else [ArrayMesh.new(),ArrayMesh.new()])
		for mesh: ArrayMesh in part.meshes:
			part.mesh_bytes.append(Parts.Builder.mesh_bytes(mesh))
			part.geometry_bytes += part.mesh_bytes[-1]
		var path := name_value if directory.is_empty() else directory.path_join(name_value+".res")
		keys[name_value] = path
		physical[path] = {"path":path,"bytes":part.geometry_bytes,"canonical_identity":part.stream_identity(),"sha256":"a".repeat(64)}
		if not directory.is_empty():
			physical[path] = Parts._save(part.meshes,name_value,path)
			if physical[path].is_empty():
				return {}
		native[path] = part
	var identity := Page.new()
	identity.configuration = "lod2_full"
	identity.level = 2
	identity.parent_id = 11
	identity.source_hash = "a".repeat(64)
	identity.collision_sha256 = "b".repeat(64)
	identity.owners_sha256 = "c".repeat(64)
	var old_low: Dictionary = physical[keys.pair].duplicate(true)
	old_low.path = "original"
	old_low.canonical_identity.slots = 1
	var original := {"canonical_identity":identity.stream_identity(),"bytes":old_low.bytes,"triangles":2,
		"game_sources":PackedInt32Array(),"mapping":[["original",0],[keys.common,0],[keys.common,1]],
		"components":{"original":old_low,keys.common:physical[keys.common]}}
	var proof := {"canonical_identity":original.canonical_identity,"original_low":["original",0],"component":keys.pair,
		"full_low_bounds":roof.get_aabb().merge(wall.get_aabb()),"wall_faces":1,"roof_faces":1,"full_low_faces":2,
		"original_low_bytes":old_low.bytes,"split_bytes":old_low.bytes}
	var row := Mapping.replace_row(original,proof,physical)
	return {"pages":{"full":row},"original":original,"proof":proof,"physical":physical,"native":native,"keys":keys}


static func checks() -> Array[bool]:
	var f := fixture()
	var results: Array[bool] = [not f.pages.full.is_empty(),Mapping.replace_row({}, {}, {}).is_empty()]
	var catalogs := [Mapping.CATALOG_SHA,Mapping.NORTH_CATALOG_SHA,Mapping.NORTHWEST_CATALOG_SHA,Mapping.COMBINED_CATALOG_SHA]
	var manifests := [Mapping.MANIFEST_SHA,Mapping.NORTH_MANIFEST_SHA,Mapping.NORTHWEST_MANIFEST_SHA,Mapping.COMBINED_MANIFEST_SHA]
	for a in catalogs.size():
		for b in manifests.size():
			results.append(Mapping.paired_identity(catalogs[a],manifests[b])==(a==b))
	results.append(not Mapping.paired_identity("","") and not Mapping.paired_identity("x".repeat(64),Mapping.NORTHWEST_MANIFEST_SHA))
	var larger_physical: Dictionary = f.physical.duplicate(true)
	larger_physical[f.keys.pair].bytes+=24
	var larger_proof: Dictionary = f.proof.duplicate(true)
	larger_proof.split_bytes+=24
	var larger := Mapping.replace_row(f.original,larger_proof,larger_physical)
	results.append(not larger.is_empty() and larger.bytes==f.original.bytes+24 and larger.components[f.keys.pair].bytes==larger_proof.split_bytes)
	results.append(Mapping.replace_row(f.original,f.proof,larger_physical).is_empty())
	for scale_value: float in [-1.0,0.0,INF,NAN]:
		results.append(Binding.fade_for_scale(scale_value) == 0.0)
	results.append(Binding.fade_for_scale(0.18) == 1.0 and Binding.fade_for_scale(0.32) == 1.0)
	results.append(is_equal_approx(Binding.fade_for_scale(0.4),0.5))
	results.append(Binding.fade_for_scale(0.48) == 0.0 and Binding.fade_for_scale(2.0) == 0.0)
	for key: String in ["full_low_faces","split_bytes","original_low_bytes"]:
		var bad: Dictionary = f.proof.duplicate(true)
		bad[key] = int(bad[key])+1
		results.append(Mapping.replace_row(f.original,bad,f.physical).is_empty())
	var bad: Dictionary = f.proof.duplicate(true)
	bad.component = "missing"
	results.append(Mapping.replace_row(f.original,bad,f.physical).is_empty())
	bad = f.proof.duplicate(true)
	bad.canonical_identity.source = "wrong"
	results.append(Mapping.replace_row(f.original,bad,f.physical).is_empty())
	results.append(Mapping.read("missing",Mapping.CATALOG_SHA,f.pages).is_empty())
	results.append(Mapping.read("missing",Mapping.NORTH_CATALOG_SHA,f.pages).is_empty())
	var owner := Node.new()
	var stream := Stream.new()
	stream.configure(owner,f.pages)
	stream._cache = f.native.duplicate()
	stream._bytes = int(f.original.bytes)
	var page: Resource = stream.resource("full")
	results.append(page != null and page.valid() and page.stream_identity() == f.original.canonical_identity)
	if page != null:
		results.append(page.meshes[0] == f.native[f.keys.pair].meshes[0] and page.low_wall_mesh == f.native[f.keys.pair].meshes[1])
		page.low_full_faces += 1
		results.append(not page.valid())
	stream._views.clear()
	stream._cache.erase(f.keys.pair)
	results.append(stream.resource("full") == null)
	stream.close()
	stream.free()
	owner.free()
	return results


static func lifecycle(parent: Node) -> int:
	var directory := ProjectSettings.globalize_path("res://tmp/low_wall_fixture_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return 1
	var f := fixture(directory)
	if f.is_empty():
		return 1
	# 丢弃制作引用；之后只允许真实Stream/逻辑页/节点持有网格。
	f.native.clear()
	var owner := Node3D.new()
	parent.add_child(owner)
	var roof_node := MeshInstance3D.new()
	owner.add_child(roof_node)
	var wall_node := Binding.create_slot(roof_node)
	var stream := Stream.new()
	parent.add_child(stream)
	stream.configure(owner,f.pages)
	stream.request(PackedStringArray(["full"]),PackedStringArray())
	var deadline := Time.get_ticks_msec()+15000
	while stream.resource("full") == null and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	if stream.resource("full") == null:
		owner.queue_free()
		return 1
	var batch := {"building":stream.resource("full"),"nodes":[roof_node],"boxes":[AABB()],"layer_triangles":[1]}
	roof_node.mesh = batch.building.meshes[0]
	Binding.bind(batch,wall_node)
	var wall_ref: WeakRef = weakref(wall_node.mesh)
	var page_ref: WeakRef = weakref(batch.building)
	var stream_ref: WeakRef = weakref(stream)
	var fail := int(Binding.faces(batch) != 1 or batch.layer_triangles[0] != 2 or roof_node.custom_aabb != f.proof.full_low_bounds)
	for mix_value: float in [1.0,0.5,0.0,1.0,0.0]:
		Binding.apply_fade(batch,mix_value)
		await parent.get_tree().process_frame
		fail += int(Binding.faces(batch) != int(mix_value < 1.0))
		fail += int(batch.layer_triangles[0] != (2 if mix_value < 1.0 else 1))
		fail += int(batch.low_full_triangles != 2 or not roof_node.visible or roof_node.mesh != batch.building.meshes[0])
		fail += int(roof_node.custom_aabb != f.proof.full_low_bounds or wall_node.mesh != wall_ref.get_ref())
	roof_node.hide()
	await parent.get_tree().process_frame
	fail += int(wall_node.is_visible_in_tree() or Binding.faces(batch) != 0)
	roof_node.show()
	await parent.get_tree().process_frame
	fail += int(not wall_node.is_visible_in_tree())
	Binding.clear(batch)
	roof_node.mesh = null
	batch.clear()
	stream.request(PackedStringArray(),PackedStringArray())
	await parent.get_tree().process_frame
	fail += int(is_instance_valid(wall_ref.get_ref()) or is_instance_valid(page_ref.get_ref()) or wall_node.mesh != null)
	# 确认新请求已进入在途队列，再经真实owner退出回收。
	stream.request(PackedStringArray(["full"]),PackedStringArray())
	stream._process_stream()
	var pending := not stream._pending.is_empty()
	owner.queue_free()
	deadline = Time.get_ticks_msec()+15000
	while is_instance_valid(stream_ref.get_ref()) and Time.get_ticks_msec()<deadline:
		await parent.get_tree().process_frame
	fail += int(not pending or is_instance_valid(stream_ref.get_ref()))
	for path: String in f.physical:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("[R188 low wall lifecycle] fade_endpoints=true pending=",pending," fail=",fail)
	return fail
