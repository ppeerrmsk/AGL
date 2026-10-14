extends RefCounted
## 有限已认证分页副清单；原目录/覆盖身份不变，不开放任意屋顶目录。
const Manifest := preload("res://scripts/rendering/tokyo_component_manifest.gd")
const CATALOG_SHA := "1599032b993a21cf1f733b39408a462f84ff0504664744cc92e0954e05344452"
const MANIFEST_SHA := "87355c28f7ffe23a60adcf1c00ab4c964df3f23ffe266ac864abef7d6a89de23"
const NORTH_CATALOG_SHA := "bccdd77db85e42d9ac258b9ca6497557fcb34b1e5ac3703fb805fd541099b827"
const NORTH_MANIFEST_SHA := "d635313648cf03e6f7a4d4d3a4f45987268313d8091610f8ed54536ad5b09142"
const NORTHWEST_CATALOG_SHA := "9a0985a329beffa9ec3188d2485d2102b0d2e50e2e37c35464fce07e21da551e"
const NORTHWEST_MANIFEST_SHA := "63b7f787083c6f82aefda3697fa1f24cd5fcb656025dd617754039606917f25e"
const COMBINED_CATALOG_SHA := "c85682837bb5dd4dff6b8bf4703430a86b6dc5be7875169ac19d70fa7ee61833"
const COMBINED_MANIFEST_SHA := "32a2b0c0da52ea023309b7a09e8b88b9d80fb166e06726395bc0436935bb21db"


static func paired_identity(catalog_sha: String, manifest_sha: String) -> bool:
	return (catalog_sha==CATALOG_SHA and manifest_sha==MANIFEST_SHA) \
		or (catalog_sha==NORTH_CATALOG_SHA and manifest_sha==NORTH_MANIFEST_SHA) \
		or (catalog_sha==NORTHWEST_CATALOG_SHA and manifest_sha==NORTHWEST_MANIFEST_SHA) \
		or (catalog_sha==COMBINED_CATALOG_SHA and manifest_sha==COMBINED_MANIFEST_SHA)


static func replace_row(original: Dictionary, proof: Dictionary, physical: Dictionary) -> Dictionary:
	if not original.get("mapping") is Array or original.mapping.size() != 3 or not original.get("components") is Dictionary:
		return {}
	if proof.get("canonical_identity") != original.get("canonical_identity") or proof.get("original_low") != original.get("mapping",[null])[0] \
			or not proof.get("component") is String or not proof.get("full_low_bounds") is AABB:
		return {}
	var path: String = proof.component
	if path.is_empty():
		return original if proof.get("wall_faces") == 0 else {}
	var descriptor: Variant = physical.get(path)
	if not descriptor is Dictionary or descriptor.get("path") != path or not descriptor.get("canonical_identity") is Dictionary \
			or descriptor.canonical_identity.get("format") != "tokyo_mesh_component" or descriptor.canonical_identity.get("schema") != 1 \
			or descriptor.canonical_identity.get("slots") != 2 or String(descriptor.canonical_identity.get("source","")).length() != 64 \
			or String(descriptor.get("sha256","")).length() != 64 or int(descriptor.get("bytes",-1)) < 0:
		return {}
	if int(proof.get("wall_faces",0)) <= 0 or int(proof.get("roof_faces",-1)) < 0 \
			or int(proof.get("full_low_faces",-1)) != int(proof.roof_faces)+int(proof.wall_faces):
		return {}
	var old_low: String = original.mapping[0][0]
	if proof.get("original_low_bytes") != original.components[old_low].bytes or proof.get("split_bytes") != descriptor.bytes:
		return {}
	var row := original.duplicate(true)
	row.mapping[0] = [path,0]
	row.components = {}
	for mapping: Array in row.mapping:
		row.components[mapping[0]] = descriptor if mapping[0] == path else original.components[mapping[0]]
	# 分槽可能重复少量共享顶点；流送必须以真实去重组件费用预约，不能沿用旧低层费用。
	row.bytes=0
	for component: Dictionary in row.components.values():
		row.bytes+=int(component.bytes)
	var paired_expected := original.duplicate(false)
	paired_expected.bytes=row.bytes
	if not Manifest.valid_row(row,paired_expected,row.components):
		return {}
	row["low_wall_slot"] = [path,1]
	row["low_full_bounds"] = proof.full_low_bounds
	row["low_full_faces"] = proof.full_low_faces
	return row


static func read(path: String, catalog_sha: String, pages: Dictionary) -> Dictionary:
	var north := catalog_sha == NORTH_CATALOG_SHA
	var northwest := catalog_sha in [NORTHWEST_CATALOG_SHA,COMBINED_CATALOG_SHA]
	if not paired_identity(catalog_sha,FileAccess.get_sha256(path)) or pages.is_empty():
		return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = file.get_var(false)
	var size := file.get_length()
	file.close()
	if not value is Dictionary or value.get("catalog_sha256") != catalog_sha or value.get("schema") != 1 \
			or not value.get("requires_atomic_wall_owner",false) or value.pages.size() != 231:
		return {}
	var result := pages.duplicate()
	var affected := 0
	for logical: String in value.pages:
		if not pages.has(logical):
			return {}
		var row := replace_row(pages[logical],value.pages[logical],value.physical)
		if row.is_empty():
			return {}
		result[logical] = row
		affected += int(row.has("low_wall_slot"))
	return {"pages":result,"metadata_bytes":size,"affected_pages":affected} if affected == (88 if north or northwest else 66) else {}
