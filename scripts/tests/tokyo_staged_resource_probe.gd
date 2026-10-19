extends RefCounted
## 分阶段对象存活取证；资源计数/弱引用不是驱动暂存释放证明。
const Saved := preload("res://scripts/tests/tokyo_selectable_geometry_save.gd")

static func counters() -> Dictionary:
	return {"texture":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),"buffer":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),"static_memory":OS.get_static_memory_usage()}

static func run(parent: Node,input: Dictionary) -> int:
	if DisplayServer.get_name()=="headless":return 1
	var binding: Dictionary=input.staged_resource_probe
	if FileAccess.get_sha256(binding.path)!=binding.sha256 or FileAccess.file_exists(input.output):return 1
	var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if contract.ready or contract.formal_enabled or contract.meshes.size()!=3:return 1
	# 基线跨过默认viewport首帧初始化，避免把通用渲染缓冲算到候选资源。
	for frame in 4:await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	var baseline := counters();var meshes: Array[ArrayMesh]=[];var textures: Array[ImageTexture]=[];var probes: Array[WeakRef]=[]
	var packed_bytes := 0;var images_released := true;var stage_samples: Array[Dictionary]=[]
	for row: Dictionary in contract.meshes:
		if FileAccess.get_sha256(row.path)!=row.sha256:return 1
		var mesh: ArrayMesh=ResourceLoader.load(row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if mesh==null or mesh.get_surface_count()!=1:return 1
		# 保存阶段已逐通道回读并绑定SHA；运行加载禁止再次通过_surfaces触发GPU读回。
		if mesh.surface_get_array_len(0)!=int(row.vertices) or mesh.surface_get_array_index_len(0)!=int(row.capacity)*3:return 1
		packed_bytes+=int(row.packed_bytes);meshes.append(mesh);probes.append(weakref(mesh));mesh=null
		stage_samples.append({"kind":"mesh_return","path":row.path,"counters":counters()})
	# 记录阶段边界，不因此把第三份上传费用从资格账中抹除。
	RenderingServer.force_sync()
	await RenderingServer.frame_post_draw
	var geometry_counters := counters()
	var texture_bytes := 0
	for bank: Dictionary in contract.texture_banks:
		for name in ["payload","blocks","mips","tiles"]:
			var row: Dictionary=bank.files[name]
			if FileAccess.get_sha256(row.path)!=row.sha256:return 1
			var data := FileAccess.get_file_as_bytes(row.path)
			if data.size()!=int(row.bytes):return 1
			var format_value := Image.FORMAT_RGBA8 if name=="payload" else (Image.FORMAT_RGF if name=="tiles" else Image.FORMAT_RGBAF)
			var image := Image.create_from_data(int(row.width),int(row.height),false,format_value,data)
			if image==null:return 1
			var image_probe: WeakRef=weakref(image)
			var texture := ImageTexture.create_from_image(image)
			if texture==null:return 1
			textures.append(texture);probes.append(weakref(texture));texture_bytes+=data.size()
			data.clear();image=null;texture=null
			images_released=images_released and image_probe.get_ref()==null
			stage_samples.append({"kind":"texture_return","path":row.path,"counters":counters()})
	var cpu_arrays: Array[PackedByteArray]=[]
	if contract.has("fixed_cpu_files"):
		# 授权的候选整包诊断：复用保存差分，不解码或展开离线顶点。
		for row: Dictionary in contract.fixed_cpu_files:
			if FileAccess.get_sha256(row.path)!=row.sha256:return 1
			var data := FileAccess.get_file_as_bytes(row.path)
			if data.size()!=int(row.bytes):return 1
			cpu_arrays.append(data)
		for size: int in contract.fixed_workspace_bytes:
			if size<0 or size>8388608:return 1
			var data := PackedByteArray()
			if data.resize(size)!=OK:return 1
			data.fill(0);cpu_arrays.append(data)
	for row: Dictionary in [contract.shared_native_indices]+contract.shared_plane_indices:
		if contract.has("fixed_cpu_files"):break
		var data := Saved.unpack(row)
		if data.is_empty():return 1
		cpu_arrays.append(data)
	for domain: Dictionary in contract.domains:
		for row: Dictionary in [domain.native_mask,domain.plane_mask]:
			var data := Saved.unpack(row)
			if data.is_empty():return 1
			cpu_arrays.append(data)
	for row: Dictionary in contract.meshes:
		for copy in 2:
			var data := PackedByteArray();data.resize(int(row.capacity)*12);cpu_arrays.append(data)
	for size in [int(contract.shared_native_indices.decoded_bytes)/12,int(contract.plane_bank_offsets[2])]:
		if contract.has("fixed_cpu_files"):break
		var data := PackedByteArray();data.resize(size);cpu_arrays.append(data)
	var cpu_bytes := 0
	for data: PackedByteArray in cpu_arrays:cpu_bytes+=data.size()
	if cpu_bytes!=int(contract.known_charge.native_cpu_indices_masks_two_updates)+int(contract.known_charge.plane_cpu_indices_masks_two_updates):return 1
	RenderingServer.force_sync();await RenderingServer.frame_post_draw
	var resident_counters := counters();var live := 0
	for probe: WeakRef in probes:live+=int(probe.get_ref()!=null)
	meshes.clear();textures.clear();cpu_arrays.clear()
	for frame in 4:await parent.get_tree().process_frame
	RenderingServer.force_sync();await RenderingServer.frame_post_draw
	var remaining := 0
	for probe: WeakRef in probes:remaining+=int(probe.get_ref()!=null)
	var report := {"baseline":baseline,"geometry_phase":geometry_counters,"resident_phase":resident_counters,"released_phase":counters(),"packed_geometry_bytes":packed_bytes,"texture_bytes":texture_bytes,"cpu_index_workspace_bytes":cpu_bytes,"cpu_images_released":images_released,"live_objects":live,"remaining_objects":remaining,"driver_transient_release_verified":false,"joint_budget_qualified":false,"visual_map_verified":false,"formal_enabled":false}
	report["load_path_gpu_readback"]=false
	report["stage_samples"]=stage_samples
	report["samples_bound_in_call_peak"]=false
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(report,"\t"));file.close();print("Staged resource objects: ",JSON.stringify(report))
	return 0 if images_released and live==11 and remaining==0 else 1
