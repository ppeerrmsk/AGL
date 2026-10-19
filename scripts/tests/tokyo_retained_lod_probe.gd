extends RefCounted
## 有限离线试验：只处理西侧保留楼体，不覆盖任何正式资源。


static func run(root: String, output: String) -> int:
	var source := root.path_join("r179-joint-patch-b/shared-complete.bin")
	if DirAccess.dir_exists_absolute(output) or FileAccess.get_sha256(source)!="159183c9bff5d28c5c99a67c1abca4a611ca1c05d90b8a5da1bb7c6b2007533c":
		return 1
	var bytes := FileAccess.get_file_as_bytes(source).slice(6034*120,(6034+2642)*120)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var owners: Dictionary = {}
	for offset in range(0,bytes.size(),40):
		var record := bytes.slice(offset,offset+40)
		var key := record.hex_encode()
		if not owners.has(key):
			var v := record.to_float32_array()
			owners[key]=vertices.size()
			vertices.append(Vector3(v[0],v[1],v[2]))
			normals.append(Vector3(v[3],v[4],v[5]))
			colors.append(Color(v[6],v[7],v[8],v[9]))
		indices.append(owners[key])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	var importer := ImporterMesh.new()
	var argument_count := -1
	for method: Dictionary in importer.get_method_list():
		if method.name=="generate_lods":
			argument_count=method.args.size()
	if argument_count not in [2,3]:
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array = []
	var per_building := OS.get_environment("AGL_TOKYO_RETAINED_LOD_BUILDINGS")=="1"
	if per_building:
		var path := root.path_join("r182-building-owners-a.json")
		if FileAccess.get_sha256(path)!="dd21298cc3254330f0c1e2a098b2b967b19aa15a05f3b425cd6b1aef8c2f13ae":
			return 1
		var owners_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for building in owners_data.buildings.size():
			var subset := PackedInt32Array()
			for face: float in owners_data.buildings[building].indices:
				subset.append_array(indices.slice(int(face)*3,int(face)*3+3))
			var local := arrays.duplicate()
			local[Mesh.ARRAY_INDEX]=subset
			rows.append_array(generate_variants(local,output,argument_count,building))
	else:
		rows=generate_variants(arrays,output,argument_count,-1)
	for row: Dictionary in rows:
		if row.has("export_failed"):
			return 1
	var report := {"engine":Engine.get_version_info().string,"argument_count":argument_count,"source_sha256":FileAccess.get_sha256(source),"source_faces":2642,"source_vertices":vertices.size(),"rows":rows,"per_building":per_building,"visual_validated":false,"runtime_integrated":false}
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("[retained LOD] variants=",rows.size()," per_building=",per_building)
	return 0


static func generate_variants(arrays: Array, output: String, argument_count: int, building: int) -> Array:
	var importer := ImporterMesh.new()
	var rows: Array = []
	for angle: float in [20.0,60.0]:
		importer.clear()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays)
		if argument_count==2:
			importer.callv("generate_lods",[angle,[]])
		else:
			importer.callv("generate_lods",[angle,0.0,[]])
		var generated := importer.get_surface_arrays(0)
		var generated_vertices: PackedVector3Array = generated[Mesh.ARRAY_VERTEX]
		var generated_normals: PackedVector3Array = generated[Mesh.ARRAY_NORMAL]
		var generated_colors: PackedColorArray = generated[Mesh.ARRAY_COLOR]
		for lod in importer.get_surface_lod_count(0):
			var selected := importer.get_surface_lod_indices(0,lod)
			var payload := PackedFloat32Array()
			for index in selected:
				var p := generated_vertices[index]
				var n := generated_normals[index]
				var c := generated_colors[index]
				payload.append_array(PackedFloat32Array([p.x,p.y,p.z,n.x,n.y,n.z,c.r,c.g,c.b,c.a]))
			var filename := "angle_%d_lod_%d.bin"%[angle,lod]
			if building>=0:
				filename="building_%d_"%building+filename
			var file := FileAccess.open(output.path_join(filename),FileAccess.WRITE)
			if file==null:
				push_error("Retained LOD export failed")
				return [{"export_failed":true}]
			file.store_buffer(payload.to_byte_array())
			file.close()
			rows.append({"building":building,"angle":angle,"lod":lod,"faces":selected.size()/3,"size":importer.get_surface_lod_size(0,lod),"file":filename,"sha256":FileAccess.get_sha256(output.path_join(filename))})
	return rows
