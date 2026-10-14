extends RefCounted
## 真实GL视口纹理A/B；独立采样夹具，不冒充正式地图接合。


static func run(tree: SceneTree, root: String, output: String) -> int:
	if DisplayServer.get_name()=="headless" or DirAccess.dir_exists_absolute(output):
		return 1
	var source := root.path_join("r286-layered-fixed-a")
	var packed_root := root.path_join("r287-layered-bc3-a")
	var packed_sha := "2872d9c263477becd6af4bdf1ca82b3c24646a0b379a460b33d6a9ee9d3d42a8"
	if OS.get_environment("AGL_TOKYO_LAYERED_MIP_FIX")=="1":
		packed_root=root.path_join("r288-layered-bc3-b")
		packed_sha="83eafb11b8f1b3843d1787650db73f0abfb520f11df91c096acd8753203f3880"
	if FileAccess.get_sha256(source.path_join("manifest.json"))!="a23d5fc131f93a33ae55bc6384203e438abc968a19fc5bdb88797c0ffb7bd1d8" or FileAccess.get_sha256(packed_root.path_join("report.json"))!=packed_sha:
		return 1
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("manifest.json")))
	var compressed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(packed_root.path_join("report.json")))
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size=Vector2i(512,512)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color(.20,.24,.21)
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.position=Vector3(0,0,10)
	camera.far=50
	viewport.add_child(camera)
	camera.current=true
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	quad.mesh=mesh
	quad.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code="shader_type spatial; render_mode unshaded, cull_disabled; uniform sampler2D source_tex: filter_linear_mipmap, repeat_disable; void fragment(){ vec4 c=texture(source_tex,UV); ALBEDO=c.rgb/max(c.a,0.00001); ALPHA=c.a; }"
	material.shader=shader
	quad.material_override=material
	viewport.add_child(quad)
	var rows: Array[Dictionary] = []
	var fail := 0
	for n in manifest.rows.size():
		var info: Dictionary = manifest.rows[n]
		var packed_info: Dictionary = compressed.rows[n]
		var raw_path := source.path_join(info.file)
		var packed_path := packed_root.path_join(packed_info.file)
		if FileAccess.get_sha256(raw_path)!=info.sha256 or FileAccess.get_sha256(packed_path)!=packed_info.sha256:
			fail+=1
			break
		var original := Image.load_from_file(raw_path)
		original.convert(Image.FORMAT_RGBA8)
		fail+=int(original.generate_mipmaps()!=OK)
		var bytes := FileAccess.get_file_as_bytes(packed_path)
		if bytes.size()!=int(packed_info.actual_bytes):
			fail+=1
			break
		var packed := Image.create_from_data(int(info.width),int(info.height),true,Image.FORMAT_DXT5,bytes)
		var textures := [ImageTexture.create_from_image(original),ImageTexture.create_from_image(packed)]
		mesh.size=Vector2(float(info.width),float(info.height))*float(info.world_step)
		for scale_value: float in [.20,.3888]:
			camera.size=512.0/scale_value
			for variant in 2:
				material.set_shader_parameter("source_tex",textures[variant])
				for frame in 3:
					await RenderingServer.frame_post_draw
				var file := "%s_step%d_scale%d_%s.png"%[info.layer,int(info.world_step),roundi(scale_value*10000),"raw" if variant==0 else "bc3"]
				fail+=int(viewport.get_texture().get_image().save_png(output.path_join(file))!=OK)
			rows.append({"layer":info.layer,"step":info.world_step,"scale":scale_value,"actual_bc3_bytes":bytes.size()})
	viewport.queue_free()
	await tree.process_frame
	var report := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"rows":rows,"fail":fail,"headless":false,"godot":Engine.get_version_info().string,"texture_sampling_only":true,"map_integration_verified":false},"\t"))
	report.close()
	return fail
