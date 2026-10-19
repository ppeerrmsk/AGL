extends RefCounted
## 输入范围升级仅改变认证元数据；原候选几何、来源和全部值必须可逆相等。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")


static func matches(plan: Dictionary, candidate: Dictionary, proof: Dictionary) -> bool:
	var scope: Variant = plan.get("interaction_scope")
	if not scope is Dictionary or scope.get("schema") != 1 or scope.get("selection_margin") != 0.003:
		return false
	var certificate: Variant = scope.get("certification")
	if not certificate is Dictionary or certificate.size() != 2 or not certificate.get("candidate") is Dictionary or not certificate.get("selection") is Dictionary:
		return false
	var limit := float(scope.get("max_coordinate",INF))
	if not is_finite(limit) or limit <= 0.0 or limit >= 8192.0 or plan.get("grid") != 1.0/2048.0 or plan.get("partial",true):
		return false
	if not proof.get("passed",false) or not proof.get("float32_exact",false) or not candidate.get("partial",false) or not candidate.get("passed",false):
		return false
	if proof.get("plan_sha256") != certificate.candidate.get("sha256") or proof.get("full_input_sha256") != plan.get("source_sha256"):
		return false
	if proof.get("selected_count") != plan.get("native_sources",[]).size() or proof.get("full_native_count") != scope.get("full_native_count"):
		return false
	var restored := plan.duplicate(true)
	restored.partial = true
	restored.interaction_scope.erase("certification")
	return restored == candidate


static func certified(plan: Dictionary) -> bool:
	var scope: Variant = plan.get("interaction_scope")
	if not scope is Dictionary or not scope.get("certification") is Dictionary:
		return false
	var certificate: Dictionary = scope.certification
	if not Root.binding_valid(certificate.get("candidate")) or not Root.binding_valid(certificate.get("selection")):
		return false
	var candidate: Variant = JSON.parse_string(FileAccess.get_file_as_string(certificate.candidate.path))
	var proof: Variant = JSON.parse_string(FileAccess.get_file_as_string(certificate.selection.path))
	return candidate is Dictionary and proof is Dictionary and matches(plan,candidate,proof)


static func checks() -> bool:
	var candidate := {"partial":true,"passed":true,"grid":1.0/2048.0,"source_sha256":"a".repeat(64),"native_sources":[{"triangle":7}],
		"interaction_scope":{"schema":1,"selection_margin":0.003,"max_coordinate":7500.0,"full_native_count":100}}
	var plan := candidate.duplicate(true)
	plan.partial = false
	plan.interaction_scope.certification = {"candidate":{"sha256":"b".repeat(64)},"selection":{}}
	var proof := {"passed":true,"float32_exact":true,"plan_sha256":"b".repeat(64),"full_input_sha256":"a".repeat(64),"selected_count":1,"full_native_count":100}
	if not matches(plan,candidate,proof) or certified(plan):
		return false
	var broken := plan.duplicate(true)
	broken.native_sources[0].triangle = 8
	if matches(broken,candidate,proof):return false
	broken = plan.duplicate(true)
	broken.interaction_scope.max_coordinate = 8192.0
	if matches(broken,candidate,proof):return false
	proof.float32_exact = false
	return not matches(plan,candidate,proof)
