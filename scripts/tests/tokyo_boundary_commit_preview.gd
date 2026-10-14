extends RefCounted
## 显式候选实景：真实三层提交；准备期间镜头继续移动，缺就绪不冒充连续覆盖。
const Sparse := preload("res://scripts/tests/tokyo_sparse_mip_sampler.gd")
const Layered := preload("res://scripts/tests/tokyo_layered_sampler.gd")
const Surface := preload("res://scripts/rendering/tokyo_hlod_surface.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Preparation := preload("res://scripts/tests/tokyo_delta_preparation.gd")
const Hash := preload("res://scripts/tests/tokyo_nine_domain_preview.gd")

static func pose(camera: Camera3D, center: Vector2, scale_value: float) -> void:
	var ground := MapProjection.ground_basis(Transform2D.IDENTITY,deg_to_rad(38))
	var basis := MapProjection.camera_basis(Transform2D.IDENTITY,deg_to_rad(38))
	camera.size=900.0/scale_value
	camera.transform=Transform3D(basis,ground*Vector3(center.x,0,center.y)+basis.z*3000)

static func prepare(parent: Node, state: Dictionary, layers: Array, camera: Camera3D, moving: bool, budget_us: int=0, cancel_after_frames: int=0) -> Dictionary:
	var outputs: Array[PackedByteArray]=[]
	var frames := 0
	var maximum_step_us := 0
	var maximum_slice_us := 0;var maximum_finalize_us := 0
	var requested_at := Time.get_ticks_usec()
	for bank in 3:
		var row: Dictionary=state.layers[bank]
		if FileAccess.get_sha256(row.path)!=row.sha256:return {}
		var worker := Preparation.new()
		if not worker.begin(FileAccess.get_file_as_bytes(row.path),int(row.indices),int(row.vertices)):return {}
		while not worker.ready():
			var slice_start := Time.get_ticks_usec()
			while not worker.ready():
				var start := Time.get_ticks_usec()
				if not worker.step():return {}
				maximum_step_us=maxi(maximum_step_us,Time.get_ticks_usec()-start)
				if budget_us<=0 or Time.get_ticks_usec()-slice_start>=budget_us:break
			maximum_slice_us=maxi(maximum_slice_us,Time.get_ticks_usec()-slice_start)
			frames+=1
			if moving:
				# 故意持续移动；这些帧尚无覆盖保证，单列而不作为通过样本。
				pose(camera,Vector2(1472+48*sin(frames*0.04),-15232),0.5+0.04*sin(frames*0.03))
			await parent.get_tree().process_frame
			if cancel_after_frames>0 and frames>=cancel_after_frames:
				worker.cancel();outputs.clear();return {}
		var finalize_start := Time.get_ticks_usec()
		var bytes := worker.take()
		if Hash.digest(bytes)!=row.decoded_sha256:return {}
		var capacity := int(layers[bank].index_capacity)
		if bytes.size()>capacity*4:return {}
		if int(layers[bank].index_stride)==2:
			var short_bytes := PackedByteArray();short_bytes.resize(capacity*2);short_bytes.fill(0)
			for n in int(row.indices):
				var value := bytes.decode_u32(n*4)
				if value>65535:return {}
				short_bytes.encode_u16(n*2,value)
			bytes=short_bytes
		else:
			var old_size := bytes.size();bytes.resize(capacity*4)
			for n in range(old_size,bytes.size(),4):bytes.encode_u32(n,0)
		outputs.append(bytes)
		maximum_finalize_us=maxi(maximum_finalize_us,Time.get_ticks_usec()-finalize_start)
	return {"outputs":outputs,"frames":frames,"maximum_step_us":maximum_step_us,"maximum_slice_us":maximum_slice_us,"maximum_finalize_us":maximum_finalize_us,"request_to_ready_us":Time.get_ticks_usec()-requested_at,"budget_us":budget_us}

static func prepare_upload(parent: Node, state: Dictionary, layers: Array, camera: Camera3D, moving: bool, cancel_after_frames: int=0, audit_viewport: SubViewport=null) -> Dictionary:
	# 只读取当前请求的三层；离线逐项还原证明绑定SHA，不常驻四套展开状态。
	var requested_at := Time.get_ticks_usec();var longest := 0;var frames := 0
	var outputs: Array[PackedByteArray]=[]
	var pending_hashes: Array[String]=[]
	for bank in 3:
		var row: Dictionary=state.layers[bank].get("upload_ready",{})
		if row.is_empty() or int(row.bytes)!=int(layers[bank].index_capacity)*int(layers[bank].index_stride):return {}
		var start := Time.get_ticks_usec()
		var bytes := FileAccess.get_file_as_bytes(row.path)
		if bytes.size()!=int(row.bytes) or Hash.digest(bytes)!=row.sha256:return {}
		outputs.append(bytes);bytes=PackedByteArray()
		longest=maxi(longest,Time.get_ticks_usec()-start);frames+=1
		if moving:pose(camera,Vector2(1472+48*sin(frames*0.04),-15232),0.5+0.04*sin(frames*0.03))
		await parent.get_tree().process_frame
		if audit_viewport!=null:
			await RenderingServer.frame_post_draw
			pending_hashes.append(Hash.digest(audit_viewport.get_texture().get_image().get_data()))
		if cancel_after_frames>0 and frames>=cancel_after_frames:outputs.clear();return {}
	return {"outputs":outputs,"frames":frames,"maximum_read_hash_us":longest,"request_to_ready_us":Time.get_ticks_usec()-requested_at,"upload_ready":true,"pending_hashes":pending_hashes}

static func interactive(parent: Node, camera: Camera3D, meshes: Array[ArrayMesh], groups: Array, center_x: float, threshold: float, seconds: float) -> Dictionary:
	# 局部检查窗口明确限制范围，不把限制当作全图连续覆盖。
	var start := Time.get_ticks_msec();var last := start
	var offset := 0.0;var zoom := threshold;var previous := -1;var commits := 0;var inputs := 0
	while Time.get_ticks_msec()-start<int(seconds*1000):
		var now := Time.get_ticks_msec();var dt := minf(float(now-last)/1000.0,0.05);last=now
		var horizontal := float(Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_LEFT))
		var vertical := float(Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_DOWN))
		if horizontal!=0 or vertical!=0:inputs+=1
		offset=clampf(offset+horizontal*40.0*dt,-20,20)
		zoom=clampf(zoom+vertical*0.12*dt,threshold-0.06,threshold+0.06)
		var selected := 0 if zoom<threshold else 1
		if previous!=selected:
			for i in 3:RenderingServer.call("mesh_surface_update_index_region",meshes[i].get_rid(),0,0,groups[selected][i])
			previous=selected;commits+=1
		pose(camera,Vector2(center_x+offset,-15232),zoom)
		await parent.get_tree().process_frame
	return {"interactive_seconds":seconds,"input_frames":inputs,"commits":commits,"user_acceptance":false}

static func local_state(center: Vector2, scale_value: float, x_offset: float=0.0) -> int:
	center.x-=x_offset
	if not center.is_finite() or not is_finite(scale_value) or scale_value<0.4 or scale_value>0.625:return -1
	var base := 0 if center.x>=1472 else 2
	var source_x := 1536.0 if base==0 else 1408.0
	if absf(center.x-source_x)>64 or absf(center.y+15232)>64:return -1
	return base+int(scale_value>=2.0/(12.0*0.5*sin(deg_to_rad(38))))

static func run(parent: Node, input: Dictionary) -> int:
	if DisplayServer.get_name()=="headless" or FileAccess.file_exists(input.output):return 1
	var binding: Dictionary=input.boundary_commit_preview
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var c: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if c.formal_enabled or c.layers.size()!=3 or c.states.size()!=4:return 1
	var meshes: Array[ArrayMesh]=[];var materials: Array[ShaderMaterial]=[];var probes: Array[WeakRef]=[]
	for row: Dictionary in c.layers:
		if FileAccess.get_sha256(row.path)!=row.sha256:return 1
		var mesh: ArrayMesh=ResourceLoader.load(row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if mesh==null or mesh.get_surface_count()!=1 or mesh.surface_get_array_index_len(0)!=int(row.index_capacity):return 1
		meshes.append(mesh);probes.append(weakref(mesh));mesh=null
	for bank: Dictionary in c.texture_banks:
		var built := Layered.build(bank.manifest) if input.get("layered_textures",false) else Sparse.build(bank.manifest)
		if built.is_empty() or not built.shared_palette:return 1
		var material: ShaderMaterial=built.material
		var textures: Array=[]
		for i in 4:textures.append(material.get_shader_parameter("page%d"%i));probes.append(weakref(textures[i]))
		var sampling := Layered.sampler_code() if input.get("layered_textures",false) else Sparse.sampler_code(true)
		material.shader.code=Surface.textured_code().replace("sample_color.a<0.001","sample_color.a<0.5").replace("void fragment() {",sampling+"\nvoid fragment() {").replace("texture(overview,UV)","read_tile(UV,UV2.x)")
		for i in 4:material.set_shader_parameter("page%d"%i,textures[i])
		materials.append(material);built.clear();textures.clear();material=null
	var viewport := SubViewport.new();viewport.size=Vector2i(1600,900);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;parent.add_child(viewport)
	var display: TextureRect
	if input.get("interactive_preview",false):
		display=TextureRect.new();display.texture=viewport.get_texture()
		display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;display.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		parent.add_child(display);display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		DisplayServer.window_set_title("Tokyo candidate / LOCAL ONLY / Left-Right pan, Up-Down zoom / timed preview")
	var camera := Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.far=10000;viewport.add_child(camera)
	var sun := DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-35,0);sun.light_energy=.8;viewport.add_child(sun)
	var native := ShaderMaterial.new();native.shader=Shader.new();native.shader.code=Surface.native_code()
	var nodes: Array[MeshInstance3D]=[]
	for i in 3:
		var node := MeshInstance3D.new();node.mesh=meshes[i]
		node.transform=Transform3D(MapProjection.ground_basis(Transform2D.IDENTITY,deg_to_rad(38)),Vector3.ZERO)
		node.material_override=native if i==0 else materials[i-1];viewport.add_child(node);nodes.append(node)
	var failures: Array=[];var results: Array=[];var moving_unqualified_frames := 0
	DirAccess.make_dir_recursive_absolute(input.preview_directory)
	pose(camera,Vector2(1536,-15232),0.5)
	if input.get("four_ready",false):
		# 替换旧差分常驻和双输出，而非在它们之上追加四状态缓存。
		var groups: Array=[];var cached_bytes := 0
		for state: Dictionary in c.states:
			var prepared := await prepare_upload(parent,state,c.layers,camera,false)
			if prepared.is_empty():failures.append("four_prepare");break
			groups.append(prepared.outputs);prepared.clear()
			for bytes: PackedByteArray in groups.back():cached_bytes+=bytes.size()
		var hashes: Array[String]=[];var edges: Dictionary={};var previous := -1
		var poses: Array=[]
		for target in [0,1,2,3,0,2,1,3,1,0,3,2,0]:poses.append([target,c.states[target].source_center[0],c.states[target].source_center[1],0.5 if target%2==0 else 0.625])
		var rejected := 0
		if input.has("layer_updates") and groups.size()==4:
			var initial_state := int(input.get("update_initial_state",2))
			for i in 3:RenderingServer.call("mesh_surface_update_index_region",meshes[i].get_rid(),0,0,groups[initial_state][i])
			pose(camera,Vector2(1408,-15232),0.5)
			for frame in 3:await RenderingServer.frame_post_draw
			var moving_pose := func(center: Vector2, scale_value: float): pose(camera,center,scale_value)
			var update_result := await Layered.apply_updates(parent,materials,viewport,input.layer_updates,moving_pose if input.get("moving_layer_updates",false) else Callable())
			results.append(update_result)
			if not update_result.get("passed",false):failures.append("layer_updates")
			poses=[[2,1408,-15232,0.5],[3,1408,-15232,0.625]]
		if input.get("continuous_local",false):
			var route_offset := float(input.get("route_x_offset",0.0))
			var evidence: Dictionary=input.source_bounds
			if FileAccess.get_sha256(evidence.path)!=evidence.sha256:return 1
			poses.clear()
			for frame in 96:
				var phase := float(frame)/95.0*TAU
				var center := Vector2(1472+route_offset+128*cos(phase),-15232+64*sin(phase))
				var scale_value := 0.4+0.225*(1+sin(phase*2))*0.5
				poses.append([local_state(center,scale_value,route_offset),center.x,center.y,scale_value])
			for invalid in [[1343,-15232,.5],[1601,-15232,.5],[1472,-15297,.5],[1472,-15167,.5],[1472,-15232,.399],[1472,-15232,.626]]:
				if local_state(Vector2(invalid[0]+route_offset,invalid[1]),invalid[2],route_offset)==-1:rejected+=1
			if rejected!=6:failures.append("domain_rejection")
		var expected_cached_bytes := 0
		for layer: Dictionary in c.layers:expected_cached_bytes+=4*int(layer.index_capacity)*int(layer.index_stride)
		if groups.size()==4 and cached_bytes==expected_cached_bytes:
			for desired: Array in poses:
				var target := int(desired[0])
				if target<0:failures.append("domain_route");break
				# 没有等待、读取或状态预测；三层与目标相机一起发布。
				for i in 3:RenderingServer.call("mesh_surface_update_index_region",meshes[i].get_rid(),0,0,groups[target][i])
				pose(camera,Vector2(desired[1],desired[2]),desired[3])
				await RenderingServer.frame_post_draw
				var immediate := Hash.digest(viewport.get_texture().get_image().get_data())
				for frame in 3:await RenderingServer.frame_post_draw
				var stable := Hash.digest(viewport.get_texture().get_image().get_data())
				if immediate!=stable:failures.append("four_settle_%d"%target)
				if not input.get("continuous_local",false) and immediate!=String(input.expected_hashes[target]):failures.append("four_target_%d"%target)
				hashes.append(immediate)
				if previous>=0:edges["%d>%d"%[previous,target]]=true
				previous=target
		else:failures.append("four_capacity")
		results.append({"poses":hashes.size(),"directed_edges":edges.size(),"rejected_outside_requests":rejected,"route_hashes":hashes,"cached_upload_bytes":cached_bytes,"delta_buffers_loaded":false,"extra_double_buffers_allocated":false,"known_joint_replacement_bytes":c.get("known_joint_bytes",0),"budget_qualified":false,"independent_source_coverage_verified":false})
		if not input.get("continuous_local",false) and not input.has("layer_updates") and edges.size()!=12:failures.append("four_edges")
		if input.get("continuous_local",false) and hashes.size()!=96:failures.append("continuous_route_count")
		groups.clear()
	if input.get("paired_route",false):
		var cross_zoom: bool=input.get("cross_zoom",false)
		var threshold := 2.0/(12.0*0.5*sin(deg_to_rad(38)))
		for mode in 2:
			var first_id := mode*2 if cross_zoom else mode
			var second_id := first_id+1 if cross_zoom else mode+2
			var first := await prepare(parent,c.states[first_id],c.layers,camera,false)
			var second := await prepare(parent,c.states[second_id],c.layers,camera,false)
			if first.is_empty() or second.is_empty():failures.append("pair_prepare");break
			var groups: Array=[first.outputs,second.outputs]
			first.clear();second.clear()
			var cached_bytes := 0
			for group: Array in groups:
				for bytes: PackedByteArray in group:cached_bytes+=bytes.size()
			if input.get("interactive_preview",false):
				var interaction := await interactive(parent,camera,meshes,groups,float(c.states[first_id].source_center[0]),threshold,clampf(float(input.get("interactive_seconds",20)),1,60))
				interaction["cached_upload_bytes"]=cached_bytes;interaction["state_pair"]=[first_id,second_id]
				results.append(interaction)
				viewport.get_texture().get_image().save_png(input.preview_directory.path_join("interactive%d.png"%mode))
				groups.clear();continue
			var hashes: Array[String]=[];var switches := 0
			for pass_id in 2:
				var previous := -1
				for frame in 48:
					var phase := float(frame)/47.0
					var center := Vector2(1472+64*cos(phase*TAU),-15232)
					var scale_value := (0.48 if mode==0 else 0.58)+0.02*sin(phase*TAU)
					var selected := 0 if center.x>=1472 else 1
					if cross_zoom:
						center=Vector2(c.states[first_id].source_center[0]+20*sin(phase*TAU),-15232)
						scale_value=threshold+0.06*sin(phase*TAU)
						selected=0 if scale_value<threshold else 1
					if selected!=previous:
						for i in 3:RenderingServer.call("mesh_surface_update_index_region",meshes[i].get_rid(),0,0,groups[selected][i])
						if pass_id==0:switches+=1
						previous=selected
					pose(camera,center,scale_value)
					await RenderingServer.frame_post_draw
					if pass_id==1:
						for settle in 3:await RenderingServer.frame_post_draw
					var picture := viewport.get_texture().get_image()
					var value := Hash.digest(picture.get_data())
					if pass_id==0:
						hashes.append(value)
						if frame in [0,12,24,36]:picture.save_png(input.preview_directory.path_join("route%d-frame%d.png"%[mode,frame]))
					elif value!=hashes[frame]:failures.append("route_settle_%d_%d"%[mode,frame])
					picture=null
			results.append({"mode":mode,"poses":48,"switches":switches,"cached_upload_bytes":cached_bytes,"route_hashes":hashes,"cross_zoom":cross_zoom,"threshold":threshold,"state_pair":[first_id,second_id]})
			groups.clear()
		print("[boundary-preview] paired routes=",results.size()," failures=",failures)
	for state: Dictionary in c.states:
		if input.get("four_ready",false):break
		if input.get("paired_route",false):break
		if input.has("only_state") and int(state.state)!=int(input.only_state):continue
		if input.get("cancel_during_prepare",false) and int(state.state)==1:
			var before_cancel := Hash.digest(viewport.get_texture().get_image().get_data())
			var cancelled: Dictionary
			if input.get("upload_ready",false):cancelled=await prepare_upload(parent,state,c.layers,camera,false,2)
			else:cancelled=await prepare(parent,state,c.layers,camera,false,int(input.get("prepare_budget_us",0)),2)
			await RenderingServer.frame_post_draw
			if not cancelled.is_empty() or before_cancel!=Hash.digest(viewport.get_texture().get_image().get_data()):failures.append("cancel_published_partial")
		var ready: Dictionary
		var audit_pending: bool=input.get("audit_pending",false) and int(state.state)>0
		if audit_pending:pose(camera,Vector2(state.source_center[0],state.source_center[1]),0.5 if int(state.state)%2==0 else 0.625)
		if input.get("upload_ready",false):ready=await prepare_upload(parent,state,c.layers,camera,int(state.state)>0 and not audit_pending,0,viewport if audit_pending else null)
		else:ready=await prepare(parent,state,c.layers,camera,int(state.state)>0,clampi(int(input.get("prepare_budget_us",0)),0,2000))
		if ready.is_empty():failures.append("prepare_%d"%int(state.state));break
		if int(state.state)>0:moving_unqualified_frames+=int(ready.frames)
		var center := Vector2(state.source_center[0],state.source_center[1])
		var scale_value := 0.5 if int(state.state)%2==0 else 0.625
		# 所有层已完成并核摘要，更新与镜头提交之间无await。
		for i in 3:RenderingServer.call("mesh_surface_update_index_region",meshes[i].get_rid(),0,0,ready.outputs[i])
		pose(camera,center,scale_value);ready.erase("outputs")
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		var immediate := Hash.digest(picture.get_data())
		picture=null
		for frame in 3:await RenderingServer.frame_post_draw
		picture=viewport.get_texture().get_image()
		var stable := Hash.digest(picture.get_data())
		var pending_mismatches := 0
		for pending: String in ready.get("pending_hashes",[]):
			if pending!=stable:pending_mismatches+=1
		ready["pending_mismatches"]=pending_mismatches
		var magenta := 0;var colors: Dictionary={}
		for y in range(0,900,8):
			for x in range(0,1600,8):
				var color := picture.get_pixel(x,y);colors[color.to_rgba32()]=true
				if color.r>0.95 and color.g<0.05 and color.b>0.95:magenta+=1
		if picture.save_png(input.preview_directory.path_join("state%d.png"%int(state.state)))!=OK:failures.append("save")
		picture=null
		if immediate!=stable:failures.append("settle_%d"%int(state.state))
		if magenta>0 or colors.size()<8:failures.append("pixels_%d"%int(state.state))
		results.append({"state":state.state,"prepare":ready,"immediate_sha":immediate,"stable_sha":stable,"sampled_magenta":magenta,"sampled_colors":colors.size()})
		if input.get("inspect_layers",false):
			for layer in 3:
				for i in 3:nodes[i].visible=i==layer
				for frame in 3:await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png(input.preview_directory.path_join("layer%d.png"%layer))
			for node: MeshInstance3D in nodes:node.visible=true
		print("[boundary-preview] state=",state.state," colors=",colors.size()," magenta=",magenta," equal=",immediate==stable)
	# 空白负对照，防止两个空画面相等被误判提交通过。
	for node: MeshInstance3D in nodes:node.visible=false
	for frame in 3:await RenderingServer.frame_post_draw
	var blank := Hash.digest(viewport.get_texture().get_image().get_data())
	for row: Dictionary in results:
		if row.has("stable_sha") and row.stable_sha==blank:failures.append("blank")
		for value: String in row.get("route_hashes",[]):
			if value==blank:failures.append("blank_route")
	if display!=null:display.texture=null;display.queue_free();display=null
	nodes.clear();viewport.queue_free();viewport=null;camera=null;sun=null;native=null;meshes.clear();materials.clear()
	for frame in 4:await parent.get_tree().process_frame
	var remaining := 0
	for probe: WeakRef in probes:remaining+=int(probe.get_ref()!=null)
	var expected_count := 2 if input.get("paired_route",false) else 4
	if input.get("four_ready",false):expected_count=2 if input.has("layer_updates") else 1
	if input.has("only_state"):expected_count=1
	var result := {"passed":failures.is_empty() and results.size()==expected_count and remaining==0,"states":results,"failures":failures,"remaining_resources":remaining,"moving_unqualified_frames":moving_unqualified_frames,"continuous_display_verified":false,"budget_qualified":false,"performance_verified":false,"formal_enabled":false,"vsync_mode":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"pending_readbacks_distort_timing":input.get("audit_pending",false),"scope":"explicit prepared boundary pair; no coverage oracle or readiness guarantee outside prepared states"}
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	return 0 if result.passed else 1
