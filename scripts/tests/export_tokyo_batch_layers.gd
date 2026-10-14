extends RefCounted
## 仅显式离线批次入口；失败不覆盖来源或既有导出。
const Preview := preload("res://scripts/tests/tokyo_residential_preview.gd")


static func run(root: String) -> int:
	if root.is_empty():
		return 1
	var full_manifest := OS.get_environment("AGL_TOKYO_BATCH_MANIFEST")
	if not full_manifest.is_empty():
		return preload("res://scripts/tests/export_tokyo_full_tile_layers.gd").run(root,full_manifest,OS.get_environment("AGL_TOKYO_BATCH_MANIFEST_SHA"))
	var path := root.path_join("r340-batch-a/progress.json")
	if FileAccess.get_sha256(path) != "c16f589ec0e11543c63240883f45608a46159217fde018e87ee8cd135067126c":
		return 1
	var progress: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not progress is Dictionary or not progress.get("rows") is Array or progress.rows.size() != 5:
		return 1
	var failed := 0
	for row: Dictionary in progress.rows:
		if row.get("native_ready") != true:
			continue
		if row.get("name") not in ["west", "northwest", "southwest", "south"]:
			return 1
		var source := root.path_join("r340-"+str(row.name)+"-native-a")
		if str(row.index).replace("\\", "/") != source.path_join("index.res").replace("\\", "/") or FileAccess.get_sha256(source.path_join("native_costs.json")) != row.report_sha256:
			return 1
		var output := root.path_join("r341-"+str(row.name)+"-layers-a")
		failed += Preview.export_index(source.path_join("index.res"),row.index_sha256,int(row.source_records),output)
		print("[Batch layers] ",row.name," cumulative_fail=",failed)
	return 1 if failed else 0
