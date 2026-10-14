extends Resource
## 16父块/64离线子块，不扩大16个同时活动块；只含路径和原生包络。
@export var schema_version := 1
@export var source_hash := ""
@export var source_count := 0
@export var original_index := "res://resources/maps/tokyo_volume_preview/r34_cells/index.res"
@export var parents: Array[Dictionary] = []


func valid() -> bool:
	if schema_version != 1 or parents.size() != 16 or source_hash.is_empty() or source_count <= 0:
		return false
	for id in 16:
		var parent: Dictionary = parents[id]
		if int(parent.get("parent_id", -1)) != id or parent.get("children", []).size() != 4:
			return false
		for n in 4:
			var child: Dictionary = parent.children[n]
			if int(child.get("cell_id", -1)) != id * 4 + n or child.get("boxes", []).size() != 3 \
					or child.get("triangles", []).size() != 3 or String(child.get("path", "")).is_empty():
				return false
	return true
