extends RefCounted
## 实际分页和完整根网格同位GPU读回；参考网格额外加载，不作性能/内存成绩。
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Bundle := preload("res://scripts/rendering/tokyo_partition_bundle.gd")


static func compare(parent: Node, stream: Node, cut: Dictionary, partition: Dictionary, pose: Dictionary, output: String) -> Dictionary:
	if DisplayServer.get_name()=="headless" or DirAccess.dir_exists_absolute(output): return {}
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return {}
	var reference: Array[ArrayMesh]=[]
	var root: Dictionary=partition.pages[partition.tree.path]
	if partition.get("schema")==3:
		var binding: Dictionary=root.bundle
		if FileAccess.get_sha256(binding.path)!=binding.sha256: return {}
		var value: Resource=ResourceLoader.load(binding.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not value is Bundle or not value.valid() or value.stream_identity()!=binding.canonical_identity: return {}
		reference.assign(value.meshes)
	for layer: Dictionary in partition.pages[partition.tree.path].layers:
		if partition.get("schema")==3: break
		if FileAccess.get_sha256(layer.path)!=layer.sha256: return {}
		var resource: Resource=ResourceLoader.load(layer.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not resource is Component or not resource.valid() or resource.stream_identity()!=layer.canonical_identity: return {}
		reference.append(resource.meshes[0])
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1600,900)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var canvas := Transform2D(float(pose.rotation),Vector2.ZERO)
	var basis := MapProjection.camera_basis(canvas,deg_to_rad(38))
	var ground := MapProjection.ground_basis(canvas,deg_to_rad(38))
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.far=10000
	camera.size=900/float(pose.scale)
	var center := ground*Vector3(pose.center[0],0,pose.center[1])
	camera.transform=Transform3D(basis,center+basis.z*3000)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-35,0)
	sun.light_energy=.8
	sun.shadow_enabled=false
	viewport.add_child(sun)
	var materials: Array[ShaderMaterial]=[]
	for kind in 3:
		var material := ShaderMaterial.new()
		material.shader=preload("res://resources/shaders/tokyo_volume_surface.gdshader")
		material.set_shader_parameter("facade_detail",kind==1)
		materials.append(material)
	var full_nodes: Array[MeshInstance3D]=[]
	var selected_nodes: Array[MeshInstance3D]=[]
	for kind in 3: full_nodes.append(add_mesh(viewport,reference[kind],ground,materials[kind]))
	for entry: Dictionary in cut.entries:
		var page: Resource=stream.resource(entry.path)
		if page==null:
			viewport.queue_free()
			await parent.get_tree().process_frame
			return {}
		for kind in 3:
			if entry.mask[kind]:
				var node := add_mesh(viewport,page.meshes[kind],ground,materials[kind])
				node.visible=false
				selected_nodes.append(node)
	for frame in 3: await RenderingServer.frame_post_draw
	var full := viewport.get_texture().get_image()
	for node in full_nodes: node.visible=false
	for node in selected_nodes: node.visible=true
	for frame in 3: await RenderingServer.frame_post_draw
	var selected := viewport.get_texture().get_image()
	# 负对照：撤掉全部候选，读回必须能发现画面缺失，防止空画面互比误过。
	for node in selected_nodes: node.visible=false
	for frame in 3: await RenderingServer.frame_post_draw
	var blank := viewport.get_texture().get_image()
	var saved := full.save_png(output.path_join("reference.png"))==OK and selected.save_png(output.path_join("selected.png"))==OK
	viewport.queue_free()
	await parent.get_tree().process_frame
	if not saved: return {}
	full.convert(Image.FORMAT_RGBA8)
	selected.convert(Image.FORMAT_RGBA8)
	blank.convert(Image.FORMAT_RGBA8)
	var a := full.get_data()
	var b := selected.get_data()
	var c := blank.get_data()
	var different := 0
	var blank_difference := 0
	var largest := 0
	for i in range(0,a.size(),4):
		var delta := 0
		var blank_delta := 0
		for channel in 4: delta=maxi(delta,absi(int(a[i+channel])-int(b[i+channel])))
		for channel in 4: blank_delta=maxi(blank_delta,absi(int(a[i+channel])-int(c[i+channel])))
		different+=int(delta>0)
		blank_difference+=int(blank_delta>0)
		largest=maxi(largest,delta)
	return {"different_pixels":different,"blank_control_pixels":blank_difference,"max_channel_delta":largest,"pixels":full.get_width()*full.get_height(),
		"reference_sha256":a.hex_encode().sha256_text(),"selected_sha256":b.hex_encode().sha256_text(),
		"selected_nodes":selected_nodes.size(),"performance_accepted":false,"runtime_integrated":false}


static func add_mesh(viewport: SubViewport, mesh: ArrayMesh, ground: Basis, material: ShaderMaterial) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh=mesh
	node.basis=ground
	node.material_override=material
	viewport.add_child(node)
	return node
