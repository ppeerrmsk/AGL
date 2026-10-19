extends RefCounted
## 独立中景候选：概括低层几何配原中景纹理；实际回读后才能迁移高楼凭据。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Coverage := preload("res://scripts/rendering/tokyo_hlod_coverage.gd")
const Packing := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const Foundation := preload("res://scripts/rendering/tokyo_hlod_foundation.gd")
const Audit := preload("res://scripts/tests/tokyo_foundation_audit.gd")
const PACKAGE := "res://resources/maps/tokyo_playable/m20/package.json"
const PACKAGE_SHA := "424e4aa1db195308389ffcce30ff672bc5b23851810801847199b4d9d572d858"


static func write_json(path: String, data: Dictionary) -> Dictionary:
	if FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return {}
	var encoded := JSON.stringify(data,"\t",true,true)
	file.store_string(encoded);file.close()
	var restored: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if restored!=JSON.parse_string(encoded): return {}
	return {"path":path,"sha256":FileAccess.get_sha256(path)}


static func aligned(mesh: ArrayMesh, bounds: Array) -> bool:
	if mesh==null or not Contract.numbers(bounds,4) or bounds[2]<=bounds[0] or bounds[3]<=bounds[1]: return false
	if mesh.get_surface_count()==0: return true
	if mesh.get_surface_count()!=1: return false
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	if uv.size()!=points.size(): return false
	for i in points.size():
		var expected := (Vector2(points[i].x,points[i].z)-Vector2(bounds[0],bounds[1]))/Vector2(bounds[2]-bounds[0],bounds[3]-bounds[1])
		if not uv[i].is_finite() or not expected.is_finite() or uv[i].distance_to(expected)>0.000002: return false
	return true


static func component(row: Dictionary, proof: Dictionary) -> Resource:
	var binding: Dictionary=row.native_geometry
	if FileAccess.get_sha256(binding.path)!=binding.sha256: return null
	var resource: Resource=ResourceLoader.load(binding.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if resource==null or not resource.has_method("valid") or not resource.valid() or resource.meshes.size()!=2 \
		or resource.schema_version!=int(binding.canonical_identity.schema) \
		or resource.source_hash!=binding.canonical_identity.source or resource.geometry_bytes!=int(binding.bytes) \
		or Count.triangles(resource.meshes[0])!=int(row.ordinary_faces) \
		or Count.triangles(resource.meshes[1])+int(row.ordinary_faces)+2!=int(row.faces) \
		or not Coverage.matches(resource.meshes[1],proof): return null
	return resource


static func checks() -> bool:
	if aligned(null,[0,0,1,1]) or aligned(ArrayMesh.new(),[0,0,0,1]): return false
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3(1,0,0),Vector3(0,0,1)])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN])
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return aligned(mesh,[0,0,1,1]) and not aligned(mesh,[0,0,2,1])


static func run(output: String) -> int:
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output) or not checks() \
		or FileAccess.get_sha256(PACKAGE)!=PACKAGE_SHA: return 1
	if preload("res://scripts/rendering/tokyo_hlod_cache_policy.gd").display_limit()!=192*1024*1024:
		print("[Middle massing] requires the explicitly approved high-memory 192MiB candidate configuration");return 1
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PACKAGE))
	var fine := Contract.read(package.catalogs[5].path,package.catalogs[5].sha256)
	var coarse := Contract.read(package.catalogs[6].path,package.catalogs[6].sha256)
	if fine.is_empty() or coarse.is_empty(): return 1
	var fine_proof := Coverage.read(package.coverage.path,package.coverage.sha256,fine)
	var coarse_proof := Coverage.read(package.coverage.path,package.coverage.sha256,coarse)
	if fine_proof.is_empty() or coarse_proof.is_empty(): return 1
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(package.catalogs[6].path))
	var fine_data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(package.catalogs[5].path))
	var rows: Array=[]
	var images := {}
	var vertices := 0
	for key: String in coarse.rows:
		var row: Dictionary=coarse.rows[key]
		var detail: Dictionary=fine.rows[key]
		if row.bounds!=detail.bounds or row.texture.bounds!=detail.texture.bounds or row.formal_source_ids!=detail.formal_source_ids: return 1
		var coarse_mesh := component(row,coarse_proof[row.native_geometry.path])
		var fine_mesh := component(detail,fine_proof[detail.native_geometry.path])
		if coarse_mesh==null or fine_mesh==null or not aligned(coarse_mesh.meshes[0],detail.texture.bounds) \
			or Packing.corner_digest(coarse_mesh.meshes[1])!=Packing.corner_digest(fine_mesh.meshes[1]):
			print("[Middle massing] mismatch page=",key," coarse=",coarse_mesh!=null," fine=",fine_mesh!=null,
				" uv=",aligned(coarse_mesh.meshes[0],detail.texture.bounds) if coarse_mesh!=null else false)
			push_error("Middle massing mesh mismatch: "+key);return 1
		if coarse_mesh.meshes[0].get_surface_count()==1:
			vertices+=coarse_mesh.meshes[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		var texture: Dictionary=detail.native_texture
		if not images.has(texture.path):
			if FileAccess.get_sha256(texture.path)!=texture.sha256: return 1
			var image_resource: Resource=ResourceLoader.load(texture.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if not image_resource is Image or image_resource.get_width()!=int(detail.texture.levels[0].width) \
				or image_resource.get_height()!=int(detail.texture.levels[0].height) or not image_resource.has_mipmaps() \
				or image_resource.get_format()!=int(texture.format) or image_resource.get_data().size()!=int(texture.mip_bytes): return 1
			images[texture.path]=true
		var saved := row.duplicate(true)
		for field: String in ["texture","native_texture","decoded_texture"]: saved[field]=detail[field].duplicate(true)
		# 新表示独立试制资格；原目录6不修改，细纹理原有逐页资格仍保留。
		saved.erase("max_scale")
		if detail.has("max_scale"): saved.max_scale=detail.max_scale
		rows.append(saved)
		if rows.size()%16==0: print("[Middle massing] actual meshes/UV/formal checked=",rows.size(),"/336")
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var recipe := write_json(output.path_join("recipe.json"),{"schema":1,"source_package":{"path":PACKAGE,"sha256":PACKAGE_SHA},
		"geometry":package.catalogs[6],"texture":package.catalogs[5],"formal_all_channels_equal":true,
		"checked_pages":rows.size(),"checked_uv_vertices":vertices,"visual_accepted":false,"performance_accepted":false})
	if recipe.is_empty(): return 1
	manifest.rows=rows;manifest.min_scale=fine_data.min_scale;manifest.max_scale=fine_data.max_scale
	manifest.input_path=recipe.path;manifest.input_sha256=recipe.sha256
	manifest.texture_reuse_path=package.catalogs[5].path;manifest.texture_reuse_sha256=package.catalogs[5].sha256
	for field: String in ["native_visual_accepted","runtime_integrated","formal_runtime_coverage_verified","texture_error_accepted"]: manifest[field]=false
	manifest["middle_massing_recipe"]=recipe
	if Contract.normalize(manifest).is_empty(): return 1
	var binding := write_json(output.path_join("middle.json"),manifest)
	if binding.is_empty(): return 1
	var candidate := Contract.read(binding.path,binding.sha256)
	var coverage: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(package.coverage.path))
	var source: Dictionary={}
	var replace := -1
	for i in coverage.catalogs.size():
		if coverage.catalogs[i].manifest.path==package.catalogs[6].path: source=coverage.catalogs[i].duplicate(true)
		if coverage.catalogs[i].manifest.path==package.catalogs[5].path: replace=i
	if source.is_empty() or replace<0: return 1
	source.manifest=binding
	coverage.catalogs[replace]=source
	if Coverage.bind(coverage,candidate).is_empty(): return 1
	var coverage_binding := write_json(output.path_join("coverage.json"),coverage)
	if coverage_binding.is_empty(): return 1
	var entries: Array[Dictionary]=[]
	for root: Dictionary in candidate.roots: entries.append_array(Audit.leaves(root,1))
	var report := {"schema":1,"samples":0,"fail":0,"max_faces":0,"max_bytes":0,"failures":[],"recipe":recipe,"visual_accepted":false}
	for size: Vector2 in [Vector2(1600,900),Vector2(2100,900)]:
		for scale: float in [0.2500001,0.4375,0.625]:
			for x in range(-16000,16001,2000):
				for y in range(-16000,16001,2000):
					for angle: float in [0.0,deg_to_rad(-14),deg_to_rad(12)]:
						var independent := Audit.sample(entries,candidate,Vector2(x,y),scale,angle,size,true)
						var selected := Foundation.select(candidate,entries,Vector2(x,y),scale,angle,size,192*1024*1024)
						var passed: bool=not selected.is_empty() and independent.covered and independent.qualified \
							and selected.bytes==independent.bytes and selected.triangles==independent.faces
						report.samples+=1;report.fail+=int(not passed)
						report.max_faces=maxi(report.max_faces,independent.faces);report.max_bytes=maxi(report.max_bytes,independent.bytes)
						if not passed and report.failures.size()<8: report.failures.append(independent)
	if write_json(output.path_join("report.json"),report).is_empty(): return 1
	if report.fail!=0:
		print("[Middle massing] fixed partition rejected: ",report);return 1
	package.catalogs[5]=binding.duplicate(true)
	package.catalogs[5]["range"]=[0.24,0.625]
	package.catalogs[5]["resident_middle_massing"]=true
	package.coverage=coverage_binding
	package["candidate_only"]=true;package["middle_massing_recipe"]=recipe
	var published := write_json(output.path_join("package.json"),package)
	if published.is_empty(): return 1
	print("[Middle massing] candidate=",published," static samples=",report.samples,"; NOT Visual/performance accepted")
	return 0
