extends RefCounted
## 完整楼体/地表局部实装：固定已就绪网格随相机移动，不是全图流送或FPS门。
const Builder := preload("res://scripts/tests/tokyo_selectable_geometry_save.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd")
const Compare := preload("res://scripts/tests/tokyo_layered_roof_review.gd")

static func run(parent: Node, input: Dictionary) -> int:
	if DisplayServer.get_name()=="headless" or input.poses.size()!=24:return 1
	if int(input.native_candidate.capacity)>240000 or int(input.native_control.capacity)>240000:return 1
	var control: ArrayMesh=Builder.build(input.native_control)
	var candidate: ArrayMesh=Builder.build(input.native_candidate)
	if control==null or candidate==null:return 1
	var channels: Dictionary=candidate.get("_surfaces")[0]
	var payload := 0
	for key: String in ["vertex_data","attribute_data","skin_data","index_data"]:
		var data: PackedByteArray=channels.get(key,PackedByteArray());payload+=data.size()
	channels.clear()
	var viewport := SubViewport.new();viewport.size=Vector2i(1600,900);viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_2X;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;parent.add_child(viewport)
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=10000;viewport.add_child(camera)
	var basis := MapProjection.camera_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var ground := MapProjection.ground_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=.8;sun.shadow_enabled=false;viewport.add_child(sun)
	var material := ShaderMaterial.new();material.shader=Shader.new();material.shader.code=Surface.native_code()
	var node := MeshInstance3D.new();node.transform=Transform3D(ground,Vector3.ZERO);node.mesh=candidate;node.material_override=material;viewport.add_child(node)
	var output: String=input.output;DirAccess.make_dir_recursive_absolute(output)
	var rows: Array=[];var success := true
	for pose: Dictionary in input.poses:
		camera.size=900.0/float(pose.scale)
		camera.transform=Transform3D(basis,ground*Vector3(pose.x,0,pose.z)+basis.z*3000)
		await RenderingServer.frame_post_draw
		var immediate: Image=viewport.get_texture().get_image()
		for frame in 2:await RenderingServer.frame_post_draw
		var stable: Image=viewport.get_texture().get_image()
		var diff := Compare.difference(immediate,stable)
		success=success and int(diff.changed_pixels)==0
		rows.append({"pose":pose,"immediate_stable":diff})
		if rows.size() in [1,7,13,19]:
			success=stable.save_png(output.path_join(str(pose.name)+"_candidate.png"))==OK and success
	# 同位原生控制与空白负对照，不能以空白帧相等当成功。
	var candidate_image: Image=viewport.get_texture().get_image()
	node.mesh=control
	for frame in 3:await RenderingServer.frame_post_draw
	var control_image: Image=viewport.get_texture().get_image()
	success=control_image.save_png(output.path_join("last_control.png"))==OK and success
	success=candidate_image.save_png(output.path_join("last_candidate.png"))==OK and success
	node.mesh=null
	for frame in 3:await RenderingServer.frame_post_draw
	var blank: Image=viewport.get_texture().get_image()
	var visible := Compare.difference(candidate_image,blank)
	var appearance := Compare.difference(control_image,candidate_image)
	success=success and int(visible.changed_pixels)>0
	var refs: Array=[weakref(control),weakref(candidate),weakref(material)]
	node.material_override=null;control=null;candidate=null;material=null
	viewport.queue_free();await parent.get_tree().process_frame;await parent.get_tree().process_frame
	var live := 0
	for ref: WeakRef in refs:
		if ref.get_ref()!=null:live+=1
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify({"rows":rows,"candidate_packed_bytes":payload,"three_copies":payload*3,"candidate_faces":input.native_candidate.capacity,"control_faces":input.native_control.capacity,"negative_control":visible,"last_control_difference":appearance,"remaining_resources":live,"vsync":DisplayServer.window_get_vsync_mode(),"msaa":"2x","capture_success":success,"source_scope":input.scope,"full_map_qualified":false,"peak_qualified":false,"performance_qualified":false},"\t"));file.close()
	return 0 if success and live==0 else 1
