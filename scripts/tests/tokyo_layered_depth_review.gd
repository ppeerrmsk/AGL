extends RefCounted
## 原生固定面与两张分层纹理的倾斜深度夹具；不等于正式旧底图接合。
const MapProjection = preload("res://scripts/experiments/volume_projection.gd")


static func run(tree: SceneTree, root: String, output: String) -> int:
	if DisplayServer.get_name()=="headless" or DirAccess.dir_exists_absolute(output):
		return 1
	var native_path := root.path_join("r289-native-source-a/clipped.bin")
	var source := root.path_join("r286-layered-fixed-a")
	var packed_root := root.path_join("r288-layered-bc3-b")
	if FileAccess.get_sha256(native_path)!="6ed0bfcd2411d80ccdd643fa7695d6ddc16299af16066a269b9aabecec265260" or FileAccess.get_sha256(source.path_join("manifest.json"))!="a23d5fc131f93a33ae55bc6384203e438abc968a19fc5bdb88797c0ffb7bd1d8" or FileAccess.get_sha256(packed_root.path_join("report.json"))!="83eafb11b8f1b3843d1787650db73f0abfb520f11df91c096acd8753203f3880":
		return 1
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("manifest.json")))
	var compressed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(packed_root.path_join("report.json")))
	var data := FileAccess.get_file_as_bytes(native_path).to_float32_array()
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var layer_filter := OS.get_environment("AGL_TOKYO_DEPTH_LAYER")
	if layer_filter not in ["", "negative", "positive"]:
		return 1
	for i in data.size()/10:
		var j := i*10
		if (layer_filter=="negative" and data[j+1]>=0) or (layer_filter=="positive" and data[j+1]<0):
			continue
		vertices.append(Vector3(data[j],data[j+1],data[j+2]))
		colors.append(Color(data[j+6],data[j+7],data[j+8],data[j+9]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_COLOR]=colors
	var native_mesh := ArrayMesh.new()
	native_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var native_material := ShaderMaterial.new()
	var native_shader := Shader.new()
	native_shader.code="shader_type spatial; render_mode unshaded, cull_disabled; void fragment(){ ALBEDO=COLOR.rgb; }"
	native_material.shader=native_shader
	var viewport := SubViewport.new()
	viewport.size=Vector2i(768,768)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color(.20,.24,.21)
	viewport.add_child(world)
	var city := Node3D.new()
	viewport.add_child(city)
	var native := MeshInstance3D.new()
	native.mesh=native_mesh
	native.material_override=native_material
	city.add_child(native)
	var hybrid := OS.get_environment("AGL_TOKYO_DEPTH_HYBRID")=="1"
	var roads := MeshInstance3D.new()
	var road_vertices := PackedVector3Array()
	var road_colors := PackedColorArray()
	for i in vertices.size():
		if vertices[i].y>=0:
			road_vertices.append(vertices[i])
			road_colors.append(colors[i])
	if hybrid:
		if layer_filter!="" or road_vertices.is_empty():
			viewport.queue_free()
			await tree.process_frame
			return 1
		var road_arrays: Array = []
		road_arrays.resize(Mesh.ARRAY_MAX)
		road_arrays[Mesh.ARRAY_VERTEX]=road_vertices
		road_arrays[Mesh.ARRAY_COLOR]=road_colors
		var road_mesh := ArrayMesh.new()
		road_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,road_arrays)
		roads.mesh=road_mesh
		roads.material_override=native_material
	city.add_child(roads)
	var cover := MeshInstance3D.new()
	var cover_mesh := PlaneMesh.new()
	cover_mesh.size=Vector2(250,500)
	cover.mesh=cover_mesh
	cover.position=Vector3(-6675,0,-4450)
	var cover_material := ShaderMaterial.new()
	var cover_shader := Shader.new()
	cover_shader.code="shader_type spatial; render_mode unshaded, cull_disabled; void fragment(){ ALBEDO=vec3(.4,.1,.4); }"
	cover_material.shader=cover_shader
	cover.material_override=cover_material
	city.add_child(cover)
	var planes: Array[MeshInstance3D] = []
	var variants: Array = []
	for n in manifest.rows.size():
		var info: Dictionary = manifest.rows[n]
		var packed_info: Dictionary = compressed.rows[n]
		var raw_path := source.path_join(info.file)
		var packed_path := packed_root.path_join(packed_info.file)
		if FileAccess.get_sha256(raw_path)!=info.sha256 or FileAccess.get_sha256(packed_path)!=packed_info.sha256:
			viewport.queue_free()
			await tree.process_frame
			return 1
		var original := Image.load_from_file(raw_path)
		original.convert(Image.FORMAT_RGBA8)
		if original.generate_mipmaps()!=OK:
			viewport.queue_free()
			await tree.process_frame
			return 1
		var packed := Image.create_from_data(int(info.width),int(info.height),true,Image.FORMAT_DXT5,FileAccess.get_file_as_bytes(packed_path))
		variants.append([ImageTexture.create_from_image(original),ImageTexture.create_from_image(packed)])
		var plane := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size=Vector2(float(info.width),float(info.height))*float(info.world_step)
		plane.mesh=mesh
		plane.position=Vector3((float(info.bounds[0])+float(info.bounds[2]))*.5,float(info.plane_height_proposal),(float(info.bounds[1])+float(info.bounds[3]))*.5)
		var material := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code="shader_type spatial; render_mode unshaded, cull_disabled; uniform sampler2D source_tex: filter_linear_mipmap, repeat_disable; void fragment(){ vec4 c=texture(source_tex,UV); ALBEDO=c.rgb/max(c.a,.00001); ALPHA=c.a; }"
		material.shader=shader
		plane.material_override=material
		plane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		city.add_child(plane)
		planes.append(plane)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	camera.current=true
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array[Dictionary] = []
	var fail := 0
	for scale_value: float in [.20,.3888,1.0]:
		for angle: float in [0.0,14.0]:
			var canvas := Transform2D(deg_to_rad(angle),Vector2.ZERO)
			var ground := MapProjection.ground_basis(canvas,deg_to_rad(38.0))
			var basis := MapProjection.camera_basis(canvas,deg_to_rad(38.0))
			city.basis=ground
			camera.size=768.0/scale_value
			camera.transform=Transform3D(basis,ground*Vector3(-6550,0,-4450)+basis.z*50000.0)
			var span := camera.size*.65+1200.0
			camera.near=maxf(.1,50000.0-span)
			camera.far=50000.0+span
			for occluded in [false,true]:
				cover.visible=occluded
				for mode in 5:
					native.visible=mode==0
					roads.visible=hybrid and mode>0
					for n in planes.size():
						planes[n].visible=mode>0 and n%2==(mode-1)/2 and (layer_filter=="" or manifest.rows[n].layer==layer_filter) and (not hybrid or manifest.rows[n].layer=="negative")
						if mode>0:
							planes[n].material_override.set_shader_parameter("source_tex",variants[n][(mode-1)%2])
					for frame in 3:
						await RenderingServer.frame_post_draw
					var file := "scale%d_rot%d_cover%d_%s.png"%[roundi(scale_value*10000),roundi(angle),int(occluded),["native","coarse_raw","coarse_bc3","fine_raw","fine_bc3"][mode]]
					fail+=int(viewport.get_texture().get_image().save_png(output.path_join(file))!=OK)
					rows.append({"file":file,"scale":scale_value,"angle":angle,"cover":occluded,"mode":mode,"diagnostic_outside_far_range":scale_value>.3888})
	viewport.queue_free()
	await tree.process_frame
	var report := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"rows":rows,"fail":fail,"hybrid_native_roads":hybrid,"road_faces":road_vertices.size()/3,"layer_filter":layer_filter,"godot":Engine.get_version_info().string,"tilt":38,"native_faces":vertices.size()/3,"map_integration_verified":false,"performance_verified":false},"\t"))
	report.close()
	return fail
