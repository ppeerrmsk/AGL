extends RefCounted
const GeoProjection := preload("res://scripts/experiments/tokyo_raster_projection.gd")
const Static := preload("res://scripts/tests/tokyo_tile_ground_review.gd")
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")


static func run(battle: Node,map: Node,output: String) -> int:
	var tree := battle.get_tree()
	var paused := tree.paused
	var source: RasterBasemapRenderer = battle._map_features._raster_basemap
	var mode := source.process_mode
	var ignore: bool = battle.camera.ignore_rotation
	var meta := GeoProjection.metadata()
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	tree.paused = true
	source.process_mode = Node.PROCESS_MODE_ALWAYS
	battle.camera.ignore_rotation = false
	var fail := 0
	var rows: Array = []
	for pose: Vector2 in [Vector2(.26,0),Vector2(.65,0),Vector2(.98,0),Vector2(.65,14)]:
		battle.camera.position = Vector2(-6000,-3500)
		battle.camera.zoom = Vector2.ONE*pose.x
		battle.camera.rotation = deg_to_rad(pose.y)
		battle.camera.force_update_scroll()
		await tree.create_timer(.3).timeout
		var deadline := Time.get_ticks_msec()+15000
		while not Session.state_ready(map.debug_state()) and Time.get_ticks_msec()<deadline:
			await tree.process_frame
		if not Session.state_ready(map.debug_state()) or not await Static._wait_source(source,tree):
			fail += 1
			continue
		map.set_process(false)
		map._release_tile_ground()
		var stem := output.path_join("r81_%02d" % rows.size())
		var before := await Capture._capture(battle,map,stem+"_original")
		var held: Array[Dictionary] = []
		for batch: Dictionary in map._batches.values():
			var node: MeshInstance3D = batch.nodes[2]
			held.append({"node":node,"visible":node.visible,"mesh":node.mesh})
			node.hide()
		await Capture._capture(battle,map,stem+"_buildings")
		var records: Array = []
		for corrected: bool in [false,true]:
			var record := await snapshot(battle,map,source,meta,corrected,stem)
			records.append(record)
			fail += int(record.anchor_error>.05)
		for entry: Dictionary in held:
			entry.node.visible = entry.visible
			fail += int(entry.node.mesh!=entry.mesh)
		var restored := await Capture._capture(battle,map,stem+"_restored")
		var error := Pixels._pixel_error(before,restored)
		fail += int(error>1 or var_to_bytes(BuildingRenderer._cache_entries)!=collision)
		rows.append({"pose":str(pose),"snapshots":records,"restore_error":error})
		print("[R81 projection] pose=",pose," data=",records," restore=",error)
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
	tree.paused = paused
	source.process_mode = mode
	battle.camera.ignore_rotation = ignore
	var file := FileAccess.open(output.path_join("r81_review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail":fail,"rows":rows,"static_only":true,"default_unchanged":true},"\t"))
	file.close()
	return fail


static func snapshot(battle: Node,map: Node,source: RasterBasemapRenderer,meta: Dictionary,corrected: bool,stem: String) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = map._viewport.size
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	battle.get_tree().root.add_child(viewport)
	var scale_value: Vector2 = Vector2(viewport.size)/battle.get_viewport().get_visible_rect().size
	var stretch := Transform2D.IDENTITY.scaled(scale_value)
	var faces := 0
	var anchor_error := 0.0
	var old_offset := 0.0
	var geometry: Array = []
	for entry: Dictionary in source.presentation_tiles():
		var sprite: Variant = entry.sprite.get_ref()
		if typeof(sprite)!=TYPE_OBJECT or not is_instance_valid(sprite) or not sprite.is_visible_in_tree():
			continue
		var texture_size: Vector2 = sprite.texture.get_size()
		var region: Rect2 = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO,texture_size)
		var rect := Rect2(sprite.position,region.size*sprite.scale)
		var uv := Rect2(region.position/texture_size,region.size/texture_size)
		var instance := MeshInstance2D.new()
		instance.mesh = GeoProjection.mesh(rect,uv,meta)
		var arrays := instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector2Array = arrays[Mesh.ARRAY_VERTEX]
		var texcoords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var actual: Array = []
		for i in vertices.size():
			actual.append([vertices[i].x,vertices[i].y,texcoords[i].x,texcoords[i].y])
		geometry.append({"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"uv":[uv.position.x,uv.position.y,uv.size.x,uv.size.y],"vertices":actual,"indices":Array(arrays[Mesh.ARRAY_INDEX])})
		for point in vertices:
			var pixel: Vector2 = map._camera.unproject_position(map._city.to_global(Vector3(point.x,0,point.y)))
			var expected: Vector2 = stretch*source.get_global_transform_with_canvas()*point
			anchor_error = maxf(anchor_error,pixel.distance_to(expected))
			old_offset = maxf(old_offset,absf(GeoProjection.raw_y(point.y,meta)-point.y)*scale_value.y*battle.camera.zoom.x)
		if not corrected:
			for i in vertices.size():
				vertices[i].y = GeoProjection.raw_y(vertices[i].y,meta)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			instance.mesh = ArrayMesh.new()
			instance.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		faces += arrays[Mesh.ARRAY_INDEX].size()/3
		instance.texture = sprite.texture
		instance.material = sprite.material
		instance.modulate = sprite.modulate
		instance.self_modulate = sprite.self_modulate
		instance.texture_filter = sprite.texture_filter
		instance.transform = stretch*sprite.get_parent().get_global_transform_with_canvas()
		viewport.add_child(instance)
	for frame in 4:
		await RenderingServer.frame_post_draw
	var suffix := "corrected" if corrected else "affine"
	if corrected:
		var file := FileAccess.open(stem+"_geometry.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"meta":meta,"rows":geometry},"\t"))
		file.close()
	var picture := viewport.get_texture().get_image()
	assert(picture.save_png(stem+"_"+suffix+"_source.png")==OK)
	var buildings := Sprite2D.new()
	buildings.centered = false
	buildings.texture = map._viewport.get_texture()
	buildings.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(buildings)
	for frame in 4:
		await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(stem+"_"+suffix+"_buildings.png")==OK)
	viewport.queue_free()
	await battle.get_tree().process_frame
	await battle.get_tree().process_frame
	return {"corrected":corrected,"faces":faces,"anchor_error":anchor_error,"maximum_old_offset_px":old_offset}
