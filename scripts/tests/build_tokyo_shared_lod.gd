extends RefCounted
## 离线双档样件：完整原始角属性共享，禁止自动接入正式流送。
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")

static func run(native: RefCounted, input: Dictionary) -> int:
	var kind := int(input.get("shared_lod_kind",1))
	if kind not in [0,1]: return 1
	var middle: String=input.get("shared_lod_middle","lod4_full")
	if middle not in ["lod4_full","lod4_mid"] or not native.catalog.configurations.has(middle): return 1
	var point := Vector2(input.shared_lod_point[0],input.shared_lod_point[1])
	var roots: Array=native.catalog.configurations.lod5_full
	var index := -1
	var distance := INF
	for n in roots.size():
		var box: AABB=roots[n].boxes[kind]
		if int(roots[n].triangles[kind])==0: continue
		var rectangle := Rect2(box.position.x,box.position.z,box.size.x,box.size.z)
		var closest := point.clamp(rectangle.position,rectangle.end)
		var candidate := point.distance_squared_to(closest)
		if candidate<distance: index=n;distance=candidate
	if index<0 or native.catalog.configurations[middle].size()!=roots.size(): return 1
	var meshes: Array[ArrayMesh]=[]
	var sources: Array=[]
	for configuration: String in ["lod5_full",middle]:
		var entry: Dictionary=native.catalog.configurations[configuration][index]
		var page: Dictionary=native.pages[entry.path]
		var path: String=page.mapping[kind][0]
		var slot := int(page.mapping[kind][1])
		var binding: Dictionary=page.components[path]
		if FileAccess.get_sha256(path)!=binding.sha256: return 1
		var resource: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if resource==null or not resource.valid() or resource.stream_identity()!=binding.canonical_identity: return 1
		var mesh: ArrayMesh=resource.meshes[slot]
		if mesh.get_surface_count()!=1 or mesh.surface_get_material(0)!=null or mesh.shadow_mesh!=null: return 1
		meshes.append(mesh);sources.append({"configuration":configuration,"page":entry.path,"binding":binding,"slot":slot,"digest":Packed.corner_digest(mesh)})
	var data: Array=[Packed._read(meshes[0]),Packed._read(meshes[1])]
	if data[0].ps!=data[1].ps or data[0].ns!=data[1].ns or data[0].cs!=data[1].cs: return 1
	if (int(data[0].surface.format)|Mesh.ARRAY_FORMAT_INDEX)!=(int(data[1].surface.format)|Mesh.ARRAY_FORMAT_INDEX): return 1
	var unique: Dictionary={}
	var positions := PackedByteArray();var normals := PackedByteArray();var attributes := PackedByteArray()
	var indices: Array=[]
	for source: Dictionary in data:
		var remap := PackedInt32Array();remap.resize(source.count);remap.fill(-1)
		var target := PackedInt32Array()
		for old: int in source.indices:
			if remap[old]<0:
				var corner: PackedByteArray=Packed._corner(source,old)
				var key := corner.hex_encode()
				if not unique.has(key):
					unique[key]=unique.size()
					positions.append_array(corner.slice(0,source.ps))
					normals.append_array(corner.slice(source.ps,source.ps+source.ns))
					attributes.append_array(corner.slice(source.ps+source.ns))
				remap[old]=int(unique[key])
			target.append(remap[old])
		indices.append(target)
	var surface: Dictionary=data[0].surface.duplicate()
	surface.format=int(surface.format)|Mesh.ARRAY_FORMAT_INDEX
	surface.vertex_count=unique.size();surface.index_count=indices[0].size()
	var stride := RenderingServer.mesh_surface_get_format_index_stride(surface.format,surface.vertex_count)
	if stride not in [2,4]: return 1
	positions.append_array(normals)
	surface.vertex_data=positions;surface.attribute_data=attributes
	surface.index_data=pack_indices(indices[0],stride)
	surface.lods=[1.0,pack_indices(indices[1],stride)]
	surface.aabb=meshes[0].get_aabb().merge(meshes[1].get_aabb())
	var result := ArrayMesh.new();result.set("_surfaces",[surface])
	var target_path: String=input.output+".res"
	if FileAccess.file_exists(target_path) or ResourceSaver.save(result,target_path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
	var copy: ArrayMesh=ResourceLoader.load(target_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if copy==null or copy.get_surface_count()!=1: return 1
	var actual: Dictionary=copy.get("_surfaces")[0]
	if actual.get("lods",[]).size()!=2 or actual.lods[1]!=surface.lods[1]: return 1
	for level in 2:
		var check: Dictionary=actual.duplicate();check.erase("lods")
		check.index_data=surface.index_data if level==0 else actual.lods[1]
		check.index_count=indices[level].size()
		var decoded := ArrayMesh.new();decoded.set("_surfaces",[check])
		if Packed.corner_digest(decoded)!=sources[level].digest: return 1
	var original_bytes := Packed.decoded_bytes(meshes[0])+Packed.decoded_bytes(meshes[1])
	# 沿用完整解码账本口径，并额外收费次档32位索引，不拿磁盘压缩当显存节省。
	var shared_bytes: int = Packed.decoded_bytes(copy)+indices[1].size()*4
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"sources":sources,"root_index":index,"kind":kind,"artifact":target_path,"sha256":FileAccess.get_sha256(target_path),
		"original_bytes":original_bytes,"shared_bytes":shared_bytes,"saved_bytes":original_bytes-shared_bytes,"vertices":unique.size(),
		"near_faces":indices[0].size()/3,"middle_faces":indices[1].size()/3,"roundtrip_corner_exact":true,
		"runtime_integrated":false,"visual_lod_verified":false},"\t"));file.close()
	return 0

static func pack_indices(indices: PackedInt32Array, stride: int) -> PackedByteArray:
	var bytes := PackedByteArray();bytes.resize(indices.size()*stride)
	for n in indices.size():
		if stride==2: bytes.encode_u16(n*2,indices[n])
		else: bytes.encode_u32(n*4,indices[n])
	return bytes
