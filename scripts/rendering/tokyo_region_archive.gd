extends Resource
## 制作候选的单档静态网格包；正式多档/分格归档另行验收，不携带原始 OSM JSON。
@export var schema_version := 1
@export var metadata: Dictionary = {}
@export var meshes: Array[ArrayMesh] = []


func valid() -> bool:
	if schema_version != 1 or meshes.size() != 5 or int(metadata.get("source_buildings", 0)) <= 0:
		return false
	for mesh in meshes:
		if mesh == null or mesh.get_surface_count() == 0:
			return false
	return true


func packet() -> Dictionary:
	var result := metadata.duplicate(true)
	for index in 4:
		result[["low_mesh", "known_mesh", "road_mesh", "rail_mesh"][index]] = meshes[index]
	return result
