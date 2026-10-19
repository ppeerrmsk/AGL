extends RefCounted
const Archive := preload("res://scripts/rendering/ocean_volume_archive.gd")
const Factory := preload("res://scripts/experiments/ocean_volume_factory.gd")
const Builder := preload("res://scripts/tests/build_ocean_volume.gd")
var _fail := 0
var _pass := 0


func run() -> void:
	var clock := preload("res://scripts/tests/map_frame_clock.gd").new()
	clock.observe(false, 100)
	clock.observe(true, 1000)
	clock.observe(true, 17666)
	clock.observe(true, 34333)
	_check(clock.report().samples == 2 and clock.report().below60 == 1, "wall clock rejects 16667us without rounding away slow frames")
	var visual_script: GDScript = load("res://scripts/tests/ocean_volume_visual.gd")
	_check(visual_script != null and visual_script.can_instantiate(), "formal Visual validator compiles")
	var overlay_script: GDScript = load("res://scripts/rendering/ocean_volume_overlay.gd")
	_check(overlay_script != null and overlay_script.can_instantiate(), "production overlay compiles")
	var lifecycle_script: GDScript = load("res://scripts/tests/ocean_volume_lifecycle_case.gd")
	_check(lifecycle_script != null and lifecycle_script.can_instantiate(), "lifecycle validator compiles")
	var combat_script: GDScript = load("res://scripts/tests/ocean_volume_combat.gd")
	_check(combat_script != null and combat_script.can_instantiate(), "combat validator compiles")
	var previous := OS.get_environment("AGL_OCEAN_VOLUME")
	OS.set_environment("AGL_OCEAN_VOLUME", "")
	_check(overlay_script.ocean_enabled("ocean", Archive.DOCUMENT), "built-in ocean defaults to volume")
	_check(not overlay_script.ocean_enabled("ocean", "user://custom.aglmap"), "custom ocean key cannot load built-in layout")
	_check(not overlay_script.ocean_enabled("tokyo", Archive.DOCUMENT), "other map stays independent")
	OS.set_environment("AGL_OCEAN_VOLUME", "off")
	_check(not overlay_script.ocean_enabled("ocean", Archive.DOCUMENT), "explicit 2D rollback")
	OS.set_environment("AGL_OCEAN_VOLUME", previous)
	var doc := MapDocument.load_from(Archive.DOCUMENT)
	var before := FileAccess.get_sha256(Archive.DOCUMENT)
	var archive: Resource = load(Archive.OCEAN_PATH)
	_check(archive != null and archive.valid(), "source fingerprint and 32MiB budget")
	if archive == null:
		return
	var stale: Resource = archive.duplicate()
	stale.data_hash = "stale"
	_check(not stale.valid(), "stale data fails closed in editor and export")
	_check(archive.building_count == 16 and archive.source_buildings == doc.buildings,
		"all source footprints and heights preserved")
	_check(doc.airports.size() == 1 and doc.railways.is_empty(), "ocean source has its sole runway and no desert railway")
	var unsafe := 0
	for band in Factory.service_bands(doc):
		for point in band:
			if not Geometry2D.is_point_in_polygon(point, doc.layer_polygons.land[1]):
				unsafe += 1
	_check(unsafe == 0, "all base service route corners stay within the source island")
	_check(archive.terrain.size() == Builder.tile_layouts(archive.terrain_bounds).size(), "every raster LOD tile has prebuilt terrain")
	var layouts := Builder.tile_layouts(archive.terrain_bounds)
	var height_lookup := {}
	var inconsistent := 0
	var min_y := INF
	var max_y := -INF
	for key: String in layouts:
		var entry: Dictionary = archive.terrain[key]
		_check(entry.bounds == layouts[key].bounds and entry.uv == layouts[key].uv, "tile registration " + key)
		var arrays: Array = entry.mesh.surface_get_arrays(0)
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			min_y = minf(min_y, vertex.y)
			max_y = maxf(max_y, vertex.y)
			var point := Vector2(vertex.x, vertex.z)
			if height_lookup.has(point) and absf(float(height_lookup[point]) - vertex.y) > 0.01:
				inconsistent += 1
			height_lookup[point] = vertex.y
			if Factory.BASE_RECT.has_point(point) and absf(vertex.y + 0.10) > 0.01:
				inconsistent += 1
	_check(inconsistent == 0, "shared terrain nodes agree across all LOD and engineered base is flat")
	_check(min_y >= -0.101 and max_y > 100 and max_y < 175, "sea plane and source-backed natural relief")
	var mesh := Factory.build(doc, true)
	_check(mesh.surface_get_array_len(0) / 3 < 12000, "detailed base triangle budget")
	var tallest := 0.0
	for point: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		tallest = maxf(tallest, point.y)
	_check(absf(tallest - 60.0) < 0.03, "120m source gantry retains its 60px height")
	_check(before == FileAccess.get_sha256(Archive.DOCUMENT), "source document remains read-only")
	print("[Ocean focused] pass=", _pass, " fail=", _fail,
		" geometry_bytes=", archive.geometry_bytes, " height_range=", Vector2(min_y, max_y))


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Ocean volume: " + label)
