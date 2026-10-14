extends RefCounted
## 同一已存资源的连续位置选择与首帧重放；GPU读回不作性能证据。
const Selector := preload("res://scripts/experiments/tokyo_cell_index_selector.gd")
const Audit := preload("res://scripts/tests/tokyo_residential_packet_audit.gd")

static func prepare(input: Dictionary) -> Dictionary:
	for binding: Dictionary in [input.residential_saved_load.packet,input.texture_contract,input.coverage]:
		if FileAccess.get_sha256(binding.path)!=binding.sha256:return {}
	var packet: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.residential_saved_load.packet.path))
	var textures: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.texture_contract.path))
	var coverage: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.coverage.path))
	if not Audit.valid_contract(packet,textures,coverage,input.residential_saved_load.packet.sha256):return {}
	if not packet.get("continuous_scale_geometry_capacity_verified",false):return {}
	if packet.view_bounds_evaluated_at_min_scale!=packet.scale_interval[0] or packet.geometry_relief_evaluated_at_max_scale!=packet.scale_interval[1]:return {}
	var normalized := {"rows":[],"vertices_sha256":packet.vertices.sha256,"selection_sha256":input.residential_saved_load.packet.sha256,
		"cell_index_union_conservative":true,"continuous_capacity_verified":true,"continuous_scale_capacity_verified":true}
	for i in packet.rows.size():
		var row: Dictionary=packet.rows[i]
		normalized.rows.append({"scale_interval":packet.scale_interval,"scale":packet.scale,"rotation":packet.rotation,"tilt_degrees":packet.tilt_degrees,
			"viewport":packet.viewport,"camera_bounds":row.camera_bounds,"certificate_leaf":i,"sha256":row.indices.sha256})
	return {"packet":normalized,"bounds":coverage.camera_domain,"interval":packet.scale_interval}

static func route(bounds: Array, interval: Array) -> Array:
	var lo := Vector2(float(bounds[0])+0.01,float(bounds[1])+0.01)
	var hi := Vector2(float(bounds[2])-0.01,float(bounds[3])-0.01)
	var mid := (lo+hi)*0.5
	var anchors := [lo,Vector2(hi.x,lo.y),hi,Vector2(lo.x,hi.y),lo,hi,Vector2(hi.x,lo.y),Vector2(lo.x,hi.y),mid]
	var poses: Array=[]
	for segment in anchors.size()-1:
		for step in 16:
			var center: Vector2=anchors[segment].lerp(anchors[segment+1],float(step)/15.0)
			# 每相邻帧跨越缩放方向，包含两端和中间非档位尺度。
			var phase := float((segment*16+step)%17)/16.0
			if segment%2:phase=1.0-phase
			poses.append([center.x,center.y,lerpf(float(interval[0]),float(interval[1]),phase)])
	return poses

static func rejection_checks(packet: Dictionary, resident: Dictionary, center: Vector2, interval: Array, bounds: Array) -> int:
	var count := 0
	for bad: Dictionary in [{"geometry_ready":false},{"textures_ready":false},{"vertices_sha256":"wrong"},{"selection_sha256":"wrong"},{"index_identities":{}}]:
		var state := resident.duplicate(true);state.merge(bad,true)
		if not Selector.select(packet,center,float(interval[0]),0,38,Vector2i(1600,900),state).is_empty():return -1
		count+=1
	for pose: Array in [[center,float(interval[0])-0.001,0,38,Vector2i(1600,900)],
		[center,float(interval[1])+0.001,0,38,Vector2i(1600,900)],
		[center,float(interval[0]),0.1,38,Vector2i(1600,900)],
		[center,float(interval[0]),0,37,Vector2i(1600,900)],
		[center,float(interval[0]),0,38,Vector2i(1920,1080)],
		[Vector2(float(bounds[0])-1,center.y),float(interval[0]),0,38,Vector2i(1600,900)],
		[Vector2(INF,center.y),float(interval[0]),0,38,Vector2i(1600,900)],
		[center,NAN,0,38,Vector2i(1600,900)]]:
		if not Selector.select(packet,pose[0],pose[1],pose[2],pose[3],pose[4],resident).is_empty():return -1
		count+=1
	return count

static func digest(image: Image) -> String:
	var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data())
	return hash.finish().hex_encode()

static func run(viewport: SubViewport, camera: Camera3D, basis: Basis, ground: Basis, input: Dictionary, state: Dictionary) -> Dictionary:
	var prepared := prepare(input)
	if prepared.is_empty():return {"passed":false,"reason":"invalid_contract"}
	var packet: Dictionary=prepared.packet
	var resident := {"geometry_ready":state.meshes.size()==3,"textures_ready":state.materials.size()==2,
		"vertices_sha256":packet.vertices_sha256,"selection_sha256":packet.selection_sha256,"index_identities":{}}
	for row: Dictionary in packet.rows:resident.index_identities[row.sha256]=true
	var poses := route(prepared.bounds,prepared.interval)
	var center := Vector2(poses[0][0],poses[0][1])
	var rejected := rejection_checks(packet,resident,center,prepared.interval,prepared.bounds)
	if rejected<0:return {"passed":false,"reason":"scope_rejection"}
	var hashes: Array[String]=[];var rows: Array=[];var cells: Dictionary={};var changes := 0
	var passed := true;var previous := -1
	# 第一遍不在单点等待稳定帧；第二遍独立重放，不掩盖移动中的迟到提交。
	for pass_id in 2:
		for i in poses.size():
			var pose: Array=poses[i];center=Vector2(pose[0],pose[1])
			var chosen := Selector.select(packet,center,float(pose[2]),0,38,viewport.size,resident)
			if chosen.is_empty():return {"passed":false,"reason":"legal_pose_missing","pose":pose}
			var cell := int(chosen.leaf)
			if cell!=previous:
				RenderingServer.call("mesh_surface_update_index_region",state.meshes[0].get_rid(),0,0,state.indices[cell])
				if pass_id==0:changes+=1
			previous=cell
			camera.size=900.0/float(pose[2])
			camera.transform=Transform3D(basis,ground*Vector3(center.x,0,center.y)+basis.z*3000)
			await RenderingServer.frame_post_draw
			if pass_id==1:
				for frame in 3:await RenderingServer.frame_post_draw
			var picture := viewport.get_texture().get_image();var value := digest(picture)
			if pass_id==0:
				hashes.append(value);cells[cell]=true
				rows.append({"pose":pose,"cell":cell,"moving_sha256":value})
				if i%32==0 and picture.save_png(input.preview_directory.path_join("route%03d.png"%i))!=OK:passed=false
			else:
				rows[i]["stable_sha256"]=value;rows[i]["equal"]=hashes[i]==value
				passed=passed and hashes[i]==value
	passed=passed and cells.size()==4 and changes>=8
	return {"passed":passed,"poses":rows,"visited_cells":cells.size(),"index_changes":changes,"rejection_cases":rejected,
		"continuous_moving_frames":poses.size(),"performance_verified":false,"full_map_verified":false}
