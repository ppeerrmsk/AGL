extends RefCounted
## 完整失败视野同位GPU对照；固定容量全部计费，不授予正式资格。
const Helper := preload("res://scripts/tests/tokyo_layered_roof_review.gd")
const Add := preload("res://scripts/tests/tokyo_partition_render_probe.gd")
const Surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd")
const ProjectionMap := preload("res://scripts/experiments/volume_projection.gd")
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")

static func run(parent: Node,input: Dictionary) -> int:
	if DisplayServer.get_name()=="headless": return 1
	for binding: Dictionary in [input.index_hybrid_review,input.textures,input.source]:
		if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.index_hybrid_review.path))
	var textures: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.textures.path))
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.source.path))
	if manifest.source_sha256!=input.source.sha256 or textures.selection_sha256!=input.index_hybrid_review.sha256:return 1
	var output: String=input.output
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output):return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK:return 1
	var viewport := SubViewport.new();viewport.size=Vector2i(1600,900);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;parent.add_child(viewport)
	var basis := ProjectionMap.camera_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var ground := ProjectionMap.ground_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var camera := Camera3D.new();viewport.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=10000
	camera.size=900.0/float(manifest.pose[2])
	camera.transform=Transform3D(basis,ground*Vector3(manifest.pose[0],0,manifest.pose[1])+basis.z*3000)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=.8;sun.shadow_enabled=false;viewport.add_child(sun)
	var material := ShaderMaterial.new();material.shader=Shader.new();material.shader.code=Surface.native_code()
	var originals: Array[MeshInstance3D]=[];var rebuilt: Array[MeshInstance3D]=[];var candidates: Array[MeshInstance3D]=[]
	var culled: Array[MeshInstance3D]=[];var pure: Dictionary={};var pure_faces := 0
	if input.has("pure_cut"):
		if FileAccess.get_sha256(input.pure_cut.path)!=input.pure_cut.sha256:return 1
		pure=JSON.parse_string(FileAccess.get_file_as_string(input.pure_cut.path))
		if pure.source_sha256!=manifest.source_sha256 or pure.pose!=manifest.pose:return 1
	for entry: Dictionary in source.samples[0].triangle_cost.exports:
		if FileAccess.get_sha256(entry.source.path)!=entry.source.sha256:return 1
		var resource: Resource=load(entry.source.path)
		if resource==null or not resource.valid():return 1
		originals.append(Add.add_mesh(viewport,resource.meshes[int(entry.slot)],ground,material))
	var native_bytes := 0;var index_capacity := 0;var upload_bytes := 0
	for row: Dictionary in manifest.rows:
		if FileAccess.get_sha256(row.attributes)!=row.attributes_sha256 or FileAccess.get_sha256(row.indices)!=row.indices_sha256:return 1
		var full := Helper.mesh_from_bytes(FileAccess.get_file_as_bytes(row.attributes))
		rebuilt.append(Add.add_mesh(viewport,full,ground,material))
		var arrays := full.surface_get_arrays(0)
		if not pure.is_empty():
			var pure_row: Dictionary=pure.rows[int(row.kind)]
			if pure_row.attributes_sha256!=row.attributes_sha256 or FileAccess.get_sha256(pure_row.indices)!=pure_row.indices_sha256:return 1
			var pure_arrays := arrays.duplicate()
			var pure_indices := FileAccess.get_file_as_bytes(pure_row.indices).to_int32_array()
			pure_arrays[Mesh.ARRAY_INDEX]=pure_indices;pure_faces+=pure_indices.size()/3
			var pure_mesh := ArrayMesh.new();pure_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,pure_arrays)
			culled.append(Add.add_mesh(viewport,pure_mesh,ground,material))
		var bytes := FileAccess.get_file_as_bytes(row.indices)
		var selected := bytes.to_int32_array()
		var count := selected.size()
		if int(row.kind)==0:count+=int(manifest.remaining_capacity_faces)*3
		selected.resize(count)
		var empty_indices := PackedInt32Array();empty_indices.resize(count);arrays[Mesh.ARRAY_INDEX]=empty_indices
		var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		RenderingServer.call("mesh_surface_update_index_region",mesh.get_rid(),0,0,selected.to_byte_array())
		native_bytes+=Packed.decoded_bytes(mesh);index_capacity+=count;upload_bytes+=selected.to_byte_array().size()
		candidates.append(Add.add_mesh(viewport,mesh,ground,material))
	var texture_bytes := 0;var plane_bytes := 0
	for row: Dictionary in textures.rows:
		if FileAccess.get_sha256(row.path)!=row.sha256:return 1
		var image := Image.load_from_file(row.path)
		if image==null or image.generate_mipmaps()!=OK:return 1
		texture_bytes+=image.get_data_size()*3
		var g: Array=row.geometry_bounds;var t: Array=row.texture_bounds
		var footprint := Rect2(g[0],g[1],g[2]-g[0],g[3]-g[1]);var bounds := Rect2(t[0],t[1],t[2]-t[0],t[3]-t[1])
		var uv := Rect2((footprint.position-bounds.position)/bounds.size,footprint.size/bounds.size)
		var mat := ShaderMaterial.new();mat.shader=Shader.new();mat.shader.code=Surface.textured_code().replace("sample_color.a<0.001","sample_color.a<0.5")
		mat.set_shader_parameter("overview",ImageTexture.create_from_image(image))
		var mesh := preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd").plane(footprint,uv)
		plane_bytes+=Packed.decoded_bytes(mesh)
		var node := Add.add_mesh(viewport,mesh,ground,mat);node.position=ground*Vector3(0,row.height,0);candidates.append(node)
	var groups: Array=[originals,rebuilt,candidates,[]];var names := ["original","rebuilt","candidate","blank"]
	if not pure.is_empty():groups.append(culled);names.append("culled_native")
	var pictures: Array[Image]=[]
	for phase in groups.size():
		for group: Array in [originals,rebuilt,candidates,culled]:
			for node: MeshInstance3D in group:node.visible=false
		for node: MeshInstance3D in groups[phase]:node.visible=true
		for frame in 3:await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image();pictures.append(image)
		if image.save_png(output.path_join(names[phase]+".png"))!=OK:return 1
	var result := {"rebuild_difference":Helper.difference(pictures[0],pictures[1]),"candidate_difference":Helper.difference(pictures[0],pictures[2]),
		"negative_control":Helper.difference(pictures[0],pictures[3]),"submitted_capacity_faces":index_capacity/3+textures.rows.size()*2,
		"native_decoded_bytes":native_bytes,"plane_decoded_bytes":plane_bytes,"texture_three_copy_bytes":texture_bytes,"index_upload_bytes":upload_bytes,
		"candidate_instances":candidates.size(),"visual_accepted":false,"performance_accepted":false,"runtime_integrated":false}
	if not pure.is_empty():
		result["pure_cut_faces_diagnostic_only"]=pure_faces
		result["pure_cut_difference"]=Helper.difference(pictures[1],pictures[4])
		result["texture_replacement_difference"]=Helper.difference(pictures[4],pictures[2])
	viewport.queue_free();await parent.get_tree().process_frame
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	return 0 if int(result.negative_control.changed_pixels)>0 and int(result.submitted_capacity_faces)==240000 else 1
