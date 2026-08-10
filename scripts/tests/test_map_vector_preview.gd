extends RefCounted

## V44 运行时资源、暖灰纸板色族、常驻高层地标与静态 packet 预算守门。
## headless 不评判画面，只验证数据完整、LOD 可构建且 draw-call 上界稳定。

var _fail := 0
const Renderer = preload("res://scripts/survivor/map_vector_preview_renderer.gd")
const BuildingPreloaderScript = preload("res://scripts/survivor/building_preloader.gd")
const DetailTileCache = preload("res://scripts/survivor/map_detail_tile_cache.gd")


func run() -> void:
	var density_colors := [
		Renderer.DENSITY_URBAN,
		Renderer.DENSITY_VEGETATION,
		Renderer.DENSITY_INDUSTRIAL,
	]
	var density_min_distance := INF
	var density_max_distance := 0.0
	for index in range(density_colors.size()):
		_check(_is_warm_paper(density_colors[index]),
			"density palette anchor %d stays in the warm paper family" % index)
		for other in range(index + 1, density_colors.size()):
			var distance := _rgb_distance(density_colors[index], density_colors[other])
			density_min_distance = minf(density_min_distance, distance)
			density_max_distance = maxf(density_max_distance, distance)
	_check(density_min_distance >= 0.02 and density_max_distance <= 0.08,
		"density channels keep subtle value separation without blue/green/orange patchwork")
	_check(DetailTileCache.detail_opacity_for_zoom(0.50) <= 0.001
			and DetailTileCache.detail_opacity_for_zoom(0.65) > 0.06
			and DetailTileCache.detail_opacity_for_zoom(0.65) < 0.10
			and DetailTileCache.detail_opacity_for_zoom(0.80) > 0.45
			and DetailTileCache.detail_opacity_for_zoom(0.80) < 0.55
			and DetailTileCache.detail_opacity_for_zoom(0.98) >= 0.999,
		"Detail uses a perceptual fade curve instead of exposing the full texture at medium zoom")
	var validation: Dictionary = Renderer.validate_preview_data()
	_check(bool(validation.get("ok", false)), "preview JSON schema/counts valid: %s" % validation)
	_check(Renderer.smoke_submit_triangle_array(), "Godot 4.7 triangle-array submission succeeds")
	if not bool(validation.get("ok", false)):
		return

	var world_rect := Rect2(Vector2(-15000.0, -15000.0), Vector2(30000.0, 30000.0))
	var first_prewarm: Dictionary = Renderer.prewarm_lod(Renderer.LOD_OPERATIONAL, world_rect)
	var cached_prewarm: Dictionary = Renderer.prewarm_lod(Renderer.LOD_OPERATIONAL, world_rect)
	_check(bool(first_prewarm.get("ok", false)),
		"loading-stage Operational prewarm succeeds in %dms" % int(first_prewarm.get("build_ms", -1)))
	_check(int(first_prewarm.get("build_ms", 99999)) <= 1600,
		"Operational loading prewarm stays within the local 1.60s target")
	_check(bool(cached_prewarm.get("cache_hit", false)),
		"second Operational request reuses cached packet definitions")
	_check(bool(Renderer.prewarm_lod(Renderer.LOD_TAB, world_rect).get("ok", false)),
		"loading-stage Tab prewarm succeeds")
	for lod in [
		Renderer.LOD_STRATEGIC,
		Renderer.LOD_OPERATIONAL,
		Renderer.LOD_DETAIL,
		Renderer.LOD_TAB,
	]:
		var metrics: Dictionary = Renderer.inspect_lod(lod, world_rect)
		_check(bool(metrics.get("ok", false)), "LOD%d builds: %s" % [lod, metrics])
		_check(int(metrics.get("draw_calls", 999)) <= 26,
			"LOD%d draw calls <=26 (got %s)" % [lod, metrics.get("draw_calls", "?")])
		_check(int(metrics.get("triangles", 0)) > 100,
			"LOD%d has non-trivial geometry (got %s triangles)" % [lod, metrics.get("triangles", "?")])
		var layer_triangles: Dictionary = metrics.get("layer_triangles", {})
		if lod == Renderer.LOD_STRATEGIC:
			_check(int(layer_triangles.get("road_core", 0)) > 3000,
				"Strategic keeps a readable primary/secondary road skeleton")
			_check(int(layer_triangles.get("urban", 0)) > 130000,
				"Strategic includes the smooth OSM-derived urban mass field")
			_check(int(layer_triangles.get("industrial", 0)) == 0,
				"Strategic omits per-building AGOB salt points")
		elif lod == Renderer.LOD_OPERATIONAL:
			_check(int(layer_triangles.get("terrain_context", 0)) >= 5000,
				"Operational keeps one batched low-frequency terrain-context layer")
			_check(int(metrics.get("terrain_context_water_hits", -1)) == 0,
				"terrain-context triangle centroids never land in visual water")
			_check(int(layer_triangles.get("landmark", 0)) >= 25000
				and int(layer_triangles.get("landmark", 0)) <= 35000,
				"Operational keeps the deduplicated >=80m pseudo-3D landmark packet")
			_check(int(layer_triangles.get("building_wall", 0)) >= 90000
				and int(layer_triangles.get("building_wall", 0)) <= 105000,
				"Operational restores one batched pseudo-3D wall layer for large buildings")
			_check(int(layer_triangles.get("road_core", 0)) > 135000,
				"Operational keeps tertiary plus the quota-limited neighbourhood skeleton")
			_check(int(layer_triangles.get("road_casing", 0)) < 60000,
				"Operational reserves casing for major roads; neighbourhood fabric is single-core")
			_check(int(layer_triangles.get("building_casing", 0)) >= 90000
				and int(layer_triangles.get("building_casing", 0)) <= 115000,
				"Operational keeps only large-building casings within the FPS budget")
			_check(int(layer_triangles.get("urban", 0)) > 140000,
				"Operational merges exact districts with the smooth OSM-derived mass field")
			_check(int(layer_triangles.get("industrial", 0)) >= 90000
				and int(layer_triangles.get("industrial", 0)) <= 115000,
				"Operational submits only summarized large-building roofs")
			_check(int(metrics.get("triangles", 0)) <= 1300000,
				"Operational stays inside the FPS-first static-triangle budget")
		elif lod == Renderer.LOD_TAB:
			_check(int(layer_triangles.get("industrial", 0)) == 0,
				"Tab omits per-building AGOB salt points")
		_check(int(layer_triangles.get("water", 0)) > 100,
			"LOD%d water topology triangulates (got %s triangles)" % [lod, layer_triangles.get("water", 0)])
		var failed_water_rings: Array = metrics.get("failed_water_rings", [])
		var largest_failed_area := 0.0
		for failure_any in failed_water_rings:
			largest_failed_area = maxf(largest_failed_area, float((failure_any as Dictionary).get("area_px2", 0.0)))
		_check(largest_failed_area < 10000.0,
			"LOD%d has no failed major water ring (largest failed area=%s, failures=%s)" % [
				lod, largest_failed_area, failed_water_rings])

	_test_loading_scene_and_stable_zoom(world_rect)

	print("[MapVectorPreviewTest] %s" % ("PASS" if _fail == 0 else "FAIL x%d" % _fail))


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_fail += 1
		printerr("  FAIL: %s" % message)


func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _is_warm_paper(color: Color) -> bool:
	var red_green := (color.r - color.g) * 255.0
	var green_blue := (color.g - color.b) * 255.0
	return red_green >= -0.5 and red_green <= 10.5 \
		and green_blue >= 4.5 and green_blue <= 16.5


func _test_loading_scene_and_stable_zoom(world_rect: Rect2) -> void:
	var preloader_scene := load("res://scenes/building_preloader.tscn") as PackedScene
	var preloader_instance := preloader_scene.instantiate() if preloader_scene != null else null
	_check(preloader_instance != null, "building_preloader scene instantiates with vector prewarm script")
	if preloader_instance != null:
		preloader_instance.free()

	var camera := Camera2D.new()
	var renderer := Renderer.new()
	camera.zoom = Vector2(0.35, 0.35)
	_check(renderer.setup(camera, world_rect), "runtime renderer binds prewarmed definitions")
	var operational := renderer.get_node_or_null("VectorMapLOD1") as Node2D
	_check(renderer.current_lod() == Renderer.LOD_OPERATIONAL
		and operational != null and operational.visible,
		"main preview starts on the stable Operational root")
	camera.zoom = Vector2(0.20, 0.20)
	renderer.update_lod(0.01)
	_check(renderer.current_lod() == Renderer.LOD_OPERATIONAL,
		"zooming out does not swap or alpha-blend a full-map root")
	var building_wall: CanvasItem = null
	var building_casing: CanvasItem = null
	var industrial: CanvasItem = null
	var urban: CanvasItem = null
	var landmark: CanvasItem = null
	var terrain_context: CanvasItem = null
	for child in operational.get_children():
		if child.name.ends_with("_building_wall"):
			building_wall = child
		elif child.name.ends_with("_building_casing"):
			building_casing = child
		elif child.name.ends_with("_industrial"):
			industrial = child
		elif child.name.ends_with("_urban"):
			urban = child
		elif child.name.ends_with("_landmark"):
			landmark = child
		elif child.name.ends_with("_terrain_context"):
			terrain_context = child
	_check(building_wall != null and building_casing != null and industrial != null and urban != null
			and landmark != null and terrain_context != null,
		"Operational exposes staged mass/roof/depth packets without per-building nodes")
	camera.zoom = Vector2(0.10, 0.10)
	renderer.update_lod(0.01)
	_check(building_wall != null and building_casing != null and industrial != null
			and building_wall.modulate.a <= 0.001
			and building_casing.modulate.a <= 0.001 and industrial.modulate.a <= 0.001
			and urban != null and urban.modulate.a >= 0.999
			and landmark != null and is_equal_approx(landmark.modulate.a, 1.0)
			and terrain_context != null and is_equal_approx(terrain_context.modulate.a, 1.0)
			and is_equal_approx(operational.modulate.a, 1.0),
		"far zoom keeps city mass, terrain context and important landmarks while removing ordinary roof/depth")
	camera.zoom = Vector2(0.35, 0.35)
	renderer.update_lod(0.01)
	_check(building_wall != null and building_casing != null and industrial != null
			and building_wall.modulate.a < 0.02
			and building_casing.modulate.a < 0.02
			and industrial.modulate.a > 0.10 and industrial.modulate.a < 0.20
			and urban != null and urban.modulate.a > 0.65 and urban.modulate.a < 0.85,
		"medium zoom replaces part of the mass with roofs before adding depth")
	camera.zoom = Vector2(0.55, 0.55)
	renderer.update_lod(0.01)
	_check(building_wall != null and building_casing != null and industrial != null
			and building_wall.modulate.a > 0.35 and building_wall.modulate.a < 0.45
			and building_casing.modulate.a > 0.35 and building_casing.modulate.a < 0.45
			and industrial.modulate.a > 0.54 and industrial.modulate.a <= Renderer.OP_ROOF_MAX_OPACITY
			and urban != null and urban.modulate.a > Renderer.OP_MASS_MIN_OPACITY,
		"close Operational holds translucent roofs and partial low-relief edges")
	camera.zoom = Vector2(0.74, 0.74)
	renderer.update_lod(0.01)
	_check(building_wall != null and building_casing != null
			and is_equal_approx(building_wall.modulate.a, Renderer.OP_DEPTH_MAX_OPACITY)
			and is_equal_approx(building_casing.modulate.a, Renderer.OP_DEPTH_MAX_OPACITY)
			and industrial != null and is_equal_approx(industrial.modulate.a, Renderer.OP_ROOF_MAX_OPACITY)
			and urban != null and is_equal_approx(urban.modulate.a, Renderer.OP_MASS_MIN_OPACITY),
		"Operational stops at a translucent low-relief scaffold before full Detail")
	camera.zoom = Vector2(0.90, 0.90)
	renderer.update_lod(0.01)
	_check(renderer.current_lod() == Renderer.LOD_OPERATIONAL
		and renderer.get_node_or_null("VectorMapLOD2") == null
		and operational != null and is_equal_approx(operational.modulate.a, 1.0)
		and landmark != null and is_equal_approx(landmark.modulate.a, 1.0)
		and terrain_context != null and is_equal_approx(terrain_context.modulate.a, 1.0),
		"zooming in keeps one opaque root plus stable terrain and landmark layers")
	renderer.free()
	camera.free()
