extends "res://scripts/rendering/tokyo_spatial_index.gd"
## 混合一级/二级目录，不放宽活动包上限；根与一级继续复用R39。
@export var hierarchy_version := 1


func valid() -> bool:
	if hierarchy_version != 1 or not super.valid():
		return false
	var leaves := 0
	for parent: Dictionary in parents:
		for child: Dictionary in parent.children:
			if child.has("children") != (int(parent.parent_id) >= 8):
				return false
			if not child.has("children"):
				continue
			if child.children.size() != 4:
				return false
			for n in 4:
				var leaf: Dictionary = child.children[n]
				if leaf.has("children") or int(leaf.get("cell_id", -1)) != 64 + int(child.cell_id) * 4 + n \
						or int(leaf.get("ancestor_id", -1)) != int(child.cell_id) or int(leaf.get("parent_id", -1)) != int(parent.parent_id) \
						or leaf.get("boxes", []).size() != 3 or leaf.get("triangles", []).size() != 3 or String(leaf.get("path", "")).is_empty():
					return false
				leaves += 1
	return leaves == 128
