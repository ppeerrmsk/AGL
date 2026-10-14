extends RefCounted
## 显式有损候选合同：绑定离线误差/连接证据和真实网格；不借用旧无损证明。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Partition := preload("res://scripts/rendering/tokyo_ground_partition.gd")
const Adapter := preload("res://scripts/rendering/tokyo_partition_catalog.gd")
const Packed := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")

static func read_json(binding: Variant) -> Dictionary:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path) != binding.sha256: return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(binding.path))
	return value if value is Dictionary else {}

static func attribute_sha(mesh: ArrayMesh) -> String:
	if mesh == null or mesh.get_surface_count() != 1: return ""
	var arrays := mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if positions.size() != normals.size() or positions.size() != colors.size(): return ""
	var values := PackedFloat32Array()
	for corner in (positions.size() if indices.is_empty() else indices.size()):
		var i: int = corner if indices.is_empty() else indices[corner]
		var p := positions[i];var n := normals[i];var c := colors[i]
		values.append_array(PackedFloat32Array([p.x,p.y,p.z,n.x,n.y,n.z,c.r,c.g,c.b,c.a]))
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK or hash.update(values.to_byte_array()) != OK: return ""
	return hash.finish().hex_encode()

static func attach(native: RefCounted, binding: Dictionary) -> bool:
	if not native._native_ground_only: return false
	var manifest := read_json(binding)
	if manifest.get("schema") != 1 or manifest.get("candidate_only") != true: return false
	var proof := read_json(manifest.get("geometry"))
	var connections := read_json(manifest.get("connections"))
	if proof.get("schema") != 1 or proof.get("non_target_oriented_corners_exact") != true: return false
	for flag: String in ["source_attributes_preserved","endpoints_and_shared_vertices_preserved","centerline_relations_preserved"]:
		if connections.get(flag) != true: return false
	if not proof.get("layers") is Array or proof.layers.size() != 2: return false
	for i in 2:
		if proof.layers[i].get("layer") != ["paths","minor_roads"][i] or proof.layers[i].get("bidirectional_set_distance_bound") != 0.2: return false
	if not connections.get("sources") is Array or connections.sources.size() != 4: return false
	for source: Dictionary in connections.sources:
		if not Contract.binding(source) or FileAccess.get_sha256(source.path) != source.sha256: return false
	var assembly := read_json(manifest.get("assembly"))
	var base := read_json(manifest.get("base_assembly"))
	if assembly.get("candidate_sha256") != proof.get("candidate_attributes",{}).get("sha256") or assembly.get("base_report_sha256") != manifest.get("base_assembly",{}).get("sha256"): return false
	if not manifest.get("generation") is Array or manifest.generation.size() != 2: return false
	for i in 2:
		var generated := read_json(manifest.generation[i])
		if generated.get("original",{}).get("sha256") != connections.sources[i*2].sha256 or generated.get("candidate",{}).get("sha256") != connections.sources[i*2+1].sha256: return false
		var report_path: String = str(generated.get("output","")).path_join("report.json")
		var expected: String = str((base if i == 0 else assembly).get("replay_sha256",""))
		if not Contract.sha(expected) or FileAccess.get_sha256(report_path) != expected: return false
	var target: String = proof.get("target","")
	var original: Dictionary = native.pages.get(target,{})
	if not original.has("mapping") or original.mapping.size() != 3: return false
	var source: String = original.mapping[2][0]
	var original_binding: Dictionary = original.components.get(source,{})
	if not Contract.binding(original_binding) or FileAccess.get_sha256(source) != original_binding.sha256: return false
	var resource: Resource = load(source)
	if resource == null or not resource.valid() or resource.stream_identity() != original_binding.canonical_identity: return false
	var original_mesh: ArrayMesh = resource.meshes[int(original.mapping[2][1])]
	if attribute_sha(original_mesh) != proof.get("original_attributes",{}).get("sha256") or Count.triangles(original_mesh) != int(proof.get("original_faces",-1)): return false
	var part: Variant = manifest.get("partition")
	if not Contract.binding(part) or FileAccess.get_sha256(part.path) != part.sha256: return false
	var file := FileAccess.open(part.path,FileAccess.READ)
	if file == null: return false
	var data: Variant = file.get_var(false);file.close()
	if not data is Dictionary or not data.get("tree") is Dictionary or data.tree.get("path") != target: return false
	var key: Dictionary = part.duplicate();key.configuration = "lod5_full"
	var normalized := Adapter.normalize(data,key)
	if normalized.is_empty(): return false
	var found := Partition.find_entry(native._grid_native_ground,target)
	if found.is_empty() or found.boxes[2] != data.tree.boxes[2]: return false
	var meshes := {}
	for path: String in data.pages:
		var layers: Array = data.pages[path].layers
		if int(layers[0].faces) != 0 or int(layers[1].faces) != 0: return false
		var layer: Dictionary = layers[2]
		if FileAccess.get_sha256(layer.path) != layer.sha256: return false
		var loaded: Resource = load(layer.path)
		if loaded == null or not loaded.valid() or loaded.stream_identity() != layer.canonical_identity: return false
		var mesh: ArrayMesh = loaded.meshes[0]
		if Count.triangles(mesh) != layer.faces or Packed.decoded_bytes(mesh) != layer.bytes or mesh.get_aabb() != layer.box: return false
		meshes[path] = mesh
	if Count.triangles(meshes[target]) != int(proof.get("candidate_faces",-1)) or attribute_sha(meshes[target]) != proof.get("candidate_attributes",{}).get("sha256"): return false
	if not Partition.conserved(data.tree,meshes): return false
	# 验证完成才原子登记；保留原有无损入口完全不变。
	native.pages.merge(normalized.pages)
	native._grid_native_ground = Adapter.replace(native._grid_native_ground,target,normalized.tree)
	native._partition_roots.lod5_full = Adapter.replace(native._partition_roots.lod5_full,target,normalized.tree)
	return true
