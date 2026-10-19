extends RefCounted
## 仅在新候选初始化阶段接入独立地表；不改变正在显示的视图身份。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")

static func attach(pages: Dictionary, hybrid: Array[Dictionary], native: Array[Dictionary], binding: Dictionary) -> Dictionary:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return {}
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not data is Dictionary or not data.get("rows") is Array or data.rows.is_empty(): return {}
	var replacements := {}
	for item: Dictionary in data.rows:
		var key: String=item.get("page","")
		if not pages.has(key) or replacements.has(key) or not item.get("roundtrip_verified",false): return {}
		var original: Dictionary=pages[key]
		if not original.has("mapping") or original.mapping.size()!=3: return {}
		var source: Dictionary=item.source
		if original.mapping[2]!=[source.path,int(item.slot)] or not original.components.has(source.path): return {}
		var old: Dictionary=original.components[source.path]
		if old.sha256!=source.sha256 or int(old.bytes)!=int(source.bytes): return {}
		var part: Dictionary=item.binding.duplicate(true)
		if not Contract.binding(part) or not Contract.integer(part.get("bytes"),1) or not Contract.integer(item.get("faces"),0): return {}
		part.bytes=int(part.bytes)
		if not part.get("canonical_identity") is Dictionary: return {}
		for field: String in ["schema","slots"]: part.canonical_identity[field]=int(part.canonical_identity.get(field,-1))
		if part.canonical_identity.get("format")!="tokyo_mesh_component" or part.canonical_identity.slots!=1 or part.canonical_identity.schema!=1: return {}
		replacements[key]={"canonical_identity":{"format":"tokyo_ground_view","schema":1,"source":binding.sha256,"parent":key},"components":{part.path:part},"mask":[false,false,true],"bytes":part.bytes,"faces":int(item.faces)}
	var found := {}
	var result_hybrid: Array[Dictionary]=[]
	var result_native: Array[Dictionary]=[]
	for root: Dictionary in hybrid:
		var next := rewrite(root,replacements,found)
		if next.is_empty(): return {}
		result_hybrid.append(next)
	for root: Dictionary in native:
		var next := rewrite(root,replacements,found)
		if next.is_empty(): return {}
		result_native.append(next)
	if found.size()!=replacements.size(): return {}
	var result_pages := pages.duplicate()
	result_pages.merge(replacements,true)
	return {"pages":result_pages,"hybrid":result_hybrid,"native":result_native}

static func rewrite(entry: Dictionary, rows: Dictionary, found: Dictionary) -> Dictionary:
	var result := entry.duplicate()
	if rows.has(entry.path):
		if entry.triangles[0]!=0 or entry.triangles[1]!=0 or entry.triangles[2]!=rows[entry.path].faces or entry.has("ground_replacement") or entry.has("ground_surfaces"): return {}
		result.bytes=rows[entry.path].bytes;found[entry.path]=true
	if entry.has("children"):
		var children: Array[Dictionary]=[]
		for child: Dictionary in entry.children:
			var next := rewrite(child,rows,found)
			if next.is_empty(): return {}
			children.append(next)
		result.children=children
	return result
