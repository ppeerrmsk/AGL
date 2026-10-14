extends Resource
## 一块的一档，或该块共享地表；不引用其他档位，便于按需释放。
@export var schema_version := 1
@export var cell_id := -1
@export var level := -1
@export var bounds := Rect2()
@export var geometry_bytes := 0
@export var triangles := 0
@export var source_ids := PackedStringArray()
@export var height_hash := ""
@export var detail_counts := PackedInt32Array()
@export var meshes: Array[ArrayMesh] = []
@export var precision_original: ArrayMesh
@export var precision_max_scale := 0.0
@export var precision_triangles := 0


func valid() -> bool:
	if schema_version != 1 or cell_id < 0 or level < -1 or level > 5:
		return false
	if meshes.size() != (1 if level == -1 else 2) or geometry_bytes < 0 or triangles < 0:
		return false
	for mesh in meshes:
		if mesh == null:
			return false
	if precision_original != null:
		if level < 0 or level > 3 or not is_equal_approx(precision_max_scale, [0.09, 0.18, 0.36, 0.72][level] * 1.08) \
				or precision_triangles <= 0 or precision_original.get_surface_count() != 1:
			return false
	elif precision_max_scale != 0.0 or precision_triangles != 0:
		return false
	return bounds.has_area()
