extends RefCounted
## 整图远景候选的原生渲染检查；独立制作场景，不授予正式地图接管权限。
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Surface := preload("res://resources/shaders/tokyo_volume_surface.gdshader")
const Ground := preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd")


static func binding(row: Variant) -> bool:
	return row is Dictionary and row.get("path") is String and row.get("sha256") is String \
		and FileAccess.file_exists(row.path) and FileAccess.get_sha256(row.path)==row.sha256


static func material(texture: Texture2D, bounds: Vector4) -> ShaderMaterial:
	var shader := Shader.new()
	var code := Surface.code.replace("specular_disabled;", "specular_disabled, cull_disabled;")
	code=code.replace("shader_type spatial;", "shader_type spatial;\nuniform sampler2D overview : filter_linear_mipmap, repeat_disable;\nuniform vec4 overview_bounds;")
	code=code.replace("vec3 base = COLOR.rgb;", "vec4 sample_color=texture(overview,UV);\nif(sample_color.a<0.001){discard;}\nvec3 base=sample_color.rgb/max(sample_color.a,0.001);")
	shader.code=code
	var result := ShaderMaterial.new()
	result.shader=shader
	result.set_shader_parameter("overview",texture)
	result.set_shader_parameter("overview_bounds",bounds)
	return result


static func triangle_mesh(raw: PackedByteArray, first: int, count: int, bounds: Rect2) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(count*3)
	normals.resize(count*3)
	colors.resize(count*3)
	uvs.resize(count*3)
	for face in count:
		for corner in 3:
			var offset := ((first+face)*3+corner)*12
			var v := Vector3(raw.decode_float(offset),raw.decode_float(offset+4),raw.decode_float(offset+8))
			vertices[face*3+corner]=v
			uvs[face*3+corner]=(Vector2(v.x,v.z)-bounds.position)/bounds.size
			colors[face*3+corner]=Color(0.59,0.61,0.55,1)
		var a := vertices[face*3]
		var n := (vertices[face*3+2]-a).cross(vertices[face*3+1]-a).normalized()
		if n.y<0.0:
			n=-n
		for corner in 3:
			normals[face*3+corner]=n
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result


static func add_mesh(city: Node3D, mesh: ArrayMesh, shading: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh=mesh
	instance.material_override=shading
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	city.add_child(instance)


static func checks() -> bool:
	if binding(null) or binding({}) or binding({"path":"","sha256":""}):
		return false
	var raw := PackedByteArray()
	raw.resize(36)
	var points := [Vector3(0,4,0),Vector3(2,4,0),Vector3(0,4,2)]
	for i in 3:
		raw.encode_float(i*12,points[i].x)
		raw.encode_float(i*12+4,points[i].y)
		raw.encode_float(i*12+8,points[i].z)
	var geometry := triangle_mesh(raw,0,1,Rect2(0,0,2,2))
	var arrays := geometry.surface_get_arrays(0)
	# Godot八面体打包的UP回读z=-1/65535；位置/UV仍要求精确，不把编码步长当几何误差。
	var normal: Vector3 = arrays[Mesh.ARRAY_NORMAL][0]
	var upward := normal.y>=0.99999 and absf(normal.x)<=2.0/65535.0 and absf(normal.z)<=2.0/65535.0
	return arrays[Mesh.ARRAY_VERTEX]==PackedVector3Array(points) and upward \
		and arrays[Mesh.ARRAY_TEX_UV]==PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN])


static func run(tree: SceneTree, directory: String, expected_sha: String, output: String) -> int:
	var path := directory.path_join("manifest.json")
	if not binding({"path":path,"sha256":expected_sha}) or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output):
		return 1
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("representation")!="whole_map_far_height_mass_native_color" \
		or data.get("tiles")!=256 or data.get("formal",[]).size()!=189 or data.get("max_scale")!=0.0243 \
		or data.get("faces",240001)+2>240000 or not binding(data.get("geometry")) or not binding(data.get("mip_payload")):
		return 1
	if DisplayServer.get_name()=="headless":
		print("[Overview HLOD] metadata checked; Visual required")
		return 1
	var raw := FileAccess.get_file_as_bytes(data.geometry.path)
	if raw.size()!=int(data.faces)*36:
		return 1
	var levels: Array = data.levels
	var mip := FileAccess.get_file_as_bytes(data.mip_payload.path)
	var image := Image.create_from_data(int(levels[0].width),int(levels[0].height),true,Image.FORMAT_RGBA8,mip)
	if image==null or image.get_data()!=mip:
		return 1
	var texture := ImageTexture.create_from_image(image)
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,960)
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var city := Node3D.new()
	viewport.add_child(city)
	var bounds := Rect2(float(data.bounds[0]),float(data.bounds[1]),float(data.bounds[2])-float(data.bounds[0]),float(data.bounds[3])-float(data.bounds[1]))
	var shading := material(texture,Vector4(bounds.position.x,bounds.position.y,bounds.end.x,bounds.end.y))
	add_mesh(city,Ground.plane(bounds,Rect2(0,0,1,1)),shading)
	add_mesh(city,triangle_mesh(raw,0,int(data.ordinary_faces),bounds),shading)
	var formal_material := ShaderMaterial.new()
	formal_material.shader=Surface
	add_mesh(city,triangle_mesh(raw,int(data.ordinary_faces),int(data.faces)-int(data.ordinary_faces),bounds),formal_material)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.near=100
	camera.far=100000
	viewport.add_child(camera)
	camera.make_current()
	var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color(0.18,0.22,0.23)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_DISABLED
	camera.environment=environment
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-35,0)
	sun.light_energy=0.8
	sun.shadow_enabled=false
	viewport.add_child(sun)
	var screen := TextureRect.new()
	screen.texture=viewport.get_texture()
	screen.size=Vector2(viewport.size)
	tree.root.add_child(screen)
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array[Dictionary] = []
	for pose in [Vector2(0.02,0),Vector2(0.02,45),Vector2(0.0243,0),Vector2(0.0243,90)]:
		var canvas := Transform2D(deg_to_rad(pose.y),Vector2.ZERO).scaled(Vector2.ONE*pose.x)
		var ground_basis := MapProjection.ground_basis(canvas,deg_to_rad(38))
		var camera_basis := MapProjection.camera_basis(canvas,deg_to_rad(38))
		var center := bounds.get_center()
		city.basis=ground_basis
		camera.size=float(viewport.size.y)/pose.x
		camera.transform=Transform3D(camera_basis,ground_basis*Vector3(center.x,0,center.y)+camera_basis.z*50000.0)
		for frame in 4:
			viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
		var capture := viewport.get_texture().get_image()
		var capture_path := output.path_join("overview_%02d.png" % rows.size())
		if capture.save_png(capture_path)!=OK:
			return 1
		rows.append({"scale":pose.x,"rotation":pose.y,"path":capture_path,"sha256":FileAccess.get_sha256(capture_path),
			"visible_primitives":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
			"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)})
		print("[Overview HLOD] actual rendered pose=",rows.size()," primitives=",rows[-1].visible_primitives)
	var weak_viewport: WeakRef = weakref(viewport)
	var weak_texture: WeakRef = weakref(texture)
	screen.queue_free()
	viewport.queue_free()
	shading=null
	texture=null
	image=null
	await tree.process_frame
	await tree.process_frame
	var released := weak_viewport.get_ref()==null and weak_texture.get_ref()==null
	var report := {"manifest_sha256":expected_sha,"poses":rows,"geometry_faces":data.faces+2,
		"rgba_mip_bytes":mip.size(),"gpu_texture_mips_roundtrip":true,"released":released,
		"production_installed":false,"performance_accepted":false,"formal_gameplay_coverage_accepted":false}
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("[Overview HLOD] static native captures=",rows.size()," released=",released," NOT combat acceptance")
	return 0 if released else 1
