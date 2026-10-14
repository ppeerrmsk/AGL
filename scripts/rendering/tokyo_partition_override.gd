extends RefCounted
## 已审计来源片替换：原目录不变，只改候选选择树，共用原stream与交接门。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Adapter := preload("res://scripts/rendering/tokyo_partition_catalog.gd")


static func json_binding(binding: Variant) -> Dictionary:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return {}
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	return value if value is Dictionary else {}


static func find(entries: Array, path: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.path==path: return entry
		var value := find(entry.children,path)
		if not value.is_empty(): return value
	return {}


static func identity_matches(actual: Dictionary, expected: Variant) -> bool:
	if not expected is Dictionary or expected.size()!=actual.size(): return false
	for key: String in actual:
		var value: Variant=actual[key]
		if value is int:
			if not Contract.integer(expected.get(key),-1) or int(expected[key])!=value: return false
		elif typeof(expected.get(key))!=typeof(value) or expected[key]!=value: return false
	return true


static func empty_game(entry: Dictionary, pages: Dictionary, coverage: Dictionary) -> bool:
	if not pages.has(entry.path) or not coverage.pages.has(entry.path): return false
	var row: Dictionary=coverage.pages[entry.path]
	if not pages[entry.path].game_sources.is_empty() or not row.tokens[0].is_empty() or not row.tokens[1].is_empty(): return false
	for child: Dictionary in entry.children:
		if not empty_game(child,pages,coverage): return false
	return true


static func read(value: Variant, catalog: Resource, catalog_sha: String, pages: Dictionary, coverage: Dictionary) -> Dictionary:
	if not value is Dictionary: return {}
	var input := json_binding(value.get("input"))
	var proof := json_binding(value.get("proof"))
	var trace := OS.get_environment("AGL_TOKYO_PARTITION_TRACE")=="1"
	if trace: print("[partition override] input=",not input.is_empty()," proof=",not proof.is_empty()," catalog=",proof.get("catalog_sha256")==catalog_sha)
	if input.is_empty() or proof.is_empty() or proof.get("input_sha256")!=value.input.sha256 \
		or proof.get("catalog_sha256")!=catalog_sha or not input.get("attachments") is Array or not proof.get("rows") is Array \
		or input.attachments.is_empty() or input.attachments.size()!=proof.rows.size(): return {}
	var result := {"roots":{},"pages":{}}
	var seen: Dictionary={}
	for n in input.attachments.size():
		var request: Variant=input.attachments[n]
		var evidence: Variant=proof.rows[n]
		if not request is Dictionary or not evidence is Dictionary or not request.get("partition") is Dictionary: return {}
		var binding: Dictionary=request.partition
		var configuration: Variant=request.get("configuration")
		if configuration not in ["lod4_full","lod5_full"] or binding.get("configuration")!=configuration \
			or evidence.get("configuration")!=configuration or evidence.get("original_layers_equal")!=[true,true,true] \
			or evidence.get("untouched_layers_equal")!=[true,true] or evidence.get("no_game_sources")!=true: return {}
		var path: Variant=evidence.get("target")
		if trace: print("[partition override] target=",path," exists=",pages.has(path)," identity=",identity_matches(pages.get(path,{}).get("canonical_identity",{}),evidence.get("identity")))
		if not path is String or seen.has(path) or not pages.has(path) or not identity_matches(pages[path].canonical_identity,evidence.get("identity")): return {}
		seen[path]=true
		var entry := find(catalog.configurations[configuration],path)
		if trace: print("[partition override] tree=",not entry.is_empty() and var_to_bytes(entry).hex_encode().sha256_text()==evidence.get("tree_sha256"))
		if entry.is_empty() or var_to_bytes(entry).hex_encode().sha256_text()!=evidence.get("tree_sha256") \
			or not empty_game(entry,pages,coverage[configuration]): return {}
		if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return {}
		var file := FileAccess.open(binding.path,FileAccess.READ)
		if file==null: return {}
		var partition: Variant=file.get_var(false)
		file.close()
		if not partition is Dictionary: return {}
		var normalized := Adapter.normalize(partition,binding)
		if trace: print("[partition override] normalized=",not normalized.is_empty())
		if normalized.is_empty(): return {}
		var roots: Array=result.roots.get(configuration,catalog.configurations[configuration])
		if find(roots,path).is_empty(): return {}
		result.roots[configuration]=Adapter.replace(roots,path,normalized.tree)
		for key: String in normalized.pages:
			if pages.has(key) or result.pages.has(key): return {}
			result.pages[key]=normalized.pages[key]
	return result
