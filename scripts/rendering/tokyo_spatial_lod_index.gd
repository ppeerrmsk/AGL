extends "res://scripts/rendering/tokyo_hierarchical_index.gd"
@export var package_variant := ""
@export var level := 4


func valid() -> bool:
	if level != 4 or package_variant not in ["full", "mid"] or not super.valid():
		return false
	for parent: Dictionary in parents:
		if parent.get("package_variant", "") != package_variant or int(parent.get("level", -1)) != level:
			return false
		for child: Dictionary in parent.children:
			if not _same_package(child):
				return false
			for leaf: Dictionary in child.get("children", []):
				if not _same_package(leaf):
					return false
	return true


func _same_package(entry: Dictionary) -> bool:
	return entry.get("package_variant", "") == package_variant and int(entry.get("level", -1)) == level \
		and String(entry.get("source_hash", "")).length() == 64 and String(entry.get("height_hash", "")).length() == 64
