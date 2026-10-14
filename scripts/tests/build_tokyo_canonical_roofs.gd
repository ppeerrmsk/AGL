extends RefCounted
## 规范父包独立制作/审计入口；不启动地图渲染器或流送器。
const Baker := preload("res://scripts/tests/bake_tokyo_shared_roofs.gd")
const Audit := preload("res://scripts/tests/audit_tokyo_shared_roof_bundle.gd")


static func run(source_directory: String, destination: String, audit_only: bool) -> int:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_directory.path_join("manifest.json")))
	if not manifest.get("passed", false) or manifest.configurations.size() != 11:
		return 1
	if not audit_only:
		if DirAccess.dir_exists_absolute(destination):
			push_error("Canonical native build refuses existing output directory")
			return 1
		DirAccess.make_dir_recursive_absolute(destination)
	var rows: Array = []
	var failures := 0
	for entry: Dictionary in manifest.configurations:
		var source_path: String = source_directory.path_join(entry.file)
		if not entry.passed or FileAccess.get_sha256(source_path) != str(entry.sha256):
			return 1
		var bundle_path: String = destination.path_join(str(entry.name) + ".res")
		var failure := Audit.run(source_path, bundle_path, destination.path_join(str(entry.name) + "_saved_roofs.json")) if audit_only else Baker.run(source_path, bundle_path)
		failures += failure
		rows.append({"name": entry.name, "fail": failure, "plan_sha256": entry.sha256,
			"bundle_sha256": FileAccess.get_sha256(bundle_path) if FileAccess.file_exists(bundle_path) else ""})
	var path := destination.path_join("audit_manifest.json" if audit_only else "build_manifest.json")
	if FileAccess.file_exists(path):
		return 1
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "fail": failures, "production_enabled": false}))
	file.close()
	print("[Tokyo canonical native] audit=", audit_only, " configurations=", rows.size(), " fail=", failures)
	return failures
