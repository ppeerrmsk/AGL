extends RefCounted
## 纯值显示凭据；调用方只能传已原子提交且实际显示的页，不接受缓存/请求清单。


static func covered_sources(data: Dictionary, committed: Dictionary, configuration: String, collision: String, catalog_sha: String) -> PackedInt32Array:
	var empty := PackedInt32Array()
	if data.get("schema") != 1 or data.get("configuration") != configuration or data.get("collision_sha256") != collision \
			or data.get("catalog_sha256") != catalog_sha or not data.get("verified", false) \
			or not data.get("pages") is Dictionary or not data.get("sources") is Dictionary:
		return empty
	var leaves: Dictionary = {}
	var tokens: Dictionary = {}
	for path: String in committed:
		var row: Variant = data.pages.get(path)
		var bound: Variant = committed[path]
		if not row is Dictionary or not bound is Dictionary or not row.get("identity") is Dictionary \
				or row.identity.is_empty() or bound.get("identity") != row.identity \
				or not bound.get("layers") is int or bound.layers < 0 or bound.layers > 7:
			return empty
		for leaf: String in row.leaves:
			if leaves.has(leaf):
				return empty
			leaves[leaf] = true
		for kind in 2:
			if (int(bound.layers) & (1 << kind)) == 0:
				continue
			for token: String in row.tokens[kind]:
				tokens[token] = true
	var result := PackedInt32Array()
	for source: int in data.sources:
		var required: PackedStringArray = data.sources[source]
		var complete := not required.is_empty()
		for token: String in required:
			complete = complete and tokens.has(token)
		if complete:
			result.append(source)
	result.sort()
	return result
