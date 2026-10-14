extends RefCounted
## 只供固定切面审查；一次验证完整来源后原位绑定，离开审查立即恢复。
const Factory := preload("res://scripts/experiments/tokyo_gameplay_volume.gd")


static func bind(map: Node, path: String, collision_signature: String) -> Dictionary:
	var bundle: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if bundle == null or bundle.collision_sha256 != collision_signature:
		return {}
	var bindings: Array[Dictionary] = []
	for index in bundle.descriptors.size():
		var descriptor: Dictionary = bundle.descriptors[index]
		var batch: Dictionary = map._batches.get(descriptor.batch, {})
		if batch.is_empty() or str(batch.path) != str(descriptor.path) or bool(batch.precision_guarded) != bool(descriptor.precision_guarded):
			return {}
		var node: MeshInstance3D = batch.nodes[int(descriptor.kind)]
		if not node.visible or node.mesh.get_surface_count() != descriptor.surfaces.size():
			return {}
		for surface in node.mesh.get_surface_count():
			if var_to_bytes(node.mesh.surface_get_arrays(surface)).hex_encode().sha256_text() != str(descriptor.surfaces[surface]):
				return {}
		bindings.append({"node": node, "original": node.mesh, "replacement": bundle.meshes[index]})
	var bytes := Factory.geometry_bytes(bundle.addition)
	for mesh: ArrayMesh in bundle.meshes:
		bytes += Factory.geometry_bytes(mesh)
	if bytes != int(bundle.decoded_bytes):
		return {}
	for binding: Dictionary in bindings:
		binding.node.mesh = binding.replacement
	return {"bundle": bundle, "bindings": bindings, "bytes": bytes, "addition": bundle.addition}


static func restore(state: Dictionary) -> void:
	for binding: Dictionary in state.get("bindings", []):
		binding.node.mesh = binding.original
	state.clear()


static func references(state: Dictionary) -> Array[WeakRef]:
	# 把遍历强引用局限在同步函数内，避免审查协程的迭代器跨await保留最后一个网格。
	var result: Array[WeakRef] = []
	for mesh: ArrayMesh in state.bundle.meshes:
		result.append(weakref(mesh))
	return result


static func submitted_faces(map: Node) -> int:
	var result := 0
	for batch: Dictionary in map._batches.values():
		for node: MeshInstance3D in batch.nodes:
			if node.visible:
				result += Factory.triangles(node.mesh)
	return result
