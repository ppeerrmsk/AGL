extends RefCounted
## 离线局部样件；按三角形重心分桶，包围盒按真实顶点计算，不授予运行时覆盖。
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Builder := preload("res://scripts/tests/build_tokyo_shared_lod.gd")

static func run(input: Dictionary) -> int:
	var binding: Dictionary=input.shared_lod_cells
	if FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	var mesh: ArrayMesh=ResourceLoader.load(binding.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if mesh==null or mesh.get_surface_count()!=1: return 1
	var raw: Dictionary=mesh.get("_surfaces")[0]
	if raw.get("lods",[]).size()!=2: return 1
	var levels: Array=[]
	for level in 2:
		var surface := raw.duplicate();surface.erase("lods")
		if level==1:
			surface.index_data=raw.lods[1]
			var stride := RenderingServer.mesh_surface_get_format_index_stride(surface.format,surface.vertex_count)
			surface.index_count=surface.index_data.size()/stride
		var single := ArrayMesh.new();single.set("_surfaces",[surface])
		levels.append(Packed._read(single))
	var size := float(input.get("cell_size",512.0))
	if size<=0: return 1
	if input.has("all_cells") and not input.all_cells is bool: return 1
	var complete: bool=input.get("all_cells",false)
	var focus := Vector2i(floori(float(input.cell_point[0])/size),floori(float(input.cell_point[1])/size))
	var cells: Dictionary={}
	var selected := [0,0]
	var selected_vertices: Dictionary={}
	for level in 2:
		var data: Dictionary=levels[level]
		for triangle in range(0,data.indices.size(),3):
			var center := Vector3.ZERO
			for corner in 3: center+=position(data,data.indices[triangle+corner])
			center/=3.0
			var cell := Vector2i(floori(center.x/size),floori(center.z/size))
			if not complete and (absi(cell.x-focus.x)>1 or absi(cell.y-focus.y)>1): continue
			if not cells.has(cell): cells[cell]=[PackedInt32Array(),PackedInt32Array()]
			for corner in 3:
				var vertex_index: int=data.indices[triangle+corner]
				cells[cell][level].append(vertex_index)
				selected_vertices[vertex_index]=true
			selected[level]+=1
	if cells.is_empty(): return 1
	if complete and (selected[0]*3!=levels[0].indices.size() or selected[1]*3!=levels[1].indices.size()): return 1
	var rows: Array=[]
	var split_vertices := 0
	var split_bytes := 0
	for cell: Vector2i in cells:
		var row := save_cell(levels,cells[cell],input.output+".%s_%s.res"%[cell.x,cell.y])
		if row.is_empty(): return 1
		row.cell=[cell.x,cell.y];rows.append(row)
		split_vertices+=int(row.shared_vertices);split_bytes+=int(row.bytes)
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"source":binding,"cell_size":size,"selected_faces":selected,"cells":rows,
		"unique_selected_source_vertices":selected_vertices.size(),"split_vertices":split_vertices,
		"boundary_duplicate_vertices":split_vertices-selected_vertices.size(),"split_bytes":split_bytes,
		"local_sample_only":not complete,"complete_source_root":complete,"runtime_integrated":false,"triangle_assignment":"centroid; actual vertex AABB"},"\t"))
	file.close();return 0

static func position(data: Dictionary, index: int) -> Vector3:
	return Vector3(data.raw.decode_float(index*12),data.raw.decode_float(index*12+4),data.raw.decode_float(index*12+8))

static func save_cell(levels: Array, selected: Array, path: String) -> Dictionary:
	# 缺失任一档先拒绝，而非让引擎误用另一档。
	if selected[0].is_empty() or selected[1].is_empty() or FileAccess.file_exists(path): return {}
	var unique: Dictionary={};var bytes := [PackedByteArray(),PackedByteArray(),PackedByteArray()]
	var indices := [PackedInt32Array(),PackedInt32Array()]
	var hashes: Array=[];var separate_vertices := 0
	var box := AABB();var initialized := false
	for level in 2:
		var data: Dictionary=levels[level];var local: Dictionary={}
		var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256)
		for old: int in selected[level]:
			var corner: PackedByteArray=Packed._corner(data,old)
			hash.update(corner)
			var key := corner.hex_encode();local[key]=true
			if not unique.has(key):
				unique[key]=unique.size()
				bytes[0].append_array(corner.slice(0,data.ps))
				bytes[1].append_array(corner.slice(data.ps,data.ps+data.ns))
				bytes[2].append_array(corner.slice(data.ps+data.ns))
				var vertex := position(data,old)
				box=box.expand(vertex) if initialized else AABB(vertex,Vector3.ZERO);initialized=true
			indices[level].append(unique[key])
		separate_vertices+=local.size();hashes.append(hash.finish().hex_encode())
	var surface: Dictionary=levels[0].surface.duplicate()
	surface.vertex_count=unique.size();surface.index_count=indices[0].size()
	var stride := RenderingServer.mesh_surface_get_format_index_stride(surface.format,surface.vertex_count)
	bytes[0].append_array(bytes[1]);surface.vertex_data=bytes[0];surface.attribute_data=bytes[2]
	surface.index_data=Builder.pack_indices(indices[0],stride);surface.lods=[1.0,Builder.pack_indices(indices[1],stride)]
	surface.aabb=box
	var mesh := ArrayMesh.new();mesh.set("_surfaces",[surface])
	if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK: return {}
	var copy: ArrayMesh=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if copy==null or copy.get_surface_count()!=1: return {}
	var actual: Dictionary=copy.get("_surfaces")[0]
	if actual.get("lods",[]).size()!=2 or actual.lods[1]!=surface.lods[1]: return {}
	for level in 2:
		var check := actual.duplicate();check.erase("lods")
		check.index_data=actual.index_data if level==0 else actual.lods[1];check.index_count=indices[level].size()
		var single := ArrayMesh.new();single.set("_surfaces",[check])
		if Packed.corner_digest(single)!=hashes[level]: return {}
	return {"path":path,"sha256":FileAccess.get_sha256(path),"near_faces":indices[0].size()/3,"middle_faces":indices[1].size()/3,
		"shared_vertices":unique.size(),"separate_vertices":separate_vertices,"bytes":Packed.decoded_bytes(copy)+indices[1].size()*4,
		"exact":true,"aabb":[box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z]}
