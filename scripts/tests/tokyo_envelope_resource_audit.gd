extends RefCounted
## 实物回读费用门；不是视觉或性能验收。
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")

static func run(_parent: Node, input: Dictionary) -> int:
	for binding: Dictionary in [input.envelope_resource_audit,input.textures]:
		if FileAccess.get_sha256(binding.path)!=binding.sha256:return 1
	var packet: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.envelope_resource_audit.path))
	var textures: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.textures.path))
	if packet.selection_sha256!=textures.selection_sha256:return 1
	if DirAccess.dir_exists_absolute(input.output):return 1
	if DirAccess.make_dir_recursive_absolute(input.output)!=OK:return 1
	if FileAccess.get_sha256(packet.vertices)!=packet.vertices_sha256:return 1
	var data := FileAccess.get_file_as_bytes(packet.vertices).to_float32_array()
	if data.size()!=int(packet.vertex_count)*10:return 1
	var vertices := PackedVector3Array();var normals := PackedVector3Array();var colors := PackedColorArray()
	for i in range(0,data.size(),10):
		vertices.append(Vector3(data[i],data[i+1],data[i+2]))
		normals.append(Vector3(data[i+3],data[i+4],data[i+5]))
		colors.append(Color(data[i+6],data[i+7],data[i+8],data[i+9]))
	var row: Dictionary=packet.rows[0]
	if FileAccess.get_sha256(row.indices)!=row.sha256:return 1
	var indices := FileAccess.get_file_as_bytes(row.indices).to_int32_array()
	if indices.size()!=int(packet.native_capacity_faces)*3:return 1
	for index: int in indices:
		if index<0 or index>=vertices.size():return 1
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var path: String=input.output.path_join("native.res")
	if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK:return 1
	var restored: ArrayMesh=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if restored==null or Packed.corner_digest(restored)!=Packed.corner_digest(mesh):return 1
	if Packed.decoded_bytes(restored)!=Packed.decoded_bytes(mesh):return 1
	var texture_bytes := 0
	for tile: Dictionary in textures.rows:
		if FileAccess.get_sha256(tile.path)!=tile.sha256:return 1
		var image := Image.load_from_file(tile.path)
		if image==null or image.generate_mipmaps()!=OK:return 1
		var charge := image.get_data_size()*3
		if charge!=int(tile.three_copy_bytes):return 1
		texture_bytes+=charge
	var report := {"native_decoded_bytes":Packed.decoded_bytes(restored),"native_saved_bytes":FileAccess.get_file_as_bytes(path).size(),
		"native_corner_digest":Packed.corner_digest(restored),"texture_three_copy_bytes":texture_bytes,
		"texture_planes":textures.rows.size(),"fixed_native_faces":indices.size()/3,"mesh_roundtrip_verified":true,
		"texture_mip_cost_verified":true,"visual_verified":false,"performance_verified":false,"runtime_integrated":false,
		"limitations":"Excludes plane meshes, driver allocations, handoff union and full-map residency."}
	if input.has("atlas"):
		var batch := preload("res://scripts/tests/tokyo_independent_mip_batch.gd").build(input.atlas,textures)
		if batch.is_empty():return 1
		report["atlas_texture_three_copy_bytes"]=batch.texture_three_copy_bytes
		report["atlas_plane_decoded_bytes"]=Packed.decoded_bytes(batch.mesh)
		report["known_single_index_bytes"]=Packed.decoded_bytes(restored)+batch.texture_three_copy_bytes+Packed.decoded_bytes(batch.mesh)
		report["known_with_all_pose_cpu_indices_bytes"]=int(report.known_single_index_bytes)+int(packet.index_bytes_per_pose)*packet.rows.size()
		report["budget_bytes"]=201326592
		report["joint_budget_verified"]=false
		report["limitations"]="Atlas fields include plane geometry and identity-deduplicated texture arrays. Excludes allocator/driver overhead, expanded pose texture coverage and full-map residency; all-pose CPU indices is one explicit retention strategy, not a universal lower bound."
	var file := FileAccess.open(input.output.path_join("report.json"),FileAccess.WRITE)
	if file==null:return 1
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("Tokyo envelope resource audit: ",JSON.stringify(report))
	return 0
