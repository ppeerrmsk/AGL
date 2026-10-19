extends RefCounted
## 仅已独立复算选择的交互候选落盘；不授予完整目录或正式覆盖。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Baker := preload("res://scripts/tests/bake_tokyo_shared_roofs.gd")
const Audit := preload("res://scripts/tests/audit_tokyo_shared_roof_bundle.gd")


static func run(input: String, proof_path: String, proof_sha: String, output: String, saved: String = "") -> int:
	if not Root.binding_valid({"path":proof_path,"sha256":proof_sha}) or not output.is_absolute_path() or output.get_extension() != "res":
		return 1
	var proof: Variant = JSON.parse_string(FileAccess.get_file_as_string(proof_path))
	if not proof is Dictionary or not proof.get("passed",false) or not Root.binding_valid({"path":input,"sha256":proof.get("plan_sha256","")}):
		return 1
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(input))
	if not plan is Dictionary or not plan.get("partial",false) or not plan.get("passed",false) or not plan.get("source_order_independent",false):
		return 1
	if plan.get("grid") != 1.0/2048.0 or plan.get("max_displacement") != 0.001 or plan.get("expected",[]).size() != 189 or plan.get("meshes",[]).size() != 32 or plan.get("parents",[]).size() != 16:
		return 1
	if plan.get("game_source_sha256") != Root.Contract.GAME_SHA or plan.get("collision_sha256") != Root.Contract.COLLISION_SHA:
		return 1
	var scope: Dictionary = plan.get("interaction_scope",{})
	if scope.get("schema") != 1 or scope.get("selection_margin") != 0.003 or float(scope.get("max_coordinate",INF)) >= 8192.0:
		return 1
	if proof.get("full_input_sha256") != plan.get("source_sha256") or proof.get("selected_count") != plan.get("native_sources",[]).size() or not proof.get("float32_exact",false):
		return 1
	if not Root.binding_valid({"path":scope.get("source_path",""),"sha256":plan.source_sha256}):
		return 1
	if saved.is_empty():
		return Baker.run(input,output)
	if not saved.is_absolute_path() or FileAccess.file_exists(saved) or not FileAccess.file_exists(output):
		return 1
	return Audit.run(input,output,saved,true)
