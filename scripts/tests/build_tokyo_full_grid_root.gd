extends RefCounted
## 离线接合一个完整8km根的一档；原自适应单元及packed属性不变。
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Index := preload("res://scripts/rendering/tokyo_cell_index.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Same := preload("res://scripts/tests/build_tokyo_shared_pages.gd")
const Contract := preload("res://scripts/rendering/tokyo_full_grid_contract.gd")


static func selection(name: String) -> Dictionary:
	if name=="fixed":
		return {"slot":-1,"guarded":false,"kinds":1}
	for level in 4:
		for guarded in [false,true]:
			if name=="lod%d_%s" % [level,"guarded" if guarded else "full"]:
				return {"slot":level,"guarded":guarded,"kinds":2}
	if name in ["lod4_full","lod4_mid","lod5_full"]:
		return {"slot":6 if name=="lod4_mid" else (4 if name=="lod4_full" else 5),"guarded":false,"kinds":2}
	return {}


static func binding_valid(value: Variant) -> bool:
	return value is Dictionary and value.get("path") is String and value.path.is_absolute_path() \
		and Contract.digest(value.get("sha256")) and FileAccess.get_sha256(value.path)==value.sha256


static func joined_exact(inputs: Array[ArrayMesh], result: ArrayMesh) -> bool:
	# 独立线性核对packed各通道与重基索引，不解码/重新量化法线颜色。
	var populated := inputs.filter(func(mesh: ArrayMesh) -> bool: return mesh.get_surface_count()>0)
	if populated.is_empty():
		return result.get_surface_count()==0
	if result.get_surface_count()!=1:
		return false
	var dst: Dictionary = result.get("_surfaces")[0]
	if (int(dst.format)&Mesh.ARRAY_FORMAT_INDEX)==0:
		return false
	var total := int(dst.vertex_count)
	var positions: PackedByteArray = dst.vertex_data
	var attrs: PackedByteArray = dst.get("attribute_data",PackedByteArray())
	var indices: PackedInt32Array = result.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var vertex_offset := 0
	var face_offset := 0
	var bounds: AABB = populated[0].get_aabb()
	for mesh: ArrayMesh in populated:
		if mesh.get_surface_count()!=1:
			return false
		var src: Dictionary = mesh.get("_surfaces")[0]
		var count := int(src.vertex_count)
		var ns := RenderingServer.mesh_surface_get_format_normal_tangent_stride(src.format,count)
		var cs := RenderingServer.mesh_surface_get_format_attribute_stride(src.format,count)
		var raw: PackedByteArray = src.vertex_data
		if (int(src.format)&~Mesh.ARRAY_FORMAT_INDEX)!=(int(dst.format)&~Mesh.ARRAY_FORMAT_INDEX) \
				or src.get("material")!=dst.get("material") or vertex_offset+count>total \
				or positions.slice(vertex_offset*12,(vertex_offset+count)*12)!=raw.slice(0,count*12) \
				or positions.slice(total*12+vertex_offset*ns,total*12+(vertex_offset+count)*ns)!=raw.slice(count*12) \
				or attrs.slice(vertex_offset*cs,(vertex_offset+count)*cs)!=src.get("attribute_data",PackedByteArray()):
			return false
		var arrays := mesh.surface_get_arrays(0)
		var old: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var size := count if old.is_empty() else old.size()
		if face_offset+size>indices.size():
			return false
		for n in size:
			if indices[face_offset+n]!=vertex_offset+(n if old.is_empty() else old[n]):
				return false
		face_offset+=size
		vertex_offset+=count
		bounds=bounds.merge(mesh.get_aabb())
	return vertex_offset==total and face_offset==indices.size() and result.get_aabb()==bounds


static func run(input_path: String, expected_sha: String, output: String, configuration: String) -> int:
	var choice := selection(configuration)
	var base := input_path.get_base_dir().replace("\\","/").simplify_path()
	output=output.replace("\\","/").simplify_path()
	if choice.is_empty() or not binding_valid({"path":input_path,"sha256":expected_sha}) \
			or not base.ends_with("/tmp/tokyo-bay-volume") or output.get_base_dir()!=base or DirAccess.dir_exists_absolute(output):
		return 1
	var inputs: Variant = JSON.parse_string(FileAccess.get_file_as_string(input_path))
	if not inputs is Dictionary or inputs.get("schema")!=1 or inputs.get("tiles_complete")!=16 \
			or inputs.get("parent_id",-1)<0 or inputs.parent_id>=16 or inputs.get("tiles",[]).size()!=16 \
			or not inputs.get("partial",false) or inputs.get("installed",true) or inputs.get("canonical_ready",true):
		return 1
	for key: String in ["source_grid","full_spool","regional_registry","routes","exact_layout","hierarchy"]:
		if not binding_valid(inputs.get(key)):
			return 1
	if inputs.exact_layout.sha256!=Contract.LAYOUT_SHA or inputs.hierarchy.sha256!=Contract.HIERARCHY_SHA \
			or inputs.regional_registry.sha256!=Contract.REGIONAL_SHA or inputs.source_grid.sha256!=Contract.GRID_SHA:
		return 1
	var file := FileAccess.open(inputs.exact_layout.path,FileAccess.READ)
	if file==null:
		return 1
	var layout: Variant = file.get_var(false)
	file.close()
	if not layout is Dictionary or layout.get("tiles",[]).size()!=256:
		return 1
	var original_layout: Dictionary = {}
	for row: Dictionary in layout.tiles:
		original_layout[row.tile]=row
	var parent := int(inputs.parent_id)
	var bounds := Rect2(-16300+(parent%4)*8000,-15700+(parent/4)*8000,8000,8000)
	if inputs.bounds!=[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]:
		return 1
	var low: Array[ArrayMesh] = []
	var high: Array[ArrayMesh] = []
	var sources: Array = []
	var seen: Dictionary = {}
	var face_totals := PackedInt64Array([0,0])
	var vertex_totals := PackedInt64Array([0,0])
	for tile: Dictionary in inputs.tiles:
		var name := str(tile.get("tile",""))
		var members := name.split("_")
		if members.size()!=3 or members[0]!="detail" or not members[1].is_valid_int() or not members[2].is_valid_int():
			return 1
		var x := int(members[1])
		var y := int(members[2])
		if name!="detail_%02d_%02d" % [x,y] or x<0 or y<0 or x>=16 or y>=16 or (y/4)*4+x/4!=parent \
				or seen.has(name) or not original_layout.has(name) or not binding_valid(tile.get("index")) or not binding_valid(tile.get("source_index")):
			return 1
		seen[name]=true
		var index: Resource = ResourceLoader.load(tile.index.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var original: Resource = ResourceLoader.load(tile.source_index.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not index is Index or not original is Index or not index.valid(inputs.regional_registry.sha256) or not original.valid() \
				or index.regional_id!=name or index.bounds!=original.bounds or index.surface_only!=tile.surface_only:
			return 1
		var proof_binding: Variant = tile.get("owner_manifest") if tile.surface_only else tile.get("transfer_manifest")
		if not binding_valid(proof_binding):
			return 1
		var proof: Variant = JSON.parse_string(FileAccess.get_file_as_string(proof_binding.path))
		if not proof is Dictionary or proof.get("registry_sha256")!=inputs.regional_registry.sha256:
			return 1
		var archive_hashes: Dictionary = {}
		for region: Dictionary in proof.get("regions",[]):
			if region.region!=name:
				continue
			for row: Dictionary in region.rows:
				archive_hashes[str(row.path)]=str(row.sha256)
		if archive_hashes.size()!=112:
			return 1
		for cell: Dictionary in index.cells:
			var id := int(cell.id)
			var exact: Array = original_layout[name].cells[id].bounds
			if cell.bounds!=Rect2(exact[0],exact[1],exact[2],exact[3]) or cell.bounds!=original.cells[id].bounds \
					or cell.fixed!=original.cells[id].fixed:
				return 1
			var path: String = cell.fixed if choice.slot<0 else (cell.mid.path if choice.slot==6 else cell.levels[choice.slot].path)
			var digest := FileAccess.get_sha256(path)
			if choice.slot>=0 and digest!=archive_hashes.get(path,""):
				return 1
			var page: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var expected_level: int = 4 if choice.slot==6 else choice.slot
			if page==null or not page.valid() or page.cell_id!=id or page.level!=expected_level:
				return 1
			var ranges: Array = []
			for kind in int(choice.kinds):
				var guarded: bool = choice.guarded and kind==0 and page.precision_original!=null
				var mesh: ArrayMesh = page.precision_original if guarded else page.meshes[kind]
				var faces := Indexed.triangles(mesh)
				var vertices := mesh.surface_get_array_len(0) if mesh.get_surface_count()>0 else 0
				ranges.append({"kind":kind,"precision_guarded":guarded,"first_triangle":face_totals[kind],"triangles":faces,
					"first_vertex":vertex_totals[kind],"vertices":vertices})
				face_totals[kind]+=faces
				vertex_totals[kind]+=vertices
				if kind==0:
					low.append(mesh)
				else:
					high.append(mesh)
			# 原tile/cell范围保留，后续分页无需从合包三角中心猜测来源。
			sources.append({"tile":name,"cell":id,"path":path,"sha256":digest,"ranges":ranges})
		print("[Full root join] parent=",parent," config=",configuration," input=",name," cells=",sources.size())
	if sources.size()!=256 or seen.size()!=16:
		return 1
	var component := Component.new()
	component.source_hash=(expected_sha+":"+configuration).sha256_text()
	component.meshes.append(Join.join(low))
	if not joined_exact(low,component.meshes[0]):
		return 1
	low.clear()
	if choice.kinds==2:
		component.meshes.append(Join.join(high))
		if not joined_exact(high,component.meshes[1]):
			return 1
		high.clear()
	for kind in component.meshes.size():
		if Indexed.triangles(component.meshes[kind])!=face_totals[kind]:
			return 1
		component.mesh_bytes.append(Builder.mesh_bytes(component.meshes[kind]))
		component.geometry_bytes+=component.mesh_bytes[-1]
	if not component.valid() or DirAccess.make_dir_recursive_absolute(output)!=OK:
		return 1
	var target := output.path_join("component.res")
	if ResourceSaver.save(component,target,ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var saved: Resource = ResourceLoader.load(target,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved==null or not saved.valid() or saved.stream_identity()!=component.stream_identity():
		return 1
	for kind in component.meshes.size():
		if not Same.same_mesh(saved.meshes[kind],component.meshes[kind]) or Builder.mesh_bytes(saved.meshes[kind])!=saved.mesh_bytes[kind]:
			return 1
	var report := {"schema":1,"parent_id":parent,"configuration":configuration,"input_sha256":expected_sha,
		"component":{"path":target,"sha256":FileAccess.get_sha256(target)},"bytes":component.geometry_bytes,
		"faces":Array(face_totals).slice(0,choice.kinds),"sources":sources,"bounds":inputs.bounds,
		"packed_roundtrip":true,"fail":0,"canonical_ready":false,"installed":false}
	file=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify(report,"",true,true))
	file.close()
	print("[Full root join] COMPLETE parent=",parent," config=",configuration," cells=256 faces=",report.faces," bytes=",component.geometry_bytes," fail=0")
	return 0
