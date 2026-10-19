extends RefCounted
## 已校验来源依赖的纯值适配；committed必须是实际提交身份，不是请求或缓存清单。
const Coverage := preload("res://scripts/experiments/tokyo_source_coverage.gd")


static func refinement_data(data: Dictionary, joined_pages: Array) -> Dictionary:
	# 输入必须来自已校验摘要的归并清单；逐面区间与既有认证依赖双向匹配。
	if data.get("schema")!=1 or not data.get("source_layers_complete",false): return {}
	var result := data.duplicate(true)
	result["pages"]={};result["coarse_to_fine"]={}
	var ranges: Dictionary={}
	for page: Dictionary in joined_pages:
		if not data.pages.has(page.path) or result.coarse_to_fine.has(page.path): return {}
		var certified: Dictionary=data.pages[page.path]
		if page.canonical_identity!=certified.identity or page.faces!=certified.faces or page.box!=certified.box: return {}
		var offset := 0
		var children: Array=[]
		for origin: Dictionary in page.origins:
			var part: Dictionary=origin.component
			if origin.first_face!=offset or int(origin.faces)<=0 or result.pages.has(part.path): return {}
			if origin.layer<0 or origin.layer>1 or not part.box is AABB: return {}
			if not part.canonical_identity is Dictionary or part.canonical_identity.is_empty(): return {}
			var token := "%s:%d:%d" % [page.path,offset,origin.faces]
			ranges[token]={"path":part.path,"identity":part.canonical_identity,"source":origin.source,"layer":origin.layer}
			result.pages[part.path]={"identity":part.canonical_identity,"box":part.box,"faces":origin.faces}
			children.append({"path":part.path,"identity":part.canonical_identity,"layer":origin.layer})
			offset+=int(origin.faces)
		if offset!=int(page.faces) or children.is_empty(): return {}
		result.coarse_to_fine[page.path]={"identity":certified.identity,"children":children}
	if result.coarse_to_fine.size()!=data.pages.size(): return {}
	for source: String in result.dependencies:
		for kind: int in result.dependencies[source]:
			var replacements: Array=[]
			for dependency: Dictionary in result.dependencies[source][kind]:
				var token := "%s:%d:%d" % [dependency.path,dependency.first_face,dependency.faces]
				if not ranges.has(token) or dependency.identity!=data.pages[dependency.path].identity: return {}
				var part: Dictionary=ranges[token]
				if part.source!=source or part.layer!=kind: return {}
				replacements.append({"path":part.path,"identity":part.identity})
				ranges.erase(token)
			result.dependencies[source][kind]=replacements
	return result if ranges.is_empty() else {}


static func refined_layers(data: Dictionary, committed: Dictionary, projection: Dictionary={}) -> Dictionary:
	if not data.get("coarse_to_fine") is Dictionary: return {}
	var pieces: Dictionary={}
	for path: String in committed:
		var actual: Variant=committed[path]
		if not actual is Dictionary or not actual.get("layers") is int or actual.layers<0 or actual.layers>3: return {}
		if data.coarse_to_fine.has(path):
			var group: Dictionary=data.coarse_to_fine[path]
			if actual.get("identity")!=group.identity: return {}
			for child: Dictionary in group.children:
				if (actual.layers&(1<<int(child.layer)))==0: continue
				if pieces.has(child.path): return {} # 同一片粗细同时提交不能算有效覆盖。
				pieces[child.path]={"identity":child.identity,"layers":1<<int(child.layer)}
		else:
			if pieces.has(path): return {}
			pieces[path]=actual
	return source_layers(data,pieces,projection)


static func source_layers(data: Dictionary, committed: Dictionary, projection: Dictionary={}) -> Dictionary:
	if data.get("schema")!=1 or not data.get("source_layers_complete",false): return {}
	if not data.get("pages") is Dictionary or not data.get("dependencies") is Dictionary: return {}
	var original: Variant=data.get("original_coverage")
	if not original is Dictionary or not original.get("pages") is Dictionary: return {}
	for path: String in committed:
		var page: Variant=data.pages.get(path)
		var actual: Variant=committed[path]
		if not page is Dictionary or not actual is Dictionary: return {}
		if not page.get("identity") is Dictionary or page.identity.is_empty() or actual.get("identity")!=page.identity: return {}
		if not actual.get("layers") is int or actual.layers<0 or actual.layers>7: return {}
	var result: Dictionary={}
	var invisible: Dictionary={}
	if not projection.is_empty():
		if not projection.get("view") is Rect2 or not projection.get("canvas") is Transform2D or not projection.get("size") is Vector2 or not projection.get("roof") is Vector2: return {}
		if not projection.view.has_area() or not projection.size.is_finite() or projection.size.x<=0 or projection.size.y<=0 or not projection.roof.is_finite(): return {}
	for source: String in data.dependencies:
		# 原无游戏楼的替换页没有覆盖凭据，不因新格合并而获得隐藏权限。
		if not original.pages.has(source): continue
		var layers := 0
		for kind: int in data.dependencies[source]:
			if kind<0 or kind>1: return {}
			var required: Variant=data.dependencies[source][kind]
			if not required is Array or required.is_empty(): return {}
			var complete := true
			for dependency: Dictionary in required:
				var page: Variant=data.pages.get(dependency.get("path",""))
				if not page is Dictionary or dependency.get("identity")!=page.get("identity"): return {}
				var actual: Dictionary=committed.get(dependency.path,{})
				if actual.is_empty() or (int(actual.layers)&(1<<kind))==0:
					# 屏外豁免必须从完整组件包络证明，不从请求/缓存或任意布尔标记推断。
					if projection.is_empty() or not page.get("box") is AABB:
						complete=false
						continue
					if not invisible.has(dependency.path):
						var bounds := preload("res://scripts/rendering/tokyo_cells_overlay.gd").projected_layer_bounds(page.box,projection.roof,Vector2.ZERO)
						invisible[dependency.path]=not preload("res://scripts/rendering/tokyo_cells_overlay.gd").intersects_view(bounds,projection.view,projection.canvas,projection.size)
					if not invisible[dependency.path]: complete=false
			if complete: layers|=1<<kind
		if layers: result[source]={"identity":original.pages[source].identity,"layers":layers}
	return result


static func covered_sources(data: Dictionary, committed: Dictionary, configuration: String, collision: String, catalog_sha: String, projection: Dictionary={}) -> PackedInt32Array:
	if data.get("configuration")!=configuration: return PackedInt32Array()
	return Coverage.covered_sources(data.get("original_coverage",{}),source_layers(data,committed,projection),configuration,collision,catalog_sha)
