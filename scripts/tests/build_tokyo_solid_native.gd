extends RefCounted
## 当前实物组件上的低楼差集；固定层/高楼及玩法覆盖不改，输出独立包。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Native := preload("res://scripts/rendering/tokyo_hlod_native.gd")
const Merge := preload("res://scripts/tests/tokyo_solid_native_mesh.gd")
const Save := preload("res://scripts/tests/build_tokyo_mesh_components.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")

static func bind(path: String) -> Dictionary:
	return {"path":path,"sha256":FileAccess.get_sha256(path)}

static func write_values(path: String, value: Variant) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return false
	file.store_var(value,false);file.close();return true

static func refresh(entries: Array, pages: Dictionary, changed: Dictionary, catalog: Resource) -> void:
	for entry: Dictionary in entries:
		var row: Dictionary=pages[entry.path]
		entry.bytes=row.bytes
		for kind in 3:
			var path: String=row.mapping[kind][0]
			if changed.has(path):
				entry.triangles[kind]=changed[path].faces
				entry.boxes[kind]=changed[path].bounds
		catalog.descriptors[entry.path].bytes=row.bytes
		refresh(entry.get("children",[]),pages,changed,catalog)

static func run(input: String, output: String) -> int:
	if DirAccess.dir_exists_absolute(output): return 1
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if not config is Dictionary: return 1
	for key: String in ["package","plan","formal"]:
		if not Contract.binding(config.get(key)) or FileAccess.get_sha256(config[key].path)!=config[key].sha256: return 1
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.package.path))
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.plan.path))
	if plan.get("profile")!="street_solid" or plan.get("max_scale")!=5.0: return 1
	var native := Native.new()
	if not native.read(package.native): return 1
	var file := FileAccess.open(package.native.components.path,FileAccess.READ)
	var data: Dictionary=file.get_var(false);file.close()
	var catalog: Resource=native.catalog.duplicate(true)
	var formal: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config.formal.path))
	var plans: Array=[]
	for group: Dictionary in plan.groups:
		var shape := PackedVector2Array()
		for p: Array in group.outer: shape.append(Vector2(p[0],p[1]))
		var safe := true
		for building: Dictionary in formal.expected:
			var ring := PackedVector2Array()
			for p: Array in building.points: ring.append(Vector2(p[0],p[1]))
			if not Geometry2D.intersect_polygons(shape,ring).is_empty(): safe=false;break
		if safe: plans.append(group)
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var paths: Dictionary={}
	var region := Rect2(-6300,-3700,4000,2000)
	for entries: Array in catalog.configurations.values(): collect(entries,data.pages,region,paths)
	var replacements: Dictionary={};var changed: Dictionary={}
	var report := {"physical_examined":0,"physical_changed":0,"groups":0,"saved_faces":0,"saved_bytes":0,"formal_unchanged":true,"installed":false}
	for path: String in paths:
		var descriptor: Dictionary=data.physical[path]
		if not Contract.binding(descriptor) or FileAccess.get_sha256(path)!=descriptor.sha256: return 1
		var source: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if source==null or not source.valid() or source.meshes.size()!=1 or source.stream_identity()!=descriptor.canonical_identity: return 1
		var result := Merge.merge_mesh(source.meshes[0],plans)
		if result.is_empty():
			push_error("Solid partition failed: "+path);return 1
		report.physical_examined+=1
		if result.groups>0:
			var destination := output.path_join("low_"+path.sha256_text()+".res")
			var meshes: Array[ArrayMesh]=[result.mesh]
			var saved := Save._save(meshes,source.source_hash+config.plan.sha256+"solid-current-v1",destination)
			if saved.is_empty() or saved.bytes>descriptor.bytes:
				push_error("Solid save/bytes failed: "+path);return 1
			replacements[path]=saved
			changed[destination]={"faces":Count.triangles(result.mesh),"bounds":result.mesh.get_aabb()}
			report.physical_changed+=1;report.groups+=result.groups;report.saved_faces+=result.saved;report.saved_bytes+=descriptor.bytes-saved.bytes
		if report.physical_examined%8==0: print("[Solid current] ",report," / ",paths.size())
	if replacements.is_empty(): return 1
	for row: Dictionary in data.pages.values():
		var old: String=row.mapping[0][0]
		if not replacements.has(old): continue
		var replacement: Dictionary=replacements[old]
		var old_faces: int=paths[old]
		row.bytes-=int(row.components[old].bytes)-int(replacement.bytes)
		row.triangles-=old_faces-int(changed[replacement.path].faces)
		row.components.erase(old);row.components[replacement.path]=replacement;row.mapping[0][0]=replacement.path
	for old: String in replacements:
		data.physical.erase(old);data.physical[replacements[old].path]=replacements[old]
	for entries: Array in catalog.configurations.values(): refresh(entries,data.pages,changed,catalog)
	if not catalog.valid(): return 1
	var catalog_path := output.path_join("catalog.res")
	if ResourceSaver.save(catalog,catalog_path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
	data.catalog_sha256=FileAccess.get_sha256(catalog_path)
	var components_path := output.path_join("components.bin")
	if not write_values(components_path,data): return 1
	package.native.catalog=bind(catalog_path);package.native.components=bind(components_path)
	for name: String in package.native.coverage:
		file=FileAccess.open(package.native.coverage[name].path,FileAccess.READ)
		var coverage: Dictionary=file.get_var(false);file.close()
		coverage.catalog_sha256=data.catalog_sha256
		var destination := output.path_join("coverage_"+name+".bin")
		if not write_values(destination,coverage): return 1
		package.native.coverage[name]=bind(destination)
	if not Native.new().read(package.native): return 1
	file=FileAccess.open(output.path_join("package.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(package,"\t"));file.close()
	report["input"]=config
	file=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("[Solid current] COMPLETE ",report)
	return 0

static func collect(entries: Array, pages: Dictionary, region: Rect2, paths: Dictionary) -> void:
	for entry: Dictionary in entries:
		var box: AABB=entry.boxes[0]
		if Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)).intersects(region):
			var path: String=pages[entry.path].mapping[0][0]
			assert(not paths.has(path) or paths[path]==entry.triangles[0])
			paths[path]=entry.triangles[0]
		collect(entry.get("children",[]),pages,region,paths)
