extends RefCounted
## 全图清单沿既有批次入口消费；必须先通过完整家族和原生来源证明。
const Preview := preload("res://scripts/tests/tokyo_residential_preview.gd")


static func run(root: String, manifest_path: String, expected_sha: String) -> int:
	root=root.replace("\\","/").simplify_path().trim_suffix("/")
	if not root.is_absolute_path() or not root.ends_with("/tmp/tokyo-bay-volume") or expected_sha.length()!=64 or FileAccess.get_sha256(manifest_path)!=expected_sha:
		return 1
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var grid: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/maps/tokyo_bay_detail_tiles_full.json"))
	if not manifest is Dictionary or not manifest.get("jobs") is Array or manifest.jobs.is_empty() or not grid is Dictionary:
		return 1
	if manifest.get("grid_sha256")!=FileAccess.get_sha256("res://resources/maps/tokyo_bay_detail_tiles_full.json"):
		return 1
	var seams_path := root.path_join("r348-source-seams-a.json")
	if FileAccess.get_sha256(seams_path)!=manifest.get("seams_sha256"):
		return 1
	var seams: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(seams_path))
	if not seams.get("passed",false) or seams.get("tiles_checked")!=256 or not seams.get("conflicts",[1]).is_empty():
		return 1
	if FileAccess.get_sha256(root.path_join("r345-family-source-a/manifest.json"))!=seams.get("family_manifest_sha256"):
		return 1
	var accepted: Dictionary = {}
	for y in int(grid.grid.rows):
		for x in int(grid.grid.columns):
			accepted["detail_%02d_%02d" % [x,y]]=true
	var seen: Dictionary = {}
	for job: Dictionary in manifest.jobs:
		var name := str(job.get("tile",""))
		if not accepted.has(name) or seen.has(name):
			return 1
		seen[name]=true
		var family_path := root.path_join("r345-family-source-a/"+name+"/family-status.json")
		if FileAccess.get_sha256(family_path)!=job.get("family_sha256"):
			return 1
		var family: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(family_path))
		if not family.get("family_complete",false) or family.get("installed",true) or family.get("tile")!=name:
			return 1
		if FileAccess.get_sha256(root.path_join("r345-family-source-a/families.json"))!=family.get("family_manifest_sha256"):
			return 1
		var native := root.path_join(("r347-" if family.get("changed",true) else "r344-")+name+"-native-a")
		var proof_path := native.path_join("batch-status.json")
		if FileAccess.get_sha256(proof_path)!=job.get("proof_sha256"):
			return 1
		var proof: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(proof_path))
		if not proof.get("native_ready",false) or proof.get("installed",true) or proof.get("tile")!=name:
			return 1
		for file: String in ["index.res","native_costs.json","build_report.json"]:
			if FileAccess.get_sha256(native.path_join(file))!=proof.hashes.get(file):
				return 1
		var costs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(native.path_join("native_costs.json")))
		if costs.get("fail",1)!=0 or not costs.get("native_source_rebuild_ok",false):
			return 1
		if costs.get("source_sha256")!=family.hashes.city or costs.get("ground_sha256")!=family.hashes.ground:
			return 1
		var output := root.path_join("r345-"+name+"-layers-a")
		if DirAccess.dir_exists_absolute(output):
			var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("manifest.json")))
			if not saved is Dictionary or saved.get("index_sha256")!=proof.hashes["index.res"] or saved.get("layers",[]).size()!=3:
				return 1
			for layer: Dictionary in saved.layers:
				var file := str(layer.get("file",""))
				for field: String in ["sha256","mesh_sha256","attributes_sha256"]:
					var digest: Variant = layer.get(field)
					if not digest is String or digest.length()!=64 or not digest.is_valid_hex_number():
						return 1
				if file.is_empty() or file.get_file()!=file or FileAccess.get_sha256(output.path_join(file))!=layer.get("sha256"):
					return 1
				if FileAccess.get_sha256(output.path_join(file+".attributes"))!=layer.attributes_sha256 or FileAccess.get_sha256(output.path_join("layer_%d.res" % int(layer.layer)))!=layer.mesh_sha256:
					return 1
			continue
		var result := Preview.export_index(native.path_join("index.res"),proof.hashes["index.res"],int(costs.source_records),output)
		print("[Full tile layers] ",name," result=",result)
		if result!=0:
			return 1
	return 0
