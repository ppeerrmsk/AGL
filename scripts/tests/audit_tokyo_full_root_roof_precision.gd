extends RefCounted
## 单根float32屋面修正的实际保存/独立审计探针；绝不冒充16根规范计划。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Baker := preload("res://scripts/tests/bake_tokyo_shared_roofs.gd")
const Audit := preload("res://scripts/tests/audit_tokyo_shared_roof_bundle.gd")


static func run(input: String, digest: String, output: String, audit_only: bool) -> int:
	if not Root.binding_valid({"path":input,"sha256":digest}) or not output.is_absolute_path() \
			or output.get_base_dir()!=input.get_base_dir():
		return 1
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(input))
	if not plan is Dictionary or not plan.get("partial",false) or not plan.get("passed",false) \
			or plan.get("grid")!=1.0/1024.0 or plan.get("max_displacement")!=0.001 or plan.get("expected",[]).size()!=189 \
			or plan.get("collision_sha256")!=Root.Contract.COLLISION_SHA or plan.get("production_enabled",true):
		return 1
	return Audit.run(input,output,output.get_basename()+"_saved_roofs_full_precision.json",true) if audit_only else Baker.run(input,output)
