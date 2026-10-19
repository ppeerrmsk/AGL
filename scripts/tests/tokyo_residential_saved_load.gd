extends RefCounted
## 只消费已保存资源；禁止在加载路径展开顶点或重建几何。不接正式入口。
const Audit := preload("res://scripts/tests/tokyo_residential_packet_audit.gd")
const Sparse := preload("res://scripts/tests/tokyo_sparse_mip_sampler.gd")

static func load_saved(input: Dictionary) -> Dictionary:
	var request: Dictionary=input.residential_saved_load
	if FileAccess.get_sha256(request.packet.path)!=request.packet.sha256:return {}
	var packet: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(request.packet.path))
	var meshes: Array[ArrayMesh]=[];var probes: Array[WeakRef]=[]
	var packed_bytes := 0;var largest_file := 0
	for binding: Dictionary in request.meshes:
		if FileAccess.get_sha256(binding.path)!=binding.sha256:return {}
		var mesh: ArrayMesh=ResourceLoader.load(binding.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if mesh==null or mesh.get_surface_count()!=1:return {}
		meshes.append(mesh);probes.append(weakref(mesh))
		largest_file=maxi(largest_file,int(binding.bytes))
		# _surfaces为打包数据，不调用surface_get_arrays生成展开副本。
		for surface: Dictionary in mesh.get("_surfaces"):
			for key in ["vertex_data","attribute_data","skin_data","index_data"]:
				packed_bytes+=surface.get(key,PackedByteArray()).size()
	var indices: Array[PackedByteArray]=[];var index_bytes := 0
	for row: Dictionary in packet.rows:
		var data := Audit.bytes(row.indices)
		if data.is_empty():return {}
		indices.append(data);index_bytes+=data.size()
	var materials: Array[ShaderMaterial]=[];var texture_bytes := 0
	for binding: Dictionary in packet.texture_bindings:
		var batch := Sparse.build(binding)
		if batch.is_empty():return {}
		materials.append(batch.material);probes.append(weakref(batch.material))
		for i in 4:probes.append(weakref(batch.material.get_shader_parameter("page%d"%i)))
		texture_bytes+=int(batch.texture_three_copy_bytes)
	if meshes.size()!=3 or indices.size()!=4 or materials.size()!=2:return {}
	# 已知结构计CPU打包/GPU/上传暂存三份，另留最大压缩输入；不是驱动实测。
	var steady := packed_bytes*2+index_bytes+texture_bytes
	return {"meshes":meshes,"indices":indices,"materials":materials,"probes":probes,
		"report":{"packed_mesh_bytes":packed_bytes,"cpu_indices_bytes":index_bytes,
		"texture_three_copy_bytes":texture_bytes,"known_steady_bytes":steady,
		"known_load_charge_bytes":steady+packed_bytes+largest_file,"largest_compressed_input":largest_file,
		"decoder_internal_peak_measured":false,"driver_memory_measured":false,
		"source_vertices_expanded":false,"runtime_integrated":false,"visual_verified":false}}

static func run(parent: Node, input: Dictionary) -> int:
	if FileAccess.file_exists(input.output):return 1
	var state := load_saved(input)
	if state.is_empty():return 1
	var probes: Array=state.probes
	var report: Dictionary=state.report
	if input.has("preview_directory"):
		report["preview"]=await preview(parent,input,state)
	await parent.get_tree().process_frame
	report["live_before_release"]=live_count(probes)
	state.clear()
	for frame in 4:await parent.get_tree().process_frame
	report["live_after_release"]=live_count(probes)
	report["within_known_charge"]=int(report.known_load_charge_bytes)<=201326592
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("Tokyo saved resource lifetime: ",JSON.stringify(report))
	return 0 if report.live_before_release==13 and report.live_after_release==0 and report.within_known_charge and report.get("preview",{"passed":true}).passed else 1

static func live_count(probes: Array) -> int:
	var count := 0
	for probe: WeakRef in probes:count+=int(probe.get_ref()!=null)
	return count

static func preview(parent: Node, input: Dictionary, state: Dictionary) -> Dictionary:
	if DisplayServer.get_name()=="headless":return {"passed":false,"reason":"requires_visual"}
	var output: String=input.preview_directory
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:return {"passed":false}
	var packet: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.residential_saved_load.packet.path))
	var projection := preload("res://scripts/experiments/volume_projection.gd")
	var surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd")
	var ground := projection.ground_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var basis := projection.camera_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var viewport := SubViewport.new();viewport.size=Vector2i(1600,900);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;parent.add_child(viewport)
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=10000;viewport.add_child(camera)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=.8;viewport.add_child(sun)
	var native := ShaderMaterial.new();native.shader=Shader.new();native.shader.code=surface.native_code()
	for i in 3:
		var node := MeshInstance3D.new();node.mesh=state.meshes[i];node.transform=Transform3D(ground,Vector3.ZERO)
		# 显式分层取证只供归因；不能作为完整画面验收。
		var layer: String=input.get("diagnostic_layer","all")
		node.visible=layer=="all" or (layer=="native" and i==0) or (layer=="planes" and i>0)
		if i==0:node.material_override=native
		else:
			var material: ShaderMaterial=state.materials[i-1]
			var textures: Array=[]
			for page in 4:textures.append(material.get_shader_parameter("page%d"%page))
			material.shader.code=surface.textured_code().replace("sample_color.a<0.001","sample_color.a<0.5").replace("void fragment() {",Sparse.sampler_code()+"\nvoid fragment() {").replace("texture(overview,UV)","read_tile(UV,UV2.x)")
			for page in 4:material.set_shader_parameter("page%d"%page,textures[page])
			node.material_override=material
		viewport.add_child(node)
	if input.has("continuous_route"):
		var continuous: Dictionary=await preload("res://scripts/tests/tokyo_residential_continuous.gd").run(viewport,camera,basis,ground,input,state)
		viewport.queue_free();await parent.get_tree().process_frame
		return continuous
	var frames: Array=[];var passed := true
	for step in 12:
		var cell := step%4;var bounds: Array=packet.rows[cell].camera_bounds
		var scale_value := 0.5+float(step%3)*0.0625
		RenderingServer.call("mesh_surface_update_index_region",state.meshes[0].get_rid(),0,0,state.indices[cell])
		camera.size=900.0/scale_value
		camera.transform=Transform3D(basis,ground*Vector3((bounds[0]+bounds[2])*0.5,0,(bounds[1]+bounds[3])*0.5)+basis.z*3000)
		await RenderingServer.frame_post_draw
		var first := viewport.get_texture().get_image()
		for frame in 3:await RenderingServer.frame_post_draw
		var stable := viewport.get_texture().get_image()
		var equal := first.get_data()==stable.get_data()
		passed=passed and equal
		if stable.save_png(output.path_join("pose%02d.png"%step))!=OK:passed=false
		frames.append({"cell":cell,"scale":scale_value,"first_equals_stable":equal})
	viewport.queue_free();await parent.get_tree().process_frame
	return {"passed":passed,"poses":frames,"full_map_verified":false,"performance_verified":false}
