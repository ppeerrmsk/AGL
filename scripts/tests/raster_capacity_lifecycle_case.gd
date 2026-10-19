extends RefCounted
## 固定可见集合复现过渡旧层保护；走三图真实异步纹理入口，不用伪造完成状态。
class Fixture extends RasterBasemapRenderer:
	var visible_sets: Dictionary = {}
	func _visible_keys(lod: StringName) -> Array[String]:
		var result: Array[String] = []
		result.assign(visible_sets.get(lod,[]))
		return result
	func _required_keys(lod: StringName) -> Array[String]:
		return _visible_keys(lod)


static func run(parent: Node) -> int:
	var fail := 0
	for map_key: String in ["tokyo","desert","ocean"]:
		fail += await _map_case(parent,map_key)
	print("[R189 raster capacity] maps=3 fail=",fail)
	return fail


static func _map_case(parent: Node, map_key: String) -> int:
	var renderer := Fixture.new()
	parent.add_child(renderer)
	renderer.set_process(false)
	renderer._map_root = RasterBasemapRenderer.map_root_for(map_key)
	renderer._manifest = JSON.parse_string(FileAccess.get_file_as_string(renderer._map_root.path_join("manifest.json")))
	renderer._world_rect = Rect2(-1000,-1000,2000,2000)
	for lod: StringName in [RasterBasemapRenderer.LOD_DETAIL,RasterBasemapRenderer.LOD_OPERATIONAL]:
		var layer := Node2D.new()
		renderer.add_child(layer)
		renderer._layers[lod] = layer
		renderer._sprites[lod] = {}
		renderer._records[lod] = {}
		renderer.visible_sets[lod] = []
	var old_nodes: Array[Sprite2D] = []
	for n in 12:
		var key := "old%d" % n
		var sprite := Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(Image.create(1,1,false,Image.FORMAT_RGBA8))
		renderer._layers[RasterBasemapRenderer.LOD_DETAIL].add_child(sprite)
		renderer._sprites[RasterBasemapRenderer.LOD_DETAIL][key] = sprite
		renderer.visible_sets[RasterBasemapRenderer.LOD_DETAIL].append(key)
		renderer._touch_lru("detail:"+key)
		old_nodes.append(sprite)
	var records: Array = renderer._manifest.levels.operational.tiles
	for n in 8:
		var key := "new%d" % n
		renderer._records[RasterBasemapRenderer.LOD_OPERATIONAL][key] = records[n]
		if n < 6:
			renderer.visible_sets[RasterBasemapRenderer.LOD_OPERATIONAL].append(key)
	renderer._current_lod = RasterBasemapRenderer.LOD_STRATEGIC
	renderer._target_lod = RasterBasemapRenderer.LOD_OPERATIONAL
	renderer._transition_from_lod = RasterBasemapRenderer.LOD_DETAIL
	renderer._transitioning = true
	renderer._request_target_tiles()
	var fail := int(renderer._pending.size() != 4 or renderer.resident_tile_count() != 12)
	var expected_backend := "main_deferred" if DisplayServer.get_name()=="headless" else "threaded"
	fail+=int(renderer.debug_state().resource_load_backend!=expected_backend)
	var deferred := 0
	for request: Dictionary in renderer._pending.values():
		if ResourceLoader.exists(request.path):
			fail+=int(request.kind!=("main_resource" if expected_backend=="main_deferred" else "resource"))
			deferred+=int(request.kind=="main_resource")
	if deferred==4:
		renderer._poll_pending()
		fail+=int(renderer._pending.size()!=4 or renderer.resident_tile_count()!=12)
	var deadline := Time.get_ticks_msec()+15000
	while not renderer._pending.is_empty() and Time.get_ticks_msec()<deadline:
		var previous_resident := renderer.resident_tile_count()
		renderer._poll_pending()
		fail+=int(renderer.resident_tile_count()-previous_resident>2)
		renderer._evict_unused()
		renderer._request_target_tiles()
		fail += int(renderer.resident_tile_count()+renderer._pending.size()>16)
		fail += int(renderer._sprites[RasterBasemapRenderer.LOD_DETAIL].size()!=12)
		await parent.get_tree().process_frame
	fail += int(renderer.resident_tile_count()!=16 or renderer._capacity_deferrals == 0)
	# 旧层仍在显示时绝不删它；只有正式过渡结束后才允许回收旧层并补齐新图。
	renderer._layers[RasterBasemapRenderer.LOD_DETAIL].hide()
	renderer._transitioning = false
	renderer._transition_from_lod = RasterBasemapRenderer.LOD_STRATEGIC
	deadline = Time.get_ticks_msec()+15000
	while renderer._sprites[RasterBasemapRenderer.LOD_OPERATIONAL].size()<6 and Time.get_ticks_msec()<deadline:
		renderer._reserve_target_capacity()
		for node: Variant in old_nodes:
			if typeof(node)==TYPE_OBJECT and is_instance_valid(node) and node.is_queued_for_deletion():
				fail += int(node.texture!=null or node.material!=null)
		renderer._poll_pending()
		renderer._evict_unused()
		renderer._request_target_tiles()
		fail += int(renderer.resident_tile_count()+renderer._pending.size()>16)
		await parent.get_tree().process_frame
	fail += int(renderer._sprites[RasterBasemapRenderer.LOD_OPERATIONAL].size()!=6)
	old_nodes.clear()
	# 正式异步请求在途时关闭拥有者；退出入口须取回并清空请求，不留后台作业。
	renderer.visible_sets[RasterBasemapRenderer.LOD_OPERATIONAL].append_array(["new6","new7"])
	renderer._reserve_target_capacity()
	renderer._request_target_tiles()
	var pending := renderer._pending.size()
	var peak := renderer._peak_committed_tiles
	var reference: WeakRef = weakref(renderer)
	renderer.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	fail += int(pending != 2 or peak != 16 or is_instance_valid(reference.get_ref()))
	print("[R189 raster map] map=",map_key," committed_peak=",peak," pending_exit=",pending," fail=",fail)
	return fail
