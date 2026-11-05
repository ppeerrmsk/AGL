extends Node2D
## 逐入口真实像素回归：隔离其它图层，空画面不能靠节点存在误判通过。
const Pacing := preload("res://scripts/util/display_pacing.gd")
const OUT := "res://tmp/map_visual_qa/player_elements/"

class Actor extends Aircraft:
	var painter: Callable
	func _ready() -> void:
		_font = ThemeDB.fallback_font
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		set_process(false)
		set_physics_process(false)
	func _draw() -> void:
		if painter.is_valid():
			painter.call()

class Canvas extends Node2D:
	var painter: Callable
	func _draw() -> void:
		if painter.is_valid():
			painter.call()

class Motion extends Node:
	var actors: Array[Aircraft] = []
	func _physics_process(delta: float) -> void:
		for ac in actors:
			ac.interp_prev_xform = ac.transform
			ac.interp_prev_tick = Engine.get_physics_frames()
			ac.position += Vector2(95, -12).rotated(float(ac.get_instance_id() % 3)) * delta
			ac.rotation += 0.6 * delta
			ac.heading = ac.rotation

class Mode extends Node2D:
	var player_aircraft: Aircraft
	var _squad_cmd: SquadCommandController

class Hud extends SurvivorHUD:
	func _ready() -> void:
		set_process(false)

class LabelOverlay extends WorldUnitStatusOverlay:
	# 仅隔离其它战术标记，标签位置/缓存仍完整走正式覆盖层。
	func _sync_tactical_canvases() -> void:
		pass

var ac: Actor
var target: Actor
var canvas: Canvas
var camera: Camera2D
var motion: Motion
var failures := 0
var results: Array[Dictionary] = []
var rail := RailgunEquipment.new()
var laser := LaserEquipment.new()
var endpoint := false
var expected_visible := true

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	Engine.max_fps = 120
	DirAccess.make_dir_recursive_absolute(OUT)
	ac = Actor.new()
	target = Actor.new()
	for unit in [ac, target]:
		unit.params = load("res://resources/playable_f14_base.tres").duplicate(true)
		unit.altitude = 5500
		unit.speed = 180
		add_child(unit)
	target.team = 1
	AircraftRenderer.player_ref = ac
	CombatUnit.all_units.assign([ac, target])
	canvas = Canvas.new()
	canvas.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(canvas)
	camera = Camera2D.new()
	camera.ignore_rotation = false
	add_child(camera)
	camera.make_current()
	motion = Motion.new()
	motion.actors.assign([ac, target])
	add_child(motion)
	var cases := ["icon", "icon_bank", "icon_pitch", "destroyed_icon", "cloud_shadow", "cloud_inside",
		"radar", "secondary_cone", "gun_hover", "gun_brake", "gun_enemy", "gunship",
		"jam_aura", "rear_aura", "fear_aura", "esm", "muzzle", "afterburner", "afterburner_pitch",
		"deadair", "lock_progress", "lock_full", "mission", "unknown", "secondary_lock",
		"secondary_empty", "secondary_reload", "secondary_cloak", "secondary_hidden", "secondary_dead",
		"combat", "combat_hidden", "assault", "waypoint", "waypoint_other",
		"formation", "reload", "popup", "popup_expired", "flare", "rail_track", "rail_nose",
		"rail_frozen", "rail_await", "rail_fan", "rail_beam", "laser", "laser_hack", "laser_heat",
		"label_full", "label_compact", "label_minimal", "label_drone", "label_destroyed"]
	for case_name in cases:
		await _case(case_name)
	await _boss_cases()
	await _projectile_cases()
	await _control_cases()
	await _hud_cases()
	await _ground_ring_cases()
	motion.actors.clear()
	ac.painter = Callable()
	canvas.painter = Callable()
	AircraftRenderer.player_ref = null
	CombatUnit.all_units.clear()
	ac.queue_free()
	target.queue_free()
	await get_tree().process_frame
	var file := FileAccess.open(OUT + "coverage.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": results, "failures": failures}, "\t"))
	file.close()
	print("[PlayerElements] cases=%d failures=%d" % [results.size(), failures])
	AudioManager.request_quit(1 if failures else 0)

func _reset() -> void:
	AircraftRenderer.player_ref = ac
	ac.painter = Callable()
	canvas.painter = Callable()
	ac.position = Vector2.ZERO
	ac.rotation = 0.0
	target.position = Vector2(130, -70)
	ac.reset_physics_interpolation()
	target.reset_physics_interpolation()
	ac.team = 0
	ac.is_hovered = true
	ac.hard_brake = false
	ac.gunship_mode_active = false
	ac.bank_angle = 0.0
	ac._active_special_pitch_visual = 0.0
	ac.cloud_state = 0
	ac.cloud_density = 0.8
	ac.jam_aura_radius_px = 0.0
	ac.rear_aura_slow_radius_px = 0.0
	ac.fear_on_lock_threshold = 0.0
	ac.params.radar_range = 600
	ac.params.secondary_missile = ac.params.missile.duplicate(true)
	ac.secondary_missile_enabled = true
	ac.secondary_missiles_remaining = 4
	ac._secondary_reload_active = false
	ac._secondary_cooldown = 0.0
	ac.secondary_radar_targets = {target: ac.params.lock_time}
	target.is_cloaked = false
	target.is_destroyed = false
	target.sensor_contact_hidden = false
	ac.incoming_lock_progress = 0.6
	ac.is_locked = false
	ac.is_mission_target = true
	ac.deadair_exposure_ratio = 0.375
	ac.combat_target = null
	ac.target_position = Vector2(150, -80)
	ac.charge_attack = false
	ac._tactic_popup_text = "BREAK"
	ac._tactic_popup_timer = 1.0
	ac._gun_reload_active = true
	ac._missile_reload_active = true
	ac.enable_flare_reload = true
	ac.flares_remaining = 0
	ac.flare_reload_progress = 0.3
	ac._flare_particles = [{"pos": Vector2(0, 40), "life": 1.2, "bright": true}, {"pos": Vector2(15, 60), "life": 0.9}]
	ac.params.equipment.clear()
	ac.params.equipment.append(rail)
	ac.params.equipment.append(laser)
	rail.fire_along_nose = false
	rail.lock_trajectory_at = RailgunEquipment.LockTrajectory.AT_FIRE_TIME
	ac.equipment_state = {
		RailgunEquipment.STATE_KEY: {"charging": true, "charge_target": target, "charge_progress": 1.0,
			"locked_aim_pos": Vector2(130, -70), "beam_fade": 0.2, "beam_start": Vector2(-60, 0), "beam_end": Vector2(160, -80)},
		LaserEquipment.STATE_KEY: {"active_beams": [{"unit": target, "alpha": 0.9, "thickness": 3.0}]}}
	endpoint = false
	expected_visible = true

func _configure(case_name: String) -> void:
	_reset()
	match case_name:
		"icon", "icon_bank", "icon_pitch":
			ac.bank_angle = 1.45 if case_name == "icon_bank" else 0.0
			ac._active_special_pitch_visual = 0.8 if case_name == "icon_pitch" else 0.0
			ac.painter = AircraftRenderer.draw_aircraft_icon.bind(ac)
		"destroyed_icon": ac.painter = AircraftRenderer.draw_aircraft_icon_destroyed.bind(ac)
		"cloud_shadow", "cloud_inside":
			ac.cloud_state = 1 if case_name == "cloud_shadow" else 2
			ac.painter = AircraftRenderer.draw_cloud_state.bind(ac)
		"radar": ac.painter = AircraftRenderer.draw_radar_cone.bind(ac)
		"secondary_cone": ac.painter = AircraftRenderer.draw_secondary_lock_cone.bind(ac)
		"gun_hover", "gun_brake", "gun_enemy", "gunship":
			ac.is_hovered = case_name in ["gun_hover", "gunship"]
			ac.hard_brake = case_name == "gun_brake"
			ac.team = 1 if case_name == "gun_enemy" else 0
			ac._gun_threat_timer = 1.0
			ac._gun_threat_fade = 1.0
			ac.gunship_mode_active = case_name == "gunship"
			ac.painter = AircraftRenderer.draw_gun_cone.bind(ac)
		"jam_aura", "rear_aura", "fear_aura":
			ac.jam_aura_radius_px = 90.0 if case_name == "jam_aura" else 0.0
			ac.rear_aura_slow_radius_px = 100.0 if case_name == "rear_aura" else 0.0
			ac.fear_on_lock_threshold = 2.0 if case_name == "fear_aura" else 0.0
			ac.painter = AircraftRenderer.draw_aura_ranges.bind(ac)
		"esm":
			ac.params.equipment.append(load("res://resources/esm_pod.tres").duplicate(true))
			ac.painter = AircraftRenderer.draw_esm_aura.bind(ac)
		"muzzle": ac.painter = AircraftRenderer.draw_muzzle_flash.bind(ac)
		"afterburner", "afterburner_pitch":
			ac._active_special_pitch_visual = 0.8 if case_name.ends_with("pitch") else 0.0
			ac.painter = AircraftRenderer.draw_afterburner_glow.bind(ac)
		"deadair": canvas.painter = AircraftRenderer.draw_deadair_exposure.bind(ac, canvas)
		"lock_progress", "lock_full":
			ac.is_locked = case_name == "lock_full"
			canvas.painter = AircraftRenderer.draw_lock_indicator.bind(ac, canvas)
		"mission": canvas.painter = AircraftRenderer.draw_target_bracket.bind(ac, true, canvas)
		"unknown": canvas.painter = AircraftRenderer.draw_sensor_unknown_target.bind(ac, canvas)
		"secondary_lock", "secondary_empty", "secondary_reload", "secondary_cloak", "secondary_hidden", "secondary_dead":
			ac.secondary_missiles_remaining = 0 if case_name == "secondary_empty" else 4
			ac._secondary_reload_active = case_name == "secondary_reload"
			target.is_cloaked = case_name == "secondary_cloak"
			target.sensor_contact_hidden = case_name == "secondary_hidden"
			target.is_destroyed = case_name == "secondary_dead"
			expected_visible = case_name == "secondary_lock"
			canvas.painter = AircraftRenderer.draw_secondary_lock_indicators.bind(ac, canvas)
		"combat", "combat_hidden", "assault", "waypoint", "waypoint_other":
			ac.combat_target = null if case_name.begins_with("waypoint") else target
			ac.charge_attack = case_name == "assault"
			ac._predicted_path_world = PackedVector2Array([Vector2.ZERO, Vector2(40, -55), Vector2(100, -90), ac.target_position])
			ac._predicted_path_healths = PackedFloat32Array([1.0, 0.8, 0.5, 1.0])
			canvas.painter = AircraftRenderer.draw_target_line.bind(ac, canvas)
			endpoint = not case_name.begins_with("waypoint")
			if case_name == "combat_hidden":
				target.sensor_contact_hidden = true
				endpoint = false
				expected_visible = false
			if case_name == "waypoint_other":
				AircraftRenderer.player_ref = target
				expected_visible = false
		"formation":
			ac._dbg_slot_pos = Vector2(100, 30)
			ac._dbg_slot_dist = 100
			canvas.painter = AircraftRenderer.draw_formation_debug.bind(ac, canvas)
		"reload": canvas.painter = AircraftRenderer.draw_reload_indicators.bind(ac, canvas)
		"popup", "popup_expired":
			ac._tactic_popup_timer = 0.0 if case_name == "popup_expired" else 1.0
			expected_visible = case_name != "popup_expired"
			canvas.painter = AircraftRenderer.draw_tactic_popup.bind(ac, canvas)
		"flare": canvas.painter = AircraftRenderer.draw_flare_particles.bind(ac, canvas)
		"rail_track", "rail_nose", "rail_frozen", "rail_await", "rail_fan":
			rail.fire_along_nose = case_name == "rail_nose"
			rail.lock_trajectory_at = RailgunEquipment.LockTrajectory.AT_CHARGE_START if case_name == "rail_frozen" else RailgunEquipment.LockTrajectory.AT_FIRE_TIME
			ac.equipment_state[RailgunEquipment.STATE_KEY]["awaiting_fire"] = case_name == "rail_await"
			ac.equipment_state[RailgunEquipment.STATE_KEY]["charge_progress"] = 0.4 if case_name == "rail_fan" else 1.0
			canvas.painter = AircraftRenderer.draw_railgun_telegraph.bind(ac, canvas)
			endpoint = case_name == "rail_track"
		"rail_beam": canvas.painter = AircraftRenderer.draw_railgun_beam.bind(ac, canvas)
		"laser", "laser_hack", "laser_heat":
			ac.equipment_state[LaserEquipment.STATE_KEY]["active_beams"][0]["hack_focus"] = case_name == "laser_hack"
			ac.equipment_state[LaserEquipment.STATE_KEY]["active_beams"][0]["hack_ratio"] = 0.6
			ac.equipment_state[LaserEquipment.STATE_KEY]["overheating"] = case_name == "laser_heat"
			ac.equipment_state[LaserEquipment.STATE_KEY]["heat"] = 95.0 if case_name == "laser_heat" else 0.0
			canvas.painter = AircraftRenderer.draw_laser_beams.bind(ac, canvas)
			endpoint = true
		"label_full": ac.painter = AircraftRenderer.draw_data_label.bind(ac)
		"label_compact": ac.painter = AircraftRenderer.draw_data_label_compact.bind(ac)
		"label_minimal": ac.painter = AircraftRenderer.draw_data_label_minimal.bind(ac)
		"label_drone": ac.painter = AircraftRenderer.draw_data_label_drone.bind(ac)
		"label_destroyed": ac.painter = AircraftRenderer.draw_destroyed_status_label.bind(ac)
	ac.queue_redraw()
	canvas.queue_redraw()

func _case(case_name: String) -> void:
	_configure(case_name)
	var label_layer: CanvasLayer
	var label_overlay: LabelOverlay
	if case_name.begins_with("label_"):
		label_layer = CanvasLayer.new()
		add_child(label_layer)
		label_overlay = LabelOverlay.new()
		label_layer.add_child(label_overlay)
		ac.queue_redraw()
		await get_tree().process_frame
		await get_tree().process_frame
	var bad := 0
	var samples := 0
	for zoom: float in [0.35, 0.7, 1.0, 2.0]:
		camera.zoom = Vector2.ONE * zoom
		for frame in range(6):
			await get_tree().process_frame
			camera.position = Pacing.display_origin(ac)
			camera.rotation = 0.22 + float(frame) * 0.04
			camera.force_update_scroll()
			canvas.transform = Pacing.display_global_transform(ac)
			AircraftRenderer.update_prediction_display(ac, 1.0 / 120.0)
			canvas.queue_redraw()
			# 机体局部几何保留缓存，只依靠引擎插值移动；动态像素采样不强迫重画机体。
			await RenderingServer.frame_post_draw
			var picture := get_viewport().get_texture().get_image()
			var nonempty := _ink(picture, Rect2i(Vector2i.ZERO, picture.get_size()))
			var ok := nonempty == expected_visible
			if label_overlay != null:
				var panel: Node2D = label_overlay._panels.get(ac.get_instance_id())
				ok = ok and panel != null and absf(panel.global_rotation) < 0.001
			if endpoint:
				var pixel := get_viewport().get_stretch_transform() * Pacing.display_screen_origin(target)
				ok = ok and _ink(picture, Rect2i(Vector2i(pixel) - Vector2i(4, 4), Vector2i(9, 9)))
			if case_name == "deadair":
				# 第一段为亮紫、第五段为暗紫；窗口缩放后仍须保持朝屏幕上方。
				var screen := Pacing.display_screen_origin(ac)
				var lit_point := get_viewport().get_stretch_transform() * (screen + Vector2.from_angle(-PI * 0.375) * 25.0)
				var dark_point := get_viewport().get_stretch_transform() * (screen + Vector2.from_angle(PI * 0.625) * 25.0)
				ok = ok and _peak_red(picture, lit_point) > _peak_red(picture, dark_point) * 2.0
			bad += 0 if ok else 1
			samples += 1
			if zoom == 1.0 and frame == 3:
				picture.save_png(OUT + case_name + ".png")
	results.append({"case": case_name, "frames": samples, "bad_frames": bad, "endpoint_pixels": endpoint})
	failures += bad
	print("[PlayerElements] %s frames=%d bad=%d endpoint=%s" % [case_name, samples, bad, endpoint])
	if label_layer != null:
		label_layer.queue_free()
		await get_tree().process_frame

func _ink(picture: Image, region: Rect2i) -> bool:
	region = region.intersection(Rect2i(Vector2i.ZERO, picture.get_size()))
	if not region.has_area():
		return false
	var small := picture.get_region(region)
	if small.get_width() > 320:
		small.resize(320, 180, Image.INTERPOLATE_LANCZOS)
	for y in range(small.get_height()):
		for x in range(small.get_width()):
			var color := small.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) > 0.015:
				return true
	return false

func _boss_cases() -> void:
	# 正式独立覆盖层；运动演员继续运行，状态快照和命中点保持各自的物理语义。
	ac.painter = Callable()
	canvas.painter = Callable()
	ac.queue_redraw()
	canvas.queue_redraw()
	var designation := MotherGooseDesignationOverlay.new()
	designation.boss_unit = ac
	designation.player_ref = target
	designation.designation = MotherGooseDesignation.new()
	add_child(designation)
	for state in [MotherGooseDesignation.State.WARNING, MotherGooseDesignation.State.ACTIVE]:
		designation.designation.state = state
		await _layer_case("goose_designation_%s" % state, designation, true)
	designation.designation.state = MotherGooseDesignation.State.COOLDOWN
	await _layer_case("goose_designation_clear", designation, false)
	designation.queue_free()
	await get_tree().process_frame
	var shield := MotherGooseShieldOverlay.new()
	shield.boss_unit = ac
	shield.jam_shield = MotherGooseJamShield.new()
	shield.jam_shield.current_radius = 100
	add_child(shield)
	for state in [MotherGooseJamShield.State.WARNING, MotherGooseJamShield.State.EXPANDING, MotherGooseJamShield.State.SUSTAIN]:
		shield.jam_shield.state = state
		await _layer_case("goose_shield_%s" % state, shield, true)
	shield.jam_shield.state = MotherGooseJamShield.State.COOLDOWN
	await _layer_case("goose_shield_clear", shield, false)
	shield.queue_free()
	await get_tree().process_frame
	var hyper := HyperAThreatOverlay.new()
	add_child(hyper)
	hyper.sync([{"center": Vector2.ZERO, "radius_px": 100, "ratio": 0.5}], [], [])
	await _layer_case("hyper_aoe", hyper, true)
	hyper.sync([], [{"from": Vector2(-100, 0), "to": Vector2(100, -40), "width_px": 30, "progress": 1.0, "brake_radius_px": 80, "brake_half_angle": 0.7}], [])
	await _layer_case("hyper_dash_brake", hyper, true)
	hyper.sync([], [], [{"center": Vector2.ZERO, "radius_px": 100, "ratio": 0.5}])
	await _layer_case("hyper_impact", hyper, true)
	hyper.sync([], [], [])
	await _layer_case("hyper_clear", hyper, false)
	hyper.queue_free()
	await get_tree().process_frame
	var aura := CommanderAura.new()
	aura.name = "CommanderAura"
	ac.add_child(aura)
	aura.set_process(false)
	aura.set_physics_process(false)
	aura.buffed_aircraft.assign([target])
	var commander := CommanderOverlay.new()
	ac.add_child(commander)
	await _layer_case("commander_datalink", commander, true)
	commander.queue_free()
	aura.queue_free()
	await get_tree().process_frame
	var orion := preload("res://scripts/survivor/orion_weapon_overlay.gd").new()
	add_child(orion)
	var locks: Array[Dictionary] = [{"position": Vector2.ZERO, "progress": 0.7, "alpha": 0.9, "count": 3}]
	var beams: Array[Dictionary] = [{"start": Vector2(-100, 0), "end": Vector2(130, -70), "active": false}]
	orion.present(locks, [], [], [])
	await _layer_case("orion_lock", orion, true)
	orion.present([], beams, [], [])
	await _layer_case("orion_fang_warning", orion, true)
	beams[0]["active"] = true
	orion.present([], beams, [], [])
	await _layer_case("orion_fang_active", orion, true)
	var rails: Array[Dictionary] = [{"start": Vector2(-100, 0), "end": Vector2(130, -70), "life": 0.2}]
	orion.present([], [], rails, [])
	await _layer_case("orion_rail", orion, true)
	var intercepts: Array[Dictionary] = [{"position": Vector2.ZERO, "life": 0.1}]
	orion.present([], [], [], intercepts)
	await _layer_case("orion_intercept", orion, true)
	orion.present([], [], [], [])
	await _layer_case("orion_clear", orion, false)
	orion.queue_free()
	await get_tree().process_frame

func _layer_case(case_name: String, layer: CanvasItem, visible_expected: bool) -> void:
	var bad := 0
	for frame in range(12):
		await get_tree().process_frame
		camera.zoom = Vector2.ONE * [0.35, 0.7, 1.0, 2.0][frame % 4]
		camera.rotation = float(frame) * 0.03
		camera.position = Vector2.ZERO if case_name.begins_with("hyper_") or case_name.begins_with("orion_") or case_name.begins_with("projectile_") else Pacing.display_origin(ac)
		camera.force_update_scroll()
		layer.queue_redraw()
		await RenderingServer.frame_post_draw
		var picture := get_viewport().get_texture().get_image()
		bad += 0 if _ink(picture, Rect2i(Vector2i.ZERO, picture.get_size())) == visible_expected else 1
		if case_name == "deadair_ground":
			var unit: CombatUnit = layer.subject.get_ref()
			var screen := Pacing.display_screen_origin(unit)
			var lit_point := get_viewport().get_stretch_transform() * (screen + Vector2.from_angle(-PI * 0.375) * 25.0)
			var dark_point := get_viewport().get_stretch_transform() * (screen + Vector2.from_angle(PI * 0.625) * 25.0)
			bad += 0 if _peak_red(picture, lit_point) > _peak_red(picture, dark_point) * 2.0 else 1
		if frame == 6:
			picture.save_png(OUT + case_name + ".png")
	results.append({"case": case_name, "frames": 12, "bad_frames": bad})
	failures += bad
	print("[PlayerElements] %s frames=12 bad=%d" % [case_name, bad])

func _peak_red(picture: Image, point: Vector2) -> float:
	var peak := 0.0
	for y in range(-2, 3):
		for x in range(-2, 3):
			var pixel := Vector2i(point) + Vector2i(x, y)
			if Rect2i(Vector2i.ZERO, picture.get_size()).has_point(pixel):
				peak = maxf(peak, picture.get_pixelv(pixel).r)
	return peak

func _projectile_cases() -> void:
	canvas.transform = Transform2D.IDENTITY
	var bombs: Array[Dictionary] = [{"pos": Vector2.ZERO, "vel": Vector2(100, -30), "life": 0.5, "max_life": 1.0}]
	var shells: Array[Dictionary] = [{"pos": Vector2.ZERO, "vel": Vector2(100, -30)}]
	var flashes: Array[Dictionary] = [{"pos": Vector2.ZERO, "age": 0.1, "duration": 1.0, "kind": "bomb", "radius": 100}]
	var bullets: Array[Dictionary] = [{"pos": Vector2.ZERO, "vel": Vector2(100, -30), "life": 0.5}]
	var sparks: Array[Dictionary] = [{"pos": Vector2.ZERO, "age": 0.02, "scale": 20, "angle": 0.5}]
	var torpedoes: Array[Dictionary] = [{"pos": Vector2.ZERO, "life": 0.5, "params": TorpedoParams.new()}]
	var empty: Array[Dictionary] = []
	for kind in ["bomb", "shell", "bomb_flash", "flak", "bullet", "rocket", "visual_bullet", "spark", "torpedo"]:
		bullets[0]["is_rocket"] = kind == "rocket"
		flashes[0]["kind"] = "bomb" if kind == "bomb_flash" else "flak"
		canvas.painter = BulletPresenter.draw.bind(canvas,
			bombs if kind == "bomb" else empty, shells if kind == "shell" else empty,
			flashes if kind in ["bomb_flash", "flak"] else empty, bullets if kind in ["bullet", "rocket"] else empty,
			PackedVector2Array([Vector2.ZERO]) if kind == "visual_bullet" else PackedVector2Array(),
			PackedVector2Array([Vector2(100, -30)]) if kind == "visual_bullet" else PackedVector2Array(),
			sparks if kind == "spark" else empty, torpedoes if kind == "torpedo" else empty)
		await _layer_case("projectile_" + kind, canvas, true)
	canvas.painter = Callable()
	canvas.queue_redraw()
	ac.position = Vector2.ZERO
	ac.reset_physics_interpolation()
	var trail := TrailRibbon.new()
	ac.add_child(trail)
	for i in range(20):
		trail.add_point(Vector2(-100 + i * 5, 30 + i), 0.5, 0.0)
	trail._visibility_fade_in = 1.0
	trail._was_culled = false
	await _layer_case("trail_moving", trail, true)
	trail.set_emission_enabled(false)
	await _layer_case("trail_hidden", trail, false)
	trail.queue_free()
	await get_tree().process_frame

func _control_cases() -> void:
	_reset()
	ac.queue_redraw()
	canvas.queue_redraw()
	var mode := Mode.new()
	mode.player_aircraft = ac
	mode._squad_cmd = SquadCommandController.new()
	mode._squad_cmd.params = RtsCommandParams.new()
	mode._squad_cmd.params.auto_engage_radius_px = 140.0
	add_child(mode)
	var wheel := CommandWheel.new()
	wheel.setup(mode, CommandWheelParams.new())
	add_child(wheel)
	var layer := CanvasLayer.new()
	add_child(layer)
	var control := Control.new()
	layer.add_child(control)
	wheel._press_target = target
	var draw_highlight := wheel._draw_target_highlight.bind(control)
	control.draw.connect(draw_highlight)
	await _layer_case("wheel_target", control, true)
	control.draw.disconnect(draw_highlight)
	wheel._hover_slot = "auto_engage"
	var draw_range := wheel._draw_range_circles.bind(control)
	control.draw.connect(draw_range)
	await _layer_case("wheel_auto_range", control, true)
	var circles := wheel._slot_range_circles("auto_engage")
	if circles[0]["center"].distance_to(Pacing.display_origin(ac)) > 0.01:
		failures += 1
	control.draw.disconnect(draw_range)
	wheel._press_screen = get_viewport_rect().size * 0.5
	wheel._press_at_s = Time.get_ticks_msec() / 1000.0 - 0.2
	var draw_charge := wheel._draw_charge_ring.bind(control)
	control.draw.connect(draw_charge)
	await _layer_case("wheel_charge", control, true)
	control.draw.disconnect(draw_charge)
	layer.queue_free()
	wheel.queue_free()
	mode._squad_cmd.free()
	mode.queue_free()
	await get_tree().process_frame
	var arrow := ZoneArrow.new()
	var zones := ZoneData.new(Callable(), false)
	zones.selected_id = &"A"
	arrow.setup(ac, camera, zones)
	add_child(arrow)
	await _layer_case("zone_arrow", arrow._draw_node, true)
	zones.selected_id = &""
	await _layer_case("zone_arrow_clear", arrow._draw_node, false)
	arrow.queue_free()
	await get_tree().process_frame

func _hud_cases() -> void:
	_reset()
	ac.queue_redraw()
	canvas.queue_redraw()
	var mode := Mode.new()
	add_child(mode)
	camera.name = "Camera2D"
	camera.reparent(mode)
	var hud := Hud.new()
	hud.game_scene = mode
	hud.survivor_player = SurvivorPlayer.new()
	hud.survivor_player.aircraft = ac
	add_child(hud)
	var radar := SurvivorHUD.RadarDisplay.new()
	radar.hud = hud
	hud.add_child(radar)
	target.is_mission_target = true
	target.position = Vector2(1400, -1100)
	target.reset_physics_interpolation()
	await _layer_case("hud_radar", radar, true)
	target.sensor_contact_hidden = true
	await _layer_case("hud_radar_stealth_hint", radar, true)
	hud.survivor_player.aircraft = target
	await _layer_case("hud_radar_control_switch", radar, true)
	hud.survivor_player.aircraft = ac
	ac.is_destroyed = true
	await _layer_case("hud_radar_destroyed", radar, false)
	ac.is_destroyed = false
	radar.queue_free()
	await get_tree().process_frame
	var threat := SurvivorHUD.ThreatOverlay.new()
	threat.hud = hud
	hud.add_child(threat)
	target.sensor_contact_hidden = false
	target.combat_target = ac
	target.position = Vector2(5000, 1500)
	target.reset_physics_interpolation()
	await _layer_case("hud_threat_offscreen", threat, true)
	target.radar_targets[ac] = ac.params.lock_time
	await _layer_case("hud_threat_locked", threat, true)
	target.position = ac.position + Vector2(20, 20)
	target.reset_physics_interpolation()
	await _layer_case("hud_threat_onscreen_clear", threat, false)
	camera.offset = Vector2(-6000, 0)
	await _layer_case("hud_player_offscreen", threat, true)
	camera.offset = Vector2.ZERO
	threat.queue_free()
	camera.reparent(self)
	hud.survivor_player.free()
	hud.survivor_player = null
	hud.queue_free()
	mode.queue_free()
	await get_tree().process_frame

func _ground_ring_cases() -> void:
	_reset()
	ac.queue_redraw()
	canvas.queue_redraw()
	var ground := CombatUnit.new()
	add_child(ground)
	ground.position = ac.position
	ground.deadair_exposure_ratio = 0.375
	CombatUnit.all_units.assign([ground])
	var layer := CanvasLayer.new()
	add_child(layer)
	var overlay := WorldUnitStatusOverlay.new()
	layer.add_child(overlay)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: Node2D = overlay._tactical_panels.get(ground.get_instance_id())
	if panel == null:
		failures += 1
	else:
		await _layer_case("deadair_ground", panel, true)
	ground.deadair_exposure_ratio = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _layer_case("deadair_ground_clear", overlay, false)
	if not overlay._tactical_panels.is_empty():
		failures += 1
	ground.queue_free()
	layer.queue_free()
	CombatUnit.all_units.assign([ac, target])
	await get_tree().process_frame
