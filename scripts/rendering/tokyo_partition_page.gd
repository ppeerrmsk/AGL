extends RefCounted
## 二分候选的纯装配协议；身份独立，不授予覆盖或正式安装资格。
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Bundle := preload("res://scripts/rendering/tokyo_partition_bundle.gd")
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")

class View extends Resource:
	var meshes: Array[ArrayMesh]=[]
	var geometry_bytes := 0
	var identity: Dictionary={}

	func stream_identity() -> Dictionary:
		return identity.duplicate(true)


static func assemble(row: Dictionary, loaded: Dictionary) -> Resource:
	var identity: Variant=row.get("canonical_identity")
	if not identity is Dictionary or identity.size()!=6: return null
	if identity.get("format")!="tokyo_partition_view" or not identity.get("schema") is int or identity.schema!=1: return null
	if not identity.get("partition") is String or not identity.get("source") is String: return null
	if not Contract.sha(identity.partition) or not Contract.sha(identity.source): return null
	if not identity.get("node") is String or identity.node.is_empty(): return null
	if identity.get("configuration") not in ["lod4_full","lod5_full"]: return null
	if not row.get("components") is Dictionary or not row.get("mapping") is Array or row.mapping.size()!=3: return null
	if not row.get("bytes") is int or row.bytes<0: return null
	var total := 0
	var used: Dictionary={}
	var page := View.new()
	if row.components.size()==1:
		var key: String=row.components.keys()[0]
		var binding: Variant=row.components[key]
		var value: Variant=loaded.get(key)
		if not binding is Dictionary or not Contract.binding(binding) or binding.path!=key: return null
		if typeof(value)!=TYPE_OBJECT or not is_instance_valid(value) or not value is Bundle: return null
		if not value.valid() or value.stream_identity()!=binding.get("canonical_identity") or value.geometry_bytes!=row.bytes or binding.get("bytes")!=row.bytes: return null
		for field: String in ["boxes","faces","mesh_bytes"]:
			if not binding.get(field) is Array or binding[field].size()!=3: return null
		for kind in 3:
			if row.mapping[kind]!=[key,kind] or value.mesh_bytes[kind]!=binding.mesh_bytes[kind]: return null
			var mesh: ArrayMesh=value.meshes[kind]
			if mesh.get_aabb()!=binding.boxes[kind] or preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(mesh)!=binding.faces[kind]: return null
			page.meshes.append(mesh)
		page.geometry_bytes=value.geometry_bytes
		page.identity=identity.duplicate(true)
		return page
	for slot: Variant in row.mapping:
		if not slot is Array or slot.size()!=2 or not slot[0] is String or not slot[1] is int or slot[1]!=0: return null
		var key: String=slot[0]
		if used.has(key) or not row.components.has(key): return null
		used[key]=true
		var binding: Variant=row.components[key]
		if not binding is Dictionary or not Contract.binding(binding) or binding.path!=key \
			or not binding.get("bytes") is int or not binding.get("canonical_identity") is Dictionary: return null
		var value: Variant=loaded.get(key)
		if typeof(value)!=TYPE_OBJECT or not is_instance_valid(value) or not value is Component: return null
		var component := value as Component
		if not component.valid() or component.meshes.size()!=1 or component.stream_identity()!=binding.canonical_identity \
			or component.geometry_bytes!=binding.bytes: return null
		if not binding.get("box") is AABB or not binding.get("faces") is int \
			or component.meshes[0].get_aabb()!=binding.box \
			or preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(component.meshes[0])!=binding.faces: return null
		total+=component.geometry_bytes
		page.meshes.append(component.meshes[0])
	if used.size()!=row.components.size() or total!=row.bytes: return null
	page.geometry_bytes=total
	page.identity=identity.duplicate(true)
	return page
