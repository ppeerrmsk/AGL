extends RefCounted
## 增量边界制作：复用现有三层导出器，不伪造旧批次身份。
const Preview := preload("res://scripts/tests/tokyo_residential_preview.gd")


static func run(path: String, expected_sha: String) -> int:
	if expected_sha.length()!=64 or FileAccess.get_sha256(path)!=expected_sha: return 1
	var base := path.get_base_dir().replace("\\","/").simplify_path()
	if not base.is_absolute_path() or not base.ends_with("/tmp/tokyo-bay-volume"): return 1
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("tiles")!=31 or not data.get("rows") is Array or data.rows.size()!=31: return 1
	var seen: Dictionary={}
	var candidates:=OS.get_environment("AGL_TOKYO_BOUNDARY_EXPORT_CANDIDATES")=="1"
	for row: Dictionary in data.rows:
		var name: String=row.get("tile","")
		var parts:=name.split("_")
		if parts.size()!=3 or parts[0]!="detail" or not parts[1].is_valid_int() or not parts[2].is_valid_int(): return 1
		var x:=int(parts[1]);var y:=int(parts[2])
		if x<0 or x>=16 or y<0 or y>=16 or (x!=15 and y!=0) or name!="detail_%02d_%02d"%[x,y] or seen.has(name): return 1
		seen[name]=true
		if row.get("family_replay_verified")!=true or row.get("installed")!=false: return 1
		if FileAccess.get_sha256(base.path_join("m20-expanded-families.json"))!=row.get("family_sha256"): return 1
		var source: String=row.source
		if source.replace("\\","/").simplify_path()!=base.path_join("r400-"+name+"-source"): return 1
		for key: String in ["city","ground","audit","source_cache"]:
			if FileAccess.get_sha256(source.path_join(key+".json"))!=row.hashes.get(key): return 1
		var native:=base.path_join("r400-"+name+"-native")
		var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(native.path_join("batch-status.json")))
		if not proof is Dictionary or proof.get("native_ready")!=true or proof.get("input_hashes")!=row.hashes: return 1
		for key: String in ["index.res","native_costs.json","build_report.json"]:
			if FileAccess.get_sha256(native.path_join(key))!=proof.hashes.get(key): return 1
		var output:=base.path_join("r400-"+name+"-layers")
		if candidates:
			var candidate:=base.path_join("r402-"+name+"-blocks-native")
			var saved_proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(candidate.path_join("m20-proof.json")))
			var report: Variant=JSON.parse_string(FileAccess.get_file_as_string(candidate.path_join("candidate_report.json")))
			if not saved_proof is Dictionary or saved_proof.get("source_sha256")!=expected_sha or not report is Dictionary \
				or report.get("fail",1)!=0 or report.get("source_index_sha256")!=proof.hashes["index.res"] \
				or saved_proof.get("report_sha256")!=FileAccess.get_sha256(candidate.path_join("candidate_report.json")) \
				or saved_proof.get("audit_sha256")!=FileAccess.get_sha256(base.path_join("m20-block-audit-"+name+".json")): return 1
			for file: String in saved_proof.hashes:
				if FileAccess.get_sha256(candidate.path_join(file))!=saved_proof.hashes[file]: return 1
			native=candidate
			proof={"hashes":saved_proof.hashes}
			output=base.path_join("r404-"+name+"-massing-layers")
		if DirAccess.dir_exists_absolute(output):
			var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("manifest.json")))
			if not saved is Dictionary or saved.get("index_sha256")!=proof.hashes["index.res"] or saved.get("layers",[]).size()!=3: return 1
			for layer: Dictionary in saved.layers:
				if FileAccess.get_sha256(output.path_join(layer.file))!=layer.sha256 or FileAccess.get_sha256(output.path_join(layer.file+".attributes"))!=layer.attributes_sha256 \
					or FileAccess.get_sha256(output.path_join(String(layer.file).get_basename()+".res"))!=layer.mesh_sha256: return 1
		else:
			var result:=Preview.export_index(native.path_join("index.res"),proof.hashes["index.res"],int(row.records),output,3 if candidates else 5)
			if result!=0: return result
		print("[Boundary export] ",name," three source-bound layers saved")
	return 0
