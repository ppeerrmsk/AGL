extends RefCounted
## 离线跨叶归并；原批次保留逐面owners，归并页记录原组件与连续面区间。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Check := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")


static func run_series(input: Dictionary) -> int:
	var jobs: Variant=input.get("joined_grid_series")
	if not jobs is Array or jobs.is_empty() or jobs.size()>8: return 1
	for job: Variant in jobs:
		if not job is Dictionary: return 1
		var request: Dictionary=job.duplicate()
		request["joined_grid"]=input.get("joined_grid")
		if run(request)!=0: return 1
	return 0


static func run(input: Dictionary) -> int:
	var binding: Variant=input.get("joined_grid")
	var first: Variant=input.get("first")
	var count: Variant=input.get("count")
	var output: String=input.get("output", "")
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return 1
	if not Contract.integer(first,0) or not Contract.integer(count,1,8192 if input.has("reuse_sources") else 256): return 1
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var audit: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not audit is Dictionary or not audit.get("all_batches_complete",false) or audit.get("configuration")!="lod5_full": return 1
	var groups: Dictionary={}
	var seen: Dictionary={}
	var snapshot: Dictionary={}
	var faces := 0
	for record: Dictionary in audit.rows:
		var batch: Variant=record.get("batch")
		if not Contract.binding(batch) or FileAccess.get_sha256(batch.path)!=batch.sha256: return 1
		var file := FileAccess.open(batch.path,FileAccess.READ)
		if file==null: return 1
		var data: Variant=file.get_var(false)
		file.close()
		if not data is Dictionary or data.get("schema")!=1 or data.get("configuration")!="lod5_full" or data.get("grid_world")!=512.0: return 1
		if not data.get("geometry_roundtrip_verified",false): return 1
		if snapshot.is_empty(): snapshot=data.snapshot
		if snapshot!=data.snapshot or data.first!=record.first or data.count!=record.count: return 1
		for index in range(data.first,data.first+data.count):
			if seen.has(index): return 1
			seen[index]=true
		for row_index in data.rows.size():
			var row: Dictionary=data.rows[row_index]
			var counts := PackedInt32Array()
			counts.resize(row.components.size())
			for owner: int in row.owners:
				if owner<0 or owner>=counts.size(): return 1
				counts[owner]+=1
			faces+=row.owners.size()
			for part in row.components.size():
				var descriptor: Dictionary=row.components[part]
				var cell: Vector2i=descriptor.cell
				if cell!=row.cells[part] or counts[part]<=0: return 1
				var key := "%d:%d:%d" % [row.layer,cell.x,cell.y]
				if not groups.has(key): groups[key]=[]
				groups[key].append({"component":descriptor,"batch":batch,"row":row_index,"part":part,
					"faces":counts[part],"source":row.source,"game_sources":row.game_sources,"layer":row.layer,"cell":cell})
	if seen.size()!=int(audit.expected_leaves) or faces!=int(audit.completed_faces): return 1
	for index in int(audit.expected_leaves):
		if not seen.has(index): return 1
	if not Contract.binding(snapshot) or FileAccess.get_sha256(snapshot.path)!=snapshot.sha256: return 1
	var keys: Array=groups.keys()
	keys.sort()
	if input.get("all_groups",false):
		if int(first)!=0 or keys.is_empty() or keys.size()>8192:return 1
		count=keys.size()
	if int(first)+int(count)>keys.size(): return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var pages: Array=[]
	var total_faces := 0
	var total_bytes := 0
	var reusable: Dictionary={}
	if input.has("reuse_sources"):
		reusable=read_reuse(input.reuse_sources)
		if reusable.is_empty():return 1
	var reused_count := 0
	for index in range(int(first),int(first)+int(count)):
		var key: String=keys[index]
		var old: Dictionary=reusable.get(key,{})
		var equivalent: bool=not old.is_empty() and old.origins.size()==groups[key].size()
		if equivalent:
			for i in groups[key].size():
				var before: Dictionary=old.origins[i];var after: Dictionary=groups[key][i]
				if before.component!=after.component or before.faces!=after.faces or before.layer!=after.layer or before.cell!=after.cell or before.game_sources!=after.game_sources:
					equivalent=false;break
		if equivalent:
			if FileAccess.get_sha256(old.path)!=old.sha256:return 1
			var page := old.duplicate();var rebound: Array=[];var cursor := 0
			for origin: Dictionary in groups[key]:
				var item := origin.duplicate();item["first_face"]=cursor;cursor+=int(item.faces);rebound.append(item)
			if cursor!=int(old.faces):return 1
			page["origins"]=rebound;page["reused_geometry"]=true
			pages.append(page);total_faces+=cursor;total_bytes+=int(page.bytes);reused_count+=1
			continue
		var meshes: Array[ArrayMesh]=[]
		var origins: Array=[]
		var offset := 0
		for source: Dictionary in groups[key]:
			var descriptor: Dictionary=source.component
			if FileAccess.get_sha256(descriptor.path)!=descriptor.sha256: return 1
			var loaded: Resource=ResourceLoader.load(descriptor.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if not loaded is Component or not loaded.valid() or loaded.stream_identity()!=descriptor.canonical_identity: return 1
			if loaded.meshes.size()!=1: return 1
			var mesh: ArrayMesh=loaded.meshes[0]
			var raw: Dictionary=Packed._read(mesh)
			if raw.indices.size()!=int(source.faces)*3: return 1
			meshes.append(mesh)
			var origin := source.duplicate()
			origin["first_face"]=offset
			origins.append(origin)
			offset+=int(source.faces)
		var joined := Join.join(meshes)
		if not Check.joined_exact(meshes,joined): return 1
		var component := Component.new()
		component.source_hash=var_to_bytes([snapshot,key,origins,Packed.corner_digest(joined)]).hex_encode().sha256_text()
		component.geometry_bytes=Packed.decoded_bytes(joined)
		component.mesh_bytes=PackedInt32Array([component.geometry_bytes]);component.meshes=[joined]
		var path := output.path_join("grid_%05d.res" % index)
		if not component.valid() or ResourceSaver.save(component,path,ResourceSaver.FLAG_COMPRESS)!=OK: return 1
		var restored: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not restored is Component or not restored.valid() or restored.stream_identity()!=component.stream_identity(): return 1
		if not Check.joined_exact(meshes,restored.meshes[0]): return 1
		pages.append({"key":key,"path":path,"sha256":FileAccess.get_sha256(path),"canonical_identity":component.stream_identity(),
			"bytes":component.geometry_bytes,"faces":offset,"origins":origins,"box":joined.get_aabb()})
		total_faces+=offset;total_bytes+=component.geometry_bytes
	var result := {"schema":1,"audit":binding,"snapshot":snapshot,"first":int(first),"count":int(count),
		"total_groups":keys.size(),"faces":total_faces,"bytes":total_bytes,"pages":pages,"geometry_roundtrip_verified":true,
		"reused_groups":reused_count,"rebuilt_groups":int(count)-reused_count,
		"runtime_integrated":false,"ground_integrated":false}
	var path := output.path_join("joined.bin")
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return 1
	file.store_var(result,false);file.close()
	file=FileAccess.open(path,FileAccess.READ)
	if file==null: return 1
	var restored: Variant=file.get_var(false)
	file.close()
	if restored!=result: return 1
	result.erase("pages")
	result["joined"]={"path":path,"sha256":FileAccess.get_sha256(path)}
	file=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	print("[Tokyo joined grid] saved_readback=true groups=",count," faces=",total_faces)
	return 0


static func read_reuse(root: String) -> Dictionary:
	var result: Dictionary={}
	var directories := DirAccess.get_directories_at(root);directories.sort()
	for directory: String in directories:
		if not directory.begins_with("tokyo-joined-grid-"):continue
		var report_path := root.path_join(directory).path_join("report.json")
		if not FileAccess.file_exists(report_path):continue
		var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report_path))
		if not report.get("geometry_roundtrip_verified",false):return {}
		var binding: Dictionary=report.joined
		if FileAccess.get_sha256(binding.path)!=binding.sha256:return {}
		var file := FileAccess.open(binding.path,FileAccess.READ)
		if file==null:return {}
		var data: Dictionary=file.get_var(false);file.close()
		if not data.get("geometry_roundtrip_verified",false):return {}
		for original: Dictionary in data.pages:
			if result.has(original.key):return {}
			var page := original.duplicate();page["reuse_source"]=binding
			result[page.key]=page
	return result
