extends RefCounted
## 加载后固定原生最细叶，交引擎裁剪；只诊断区域，不授予正式地图或战斗性能资格。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")


static func run(parent: Node, input: Dictionary) -> int:
	var binding: Variant=input.get("static_leaf_probe")
	var output: String=input.get("output","")
	var region_data: Variant=input.get("region")
	var poses: Variant=input.get("poses")
	var mesh_limit_mib: Variant=input.get("mesh_limit_mib",1024)
	if not Contract.integer(mesh_limit_mib,1,3072) or int(mesh_limit_mib) not in [1024,3072]: return 1
	if DisplayServer.get_name()=="headless" or not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output) or not Contract.numbers(region_data,4): return 1
	if not poses is Array or poses.size()<2 or poses.size()>16: return 1
	for pose: Variant in poses:
		if not Contract.numbers(pose,3) or pose[2]<=0.0 or pose[2]>5.0: return 1
	var region := Rect2(region_data[0],region_data[1],region_data[2],region_data[3])
	if not region.has_area(): return 1
	var package: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not package is Dictionary or not package.has("native"): return 1
	var native := preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
	if not native.read(package.native): return 1
	var map_bounds: Rect2=native.catalog.full_grid.bounds
	var stack: Array=native._partition_roots.get("lod5_full",native.catalog.configurations.lod5_full).duplicate()
	var leaves: Array[Dictionary]=[]
	var physical: Dictionary={}
	while not stack.is_empty():
		var entry: Dictionary=stack.pop_back()
		var intersects := false
		for kind in 3:
			var box: AABB=entry.boxes[kind]
			if int(entry.triangles[kind])>0 and region.intersects(Rect2(box.position.x,box.position.z,box.size.x,box.size.z),true): intersects=true
		if not intersects: continue
		if not entry.get("children",[]).is_empty(): stack.append_array(entry.children);continue
		leaves.append(entry)
		physical.merge(native.pages[entry.path].components,true)
	var charged := 0
	for descriptor: Dictionary in physical.values(): charged+=int(descriptor.bytes)
	print("[Static leaf probe] leaves=",leaves.size()," physical=",physical.size()," bytes=",charged)
	# 独立候选明确计费；整图仅显式3072MiB探针允许，不改变正式流送预算。
	if leaves.is_empty() or charged>int(mesh_limit_mib)*1024*1024 or DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1600,900);viewport.own_world_3d=true;viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	parent.add_child(viewport)
	var basis := MapProjection.camera_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var ground := MapProjection.ground_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=10000
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=0.8;sun.shadow_enabled=false
	viewport.add_child(sun)
	var shader := Shader.new()
	shader.code=preload("res://scripts/rendering/tokyo_hlod_surface.gd").native_code()
	var materials: Array[ShaderMaterial]=[]
	for kind in 3:
		var material := ShaderMaterial.new()
		material.shader=shader;material.set_shader_parameter("facade_detail",kind==1)
		materials.append(material)
	var loading_started := Time.get_ticks_usec()
	var loaded: Dictionary={}
	for path: String in physical:
		if FileAccess.get_sha256(path)!=physical[path].sha256: return 1
		loaded[path]=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if loaded[path]==null: return 1
		if loaded.size()%32==0: await parent.get_tree().process_frame
	var mesh_nodes := 0
	for entry: Dictionary in leaves:
		var page := preload("res://scripts/rendering/tokyo_component_page.gd").assemble(native.pages[entry.path],loaded)
		if page==null: return 1
		for kind in 3:
			if int(entry.triangles[kind])==0: continue
			preload("res://scripts/tests/tokyo_partition_render_probe.gd").add_mesh(viewport,page.meshes[kind],ground,materials[kind])
			mesh_nodes+=1
		if mesh_nodes%48==0: await parent.get_tree().process_frame
	var loading_usec := Time.get_ticks_usec()-loading_started
	var screen := TextureRect.new()
	screen.texture=viewport.get_texture();screen.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	screen.size=Vector2(1600,900);screen.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(screen)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var shots: Array=[]
	for pose: Array in poses:
		var half_view := Vector2(800,450)/float(pose[2])
		var center := Vector2(pose[0],pose[1]).clamp(map_bounds.position+half_view,map_bounds.end-half_view)
		camera.size=900.0/float(pose[2])
		camera.transform=Transform3D(basis,ground*Vector3(center.x,0,center.y)+basis.z*3000)
		for frame in 4: await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image.save_png(output.path_join("pose_%02d.png"%shots.size()))!=OK: return 1
		shots.append({"requested_pose":pose,"actual_pose":[center.x,center.y,pose[2]],"clamped_to_source_extent":center!=Vector2(pose[0],pose[1]),
			"coverage":preload("res://scripts/tests/tokyo_hlod_edge_audit.gd").alpha_coverage(image)})
	# 无读回巡检独立计时；没有战斗演员，因此只能作为地图成本探针。
	var started := Time.get_ticks_usec()
	var previous := started
	var frames := 0
	var slow := 0
	var worst := 0
	var drawn_started := Engine.get_frames_drawn()
	while Time.get_ticks_usec()-started<10000000:
		var elapsed := float(Time.get_ticks_usec()-started)/1000000.0
		var weight := 1.0-absf(fposmod(elapsed,1.0)*2.0-1.0)
		var center := Vector2(poses[0][0],poses[0][1]).lerp(Vector2(poses[1][0],poses[1][1]),weight)
		camera.size=900.0/lerpf(1.25,3.2,absf(sin(elapsed*PI*0.5)))
		camera.transform=Transform3D(basis,ground*Vector3(center.x,0,center.y)+basis.z*3000)
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var interval := now-previous
		frames+=1;slow+=int(interval>16666);worst=maxi(worst,interval);previous=now
	var report := {"source":binding,"region":region_data,"leaves":leaves.size(),"physical_meshes":physical.size(),"mesh_nodes":mesh_nodes,
		"mesh_charge":charged,"mesh_limit_mib":mesh_limit_mib,"loading_usec":loading_usec,"shots":shots,"probe_frames":frames,"probe_frames_below_60":slow,
		"probe_worst_usec":worst,"probe_avg_fps":float(frames)*1000000.0/float(previous-started),"vsync_mode":DisplayServer.window_get_vsync_mode(),
		"drawn_frames":Engine.get_frames_drawn()-drawn_started,"screen_composited":true,"map_bounds":str(map_bounds),
		"probe_map_load_calls_during_patrol":0,"runtime_integrated":false,"combat_verified":false,"performance_accepted":false,"full_map_verified":false}
	screen.queue_free()
	viewport.queue_free()
	await parent.get_tree().process_frame
	loaded.clear()
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(report,"\t"));file.close()
	return 0
