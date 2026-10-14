extends RefCounted
## 离线有向三角差集，支持16/32位索引；保留原生角点属性，绝不重算法线或位置。
const Read := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Signature := preload("res://scripts/tests/tokyo_mesh_signature.gd")


static func supported(mesh: ArrayMesh) -> bool:
	if mesh.get_surface_count()==0:
		return true
	if mesh.get_surface_count()!=1 or mesh.get_blend_shape_count()!=0:
		return false
	var source: Dictionary = mesh.get("_surfaces")[0]
	return int(source.primitive)==Mesh.PRIMITIVE_TRIANGLES and (int(source.format)&Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)==0 \
		and source.get("skin_data",PackedByteArray()).is_empty() and source.get("lods",[]).is_empty()


static func subtract(original: ArrayMesh, removed: ArrayMesh) -> Dictionary:
	if not supported(original) or not supported(removed):
		return {}
	if removed.get_surface_count()==0:
		return {"mesh":original,"removed":0}
	if original.get_surface_count()==0:
		return {}
	var data := Read._read(original)
	var other: Dictionary = removed.get("_surfaces")[0]
	if (int(data.surface.format)&~Mesh.ARRAY_FORMAT_INDEX)!=(int(other.format)&~Mesh.ARRAY_FORMAT_INDEX) or data.surface.get("material")!=other.get("material"):
		return {}
	var pending := Join.signatures(removed)
	var kept := PackedInt32Array()
	var count := 0
	for first in range(0,data.indices.size(),3):
		var key := PackedByteArray()
		for offset in 3:
			key.append_array(Read._corner(data,data.indices[first+offset]))
		if int(pending.get(key,0))>0:
			pending[key]-=1
			count+=1
		else:
			for offset in 3:
				kept.append(data.indices[first+offset])
	for value: int in pending.values():
		if value!=0:
			return {}
	if kept.is_empty():
		return {"mesh":ArrayMesh.new(),"removed":count}
	var remap: Dictionary = {}
	var positions := PackedByteArray()
	var normals := PackedByteArray()
	var attributes := PackedByteArray()
	var indices := PackedInt32Array()
	for index: int in kept:
		if not remap.has(index):
			remap[index]=remap.size()
			var key := Read._corner(data,index)
			positions.append_array(key.slice(0,data.ps))
			normals.append_array(key.slice(data.ps,data.ps+data.ns))
			attributes.append_array(key.slice(data.ps+data.ns))
		indices.append(int(remap[index]))
	var changed: Dictionary = data.surface.duplicate()
	changed.vertex_count=remap.size()
	var packed := PackedByteArray()
	if int(data.surface.get("index_count",0))>0:
		changed.index_count=indices.size()
		var stride := RenderingServer.mesh_surface_get_format_index_stride(changed.format,changed.vertex_count)
		packed.resize(indices.size()*stride)
		for index in indices.size():
			if stride==2:
				packed.encode_u16(index*2,indices[index])
			else:
				packed.encode_u32(index*4,indices[index])
	else:
		# 非索引来源先保留紧凑顺序流；repack只在真省内存时才增加索引。
		changed.index_count=0
	positions.append_array(normals)
	changed.vertex_data=positions
	changed.attribute_data=attributes
	changed.index_data=packed
	var result := ArrayMesh.new()
	result.set("_surfaces",[changed])
	result.custom_aabb=original.custom_aabb
	return {"mesh":Read.repack(result),"removed":count}


static func conserved(original: ArrayMesh, current: ArrayMesh, removed: ArrayMesh) -> bool:
	# 独立使用解码后的float角点，不复用裁取所用的原生打包key。
	var expected := Signature.of_mesh(original)
	for mesh: ArrayMesh in [current,removed]:
		var actual := Signature.of_mesh(mesh)
		for key: PackedByteArray in actual:
			var remaining := int(expected.get(key,0))-int(actual[key])
			if remaining<0:
				return false
			if remaining==0:
				expected.erase(key)
			else:
				expected[key]=remaining
	return expected.is_empty()
