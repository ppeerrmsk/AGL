extends RefCounted
## 完整规范配置的有限批次入口；复用既有共同屋面Baker与实际磁盘Audit。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Full := preload("res://scripts/rendering/tokyo_full_grid_contract.gd")
const Baker := preload("res://scripts/tests/bake_tokyo_shared_roofs.gd")
const Audit := preload("res://scripts/tests/audit_tokyo_shared_roof_bundle.gd")
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")


static func valid(plan: Dictionary) -> bool:
	var interaction := plan.has("interaction_scope")
	if interaction and not preload("res://scripts/tests/tokyo_interaction_certificate.gd").certified(plan):return false
	if not plan.get("passed",false) or not plan.get("camera_independent",false) \
			or not plan.get("source_order_independent",false) or plan.get("partial",false) \
			or (plan.get("grid")!=1.0/1024.0 and not interaction) or plan.get("collision_sha256")!=Full.COLLISION_SHA \
			or plan.get("game_source_sha256")!=Full.GAME_SHA or plan.get("configuration",{}).get("name") not in Catalog.CONFIGURATIONS \
			or plan.get("parents",[]).size()!=16 or plan.get("meshes",[]).size()!=32 or plan.get("expected",[]).size()!=189:
		return false
	var parents: Dictionary={}
	var meshes: Dictionary={}
	var identities: Dictionary={}
	var sources: Dictionary={}
	for row: Dictionary in plan.parents:
		var parent:=int(row.get("parent_id",-1))
		if parent<0 or parent>=16 or parent!=row.parent_id or parents.has(parent):return false
		parents[parent]=true
	for row: Dictionary in plan.meshes:
		var parent:=int(row.get("parent_id",-1))
		var kind:=int(row.get("kind",-1))
		var id:=int(row.get("id",-1))
		var pair:=Vector2i(parent,kind)
		if parent<0 or parent>=16 or parent!=row.parent_id or kind<0 or kind>1 or kind!=row.kind \
				or id<0 or id!=row.id or meshes.has(pair) or identities.has(id):return false
		meshes[pair]=true
		identities[id]=true
	for row: Dictionary in plan.expected:
		var id:=int(row.get("source_id",-1))
		if id<0 or id!=row.source_id or sources.has(id):return false
		sources[id]=true
	return parents.size()==16 and meshes.size()==32 and sources.size()==189


static func run(input: String, digest: String, output: String, saved_audit: String="") -> int:
	if not Root.binding_valid({"path":input,"sha256":digest}) or not output.is_absolute_path() or output.get_extension()!="res":
		return 1
	var plan: Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if not plan is Dictionary or not valid(plan):return 1
	if saved_audit.is_empty():
		return Baker.run(input,output)
	if not saved_audit.is_absolute_path() or FileAccess.file_exists(saved_audit) or not FileAccess.file_exists(output):return 1
	# Audit从保存后的bundle读取实际顶点；FULL_GRID自动启用全精度JSON输出。
	return Audit.run(input,output,saved_audit,true)
