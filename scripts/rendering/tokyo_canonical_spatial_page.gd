extends Resource
## R52离线候选；完整三层包，来源和组合身份独立，不冒充旧LOD4或LOD5包。
@export var schema_version := 1
@export var configuration := ""
@export var level := -1
@export var parent_id := -1
@export var cell_id := -1
@export var ancestor_id := -1
@export var source_hash := ""
@export var collision_sha256 := ""
@export var owners_sha256 := ""
@export var geometry_bytes := 0
@export var triangles := 0
@export var meshes: Array[ArrayMesh] = []
@export var game_sources := PackedInt32Array()
# 只由认证组件流送组装，不序列化成可独立加载的屋顶归档。
var low_wall_mesh: ArrayMesh
var low_full_bounds := AABB()
var low_full_faces := 0


func valid() -> bool:
	if schema_version not in [1,2] or level < 0 or level > 5 or parent_id < 0 or parent_id >= 16 or meshes.size() != 3:
		return false
	if configuration != "lod%d_full" % level and not (level < 4 and configuration == "lod%d_guarded" % level) and not (level == 4 and configuration == "lod4_mid"):
		return false
	if source_hash.length() != 64 or collision_sha256.length() != 64 or owners_sha256.length() != 64 or geometry_bytes < 0 or triangles < 0:
		return false
	if schema_version==2:
		if not preload("res://scripts/rendering/tokyo_full_grid_contract.gd").coordinates_valid(parent_id,cell_id,ancestor_id):
			return false
	elif cell_id == -1:
		if ancestor_id != -1:
			return false
	elif ancestor_id == -1:
		if cell_id < 0 or cell_id >= 64 or cell_id / 4 != parent_id:
			return false
	elif ancestor_id < 0 or ancestor_id >= 64 or ancestor_id / 4 != parent_id or cell_id < 64 + ancestor_id * 4 or cell_id >= 68 + ancestor_id * 4:
		return false
	for mesh: ArrayMesh in meshes:
		if mesh == null or mesh.get_surface_count() > 1:
			return false
	if low_wall_mesh != null:
		if low_wall_mesh.get_surface_count() != 1 or not low_full_bounds.position.is_finite() or not low_full_bounds.size.is_finite():
			return false
		var indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
		if low_full_faces != indexed.triangles(meshes[0])+indexed.triangles(low_wall_mesh):
			return false
	return true


func stream_identity() -> Dictionary:
	return {"format": "tokyo_canonical_spatial", "schema": schema_version,
		"configuration": configuration, "level": level, "parent": parent_id,
		"cell": cell_id, "ancestor": ancestor_id, "source": source_hash,
		"collision": collision_sha256, "owners": owners_sha256,
		"game_sources": var_to_bytes(game_sources).hex_encode().sha256_text()}
