extends Resource
## 完整切面共享归档：槽位映射复用真实Mesh，不以减记预算冒充共享。
@export var schema_version := 1
@export var source_hash := ""
@export var geometry_bytes := 0
@export var mesh_bytes := PackedInt32Array()
@export var meshes: Array[ArrayMesh] = []
@export var variants: Dictionary = {}


func valid() -> bool:
	if schema_version != 1 or source_hash.length() != 64 or variants.size() != 2 or meshes.is_empty() \
			or meshes.size() > 6 or meshes.size() != mesh_bytes.size() or geometry_bytes < 0:
		return false
	var total := 0
	var instances: Dictionary = {}
	for n in meshes.size():
		if meshes[n] == null or meshes[n].get_surface_count() > 1 or mesh_bytes[n] < 0 or instances.has(meshes[n].get_instance_id()):
			return false
		instances[meshes[n].get_instance_id()] = true
		total += mesh_bytes[n]
	if total != geometry_bytes:
		return false
	var shared_identity: Dictionary = {}
	var used: Dictionary = {}
	for configuration: String in variants:
		if not variants[configuration] is Dictionary or not variants[configuration].get("identity") is Dictionary:
			return false
		var row: Dictionary = variants[configuration]
		var identity: Dictionary = row.get("identity", {})
		var slots: Variant = row.get("slots")
		if identity.size() != 11 or identity.get("format") != "tokyo_canonical_spatial" or identity.get("schema") != 1 \
				or identity.get("configuration") != configuration or String(row.get("sha256", "")).length() != 64 \
				or String(row.get("path", "")).is_empty() or not slots is PackedInt32Array or slots.size() != 3:
			return false
		for key: String in ["source", "collision", "owners", "game_sources"]:
			if not identity.get(key) is String or String(identity[key]).length() != 64:
				return false
		for key: String in ["parent", "cell", "ancestor", "level"]:
			if not identity.get(key) is int:
				return false
		var parent := int(identity.parent)
		var cell := int(identity.cell)
		var ancestor := int(identity.ancestor)
		if parent < 0 or parent >= 16 or (cell == -1 and ancestor != -1):
			return false
		if cell != -1 and ((ancestor == -1 and (cell < 0 or cell >= 64 or cell/4 != parent)) \
				or (ancestor != -1 and (ancestor < 0 or ancestor >= 64 or ancestor/4 != parent or cell < 64+ancestor*4 or cell >= 68+ancestor*4))):
			return false
		if shared_identity.is_empty():
			shared_identity = identity
		for key: String in ["parent", "cell", "ancestor", "level", "collision", "owners", "game_sources"]:
			if identity.get(key) != shared_identity.get(key):
				return false
		for slot: int in slots:
			if slot < 0 or slot >= meshes.size():
				return false
			used[slot] = true
	var level := int(shared_identity.get("level", -1))
	return level >= 0 and level < 4 and variants.has("lod%d_full" % level) and variants.has("lod%d_guarded" % level) \
		and used.size() == meshes.size()


func stream_identity() -> Dictionary:
	return {"format": "tokyo_shared_page", "schema": schema_version, "source": source_hash,
		"mapping": var_to_bytes(variants).hex_encode().sha256_text()}


func variant_meshes(configuration: String) -> Array[ArrayMesh]:
	var result: Array[ArrayMesh] = []
	if not variants.has(configuration):
		return result
	for slot: int in variants[configuration].slots:
		result.append(meshes[slot])
	return result
