extends RefCounted
## 新HLOD原生页同机位对拍，独立制作场景，不改变正式地图默认。
const Review := preload("res://scripts/tests/tokyo_overview_hlod_review.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Ground := preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")


static func valid_pose(pose: Variant) -> bool:
	return pose is Dictionary and pose.get("center") is Array and pose.center.size()==2 \
		and typeof(pose.get("scale")) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(pose.scale)) and pose.scale>0 \
		and typeof(pose.get("rotation")) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(pose.rotation)) \
		and pose.get("cut") is Array and pose.cut.size()>0 and pose.cut.size()<=16


static func add_page(city: Node3D, row: Dictionary, encoding: String, shader: Shader, weak_textures: Array[WeakRef]) -> bool:
	if not Review.binding(row.get("native_geometry")) or not Review.binding(row.get("native_texture")) \
		or not Review.binding(row.texture.get("file")): return false
	var component: Resource = ResourceLoader.load(row.native_geometry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if not component is Component or not component.valid() or component.meshes.size()!=2 \
		or component.geometry_bytes!=int(row.native_geometry.bytes): return false
	var image: Image
	if encoding=="bc3":
		image=ResourceLoader.load(row.native_texture.path,"",ResourceLoader.CACHE_MODE_IGNORE) as Image
		if image==null or image.get_format()!=Image.FORMAT_DXT5 or image.get_data().size()!=int(row.native_texture.mip_bytes): return false
	else:
		var levels: Array = row.texture.levels
		var raw := FileAccess.get_file_as_bytes(row.texture.file.path)
		image=Image.create_from_data(int(levels[0].width),int(levels[0].height),true,Image.FORMAT_RGBA8,raw)
		if image==null or image.get_data()!=raw: return false
	var texture := ImageTexture.create_from_image(image)
	weak_textures.append(weakref(texture))
	var shading := ShaderMaterial.new()
	shading.shader=shader
	shading.set_shader_parameter("overview",texture)
	var bounds := Rect2(float(row.bounds[0]),float(row.bounds[1]),float(row.bounds[2])-float(row.bounds[0]),float(row.bounds[3])-float(row.bounds[1]))
	var tex_bounds := Rect2(float(row.texture.bounds[0]),float(row.texture.bounds[1]),float(row.texture.bounds[2])-float(row.texture.bounds[0]),float(row.texture.bounds[3])-float(row.texture.bounds[1]))
	var uv := Rect2((bounds.position-tex_bounds.position)/tex_bounds.size,bounds.size/tex_bounds.size)
	Review.add_mesh(city,Ground.plane(bounds,uv),shading)
	Review.add_mesh(city,component.meshes[0],shading)
	var formal_material := ShaderMaterial.new()
	formal_material.shader=Review.Surface
	Review.add_mesh(city,component.meshes[1],formal_material)
	return true


static func capture(tree: SceneTree, rows: Dictionary, pose: Dictionary, encoding: String, path: String) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1600,900)
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var city := Node3D.new()
	viewport.add_child(city)
	var weak_textures: Array[WeakRef] = []
	var shader: Shader = Review.material(null,Vector4.ZERO).shader
	var faces := 0
	var charge := 0
	var good := true
	for key: Array in pose.cut:
		var id_value := "%d:%d" % [int(key[0]),int(key[1])]
		if not rows.has(id_value):
			good=false;break
		var row: Dictionary = rows[id_value]
		if not add_page(city,row,encoding,shader,weak_textures):
			good=false;break
		faces+=int(row.faces)
		charge+=int(row.native_geometry.bytes)+288+(int(row.native_texture.three_copy_charge) if encoding=="bc3" else int(row.texture.bytes)*3+4096)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.near=100;camera.far=100000
	viewport.add_child(camera)
	camera.make_current()
	var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color(0.18,0.22,0.23)
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_DISABLED
	camera.environment=environment
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-35,0)
	sun.light_energy=0.8;sun.shadow_enabled=false
	viewport.add_child(sun)
	var canvas := Transform2D(float(pose.rotation),Vector2.ZERO).scaled(Vector2.ONE*float(pose.scale))
	var ground_basis := MapProjection.ground_basis(canvas,deg_to_rad(38))
	var camera_basis := MapProjection.camera_basis(canvas,deg_to_rad(38))
	city.basis=ground_basis
	camera.size=float(viewport.size.y)/float(pose.scale)
	camera.transform=Transform3D(camera_basis,ground_basis*Vector3(float(pose.center[0]),0,float(pose.center[1]))+camera_basis.z*50000.0)
	var result: Dictionary = {}
	if good:
		for frame in 4:
			viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
		var screenshot := viewport.get_texture().get_image()
		if screenshot.save_png(path)==OK:
			result={"path":path,"sha256":FileAccess.get_sha256(path),"encoding":encoding,"pose":pose,"submitted_faces":faces,"resource_charge":charge,
				"budget_qualified":faces<=240000 and charge<=96*1024*1024,
				"visible_primitives":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
				"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	var weak_viewport: WeakRef = weakref(viewport)
	viewport.queue_free()
	await tree.process_frame
	await tree.process_frame
	var released := weak_viewport.get_ref()==null
	for texture_ref in weak_textures: released=released and texture_ref.get_ref()==null
	if not result.is_empty(): result["released"]=released
	return result if released else {}


static func run(tree: SceneTree, path: String, expected_sha: String, output: String) -> int:
	if DisplayServer.get_name()=="headless" or not Review.binding({"path":path,"sha256":expected_sha}) \
		or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not plan is Dictionary or plan.get("schema")!=1 or not plan.get("views") is Array: return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var results: Array[Dictionary] = []
	for view: Dictionary in plan.views:
		if not valid_pose(view.get("pose")) or not Review.binding(view.get("manifest")) or view.get("encoding") not in ["rgba8","bc3"]: return 1
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(view.manifest.path))
		if not data is Dictionary or data.get("native_saved_roundtrip")!=true or data.get("rows",[]).size()!=336: return 1
		var rows: Dictionary = {}
		for row: Dictionary in data.rows: rows["%d:%d" % [int(row.depth),int(row.id)]]=row
		var result := await capture(tree,rows,view.pose,view.encoding,output.path_join("view_%02d.png" % results.size()))
		if result.is_empty(): return 1
		result["label"]=view.get("label","")
		result["manifest"]=view.manifest
		results.append(result)
		print("[HLOD pages review] saved=",results.size()," faces=",result.submitted_faces," released=",result.released)
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"source_sha256":expected_sha,"views":results,"production_installed":false,"performance_accepted":false,"visual_accepted":false},"\t"))
	file.close()
	return 0
