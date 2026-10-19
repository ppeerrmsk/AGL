extends Resource
const FullGrid := preload("res://scripts/rendering/tokyo_full_grid_contract.gd")
## 规范空间目录只有值和路径，不持有任何Mesh或旧父资源。
const CONFIGURATIONS := ["lod0_full", "lod0_guarded", "lod1_full", "lod1_guarded", "lod2_full", "lod2_guarded",
	"lod3_full", "lod3_guarded", "lod4_full", "lod4_mid", "lod5_full"]
# R143独立保存审计：只变LOD5低楼；固定层和LOD1/2全体配置逐源不变。不是任意新目录的兼容许可。
const UNCHANGED_FIXED_LOD12_CATALOGS := ["3f3842acb66ddb133cc1738dbaf775fb09f4ddbb7d2df13f8f7b0677f2aaca92",
	"f4139942c2708b515de82aa32f48c1de1f7cac6fe7b2eab37d9eee9047e2bc85"]
@export var schema_version := 1
@export var collision_sha256 := ""
@export var owners_sha256 := ""
@export var configurations: Dictionary = {}
@export var descriptors: Dictionary = {}
@export var regional_extension: Dictionary = {}
@export var full_grid: Dictionary = {}


func valid() -> bool:
	if schema_version==2:
		return FullGrid.valid(self)
	if not extension_valid() or schema_version != 1 or collision_sha256.length() != 64 or owners_sha256.length() != 64 \
			or configurations.size() != CONFIGURATIONS.size() or descriptors.size() != 2288:
		return false
	var seen: Dictionary = {}
	for configuration: String in CONFIGURATIONS:
		var parents: Variant = configurations.get(configuration)
		if not parents is Array or parents.size() != 16:
			return false
		for parent in 16:
			if not _entry_valid(parents[parent], configuration, parent, -1, -1, seen):
				return false
	return seen.size() == descriptors.size()


func extension_valid() -> bool:
	if schema_version==2:
		return regional_extension.is_empty() and FullGrid.metadata_valid(full_grid,collision_sha256,owners_sha256)
	if not full_grid.is_empty():
		return false
	if regional_extension.is_empty():
		return true
	if regional_extension.size()!=6:
		return false
	var old_west: bool = regional_extension.get("region")=="west_residential" and regional_extension.get("bounds")==Rect2(-6800,-2700,500,1000) and regional_extension.get("source_count")==76473
	var corridor: bool = regional_extension.get("region")=="west_corridor" and regional_extension.get("bounds")==Rect2(-7300,-2700,1000,1000) and regional_extension.get("source_count")==80511
	var northwest: bool = regional_extension.get("region")=="west_northwest" and regional_extension.get("bounds")==Rect2(-7300,-3700,1000,2000) and regional_extension.get("source_count")==88575 \
		and regional_extension.get("registry_sha256")=="b2071a17cbb4222ddd7532b495f1ed2425212e9dac237d388aedbe4ce8c068fe" \
		and regional_extension.get("source_manifest_sha256") in ["68c3981291b9e2c04783471f9e4d34a366b55f1b9797b7cb8849388e3bbb71a3","e4418975c4c5da7818043376e3b14c33c22994c87c2a0b8b318b709f1a9f3d33","a8176d4a777584200a239f5cf13fe7ff2a4b5327aedfd75c8615f4bbe1e46084"] \
		and regional_extension.get("boundary_manifest_sha256")=="a140ace529731e8e210de0b695f3503e024b64b8ac76c4ca08682f6cf6f5edb9"
	var outer_west: bool = regional_extension.get("region")=="west_outer" and regional_extension.get("bounds")==Rect2(-8300,-3700,2000,2000) and regional_extension.get("source_count")==94058 \
		and regional_extension.get("registry_sha256")=="e57da4c3ca3e0cddbfb692ec78e6df2a273caf7b0fede082b6f22c8a8624603d" \
		and regional_extension.get("source_manifest_sha256")=="2c939a288876ce091bcfbdf2972652e72111d89bdc22589644c866f1b44f7567" \
		and regional_extension.get("boundary_manifest_sha256")=="a140ace529731e8e210de0b695f3503e024b64b8ac76c4ca08682f6cf6f5edb9"
	var north_seam: bool = regional_extension.get("region")=="west_north_seam" and regional_extension.get("bounds")==Rect2(-8300,-4700,2000,3000) and regional_extension.get("source_count")==97368 \
		and regional_extension.get("registry_sha256")=="6ca1fb5664dd0ce41ff58650d2c50bd7391eb2e23913ec0d4425208c74060204" \
		and regional_extension.get("source_manifest_sha256")=="d7f76a7c97f58fa4f566324f33fde079230a8761e34833758970e106bba168e6" \
		and regional_extension.get("boundary_manifest_sha256")=="a140ace529731e8e210de0b695f3503e024b64b8ac76c4ca08682f6cf6f5edb9"
	var north_left: bool = regional_extension.get("region")=="west_north_left" and regional_extension.get("bounds")==Rect2(-8300,-4700,2000,3000) and regional_extension.get("source_count")==100000 \
		and regional_extension.get("registry_sha256")=="07d7bf28673e6472a05211a58a95a1325d9dc9b0c2abf613ea49d12f05dfde09" \
		and regional_extension.get("source_manifest_sha256")=="3fd5c30f2977993ba99f68133815bf40795cfd2f97470fe6669a3f4fe069bda7" \
		and regional_extension.get("boundary_manifest_sha256")=="a140ace529731e8e210de0b695f3503e024b64b8ac76c4ca08682f6cf6f5edb9"
	var north_right: bool = regional_extension.get("region")=="west_north_right" and regional_extension.get("bounds")==Rect2(-8300,-4700,2000,3000) and regional_extension.get("source_count")==101235 \
		and regional_extension.get("registry_sha256")=="45098e3d30e11470986c93200e8d81be56ff68e6616929baffc3d12e7cfb54b9" \
		and regional_extension.get("source_manifest_sha256") in ["f4457072407b815990fc2a9cd57fc2762fd080023708bc3f6653b547fbbdd807","48652d4fe45243908d947c2d793273ba4e7e2fd25abeb86a6930c98527e55c31"] \
		and regional_extension.get("boundary_manifest_sha256")=="a140ace529731e8e210de0b695f3503e024b64b8ac76c4ca08682f6cf6f5edb9"
	var southwest: bool = regional_extension.get("region")=="west_southwest" and regional_extension.get("bounds")==Rect2(-8300,-4700,2000,3000) and regional_extension.get("source_count")==106951 \
		and regional_extension.get("registry_sha256")=="67f3e204ecda7a49d6d51f00f2b49a0c8ecfc2b9b4c04a24ba559df8b03b1229" \
		and regional_extension.get("source_manifest_sha256")=="de82a0722298df2f816e7f546353726578c73c9d183015ae017019fe84862a1f" \
		and regional_extension.get("boundary_manifest_sha256")=="a6500e439ac54be0538727b8620e6b030f8489deb73a5b441240fabbf0d6f808"
	if not old_west and not corridor and not northwest and not outer_west and not north_seam and not north_left and not north_right and not southwest:
		return false
	for key: String in ["registry_sha256","source_manifest_sha256","boundary_manifest_sha256"]:
		var value: Variant = regional_extension.get(key)
		if not value is String or value.length()!=64 or not value.is_valid_hex_number():
			return false
	return true


func presentation_archive(original: Resource) -> Resource:
	if original==null or not extension_valid():
		return null
	if schema_version==2:
		var whole: Resource = original.duplicate(true)
		whole.bounds=full_grid.bounds
		whole.coverage_rects.assign([full_grid.bounds])
		whole.source_count=int(full_grid.source_count)
		whole.source_hash=(original.source_hash+full_grid.input_manifest_sha256).sha256_text()
		return whole
	if regional_extension.is_empty():
		return original
	var result: Resource = original.duplicate(true)
	result.bounds = result.bounds.merge(regional_extension.bounds)
	if regional_extension.region in ["west_outer","west_north_seam","west_north_left","west_north_right","west_southwest"]:
		# L形覆盖不得以外包络吞掉西南尚未制作的底图。
		result.coverage_rects.append(Rect2(-7300,-3700,1000,2000))
		result.coverage_rects.append(Rect2(-8300,-3700,1000,1000))
		if regional_extension.region in ["west_north_seam","west_north_left","west_north_right","west_southwest"]:
			result.coverage_rects.append(Rect2(-7800,-4700,1000,1000))
		if regional_extension.region in ["west_north_left","west_north_right","west_southwest"]:
			result.coverage_rects.append(Rect2(-8300,-4700,500,1000))
		if regional_extension.region in ["west_north_right","west_southwest"]:
			result.coverage_rects.append(Rect2(-6800,-4700,500,1000))
		if regional_extension.region=="west_southwest":
			result.coverage_rects.append(Rect2(-8300,-2700,1000,1000))
	else:
		result.coverage_rects.append(regional_extension.bounds)
	result.source_count = regional_extension.source_count
	result.source_hash = (original.source_hash+regional_extension.source_manifest_sha256+regional_extension.boundary_manifest_sha256).sha256_text()
	return result


func pages_per_configuration() -> int:
	return FullGrid.PAGES if schema_version==2 else 208


func gameplay_source_count() -> int:
	return int(full_grid.get("game_source_count",0)) if schema_version==2 else 48


func _entry_valid(entry: Dictionary, configuration: String, parent: int, cell: int, ancestor: int, seen: Dictionary) -> bool:
	var path: String = entry.get("path", "")
	var descriptor: Dictionary = descriptors.get(path, {})
	var identity: Dictionary = descriptor.get("canonical_identity", {})
	if path.is_empty() or seen.has(path) or identity.size() != 11 or identity.get("format") != "tokyo_canonical_spatial" \
			or identity.get("schema") != 1 or identity.get("configuration") != configuration \
			or identity.get("level") != int(configuration.substr(3, 1)) or identity.get("parent") != parent \
			or identity.get("cell") != cell or identity.get("ancestor") != ancestor \
			or identity.get("collision") != collision_sha256 or identity.get("owners") != owners_sha256 \
			or String(identity.get("source", "")).length() != 64 or String(identity.get("game_sources", "")).length() != 64:
		return false
	if int(entry.get("parent_id", -2)) != parent or int(entry.get("cell_id", -2)) != cell \
			or int(entry.get("ancestor_id", -2)) != ancestor or entry.get("level") != identity.level \
			or int(entry.get("bytes", -1)) < 0 or entry.get("bytes") != descriptor.get("bytes") \
			or entry.get("boxes", []).size() != 3 or entry.get("triangles", []).size() != 3:
		return false
	for kind in 3:
		var box: Variant = entry.boxes[kind]
		if not box is AABB or not box.position.is_finite() or not box.size.is_finite() \
				or box.size.x < 0 or box.size.y < 0 or box.size.z < 0 or int(entry.triangles[kind]) < 0:
			return false
	seen[path] = true
	var children: Array = entry.get("children", [])
	var count := 4 if cell == -1 or (ancestor == -1 and parent >= 8) else 0
	if children.size() != count or (count > 0 and entry.get("cuts", PackedFloat32Array()).size() != 3):
		return false
	for cut: float in entry.get("cuts", PackedFloat32Array()):
		if not is_finite(cut):
			return false
	for n in count:
		var child := parent * 4 + n if cell == -1 else 64 + cell * 4 + n
		if not _entry_valid(children[n], configuration, parent, child, -1 if cell == -1 else cell, seen):
			return false
	return true
