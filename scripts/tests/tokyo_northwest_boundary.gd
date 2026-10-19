extends RefCounted
## 当前成品的边界差集准备；不写回目录，逐配置保留失败证据。
const Boundary := preload("res://scripts/tests/build_tokyo_boundary_transfer.gd")
const SOURCE_SHA := "bccdd77db85e42d9ac258b9ca6497557fcb34b1e5ac3703fb805fd541099b827"
const REGISTRY_SHA := "b2071a17cbb4222ddd7532b495f1ed2425212e9dac237d388aedbe4ce8c068fe"


static func compare_positions(original: ArrayMesh, target: ArrayMesh) -> Dictionary:
	var source: Dictionary = {}
	var missing := 0
	var attributes := 0
	var sample: Dictionary = {}
	for which in 2:
		var mesh := original if which==0 else target
		if mesh.get_surface_count()==0:
			continue
		var data := mesh.surface_get_arrays(0)
		var points: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = data[Mesh.ARRAY_COLOR]
		var ids: PackedInt32Array = data[Mesh.ARRAY_INDEX] if data[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if ids.is_empty():
			for i in points.size():
				ids.append(i)
		for first in range(0,ids.size(),3):
			var p := PackedVector3Array()
			var n := PackedVector3Array()
			var c := PackedColorArray()
			for k in 3:
				p.append(points[ids[first+k]])
				n.append(normals[ids[first+k]])
				c.append(colors[ids[first+k]])
			var key := p.to_byte_array()
			var value := var_to_bytes([n,c])
			if which==0:
				if not source.has(key):
					source[key]=[]
				source[key].append({"value":value,"normal":str(n),"color":str(c)})
			elif not source.has(key) or source[key].is_empty():
				missing+=1
			else:
				var found := -1
				for i in source[key].size():
					if source[key][i].value==value:
						found=i
						break
				if found<0:
					attributes+=1
					if sample.is_empty():
						sample={"points":str(p),"actual_normal":source[key][0].normal,"target_normal":str(n),"actual_color":source[key][0].color,"target_color":str(c)}
				source[key].remove_at(maxi(found,0))
	return {"missing_position_faces":missing,"attribute_mismatch_faces":attributes,"sample":sample}


static func run(root: String, output: String) -> int:
	if OS.get_environment("AGL_TOKYO_SOUTHWEST_BOUNDARY")=="1":
		return southwest(root,output,false)
	if root.is_empty() or output.is_empty() or not Boundary.Far.Builder.valid_sample_output(root.path_join("r193-native-full-a"),output):
		print("[Northwest boundary rejected] output scope")
		return 1
	var catalog_path := root.path_join("r193-native-full-a/catalog.res")
	var registry_path := root.path_join("r200-owned-source-a/ownership.json")
	var old_path := root.path_join("r134-owned-source-a/ownership.json")
	if FileAccess.get_sha256(catalog_path)!=SOURCE_SHA or FileAccess.get_sha256(registry_path)!=REGISTRY_SHA or FileAccess.get_sha256(old_path)!="d35401afb80841508b0d1c6afca4a3d0eb674bacfcac51be801889b6d4cb8abb":
		print("[Northwest boundary rejected] source identity")
		return 1
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(registry_path))
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_path))
	var records: Dictionary = {}
	var owners: Dictionary = {}
	for pair: Array in [["north_coast","r30-area-source-b/north_coast"],["west_residential","r119-west-source-b"],["west_extension","r133-west2-strokes-a"]]:
		var source := root.path_join(pair[1]+"/city.json")
		var expected: String = Boundary.Far.CITY_HASH if pair[0]=="north_coast" else old.inputs[pair[0]]["city.json"]
		if FileAccess.get_sha256(source)!=expected:
			print("[Northwest boundary rejected] city identity ",pair[0])
			return 1
		var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
		for raw: Dictionary in city.buildings:
			if not old.assignments.has(raw.id) or old.assignments[raw.id].owner!=pair[0] or registry.assignments[raw.id].owner==pair[0]:
				continue
			if registry.assignments[raw.id].owner!="northwest" or records.has(raw.id):
				return 1
			records[raw.id]=raw
			owners[raw.id]=pair[0]
	if records.size()!=69:
		print("[Northwest boundary rejected] records=",records.size())
		return 1
	var parents: Dictionary = {}
	var assigned: Dictionary = {}
	var index: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	for entry: Dictionary in index.cells:
		var cell: Resource = load(entry.levels[5].path)
		for identity: String in cell.source_ids:
			if owners.get(identity,"")!="north_coast":
				continue
			if assigned.has(identity):
				return 1
			assigned[identity]=entry.id
	for identity: String in owners:
		if owners[identity]!="north_coast":
			assigned[identity]=11
	if assigned.size()!=69:
		print("[Northwest boundary rejected] assigned=",assigned.size())
		return 1
	for identity: String in assigned:
		var parent: int = assigned[identity]
		if not parents.has(parent):
			parents[parent]=[]
		parents[parent].append(records[identity])
	var catalog: Resource = ResourceLoader.load(catalog_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if catalog==null or not catalog.valid():
		print("[Northwest boundary rejected] catalog")
		return 1
	var game := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd").read_source()
	if game.is_empty() or game.collision_sha256!=catalog.collision_sha256:
		print("[Northwest boundary rejected] gameplay")
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var report := {"source_catalog_sha256":SOURCE_SHA,"registry_sha256":REGISTRY_SHA,"assigned":assigned,"rows":[],"failures":[],"position_diagnostics":[],"production_enabled":false}
	for configuration: String in Boundary.Catalog.CONFIGURATIONS:
		for parent: int in parents:
			var entry: Dictionary = catalog.configurations[configuration][parent]
			if FileAccess.get_sha256(entry.path)!=entry.sha256:
				return 1
			var original: Resource = ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var removed := Boundary.target_meshes(parents[parent],configuration)
			for kind in 2:
				var historical := parent==11 and kind==0 and configuration in ["lod4_full","lod5_full"]
				if historical:
					removed[kind]=historical_target(root,configuration,removed[kind])
					if removed[kind]==null:
						print("[Historical target rejected] ",configuration)
						return 1
				var result := Boundary.Diff.subtract(original.meshes[kind],removed[kind])
				var roundtrips := 0
				# 父11低层来自历史float导出/导入；只还原目标编码，原成品字节不动。
				if parent==11 and kind==0 and not historical:
					while result.is_empty() and roundtrips<2:
						removed[kind]=decoded_roundtrip(removed[kind])
						roundtrips+=1
						result=Boundary.Diff.subtract(original.meshes[kind],removed[kind])
				var label := "%s_parent%d_layer%d" % [configuration,parent,kind]
				if result.is_empty() or not Boundary.Diff.conserved(original.meshes[kind],result.mesh,removed[kind]):
					report.failures.append(label)
					var diagnosis := compare_positions(original.meshes[kind],removed[kind])
					diagnosis.label=label
					report.position_diagnostics.append(diagnosis)
					continue
				if removed[kind].get_surface_count()>0:
					var box := removed[kind].get_aabb()
					var guard := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd").inspect_bounds(Rect2(box.position.x,box.position.z,box.size.x,box.size.z),game.entries)
					if guard.is_empty() or not guard.standalone_merge_allowed:
						print("[Northwest boundary rejected] gameplay bounds ",label," ",box)
						return 1
				var kept_path := output.path_join(label+"_kept.res")
				var removed_path := output.path_join(label+"_removed.res")
				if ResourceSaver.save(result.mesh,kept_path,ResourceSaver.FLAG_COMPRESS)!=OK or ResourceSaver.save(removed[kind],removed_path,ResourceSaver.FLAG_COMPRESS)!=OK:
					return 1
				var kept: ArrayMesh = ResourceLoader.load(kept_path,"",ResourceLoader.CACHE_MODE_IGNORE)
				var delta: ArrayMesh = ResourceLoader.load(removed_path,"",ResourceLoader.CACHE_MODE_IGNORE)
				if not Boundary.Diff.conserved(original.meshes[kind],kept,delta):
					return 1
				report.rows.append({"configuration":configuration,"parent":parent,"layer":kind,"original":entry.path,"original_sha256":entry.sha256,"kept":kept_path,"kept_sha256":FileAccess.get_sha256(kept_path),"removed":removed_path,"removed_sha256":FileAccess.get_sha256(removed_path),"removed_faces":result.removed,"target_encoding_roundtrips":roundtrips,"historical_attributes":historical})
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	print("[Northwest boundary] parents=",parents.keys()," rows=",report.rows.size()," failures=",report.failures)
	return 0 if report.failures.is_empty() else 1


static func decoded_roundtrip(mesh: ArrayMesh) -> ArrayMesh:
	if mesh.get_surface_count()==0:
		return ArrayMesh.new()
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.surface_get_arrays(0))
	return result


static func historical_target(root: String, configuration: String, target: ArrayMesh) -> ArrayMesh:
	var hashes := {"lod4_full":"45eec139fb755b9015c0242d25092ad3b49c22abce9a615f25c68fa54e142ec2","lod5_full":"67451423fe7ddcee76c2e30ba757b079fcb2f083e4b648d1dd59ff8f003432f5"}
	if not hashes.has(configuration):
		return null
	var path := root.path_join("r161-original-matrix-a/"+configuration+"-original.bin.attributes")
	if FileAccess.get_sha256(path)!=hashes[configuration]:
		return null
	var source := preload("res://scripts/tests/tokyo_residential_patch.gd").decode(FileAccess.get_file_as_bytes(path))
	return select_historical(source,target) if source!=null else null


static func select_historical(source: ArrayMesh, target: ArrayMesh) -> ArrayMesh:
	if source==null or target==null or not Boundary.Diff.supported(source) or not Boundary.Diff.supported(target):
		return null
	var faces: Dictionary = {}
	var selected := PackedInt32Array()
	var seen: Dictionary = {}
	var bounds := AABB()
	var first_point := true
	for which in 2:
		var mesh := source if which==0 else target
		if mesh.get_surface_count()==0:
			continue
		var data := mesh.surface_get_arrays(0)
		var points: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = data[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX] if data[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for i in points.size():
				indices.append(i)
		for first in range(0,indices.size(),3):
			var p := PackedVector3Array()
			var c := PackedColorArray()
			for i in 3:
				p.append(points[indices[first+i]])
				c.append(colors[indices[first+i]])
			var key := var_to_bytes([p,c])
			if which==0:
				if not faces.has(key):
					faces[key]=[]
				faces[key].append(indices.slice(first,first+3))
			else:
				if not faces.has(key) or faces[key].size()!=1 or seen.has(key):
					print("[Historical selection rejected] face=",first/3," matches=",faces.get(key,[]).size()," reused=",seen.has(key)," position=",p)
					return null
				seen[key]=true
				selected.append_array(faces[key][0])
				for point: Vector3 in p:
					if first_point:
						bounds=AABB(point,Vector3.ZERO)
						first_point=false
					else:
						bounds=bounds.expand(point)
	if selected.is_empty():
		return ArrayMesh.new()
	var result := preload("res://scripts/tests/build_tokyo_path_lod.gd").subset(source,selected)
	# 通用subset保留旧surface包围盒；这里必须按实际索引面收紧，不能误报全父区玩法交叠。
	var surfaces: Array = result.get("_surfaces").duplicate(true)
	surfaces[0].aabb=bounds
	result.set("_surfaces",surfaces)
	return result


static func audit(root: String, directory: String) -> int:
	if OS.get_environment("AGL_TOKYO_SOUTHWEST_BOUNDARY")=="1":
		return southwest(root,directory,true)
	if root.is_empty() or directory.is_empty() or not FileAccess.file_exists(directory.path_join("report.json")) or FileAccess.file_exists(directory.path_join("saved_audit.json")):
		return 1
	var source := root.path_join("r193-native-full-a/catalog.res")
	if FileAccess.get_sha256(source)!=SOURCE_SHA or FileAccess.get_sha256(root.path_join("r200-owned-source-a/ownership.json"))!=REGISTRY_SHA:
		return 1
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("report.json")))
	if report.get("source_catalog_sha256","")!=SOURCE_SHA or report.get("registry_sha256","")!=REGISTRY_SHA or report.get("production_enabled",true) or report.get("failures",[1]).size()!=0 or report.get("rows",[]).size()!=66 or report.get("assigned",{}).size()!=69:
		return 1
	var catalog: Resource = ResourceLoader.load(source,"",ResourceLoader.CACHE_MODE_IGNORE)
	var game := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd").read_source()
	if catalog==null or not catalog.valid() or game.is_empty() or game.collision_sha256!=catalog.collision_sha256:
		return 1
	var seen: Dictionary = {}
	var totals: Dictionary = {}
	for row: Dictionary in report.rows:
		var parent := int(row.parent)
		var layer := int(row.layer)
		if row.configuration not in Boundary.Catalog.CONFIGURATIONS or parent not in [8,9,11] or layer not in [0,1]:
			return 1
		var key := "%s:%d:%d" % [row.configuration,parent,layer]
		if seen.has(key):
			return 1
		seen[key]=true
		var entry: Dictionary = catalog.configurations[row.configuration][parent]
		if row.original!=entry.path or row.original_sha256!=entry.sha256 or FileAccess.get_sha256(entry.path)!=entry.sha256 or FileAccess.get_sha256(row.kept)!=row.kept_sha256 or FileAccess.get_sha256(row.removed)!=row.removed_sha256:
			return 1
		var original: Resource = ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var kept: ArrayMesh = ResourceLoader.load(row.kept,"",ResourceLoader.CACHE_MODE_IGNORE)
		var removed: ArrayMesh = ResourceLoader.load(row.removed,"",ResourceLoader.CACHE_MODE_IGNORE)
		if original==null or not original.valid() or kept==null or removed==null or not Boundary.Diff.conserved(original.meshes[layer],kept,removed) or Boundary.Far.Indexed.triangles(removed)!=int(row.removed_faces):
			return 1
		if removed.get_surface_count()>0:
			var box := removed.get_aabb()
			var guard := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd").inspect_bounds(Rect2(box.position.x,box.position.z,box.size.x,box.size.z),game.entries)
			if guard.is_empty() or not guard.standalone_merge_allowed:
				return 1
		totals[row.configuration]=int(totals.get(row.configuration,0))+int(row.removed_faces)
	var file := FileAccess.open(directory.path_join("saved_audit.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":0,"checked_layers":seen.size(),"saved_meshes":seen.size()*2,"removed_faces":totals,"source_catalog_sha256":SOURCE_SHA,"report_sha256":FileAccess.get_sha256(directory.path_join("report.json")),"gameplay_overlap":0,"production_enabled":false}))
	file.close()
	print("[Northwest boundary saved audit] layers=",seen.size()," removed=",totals," fail=0")
	return 0


static func southwest(root: String, output: String, audit_only: bool) -> int:
	# 只扣R310新增21条，输入为R203已扣过旧69条的保留网格。
	if root.is_empty() or output.is_empty():
		return 1
	var plan_path := root.path_join("r310-transfer-plan.json")
	var proof_path := root.path_join("r203-boundary-c/report.json")
	if FileAccess.get_sha256(plan_path)!="9294ada7c0dcb5ad379cc073874acebd08989b1b519f13c0fad082847576855b" or FileAccess.get_sha256(proof_path)!="a140ace529731e8e210de0b695f3503e024b64b8ac76c4ca08682f6cf6f5edb9":
		return 1
	if (not audit_only and not Boundary.Far.Builder.valid_sample_output(root.path_join("r193-native-full-a"),output)) or (audit_only and FileAccess.file_exists(output.path_join("saved_audit.json"))):
		return 1
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	var proof: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(proof_path))
	var selected: Array = plan.rows.filter(func(row: Dictionary) -> bool: return row.previous_owner=="west_extension")
	if selected.size()!=1 or selected[0].records.size()!=21 or selected[0].ids.size()!=21:
		return 1
	var city_path := root.path_join("r133-west2-strokes-a/city.json")
	if FileAccess.get_sha256(city_path)!=selected[0].source_sha256:
		return 1
	var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(city_path))
	var seen: Dictionary = {}
	for record: Dictionary in selected[0].records:
		var matches: Array = city.buildings.filter(func(raw: Dictionary) -> bool: return raw.id==record.id)
		if matches.size()!=1 or matches[0]!=record or record.id not in selected[0].ids or seen.has(record.id) or proof.assigned.has(record.id):
			return 1
		seen[record.id]=true
	var game := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd").read_source()
	if game.is_empty():
		return 1
	var report := {"transfer_sha256":FileAccess.get_sha256(plan_path),"boundary_sha256":FileAccess.get_sha256(proof_path),"source_ids":seen.keys(),"rows":[],"failures":[],"production_enabled":false}
	var saved_report: Dictionary = {}
	if audit_only:
		saved_report=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("report.json")))
		if saved_report.get("transfer_sha256","")!=report.transfer_sha256 or saved_report.get("boundary_sha256","")!=report.boundary_sha256 or saved_report.get("failures",[1]).size()!=0 or saved_report.get("rows",[]).size()!=22:
			return 1
	else:
		if DirAccess.make_dir_recursive_absolute(output)!=OK:
			return 1
	for configuration: String in Boundary.Catalog.CONFIGURATIONS:
		var targets := Boundary.target_meshes(selected[0].records,configuration)
		for kind in 2:
			var entries: Array = proof.rows.filter(func(row: Dictionary) -> bool: return row.configuration==configuration and int(row.parent)==11 and int(row.layer)==kind)
			if entries.size()!=1 or FileAccess.get_sha256(entries[0].kept)!=entries[0].kept_sha256:
				return 1
			var original: ArrayMesh = ResourceLoader.load(entries[0].kept,"",ResourceLoader.CACHE_MODE_IGNORE)
			var target: ArrayMesh = targets[kind]
			if kind==0 and configuration in ["lod4_full","lod5_full"]:
				target=historical_target(root,configuration,target)
			var label := "%s_parent11_layer%d" % [configuration,kind]
			if target==null:
				report.failures.append(label+":historical_target")
				continue
			var result := Boundary.Diff.subtract(original,target)
			var roundtrips := 0
			while result.is_empty() and kind==0 and configuration not in ["lod4_full","lod5_full"] and roundtrips<2:
				target=decoded_roundtrip(target)
				roundtrips+=1
				result=Boundary.Diff.subtract(original,target)
			if result.is_empty() or not Boundary.Diff.conserved(original,result.mesh,target):
				report.failures.append({"label":label,"diagnosis":compare_positions(original,target)})
				continue
			if target.get_surface_count()>0:
				var box := target.get_aabb()
				var inspected := preload("res://scripts/tests/tokyo_region_gameplay_guard.gd").inspect_bounds(Rect2(box.position.x,box.position.z,box.size.x,box.size.z),game.entries)
				if inspected.is_empty() or not inspected.standalone_merge_allowed:
					return 1
			var kept_path := output.path_join(label+"_kept.res")
			var removed_path := output.path_join(label+"_removed.res")
			if audit_only:
				var rows: Array = saved_report.rows.filter(func(row: Dictionary) -> bool: return row.configuration==configuration and int(row.layer)==kind)
				if rows.size()!=1 or rows[0].original!=entries[0].kept or rows[0].original_sha256!=entries[0].kept_sha256 or FileAccess.get_sha256(kept_path)!=rows[0].kept_sha256 or FileAccess.get_sha256(removed_path)!=rows[0].removed_sha256 or rows[0].removed_faces!=result.removed:
					return 1
			else:
				if ResourceSaver.save(result.mesh,kept_path,ResourceSaver.FLAG_COMPRESS)!=OK or ResourceSaver.save(target,removed_path,ResourceSaver.FLAG_COMPRESS)!=OK:
					return 1
			var kept: ArrayMesh = ResourceLoader.load(kept_path,"",ResourceLoader.CACHE_MODE_IGNORE)
			var removed: ArrayMesh = ResourceLoader.load(removed_path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if not Boundary.Diff.conserved(original,kept,removed) or not Boundary.Diff.conserved(target,removed,ArrayMesh.new()):
				return 1
			report.rows.append({"configuration":configuration,"parent":11,"layer":kind,"original":entries[0].kept,"original_sha256":entries[0].kept_sha256,"kept":kept_path,"kept_sha256":FileAccess.get_sha256(kept_path),"removed":removed_path,"removed_sha256":FileAccess.get_sha256(removed_path),"removed_faces":result.removed,"roundtrips":roundtrips})
	var file := FileAccess.open(output.path_join("saved_audit.json" if audit_only else "report.json"),FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify(report))
	file.close()
	print("[Southwest historical transfer] audit=",audit_only," rows=",report.rows.size()," failures=",report.failures)
	return 0 if report.failures.is_empty() and report.rows.size()==22 else 1
