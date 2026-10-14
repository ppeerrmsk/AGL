extends RefCounted
## 认证单层/同格双层组件到既有三槽视图；共用原Mesh，不复制几何或新增加载池。
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const View := preload("res://scripts/rendering/tokyo_partition_page.gd").View

class SegmentedView extends View:
	var layer_meshes: Array=[[],[],[]]


static func assemble(row: Dictionary, loaded: Dictionary) -> Resource:
	var identity: Variant=row.get("canonical_identity")
	if identity is Dictionary and identity.get("schema")==3: return assemble_segmented(row,loaded)
	if identity is Dictionary and identity.get("schema")==2: return assemble_group(row,loaded)
	if not identity is Dictionary or identity.size()!=6: return null
	if identity.get("format")!="tokyo_grid_view" or identity.get("schema")!=1: return null
	if identity.get("configuration") not in ["lod4_full","lod5_full"]: return null
	if not Contract.sha(identity.get("source")) or not Contract.sha(identity.get("component")): return null
	if not identity.get("layer") is int or identity.layer<0 or identity.layer>1: return null
	if not row.get("components") is Dictionary or row.components.size()!=1: return null
	if not row.get("bytes") is int or not row.get("faces") is int or not row.get("box") is AABB: return null
	var path: String=row.components.keys()[0]
	var binding: Variant=row.components[path]
	if not binding is Dictionary or not Contract.binding(binding) or binding.path!=path: return null
	if not binding.get("canonical_identity") is Dictionary or binding.canonical_identity.get("source")!=identity.component: return null
	var value: Variant=loaded.get(path)
	if typeof(value)!=TYPE_OBJECT or not is_instance_valid(value) or not value is Component: return null
	var component := value as Component
	if not component.valid() or component.meshes.size()!=1 or component.stream_identity()!=binding.canonical_identity: return null
	if component.geometry_bytes!=row.bytes or binding.get("bytes")!=row.bytes: return null
	var mesh: ArrayMesh=component.meshes[0]
	if mesh.get_aabb()!=row.box or preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(mesh)!=row.faces: return null
	var page := View.new()
	page.meshes=[ArrayMesh.new(),ArrayMesh.new(),ArrayMesh.new()]
	page.meshes[identity.layer]=mesh
	page.geometry_bytes=component.geometry_bytes
	page.identity=identity.duplicate(true)
	return page


static func assemble_segmented(row: Dictionary, loaded: Dictionary) -> Resource:
	# 片集合属于身份；仅装配显式选中的原片，不授予整格来源覆盖资格。
	var identity: Dictionary=row.canonical_identity
	if identity.size()!=5 or identity.get("format")!="tokyo_grid_view": return null
	if identity.get("configuration") not in ["lod4_full","lod5_full"] or not Contract.sha(identity.get("source")): return null
	if not row.get("views") is Array or row.views.size()!=2 or not identity.get("layers") is Array or identity.layers.size()!=2: return null
	if not row.get("components") is Dictionary or not row.get("bytes") is int: return null
	var page := SegmentedView.new()
	page.meshes=[ArrayMesh.new(),ArrayMesh.new(),ArrayMesh.new()]
	var bindings: Dictionary={}
	var total := 0
	for kind in 2:
		if not row.views[kind] is Array or not identity.layers[kind] is Array: return null
		var identities: Array=[]
		for child: Variant in row.views[kind]:
			if not child is Dictionary or not child.get("canonical_identity") is Dictionary: return null
			var child_identity: Dictionary=child.canonical_identity
			if child_identity.get("schema")!=1 or child_identity.get("layer")!=kind: return null
			if child_identity.get("source")!=identity.source or child_identity.get("configuration")!=identity.configuration: return null
			var view: Resource=assemble(child,loaded)
			if view==null: return null
			for path: String in child.components:
				if bindings.has(path): return null
				bindings[path]=child.components[path]
			identities.append(child_identity)
			page.layer_meshes[kind].append(view.meshes[kind])
			total+=int(view.geometry_bytes)
		if identities!=identity.layers[kind]: return null
	if bindings.is_empty() or bindings!=row.components or total!=row.bytes: return null
	page.geometry_bytes=total
	page.identity=identity.duplicate(true)
	return page


static func assemble_group(row: Dictionary, loaded: Dictionary) -> Resource:
	var identity: Dictionary=row.canonical_identity
	if identity.size()!=5 or identity.get("format")!="tokyo_grid_view": return null
	if identity.get("configuration") not in ["lod4_full","lod5_full"] or not Contract.sha(identity.get("source")): return null
	if not row.get("views") is Array or row.views.size()!=2 or not identity.get("layers") is Array or identity.layers.size()!=2: return null
	if not row.get("components") is Dictionary or not row.get("bytes") is int: return null
	var page := View.new()
	page.meshes=[ArrayMesh.new(),ArrayMesh.new(),ArrayMesh.new()]
	var bindings: Dictionary={}
	var total := 0
	for kind in 2:
		var child: Variant=row.views[kind]
		if child==null:
			if identity.layers[kind]!=null: return null
			continue
		if not child is Dictionary or not child.get("canonical_identity") is Dictionary: return null
		var child_identity: Dictionary=child.canonical_identity
		if child_identity.get("schema")!=1 or child_identity.get("layer")!=kind: return null
		if child_identity!=identity.layers[kind] or child_identity.get("source")!=identity.source or child_identity.get("configuration")!=identity.configuration: return null
		var view: Resource=assemble(child,loaded)
		if view==null: return null
		for path: String in child.components:
			if bindings.has(path): return null
			bindings[path]=child.components[path]
		page.meshes[kind]=view.meshes[kind]
		total+=int(view.geometry_bytes)
	if bindings.is_empty() or bindings!=row.components or total!=row.bytes: return null
	page.geometry_bytes=total
	page.identity=identity.duplicate(true)
	return page
