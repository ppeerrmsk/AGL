extends RefCounted
## 独立包只供后续接线；旧schema1加载器必须继续拒绝此schema2。
const Candidate := preload("res://scripts/experiments/tokyo_shoreline_morph_candidate.gd")


static func numbers_equal(value: Variant,expected: Array) -> bool:
	if not value is Array or value.size()!=expected.size():
		return false
	for i in expected.size():
		if not typeof(value[i]) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value[i])) or float(value[i])!=float(expected[i]):
			return false
	return true


static func run(source: String,output: String) -> int:
	if DirAccess.dir_exists_absolute(output) or not FileAccess.file_exists(source):
		return 1
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
	if not data is Dictionary or data.get("schema",0)!=1 or data.get("height",0)!=.03 or not numbers_equal(data.get("rgb"),[70,82,83]) or not numbers_equal(data.get("widths"),[2.0,1.0,.35]) or not data.get("groups") is Array:
		print("[R117 bake rejected] header")
		return 1
	if not FileAccess.file_exists(data.get("source","")) or FileAccess.get_sha256(data.source)!=data.get("source_sha",""):
		print("[R117 bake rejected] source identity")
		return 1
	var meshes: Array[ArrayMesh] = []
	var faces: Array[int] = []
	for slot in 4:
		var mesh := Candidate.build_mesh(data.groups,slot)
		if mesh==null:
			print("[R117 bake rejected] slot=",slot)
			return 1
		meshes.append(mesh)
		faces.append(mesh.surface_get_array_len(0)/3)
	if not data.get("summary") is Dictionary or faces[0]!=data.summary.get("morph_faces",-1):
		print("[R117 bake rejected] shared cost")
		return 1
	for i in 3:
		if faces[i+1]!=data.summary.fallback_faces[i] or faces[0]+faces[i+1]!=data.summary.baseline_faces[i]:
			print("[R117 bake rejected] fallback cost ",i)
			return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		return 1
	var rows: Array = []
	var exported: Array = []
	for slot in 4:
		var name := "morph.res" if slot==0 else "fallback_%d.res"%(slot-1)
		var path := output.path_join(name)
		if ResourceSaver.save(meshes[slot],path)!=OK:
			return 1
		var copy: ArrayMesh = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if copy==null or var_to_bytes(copy.surface_get_arrays(0))!=var_to_bytes(meshes[slot].surface_get_arrays(0)) or copy.custom_aabb!=meshes[slot].custom_aabb:
			print("[R117 bake rejected] roundtrip ",slot)
			return 1
		var arrays := copy.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var offsets: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var points: Array = []
		for i in vertices.size():
			points.append([vertices[i].x,vertices[i].y,vertices[i].z,offsets[i].x,offsets[i].y])
		var bound := copy.custom_aabb
		exported.append({"file":name,"points":points,"aabb":[bound.position.x,bound.position.y,bound.position.z,bound.end.x,bound.end.y,bound.end.z]})
		rows.append({"file":name,"sha256":FileAccess.get_sha256(path),"faces":faces[slot]})
	var manifest := {"schema":2,"plan_sha":FileAccess.get_sha256(source),"source_sha":data.source_sha,"meshes":rows,"widths":[2.0,1.0,.35],"reserved_bytes":(faces[0]+faces[1]+faces[2]+faces[3])*3*64*3,"runtime_enabled":false}
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"))
	file.close()
	file=FileAccess.open(output.path_join("native_geometry.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(exported))
	file.close()
	print("[R117 native bake] ",manifest)
	return 0
