extends RefCounted
## 被默认 lifecycle_gauntlet 调用；真实伤害、真实 queue_free 与下一消费者 tick。
const Probe := preload("res://scripts/experiments/volume_world_probe.gd")
const FormalOverlay := preload("res://scripts/rendering/aircraft_volume_overlay.gd")
const FormalDesert := preload("res://scripts/rendering/desert_volume_presentation.gd")
const Satellite := preload("res://scripts/experiments/volume_satellite_ground.gd")
const Renderer := preload("res://scripts/aircraft_renderer.gd")
const AtmosphereExperiment := preload("res://scripts/survivor/battlefield_atmosphere_experiment.gd")

class Host:
	extends Node2D
	var camera := Camera2D.new()
	var _map_features: CanvasItem
	var _building_renderer: CanvasItem

var _fail := 0
var _pass := 0


func run(parent: Node) -> int:
	_fail += await preload("res://scripts/tests/weather_volume_lifecycle_case.gd").new().run(parent)
	_fail += await preload("res://scripts/tests/volume_ground_lifecycle_case.gd").new().run(parent)
	var host := Host.new()
	parent.add_child(host)
	host.add_child(host.camera)
	var ac := Aircraft.new()
	ac.params = AircraftParams.new()
	ac.params.display_name = "F-14 Tomcat"
	ac.set_physics_process(false)
	host.add_child(ac)
	# 正式场由 SurvivorMode 刷新注册表；此隔离 fixture 明确登记真实 SceneTree 单位。
	CombatUnit.all_units.append(ac)
	var probe := FormalDesert.new()
	host.add_child(probe)
	probe.setup_formal(host)
	probe.set_process(false)
	Probe._set_body_override(ac, true)
	var mount := WeaponMount.new()
	var params := WeaponMountParams.new()
	params.max_hp = 200.0
	params.local_offset = Vector2(-63, 21)
	mount.initialize(params)
	ac.set_meta(&"mg_mounts", [mount])
	probe._counts["prop"] = 0
	probe._sync_goose_mounts(ac, Color.WHITE)
	_check(int(probe._counts["prop"]) == 1, "live mount is submitted")
	mount.apply_damage(200.0)
	await parent.get_tree().process_frame
	probe._counts["prop"] = 0
	probe._sync_goose_mounts(ac, Color.WHITE)
	_check(mount.destroyed and int(probe._counts["prop"]) == 0, "real mount death removes proxy next frame")
	ac.take_damage(99999.0, null, "missile")
	await parent.get_tree().process_frame
	probe._process(0.11)
	_check(ac.is_destroyed and ac.has_meta(Probe.BODY_META),
		"real aircraft damage retains the same 3D renderer through the next frame")
	var retained: Variant = ac
	CombatUnit.all_units.erase(ac)
	ac.queue_free()
	await parent.get_tree().process_frame
	probe._process(0.01)
	probe._process(0.11)
	_check(not is_instance_valid(retained), "freed cache consumer executes to completion")
	var survivor := Aircraft.new()
	survivor.params = AircraftParams.new()
	survivor.params.display_name = "F-15C Eagle"
	survivor.set_physics_process(false)
	host.add_child(survivor)
	CombatUnit.all_units.append(survivor)
	Renderer.player_ref = survivor
	probe._refresh_members()
	Probe._set_body_override(survivor, true)
	probe.queue_free()
	await parent.get_tree().process_frame
	_check(not survivor.has_meta(Probe.BODY_META), "adapter teardown restores surviving body")
	var overlay: CanvasLayer = FormalOverlay.new()
	host.add_child(overlay)
	overlay.call("setup", host)
	await parent.get_tree().process_frame
	var formal_viewport: Variant = overlay.get("_subviewport")
	var formal_probe: Variant = overlay.get("_probe")
	_check(typeof(formal_viewport) == TYPE_OBJECT and is_instance_valid(formal_viewport) \
			and formal_viewport is SubViewport and formal_viewport.transparent_bg,
		"formal renderer owns one transparent shared SubViewport")
	_check(formal_viewport.msaa_3d == Viewport.MSAA_2X,
		"formal aircraft edges retain the F6 two-sample antialiasing")
	var source_viewport := host.get_viewport()
	var stretch := source_viewport.get_stretch_transform().get_scale() if source_viewport is Window else Vector2.ONE
	var expected_pixels := Vector2i(source_viewport.get_visible_rect().size * stretch)
	_check(formal_viewport.size == expected_pixels,
		"formal aircraft layer renders at final output pixel resolution")
	overlay.set_process(false)
	var cadence_ok := true
	for hz in [60, 120, 144, 165, 240]:
		var before: int = formal_probe.get("_updates")
		for frame in hz:
			host.camera.position.x += 0.25
			overlay.call("_process", 1.0 / float(hz))
		cadence_ok = cadence_ok and int(formal_probe.get("_updates")) - before == hz
	_check(cadence_ok, "each display frame samples current camera and aircraft at 60/120/144/165/240 Hz")
	if typeof(formal_probe) == TYPE_OBJECT and is_instance_valid(formal_probe):
		_check(formal_probe.get("_root_map") == null,
			"aircraft-only renderer does not allocate an orphan 3D map instance")
		formal_probe._process(0.11)
		var formal_sun: Variant = formal_probe.get("_sun")
		_check(typeof(formal_sun) == TYPE_OBJECT and is_instance_valid(formal_sun) \
				and formal_sun is DirectionalLight3D and not formal_sun.shadow_enabled,
			"aircraft-only compositor skips the invisible shadow map")
	_check(survivor.has_meta(Probe.BODY_META), "formal Survivor overlay enables the dedicated 3D body by default")
	overlay.call("set_volume_enabled", false)
	_check(not survivor.has_meta(Probe.BODY_META), "formal old/new toggle restores PNG fallback on the same Aircraft")
	overlay.queue_free()
	await parent.get_tree().process_frame
	Renderer.player_ref = null
	CombatUnit.all_units.erase(survivor)
	# 真实 SceneTree owner 退出后跨过桥接下一 tick；不能留下过期 Sprite/纹理引用。
	var raster := RasterBasemapRenderer.new()
	host.add_child(raster)
	raster.set_process(false)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(Image.create_empty(4, 4, false, Image.FORMAT_RGB8))
	raster.add_child(sprite)
	raster._strategic_sprite = sprite
	var ground := Satellite.new()
	var lod_view := SubViewport.new()
	lod_view.size = Vector2i(1000, 1000)
	lod_view.own_world_3d = true
	host.add_child(lod_view)
	var lod_camera := Camera3D.new()
	lod_view.add_child(lod_camera)
	lod_camera.rotation.x = -PI / 3.0
	lod_camera.position = Vector3(0, 2000, 2000)
	lod_camera.set_orthogonal(2000, 0.1, 10000)
	lod_camera.make_current()
	lod_view.add_child(ground)
	ground.enable_relief()
	ground.setup(raster)
	_check(ground.debug_state().planes == 1, "satellite owner is consumed in real tree")
	await parent.get_tree().process_frame
	ground.sync(0.11)
	var actual_error := lod_camera.unproject_position(Vector3.ZERO).distance_to(
		lod_camera.unproject_position(Vector3.UP * Satellite.Relief.COVER_LOD_ERROR))
	_check(ground.debug_state().cover_lod_far and absf(ground.debug_state().cover_lod_error_px - actual_error) < 0.001,
		"actual orthographic camera projection enters far LOD with matching pixel error")
	lod_view.size_2d_override = Vector2i(2000, 2000)
	lod_view.size_2d_override_stretch = true
	ground.sync(0.11)
	_check(ground.debug_state().cover_lod_far and is_equal_approx(ground.debug_state().cover_lod_error_px, 0.125),
		"2D logical size override never doubles actual 3D output pixel error")
	lod_view.size_2d_override = Vector2i.ZERO
	lod_view.size_2d_override_stretch = false
	lod_camera.size = 1500
	ground.sync(0.11)
	_check(ground.debug_state().cover_lod_far and ground.debug_state().cover_lod_swaps == 1,
		"real camera scale stays far inside hysteresis band")
	lod_camera.size = 1000
	ground.sync(0.11)
	_check(not ground.debug_state().cover_lod_far and ground.debug_state().cover_lod_swaps == 2,
		"real camera zoom restores near cover")
	lod_camera.size = 2000
	ground.sync(0.11)
	lod_camera.queue_free()
	await parent.get_tree().process_frame
	ground.sync(0.11)
	_check(not ground.debug_state().cover_lod_far and is_inf(ground.debug_state().cover_lod_error_px),
		"freed projection owner safely restores near meshes next tick")
	raster.queue_free()
	await parent.get_tree().process_frame
	ground.sync(0.11)
	_check(ground.debug_state().planes == 0 and ground.get_child_count() == 0 and not ground.debug_state().cover_lod_far,
		"released satellite owner clears texture and mesh consumers next tick")
	# 诊断回调也必须随真正的节点终态解除，不能留住测试视口/adapter。
	var warmup := Satellite.MaterialWarmup.new()
	var warm_material := ShaderMaterial.new()
	warm_material.shader = Satellite.TacticalContext.SHADER
	warmup.configure(warm_material)
	var warm_ref: WeakRef = weakref(warmup)
	var warm_callback: Callable = warmup._after_draw
	host.add_child(warmup)
	# 模拟预热尚未完成就退出；headless的跳过释放也必须清除显式连接。
	if not RenderingServer.frame_post_draw.is_connected(warm_callback):
		RenderingServer.frame_post_draw.connect(warm_callback)
	warmup.queue_free()
	await parent.get_tree().process_frame
	_check(warm_ref.get_ref() == null and not RenderingServer.frame_post_draw.is_connected(warm_callback),
		"early warmup owner exit releases the private viewport and frame callback")
	var timing := load("res://scripts/tests/volume_map_performance.gd").new() as Node
	host.add_child(timing)
	timing._timing_viewport = host.get_viewport().get_viewport_rid()
	var callback: Callable = timing._sample_render_times
	RenderingServer.frame_post_draw.connect(callback)
	_check(RenderingServer.frame_post_draw.is_connected(callback), "render timing callback is connected in actual tree")
	var timing_ref: WeakRef = weakref(timing)
	timing.queue_free()
	await parent.get_tree().process_frame
	_check(timing_ref.get_ref() == null and not RenderingServer.frame_post_draw.is_connected(callback),
		"queued timing adapter release disconnects next-frame render consumer")
	# 大气战场的 typed 数组会在对象释放后一帧短暂保留失效引用；清理 helper 必须先收 Variant。
	var atmosphere: Node2D = AtmosphereExperiment.new()
	atmosphere.set_physics_process(false)
	host.add_child(atmosphere)
	var retired_aircraft := Aircraft.new()
	retired_aircraft.params = AircraftParams.new()
	retired_aircraft.set_physics_process(false)
	retired_aircraft.set_meta(&"ambient_engagement_id", atmosphere.get("_run_id"))
	host.add_child(retired_aircraft)
	atmosphere.get("_fighters").append(retired_aircraft)
	atmosphere.get("_helis").append(retired_aircraft)
	var retired_ref: Variant = retired_aircraft
	retired_aircraft.queue_free()
	await parent.get_tree().process_frame
	atmosphere.call("_cleanup_refs")
	atmosphere.call("_refresh_assignments")
	_check(not is_instance_valid(retired_ref) \
			and atmosphere.get("_fighters").is_empty() \
			and atmosphere.get("_helis").is_empty(),
		"atmosphere cleanup consumes freed typed-array refs through the next assignment tick")
	host.queue_free()
	await parent.get_tree().process_frame
	print("[Volume lifecycle] pass=%d fail=%d" % [_pass, _fail])
	return _fail


func _check(value: bool, label: String) -> void:
	if value:
		_pass += 1
	else:
		_fail += 1
		push_error("Volume lifecycle: " + label)
