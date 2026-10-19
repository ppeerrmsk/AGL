extends RefCounted
## 有限离线资源制作：保存真实通道并回读，不授予连续显示或GPU峰值资格。

static func unpack(binding: Dictionary) -> PackedByteArray:
	if FileAccess.get_sha256(binding.path)!=binding.sha256:return PackedByteArray()
	var data := FileAccess.get_file_as_bytes(binding.path).decompress(int(binding.decoded_bytes),FileAccess.COMPRESSION_GZIP)
	return data if data.size()==int(binding.decoded_bytes) else PackedByteArray()

static func build(row: Dictionary) -> ArrayMesh:
	var source := unpack(row.vertices).to_float32_array()
	var original := unpack(row.indices).to_int32_array()
	var mask := unpack(row.mask)
	if source.is_empty() or source.size()%10!=0 or original.is_empty() or original.size()%3!=0:return null
	var units := int(row.mask_units);var capacity := int(row.capacity)
	if mask.size()*8<original.size()/3/units:return null
	var indices := PackedInt32Array();indices.resize(capacity*3);indices.fill(0)
	var offset := 0
	for face in original.size()/3:
		var bit := face/units
		if (mask[bit/8]&(1<<(bit%8)))==0:continue
		if offset+3>indices.size():return null
		for corner in 3:
			var index := original[face*3+corner]
			if index<0 or index>=source.size()/10:return null
			indices[offset]=index;offset+=1
	var positions := PackedVector3Array();var normals := PackedVector3Array();var colors := PackedColorArray()
	var uv := PackedVector2Array();var uv2 := PackedVector2Array()
	for i in range(0,source.size(),10):
		for j in 10:
			if not is_finite(source[i+j]):return null
		positions.append(Vector3(source[i],source[i+1],source[i+2]));normals.append(Vector3(source[i+3],source[i+4],source[i+5]))
		if row.kind=="native":colors.append(Color(source[i+6],source[i+7],source[i+8],source[i+9]))
		else:
			uv.append(Vector2(source[i+6],source[i+7]));uv2.append(Vector2(source[i+8],source[i+9]))
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
	if row.kind=="native":arrays[Mesh.ARRAY_COLOR]=colors
	else:arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func run(input: Dictionary) -> int:
	if FileAccess.get_sha256(input.source_report.path)!=input.source_report.sha256:return 1
	var expected_layers := 1 if input.get("single_layer_repair",false) else 3
	if int(input.total_capacity)>240000 or input.selectable_geometry_save.size()!=expected_layers:return 1
	if DirAccess.make_dir_recursive_absolute(input.output)!=OK:return 1
	var rows: Array=[];var total := 0;var largest_file := 0
	for row: Dictionary in input.selectable_geometry_save:
		var mesh := build(row)
		if mesh==null:return 1
		var path: String=input.output.path_join("mesh%d.res"%rows.size())
		if FileAccess.file_exists(path):return 1
		if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK:return 1
		var restored: ArrayMesh=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if restored==null or restored.get_surface_count()!=1:return 1
		var before: Dictionary=mesh.get("_surfaces")[0];var after: Dictionary=restored.get("_surfaces")[0]
		var channels: Dictionary={}
		for key in ["vertex_data","attribute_data","skin_data","index_data"]:
			var old: PackedByteArray=before.get(key,PackedByteArray());var saved: PackedByteArray=after.get(key,PackedByteArray())
			if old!=saved:return 1
			channels[key]=saved.size();total+=saved.size()
		if int(after.index_count)!=int(row.capacity)*3:return 1
		var file := FileAccess.open(path,FileAccess.READ);var size := file.get_length();file.close();largest_file=maxi(largest_file,size)
		rows.append({"path":path,"sha256":FileAccess.get_sha256(path),"packed_channels":channels,"vertex_count":after.vertex_count,"index_count":after.index_count,"compressed_file_bytes":size})
		mesh=null;restored=null
	var report := {"rows":rows,"packed_geometry_bytes":total,"largest_compressed_file_bytes":largest_file,"saved_packed_channels_exact":true,"three_geometry_copies_plus_input":3*total+largest_file,"texture_loaded":false,"gpu_upload_peak_measured":false,"atomic_selection_verified":false,"formal_qualified":false}
	var output := FileAccess.open(input.output.path_join("report.json"),FileAccess.WRITE)
	if output==null:return 1
	output.store_string(JSON.stringify(report,"\t"));output.close()
	print("Selectable geometry saved: ",JSON.stringify(report));return 0
