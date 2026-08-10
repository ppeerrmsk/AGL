extends Node2D

## 全东京湾 Detail 瓦片运行时视觉审计。
##
## 逐格复用生产 MapDetailTileCache 的超采样、降采样、色阶与 padding 路径，
## 只在显式 Visual bench 中生成 16x16 缩略图；产物位于 tmp/，永不进入游戏资源。

const DetailCache = preload("res://scripts/survivor/map_detail_tile_cache.gd")
const DirectRenderer = preload("res://scripts/survivor/map_detail_vector_renderer.gd")
const BaseRenderer = preload("res://scripts/survivor/map_vector_preview_renderer.gd")
const MANIFEST_PATH := "res://resources/maps/tokyo_bay_detail_tiles_full.json"
const OUTPUT_DIR := "res://tmp/map_visual_qa/detail_atlas"
const THUMB_SIZE := Vector2i(128, 128)
const GRID_SIZE := Vector2i(16, 16)
const GRID_WORLD_RECT := Rect2(Vector2(-16300.0, -15700.0), Vector2(32000.0, 32000.0))
const MIN_TILE_LUMINANCE := 90.0
const MAX_TILE_LUMINANCE := 146.0
const MAX_TILE_TRIANGLES := 1_400_000
const MIN_GREEN_MINUS_RED := 3.0
const MAX_GREEN_MINUS_RED := 12.0
const MIN_BLUE_MINUS_GREEN := -10.0
const MAX_BLUE_MINUS_GREEN := -1.0
const CONTENT_RECT := Rect2i(
	Vector2i(DetailCache.CACHE_PADDING_PX, DetailCache.CACHE_PADDING_PX),
	DetailCache.CACHE_CONTENT_SIZE)

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var manifest := _load_manifest()
	if manifest.is_empty():
		_finish()
		return
	var tiles: Array = manifest.get("tiles", [])
	var atlas: Image = await _capture_base_atlas()
	if atlas == null or atlas.is_empty():
		_failures.append("Operational atlas base capture failed")
		_finish()
		return
	var cache: Node2D = DetailCache.new()
	cache.name = "AtlasProductionCache"
	add_child(cache)
	var records: Array = []
	var started_ms := Time.get_ticks_msec()
	for index in range(tiles.size()):
		var raw: Dictionary = tiles[index]
		var tile_id := String(raw.get("id", ""))
		var data_path := String(raw.get("data_path", ""))
		var rect_values: Array = raw.get("rect", [])
		if tile_id == "" or data_path == "" or rect_values.size() != 4:
			_failures.append("invalid manifest tile at index %d" % index)
			continue
		var spec := {
			"id": tile_id,
			"data_path": data_path,
			"rect": Rect2(
				Vector2(float(rect_values[0]), float(rect_values[1])),
				Vector2(float(rect_values[2]), float(rect_values[3]))),
		}
		var source_counts: Dictionary = raw.get("counts", {})
		var source_feature_count := 0
		for count_any in source_counts.values():
			source_feature_count += int(count_any)
		var cell := _cell_from_id(tile_id)
		if source_feature_count == 0:
			records.append({
				"id": tile_id,
				"cell": [cell.x, cell.y],
				"expected_empty": true,
				"source_feature_count": 0,
			})
			continue
		var direct_metrics: Dictionary = DirectRenderer.prewarm(data_path)
		if not bool(direct_metrics.get("ok", false)):
			_failures.append("%s prewarm failed: %s" % [tile_id, direct_metrics])
			continue
		var baked: Dictionary = await cache._bake_tile(spec)
		DirectRenderer.release_prewarm(data_path)
		if not bool(baked.get("ok", false)):
			_failures.append("%s bake failed: %s" % [tile_id, baked])
			continue
		var texture: Texture2D = baked.get("texture")
		var image := texture.get_image() if texture != null else null
		if image == null or image.is_empty():
			_failures.append("%s texture readback failed" % tile_id)
			continue
		var content := image.get_region(CONTENT_RECT)
		content.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_LANCZOS)
		if cell.x < 0 or cell.y < 0 or cell.x >= GRID_SIZE.x or cell.y >= GRID_SIZE.y:
			_failures.append("%s has invalid grid cell %s" % [tile_id, cell])
			continue
		atlas.blend_rect(content, Rect2i(Vector2i.ZERO, THUMB_SIZE), cell * THUMB_SIZE)
		var stats := _thumbnail_stats(atlas.get_region(
			Rect2i(cell * THUMB_SIZE, THUMB_SIZE)))
		stats["id"] = tile_id
		stats["cell"] = [cell.x, cell.y]
		stats["expected_empty"] = false
		stats["source_feature_count"] = source_feature_count
		stats["triangles"] = int(direct_metrics.get("triangles", 0))
		stats["bake_ms"] = int(baked.get("bake_ms", 0))
		records.append(stats)
		texture = null
		baked.clear()
		if (index + 1) % 16 == 0 or index + 1 == tiles.size():
			print("[MapDetailAtlasQa] %d/%d tiles" % [index + 1, tiles.size()])
		await get_tree().process_frame
	cache.queue_free()
	var seam_metrics := _atlas_seam_metrics(atlas)
	if float(seam_metrics.get("peak_excess_rgb", INF)) >= 3.0:
		_failures.append("atlas seam excess %.3f >= 3.0 RGB" %
			float(seam_metrics.get("peak_excess_rgb", INF)))
	var style_metrics := _atlas_style_metrics(records)
	if not bool(style_metrics.get("pass", false)):
		_failures.append(
			"atlas style budget failed: darkest=%s %.3f, brightest=%s %.3f, heaviest=%s %d tris, G-R=%.3f..%.3f, B-G=%.3f..%.3f" % [
				String(style_metrics.get("darkest_tile", "")),
				float(style_metrics.get("min_luminance", -INF)),
				String(style_metrics.get("brightest_tile", "")),
				float(style_metrics.get("max_luminance", INF)),
				String(style_metrics.get("heaviest_tile", "")),
				int(style_metrics.get("max_triangles", 0)),
				float(style_metrics.get("min_green_minus_red", -INF)),
				float(style_metrics.get("max_green_minus_red", INF)),
				float(style_metrics.get("min_blue_minus_green", -INF)),
				float(style_metrics.get("max_blue_minus_green", INF)),
			])
	var atlas_path := "%s/detail_atlas.png" % OUTPUT_DIR
	var save_error := atlas.save_png(atlas_path)
	if save_error != OK:
		_failures.append("atlas save failed: %s" % error_string(save_error))
	var registered_ids: Dictionary = {}
	var registered_empty_ids: Array[String] = []
	for record_any in records:
		var record: Dictionary = record_any
		registered_ids[String(record.get("id", ""))] = true
		if bool(record.get("expected_empty", false)):
			registered_empty_ids.append(String(record.get("id", "")))
	var omitted_ids: Array[String] = []
	for grid_y in range(GRID_SIZE.y):
		for grid_x in range(GRID_SIZE.x):
			var grid_id := "detail_%02d_%02d" % [grid_x, grid_y]
			if not registered_ids.has(grid_id):
				omitted_ids.append(grid_id)
	registered_empty_ids.sort()
	var report := {
		"schema_version": 1,
		"style_profile": String(manifest.get("style_profile", "")),
		"grid_cell_count": GRID_SIZE.x * GRID_SIZE.y,
		"tile_count": tiles.size(),
		"omitted_cell_count": omitted_ids.size(),
		"omitted_cell_ids": omitted_ids,
		"registered_empty_ids": registered_empty_ids,
		"explicit_empty_coast_edge_ids": ["detail_10_06", "detail_14_04"],
		"captured_count": records.size(),
		"elapsed_ms": Time.get_ticks_msec() - started_ms,
		"atlas": "detail_atlas.png",
		"seam_metrics": seam_metrics,
		"style_metrics": style_metrics,
		"failures": _failures,
		"tiles": records,
	}
	var report_file := FileAccess.open("%s/report.json" % OUTPUT_DIR, FileAccess.WRITE)
	if report_file == null:
		_failures.append("report open failed")
	else:
		report_file.store_string(JSON.stringify(report, "  "))
		report_file.close()
	_finish()


func _capture_base_atlas() -> Image:
	var viewport := SubViewport.new()
	viewport.name = "AtlasOperationalBase"
	viewport.size = GRID_SIZE * THUMB_SIZE
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var content := Node2D.new()
	var scale_value := float(viewport.size.x) / GRID_WORLD_RECT.size.x
	content.scale = Vector2.ONE * scale_value
	content.position = -GRID_WORLD_RECT.position * scale_value
	viewport.add_child(content)
	var renderer: Node2D = BaseRenderer.new()
	content.add_child(renderer)
	if not renderer.setup(null, GRID_WORLD_RECT, BaseRenderer.LOD_OPERATIONAL):
		viewport.queue_free()
		return null
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	await get_tree().process_frame
	return image


func _load_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		_failures.append("manifest open failed")
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_failures.append("manifest parse failed")
		return {}
	return parsed as Dictionary


func _cell_from_id(tile_id: String) -> Vector2i:
	var parts := tile_id.split("_")
	if parts.size() != 3:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[1]), int(parts[2]))


func _thumbnail_stats(image: Image) -> Dictionary:
	var luminance_sum := 0.0
	var rgb_sum := Vector3.ZERO
	var opaque_count := 0
	var pixel_count := image.get_width() * image.get_height()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a <= 0.01:
				continue
			opaque_count += 1
			luminance_sum += (color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722) * 255.0
			rgb_sum += Vector3(color.r, color.g, color.b) * 255.0
	var safe_count := maxf(float(opaque_count), 1.0)
	return {
		"opaque_ratio": float(opaque_count) / maxf(float(pixel_count), 1.0),
		"mean_luminance": luminance_sum / safe_count,
		"mean_rgb": [rgb_sum.x / safe_count, rgb_sum.y / safe_count, rgb_sum.z / safe_count],
	}


func _atlas_style_metrics(records: Array) -> Dictionary:
	var min_luminance := INF
	var max_luminance := -INF
	var max_triangles := 0
	var darkest_tile := ""
	var brightest_tile := ""
	var heaviest_tile := ""
	var min_green_minus_red := INF
	var max_green_minus_red := -INF
	var min_blue_minus_green := INF
	var max_blue_minus_green := -INF
	var min_green_minus_red_tile := ""
	var max_green_minus_red_tile := ""
	var min_blue_minus_green_tile := ""
	var max_blue_minus_green_tile := ""
	var nonempty_count := 0
	for record_any in records:
		var record: Dictionary = record_any
		if bool(record.get("expected_empty", false)):
			continue
		nonempty_count += 1
		var luminance := float(record.get("mean_luminance", -INF))
		var triangles := int(record.get("triangles", 0))
		var mean_rgb: Array = record.get("mean_rgb", [])
		if mean_rgb.size() != 3:
			continue
		var green_minus_red := float(mean_rgb[1]) - float(mean_rgb[0])
		var blue_minus_green := float(mean_rgb[2]) - float(mean_rgb[1])
		if luminance < min_luminance:
			min_luminance = luminance
			darkest_tile = String(record.get("id", ""))
		if luminance > max_luminance:
			max_luminance = luminance
			brightest_tile = String(record.get("id", ""))
		if triangles > max_triangles:
			max_triangles = triangles
			heaviest_tile = String(record.get("id", ""))
		if green_minus_red < min_green_minus_red:
			min_green_minus_red = green_minus_red
			min_green_minus_red_tile = String(record.get("id", ""))
		if green_minus_red > max_green_minus_red:
			max_green_minus_red = green_minus_red
			max_green_minus_red_tile = String(record.get("id", ""))
		if blue_minus_green < min_blue_minus_green:
			min_blue_minus_green = blue_minus_green
			min_blue_minus_green_tile = String(record.get("id", ""))
		if blue_minus_green > max_blue_minus_green:
			max_blue_minus_green = blue_minus_green
			max_blue_minus_green_tile = String(record.get("id", ""))
	return {
		"pass": nonempty_count > 0
			and min_luminance >= MIN_TILE_LUMINANCE
			and max_luminance <= MAX_TILE_LUMINANCE
			and max_triangles <= MAX_TILE_TRIANGLES
			and min_green_minus_red >= MIN_GREEN_MINUS_RED
			and max_green_minus_red <= MAX_GREEN_MINUS_RED
			and min_blue_minus_green >= MIN_BLUE_MINUS_GREEN
			and max_blue_minus_green <= MAX_BLUE_MINUS_GREEN,
		"nonempty_count": nonempty_count,
		"min_luminance": min_luminance,
		"max_luminance": max_luminance,
		"max_triangles": max_triangles,
		"darkest_tile": darkest_tile,
		"brightest_tile": brightest_tile,
		"heaviest_tile": heaviest_tile,
		"min_green_minus_red": min_green_minus_red,
		"max_green_minus_red": max_green_minus_red,
		"min_blue_minus_green": min_blue_minus_green,
		"max_blue_minus_green": max_blue_minus_green,
		"min_green_minus_red_tile": min_green_minus_red_tile,
		"max_green_minus_red_tile": max_green_minus_red_tile,
		"min_blue_minus_green_tile": min_blue_minus_green_tile,
		"max_blue_minus_green_tile": max_blue_minus_green_tile,
		"limits": {
			"min_luminance": MIN_TILE_LUMINANCE,
			"max_luminance": MAX_TILE_LUMINANCE,
			"max_triangles": MAX_TILE_TRIANGLES,
			"min_green_minus_red": MIN_GREEN_MINUS_RED,
			"max_green_minus_red": MAX_GREEN_MINUS_RED,
			"min_blue_minus_green": MIN_BLUE_MINUS_GREEN,
			"max_blue_minus_green": MAX_BLUE_MINUS_GREEN,
		},
	}


func _atlas_seam_metrics(image: Image) -> Dictionary:
	var samples: Array = []
	var boundary_sum := 0.0
	var excess_sum := 0.0
	var peak_excess := -INF
	for axis in ["vertical", "horizontal"]:
		for boundary_index in range(1, GRID_SIZE.x if axis == "vertical" else GRID_SIZE.y):
			var boundary_px := boundary_index * (THUMB_SIZE.x if axis == "vertical" else THUMB_SIZE.y)
			var boundary_delta := 0.0
			var neighbor_delta := 0.0
			var sample_count := image.get_height() if axis == "vertical" else image.get_width()
			for offset in range(sample_count):
				if axis == "vertical":
					boundary_delta += _rgb_delta(image.get_pixel(boundary_px - 1, offset), image.get_pixel(boundary_px, offset))
					neighbor_delta += 0.5 * (
						_rgb_delta(image.get_pixel(boundary_px - 2, offset), image.get_pixel(boundary_px - 1, offset))
						+ _rgb_delta(image.get_pixel(boundary_px, offset), image.get_pixel(boundary_px + 1, offset)))
				else:
					boundary_delta += _rgb_delta(image.get_pixel(offset, boundary_px - 1), image.get_pixel(offset, boundary_px))
					neighbor_delta += 0.5 * (
						_rgb_delta(image.get_pixel(offset, boundary_px - 2), image.get_pixel(offset, boundary_px - 1))
						+ _rgb_delta(image.get_pixel(offset, boundary_px), image.get_pixel(offset, boundary_px + 1)))
			boundary_delta /= float(sample_count)
			neighbor_delta /= float(sample_count)
			var excess := boundary_delta - neighbor_delta
			boundary_sum += boundary_delta
			excess_sum += excess
			peak_excess = maxf(peak_excess, excess)
			samples.append({
				"axis": axis,
				"index": boundary_index,
				"boundary_rgb": boundary_delta,
				"neighbor_rgb": neighbor_delta,
				"excess_rgb": excess,
			})
	return {
		"sample_count": samples.size(),
		"mean_boundary_rgb": boundary_sum / maxf(float(samples.size()), 1.0),
		"mean_excess_rgb": excess_sum / maxf(float(samples.size()), 1.0),
		"peak_excess_rgb": peak_excess,
		"pass": peak_excess < 3.0,
		"samples": samples,
	}


func _rgb_delta(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * (255.0 / 3.0)


func _finish() -> void:
	print("[MapDetailAtlasQa] %s output=%s" % [
		"PASS" if _failures.is_empty() else "FAIL x%d" % _failures.size(),
		ProjectSettings.globalize_path(OUTPUT_DIR),
	])
	for failure in _failures:
		printerr("[MapDetailAtlasQa] FAIL: %s" % failure)
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)
