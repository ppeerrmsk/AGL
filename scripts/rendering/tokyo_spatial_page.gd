extends Resource
## 近景空间子包，不是新的建筑来源；身份与高度权威仍在原父包。
@export var schema_version := 1
@export var cell_id := -1
@export var parent_id := -1
@export var level := 5
@export var geometry_bytes := 0
@export var triangles := 0
@export var height_hash := ""
@export var source_hash := ""
@export var meshes: Array[ArrayMesh] = []


func valid() -> bool:
	if schema_version != 1 or level != 5 or parent_id < 0 or parent_id >= 16 or cell_id < 0 or cell_id >= 64 or cell_id / 4 != parent_id:
		return false
	if meshes.size() != 3 or geometry_bytes < 0 or triangles < 0 or height_hash.length() != 64 or source_hash.length() != 64:
		return false
	for mesh: ArrayMesh in meshes:
		if mesh == null:
			return false
	return true
