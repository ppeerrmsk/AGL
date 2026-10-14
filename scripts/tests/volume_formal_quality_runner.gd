extends Node2D
## 正式合成/F6 同源对照、逐显示帧相机同步、真实伤害后的同网格坠毁与淡出。
const Overlay := preload("res://scripts/rendering/aircraft_volume_overlay.gd")
const Probe := preload("res://scripts/experiments/volume_world_probe.gd")
const Destruction := preload("res://scripts/aircraft_destruction.gd")
var camera := Camera2D.new()
var _map_features: CanvasItem
var _building_renderer: CanvasItem
var _overlay: CanvasLayer
var _background: ColorRect
var _actors: Array[Aircraft] = []
var _pass := 0
var _fail := 0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	add_child(camera)
	camera.zoom = Vector2.ONE * 2.0
	camera.make_current()
	var background := CanvasLayer.new()
	background.layer = -100
	add_child(background)
	var fill := ColorRect.new()
	fill.color = Color("798887")
	fill.size = Vector2(4096, 4096)
	background.add_child(fill)
	_background = fill
	var paths := ["res://resources/player/player_f14.tres",
		"res://resources/player/player_f47.tres", "res://resources/enemy_tu160.tres"]
	for index in paths.size():
		var ac := Aircraft.new()
		ac.params = load(paths[index]).duplicate(true)
		ac.position = Vector2((index - 1) * 240.0, 0)
		ac.initial_heading_deg = -25.0
		add_child(ac)
		ac.process_mode = Node.PROCESS_MODE_DISABLED
		ac.altitude = 9000.0
		ac.bank_angle = 0.32
		_actors.append(ac)
		CombatUnit.all_units.append(ac)
	_overlay = Overlay.new()
	add_child(_overlay)
	_overlay.setup(self)
	_run.call_deferred()


func _run() -> void:
	var probe: Node3D = _overlay.get("_probe")
	var viewport: SubViewport = _overlay.get("_subviewport")
	_check(viewport.msaa_3d == Viewport.MSAA_2X, "formal uses F6 MSAA")
	# setup 的 deferred 帧可能已越过新节点的 process；只采样稳定显示循环。
	for warmup in 3:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	var before: int = probe.get("_updates")
	var projection_error := 0.0
	for frame in 144:
		camera.position = Vector2(sin(frame * 0.035) * 30, cos(frame * 0.025) * 15)
		camera.rotation = sin(frame * 0.025) * 0.12
		camera.zoom = Vector2.ONE * (2.0 + sin(frame * 0.03) * 0.3)
		await RenderingServer.frame_post_draw
		var actor := _actors[0]
		var actual: Vector2 = probe.get("_camera").unproject_position(
			_volume_point(actor, probe))
		actual *= get_viewport().get_visible_rect().size / Vector2(viewport.size)
		projection_error = maxf(projection_error,
			actual.distance_to(actor.get_global_transform_with_canvas().origin))
		await get_tree().process_frame
	_check(int(probe.get("_updates")) - before >= 144, "formal consumes every presented camera frame")
	_check(projection_error < 0.1, "same-frame camera and body alignment < 0.1 px")
	camera.position = Vector2.ZERO
	camera.rotation = 0.0
	camera.zoom = Vector2.ONE * 2.0
	await _capture("formal_alive")
	_overlay.set_volume_enabled(false)
	var direct := Probe.new()
	add_child(direct)
	direct.setup(self, "volume_3d_quality_reference", {"include_map": false})
	_background.hide()
	direct.get("_camera").environment.background_color = Color("798887")
	await _capture("f6_reference_alive")
	direct.queue_free()
	await get_tree().process_frame
	_overlay.set_volume_enabled(true)
	_background.show()
	await _capture("formal_before_damage")
	var actor := _actors[0]
	var body_route := "f14"
	var original_mesh: ArrayMesh = probe.get("_mesh_routes")[body_route]
	var original_color := actor.params.icon_color
	actor.take_damage(99999.0, null, "missile")
	await _capture("formal_after_damage")
	_check(actor.is_destroyed and actor.has_meta(Probe.BODY_META),
		"real lethal damage retains 3D ownership")
	_check(probe.get("_mesh_routes")[body_route] == original_mesh
		and actor.params.icon_color == original_color, "death retains identical mesh and livery")
	var fade_seen := false
	var release_ref: WeakRef = weakref(actor)
	# 每步调用生产坠毁动画；相机跟随同一实体，覆盖全部缩小、爆炸保留与淡出阶段。
	for step in 1200:
		if not is_instance_valid(actor):
			break
		Destruction.update(actor, 1.0 / 60.0)
		camera.position = actor.position
		actor.queue_redraw()
		await RenderingServer.frame_post_draw
		if is_instance_valid(actor) and actor._destroy_visual_alpha < 0.75 \
				and actor._destroy_visual_alpha > 0.1 and not fade_seen:
			fade_seen = true
			_check(actor.has_meta(Probe.BODY_META), "fade never switches back to PNG")
			var fade_route := Probe.FADE_ROUTE_PREFIX + body_route
			_check(probe.get("_mesh_routes").get(fade_route) == original_mesh,
				"fade material shares the exact pre-death ArrayMesh")
			await _capture("formal_fade")
		await get_tree().process_frame
	_check(fade_seen and release_ref.get_ref() == null, "real destruction completes fade and releases")
	await get_tree().create_timer(0.12).timeout
	_check(int(probe.get("_counts").get("fade_f14", 0)) == 0, "released crash leaves no rendered instance")
	print("[Formal quality] pass=%d fail=%d projection_error_px=%.5f %s" % [
		_pass, _fail, projection_error, _overlay.summary()])
	get_tree().quit(0 if _fail == 0 else 1)


func _volume_point(actor: Aircraft, probe: Node3D) -> Vector3:
	var ground: Basis = probe.get("_display_ground")
	var shift: Vector3 = probe.get("_display_anchor_shift")
	return ground * (Probe.world_point(actor.global_position, Probe.AIR_HEIGHT)
		- shift * Probe.AIR_HEIGHT)


func _capture(suffix: String) -> void:
	for frame in 3:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://bench/results/volume_quality_%s.png" % suffix
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "capture " + suffix)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Formal quality: " + label)
