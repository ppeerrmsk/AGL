extends RefCounted
## 事件级低墙绑定；没有独立tick/加载器，墙随原低层父节点裁剪。
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")


static func create_slot(parent: MeshInstance3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "LowWalls"
	node.material_override = parent.material_override
	node.hide()
	parent.add_child(node)
	return node


static func bind(batch: Dictionary, node: MeshInstance3D) -> void:
	var page: Resource = batch.building
	if page.low_wall_mesh == null:
		return
	node.mesh = page.low_wall_mesh
	node.cast_shadow = batch.nodes[0].cast_shadow
	node.show()
	batch["low_wall_node"] = node
	batch.boxes[0] = page.low_full_bounds
	batch.nodes[0].custom_aabb = page.low_full_bounds
	batch.layer_triangles[0] = page.low_full_faces
	batch["low_full_triangles"] = page.low_full_faces
	batch["low_roof_triangles"] = Indexed.triangles(page.meshes[0])


static func fade_for_scale(scale_value: float) -> float:
	if not is_finite(scale_value) or scale_value <= 0.0:
		return 0.0
	return 1.0 - smoothstep(0.32, 0.48, scale_value)


static func apply_fade(batch: Dictionary, mix_value: float) -> void:
	if not batch.has("low_wall_node"):
		return
	var node: MeshInstance3D = batch.low_wall_node
	node.visible = mix_value < 1.0
	batch.layer_triangles[0] = batch.low_full_triangles if node.visible else batch.low_roof_triangles


static func clear(batch: Dictionary) -> void:
	var node: Variant = batch.get("low_wall_node")
	if typeof(node) == TYPE_OBJECT and is_instance_valid(node):
		node.hide()
		node.mesh = null
	batch.nodes[0].custom_aabb = AABB()
	batch.erase("low_wall_node")
	batch.erase("low_full_triangles")
	batch.erase("low_roof_triangles")


static func faces(batch: Dictionary) -> int:
	var node: Variant = batch.get("low_wall_node")
	if typeof(node) != TYPE_OBJECT or not is_instance_valid(node) or not node.visible or not batch.nodes[0].visible or node.mesh == null:
		return 0
	return Indexed.triangles(node.mesh)
