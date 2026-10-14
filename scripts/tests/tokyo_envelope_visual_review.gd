extends RefCounted
## 包络候选同位多姿态读回；不以截图替代连续性能验收。
const Helper := preload("res://scripts/tests/tokyo_layered_roof_review.gd")
const Add := preload("res://scripts/tests/tokyo_partition_render_probe.gd")
const Surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd")
const ProjectionMap := preload("res://scripts/experiments/volume_projection.gd")
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")

static func run(parent: Node,input: Dictionary) -> int:
	if DisplayServer.get_name()=="headless":return 1
	for binding: Dictionary in [input.envelope_visual_review,input.textures,input.source,input.native]:
		if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var packet: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.envelope_visual_review.path))
	var textures: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.textures.path))
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.source.path))
	if packet.selection_sha256!=textures.selection_sha256:return 1
	var output: String=input.output
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:return 1
	var viewport := SubViewport.new();viewport.size=Vector2i(1600,900);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;parent.add_child(viewport)
	var basis := ProjectionMap.camera_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var ground := ProjectionMap.ground_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var camera := Camera3D.new();viewport.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=10000
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=.8;sun.shadow_enabled=false;viewport.add_child(sun)
	var material := ShaderMaterial.new();material.shader=Shader.new();material.shader.code=Surface.native_code()
	var originals: Array[MeshInstance3D]=[];var candidates: Array[MeshInstance3D]=[]
	for entry: Dictionary in source.samples[0].triangle_cost.exports:
		if FileAccess.get_sha256(entry.source.path)!=entry.source.sha256:return 1
		var resource: Resource=load(entry.source.path)
		if resource==null or not resource.valid():return 1
		originals.append(Add.add_mesh(viewport,resource.meshes[int(entry.slot)],ground,material))
	var native: ArrayMesh=load(input.native.path)
	if native==null or native.surface_get_array_index_len(0)!=int(packet.native_capacity_faces)*3:return 1
	candidates.append(Add.add_mesh(viewport,native,ground,material))
	var plane_bytes := 0;var texture_bytes := 0
	for tile: Dictionary in textures.rows:
		if FileAccess.get_sha256(tile.path)!=tile.sha256:return 1
		var image := Image.load_from_file(tile.path)
		if image==null or image.generate_mipmaps()!=OK:return 1
		texture_bytes+=image.get_data_size()*3
		var g: Array=tile.geometry_bounds;var t: Array=tile.texture_bounds
		var footprint := Rect2(g[0],g[1],g[2]-g[0],g[3]-g[1]);var bounds := Rect2(t[0],t[1],t[2]-t[0],t[3]-t[1])
		var uv := Rect2((footprint.position-bounds.position)/bounds.size,footprint.size/bounds.size)
		var mat := ShaderMaterial.new();mat.shader=Shader.new();mat.shader.code=Surface.textured_code().replace("sample_color.a<0.001","sample_color.a<0.5")
		if input.has("diagnostic_lod"):
			mat.shader.code=mat.shader.code.replace("texture(overview,UV)","textureLod(overview,UV,%.1f)"%float(input.diagnostic_lod))
		if input.get("alpha_diagnostic",false):
			mat.shader.code=mat.shader.code.replace("if(sample_color.a<0.5){discard;}","").replace("vec3 base=sample_color.rgb/max(sample_color.a,0.001);","vec3 base=vec3(sample_color.a);")
		mat.set_shader_parameter("overview",ImageTexture.create_from_image(image))
		var mesh := preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd").plane(footprint,uv)
		plane_bytes+=Packed.decoded_bytes(mesh)
		var node := Add.add_mesh(viewport,mesh,ground,mat);node.position=ground*Vector3(0,tile.height,0);candidates.append(node)
	var atlas_nodes: Array[MeshInstance3D]=[];var atlas_split: Array[MeshInstance3D]=[];var atlas_data: Dictionary={}
	if input.has("atlas"):
		atlas_data=preload("res://scripts/tests/tokyo_independent_mip_batch.gd").build(input.atlas,textures)
		if atlas_data.is_empty():return 1
		atlas_nodes.append(candidates[0]);atlas_nodes.append(Add.add_mesh(viewport,atlas_data.mesh,ground,atlas_data.material))
		if input.get("split_atlas_diagnostic",false):
			atlas_split.append(candidates[0])
			for i in textures.rows.size():
				var original := candidates[i+1];var arrays := original.mesh.surface_get_arrays(0)
				var ids := PackedVector2Array();ids.resize(original.mesh.surface_get_array_len(0));ids.fill(Vector2(int(textures.rows[i].get("texture_index",i)),0))
				arrays[Mesh.ARRAY_TEX_UV2]=ids
				var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				var node := Add.add_mesh(viewport,mesh,ground,atlas_data.material);node.position=original.position;atlas_split.append(node)
	if input.get("route_first_frame",false):
		return await _route(parent,viewport,camera,basis,ground,native,packet,originals,candidates,atlas_nodes,output)
	var results: Array=[];var success := true
	for pose_id: int in input.get("pose_ids",[0,13,26]):
		var row: Dictionary=packet.rows[pose_id];var pose: Array=row.pose
		if FileAccess.get_sha256(row.indices)!=row.sha256:return 1
		var bytes := FileAccess.get_file_as_bytes(row.indices)
		if bytes.size()!=int(packet.index_bytes_per_pose):return 1
		RenderingServer.call("mesh_surface_update_index_region",native.get_rid(),0,0,bytes)
		camera.size=900.0/float(pose[2]);camera.transform=Transform3D(basis,ground*Vector3(pose[0],0,pose[1])+basis.z*3000)
		var pictures: Array[Image]=[];var groups: Array=[originals,candidates,[]];var names := ["original","candidate","blank"]
		if not atlas_nodes.is_empty():groups.append(atlas_nodes);names.append("atlas")
		if not atlas_split.is_empty():groups.append(atlas_split);names.append("atlas_split")
		for phase in groups.size():
			for group: Array in [originals,candidates,atlas_nodes,atlas_split]:
				for node: MeshInstance3D in group:node.visible=false
			for node: MeshInstance3D in groups[phase]:node.visible=true
			for frame in 3:await RenderingServer.frame_post_draw
			var picture := viewport.get_texture().get_image();pictures.append(picture)
			if picture.save_png(output.path_join("%02d_%s.png"%[pose_id,names[phase]]))!=OK:return 1
		var negative := Helper.difference(pictures[0],pictures[2]);success=success and int(negative.changed_pixels)>0
		results.append({"pose_id":pose_id,"pose":pose,"difference":Helper.difference(pictures[0],pictures[1]),"negative":negative})
		if not atlas_nodes.is_empty():results[-1]["atlas_vs_independent"]=Helper.difference(pictures[1],pictures[3])
		if not atlas_split.is_empty():
			results[-1]["sampling_only_difference"]=Helper.difference(pictures[1],pictures[4])
			results[-1]["merge_only_difference"]=Helper.difference(pictures[4],pictures[3])
	var result := {"poses":results,"native_decoded_bytes":Packed.decoded_bytes(native),"plane_decoded_bytes":plane_bytes,"texture_three_copy_bytes":texture_bytes,
		"candidate_instances":candidates.size(),"submitted_capacity_faces":int(packet.native_capacity_faces)+textures.rows.size()*2,
		"visual_accepted":false,"performance_accepted":false,"runtime_integrated":false}
	if not atlas_nodes.is_empty():
		result["atlas_instances"]=atlas_nodes.size();result["atlas_texture_three_copy_bytes"]=atlas_data.texture_three_copy_bytes
		result["atlas_plane_decoded_bytes"]=Packed.decoded_bytes(atlas_data.mesh)
	viewport.queue_free();await parent.get_tree().process_frame
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	return 0 if success and int(result.submitted_capacity_faces)==240000 else 1

static func _route(parent: Node,viewport: SubViewport,camera: Camera3D,basis: Basis,ground: Basis,native: ArrayMesh,packet: Dictionary,originals: Array[MeshInstance3D],candidates: Array[MeshInstance3D],atlas_nodes: Array[MeshInstance3D],output: String) -> int:
	if atlas_nodes.size()!=2:return 1
	var resident_indices: Dictionary={}
	var resident_index_bytes := 0
	for row: Dictionary in packet.rows:
		if resident_indices.has(row.sha256):continue
		if FileAccess.get_sha256(row.indices)!=row.sha256:return 1
		var data := FileAccess.get_file_as_bytes(row.indices)
		if data.size()!=int(packet.index_bytes_per_pose):return 1
		resident_indices[row.sha256]=data
		resident_index_bytes+=data.size()
	for group: Array in [originals,candidates]:
		for node: MeshInstance3D in group:node.visible=false
	for node: MeshInstance3D in atlas_nodes:node.visible=true
	var route: Array=packet.rows
	if packet.has("route_poses"):
		route=[]
		var ready := {"geometry_ready":true,"textures_ready":true,"vertices_sha256":packet.vertices_sha256,"selection_sha256":packet.selection_sha256,"index_identities":{}}
		for identity: String in resident_indices:ready.index_identities[identity]=true
		for pose: Array in packet.route_poses:
			var chosen := preload("res://scripts/experiments/tokyo_cell_index_selector.gd").select(packet,Vector2(pose[0],pose[1]),float(pose[2]),0,38,Vector2i(1600,900),ready)
			if chosen.is_empty():return 1
			var selected: Dictionary=packet.rows[int(chosen.leaf)].duplicate()
			if selected.sha256!=chosen.index_sha256:return 1
			selected.pose=pose;route.append(selected)
	var rows: Array=[];var success := true
	for i in route.size():
		var row: Dictionary=route[i];var pose: Array=row.pose
		var bytes: PackedByteArray=resident_indices[row.sha256]
		RenderingServer.call("mesh_surface_update_index_region",native.get_rid(),0,0,bytes)
		camera.size=900.0/float(pose[2]);camera.transform=Transform3D(basis,ground*Vector3(pose[0],0,pose[1])+basis.z*3000)
		# 相机与索引同一提交段更新，立即取下一个完成绘制的帧，不预等3帧。
		await RenderingServer.frame_post_draw
		var first := viewport.get_texture().get_image()
		for frame in 2:await RenderingServer.frame_post_draw
		var stable := viewport.get_texture().get_image();var diff := Helper.difference(first,stable)
		success=success and int(diff.changed_pixels)==0
		if first.save_png(output.path_join("%02d_first.png"%i))!=OK or stable.save_png(output.path_join("%02d_stable.png"%i))!=OK:return 1
		rows.append({"pose":pose,"certificate_leaf":row.get("certificate_leaf",-1),"first_vs_stable":diff})
	# 第二遍才显示参考，不把逐姿态参考切换混入候选连续运行序列。
	for node: MeshInstance3D in atlas_nodes:node.visible=false
	for node: MeshInstance3D in originals:node.visible=true
	for i in route.size():
		var pose: Array=route[i].pose
		camera.size=900.0/float(pose[2]);camera.transform=Transform3D(basis,ground*Vector3(pose[0],0,pose[1])+basis.z*3000)
		await RenderingServer.frame_post_draw
		var reference := viewport.get_texture().get_image()
		var first := Image.load_from_file(output.path_join("%02d_first.png"%i))
		rows[i]["reference_difference"]=Helper.difference(reference,first)
		if reference.save_png(output.path_join("%02d_reference.png"%i))!=OK:return 1
	viewport.queue_free();await parent.get_tree().process_frame
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"rows":rows,"all_first_frames_equal_stable":success,"source_reference_visual_accepted":false,
		"resident_index_resources":resident_indices.size(),"resident_index_bytes":resident_index_bytes,"route_index_file_reads":0,
		"limitations":"Indices preloaded before route. GPU screenshots serialize frames; not streaming latency, frame pacing or FPS acceptance. Reference resources also reside in diagnostic process.","full_map_accepted":false,"performance_accepted":false,"runtime_integrated":false},"\t"));file.close()
	return 0 if success else 1
