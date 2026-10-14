extends RefCounted
## 只制作单地表空间替代；完整几何逐角守恒，成本重放不授予显示资格。
const Read := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")

static func run(native: RefCounted, package: Dictionary, input: Dictionary) -> int:
	var target: String=input.ground_split_candidate
	var row: Dictionary=native.pages.get(target,{})
	if not row.has("mapping"): return 1
	var source: String=row.mapping[2][0]
	var slot := int(row.mapping[2][1])
	var binding: Dictionary=row.components[source]
	if FileAccess.get_sha256(source)!=binding.sha256: return 1
	var resource: Resource=load(source)
	if resource==null or not resource.valid() or resource.stream_identity()!=binding.canonical_identity: return 1
	var ground: ArrayMesh=resource.meshes[slot]
	var meshes: Array[ArrayMesh]=[ArrayMesh.new(),ArrayMesh.new(),ground]
	var seed := {"path":target,"boxes":[AABB(),AABB(),ground.get_aabb()],"triangles":[0,0,Count.triangles(ground)],"bytes":Read.decoded_bytes(ground),"children":[]}
	var writer := preload("res://scripts/tests/tokyo_partition_page_writer.gd").new()
	writer.output=input.output+".partition"
	if DirAccess.dir_exists_absolute(writer.output): return 1
	var splitter := preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
	# 固定两层中位数空间二分，不根据已知失败镜头删除或裁切三角形。
	splitter.branching=2;splitter.page_sink=writer.emit
	var tree: Dictionary=splitter._split(seed,meshes,2)
	if splitter.failed or splitter.conserved_splits!=9: return 1
	var saved: Dictionary=writer.finish(tree,binding.sha256)
	if saved.is_empty(): return 1
	var replaced := 0
	var roots: Array[Dictionary]=[]
	for root: Dictionary in native._grid_native_ground:
		var result := replace(root,target,tree)
		roots.append(result.entry);replaced+=int(result.count)
	if replaced!=1: return 1
	native._grid_native_ground=roots
	# 仅内存候选树；原目录和正式运行时不变，未登记为可流送资源。
	var status := preload("res://scripts/tests/tokyo_prefetch_replay_case.gd").run(native,package,input)
	if status!=0: return status
	var result: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input.output))
	result["ground_partition"]=saved
	result["source_faces"]=Count.triangles(ground)
	result["source_page"]=target
	var file := FileAccess.open(input.output,FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify(result,"\t"));file.close()
	return 0

static func replace(entry: Dictionary, target: String, tree: Dictionary) -> Dictionary:
	if entry.path==target: return {"entry":tree,"count":1}
	var copy := entry.duplicate()
	var children: Array[Dictionary]=[]
	var count := 0
	for child: Dictionary in entry.get("children",[]):
		var result := replace(child,target,tree)
		children.append(result.entry);count+=int(result.count)
	copy.children=children
	return {"entry":copy,"count":count}
