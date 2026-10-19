extends "res://scripts/rendering/tokyo_spatial_page.gd"
## 二级空间叶包；parent_id仍是来源根，ancestor_id是R39一级显示包。
@export var ancestor_id := -1


func valid() -> bool:
	if schema_version != 2 or level != 5 or ancestor_id < 0 or ancestor_id >= 64 or parent_id != ancestor_id / 4:
		return false
	if cell_id < 64 + ancestor_id * 4 or cell_id >= 68 + ancestor_id * 4:
		return false
	if meshes.size() != 3 or geometry_bytes < 0 or triangles < 0 or height_hash.length() != 64 or source_hash.length() != 64:
		return false
	for mesh: ArrayMesh in meshes:
		if mesh == null:
			return false
	return true
