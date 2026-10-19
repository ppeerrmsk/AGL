extends RefCounted
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")


static func run(path: String, expected_sha: String, output: String) -> int:
	if not Contract.sha(expected_sha) or FileAccess.get_sha256(path)!=expected_sha or not output.is_absolute_path() or FileAccess.file_exists(output): return 1
	var input: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not input is Array or input.is_empty(): return 1
	var results: Array = []
	var native: RefCounted
	var native_binding: Dictionary = {}
	for binding: Variant in input:
		if not Contract.binding(binding): return 1
		var refinement: RefCounted
		var refinement_depth := int(binding.get("refinement_depth",0))
		if refinement_depth not in [0,1,2,3,4] or (refinement_depth>0 and not binding.get("native_only",false)): return 1
		if refinement_depth>0:
			refinement=preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
			refinement.branching=int(binding.get("refinement_branching",4))
			refinement.diagnostic_cap=int(binding.get("refinement_cap",16))
		if binding.has("native") and binding.native!=native_binding:
			if not binding.native is Dictionary: return 1
			native=preload("res://scripts/rendering/tokyo_hlod_native.gd").new()
			if not native.read(binding.native): return 1
			native_binding=binding.native
		if binding.get("native_only",false) and (not binding.has("native") or native==null): return 1
		var started := Time.get_ticks_usec()
		var catalog := Contract.read(binding.path,binding.sha256)
		if catalog.is_empty():
			var rejected: Variant = JSON.parse_string(FileAccess.get_file_as_string(binding.path))
			if rejected is Dictionary and rejected.get("rows") is Array:
				for row: Variant in rejected.rows:
					if not Contract.row_valid(row):
						print("[HLOD manifest audit] first invalid row depth=",row.get("depth")," id=",row.get("id")," texture_valid=",Contract.texture_valid(row))
						break
			push_error("HLOD native manifest rejected: "+String(binding.path))
			return 1
		var roots := PackedStringArray()
		for id_value in 16: roots.append("0:%d" % id_value)
		results.append({"identity":catalog.identity,"rows":catalog.rows.size(),"sources":catalog.source_count,"geometry_resources":catalog.geometry.size(),
			"texture_resources":catalog.textures.size(),"read_usec":Time.get_ticks_usec()-started,"whole_root_charge":Contract.charges(catalog,roots),
			"formal_runtime_coverage_verified":false,"runtime_integrated":false})
		results[-1]["mode"]="native_only" if binding.get("native_only",false) else "hlod_with_optional_native"
		if binding.has("poses"):
			if not Contract.binding(binding.poses) or FileAccess.get_sha256(binding.poses.path)!=binding.poses.sha256: return 1
			var pose_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(binding.poses.path))
			if not pose_data is Dictionary or not pose_data.get("poses") is Array: return 1
			var poses: Array = []
			var passed := 0
			var hybrid_passed := 0
			for pose: Dictionary in pose_data.poses:
				if not Contract.numbers(pose.get("center"),2): return 1
				var query: Dictionary = native.select(Vector2(pose.center[0],pose.center[1]),float(pose.scale),float(pose.rotation),Vector2(1600,900),String(binding.get("native_configuration",""))) \
					if binding.get("native_only",false) else Contract.select(catalog,Vector2(pose.center[0],pose.center[1]),float(pose.scale),float(pose.rotation))
				if query.is_empty(): return 1
				if refinement!=null:
					query=refinement.select(native,Vector2(pose.center[0],pose.center[1]),float(pose.scale),float(pose.rotation),Vector2(1600,900),String(binding.get("native_configuration","")),refinement_depth)
					if query.is_empty(): return 1
				var layer_faces := [0,0,0]
				var native_pages: Array = []
				# HLOD与原生切面的entries结构不同，只解析原生三层描述。
				if binding.get("native_only",false):
					for entry: Dictionary in query.entries:
						for kind in 3:
							if entry.mask[kind]: layer_faces[kind]+=int(entry.triangles[kind])
						native_pages.append({"path":entry.path,"triangles":entry.triangles,"mask":entry.mask,
							"boxes":str(entry.boxes)})
				poses.append({"center":pose.center,"scale":pose.scale,"rotation":pose.rotation,"active":query.active,
					"faces":query.triangles,"layer_faces":layer_faces,"native_pages":native_pages,"configuration":query.get("configuration","hlod"),
					"bytes":query.bytes,"charges":query.charges,"keys":query.keys,
					"within_budget":query.within_budget,"solver_usec":query.solver_usec})
				if refinement!=null: poses[-1]["refinement"]=query.refinement
				if binding.has("export_directory") and poses.size()==1:
					if refinement!=null or not binding.get("native_only",false): return 1
					var exported:=preload("res://scripts/tests/tokyo_native_refinement_probe.gd").export_cut(native,query,str(binding.export_directory))
					if exported.is_empty(): return 1
					poses[-1]["exported"]=exported
				passed+=int(query.within_budget)
				var hybrid_ok: bool = query.within_budget
				if not hybrid_ok and binding.has("native") and native!=null and float(pose.scale)>0.1944:
					var fallback: Dictionary = native.select(Vector2(pose.center[0],pose.center[1]),float(pose.scale),float(pose.rotation),Vector2(1600,900))
					hybrid_ok=not fallback.is_empty() and fallback.within_budget
					poses[-1]["native_fallback"]={"within_budget":hybrid_ok,"faces":fallback.get("triangles",-1),"charges":fallback.get("charges",{})}
				poses[-1]["hybrid_within_budget"]=hybrid_ok
				hybrid_passed+=int(hybrid_ok)
			results[-1]["poses"]=poses
			results[-1]["passing"]=passed
			results[-1]["pose_count"]=poses.size()
			results[-1]["hybrid_passing"]=hybrid_passed
			print("[HLOD existing runtime cut] budget=",passed,"/",poses.size())
			if binding.has("native"): print("[HLOD plus native cut] budget=",hybrid_passed,"/",poses.size())
		print("[HLOD manifest audit] accepted=",results.size()," pages=",catalog.rows.size()," sources=",catalog.source_count)
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"input_sha256":expected_sha,"rows":results,"accepted":true,"gpu_assets_loaded":false},"\t"));file.close()
	return 0
