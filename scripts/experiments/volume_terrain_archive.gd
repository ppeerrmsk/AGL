extends Resource
## 离线生成、场景级持有的静态三维资源；不保存纹理，不改变曲面精度。
const PATH := "res://resources/maps/desert_volume_terrain.res"
const TACTICAL_PATH := "res://resources/maps/desert_volume_terrain_tactical.res"
const MANIFEST := "res://resources/maps/basemap_tiles/desert/manifest.json"
const METADATA := "res://resources/maps/desert_railway_bg_v2.json"
const EDGE_QUANTUM := 1.0 / 256.0
const SOURCES := [
	"res://resources/maps/desert_volume_relief.json", MANIFEST, METADATA,
	"res://resources/maps/desert_volume_hydrography.json",
	"res://scripts/experiments/volume_watercourse.gd",
	"res://scripts/experiments/volume_desert_relief.gd",
	"res://scripts/experiments/volume_terrain_surface.gd",
	"res://scripts/experiments/volume_mesh_factory.gd",
	"res://scripts/experiments/volume_terrain_archive.gd",
]
@export var fingerprint: String
@export var entries: Dictionary = {}
@export var details: PackedScene
@export var tactical_profile: bool = false
@export var geometry_bytes: int = 0


static func source_fingerprint() -> String:
	var hashes := PackedStringArray()
	for path: String in SOURCES:
		hashes.append(FileAccess.get_sha256(path))
	return "r15:" + "|".join(hashes).sha256_text()


func is_current(tactical: bool = false) -> bool:
	return fingerprint == source_fingerprint() and entries.size() == 146 and details != null and tactical_profile == tactical


func matching_mesh(key: String, bounds: Rect2, uv: Rect2, base_y: float) -> ArrayMesh:
	var entry: Dictionary = entries.get(key, {})
	# 同名瓦片也必须校验投影尺寸及 gutter；不能把旧几何套到新坐标。
	if entry.is_empty() or entry.bounds != bounds or entry.uv != uv or entry.base_y != base_y:
		return null
	return entry.mesh as ArrayMesh


static func source_rect(meta: Dictionary) -> Rect2:
	var bbox: Dictionary = meta.bbox_ll
	var center: Array = meta.game_world_center_latlon
	var lon_scale: float = float(meta.game_world_meters_per_degree_lon_at_center) * float(meta.game_world_px_per_meter)
	var lat_scale: float = float(meta.game_world_meters_per_degree_lat) * float(meta.game_world_px_per_meter)
	var x0 := (float(bbox.lon_min) - float(center[1])) * lon_scale
	var x1 := (float(bbox.lon_max) - float(center[1])) * lon_scale
	var y0 := -(float(bbox.lat_max) - float(center[0])) * lat_scale
	var y1 := -(float(bbox.lat_min) - float(center[0])) * lat_scale
	# 与正式 MapFeatureRenderer 一致：先以双精度作差，再转 Vector2。
	return Rect2(Vector2(x0, y0), Vector2(x1 - x0, y1 - y0))


static func tile_layouts() -> Dictionary:
	var rect := source_rect(JSON.parse_string(FileAccess.get_file_as_string(METADATA)))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var layouts := {}
	for lod: String in ["strategic", "operational", "detail"]:
		var level: Dictionary = manifest.levels[lod]
		var size := Vector2(level["size"][0], level["size"][1])
		for tile: Dictionary in level.tiles:
			if lod == "strategic":
				# 与 Sprite2D region.size * sprite.scale 保持相同浮点运算顺序。
				layouts["StrategicBasemap"] = {"bounds": Rect2(rect.position, size * (rect.size / size)),
					"render_bounds": canonical_tile_rect(rect.position, rect.end),
					"uv": Rect2(0, 0, 1, 1), "base_y": -0.8}
			else:
				var c: Array = tile.content_rect
				var content := Vector2(c[2], c[3])
				var gutter := Vector2.ONE * float(manifest.gutter)
				# 边缘不足一块的纹理仍填充到 content_size，不能按剩余内容宽度算 UV。
				var texture_size := Vector2.ONE * float(manifest.content_size) + gutter * 2.0
				var key := "%s_r%02d_c%02d" % [lod, tile.row, tile.column]
				var start := rect.position + Vector2(c[0], c[1]) / size * rect.size
				var end := rect.position + Vector2(c[0] + c[2], c[1] + c[3]) / size * rect.size
				layouts[key] = {"bounds": Rect2(start, content * (rect.size / size)),
					"render_bounds": canonical_tile_rect(start, end),
					"uv": Rect2(gutter / texture_size, content / texture_size), "base_y": -0.6}
	return layouts


static func canonical_tile_rect(start: Vector2, end: Vector2) -> Rect2:
	# 同一原像素边独立映射后落到同一可精确表示的格点，不从前一块的宽度累加。
	var lower := start.snapped(Vector2.ONE * EDGE_QUANTUM)
	var upper := end.snapped(Vector2.ONE * EDGE_QUANTUM)
	assert(maxf(lower.abs().x, lower.abs().y) <= 65536.0
		and maxf(upper.abs().x, upper.abs().y) <= 65536.0
		and maxf((upper - lower).abs().x, (upper - lower).abs().y) <= 65536.0,
		"canonical edge grid requires exact float32 coordinate and extent range")
	return Rect2(lower, upper - lower)
