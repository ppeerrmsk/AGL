extends RefCounted
## 离线候选：只删除角点属性完全相同、同绕序且全不透明的重复三角形。
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")

static func run(native: RefCounted, input: Dictionary) -> int:
	var page: Dictionary=native.pages.get(input.ground_duplicate_candidate,{})
	if not page.has("mapping"): return 1
	var path: String=page.mapping[2][0]
	var slot := int(page.mapping[2][1])
	var binding: Dictionary=page.components[path]
	if FileAccess.get_sha256(path)!=binding.sha256: return 1
	var source: Resource=load(path)
	if source==null or not source.valid() or source.stream_identity()!=binding.canonical_identity: return 1
	var mesh: ArrayMesh=source.meshes[slot]
	var data := Packed._read(mesh)
	var arrays := mesh.surface_get_arrays(0)
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR]!=null else PackedColorArray()
	# 无颜色或含透明度时拒绝去重：重叠可能具有混合语义。
	var opaque := colors.size()==int(data.count)
	for color: Color in colors: opaque=opaque and color.a==1.0
	var seen: Dictionary={}
	var kept := PackedInt32Array()
	var duplicates := 0
	for offset in range(0,data.indices.size(),3):
		var key := PackedByteArray()
		for corner in 3: key.append_array(Packed._corner(data,data.indices[offset+corner]))
		if opaque and seen.has(key): duplicates+=1;continue
		seen[key]=true
		for corner in 3: kept.append(data.indices[offset+corner])
	var output := {"source":binding,"slot":slot,"before_faces":data.indices.size()/3,"duplicate_faces":duplicates,"opaque":opaque,"runtime_acceptance":false,"candidate_saved":false}
	if duplicates>0:
		var surface: Dictionary=data.surface.duplicate()
		surface.format=int(surface.format)|Mesh.ARRAY_FORMAT_INDEX
		surface.index_count=kept.size()
		var stride := RenderingServer.mesh_surface_get_format_index_stride(surface.format,data.count)
		var indices := PackedByteArray();indices.resize(kept.size()*stride)
		for n in kept.size():
			if stride==2: indices.encode_u16(n*2,kept[n])
			elif stride==4: indices.encode_u32(n*4,kept[n])
			else: return 1
		surface.index_data=indices
		var candidate := ArrayMesh.new();candidate.set("_surfaces",[surface]);candidate.custom_aabb=mesh.custom_aabb
		var part := Component.new()
		part.source_hash=var_to_bytes([binding.sha256,slot,"opaque_exact_triangle_dedup"]).hex_encode().sha256_text()
		part.geometry_bytes=Packed.decoded_bytes(candidate);part.mesh_bytes=PackedInt32Array([part.geometry_bytes]);part.meshes=[candidate]
		var destination: String=input.output+".res"
		if FileAccess.file_exists(destination) or not part.valid() or ResourceSaver.save(part,destination,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
		var copy: Resource=ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
		if copy==null or not copy.valid() or Packed.corner_digest(copy.meshes[0])!=Packed.corner_digest(candidate): return 1
		output.merge({"candidate_saved":true,"path":destination,"sha256":FileAccess.get_sha256(destination),"after_faces":kept.size()/3,"bytes":part.geometry_bytes},true)
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(output,"\t"));file.close()
	return 0
