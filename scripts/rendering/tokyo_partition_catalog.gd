extends RefCounted
## 新分区只规范身份、完整树与费用；不把包围盒当作来源覆盖证明。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")


static func normalize(data: Dictionary, binding: Dictionary) -> Dictionary:
	if not Contract.binding(binding) or binding.get("configuration") not in ["lod4_full","lod5_full"]: return {}
	if data.get("schema") not in [2,3] or not Contract.sha(data.get("input_sha256")) \
		or not data.get("pages") is Dictionary or not data.get("tree") is Dictionary: return {}
	var result := {"pages":{},"keys":{},"configuration":binding.configuration,"coverage_verified":false}
	var tree := node(data.tree,data.pages,binding,data.input_sha256,result,0,data.schema==3)
	if tree.is_empty() or result.pages.size()!=data.pages.size(): return {}
	result["tree"]=tree
	return result


static func replace(entries: Array, target: String, replacement: Dictionary) -> Array[Dictionary]:
	# 只复制树元数据；旧目录不变，原父表示仍可由选择器使用。
	var result: Array[Dictionary]=[]
	for entry: Dictionary in entries:
		if entry.path==target:
			result.append(replacement)
		else:
			var copy := entry.duplicate()
			copy.children=replace(entry.children,target,replacement)
			result.append(copy)
	return result


static func node(entry: Dictionary, pages: Dictionary, binding: Dictionary, source: String, result: Dictionary, depth: int, packed: bool = false) -> Dictionary:
	if depth>16 or not entry.get("path") is String or entry.path.is_empty() or result.keys.has(entry.path): return {}
	if not pages.get(entry.path) is Dictionary or not entry.get("children") is Array or entry.children.size() not in [0,2]: return {}
	if not entry.get("boxes") is Array or entry.boxes.size()!=3 or not entry.get("triangles") is Array or entry.triangles.size()!=3: return {}
	if not entry.get("bytes") is int or entry.bytes<0: return {}
	var row: Dictionary=pages[entry.path]
	if not row.get("layers") is Array or row.layers.size()!=3 or row.get("bytes")!=entry.bytes: return {}
	var parts: Dictionary={}
	var mapping: Array=[]
	var total := 0
	if row.has("bundle")!=packed: return {}
	if packed:
		var part := preload("res://scripts/rendering/tokyo_partition_bundle.gd").descriptor(row,entry)
		if part.is_empty(): return {}
		parts[part.path]=part
		for kind in 3: mapping.append([part.path,kind])
		total=part.bytes
	for kind in 3:
		if packed: break
		var layer: Variant=row.layers[kind]
		if not layer is Dictionary or not Contract.binding(layer) or parts.has(layer.path): return {}
		if not layer.get("bytes") is int or layer.bytes<0 or not layer.get("faces") is int or layer.faces<0: return {}
		if not entry.triangles[kind] is int or layer.faces!=entry.triangles[kind] or not entry.boxes[kind] is AABB: return {}
		var box: AABB=entry.boxes[kind]
		if not box.position.is_finite() or not box.size.is_finite() or box.size.x<0 or box.size.y<0 or box.size.z<0 or layer.get("box")!=box: return {}
		var identity: Variant=layer.get("canonical_identity")
		if not identity is Dictionary or identity.get("format")!="tokyo_mesh_component" or identity.get("schema")!=1 \
			or identity.get("slots")!=1 or not Contract.sha(identity.get("source")): return {}
		parts[layer.path]=layer
		mapping.append([layer.path,0])
		total+=layer.bytes
	if total!=entry.bytes: return {}
	var key: String=binding.sha256+":"+entry.path
	result.keys[entry.path]=key
	result.pages[key]={"components":parts,"mapping":mapping,"bytes":total,"canonical_identity":{
		"format":"tokyo_partition_view","schema":1,"partition":binding.sha256,"source":source,
		"node":entry.path,"configuration":binding.configuration}}
	var children: Array=[]
	var child_faces := [0,0,0]
	for child: Variant in entry.children:
		if not child is Dictionary: return {}
		var normalized := node(child,pages,binding,source,result,depth+1,packed)
		if normalized.is_empty(): return {}
		children.append(normalized)
		for kind in 3: child_faces[kind]+=normalized.triangles[kind]
	if not children.is_empty() and child_faces!=entry.triangles: return {}
	var output := entry.duplicate()
	output.path=key
	output.children=children
	return output
