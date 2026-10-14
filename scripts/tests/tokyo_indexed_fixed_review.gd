extends RefCounted
## 全图地表编码的有限GL对照；不启用正式地图，不作为实战帧时通过。
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")


static func run(tree: SceneTree, root: String, output: String) -> int:
	if DisplayServer.get_name()=="headless" or not root.is_absolute_path() or not output.begins_with(root.trim_suffix("/")+"/r359-") or DirAccess.dir_exists_absolute(output):
		return 1
	var source_dir := root.path_join("r345-detail_06_05-layers-a")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_dir.path_join("manifest.json")))
	var row: Dictionary = source.layers[2]
	var source_path := source_dir.path_join("layer_2.res")
	if FileAccess.get_sha256(source_path)!=row.mesh_sha256:
		return 1
	var native_mesh: ArrayMesh = ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if native_mesh==null:
		return 1
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color(.2,.24,.21)
	viewport.add_child(world)
	var city := Node3D.new()
	viewport.add_child(city)
	var native := MeshInstance3D.new()
	native.mesh=native_mesh
	var material := ShaderMaterial.new()
	material.shader=Shader.new()
	material.shader.code="shader_type spatial; render_mode unshaded,cull_disabled; void fragment(){ALBEDO=COLOR.rgb;}"
	native.material_override=material
	city.add_child(native)
	var shader := Shader.new()
	shader.code="shader_type spatial; render_mode unshaded,cull_disabled; uniform sampler2D categories:filter_nearest,repeat_disable; uniform vec4 palette[32]; void fragment(){int index=int(round(texture(categories,UV).r*255.0)); if(index==0){discard;} ALBEDO=palette[index].rgb;}"
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	camera.current=true
	DirAccess.make_dir_recursive_absolute(output)
	var reports: Array[Dictionary] = []
	var failure := 0
	for step: int in [8,4,2]:
		var directory := root.path_join("r359-detail_06_05-indexed-fixed-step%d" % step)
		var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
		if plan.get("source_sha256")!=row.attributes_sha256 or plan.get("step")!=step or plan.get("palette",[]).size()>31:
			failure=1
			break
		var palette := PackedColorArray()
		palette.resize(32)
		for index in plan.palette.size():
			var color: Array = plan.palette[index]
			palette[index+1]=Color(color[1],color[2],color[3],color[4])
		var planes: Array[MeshInstance3D] = []
		var bytes := 0
		for layer: Dictionary in plan.rows:
			var path := directory.path_join(layer.file)
			var raw := FileAccess.get_file_as_bytes(path)
			if FileAccess.get_sha256(path)!=layer.sha256 or raw.size()!=int(layer.width)*int(layer.height):
				failure=1
				break
			bytes+=raw.size()
			var plane := MeshInstance3D.new()
			var mesh := PlaneMesh.new()
			mesh.size=Vector2(plan.bounds[2]-plan.bounds[0],plan.bounds[3]-plan.bounds[1])
			plane.mesh=mesh
			plane.position=Vector3((plan.bounds[0]+plan.bounds[2])*.5,layer.plane_height,(plan.bounds[1]+plan.bounds[3])*.5)
			var candidate := ShaderMaterial.new()
			candidate.shader=shader
			candidate.set_shader_parameter("palette",palette)
			candidate.set_shader_parameter("categories",ImageTexture.create_from_image(Image.create_from_data(int(layer.width),int(layer.height),false,Image.FORMAT_R8,raw)))
			plane.material_override=candidate
			plane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			city.add_child(plane)
			planes.append(plane)
		var scale_value := .7776/step
		for angle: float in [0.0,14.0]:
			var canvas := Transform2D(deg_to_rad(angle),Vector2.ZERO)
			var ground := MapProjection.ground_basis(canvas,deg_to_rad(38.0))
			var basis := MapProjection.camera_basis(canvas,deg_to_rad(38.0))
			city.basis=ground
			camera.size=720.0/scale_value
			camera.transform=Transform3D(basis,ground*Vector3(-3300,0,-4700)+basis.z*50000.0)
			camera.near=30000.0
			camera.far=70000.0
			for original in [true,false]:
				native.visible=original
				for plane: MeshInstance3D in planes:
					plane.visible=not original
				for frame in 3:
					await RenderingServer.frame_post_draw
				var file := "step%d_rot%d_%s.png" % [step,roundi(angle),"native" if original else "indexed"]
				failure+=int(viewport.get_texture().get_image().save_png(output.path_join(file))!=OK)
				reports.append({"file":file,"step":step,"scale":scale_value,"angle":angle,"native":original,"texture_bytes":bytes})
		for plane: MeshInstance3D in planes:
			plane.queue_free()
		await tree.process_frame
	viewport.queue_free()
	await tree.process_frame
	var report := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if report==null:
		return 1
	report.store_string(JSON.stringify({"rows":reports,"fail":failure,"source_mesh_sha256":row.mesh_sha256,"native_faces":59777,"candidate_faces":4,"tilt":38,"game_integration":false,"performance_verified":false}))
	report.close()
	return failure
