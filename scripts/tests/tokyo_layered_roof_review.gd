extends RefCounted
## 当前屋顶分层候选的同位GPU读回；仅取证，不授予正式覆盖或性能资格。
const Surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Add := preload("res://scripts/tests/tokyo_partition_render_probe.gd")

static func mesh_from_bytes(bytes: PackedByteArray) -> ArrayMesh:
	var data := bytes.to_float32_array()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for i in range(0,data.size(),10):
		vertices.append(Vector3(data[i],data[i+1],data[i+2]))
		normals.append(Vector3(data[i+3],data[i+4],data[i+5]))
		colors.append(Color(data[i+6],data[i+7],data[i+8],data[i+9]))
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func difference(a: Image,b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8);b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data();var bb := b.get_data();var changed := 0;var large := 0;var maximum := 0
	for i in range(0,aa.size(),4):
		var delta := 0
		for c in 3: delta=maxi(delta,absi(int(aa[i+c])-int(bb[i+c])))
		changed+=int(delta>0);large+=int(delta>8);maximum=maxi(maximum,delta)
	return {"changed_pixels":changed,"delta_over_8":large,"max_channel_delta":maximum}

static func wall_bins(bytes: PackedByteArray,ray: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for i in 16: result.append({"bytes":PackedByteArray(),"front":false,"faces":0})
	var data := bytes.to_float32_array()
	for i in range(0,data.size(),30):
		var a := Vector3(data[i],data[i+1],data[i+2])
		var b := Vector3(data[i+10],data[i+11],data[i+12])
		var c := Vector3(data[i+20],data[i+21],data[i+22])
		var normal := (c-a).cross(b-a).normalized()
		var index := posmod(int(floor((atan2(normal.z,normal.x)+PI)/TAU*16.0)),16)
		result[index].bytes.append_array(bytes.slice(i*4,(i+30)*4))
		result[index].front=result[index].front or normal.dot(ray)>=-0.00000001
		result[index].faces+=1
	return result

static func run(parent: Node,input: Dictionary) -> int:
	if DisplayServer.get_name()=="headless": return 1
	var binding: Dictionary=input.layered_roof_review
	if FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	var base: String=String(binding.path).get_base_dir()
	var output: String=input.output
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	if FileAccess.get_sha256(input.source)!=manifest.source_sha256 or FileAccess.get_sha256(base.path_join("walls.attributes"))!=manifest.wall_attributes_sha256: return 1
	var source := FileAccess.get_file_as_bytes(input.source)
	var walls := FileAccess.get_file_as_bytes(base.path_join("walls.attributes"))
	if source.size()!=int(manifest.source_faces)*120 or walls.size()!=int(manifest.wall_faces)*120: return 1
	var images: Array[Image]=[]
	for row: Dictionary in manifest.rows:
		var path := base.path_join(row.file)
		if FileAccess.get_sha256(path)!=row.sha256: return 1
		var image := Image.load_from_file(path)
		if image==null or image.generate_mipmaps()!=OK: return 1
		images.append(image)
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var viewport := SubViewport.new();viewport.size=Vector2i(1600,900);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;parent.add_child(viewport)
	var basis := MapProjection.camera_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var ground := MapProjection.ground_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var camera := Camera3D.new();viewport.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=10000
	camera.transform=Transform3D(basis,ground*Vector3(-4150,0,-14700)+basis.z*3000)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=.8;sun.shadow_enabled=false;viewport.add_child(sun)
	var mat := ShaderMaterial.new();mat.shader=Shader.new();mat.shader.code=Surface.native_code()
	var original := Add.add_mesh(viewport,mesh_from_bytes(source),ground,mat)
	var candidates: Array[MeshInstance3D]=[]
	var submitted_faces := int(manifest.candidate_faces)
	if input.get("wall_bins",false):
		submitted_faces=int(manifest.candidate_faces)-int(manifest.wall_faces)
		for group: Dictionary in wall_bins(walls,ground.inverse()*basis.z):
			if group.bytes.is_empty(): continue
			var node := Add.add_mesh(viewport,mesh_from_bytes(group.bytes),ground,mat)
			node.set_meta("facing",group.front);candidates.append(node)
			if group.front: submitted_faces+=int(group.faces)
	else: candidates.append(Add.add_mesh(viewport,mesh_from_bytes(walls),ground,mat))
	for i in manifest.rows.size():
		var row: Dictionary=manifest.rows[i]
		var g: Array=row.geometry_bounds;var t: Array=row.texture_bounds
		var footprint := Rect2(g[0],g[1],g[2]-g[0],g[3]-g[1]);var texture_bounds := Rect2(t[0],t[1],t[2]-t[0],t[3]-t[1])
		var uv := Rect2((footprint.position-texture_bounds.position)/texture_bounds.size,footprint.size/texture_bounds.size)
		var material := ShaderMaterial.new();material.shader=Shader.new()
		# 屋顶是实体轮廓，不把过滤后的极小alpha尾部画成不透明街区。
		material.shader.code=Surface.textured_code().replace("sample_color.a<0.001","sample_color.a<0.5")
		material.set_shader_parameter("overview",ImageTexture.create_from_image(images[i]))
		var plane := Add.add_mesh(viewport,preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd").plane(footprint,uv),ground,material)
		plane.position=ground*Vector3(0,float(row.height),0);candidates.append(plane)
	var rows: Array=[];var success := true
	for scale_value: float in [.4,.7776]:
		camera.size=900.0/scale_value;original.visible=true
		for node in candidates: node.visible=false
		for frame in 3: await RenderingServer.frame_post_draw
		var reference := viewport.get_texture().get_image()
		original.visible=false
		for node in candidates: node.visible=node.get_meta("facing",true)
		for frame in 3: await RenderingServer.frame_post_draw
		var selected := viewport.get_texture().get_image()
		for node in candidates: node.visible=false
		for frame in 3: await RenderingServer.frame_post_draw
		var blank := viewport.get_texture().get_image()
		var prefix := output.path_join("scale_%.4f"%scale_value)
		success=success and reference.save_png(prefix+"_reference.png")==OK and selected.save_png(prefix+"_candidate.png")==OK and blank.save_png(prefix+"_blank.png")==OK
		var negative := difference(reference,blank)
		success=success and int(negative.changed_pixels)>0
		rows.append({"scale":scale_value,"difference":difference(reference,selected),"negative_control":negative})
	viewport.queue_free();await parent.get_tree().process_frame
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"manifest":binding,"rows":rows,"capture_success":success,"candidate_mesh_instances":candidates.size(),"submitted_faces":submitted_faces,"wall_bins":input.get("wall_bins",false),"visual_accepted":false,"performance_accepted":false,"runtime_integrated":false},"\t"))
	return 0 if success else 1
