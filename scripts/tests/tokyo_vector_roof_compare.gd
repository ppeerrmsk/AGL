extends RefCounted
## 仅样块同位截图；像素差异不是自动美术验收或性能证据。
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd")
const Compare := preload("res://scripts/tests/tokyo_layered_roof_review.gd")

static func run(parent: Node, input: Dictionary) -> int:
	if input.get("native_joint_patch",false):
		return await preload("res://scripts/tests/tokyo_native_joint_preview.gd").run(parent,input)
	if DisplayServer.get_name()=="headless": return 1
	for key: String in ["positions","indices","candidate"]:
		var binding: Dictionary=input[key]
		if FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var packed := FileAccess.get_file_as_bytes(input.positions.path).to_float32_array()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for offset in range(0,packed.size(),3):
		vertices.append(Vector3(packed[offset],packed[offset+1],packed[offset+2]))
		normals.append(Vector3.UP)
		colors.append(Color(176.0/255,177.0/255,169.0/255,1))
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=FileAccess.get_file_as_bytes(input.indices.path).to_int32_array()
	var original := ArrayMesh.new();original.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var encoded: Dictionary={}
	var candidate: ArrayMesh
	if input.get("local_roof_gpu",false):
		encoded=preload("res://scripts/tests/tokyo_local_roof_gpu.gd").build(input,original.get_aabb())
		candidate=encoded.get("mesh")
	else: candidate=ResourceLoader.load(input.candidate.path,"ArrayMesh",ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	if candidate==null: return 1
	var viewport := SubViewport.new();viewport.size=Vector2i(1600,900)
	viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_2X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;parent.add_child(viewport)
	var basis := MapProjection.camera_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var ground := MapProjection.ground_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=10000
	viewport.add_child(camera)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=.8;sun.shadow_enabled=false;viewport.add_child(sun)
	var double_sided: bool=input.get("diagnostic_double_sided",false)
	var material := ShaderMaterial.new();material.shader=Shader.new();material.shader.code=Surface.native_code()
	if double_sided: material.shader.code=material.shader.code.replace("specular_disabled;","specular_disabled, cull_disabled;")
	var node := MeshInstance3D.new();node.transform=Transform3D(ground,Vector3.ZERO);node.material_override=material;viewport.add_child(node)
	var output: String=input.output;DirAccess.make_dir_recursive_absolute(output)
	var rows: Array=[];var success := true
	for pose: Dictionary in input.poses:
		camera.size=900.0/float(pose.scale)
		camera.transform=Transform3D(basis,ground*Vector3(pose.x,0,pose.z)+basis.z*3000)
		var images: Array[Image]=[]
		for phase in 3:
			node.mesh=original if phase==0 else (candidate if phase==1 else null)
			node.material_override=encoded.get("material",material) if phase==1 else material
			for frame in 3: await RenderingServer.frame_post_draw
			images.append(viewport.get_texture().get_image())
		var prefix := output.path_join(str(pose.name))
		success=images[0].save_png(prefix+"_original.png")==OK and success
		success=images[1].save_png(prefix+"_candidate.png")==OK and success
		var negative := Compare.difference(images[0],images[2])
		success=success and int(negative.changed_pixels)>0
		rows.append({"pose":pose,"difference":Compare.difference(images[0],images[1]),"negative_control":negative})
	var costs: Dictionary={}
	var refs: Array=[weakref(original),weakref(candidate),weakref(material)]
	if not encoded.is_empty():
		refs.append(weakref(encoded.material));refs.append(weakref(encoded.texture))
		costs={"channels":encoded.costs,"table_bytes":encoded.table_bytes,"three_payload_copies":encoded.three_payload_copies,"metadata_upload_peak_verified":false}
	encoded.clear()
	node.mesh=null;node.material_override=null;original=null;candidate=null;material=null
	viewport.queue_free();await parent.get_tree().process_frame;await parent.get_tree().process_frame
	var live := 0
	for ref: WeakRef in refs:
		if ref.get_ref()!=null: live+=1
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"rows":rows,"encoded_costs":costs,"capture_success":success,"diagnostic_double_sided":double_sided,"source_winding_requires_review":double_sided,"remaining_mesh_material_resources":live,"vsync":DisplayServer.window_get_vsync_mode(),"msaa":"2x","scope":input.get("scope","detail_00_00 authorized group roofs only"),"visual_accepted":false,"performance_accepted":false,"full_map_accepted":false},"\t"))
	file.close()
	return 0 if success and live==0 else 1
