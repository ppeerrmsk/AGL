extends Resource
## 可单独退役的原生组件；物理身份与原逻辑页身份分离。
@export var schema_version := 1
@export var source_hash := ""
@export var geometry_bytes := 0
@export var mesh_bytes := PackedInt32Array()
@export var meshes: Array[ArrayMesh] = []


func valid() -> bool:
	if schema_version != 1 or source_hash.length() != 64 or meshes.size() < 1 or meshes.size() > 2 or mesh_bytes.size() != meshes.size():
		return false
	var total := 0
	for n in meshes.size():
		if meshes[n] == null or meshes[n].get_surface_count() > 1 or mesh_bytes[n] < 0:
			return false
		total += mesh_bytes[n]
	return total == geometry_bytes


func stream_identity() -> Dictionary:
	return {"format": "tokyo_mesh_component", "schema": schema_version, "source": source_hash, "slots": meshes.size()}
