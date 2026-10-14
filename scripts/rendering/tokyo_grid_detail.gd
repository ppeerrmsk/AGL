extends RefCounted
## 离线无损子块：只展开认证依赖，不按缓存就绪伪造来源覆盖。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")


static func expand(fine: Dictionary, coverage: Dictionary, data: Dictionary, binding: Dictionary) -> Dictionary:
	if data.get("schema")!=1 or data.get("grid")!=binding or data.get("grid_world")!=256.0 or not data.get("roundtrip_verified",false): return {}
	if not data.get("parents") is Dictionary or data.parents.is_empty() or data.parents.size()>4096: return {}
	var replacements: Dictionary={}
	var expanded := fine.duplicate(true)
	var all_paths: Dictionary={}
	for key: String in fine:
		for kind in 2:
			var children: Array=[]
			for original: Dictionary in fine[key][kind]:
				var path: String=original.components.keys()[0]
				if not data.parents.has(path): children.append(original);continue
				var parent: Dictionary=data.parents[path]
				if replacements.has(path) or parent.get("binding")!=original.components[path] or parent.get("faces")!=original.faces or parent.get("box")!=original.box or parent.get("layer")!=kind: return {}
				if not parent.get("children") is Array or parent.children.is_empty() or parent.children.size()>256: return {}
				var faces := 0
				var dependencies: Array=[]
				for child: Variant in parent.children:
					if not child is Dictionary or not Contract.binding(child.get("binding")) or not child.get("box") is AABB or not Contract.integer(child.get("faces"),1): return {}
					var part: Dictionary=child.binding
					if not part.get("canonical_identity") is Dictionary or not Contract.integer(part.get("bytes"),1): return {}
					var identity: Dictionary=part.canonical_identity
					if identity.get("format")!="tokyo_mesh_component" or identity.get("schema")!=1 or identity.get("slots")!=1 or not Contract.sha(identity.get("source")): return {}
					if all_paths.has(part.path) or coverage.pages.has(part.path) or not original.box.encloses(child.box): return {}
					all_paths[part.path]=true;faces+=int(child.faces)
					var view_identity: Dictionary=original.canonical_identity.duplicate(true)
					view_identity.component=identity.source
					children.append({"canonical_identity":view_identity,"components":{part.path:part},"bytes":part.bytes,"faces":child.faces,"box":child.box})
					dependencies.append({"path":part.path,"identity":identity,"layer":kind,"box":child.box,"faces":child.faces})
				if faces!=int(original.faces): return {}
				replacements[path]=dependencies
			expanded[key][kind]=children
	if replacements.size()!=data.parents.size(): return {}
	var result := coverage.duplicate(true)
	for source: String in result.dependencies:
		for kind: int in result.dependencies[source]:
			var values: Array=[]
			for dependency: Dictionary in result.dependencies[source][kind]:
				if replacements.has(dependency.path):
					for child: Dictionary in replacements[dependency.path]: values.append({"path":child.path,"identity":child.identity})
				else: values.append(dependency)
			result.dependencies[source][kind]=values
	for path: String in result.coarse_to_fine:
		var values: Array=[]
		for child: Dictionary in result.coarse_to_fine[path].children:
			values.append_array(replacements[child.path] if replacements.has(child.path) else [child])
		result.coarse_to_fine[path].children=values
	for path: String in replacements:
		result.coarse_to_fine[path]={"identity":result.pages[path].identity,"children":replacements[path]}
		result.pages.erase(path)
		for child: Dictionary in replacements[path]: result.pages[child.path]={"identity":child.identity,"faces":child.faces,"box":child.box}
	return {"fine":expanded,"coverage":result}
