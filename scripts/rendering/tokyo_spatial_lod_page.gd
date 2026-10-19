extends "res://scripts/rendering/tokyo_spatial_leaf.gd"
## 独立LOD4子/叶包；不能冒充相同楼高、不同档位的近景资源。
@export var package_variant := ""


func valid() -> bool:
	if schema_version != 3 or level != 4 or package_variant not in ["full", "mid"] or parent_id < 0 or parent_id >= 16:
		return false
	if ancestor_id < 0:
		if ancestor_id != -1 or cell_id < 0 or cell_id >= 64 or cell_id / 4 != parent_id:
			return false
	elif ancestor_id < 32 or ancestor_id >= 64 or parent_id != ancestor_id / 4 or cell_id < 64 + ancestor_id * 4 or cell_id >= 68 + ancestor_id * 4:
		return false
	if meshes.size() != 3 or geometry_bytes < 0 or triangles < 0 or height_hash.length() != 64 or source_hash.length() != 64:
		return false
	for mesh: ArrayMesh in meshes:
		if mesh == null:
			return false
	return true
