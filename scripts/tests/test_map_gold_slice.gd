extends RefCounted

## 横滨金样纯矢量数据与静态批次预算回归；不判断美术质量。

const Renderer = preload("res://scripts/survivor/map_detail_vector_renderer.gd")
const DetailCache = preload("res://scripts/survivor/map_detail_tile_cache.gd")
const MapFeature = preload("res://scripts/survivor/map_feature_renderer.gd")
const TacticalMapScript = preload("res://scripts/survivor/tactical_map.gd")
const SurvivorModeScript = preload("res://scripts/survivor/survivor_mode.gd")
const MapBoundaryScript = preload("res://scripts/survivor/map_boundary.gd")
const ZoneDataScript = preload("res://scripts/survivor/zone_data.gd")
const MapGeographyScript = preload("res://scripts/survivor/map_geography.gd")
const PACKED_GOLD_PATH := "res://resources/maps/detail_tiles_packed/detail_05_07.agdt.gz"
const LANDMARK_MANIFEST_PATH := "res://resources/maps/tokyo_bay_landmark_walls.json"
const DETAIL_MANIFEST_PATH := "res://resources/maps/tokyo_bay_detail_tiles_full.json"
const EXPECTED_EMPTY_COAST_EDGE_CELLS := {
	# Both cells are predominantly water. Fixed 0.8 zoom PNG/vector captures
	# confirm only a tiny strict-land fringe/bridge, and the source PBF assigns
	# no supported detail feature to either tile.
	"detail_10_06": true,
	"detail_14_04": true,
}
var _fail := 0


func run() -> void:
	var metrics: Dictionary = Renderer.prewarm()
	_check(bool(metrics.get("ok", false)), "gold slice prewarm succeeds: %s" % metrics)
	_check(int(metrics.get("draw_calls", 999)) <= 22,
		"gold slice uses <=22 loading-only static draw calls (got %s)" % metrics.get("draw_calls", "?"))
	_check(int(metrics.get("triangles", 0)) > 50000,
		"gold slice has non-trivial baked geometry (got %s triangles)" % metrics.get("triangles", "?"))
	var counts: Dictionary = metrics.get("source_counts", {})
	var building_count := (
		int(counts.get("building_small", 0))
		+ int(counts.get("building_medium", 0))
		+ int(counts.get("building_large", 0)))
	_check(building_count >= 15000,
		"gold slice contains >=15000 real OSM buildings (got %d)" % building_count)
	_check(int(metrics.get("build_ms", 999999)) < 3000,
		"gold slice packet prewarm <3000ms (got %sms)" % metrics.get("build_ms", "?"))
	var packed_metrics: Dictionary = Renderer.prewarm(PACKED_GOLD_PATH)
	_check(bool(packed_metrics.get("ok", false)),
		"packed AGDT gold tile decodes: %s" % packed_metrics)
	_check(int(packed_metrics.get("triangles", 0)) > 50000,
		"packed AGDT retains non-trivial geometry (got %s triangles)" % packed_metrics.get("triangles", "?"))
	_check(int(packed_metrics.get("landmark_wall_triangles", 0)) > 0,
		"packed Yokohama tile merges OSM-height landmark walls into the existing wall packet")
	_check(int(packed_metrics.get("draw_calls", 999)) <= 22,
		"landmark walls do not increase the detail draw-call budget")
	Renderer.release_prewarm(PACKED_GOLD_PATH)
	var landmark_file := FileAccess.open(LANDMARK_MANIFEST_PATH, FileAccess.READ)
	_check(landmark_file != null, "full-map landmark wall manifest exists")
	if landmark_file != null:
		var landmark_manifest = JSON.parse_string(landmark_file.get_as_text())
		landmark_file.close()
		_check(typeof(landmark_manifest) == TYPE_DICTIONARY,
			"full-map landmark wall manifest parses")
		if typeof(landmark_manifest) == TYPE_DICTIONARY:
			var wall_manifest: Dictionary = landmark_manifest
			var wall_tiles: Array = wall_manifest.get("tiles", [])
			var wall_triangle_sum := 0
			var roof_triangle_sum := 0
			var wall_gzip_sum := 0
			var wall_max_triangles := 0
			var wall_files_valid := true
			var wall_ids: Dictionary = {}
			for tile_any in wall_tiles:
				var tile: Dictionary = tile_any
				var tile_id := String(tile.get("id", ""))
				var tile_path := String(tile.get("data_path", ""))
				var tile_triangles := int(tile.get("triangles", 0))
				var tile_roof_triangles := int(tile.get("roof_triangles", 0))
				var tile_gzip_bytes := int(tile.get("gzip_bytes", 0))
				wall_ids[tile_id] = true
				wall_triangle_sum += tile_triangles
				roof_triangle_sum += tile_roof_triangles
				wall_gzip_sum += tile_gzip_bytes
				wall_max_triangles = maxi(wall_max_triangles, tile_triangles)
				if tile_id.is_empty() or not FileAccess.file_exists(tile_path):
					wall_files_valid = false
					continue
				var wall_bytes := FileAccess.get_file_as_bytes(tile_path)
				if wall_bytes.size() != tile_gzip_bytes:
					wall_files_valid = false
					continue
				var unpacked := wall_bytes.decompress_dynamic(
					8 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
				if unpacked.size() < 24 or unpacked.slice(0, 4).get_string_from_ascii() != "AGLW":
					wall_files_valid = false
					continue
				var point_count := int(unpacked.decode_u32(20))
				if point_count % 3 != 0 or point_count / 3 != tile_triangles \
						or unpacked.size() != 24 + point_count * 12:
					wall_files_valid = false
			_check(wall_files_valid,
				"all full-map AGLW sidecars decode and match their manifest budgets")
			_check(wall_ids.size() == wall_tiles.size()
					and wall_tiles.size() == int(wall_manifest.get("tile_count", -1)),
				"full-map landmark tile ids are unique and count matches manifest")
			_check(wall_triangle_sum == int(wall_manifest.get("triangles", -1))
					and wall_gzip_sum == int(wall_manifest.get("gzip_bytes", -1))
					and wall_max_triangles == int(wall_manifest.get("max_tile_triangles", -1)),
				"full-map landmark aggregate triangle/size maxima match manifest")
			_check(roof_triangle_sum == int(wall_manifest.get("roof_triangles", -1))
					and roof_triangle_sum in range(1, 20001),
				"real high-rise roof caps are present and stay within the static budget")
			_check(wall_tiles.size() <= 199 and wall_triangle_sum <= 210000
					and wall_gzip_sum <= 16 * 1024 * 1024 and wall_max_triangles <= 50000,
				"full-map landmark layer stays within static city-detail budgets")
	var plan: Dictionary = DetailCache.cache_plan()
	_check(bool(plan.get("ok", false)), "detail tile manifest loads: %s" % plan)
	_check(int(plan.get("tile_count", 0)) >= 195,
		"full Tokyo Bay manifest covers >=195 non-empty land/detail tiles (got %s)" % plan.get("tile_count", "?"))
	_check(int(plan.get("bootstrap_tile_count", 0)) in range(1, 9),
		"loading bootstrap is bounded to 1..8 tiles (got %s)" % plan.get("bootstrap_tile_count", "?"))
	_check(int(plan.get("cache_bytes_rgba8", 999999999)) <= 110 * 1024 * 1024,
		"detail LRU resident memory <=110MiB (got %s bytes)" % plan.get("cache_bytes_rgba8", "?"))
	_check(int(plan.get("peak_bytes_rgba8", 999999999)) <= 150 * 1024 * 1024,
		"detail LRU sequential-bake peak <=150MiB (got %s bytes)" % plan.get("peak_bytes_rgba8", "?"))
	_check(int(plan.get("max_main_canvas_draw_calls", 999)) <= 12,
		"detail LRU exposes <=12 cached sprites (got %s)" % plan.get("max_main_canvas_draw_calls", "?"))
	_check(DetailCache.BOOTSTRAP_REGION.has_point(MapBoundaryScript.get_player_start()),
		"loading bootstrap region contains the formal player start")
	var all_zone_view_unions_valid := true
	for zone_any in ZoneDataScript.ZONES:
		var zone: Dictionary = zone_any
		var center: Vector2 = zone.get("center", Vector2.INF)
		var radius := float(zone.get("radius", 0.0))
		for direction_any in [
			Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT,
			Vector2(1.0, 1.0).normalized(), Vector2(-1.0, 1.0).normalized(),
			Vector2(1.0, -1.0).normalized(), Vector2(-1.0, -1.0).normalized(),
		]:
			var direction: Vector2 = direction_any
			var cruise_edge: Vector2 = center + direction * radius
			var view_regions: Array = SurvivorModeScript._detail_path_view_regions(
				cruise_edge, center, Vector2(1600.0, 900.0))
			var view_plan: Dictionary = DetailCache.regions_plan(view_regions)
			if not bool(view_plan.get("ok", false)) \
					or int(view_plan.get("tile_count", 0)) not in range(0, 13):
				all_zone_view_unions_valid = false
				printerr("  INFO: detail coverage overflow center=%s radius=%.1f direction=%s plan=%s" % [
					center, radius, direction, view_plan])
	_check(all_zone_view_unions_valid,
		"all formal zone approaches fit 0..12 complete tiles; pure-ocean paths need no Detail")
	var detail_manifest_file := FileAccess.open(DETAIL_MANIFEST_PATH, FileAccess.READ)
	_check(detail_manifest_file != null, "full-map AGDT manifest exists")
	if detail_manifest_file != null:
		var detail_manifest = JSON.parse_string(detail_manifest_file.get_as_text())
		detail_manifest_file.close()
		_check(typeof(detail_manifest) == TYPE_DICTIONARY, "full-map AGDT manifest parses")
		if typeof(detail_manifest) == TYPE_DICTIONARY:
			var packed_manifest: Dictionary = detail_manifest
			var packed_tiles: Array = packed_manifest.get("tiles", [])
			var packed_ids: Dictionary = {}
			var feature_counts_by_id: Dictionary = {}
			var packed_bytes_sum := 0
			var nonempty_tiles := 0
			var packed_files_valid := true
			var sources_are_build_only := true
			for tile_any in packed_tiles:
				var tile: Dictionary = tile_any
				var tile_id := String(tile.get("id", ""))
				var tile_path := String(tile.get("data_path", ""))
				var source_path := String(tile.get("json_source_path", ""))
				var expected_bytes := int(tile.get("packed_bytes", -1))
				packed_ids[tile_id] = true
				packed_bytes_sum += maxi(expected_bytes, 0)
				var count_sum := 0
				for value_any in (tile.get("counts", {}) as Dictionary).values():
					count_sum += int(value_any)
				feature_counts_by_id[tile_id] = count_sum
				if count_sum > 0:
					nonempty_tiles += 1
				if tile_id.is_empty() or not FileAccess.file_exists(tile_path):
					packed_files_valid = false
				else:
					var packed_file := FileAccess.open(tile_path, FileAccess.READ)
					if packed_file == null or packed_file.get_length() != expected_bytes:
						packed_files_valid = false
					if packed_file != null:
						packed_file.close()
				if not source_path.begins_with("tmp/full_map_detail/detail_tiles_source/") \
						or source_path.begins_with("res://"):
					sources_are_build_only = false
			_check(packed_files_valid,
				"all 203 AGDT runtime files exist and match manifest byte lengths")
			_check(packed_ids.size() == packed_tiles.size()
					and packed_tiles.size() == int(packed_manifest.get("tile_count", -1)),
				"full-map AGDT tile ids are unique and count matches manifest")
			_check(nonempty_tiles == 199,
				"full-map AGDT manifest contains exactly 199 nonempty runtime tiles")
			_check(packed_bytes_sum == int(packed_manifest.get("packed_bytes", -1)),
				"full-map AGDT aggregate packed bytes match manifest")
			_check(sources_are_build_only,
				"near-1GiB source JSON stays under tmp/.gdignore and out of Godot resources")
			var omitted_land_cells: Array[String] = []
			var registered_empty_land_cells: Array[String] = []
			var expected_empty_coast_edge_hits: Array[String] = []
			var broad_only_cells: Array[String] = []
			var formal_world := Rect2(Vector2(-15000.0, -15000.0), Vector2(30000.0, 30000.0))
			for grid_y in range(16):
				for grid_x in range(16):
					var grid_id := "detail_%02d_%02d" % [grid_x, grid_y]
					var grid_rect := Rect2(
						Vector2(-16300.0 + grid_x * 2000.0, -15700.0 + grid_y * 2000.0),
						Vector2(2000.0, 2000.0)).intersection(formal_world)
					if grid_rect.size.x <= 0.0 or grid_rect.size.y <= 0.0:
						continue
					var contains_land := false
					var contains_broad_land := false
					for sample_y in range(7):
						for sample_x in range(7):
							var uv := Vector2((sample_x + 0.5) / 7.0, (sample_y + 0.5) / 7.0)
							var sample := grid_rect.position + grid_rect.size * uv
							contains_broad_land = contains_broad_land \
								or MapGeographyScript.is_on_land(sample)
							if MapGeographyScript.is_on_land_strict(sample):
								contains_land = true
								break
						if contains_land:
							break
					if not contains_land:
						if contains_broad_land and (not packed_ids.has(grid_id) \
								or int(feature_counts_by_id.get(grid_id, 0)) <= 0):
							broad_only_cells.append(grid_id)
						continue
					if not packed_ids.has(grid_id):
						omitted_land_cells.append(grid_id)
					elif int(feature_counts_by_id.get(grid_id, 0)) <= 0:
						if EXPECTED_EMPTY_COAST_EDGE_CELLS.has(grid_id):
							expected_empty_coast_edge_hits.append(grid_id)
						else:
							registered_empty_land_cells.append(grid_id)
			_check(omitted_land_cells.is_empty(),
				"all manifest-omitted grid cells are sampled ocean/outside (land hits=%s)" % [omitted_land_cells])
			_check(registered_empty_land_cells.is_empty(),
				"all registered empty detail cells are sampled ocean (land hits=%s)" % [registered_empty_land_cells])
			expected_empty_coast_edge_hits.sort()
			var expected_empty_ids: Array[String] = []
			for expected_id_any in EXPECTED_EMPTY_COAST_EDGE_CELLS.keys():
				expected_empty_ids.append(String(expected_id_any))
			expected_empty_ids.sort()
			_check(expected_empty_coast_edge_hits == expected_empty_ids,
				"known empty coast-edge cells stay explicit and exact (hits=%s)" % [expected_empty_coast_edge_hits])
			print("  INFO: broad-only land cells intentionally audited as strict-water=%s" % [broad_only_cells])
	var cache_node: Node2D = DetailCache.new()
	_check(cache_node.has_method("bake_cache") and cache_node.has_method("attach_cached"),
		"detail cache exposes loading bake and runtime attach paths")
	_check(cache_node.has_method("set_detail_zoom"),
		"detail cache exposes continuous zoom fade")
	_check(cache_node.has_method("bake_region"),
		"detail cache exposes explicit safe-pause region prewarm")
	cache_node.free()
	var feature_node: Node2D = MapFeature.new()
	_check(feature_node.has_method("prewarm_detail_region"),
		"production map renderer exposes cross-zone detail prewarm")
	_check(feature_node.has_method("prewarm_detail_regions"),
		"production map renderer exposes all-or-nothing viewport-union prewarm")
	feature_node.free()
	var survivor_mode: Node2D = SurvivorModeScript.new()
	_check(survivor_mode.has_method("_prewarm_nav_detail"),
		"arbitrary Tab navigation points expose the same safe-pause detail prewarm path")
	survivor_mode.free()
	var tactical_map: CanvasLayer = TacticalMapScript.new()
	tactical_map.set("_is_open", true)
	tactical_map.set_detail_prepare_in_progress(true)
	tactical_map.close()
	_check(tactical_map.is_open() and bool(tactical_map.get("_close_after_detail_prepare")),
		"Tab/Esc close is deferred while cross-zone detail is preparing")
	tactical_map.free()
	print("[MapGoldSliceTest] %s" % ("PASS" if _fail == 0 else "FAIL x%d" % _fail))


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_fail += 1
		printerr("  FAIL: %s" % message)
