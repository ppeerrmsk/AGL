extends RefCounted
const Ground := preload("res://scripts/experiments/volume_satellite_ground.gd")
const MapFactory := preload("res://scripts/experiments/volume_map_factory.gd")
var _pass := 0
var _fail := 0


func run() -> bool:
	var previous_style := OS.get_environment("AGL_DESERT_STYLE")
	OS.set_environment("AGL_DESERT_STYLE", "")
	_check(Ground.TacticalContext.is_enabled("desert") and not Ground.TacticalContext.is_enabled("tokyo_bay")
		and not Ground.TacticalContext.is_enabled("ocean"), "normal launch defaults only desert to tactical style")
	for override_value in ["source", "off", "unknown"]:
		OS.set_environment("AGL_DESERT_STYLE", override_value)
		_check(not Ground.TacticalContext.is_enabled("desert"), "explicit style override preserves source fallback: " + override_value)
	OS.set_environment("AGL_DESERT_STYLE", "source")
	var doc := MapDocument.load_from("res://resources/maps/desert_railway_preview.aglmap")
	var before := JSON.stringify(doc.to_json_dict())
	var packet := MapFactory.build(doc, true, true)
	var old := MapFactory.build(doc)
	_check(packet.ok and packet.ground_mesh.surface_get_array_len(0) < old.ground_mesh.surface_get_array_len(0),
		"satellite removes abstract terrain from the actual ground mesh")
	_check(packet.structure_meshes.size() == 7 and packet.districts == old.districts
		and JSON.stringify(doc.to_json_dict()) == before, "satellite does not change source or building layout")
	var source := RasterBasemapRenderer.new()
	var texture := ImageTexture.create_from_image(Image.create_empty(64, 64, false, Image.FORMAT_RGB8))
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(-100, -200)
	sprite.scale = Vector2(4, 3)
	source._strategic_sprite = sprite
	source.add_child(sprite)
	var ground := Ground.new()
	ground.setup(source)
	_check(ground.debug_state().planes == 1, "one shared strategic plane")
	var plane: MeshInstance3D = ground.get_child(0)
	var material := plane.material_override as ShaderMaterial
	_check(material.get_shader_parameter("map_texture") == texture, "same Texture2D object no duplicate decode")
	_check(material.shader == Ground.OPAQUE_SHADER, "stable terrain uses opaque depth without changing texture")
	var bounds := plane.mesh.get_aabb()
	_check(bounds.position.x == -100 and bounds.position.z == -200
		and bounds.size.x == 256 and bounds.size.z == 192, "exact source world rectangle")
	var a: Array = plane.mesh.surface_get_arrays(0)
	_check(a[Mesh.ARRAY_TEX_UV][0] == Vector2.ZERO and a[Mesh.ARRAY_TEX_UV][2] == Vector2.ONE,
		"texture UV is not rotated or mirrored")
	var layer := Node2D.new()
	source.add_child(layer)
	var tile := Sprite2D.new()
	tile.texture = texture
	tile.region_enabled = true
	tile.region_rect = Rect2(16, 16, 32, 32)
	tile.scale = Vector2(4, 3)
	layer.add_child(tile)
	source._layers[&"detail"] = layer
	source._sprites[&"detail"] = {"tile": tile}
	ground.sync(0.11)
	var tile_plane: MeshInstance3D = ground.get_child(1)
	var tile_arrays: Array = tile_plane.mesh.surface_get_arrays(0)
	_check(tile_arrays[Mesh.ARRAY_TEX_UV][0] == Vector2(0.25, 0.25)
		and tile_arrays[Mesh.ARRAY_TEX_UV][2] == Vector2(0.75, 0.75), "gutter excluded without world expansion")
	layer.modulate.a = 0.5
	tile.modulate.a = 0.6
	layer.z_index = 2
	ground.sync(0.01)
	_check(is_equal_approx(tile_plane.material_override.get_shader_parameter("opacity"), 0.3)
		and tile_plane.material_override.render_priority == -80, "source alpha-over transition order preserved")
	_check(tile_plane.material_override.shader == Ground.SHADER, "fractional opacity retains original blended shader")
	layer.modulate.a = 1.0
	tile.modulate.a = 1.0
	ground.sync(0.01)
	_check(tile_plane.material_override.shader == Ground.OPAQUE_SHADER
		and tile_plane.material_override.get_shader_parameter("map_texture") == texture,
		"transition completion restores depth with all material parameters retained")
	layer.hide()
	ground.sync(0.01)
	_check(not tile_plane.visible, "hidden source LOD not duplicated")
	source._sprites[&"detail"].clear()
	tile.free()
	ground.sync(0.01)
	_check(ground.debug_state().planes == 1, "freed tile releases bridge before next resource tick")
	source.free()
	ground.sync(0.11)
	_check(ground.debug_state().planes == 0, "released owner clears remaining mesh and texture bindings")
	ground.free()
	_test_detail_material(texture)
	_test_satellite_profile(texture)
	_test_tactical_profile(texture)
	_check(Ground.cover_lod_far(false, 0.15) and not Ground.cover_lod_far(false, 0.151)
		and Ground.cover_lod_far(true, 0.199) and not Ground.cover_lod_far(true, 0.20)
		and not Ground.cover_lod_far(true, INF), "cover LOD enter/exit hysteresis and missing-camera fallback")
	var view := Basis(Vector3.RIGHT, -PI / 3.0)
	_check(is_equal_approx(Ground.cover_error_pixels(view, Basis.IDENTITY, 1000, 2000), 0.125)
		and is_equal_approx(Ground.cover_error_pixels(view, Basis.IDENTITY, 2000, 2000), 0.25)
		and is_equal_approx(Ground.cover_error_pixels(view, Basis.IDENTITY.scaled(Vector3.ONE * 2), 1000, 2000), 0.25),
		"cover projection respects camera tilt render-target resolution and world scaling")
	print("[Volume satellite] pass=%d fail=%d" % [_pass, _fail])
	OS.set_environment("AGL_DESERT_STYLE", previous_style)
	return _fail == 0


func _test_detail_material(texture: Texture2D) -> void:
	var source := RasterBasemapRenderer.new()
	var sprite := Sprite2D.new()
	sprite.name = "StrategicBasemap"
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(1, 1, 62, 62)
	sprite.position = Vector2(-100, -200)
	sprite.scale = Vector2(4, 3)
	sprite.self_modulate = Color(0.8, 0.8, 0.8)
	source._strategic_sprite = sprite
	source.add_child(sprite)
	var ground := Ground.new()
	ground.enable_relief()
	ground.setup(source)
	var shared: ShaderMaterial
	var count := 0
	var valid := true
	for detail: MeshInstance3D in ground._details.get_children():
		if not String(detail.name).begins_with("Scrub_"):
			continue
		if shared == null:
			shared = detail.material_override as ShaderMaterial
		valid = valid and shared != null and detail.material_override == shared
		count += 1
	_check(valid and count == 16 and shared.shader == Ground.DECORATION_SHADER
		and shared.get_shader_parameter("map_texture") == texture,
		"sixteen static detail batches borrow one material and the original resident texture")
	_check(shared.get_shader_parameter("decoration_world_rect") == Vector4(-100, -200, 248, 186)
		and shared.get_shader_parameter("decoration_uv_rect") == Vector4(1.0/64, 1.0/64, 62.0/64, 62.0/64)
		and is_equal_approx(shared.get_shader_parameter("luma_scale"), 0.8),
		"decoration projection retains source offset scale gutter and luminance")
	var rock_texture: Texture2D = shared.get_shader_parameter("rock_texture")
	var rock_image := rock_texture.get_image()
	var mean_srgb: Vector3 = rock_texture.get_meta("mean_srgb")
	var mean_linear: Vector3 = rock_texture.get_meta("mean_linear")
	_check(mean_srgb.is_finite() and mean_linear.is_finite() and mean_srgb.x > mean_linear.x
		and mean_linear.z > 0.01 and mean_srgb.x < 1.0
		and shared.get_shader_parameter("rock_mean_srgb") == mean_srgb
		and shared.get_shader_parameter("rock_mean_linear") == mean_linear,
		"prebuilt albedo carries separate sRGB and linear means with matching shader bindings")
	_check(rock_texture.get_size() == Vector2(512, 512) and rock_image.has_mipmaps()
		and rock_image.get_data().size() <= Ground.ROCK_TEXTURE_BUDGET_BYTES,
		"one prebuilt mipmapped rock texture fits its separate 1.34 MiB budget")
	var terrain_plane: MeshInstance3D = ground.get_child(1)
	var terrain_material: ShaderMaterial = terrain_plane.material_override as ShaderMaterial
	_check(terrain_material.get_shader_parameter("terrain_detail_enabled")
		and terrain_material.get_shader_parameter("terrain_detail_texture") == rock_texture
		and terrain_material.get_shader_parameter("terrain_detail_mean_linear") == mean_linear
		and terrain_material.get_shader_parameter("terrain_detail_mean_srgb") == mean_srgb,
		"ground reuses the existing rock texture for bounded satellite microdetail")
	var clean_texture: Texture2D = terrain_material.get_shader_parameter("clean_terrain_texture")
	var clean_image := clean_texture.get_image()
	var relief_rect: Rect2 = ground.relief.rect
	_check(terrain_material.get_shader_parameter("clean_terrain_enabled")
		and clean_texture == ground._clean_terrain_texture
		and terrain_material.get_shader_parameter("clean_terrain_world_rect") == Vector4(
			relief_rect.position.x, relief_rect.position.y, relief_rect.size.x, relief_rect.size.y)
		and terrain_material.get_shader_parameter("legacy_runway_start") == Ground.LEGACY_RUNWAY_START
		and terrain_material.get_shader_parameter("legacy_runway_end") == Ground.LEGACY_RUNWAY_END,
		"legacy airport repair binds one clean-terrain texture to the audited runway")
	var airport_boundary := PackedVector2Array(Ground.LEGACY_AIRPORT_BOUNDARY)
	var runway_inside := true
	for step in 17:
		runway_inside = runway_inside and Geometry2D.is_point_in_polygon(
			Ground.LEGACY_RUNWAY_START.lerp(Ground.LEGACY_RUNWAY_END, float(step) / 16.0), airport_boundary)
	_check(runway_inside and not Geometry2D.is_point_in_polygon(Vector2(7680, 4000), airport_boundary)
		and terrain_material.get_shader_parameter("legacy_airport_boundary") == airport_boundary,
		"airport feature mask contains the audited runway and excludes the western road corridor")
	_check(clean_texture.get_size() == Vector2(1254, 1254) and clean_image.has_mipmaps()
		and clean_image.get_data().size() <= Ground.CLEAN_TERRAIN_TEXTURE_BUDGET_BYTES,
		"clean-terrain texture is prebuilt mipmapped and fits its separate 8 MiB budget")
	# ShaderMaterial 是 RefCounted；生命周期断言前释放测试自身的强引用。
	terrain_material = null
	var rock_ref: WeakRef = weakref(rock_texture)
	var clean_ref: WeakRef = weakref(clean_texture)
	rock_texture = null
	rock_image = null
	clean_texture = null
	clean_image = null
	var original: Node = ground.relief.archive.details.instantiate()
	valid = true
	for detail: MeshInstance3D in original.get_children():
		if String(detail.name).begins_with("Scrub_"):
			valid = valid and detail.material_override is StandardMaterial3D
	_check(valid, "runtime material binding never mutates the reusable packed archive")
	original.free()
	ground._apply_cover_lod(true)
	ground._apply_cover_lod(true)
	valid = true
	for detail: MeshInstance3D in ground._details.get_children():
		if detail.has_meta("cover_far_mesh"):
			valid = valid and detail.mesh == detail.get_meta("cover_far_mesh") and detail.material_override == shared
	_check(valid and ground.debug_state().cover_lod_swaps == 1,
		"far switch reuses sixteen prebuilt meshes and material without repeat writes")
	ground._apply_cover_lod(false)
	valid = true
	for detail: MeshInstance3D in ground._details.get_children():
		if detail.has_meta("cover_near_mesh"):
			valid = valid and detail.mesh == detail.get_meta("cover_near_mesh")
	_check(valid and ground.debug_state().cover_lod_swaps == 2, "near switch restores original crown geometry")
	var material_ref: WeakRef = weakref(shared)
	shared = null
	source.free()
	ground.sync(0.11)
	_check(ground._details == null and ground.get_child_count() == 0 and material_ref.get_ref() == null,
		"owner retirement releases detail material and borrowed texture binding")
	_check(rock_ref.get_ref() == null, "owner retirement releases the additional rock material texture too")
	_check(clean_ref.get_ref() == null, "owner retirement releases the clean-terrain repair texture too")
	ground.free()


func _test_satellite_profile(texture: Texture2D) -> void:
	_check(RasterBasemapRenderer.map_root_for("desert", "sentinel").ends_with("/desert_satellite")
		and RasterBasemapRenderer.map_root_for("desert").ends_with("/desert")
		and RasterBasemapRenderer.map_root_for("ocean", "sentinel").ends_with("/ocean")
		and RasterBasemapRenderer.map_root_for("tokyo", "sentinel").ends_with("/tokyo")
		and RasterBasemapRenderer.map_root_for("desert", "../bad").ends_with("/desert"),
		"satellite source selection is explicit desert-only and rejects arbitrary selectors")
	var source := RasterBasemapRenderer.new()
	source._manifest = {"volume_profile": {"source_kind": "satellite", "saturation": 0.9}}
	source._map_key = "desert"
	var copy := source.presentation_profile()
	copy["saturation"] = 0.1
	_check(source.presentation_profile().saturation == 0.9, "presentation profile is a copy of source authority")
	var sprite := Sprite2D.new()
	sprite.name = "StrategicBasemap"
	sprite.texture = texture
	source._strategic_sprite = sprite
	source.add_child(sprite)
	var ground := Ground.new()
	ground.enable_relief()
	ground.setup(source)
	var plane: MeshInstance3D = ground.get_child(1)
	_check(source.shared_strategic_texture("desert") == texture
		and source.shared_strategic_texture("ocean") == null,
		"Strategic accessor borrows the original texture only for its own map")
	var material: ShaderMaterial = plane.material_override
	_check(ground.debug_state().source_kind == "satellite"
		and material.get_shader_parameter("source_is_satellite")
		and is_equal_approx(material.get_shader_parameter("saturation"), 0.9)
		and not material.get_shader_parameter("clean_terrain_enabled")
		and not material.get_shader_parameter("terrain_detail_enabled")
		and material.get_shader_parameter("map_texture") == texture,
		"satellite terrain uses source color without CARTO airport repair or fake microtexture")
	var valid := true
	for detail: MeshInstance3D in ground._details.get_children():
		if String(detail.name).begins_with("Scrub_"):
			valid = valid and detail.material_override.get_shader_parameter("source_is_satellite")
	_check(valid and not ground._details.get_node("Source_Water_EvenOdd_Fill").visible,
		"satellite decorations share the source profile and leave real water in the imagery")
	_check(ground.debug_state().outcrops == 360,
		"explicit source presentation retains the complete original decoration variant")
	var original: Node = ground.relief.archive.details.instantiate()
	_check(original.get_node("Source_Water_EvenOdd_Fill").visible, "satellite water override does not mutate packed terrain")
	original.free()
	source.free()
	ground.sync(0.11)
	_check(ground._source_profile.is_empty() and ground.get_child_count() == 0, "satellite profile retires with its owner")
	ground.free()


func _test_tactical_profile(texture: Texture2D) -> void:
	var previous := OS.get_environment("AGL_DESERT_STYLE")
	OS.set_environment("AGL_DESERT_STYLE", "tactical")
	var source := RasterBasemapRenderer.new()
	source._map_key = "desert"
	source._manifest = {"volume_profile": {"source_kind": "satellite"}}
	var sprite := Sprite2D.new()
	sprite.name = "StrategicBasemap"
	sprite.texture = texture
	var layout: Dictionary = Ground.Relief.Archive.tile_layouts().StrategicBasemap
	sprite.centered = false
	sprite.position = layout.bounds.position
	sprite.scale = layout.bounds.size / Vector2(texture.get_size())
	source._strategic_sprite = sprite
	source.add_child(sprite)
	var ground := Ground.new()
	ground.enable_relief()
	ground.setup(source)
	var doc := MapDocument.load_from("res://resources/maps/desert_railway_preview.aglmap")
	var before := JSON.stringify(doc.to_json_dict())
	var packet := MapFactory.build(doc, true, true)
	OS.set_environment("AGL_DESERT_STYLE", previous)
	var plane: MeshInstance3D = ground.get_child(1)
	_check(ground.debug_state().visual_style == "tactical" and plane.material_override.shader == Ground.TACTICAL_OPAQUE_SHADER,
		"tactical terrain uses the native matte shader through the same source owner")
	_check(ground.debug_state().outcrops == 0 and ground.debug_state().vegetation == 1200,
		"actual tactical owner chooses the prebuilt low-density variant without removing ground cover")
	var warmup: SubViewport = ground.get_node("MaterialWarmup")
	var warm_sample: MeshInstance3D = warmup.get_node("MaterialSample")
	_check(warmup.size == Vector2i(32, 32) and warmup.own_world_3d and not warmup.is_processing()
		and warm_sample.material_override.shader == Ground.TacticalContext.SHADER
		and warm_sample.mesh.surface_get_array_len(0) == 72
		and warm_sample.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != null,
		"warmup is bounded and reuses the actual tactical material with matching colored mesh format")
	_check(plane.mesh == ground.relief.archive.entries.StrategicBasemap.mesh
		and plane.position == Vector3(0, Ground.TACTICAL_SURFACE_LIFT, 0)
		and ground.debug_state().archive_misses == 0,
		"native ground reuses the full-resolution archive at the original detail surface height")
	var layer := Node2D.new()
	source.add_child(layer)
	var tile := Sprite2D.new()
	tile.texture = texture
	layer.add_child(tile)
	source._layers[&"detail"] = layer
	source._sprites[&"detail"] = {"tile": tile}
	sprite.hide()
	sprite.modulate.a = 0.0
	layer.modulate.a = 0.5
	ground.sync(0.11)
	_check(ground.debug_state().planes == 1 and ground.debug_state().surface_mode == "native_full"
		and plane.visible and plane.material_override.shader == Ground.TACTICAL_OPAQUE_SHADER,
		"native surface remains complete and opaque while photo tiles arrive and fade, without duplicate ground")
	var shader_text := FileAccess.get_file_as_string("res://resources/shaders/volume_desert_tactical_surface.gdshaderinc")
	_check(not shader_text.contains("texture(") and not shader_text.contains("sampler2D"),
		"tactical ground has no photograph or grain sampler, not a photographic color filter")
	var near_triangles := 0
	var far_triangles := 0
	var cells := 0
	var valid := true
	var context_palette_counts := {"roof": 0, "wall": 0, "road": 0}
	var observed_colors := {}
	var context_palette_valid := true
	for detail: MeshInstance3D in ground._details.get_children():
		if detail.has_meta("context_near_mesh"):
			cells += 1
			near_triangles += detail.mesh.surface_get_array_len(0) / 3
			var far_mesh: ArrayMesh = detail.get_meta("context_far_mesh")
			far_triangles += far_mesh.surface_get_array_len(0) / 3
			valid = valid and float(detail.get_meta("context_height_error")) >= 1.6
			valid = valid and detail.get_child_count() == 0
			for context_mesh: ArrayMesh in [detail.mesh, far_mesh]:
				var colors: PackedColorArray = context_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
				for color: Color in colors:
					var observed_key := color.to_html(false)
					observed_colors[observed_key] = int(observed_colors.get(observed_key, 0)) + 1
					# 与正式整数色板逐通道完全一致，不用容差掩盖角色变化。
					var key := ""
					if color == Color("b9b1a0"):
						key = "roof"
					elif color == Color("797466"):
						key = "wall"
					elif color == Color("73786f"):
						key = "road"
					context_palette_valid = context_palette_valid and context_palette_counts.has(key) and color.a == 1.0
					if context_palette_counts.has(key):
						context_palette_counts[key] += 1
		elif String(detail.name).begins_with("Scrub_"):
			valid = valid and detail.material_override.shader == Ground.TACTICAL_DECORATION_SHADER
	_check(valid and cells == 4 and near_triangles == 39601 and far_triangles == 13223
		and near_triangles <= Ground.TacticalContext.TRIANGLE_BUDGET,
		"four bounded native districts retain source roofs/walls and height-aware far resources")
	print("[Tactical palette channels] ", observed_colors, " classified=", context_palette_counts)
	_check(context_palette_valid and context_palette_counts == {"roof": 50730, "wall": 79134, "road": 28608},
		"near/far background roofs and walls use restrained opaque colors; every original road color is retained")
	var water: MeshInstance3D = ground._details.get_node("Source_Water_EvenOdd_Fill")
	_check(water.visible and not water.material_override.get_shader_parameter("sediment_enabled"),
		"tactical water retains its geographic contour without sediment grain")
	var root := MeshInstance3D.new()
	MapFactory.configure_instance(root, packet, StandardMaterial3D.new())
	_check(packet.tactical_style and root.get_child(1).material_override.shader == MapFactory.TACTICAL_STRUCTURE_SHADER
		and JSON.stringify(doc.to_json_dict()) == before, "tactical structures share matte presentation without changing source coordinates")
	root.free()
	_test_road_joins(ground, doc)
	source.free()
	ground.sync(0.11)
	_check(ground.get_child_count() == 0 and not ground._tactical_style,
		"native districts and presentation selection retire with the original owner")
	ground.free()


func _test_road_joins(ground: Node3D, doc: MapDocument) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Ground.TacticalContext.PATH))
	var valid: bool = data.road_clip_footprints.size() == doc.buildings.size()
	for clip: Dictionary in data.road_clip_footprints:
		var source := MapFactory.Geometry.points_from(doc.buildings[int(clip.building_index)].footprint)
		var tank := source.size() == 8
		var scale_value := 1.24 if tank else (1.06 if float(MapFactory.Buildings.frame(source).length) >= 70.0 else 1.14)
		var expected := MapFactory.Buildings.scaled_polygon(source, scale_value)
		var actual := MapFactory.Geometry.points_from(clip.outline)
		valid = valid and actual.size() == expected.size() and float(clip.outer_margin) == (0.8 if tank else 0.0)
		for i in mini(actual.size(), expected.size()):
			valid = valid and actual[i].distance_to(expected[i]) < 0.002
	_check(valid, "road cut footprints match actual GDScript facility pads and bund half-width, not building clearance")
	var road_vertices := PackedVector2Array()
	var road_palette_valid := true
	var checked_road_vertices := 0
	for key: String in data.cells:
		var node: MeshInstance3D = ground._details.get_node("TacticalContext_" + key)
		var near_arrays := node.mesh.surface_get_arrays(0)
		var far_arrays: Array = node.get_meta("context_far_mesh").surface_get_arrays(0)
		var vertices: PackedVector3Array = near_arrays[Mesh.ARRAY_VERTEX]
		var far_vertices: PackedVector3Array = far_arrays[Mesh.ARRAY_VERTEX]
		var road_count: int = data.cells[key].roads.size()
		for i in range(vertices.size() - road_count, vertices.size()):
			var offset := i - (vertices.size() - road_count)
			var far_index := far_vertices.size() - road_count + offset
			var point := Vector2(vertices[i].x, vertices[i].z)
			var source_match := false
			for j in 3:
				var raw: Array = data.cells[key].roads[(offset / 3) * 3 + j]
				source_match = source_match or point == Vector2(raw[0], raw[1])
			road_palette_valid = road_palette_valid and source_match and vertices[i] == far_vertices[far_index]
			road_palette_valid = road_palette_valid and near_arrays[Mesh.ARRAY_NORMAL][i] == far_arrays[Mesh.ARRAY_NORMAL][far_index]
			road_palette_valid = road_palette_valid and near_arrays[Mesh.ARRAY_COLOR][i] == Color("73786f")
			road_palette_valid = road_palette_valid and far_arrays[Mesh.ARRAY_COLOR][far_index] == Color("73786f")
			road_palette_valid = road_palette_valid and absf(vertices[i].y - (ground.relief.height_at(point) + 0.04)) < 0.001
			checked_road_vertices += 1
			road_vertices.append(Vector2(vertices[i].x, vertices[i].z))
	_check(road_palette_valid and checked_road_vertices == 14304,
		"all background roads retain source geometry, draped height, normals and original color in both LODs")
	var covered := 0
	for join: Dictionary in data.road_joins:
		var point := Vector2(join.point[0], join.point[1])
		var found := false
		for i in range(0, road_vertices.size(), 3):
			var triangle := PackedVector2Array([road_vertices[i], road_vertices[i + 1], road_vertices[i + 2]])
			if Geometry2D.is_point_in_polygon(point, triangle):
				found = true
			else:
				for edge in 3:
					found = found or point.distance_to(Geometry2D.get_closest_point_to_segment(point,
						triangle[edge], triangle[(edge + 1) % 3])) < 0.002
			if found:
				break
		covered += int(found)
	_check(covered == data.road_joins.size() and covered > 0,
		"every clipped source street reaches its pad edge in actual Float32 render geometry")
	print("[Tactical road joins] covered=%d/%d" % [covered, data.road_joins.size()])


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Volume satellite: " + label)
