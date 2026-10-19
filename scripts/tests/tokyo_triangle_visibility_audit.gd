extends RefCounted
## 离线裁决屏外过绘；逐三角包络可见不等于最终像素可见，不用于实时绘制。
const Overlay := preload("res://scripts/rendering/tokyo_cells_overlay.gd")

static func count(native: RefCounted, pieces: Array, view: Rect2, canvas: Transform2D, size: Vector2, roof: Vector2, export_directory: String="") -> Dictionary:
	var result := {"source_faces":[0,0,0],"triangle_box_visible":[0,0,0],"source_meshes":[0,0,0]}
	if not export_directory.is_empty():
		if not export_directory.is_absolute_path() or DirAccess.dir_exists_absolute(export_directory): return {}
		if DirAccess.make_dir_recursive_absolute(export_directory)!=OK: return {}
		result["exports"]=[]
	for piece: Dictionary in pieces:
		var kind := int(piece.kind)
		if kind==0 and export_directory.is_empty(): continue
		var path: String=piece.components.keys()[0]
		var slot := 0
		if kind==2:
			var mapping: Array=native.pages[piece.source].mapping[2]
			path=mapping[0];slot=int(mapping[1])
		var binding: Dictionary=piece.components[path]
		if FileAccess.get_sha256(path)!=binding.sha256: return {}
		var resource: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if resource==null or not resource.valid() or resource.stream_identity()!=binding.canonical_identity: return {}
		var mesh: ArrayMesh=resource.meshes[slot]
		if mesh.get_surface_count()!=1: return {}
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var corners := indices.size() if not indices.is_empty() else vertices.size()
		if corners%3!=0 or corners/3!=int(piece.faces): return {}
		if not export_directory.is_empty():
			var raw: PackedByteArray=preload("res://scripts/tests/tokyo_residential_preview.gd").export_payload(mesh).attributes
			if raw.size()!=corners*40: return {}
			var target := export_directory.path_join("%04d_layer%d.bin"%[result.exports.size(),kind])
			var file := FileAccess.open(target,FileAccess.WRITE)
			if file==null: return {}
			file.store_buffer(raw);file.close()
			result.exports.append({"path":target,"sha256":FileAccess.get_sha256(target),"kind":kind,"faces":corners/3,"source":binding,"slot":slot})
		result.source_faces[kind]+=corners/3;result.source_meshes[kind]+=1
		for offset in range(0,corners,3):
			var box := AABB(vertices[indices[offset] if not indices.is_empty() else offset],Vector3.ZERO)
			for n in range(1,3): box=box.expand(vertices[indices[offset+n] if not indices.is_empty() else offset+n])
			if Overlay.intersects_view(Overlay.projected_layer_bounds(box,roof,Vector2.ZERO),view,canvas,size):
				result.triangle_box_visible[kind]+=1
	return result
