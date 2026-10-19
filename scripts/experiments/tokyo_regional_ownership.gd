extends RefCounted
## 离线来源门：只接受经摘要绑定的联合专用数据；不负责运行时配对加载。


static func validate(data: Dictionary, original: Dictionary, registry: Dictionary, region: String, digest: String) -> Dictionary:
	var metadata: Dictionary = data.get("regional_ownership", {})
	# JSON将数值解析为float；Dictionary整体相等会区分1与1.0，仅版本号显式数值比较。
	if region.is_empty() or digest.length() != 64 or metadata.size() != 4 \
			or typeof(metadata.get("schema_version")) not in [TYPE_INT, TYPE_FLOAT] \
			or float(metadata.get("schema_version", -1)) != 1.0 or metadata.get("joined_only") != true \
			or metadata.get("region_id") != region or metadata.get("registry_sha256") != digest:
		return {}
	if typeof(registry.get("schema_version")) not in [TYPE_INT, TYPE_FLOAT] \
			or float(registry.get("schema_version", -1)) != 1.0 or not registry.get("joined_only", false) \
			or not registry.get("regions", []).has(region) or not registry.get("assignments", {}) is Dictionary:
		return {}
	var restored := data.duplicate()
	restored.erase("regional_ownership")
	restored.erase("buildings")
	var original_header := original.duplicate()
	original_header.erase("buildings")
	if restored != original_header or data.get("buildings", []).size() != original.get("buildings", []).size():
		return {}
	var skipped := PackedStringArray()
	var seen: Dictionary = {}
	for i in data.buildings.size():
		var raw: Dictionary = data.buildings[i]
		var identity := String(raw.get("id", ""))
		var record := raw.duplicate()
		record.erase("regional_draw_owner")
		if identity.is_empty() or seen.has(identity) or record != original.buildings[i]:
			return {}
		seen[identity] = true
		var assignment: Dictionary = registry.assignments.get(identity, {})
		var owner := String(assignment.get("owner", ""))
		var copies: Array = assignment.get("regions", [])
		if owner.is_empty() or not copies.has(region) or not copies.has(owner) \
				or not registry.regions.has(owner) or String(raw.get("regional_draw_owner", "")) != owner:
			return {}
		if owner != region:
			skipped.append(identity)
	# 相同来源集合必须完整；防止清单声称本区还有楼、实际准备包却遗漏。
	for identity: String in registry.assignments:
		if registry.assignments[identity].regions.has(region) and not seen.has(identity):
			return {}
	skipped.sort()
	return {"region": region, "registry_hash": digest, "nonowner_ids": skipped}
