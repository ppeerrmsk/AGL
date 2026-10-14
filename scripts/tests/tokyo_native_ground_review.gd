extends RefCounted
## 烘焙地面与原生楼栋的独立GPU对照；不接正式覆盖、不作性能成绩。


static func run(parent: Node, input: Dictionary) -> int:
	var binding: Dictionary=input.get("ground_review",{})
	var output: String=input.get("output","")
	if DisplayServer.get_name()=="headless" or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var baked: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not baked is Dictionary or not baked.get("preview_only",false) or baked.get("roof_geometry_baked",true): return 1
	var package_path: String=input.get("package","")
	if FileAccess.get_sha256(package_path)!=baked.package_sha256: return 1
	var package: Variant=JSON.parse_string(FileAccess.get_file_as_string(package_path))
	if not input.get("height_depth_preview",false) is bool: return 1
	var poses: Variant=input.get("poses",[[330,-13420,0.8333333333,4],[330,-13420,1.25,4],[330,-13420,1.6666666667,5],[-4300,-3700,0.4166666667,3],[-4300,-3700,0.75,3]])
	if not poses is Array or poses.is_empty() or poses.size()>16: return 1
	for pose: Variant in poses:
		if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").numbers(pose,4) \
			or float(pose[2])<=0 or float(pose[2])>1.6666666667 \
			or pose[3]!=int(pose[3]) or int(pose[3]) not in [3,4,5]: return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.native) or DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var results: Array=[]
	for pose: Array in poses:
		var cut := native.select(Vector2(pose[0],pose[1]),pose[2],0.,Vector2(1600,900),"lod%d_full" % int(pose[3]),192*1024*1024)
		if not preload("res://scripts/rendering/tokyo_hlod_handoff.gd").native_qualified(cut,pose[2]): return 1
		var viewport := SubViewport.new()
		viewport.size=Vector2i(1600,900)
		viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		parent.add_child(viewport)
		var projection := preload("res://scripts/experiments/volume_projection.gd")
		var basis := projection.camera_basis(Transform2D.IDENTITY,deg_to_rad(38))
		var ground := projection.ground_basis(Transform2D.IDENTITY,deg_to_rad(38))
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.far=10000
		camera.size=900/float(pose[2])
		camera.transform=Transform3D(basis,ground*Vector3(pose[0],0,pose[1])+basis.z*3000)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees=Vector3(-50,-35,0)
		sun.light_energy=.8
		sun.shadow_enabled=false
		viewport.add_child(sun)
		var materials: Array[ShaderMaterial]=[]
		for kind in 3:
			var material := ShaderMaterial.new()
			material.shader=Shader.new()
			material.shader.code=preload("res://scripts/rendering/tokyo_hlod_surface.gd").native_code()
			material.set_shader_parameter("facade_detail",kind==1)
			materials.append(material)
		var original: Array[MeshInstance3D]=[]
		var planes: Array[MeshInstance3D]=[]
		var texture_bytes := 0
		var height_bytes := 0
		var ground_faces := 0
		var add := preload("res://scripts/tests/tokyo_partition_render_probe.gd")
		for entry: Dictionary in cut.entries:
			var row: Dictionary=native.pages[entry.path]
			var loaded: Dictionary={}
			for path: String in row.components:
				if FileAccess.get_sha256(path)!=row.components[path].sha256: return 1
				loaded[path]=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var page := preload("res://scripts/rendering/tokyo_component_page.gd").assemble(row,loaded)
			if page==null: return 1
			for kind in 3:
				if not entry.mask[kind]: continue
				var node := add.add_mesh(viewport,page.meshes[kind],ground,materials[kind])
				if kind==2: original.append(node)
			if not entry.mask[2]: continue
			if not baked.rows.has(entry.path): return 1
			var record: Dictionary=baked.rows[entry.path]
			if float(pose[2])>float(record.raster.max_scale) or FileAccess.get_sha256(record.texture.path)!=record.texture.sha256: return 1
			var image := Image.load_from_file(record.texture.path)
			if image==null or image.generate_mipmaps()!=OK: return 1
			texture_bytes+=image.get_data().size()*3
			ground_faces+=int(entry.triangles[2])
			var material := ShaderMaterial.new()
			material.shader=Shader.new()
			material.shader.code=preload("res://scripts/rendering/tokyo_hlod_surface.gd").textured_code()
			if input.get("height_depth_preview",false):
				# 仅独立Compatibility诊断：恢复每像素源高度的深度，不接正式材质。
				var height_binding: Dictionary=record.get("height_texture",{})
				if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").binding(height_binding) or FileAccess.get_sha256(height_binding.path)!=height_binding.sha256: return 1
				var height_image := Image.load_from_file(height_binding.path)
				var packed_height: bool=record.get("height_packing","")=="two_nibbles_per_byte"
				var expected_height_size := Vector2i((image.get_width()+7)/8,image.get_height()) if packed_height else image.get_size()
				if height_image==null or height_image.get_size()!=expected_height_size: return 1
				height_bytes+=height_image.get_data().size()*3
				var depth_code := material.shader.code.replace("shader_type spatial;","shader_type spatial;\nuniform sampler2D height_source : filter_nearest, repeat_disable;\nuniform float plane_y;")
				depth_code=depth_code.replace("void fragment() {","void fragment() {\nfloat source_y=texture(height_source,UV).r*2.0-1.0;\nvec3 up_view=(VIEW_MATRIX*MODEL_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz;\nvec4 source_clip=PROJECTION_MATRIX*vec4(VERTEX+up_view*(source_y-plane_y),1.0);\nDEPTH=source_clip.z/source_clip.w*0.5+0.5;")
				if packed_height:
					if not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").numbers(record.get("height_levels"),16): return 1
					depth_code=depth_code.replace("uniform float plane_y;","uniform float plane_y;\nuniform vec2 height_size;\nuniform float height_levels[16];")
					depth_code=depth_code.replace("float source_y=texture(height_source,UV).r*2.0-1.0;","ivec2 pixel=clamp(ivec2(UV*height_size),ivec2(0),ivec2(height_size)-ivec2(1));\nvec4 packed=texelFetch(height_source,ivec2(pixel.x/8,pixel.y),0)*255.0;\nint byte_value=int(round(packed[(pixel.x%8)/2]));\nint height_id=(pixel.x%2)==0 ? (byte_value&15) : (byte_value>>4);\nfloat source_y=height_levels[height_id];")
				material.shader.code=depth_code
				if packed_height:
					material.set_shader_parameter("height_levels",PackedFloat32Array(record.height_levels))
					material.set_shader_parameter("height_size",Vector2(image.get_size()))
				material.set_shader_parameter("height_source",ImageTexture.create_from_image(height_image))
				material.set_shader_parameter("plane_y",float(record.raster.flattened_plane_y))
			material.set_shader_parameter("overview",ImageTexture.create_from_image(image))
			var b: Array=record.source.bounds
			var t: Array=record.raster.bounds
			var footprint := Rect2(b[0],b[1],b[2]-b[0],b[3]-b[1])
			var texture_bounds := Rect2(t[0],t[1],t[2]-t[0],t[3]-t[1])
			var uv := Rect2((footprint.position-texture_bounds.position)/texture_bounds.size,footprint.size/texture_bounds.size)
			var mesh := preload("res://scripts/rendering/tokyo_fixed_atlas_layer.gd").plane(footprint,uv)
			var plane := add.add_mesh(viewport,mesh,ground,material)
			plane.position=ground*Vector3(0,float(record.raster.flattened_plane_y),0)
			plane.visible=false
			planes.append(plane)
		for frame in 3: await RenderingServer.frame_post_draw
		var before := viewport.get_texture().get_image()
		for node in original: node.visible=false
		for node in planes: node.visible=true
		for frame in 3: await RenderingServer.frame_post_draw
		var after := viewport.get_texture().get_image()
		var prefix := output.path_join("pose_%02d" % results.size())
		if before.save_png(prefix+"_native.png")!=OK or after.save_png(prefix+"_hybrid.png")!=OK: return 1
		results.append({"pose":pose,"native_triangles":cut.triangles,"ground_triangles":ground_faces,
			"hybrid_triangles":int(cut.triangles)-ground_faces+planes.size()*2,"native_bytes":cut.bytes,
			"texture_three_copy_bytes":texture_bytes,"height_three_copy_bytes":height_bytes,
			"height_depth_preview":input.get("height_depth_preview",false),"logical_pages":cut.active,"ground_planes":planes.size(),
			"combined_budget_accepted":false,"seams_accepted":false})
		viewport.queue_free()
		await parent.get_tree().process_frame
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"source":binding,"rows":results,"runtime_integrated":false,"visual_accepted":false,"performance_accepted":false},"\t"))
	file.close()
	return 0
