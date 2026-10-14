extends RefCounted
## 全图清单共用既有矩阵/逐格保存工序；不会自动启用生产目录。
const Layers := preload("res://scripts/tests/export_tokyo_full_tile_layers.gd")
const Common := preload("res://scripts/tests/build_tokyo_batch_blocks.gd")


static func run(root: String, manifest_path: String, manifest_sha: String, audit_path: String, audit_sha: String) -> int:
	if root.is_empty() or manifest_sha.length()!=64 or audit_sha.length()!=64 or FileAccess.get_sha256(audit_path)!=audit_sha:
		return 1
	if Layers.run(root,manifest_path,manifest_sha)!=0:
		return 1
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(audit_path))
	if audit.get("job_manifest_sha256")!=manifest_sha or audit.get("rows",[]).size()!=manifest.jobs.size():
		return 1
	var by_name: Dictionary = {}
	for row: Dictionary in audit.rows:
		var name := str(row.get("name",""))
		if name.is_empty() or by_name.has(name):
			return 1
		by_name[name]=row
	var failures := 0
	for job: Dictionary in manifest.jobs:
		var name := str(job.tile)
		if not by_name.has(name):
			return 1
		var row: Dictionary = by_name[name]
		var plan_path := root.path_join("r346-"+name+"-blocks-a/plan.json")
		var selection_path := root.path_join("r346-"+name+"-blocks-a/selection.json")
		if FileAccess.get_sha256(plan_path)!=row.get("plan_sha256") or FileAccess.get_sha256(selection_path)!=row.get("selection_sha256"):
			return 1
		var family: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("r345-family-source-a/"+name+"/family-status.json")))
		var native := root.path_join(("r347-" if family.changed else "r344-")+name+"-native-a")
		var source := native.path_join("index.res")
		var costs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(native.path_join("native_costs.json")))
		var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
		if plan.get("index_sha256")!=FileAccess.get_sha256(source) or plan.get("source_manifest_sha256")!=FileAccess.get_sha256(root.path_join("r345-"+name+"-layers-a/manifest.json")):
			return 1
		var output := root.path_join("r349-"+name+"-blocks-native-a")
		var result := Common.build_paths(source,plan_path,selection_path,output,int(costs.source_records),row)
		failures+=int(result!=0)
		print("[Full tile blocks] ",name," result=",result)
	return 1 if failures else 0
