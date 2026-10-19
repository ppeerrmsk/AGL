extends RefCounted
## 独立地表视图：仅持有地表槽，不能获得楼栋层资格。
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
class View extends Resource:
	var meshes: Array[ArrayMesh]=[]
	var geometry_bytes := 0
	var identity: Dictionary={}
	func stream_identity() -> Dictionary:
		return identity.duplicate(true)

static func assemble(row: Dictionary, loaded: Dictionary) -> Resource:
	var identity: Variant=row.get("canonical_identity")
	if not identity is Dictionary or identity.size()!=4 or identity.get("format")!="tokyo_ground_view" or identity.get("schema")!=1: return null
	if not Contract.sha(identity.get("source")) or not identity.get("parent") is String or identity.parent.is_empty(): return null
	if not row.get("components") is Dictionary or row.components.size()!=1 or row.get("mask")!=[false,false,true]: return null
	var path: String=row.components.keys()[0]
	var binding: Dictionary=row.components[path]
	if not Contract.binding(binding) or binding.path!=path or not row.get("bytes") is int or row.bytes!=binding.get("bytes"): return null
	var value: Variant=loaded.get(path)
	if typeof(value)!=TYPE_OBJECT or not is_instance_valid(value) or not value is Component: return null
	if not value.valid() or value.meshes.size()!=1 or value.geometry_bytes!=row.bytes or value.stream_identity()!=binding.get("canonical_identity"): return null
	if not row.get("faces") is int or preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(value.meshes[0])!=row.faces: return null
	var page := View.new()
	page.meshes=[null,null,value.meshes[0]];page.geometry_bytes=row.bytes;page.identity=identity.duplicate(true)
	return page
