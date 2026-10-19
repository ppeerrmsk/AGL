extends RefCounted
## 离线索引复用；逐角顺序及原生打包属性不变，不用于运行时逐帧处理。


static func repack(mesh: ArrayMesh) -> ArrayMesh:
	if mesh.get_surface_count()==0:
		return mesh
	var data := _read(mesh)
	var source: Dictionary = data.surface
	var remap := PackedInt32Array()
	remap.resize(data.count)
	remap.fill(-1)
	var unique: Dictionary = {}
	var positions := PackedByteArray()
	var normals := PackedByteArray()
	var attributes := PackedByteArray()
	var indices := PackedInt32Array()
	for old: int in data.indices:
		if remap[old]<0:
			var key := _corner(data,old)
			if not unique.has(key):
				unique[key]=unique.size()
				positions.append_array(key.slice(0,data.ps))
				normals.append_array(key.slice(data.ps,data.ps+data.ns))
				attributes.append_array(key.slice(data.ps+data.ns))
			remap[old]=int(unique[key])
		indices.append(remap[old])
	var result := source.duplicate()
	result.vertex_count=unique.size()
	result.format=int(source.format)|Mesh.ARRAY_FORMAT_INDEX
	result.index_count=indices.size()
	var stride := RenderingServer.mesh_surface_get_format_index_stride(result.format,result.vertex_count)
	var packed := PackedByteArray()
	packed.resize(indices.size()*stride)
	for n in indices.size():
		if stride==2:
			packed.encode_u16(n*2,indices[n])
		else:
			assert(stride==4)
			packed.encode_u32(n*4,indices[n])
	positions.append_array(normals)
	result.vertex_data=positions
	result.attribute_data=attributes
	result.index_data=packed
	var output := ArrayMesh.new()
	output.set("_surfaces",[result])
	output.custom_aabb=mesh.custom_aabb
	return output if decoded_bytes(output)<decoded_bytes(mesh) else mesh


static func _read(mesh: ArrayMesh) -> Dictionary:
	assert(mesh.get_surface_count()==1 and mesh.get_blend_shape_count()==0)
	var surface: Dictionary = mesh.get("_surfaces")[0]
	var format := int(surface.format)
	assert((format&Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)==0 and surface.get("lods",[]).is_empty() and surface.get("skin_data",PackedByteArray()).is_empty())
	assert(int(surface.primitive)==Mesh.PRIMITIVE_TRIANGLES)
	var count := int(surface.vertex_count)
	var ps := RenderingServer.mesh_surface_get_format_vertex_stride(format,count)
	var ns := RenderingServer.mesh_surface_get_format_normal_tangent_stride(format,count)
	var cs := RenderingServer.mesh_surface_get_format_attribute_stride(format,count)
	var raw: PackedByteArray = surface.vertex_data
	var attributes: PackedByteArray = surface.get("attribute_data",PackedByteArray())
	assert(ps==12 and raw.size()==count*(ps+ns) and attributes.size()==count*cs)
	var arrays := mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(count)
		for n in count:
			indices[n]=n
	assert(indices.size()%3==0)
	for n: int in indices:
		assert(n>=0 and n<count)
	return {"surface":surface,"count":count,"ps":ps,"ns":ns,"cs":cs,"raw":raw,"attributes":attributes,"indices":indices}


static func _corner(data: Dictionary, index: int) -> PackedByteArray:
	var key: PackedByteArray = data.raw.slice(index*data.ps,(index+1)*data.ps)
	key.append_array(data.raw.slice(data.count*data.ps+index*data.ns,data.count*data.ps+(index+1)*data.ns))
	key.append_array(data.attributes.slice(index*data.cs,(index+1)*data.cs))
	return key


static func corner_digest(mesh: ArrayMesh) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	if mesh.get_surface_count()>0:
		var data := _read(mesh)
		var buffer := PackedByteArray()
		for index: int in data.indices:
			buffer.append_array(_corner(data,index))
			if buffer.size()>=65536:
				hash.update(buffer)
				buffer.clear()
		if not buffer.is_empty():
			hash.update(buffer)
	return hash.finish().hex_encode()


static func decoded_bytes(mesh: ArrayMesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		for channel: Variant in mesh.surface_get_arrays(surface):
			if channel!=null:
				count+=channel.to_byte_array().size()
	return count
