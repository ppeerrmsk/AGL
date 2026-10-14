extends RefCounted
## 精确北侧候选离线调色；只改变RGB，源、楼高、几何与LOD身份保留。
const Palette := preload("res://scripts/experiments/tokyo_palette.gd")
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const SHA := "fa315481f893082794f9bdad5d084a73fcfa84c5dc1d286c5ef7f0136005f9e6"


static func build(path: String, output: String) -> int:
	var expected_sha := SHA
	if OS.get_environment("AGL_TOKYO_NORTH_RIGHT_PALETTE")=="1":
		if OS.get_environment("AGL_TOKYO_NORTH_LEFT_PALETTE")=="1":
			return 1
		expected_sha="bcba284aa13319d6c887381fd6e4ec5208a58467d7473ade2ad4f0f56c77fc22"
	if OS.get_environment("AGL_TOKYO_NORTH_LEFT_PALETTE")=="1":
		expected_sha="7f933648d6ef66df7326597aba6b1fc200eeb9cbbd1fb38520dd70e4bf09d0df"
	if FileAccess.get_sha256(path)!=expected_sha or not Builder.valid_sample_output(path.get_base_dir(),output):
		return 1
	var original: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if original==null or not original.valid():
		return 1
	var target: Resource = original.duplicate(true)
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		return 1
	var rows: Array = []
	for entry: Dictionary in target.cells:
		for slot in range(-1,7):
			var descriptor: Dictionary = {} if slot==-1 else (entry.mid if slot==6 else entry.levels[slot])
			var source_path: String = entry.fixed if slot==-1 else descriptor.path
			var digest := FileAccess.get_sha256(source_path)
			var source: Resource = ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if source==null or not source.valid():
				return 1
			var candidate: Resource = source.duplicate(false)
			var meshes: Array[ArrayMesh] = []
			for mesh: ArrayMesh in source.meshes:
				var changed := Palette.recolor(mesh)
				if not geometry_equal(mesh,changed):
					return 1
				meshes.append(changed)
			candidate.meshes=meshes
			if source.precision_original!=null:
				candidate.precision_original=Palette.recolor(source.precision_original)
				if not geometry_equal(source.precision_original,candidate.precision_original):
					return 1
			var destination := output.path_join("cell_%02d_slot_%d.res" % [entry.id,slot])
			if not candidate.valid() or ResourceSaver.save(candidate,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
				return 1
			var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
			if saved==null or not saved.valid():
				return 1
			for field: String in ["source_ids","height_hash","bounds","triangles","geometry_bytes"]:
				if source.get(field)!=saved.get(field):
					return 1
			for n in meshes.size():
				if not geometry_equal(source.meshes[n],saved.meshes[n]) or meshes[n].get("_surfaces")!=saved.meshes[n].get("_surfaces"):
					return 1
			if FileAccess.get_sha256(source_path)!=digest:
				return 1
			if slot==-1:
				entry.fixed=destination
			else:
				descriptor.path=destination
			rows.append({"source":source_path,"source_sha256":digest,"path":destination,"sha256":FileAccess.get_sha256(destination)})
	if not target.valid() or ResourceSaver.save(target,output.path_join("index.res"),ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var saved_index: Resource = ResourceLoader.load(output.path_join("index.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved_index==null or not saved_index.valid() or saved_index.cells!=target.cells:
		return 1
	var file := FileAccess.open(output.path_join("palette_report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"source_index_sha256":expected_sha,"index_sha256":FileAccess.get_sha256(output.path_join("index.res")),"palette":Palette.PAIRS,"rows":rows,"geometry_preserved":true,"visual_verified":false,"production_joined":false}))
	file.close()
	print("[North palette] pages=",rows.size()," geometry/alpha/height preserved=true fail=0")
	return 0


static func geometry_equal(a: ArrayMesh, b: ArrayMesh) -> bool:
	if a.get_surface_count()!=b.get_surface_count() or a.get_aabb()!=b.get_aabb():
		return false
	if a.get_surface_count()==0:
		return true
	var x: Dictionary = a.get("_surfaces")[0].duplicate(true)
	var y: Dictionary = b.get("_surfaces")[0].duplicate(true)
	var xa: PackedByteArray = x.attribute_data
	var ya: PackedByteArray = y.attribute_data
	if xa.size()!=ya.size():
		return false
	for n in range(0,xa.size(),4):
		for k in 3:
			xa[n+k]=0
			ya[n+k]=0
	x.attribute_data=xa
	y.attribute_data=ya
	return x==y
