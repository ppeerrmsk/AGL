extends RefCounted
## 边界块面七档复用已验收的保存器，不重开美术参数。
const Blocks := preload("res://scripts/tests/build_tokyo_batch_blocks.gd")


static func run(source_path: String, source_sha: String, audit_path: String, audit_sha: String, tile: String) -> int:
	if source_sha.length()!=64 or audit_sha.length()!=64 or FileAccess.get_sha256(source_path)!=source_sha \
		or FileAccess.get_sha256(audit_path)!=audit_sha: return 1
	var base:=source_path.get_base_dir().replace("\\","/").simplify_path()
	if not base.is_absolute_path() or not base.ends_with("/tmp/tokyo-bay-volume"): return 1
	var sources: Variant=JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var audits: Variant=JSON.parse_string(FileAccess.get_file_as_string(audit_path))
	if not sources is Dictionary or sources.get("tiles")!=31 or not audits is Dictionary \
		or audits.get("job_manifest_sha256")!=source_sha: return 1
	var source_rows: Array=sources.rows.filter(func(r: Dictionary) -> bool: return r.tile==tile)
	var audit_rows: Array=audits.rows.filter(func(r: Dictionary) -> bool: return r.name==tile)
	if source_rows.size()!=1 or audit_rows.size()!=1: return 1
	var source: Dictionary=source_rows[0]
	var audit: Dictionary=audit_rows[0]
	var native:=base.path_join("r400-"+tile+"-native")
	var plan:=base.path_join("r401-"+tile+"-blocks/plan.json")
	var selection:=base.path_join("r401-"+tile+"-blocks/selection.json")
	var proof: Variant=JSON.parse_string(FileAccess.get_file_as_string(native.path_join("batch-status.json")))
	if not proof is Dictionary or proof.get("native_ready")!=true or proof.get("input_hashes")!=source.hashes \
		or FileAccess.get_sha256(native.path_join("index.res"))!=proof.hashes["index.res"] \
		or FileAccess.get_sha256(plan)!=audit.plan_sha256 or FileAccess.get_sha256(selection)!=audit.selection_sha256: return 1
	for field: String in ["city","ground","audit","source_cache"]:
		if FileAccess.get_sha256(String(source.source).path_join(field+".json"))!=source.hashes[field]: return 1
	return Blocks.build_paths(native.path_join("index.res"),plan,selection,base.path_join("r402-"+tile+"-blocks-native"),int(source.records),audit)
