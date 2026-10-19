extends RefCounted
## 厂棚等高外壳：精确源三角差集，保留周围完整打包属性与源身份。
const Builder := preload("res://scripts/tests/build_tokyo_cells.gd")
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Palette := preload("res://scripts/experiments/tokyo_palette.gd")
const Difference := preload("res://scripts/experiments/tokyo_packed_mesh_difference.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Levels := preload("res://scripts/rendering/tokyo_volume_archive.gd")


static func build(path: String, output: String) -> int:
	var root := path.get_base_dir().get_base_dir()
	var plan_path := root.path_join("r245-depot-union-plan.json")
	var city_path := root.path_join("r240-north-seam-source-b/city.json")
	if FileAccess.get_sha256(path)!="199e256163dc145b447f3f8d8fb3e46540369ada124ba4d786d8fcfd520658c6" or FileAccess.get_sha256(plan_path)!="7588a2776b65972ff09a0c6ec904cffa8940291a4e9476fd615fda5fda203017" or not Builder.valid_sample_output(path.get_base_dir(),output):
		return 1
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	if FileAccess.get_sha256(city_path)!=plan.source_sha256:
		return 1
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(city_path))
	var records: Array[Dictionary] = []
	for record: Dictionary in city.buildings:
		if record.id in plan.source_ids:
			records.append(record)
	if records.size()!=2:
		return 1
	var original: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if original==null or not original.valid():
		return 1
	var index: Resource = original.duplicate(true)
	var owner := -1
	for entry: Dictionary in index.cells:
		var cell: Resource = load(entry.levels[5].path)
		if records[0].id in cell.source_ids or records[1].id in cell.source_ids:
			if owner!=-1 or not (records[0].id in cell.source_ids and records[1].id in cell.source_ids):
				return 1
			owner=entry.id
	if owner<0:
		return 1
	var triangle_points: Array = []
	for triangle: Array in plan.triangles:
		triangle_points.append_array(triangle)
	var union_record: Dictionary = records[0].duplicate(true)
	union_record.rings=[{"outer":plan.outer,"holes":plan.holes,"triangles":triangle_points}]
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		return 1
	var rows: Array = []
	for slot in 7:
		var level := slot if slot<6 else 4
		var descriptor: Dictionary = index.cells[owner].levels[slot] if slot<6 else index.cells[owner].mid
		var source: Resource = ResourceLoader.load(descriptor.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var source_sha := FileAccess.get_sha256(descriptor.path)
		if source==null or not source.valid() or source.precision_original!=null:
			return 1
		var old_geometry := Geometry.new()
		var scale_value: float = 1.0 if slot==6 else Levels.SCALES[level]
		for record: Dictionary in records:
			Factory._add_ring_building(old_geometry,record,11.2,Builder.detail_level(record,scale_value,true))
		var removed := Palette.recolor(old_geometry.mesh())
		var difference := Difference.subtract(source.meshes[0],removed)
		if difference.is_empty() or not Difference.conserved(source.meshes[0],difference.mesh,removed):
			push_error("[Depot union] exact source subtraction failed slot=%d" % slot)
			return 1
		var new_geometry := Geometry.new()
		Factory._add_ring_building(new_geometry,union_record,11.2,Builder.detail_level(union_record,scale_value,true))
		var addition := Palette.recolor(new_geometry.mesh())
		var combined := Join.join([difference.mesh,addition])
		if not Join.conserved(combined,[difference.mesh,addition]):
			return 1
		var candidate: Resource = source.duplicate(false)
		var meshes: Array[ArrayMesh] = [combined,source.meshes[1]]
		candidate.meshes=meshes
		candidate.triangles=0
		candidate.geometry_bytes=0
		Builder.finish(candidate)
		var destination := output.path_join("cell_%02d_slot_%d.res" % [owner,slot])
		if not candidate.valid() or ResourceSaver.save(candidate,destination,ResourceSaver.FLAG_COMPRESS)!=OK:
			return 1
		var saved: Resource = ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE)
		if saved==null or not saved.valid() or saved.source_ids!=source.source_ids or saved.height_hash!=source.height_hash or not Join.conserved(saved.meshes[0],[difference.mesh,addition]) or not Join.conserved(saved.meshes[1],[source.meshes[1]]) or FileAccess.get_sha256(descriptor.path)!=source_sha:
			return 1
		rows.append({"slot":slot,"owner":owner,"source_sha256":source_sha,"before_faces":source.triangles,"after_faces":saved.triangles,"removed_faces":difference.removed,"path":destination})
		descriptor.path=destination
		descriptor.bytes=saved.geometry_bytes
		descriptor.triangles=saved.triangles
	if not index.valid() or ResourceSaver.save(index,output.path_join("index.res"),ResourceSaver.FLAG_COMPRESS)!=OK:
		return 1
	var restored: Resource = ResourceLoader.load(output.path_join("index.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	if restored==null or not restored.valid() or restored.cells!=index.cells:
		return 1
	var file := FileAccess.open(output.path_join("union_report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"rows":rows,"index_sha256":FileAccess.get_sha256(output.path_join("index.res")),"source_ids":plan.source_ids,"height_m":22.4,"production_joined":false,"visual_verified":false}))
	file.close()
	print("[Depot union] saved=7 exact subtraction/source heights preserved=true fail=0")
	return 0
