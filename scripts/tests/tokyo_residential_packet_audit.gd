extends RefCounted
## 显式资源回读，不接正式地图，不将Headless当显示验收。
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Sparse := preload("res://scripts/tests/tokyo_sparse_mip_sampler.gd")

static func bytes(binding: Dictionary) -> PackedByteArray:
	if not binding.has_all(["path","sha256","bytes"]):return PackedByteArray()
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return PackedByteArray()
	var value := FileAccess.get_file_as_bytes(binding.path)
	if value.size()!=int(binding.bytes):return PackedByteArray()
	return value

static func run(input: Dictionary) -> int:
	if not input.has_all(["residential_packet_audit","texture_contract","coverage","output"]):return 1
	for binding: Dictionary in [input.residential_packet_audit,input.texture_contract,input.coverage]:
		if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var packet: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.residential_packet_audit.path))
	var textures: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.texture_contract.path))
	var coverage: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.coverage.path))
	if not valid_contract(packet,textures,coverage,input.residential_packet_audit.sha256):return 1
	# 使用真实候选生成拒绝反例；引擎运行后才形成测试证据。
	if valid_contract(packet,textures,coverage,"wrong_identity"):return 1
	var bad_coverage := coverage.duplicate(true);bad_coverage["missing_pages"]=1
	if valid_contract(packet,textures,bad_coverage,input.residential_packet_audit.sha256):return 1
	bad_coverage=coverage.duplicate(true);bad_coverage["cell_partition_gap_free"]=false
	if valid_contract(packet,textures,bad_coverage,input.residential_packet_audit.sha256):return 1
	var bad_textures := textures.duplicate(true);bad_textures.planes[0]["height"]=float(bad_textures.planes[0].height)+1.0
	if valid_contract(packet,bad_textures,coverage,input.residential_packet_audit.sha256):return 1
	bad_textures=textures.duplicate(true);bad_textures["scale_interval"]=[0.5,0.8]
	if valid_contract(packet,bad_textures,coverage,input.residential_packet_audit.sha256):return 1
	bad_textures=textures.duplicate(true);bad_textures.planes[0]["atlas"]=-1
	if valid_contract(packet,bad_textures,coverage,input.residential_packet_audit.sha256):return 1
	bad_textures.clear();bad_coverage.clear()
	var bad_capacity := packet.duplicate(true);bad_capacity["native_capacity_faces"]=240001
	if valid_contract(bad_capacity,textures,coverage,input.residential_packet_audit.sha256):return 1
	bad_capacity["native_capacity_faces"]=0
	if valid_contract(bad_capacity,textures,coverage,input.residential_packet_audit.sha256):return 1
	bad_capacity.clear()
	if DirAccess.dir_exists_absolute(input.output):return 1
	var data := bytes(packet.vertices).to_float32_array()
	if data.size()!=int(packet.vertex_count)*10:return 1
	var vertices := PackedVector3Array();var normals := PackedVector3Array();var colors := PackedColorArray()
	for i in range(0,data.size(),10):
		for j in 10:
			if not is_finite(data[i+j]):return 1
		vertices.append(Vector3(data[i],data[i+1],data[i+2]))
		normals.append(Vector3(data[i+3],data[i+4],data[i+5]))
		colors.append(Color(data[i+6],data[i+7],data[i+8],data[i+9]))
	var cached: Array[PackedInt32Array]=[];var cpu_index_bytes := 0
	for row: Dictionary in packet.rows:
		var indices := bytes(row.indices).to_int32_array()
		if indices.size()!=int(packet.native_capacity_faces)*3:return 1
		if int(row.selected_native_faces)+int(row.padding_faces)!=int(packet.native_capacity_faces):return 1
		for i in indices.size():
			if indices[i]<0 or indices[i]>=vertices.size():return 1
			if i>=int(row.selected_native_faces)*3 and indices[i]!=0:return 1
		cached.append(indices);cpu_index_bytes+=indices.size()*4
	if int(packet.native_capacity_faces)<=0 or int(packet.native_capacity_faces)+textures.planes.size()*2>240000:return 1
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=cached[0]
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var batches: Array[Dictionary]=[];var texture_bytes := 0;var plane_bytes := 0
	for atlas in packet.texture_bindings.size():
		var rows: Array=[]
		for plane: Dictionary in textures.planes:
			if int(plane.atlas)==atlas:
				var row := plane.duplicate();row["texture_index"]=int(plane.tile);rows.append(row)
		if rows.is_empty():return 1
		var batch := Sparse.build_map(packet.texture_bindings[atlas],{"rows":rows})
		if batch.is_empty():return 1
		batches.append(batch);texture_bytes+=int(batch.texture_three_copy_bytes)
		plane_bytes+=Packed.decoded_bytes(batch.mesh)
	if DirAccess.make_dir_recursive_absolute(input.output)!=OK:return 1
	var meshes: Array[ArrayMesh]=[mesh]
	for batch: Dictionary in batches:meshes.append(batch.mesh)
	var digests: Array=[];var surface_count := 0
	for i in meshes.size():
		var path: String=input.output.path_join("mesh%d.res"%i)
		if ResourceSaver.save(meshes[i],path,ResourceSaver.FLAG_COMPRESS)!=OK:return 1
		var restored: ArrayMesh=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if restored==null or Packed.corner_digest(restored)!=Packed.corner_digest(meshes[i]):return 1
		var before := meshes[i].surface_get_arrays(0);var after := restored.surface_get_arrays(0)
		for channel in [Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
			if var_to_bytes(before[channel])!=var_to_bytes(after[channel]):return 1
		digests.append(Packed.corner_digest(restored));surface_count+=restored.get_surface_count()
	# 数组费用CPU/GPU各计一份；并非驱动实际分配量。
	var known := (Packed.decoded_bytes(mesh)+plane_bytes)*2+texture_bytes+cpu_index_bytes
	var array_channels: Array=[]
	var packed_channels: Array=[]
	for item: ArrayMesh in meshes:
		var charges: Array=[]
		for channel: Variant in item.surface_get_arrays(0):
			charges.append(0 if channel==null else channel.to_byte_array().size())
		array_channels.append(charges)
		var packed: Dictionary=item.get("_surfaces")[0]
		var stored: Dictionary={}
		for key in ["vertex_data","attribute_data","skin_data","index_data"]:
			stored[key]=packed.get(key,PackedByteArray()).size()
		packed_channels.append(stored)
	var report := {"resource_roundtrip_verified":true,"contract_rejection_cases":8,"surface_count":surface_count,"corner_digests":digests,
		"array_channel_bytes":array_channels,"native_decoded_bytes":Packed.decoded_bytes(mesh),"plane_decoded_bytes":plane_bytes,
		"packed_channel_bytes":packed_channels,
		"known_resource_bytes":known,"budget_bytes":201326592,"within_known_budget":known<=201326592,
		"cpu_index_bytes":cpu_index_bytes,"texture_three_copy_bytes":texture_bytes,
		"driver_allocations_measured":false,"geometry_array_copy_charge":2,
		"visual_verified":false,"draw_calls_verified":false,"performance_verified":false,"runtime_integrated":false}
	var file := FileAccess.open(input.output.path_join("report.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("Tokyo residential packet audit: ",JSON.stringify(report))
	return 0 if known<=201326592 and surface_count==3 else 1

static func valid_contract(packet: Dictionary, textures: Dictionary, coverage: Dictionary, identity: String) -> bool:
	if textures.get("packet_sha256","")!=identity or coverage.get("packet_sha256","")!=identity:return false
	if not textures.get("png_level0_exact",false) or not textures.get("sparse_tile_order_verified",false):return false
	if not coverage.get("source_envelope_complete",false) or not coverage.get("cell_partition_gap_free",false):return false
	if int(coverage.get("missing_pages",-1))!=0 or int(coverage.get("missing_planes",-1))!=0:return false
	if packet.get("scale_interval",[])!=textures.get("scale_interval",[]) or packet.get("scale_interval",[])!=coverage.get("scale_interval",[]):return false
	if packet.get("rows",[]).size()!=4 or packet.get("texture_bindings",[]).size()!=2:return false
	var planes: Array=packet.get("texture_planes",[])
	if int(packet.get("native_capacity_faces",0))<=0 or int(packet.native_capacity_faces)+planes.size()*2>240000:return false
	if planes.is_empty() or planes.size()!=textures.get("planes",[]).size() or planes.size()!=int(coverage.get("required_planes",-1)):return false
	if float(textures.get("worst_base_texel_screen_pixels",INF))>1.25:return false
	for i in planes.size():
		var candidate: Dictionary=textures.planes[i]
		for key in ["key","height","geometry_bounds","texture_bounds","texture_sha256"]:
			if not candidate.has(key) or candidate[key]!=planes[i].get(key):return false
		if int(candidate.get("atlas",-1))<0 or int(candidate.atlas)>=packet.texture_bindings.size():return false
		if int(candidate.get("tile",-1))<0:return false
	return true
