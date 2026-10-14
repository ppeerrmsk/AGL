extends RefCounted
## 独立来源只换现有色板；AO导出保留独立身份，不伪造规范碰撞凭据。
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Palette := preload("res://scripts/experiments/tokyo_palette.gd")
const Audit := preload("res://scripts/tests/test_tokyo_palette.gd")
const REGION := Rect2(-6750, -2400, 400, 400)


func run(index_path: String, output: String, region_name: String = "") -> int:
	var region := region_for(region_name)
	if not region.has_area() or not Builder.valid_sample_output(index_path.get_base_dir(), output):
		return 1
	var source: Resource = ResourceLoader.load(index_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if source == null or not source.valid() or not source.joined_sources.is_empty() or not source.bounds.encloses(region.grow(9.0)):
		return 1
	var target: Resource = source.duplicate(true)
	var auditor := Audit.new()
	var rows: Array = []
	var ao_sources: Array = []
	var ao_triangles: Array = []
	DirAccess.make_dir_recursive_absolute(output)
	for entry: Dictionary in target.cells:
		for slot in range(-1,7):
			var descriptor: Dictionary = {} if slot == -1 else (entry.mid if slot == 6 else entry.levels[slot])
			var path: String = entry.fixed if slot == -1 else descriptor.path
			var old: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if old == null or not old.valid():
				return 1
			var cell: Resource = old.duplicate(false)
			var meshes: Array[ArrayMesh] = []
			for mesh: ArrayMesh in old.meshes:
				meshes.append(Palette.recolor(mesh))
			cell.meshes = meshes
			if old.precision_original != null:
				cell.precision_original = Palette.recolor(old.precision_original)
			var destination := output.path_join("cell_%02d_slot_%d.res" % [old.cell_id,slot])
			if not cell.valid() or ResourceSaver.save(cell,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
				return 1
			var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
			if saved == null or not saved.valid() or saved.source_ids!=old.source_ids or saved.height_hash!=old.height_hash or saved.geometry_bytes!=old.geometry_bytes or saved.triangles!=old.triangles:
				return 1
			for kind in old.meshes.size():
				if not auditor._same_geometry_and_palette(old.meshes[kind],saved.meshes[kind]):
					return 1
			if old.precision_original!=null and not auditor._same_geometry_and_palette(old.precision_original,saved.precision_original):
				return 1
			if slot == -1:
				entry.fixed=destination
			else:
				descriptor.path=destination
			rows.append({"source":path,"source_sha256":FileAccess.get_sha256(path),"path":destination,"sha256":FileAccess.get_sha256(destination),"slot":slot,"cell":old.cell_id})
			if slot in [-1,5]:
				ao_sources.append({"path":destination,"sha256":FileAccess.get_sha256(destination)})
				append_upward(saved,ao_triangles,region)
	if not target.valid() or ResourceSaver.save(target,output.path_join("index.res"),ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var saved_index: Resource = ResourceLoader.load(output.path_join("index.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved_index==null or not saved_index.valid() or saved_index.cells!=target.cells or saved_index.source_hash!=source.source_hash:
		return 1
	var report := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"rows":rows,"source_index_sha256":FileAccess.get_sha256(index_path),"fail":0,"production_enabled":false}))
	report.close()
	var ao := FileAccess.open(output.path_join("ao_source.json"),FileAccess.WRITE)
	ao.store_string(JSON.stringify({"schema":1,"configuration":"independent_cells_lod5","index_path":output.path_join("index.res"),"index_sha256":FileAccess.get_sha256(output.path_join("index.res")),
		"bounds":[region.position.x,region.position.y,region.end.x,region.end.y],"radius":8.0,"sources":ao_sources,"triangles":ao_triangles}))
	ao.close()
	print("[Tokyo regional surface] archives=",rows.size()," AO triangles=",ao_triangles.size()," sources=",ao_sources.size())
	return 0


static func append_upward(cell: Resource, rows: Array, region: Rect2 = REGION) -> void:
	for kind in cell.meshes.size():
		var mesh: ArrayMesh = cell.meshes[kind]
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices.resize(vertices.size())
				for i in vertices.size():
					indices[i]=i
			for offset in range(0,indices.size(),3):
				var points: Array = []
				var bounds := Rect2(Vector2(vertices[indices[offset]].x,vertices[indices[offset]].z),Vector2.ZERO)
				var up := true
				for n in 3:
					var id := indices[offset+n]
					var point := vertices[id]
					up = up and normals[id].y>0.85
					bounds=bounds.expand(Vector2(point.x,point.z))
					points.append([point.x,point.y,point.z])
				if up and bounds.intersects(region.grow(9.0),true):
					rows.append({"cell":cell.cell_id,"slot":cell.level,"kind":kind,"points":points})


static func region_for(name_value: String) -> Rect2:
	match name_value:
		"":
			return REGION
		"west_extension":
			return Rect2(-7250,-2400,400,400)
	return Rect2()
