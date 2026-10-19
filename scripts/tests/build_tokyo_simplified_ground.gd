extends RefCounted
## 将已审查属性落为独立候选；不借用无损分区证明，不修改正式目录。
static func run(input: Dictionary) -> int:
	if input.has("partition_candidate"): return partition(input)
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	for key: String in ["attributes", "proof"]:
		if not contract.binding(input.get(key)) or FileAccess.get_sha256(input[key].path) != input[key].sha256: return 1
	var proof: Variant = JSON.parse_string(FileAccess.get_file_as_string(input.proof.path))
	if not proof is Dictionary or proof.get("candidate_sha256") != input.attributes.sha256 or proof.get("original_oriented_corners_exact") != true: return 1
	var raw := FileAccess.get_file_as_bytes(input.attributes.path)
	if raw.is_empty() or raw.size() % 120 != 0 or raw.size() / 120 != proof.candidate_faces: return 1
	var values := raw.to_float32_array()
	for value: float in values:
		if not is_finite(value): return 1
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for offset in range(0, values.size(), 10):
		positions.append(Vector3(values[offset], values[offset+1], values[offset+2]))
		normals.append(Vector3(values[offset+3], values[offset+4], values[offset+5]))
		colors.append(Color(values[offset+6], values[offset+7], values[offset+8], values[offset+9]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
	mesh = packed.repack(mesh)
	var export := preload("res://scripts/tests/tokyo_residential_preview.gd")
	if export.export_payload(mesh).attributes != raw: return 1
	var component := preload("res://scripts/rendering/tokyo_mesh_component.gd").new()
	component.source_hash = var_to_bytes(["simplified_ground_v1",input.attributes.sha256,input.proof.sha256]).hex_encode().sha256_text()
	component.geometry_bytes = packed.decoded_bytes(mesh)
	component.mesh_bytes = PackedInt32Array([component.geometry_bytes])
	component.meshes = [mesh]
	var output: String = input.get("output", "")
	if not component.valid() or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	if DirAccess.make_dir_recursive_absolute(output) != OK: return 1
	var target := output.path_join("ground.res")
	if ResourceSaver.save(component,target,ResourceSaver.FLAG_COMPRESS) != OK: return 1
	var copy: Resource = ResourceLoader.load(target,"",ResourceLoader.CACHE_MODE_IGNORE)
	if copy == null or not copy.valid() or copy.stream_identity() != component.stream_identity(): return 1
	if export.export_payload(copy.meshes[0]).attributes != raw or copy.meshes[0].get_aabb() != mesh.get_aabb(): return 1
	var report := {"attributes":input.attributes,"proof":input.proof,"binding":{"path":target,"sha256":FileAccess.get_sha256(target),"bytes":component.geometry_bytes,"canonical_identity":component.stream_identity()},"faces":int(raw.size()/120),"surfaces":mesh.get_surface_count(),"roundtrip_attributes_exact":true,"runtime_integrated":false,"full_route_budget_verified":false}
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file == null: return 1
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("[Simplified ground] ",JSON.stringify(report))
	return 0


static func partition(input: Dictionary) -> int:
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	var binding: Variant = input.get("partition_candidate")
	if not contract.binding(binding) or FileAccess.get_sha256(binding.path) != binding.sha256: return 1
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	if not report is Dictionary or report.get("roundtrip_attributes_exact") != true: return 1
	for key: String in ["binding", "attributes", "proof"]:
		if not contract.binding(report.get(key)) or FileAccess.get_sha256(report[key].path) != report[key].sha256: return 1
	var component: Resource = load(report.binding.path)
	if component == null or not component.valid() or component.meshes.size() != 1: return 1
	var mesh: ArrayMesh = component.meshes[0]
	if preload("res://scripts/tests/tokyo_residential_preview.gd").export_payload(mesh).attributes != FileAccess.get_file_as_bytes(report.attributes.path): return 1
	var target: String = input.get("target", "")
	var output: String = input.get("output", "")
	if target.is_empty() or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
	if count.triangles(mesh) != int(report.faces): return 1
	var seed := {"path":target,"boxes":[AABB(),AABB(),mesh.get_aabb()],"triangles":[0,0,count.triangles(mesh)],"bytes":component.geometry_bytes,"children":[]}
	var writer := preload("res://scripts/tests/tokyo_partition_page_writer.gd").new()
	writer.output = output
	var splitter := preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
	splitter.branching = 2; splitter.page_sink = writer.emit
	var meshes: Array[ArrayMesh] = [ArrayMesh.new(),ArrayMesh.new(),mesh]
	var tree: Dictionary = splitter._split(seed,meshes,2)
	if splitter.failed or splitter.conserved_splits != 9: return 1
	var saved: Dictionary = writer.finish(tree,report.binding.sha256)
	if saved.is_empty(): return 1
	# 此守恒只相对新候选；不是相对旧正式地表的无损证明。
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file == null: return 1
	file.store_string(JSON.stringify({"candidate_report":binding,"partition":saved,"conservation_basis":"simplified_candidate_only","source_faces":count.triangles(mesh),"runtime_integrated":false},"\t"));file.close()
	print("[Simplified ground partition] ",JSON.stringify(saved))
	return 0


static func install_cost_candidate(native: RefCounted, binding: Dictionary) -> bool:
	# 仅供确定性成本问题：不由正式读取器调用，不授予有损质量或连续覆盖资格。
	var contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
	if not native._native_ground_only or not contract.binding(binding) or FileAccess.get_sha256(binding.path) != binding.sha256: return false
	var file := FileAccess.open(binding.path,FileAccess.READ)
	if file == null: return false
	var data: Variant = file.get_var(false);file.close()
	if not data is Dictionary or not data.get("tree") is Dictionary or not data.get("pages") is Dictionary: return false
	var target: String = data.tree.get("path","")
	var guard := preload("res://scripts/rendering/tokyo_ground_partition.gd")
	var original := guard.find_entry(native._grid_native_ground,target)
	if original.is_empty() or original.boxes[2] != data.tree.boxes[2]: return false
	var adapter := preload("res://scripts/rendering/tokyo_partition_catalog.gd")
	var key := binding.duplicate();key.configuration = "lod5_full"
	var normalized := adapter.normalize(data,key)
	if normalized.is_empty(): return false
	var meshes := {}
	for path: String in data.pages:
		var layers: Array = data.pages[path].layers
		if int(layers[0].faces) != 0 or int(layers[1].faces) != 0: return false
		var layer: Dictionary = layers[2]
		if FileAccess.get_sha256(layer.path) != layer.sha256: return false
		var resource: Resource = load(layer.path)
		if resource == null or not resource.valid() or resource.stream_identity() != layer.canonical_identity: return false
		var mesh: ArrayMesh = resource.meshes[0]
		if preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(mesh) != layer.faces or resource.geometry_bytes != layer.bytes or mesh.get_aabb() != layer.box: return false
		meshes[path] = mesh
	if not guard.conserved(data.tree,meshes): return false
	native.pages.merge(normalized.pages)
	native._grid_native_ground = adapter.replace(native._grid_native_ground,target,normalized.tree)
	native._partition_roots.lod5_full = adapter.replace(native._partition_roots.lod5_full,target,normalized.tree)
	return true


static func rejection_checks(native: RefCounted, binding: Dictionary) -> bool:
	var api := preload("res://scripts/rendering/tokyo_simplified_ground.gd")
	var manifest := api.read_json(binding)
	var proof := api.read_json(manifest.get("geometry"))
	var target: String = proof.get("target","")
	if not native.pages.has(target): return false
	var pages: Dictionary = native.pages.duplicate(true)
	var roots: Array = native._grid_native_ground.duplicate(true)
	var coverage: Array = native._partition_roots.lod5_full.duplicate(true)
	for kind in 3:
		native.pages = pages.duplicate(true)
		var bad := binding.duplicate(true)
		if kind == 0: bad.sha256 = "0".repeat(64)
		elif kind == 1:
			var source: String = native.pages[target].mapping[2][0]
			native.pages[target].components[source].sha256 = "0".repeat(64)
		else:
			native.pages[target].mapping[2] = native.pages[target].mapping[0].duplicate()
		var before: Dictionary = native.pages.duplicate(true)
		if api.attach(native,bad): return false
		if native.pages != before or native._grid_native_ground != roots or native._partition_roots.lod5_full != coverage: return false
		print("[Simplified rejection] case=",kind," rejected without partial registration")
	native.pages = pages
	if not api.attach(native,binding): return false
	print("[Simplified rejection] 3 rejected; valid candidate accepted")
	return true
