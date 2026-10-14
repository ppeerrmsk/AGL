extends RefCounted
## 载入期认证地表替代；逐角守恒，选择树、覆盖树及物理目录一起生效。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Adapter := preload("res://scripts/rendering/tokyo_partition_catalog.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")

static func attach(native: RefCounted, binding: Dictionary) -> bool:
	if not native._native_ground_only or not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return false
	var file := FileAccess.open(binding.path,FileAccess.READ)
	if file==null: return false
	var data: Variant=file.get_var(false);file.close()
	if not data is Dictionary or not data.get("tree") is Dictionary or not data.get("pages") is Dictionary: return false
	var target: String=data.tree.get("path","")
	var original: Dictionary=native.pages.get(target,{})
	if not original.has("mapping") or original.mapping.size()!=3: return false
	var source: String=original.mapping[2][0]
	var part: Dictionary=original.components.get(source,{})
	if part.get("sha256","")!=data.get("input_sha256","") or FileAccess.get_sha256(source)!=part.sha256: return false
	var source_resource: Resource=load(source)
	if source_resource==null or not source_resource.valid() or source_resource.stream_identity()!=part.canonical_identity: return false
	var key := binding.duplicate();key.configuration="lod5_full"
	var normalized := Adapter.normalize(data,key)
	if normalized.is_empty(): return false
	var found := find_entry(native._grid_native_ground,target)
	# ground_only保留旧楼层包络但面数为零；只比较实际地表包络，不把无几何层当覆盖。
	if found.is_empty() or data.tree.boxes[2]!=found.boxes[2] or data.tree.triangles!=Array(found.triangles): return false
	var meshes: Dictionary={}
	for path: String in data.pages:
		var layers: Array=data.pages[path].layers
		if int(layers[0].faces)!=0 or int(layers[1].faces)!=0: return false
		var layer: Dictionary=layers[2]
		if FileAccess.get_sha256(layer.path)!=layer.sha256: return false
		var resource: Resource=load(layer.path)
		if resource==null or not resource.valid() or resource.stream_identity()!=layer.canonical_identity: return false
		meshes[path]=resource.meshes[0]
	if not Join.conserved(source_resource.meshes[int(original.mapping[2][1])],[meshes[target]]) or not conserved(data.tree,meshes): return false
	# 全部检查成功后才登记，不留下半接入目录。
	native.pages.merge(normalized.pages)
	native._grid_native_ground=Adapter.replace(native._grid_native_ground,target,normalized.tree)
	native._partition_roots.lod5_full=Adapter.replace(native._partition_roots.lod5_full,target,normalized.tree)
	return true

static func conserved(entry: Dictionary, meshes: Dictionary) -> bool:
	if entry.children.is_empty(): return true
	var children: Array[ArrayMesh]=[]
	for child: Dictionary in entry.children:
		if not conserved(child,meshes): return false
		children.append(meshes[child.path])
	return Join.conserved(meshes[entry.path],children)

static func find_entry(entries: Array, target: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.path==target: return entry
		var found := find_entry(entry.get("children",[]),target)
		if not found.is_empty(): return found
	return {}
