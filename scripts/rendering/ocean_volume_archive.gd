extends "res://scripts/rendering/tokyo_volume_archive.gd"
## 海洋专属离线数据；不持有地图纹理，也不读取沙漠布局。
const OCEAN_PATH := "res://resources/maps/ocean_volume.res"
const DOCUMENT := "res://resources/maps/ocean_islands_preview.aglmap"
const METADATA := "res://resources/maps/ocean_islands_bg_v2.json"
const MANIFEST := "res://resources/maps/basemap_tiles/ocean/manifest.json"
const ELEVATION := "res://resources/maps/ocean_volume_elevation.json"
const INPUTS := [DOCUMENT, METADATA, MANIFEST, ELEVATION,
	"res://scripts/rendering/ocean_volume_archive.gd",
	"res://scripts/experiments/ocean_volume_factory.gd",
	"res://scripts/experiments/volume_building_factory.gd",
	"res://scripts/experiments/volume_terrain_surface.gd",
	"res://scripts/tests/build_ocean_volume.gd"]
@export var data_hash := ""
@export var relief_texture: ImageTexture
@export var terrain: Dictionary = {}
@export var terrain_bounds := Rect2()
@export var source_buildings: Array[Dictionary] = []


static func fingerprint() -> String:
	var hashes := PackedStringArray()
	for path: String in INPUTS:
		hashes.append(FileAccess.get_sha256(path))
	return "ocean-r1:" + "|".join(hashes).sha256_text()


static func data_fingerprint() -> String:
	var hashes := PackedStringArray()
	for path: String in [DOCUMENT, METADATA, MANIFEST, ELEVATION]:
		hashes.append(FileAccess.get_sha256(path))
	return "|".join(hashes).sha256_text()


func valid() -> bool:
	return super.valid() and building_count == 16 and terrain.size() == 146 \
		and relief_texture != null and geometry_bytes <= 32 * 1024 * 1024 and data_hash == data_fingerprint() \
		and (not OS.has_feature("editor") or source_hash == fingerprint())
