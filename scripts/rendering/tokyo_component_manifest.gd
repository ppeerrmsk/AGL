extends RefCounted
## 只加载值元数据；逻辑几何身份继续由原规范目录/coverage约束。
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")


static func read(path: String, catalog: Resource, catalog_sha: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = file.get_var(false)
	var size := file.get_length()
	file.close()
	if not value is Dictionary or value.get("schema") not in [1,2] or value.get("catalog_sha256") != catalog_sha \
			or not value.get("pages") is Dictionary or not value.get("physical") is Dictionary:
		return {}
	var configurations := PackedStringArray(["lod2_full","lod2_guarded"])
	if value.schema == 2:
		if not value.get("configurations") is PackedStringArray:
			return {}
		configurations = value.configurations
	if not complete_coverage(value.pages,catalog.descriptors,configurations,catalog.pages_per_configuration()):
		return {}
	for key: String in value.physical:
		var item: Variant = value.physical[key]
		if not item is Dictionary or item.get("path") != key or not item.get("canonical_identity") is Dictionary:
			return {}
		var identity: Dictionary = item.canonical_identity
		if identity.get("format") != "tokyo_mesh_component" or identity.get("schema") != 1 \
				or int(identity.get("slots", 0)) not in [1, 2] or String(identity.get("source", "")).length() != 64 \
				or int(item.get("bytes", -1)) < 0:
			return {}
	var used: Dictionary = {}
	for logical: String in value.pages:
		if not valid_row(value.pages[logical], catalog.descriptors.get(logical, {}), value.physical):
			return {}
		# 双槽低墙仅由精确认证副清单派生，旧磁盘schema不能自行注入显示分层。
		if value.pages[logical].has("low_wall_slot"):
			return {}
		for key: String in value.pages[logical].components:
			used[key] = true
	if used.size() != value.physical.size():
		return {}
	return {"pages": value.pages, "metadata_bytes": size}


static func valid_row(row: Variant, expected: Dictionary, physical: Dictionary) -> bool:
	if not row is Dictionary or expected.is_empty() or row.get("canonical_identity") != expected.get("canonical_identity") \
			or row.get("bytes") != expected.get("bytes") or not row.get("components") is Dictionary \
			or row.components.size() < 1 or row.components.size() > 3 or not row.get("mapping") is Array or row.mapping.size() != 3 \
			or not row.get("game_sources") is PackedInt32Array or int(row.get("triangles", -1)) < 0:
		return false
	var identity: Dictionary = row.canonical_identity
	if identity.get("configuration") not in Catalog.CONFIGURATIONS \
			or var_to_bytes(row.game_sources).hex_encode().sha256_text() != identity.game_sources:
		return false
	var total := 0
	var used: Dictionary = {}
	for key: String in row.components:
		if not physical.has(key) or row.components[key] != physical[key]:
			return false
		total += int(physical[key].bytes)
	for mapping: Variant in row.mapping:
		if not mapping is Array or mapping.size() != 2 or not mapping[0] is String or not mapping[1] is int \
				or not row.components.has(mapping[0]) or mapping[1] < 0 or mapping[1] >= int(row.components[mapping[0]].canonical_identity.slots):
			return false
		used[mapping[0]] = true
	return total == int(row.bytes) and used.size() == row.components.size()


static func complete_coverage(pages: Dictionary, descriptors: Dictionary, configurations: PackedStringArray, page_count: int = 208) -> bool:
	if page_count not in [208,4432] or configurations.is_empty() or pages.size() != configurations.size() * page_count:
		return false
	var selected: Dictionary = {}
	for configuration: String in configurations:
		if configuration not in Catalog.CONFIGURATIONS or selected.has(configuration):
			return false
		selected[configuration] = true
	var expected := 0
	for path: String in descriptors:
		if descriptors[path].get("canonical_identity",{}).get("configuration","") in selected:
			expected += 1
			if not pages.has(path):
				return false
	return expected == pages.size()
