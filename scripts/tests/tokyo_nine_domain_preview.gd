extends RefCounted
## 九域预载索引同帧提交；只供受限实景验证，不改变正式地图。
const Sparse := preload("res://scripts/tests/tokyo_sparse_mip_sampler.gd")
const Saved := preload("res://scripts/tests/tokyo_selectable_geometry_save.gd")
const Surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Recipe := preload("res://scripts/tests/tokyo_index_recipe_probe.gd")

static func digest(data: PackedByteArray) -> String:
	var h := HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(data);return h.finish().hex_encode()

static func choose(c: Dictionary, center: Vector2, scale_value: float, ready: bool) -> int:
	if not ready or not center.is_finite() or not is_finite(scale_value):return -1
	if c.has("wall_restore_threshold"):
		var minimum := 0.4 if c.get("recipe_indices",false) else 0.5
		if scale_value<minimum or scale_value>0.625:return -1
	elif scale_value!=0.5:return -1
	for i in c.domains.size():
		var b: Array=c.domains[i].camera_bounds
		if center.x>=b[0] and center.y>=b[1] and center.x<=b[2] and center.y<=b[3]:return i
	return -1

static func run(parent: Node, input: Dictionary) -> int:
	if DisplayServer.get_name()=="headless" or FileAccess.file_exists(input.output):return 1
	var binding: Dictionary=input.nine_domain_preview
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var c: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if c.formal_enabled or c.domains.size()!=9 or c.meshes.size()!=3 or c.known_load_charge>201326592:return 1
	if FileAccess.get_sha256(c.coverage.path)!=c.coverage.sha256:return 1
	var coverage: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(c.coverage.path))
	var recipe_test: bool=c.get("recipe_indices",false)
	if not coverage.passed:return 1
	if recipe_test:
		if not coverage.all_full_mips_checked or coverage.results.size()!=4:return 1
		for row: Dictionary in coverage.results:
			if row.missing_unique!=0:return 1
	else:
		if coverage.missing_reachable_count!=0:return 1
	var restore_test := c.has("wall_restore_threshold")
	var compressed: Array[PackedByteArray]=[]
	var recipe_sources: Array[PackedByteArray]=[]
	var recipe_data: Array=[]
	if recipe_test:
		if not restore_test or absf(float(c.wall_restore_threshold)-2.0/(12.0*0.5*sin(deg_to_rad(38))))>1e-12:return 1
		for item: Dictionary in c.recipe_sources:
			var data := Recipe.load_bytes(item)
			if data.is_empty():return 1
			recipe_sources.append(data)
		for domain: Dictionary in c.domains:
			var modes: Array=[]
			for mode in ["simplified","full"]:
				var group: Array[PackedByteArray]=[]
				for item: Dictionary in domain.recipes[mode]:
					var data := Recipe.load_bytes(item.recipe)
					if data.is_empty():return 1
					group.append(data)
				modes.append(group)
			recipe_data.append(modes)
	elif restore_test:
		if FileAccess.get_sha256(c.coverage_basis.path)!=c.coverage_basis.sha256:return 1
		var basis_report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(c.coverage_basis.path))
		for row: Dictionary in basis_report.results:
			if row.scale>=0.5 and row.scale<=0.625 and row.missing_unique!=0:return 1
		if absf(float(c.wall_restore_threshold)-2.0/(12.0*0.5*sin(deg_to_rad(38))))>1e-12:return 1
		var compressed_bytes := 0
		for domain: Dictionary in c.domains:
			var row: Dictionary=domain.simplified_native
			if FileAccess.get_sha256(row.path)!=row.sha256:return 1
			var bytes := FileAccess.get_file_as_bytes(row.path)
			compressed.append(bytes);compressed_bytes+=bytes.size()
		if compressed_bytes!=int(c.simplified_compressed_bytes):return 1
	var meshes: Array[ArrayMesh]=[];var probes: Array[WeakRef]=[];var indices: Array=[];var materials: Array[ShaderMaterial]=[]
	for row: Dictionary in c.meshes:
		if FileAccess.get_sha256(row.path)!=row.sha256:return 1
		var mesh: ArrayMesh=ResourceLoader.load(row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if mesh==null or mesh.get_surface_count()!=1 or mesh.surface_get_array_index_len(0)!=int(row.capacity)*3:return 1
		meshes.append(mesh);probes.append(weakref(mesh));mesh=null
	var index_bytes := 0
	for domain: Dictionary in c.domains:
		if recipe_test:break
		var group: Array[PackedByteArray]=[]
		for i in 3:
			var row: Dictionary=domain.indices[i];var bytes := Saved.unpack(row)
			if bytes.size()!=int(c.meshes[i].capacity)*3*int(c.meshes[i].index_stride) or digest(bytes)!=row.decoded_sha256:return 1
			group.append(bytes);index_bytes+=bytes.size()
		indices.append(group)
	if not recipe_test and index_bytes!=int(coverage.cached_index_bytes):return 1
	for bank: Dictionary in c.texture_banks:
		var material := ShaderMaterial.new();material.shader=Shader.new()
		material.shader.code=Surface.textured_code().replace("sample_color.a<0.001","sample_color.a<0.5").replace("void fragment() {",Sparse.sampler_code()+"\nvoid fragment() {").replace("texture(overview,UV)","read_tile(UV,UV2.x)")
		for i in 4:
			var row: Dictionary=bank.files[["payload","blocks","mips","tiles"][i]]
			if FileAccess.get_sha256(row.path)!=row.sha256:return 1
			var bytes := FileAccess.get_file_as_bytes(row.path)
			if bytes.size()!=int(row.bytes):return 1
			var format_value := Image.FORMAT_RGBA8 if i==0 else (Image.FORMAT_RGF if i==3 else Image.FORMAT_RGBAF)
			var source := Image.create_from_data(int(row.width),int(row.height),false,format_value,bytes)
			var texture := ImageTexture.create_from_image(source)
			if texture==null:return 1
			material.set_shader_parameter("page%d"%i,texture);probes.append(weakref(texture));source=null;texture=null;bytes.clear()
		materials.append(material);probes.append(weakref(material));material=null
	var viewport := SubViewport.new();viewport.size=Vector2i(1600,900);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;parent.add_child(viewport)
	var ground := MapProjection.ground_basis(Transform2D.IDENTITY,deg_to_rad(38));var basis := MapProjection.camera_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1800;camera.far=10000;viewport.add_child(camera)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=.8;viewport.add_child(sun)
	var native := ShaderMaterial.new();native.shader=Shader.new();native.shader.code=Surface.native_code()
	for i in 3:
		var node := MeshInstance3D.new();node.mesh=meshes[i];node.transform=Transform3D(ground,Vector3.ZERO)
		node.material_override=native if i==0 else materials[i-1];viewport.add_child(node)
	var poses: Array[Vector2]=[]
	for i in 9:
		var a: Array=c.domains[i].center;var b: Array=c.domains[(i+1)%9].center
		for step in 12:poses.append(Vector2(a[0],a[1]).lerp(Vector2(b[0],b[1]),float(step)/11.0))
	var rejects := 0
	for bad: Array in [[Vector2(INF,0),0.5,true],[poses[0],NAN,true],[poses[0],0.7 if restore_test else 0.625,true],[poses[0],0.5,false],[Vector2.ZERO,0.5,true]]:
		if choose(c,bad[0],bad[1],bad[2])!=-1:return 1
		rejects+=1
	var hashes: Array[String]=[];var visited: Dictionary={};var changes := 0;var failures: Array=[]
	var restore_controls := 0
	var simplified_frames := 0
	var scales: Array[float]=[0.5]
	if restore_test:scales=[0.5,float(c.wall_restore_threshold)-0.000001,float(c.wall_restore_threshold),float(c.wall_restore_threshold)+0.000001,0.625,0.56,0.53]
	if recipe_test:scales=[0.4,0.45,0.5,float(c.wall_restore_threshold)-0.000001,float(c.wall_restore_threshold),float(c.wall_restore_threshold)+0.000001,0.625,0.56,0.53]
	if DirAccess.make_dir_recursive_absolute(input.preview_directory)!=OK:return 1
	for pass_id in (3 if restore_test else 2):
		var previous := -1
		var previous_simple := false
		for n in poses.size():
			var scale_value: float=scales[n%scales.size()]
			var simple := restore_test and scale_value<float(c.wall_restore_threshold)
			if pass_id==2 and simple:continue
			var center: Vector2=poses[n];var cell := choose(c,center,scale_value,true)
			if cell<0:return 1
			if cell!=previous or simple!=previous_simple:
				var next_group: Array[PackedByteArray]=[]
				var native_indices := PackedByteArray()
				if recipe_test:
					var mode := "simplified" if simple else "full"
					for bank in 3:
						var item: Dictionary=c.domains[cell].recipes[mode][bank]
						var assembled := Recipe.assemble(recipe_sources[bank],recipe_data[cell][0 if simple else 1][bank],int(c.meshes[bank].capacity)*12)
						if assembled.is_empty() or digest(assembled.bytes)!=item.padded_sha256:return 1
						var bytes: PackedByteArray=assembled.bytes
						if int(c.meshes[bank].index_stride)==2:
							var short_bytes := PackedByteArray();short_bytes.resize(bytes.size()/2)
							for offset in range(0,bytes.size(),4):
								var value := bytes.decode_u32(offset)
								if value>65535:return 1
								short_bytes.encode_u16(offset/2,value)
							bytes=short_bytes
						next_group.append(bytes)
				else:
					native_indices=indices[cell][0]
				if simple and not recipe_test:
					var row: Dictionary=c.domains[cell].simplified_native
					native_indices=compressed[cell].decompress(int(row.decoded_bytes),FileAccess.COMPRESSION_GZIP)
					if native_indices.size()!=int(row.decoded_bytes) or digest(native_indices)!=row.decoded_sha256:return 1
					native_indices.resize(int(c.meshes[0].capacity)*12)
				# 三层都已在同一合同内就绪；三次更新和相机变换之间没有await。
				for bank in 3:RenderingServer.call("mesh_surface_update_index_region",meshes[bank].get_rid(),0,0,next_group[bank] if recipe_test else (native_indices if bank==0 else indices[cell][bank]))
				if pass_id==0:changes+=1
				previous=cell
				previous_simple=simple
			camera.size=900.0/scale_value
			camera.transform=Transform3D(basis,ground*Vector3(center.x,0,center.y)+basis.z*3000)
			await RenderingServer.frame_post_draw
			if pass_id>0:
				for frame in 3:await RenderingServer.frame_post_draw
			var picture := viewport.get_texture().get_image();var value := digest(picture.get_data())
			if pass_id==0:
				if simple:simplified_frames+=1
				hashes.append(value);visited[cell]=true
				if n%24==0 and picture.save_png(input.preview_directory.path_join("pose%03d.png"%n))!=OK:return 1
			elif hashes[n]!=value:failures.append(n)
			if pass_id==2:restore_controls+=1
	viewport.queue_free();viewport=null;camera=null;sun=null;native=null;meshes.clear();materials.clear();indices.clear()
	recipe_sources.clear();recipe_data.clear()
	for frame in 4:await parent.get_tree().process_frame
	var remaining := 0
	for probe: WeakRef in probes:remaining+=int(probe.get_ref()!=null)
	var submitted := 0
	for row: Dictionary in c.meshes:submitted+=int(row.capacity)
	var result := {"poses":poses.size(),"visited_domains":visited.size(),"index_changes":changes,"rejections":rejects,"pixel_mismatches":failures,"remaining_objects":remaining,"known_load_charge":c.known_load_charge,"cpu_cached_indices":index_bytes,"mesh_surfaces":3,"joint_submitted_faces":submitted,"full_map_verified":false,"zoom_range_verified":false,"performance_verified":false,"formal_enabled":false}
	result["passed"]=visited.size()==9 and changes>=9 and failures.is_empty() and remaining==0
	result["restore_control_frames"]=restore_controls
	result["simplified_frames"]=simplified_frames
	result["recipe_indices_verified"]=recipe_test and failures.is_empty()
	result["local_zoom_restore_verified"]=restore_test and restore_controls>0 and simplified_frames>0 and failures.is_empty()
	if restore_test:result["passed"]=result.passed and result.local_zoom_restore_verified
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(result,"\t"));file.close();print("Nine domain preview: ",JSON.stringify(result))
	return 0 if result.passed else 1
