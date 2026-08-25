extends Node2D

## 真实 Canvas 回归：大型机结构波、小型机受击分区响应与单次坠毁动画。

const F14_TEXTURE: Texture2D = preload("res://resources/aircraft_silhouettes/f14_detail.png")
const TU160_TEXTURE: Texture2D = preload("res://resources/aircraft_silhouettes/tu160_detail.png")
const CRASH_PARAMS: AircraftParams = preload("res://resources/enemy_f14.tres")
const ROUTE_NAMES: PackedStringArray = [
	"NOSE PORT SWEEP",
	"NOSE STARBOARD SWEEP",
	"TAIL RETURN",
	"WING ZIGZAG",
]
const SAMPLE_ELAPSED_S: Array[float] = [0.10, 0.28, 0.50]
const SAMPLE_HEADINGS_DEG: Array[float] = [0.0, 32.0, 146.0, 272.0]
const CRASH_PROGRESS_SAMPLES: Array[float] = [0.10, 0.40, 0.70, 1.00]
const HIT_ZONE_NAMES: PackedStringArray = [
	"NOSE", "TAIL / ENGINE", "PORT WING", "STARBOARD WING", "CENTER",
]
const HIT_ZONE_OFFSETS: Array[Vector2] = [
	Vector2(0.0, -100.0), Vector2(0.0, 100.0), Vector2(-100.0, 0.0),
	Vector2(100.0, 0.0), Vector2.ZERO,
]
const EXPECTED_HIT_ZONES: Array[StringName] = [
	AircraftDestruction.HIT_NOSE, AircraftDestruction.HIT_TAIL_ENGINE,
	AircraftDestruction.HIT_PORT_WING, AircraftDestruction.HIT_STARBOARD_WING,
	AircraftDestruction.HIT_CENTER,
]


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 1200))
	RenderingServer.set_default_clear_color(Color("10141a"))

	var background := ColorRect.new()
	background.color = Color("10141a")
	background.size = Vector2(1280.0, 1200.0)
	add_child(background)

	var title := Label.new()
	title.text = "LARGE AIRCRAFT ONLY — STRUCTURAL BREAKUP / 4 ROUTES"
	title.position = Vector2(42.0, 24.0)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("e9eef5"))
	add_child(title)

	var seen_routes: Dictionary = {}
	var sample_count := 0
	var wave_contract_ok := true
	var auto_route_probe := MissileManager.new()
	for expected_route in MissileManager.AIRFRAME_WAVE_ROUTE_COUNT:
		var start_index := auto_route_probe._hit_flashes.size()
		auto_route_probe.spawn_airframe_wave(
			Vector2.ZERO, 0.0, 20.0, 14.0, 1.0, -1, 0.0)
		for flash_index in range(start_index, auto_route_probe._hit_flashes.size()):
			if int(auto_route_probe._hit_flashes[flash_index]["route"]) != expected_route:
				wave_contract_ok = false
	auto_route_probe.free()
	for route in MissileManager.AIRFRAME_WAVE_ROUTE_COUNT:
		var header := Label.new()
		header.text = "%d  %s" % [route + 1, ROUTE_NAMES[route]]
		header.position = Vector2(40.0 + float(route) * 310.0, 82.0)
		header.add_theme_font_size_override("font_size", 15)
		header.add_theme_color_override("font_color", Color("cbd6e2"))
		add_child(header)

		for row in SAMPLE_ELAPSED_S.size():
			var elapsed := SAMPLE_ELAPSED_S[row]
			var sample_pos := Vector2(
				165.0 + float(route) * 310.0,
				205.0 + float(row) * 215.0)
			var heading := deg_to_rad(SAMPLE_HEADINGS_DEG[route])

			# 结构波只放在正式 Tu-160 大型机轮廓上；战斗机不再展示这种连续语法。
			var silhouette := Sprite2D.new()
			silhouette.texture = TU160_TEXTURE
			silhouette.global_position = sample_pos
			silhouette.rotation = heading
			silhouette.scale = Vector2.ONE * (62.0 / 128.0)
			silhouette.modulate = Color(0.92, 0.30, 0.20, 0.82)
			add_child(silhouette)

			var manager := MissileManager.new()
			manager.target_list = []
			add_child(manager)
			manager.set_physics_process(false)
			var extents := Vector2(30.0, 31.0)
			manager.spawn_airframe_wave(
				sample_pos, heading, extents.x, extents.y, 0.92, route, 0.0)
			if manager._hit_flashes.size() != 5:
				wave_contract_ok = false
			else:
				var point_indices: Dictionary = {}
				for step in manager._hit_flashes.size():
					var queued: Dictionary = manager._hit_flashes[step]
					point_indices[int(queued["point_index"])] = true
					if int(queued["route"]) != route or not is_equal_approx(
							float(queued["delay"]),
							float(step) * MissileManager.AIRFRAME_WAVE_INTERVAL):
						wave_contract_ok = false
				if point_indices.size() != 5:
					wave_contract_ok = false
			manager._update_hit_flashes(elapsed)
			manager.queue_redraw()

			for flash in manager._hit_flashes:
				if int(flash["route"]) == route:
					seen_routes[route] = true
			sample_count += 1

			var age_label := Label.new()
			age_label.text = "T + %.2fs" % elapsed
			age_label.position = sample_pos + Vector2(-35.0, 73.0)
			age_label.add_theme_font_size_override("font_size", 14)
			age_label.add_theme_color_override("font_color", Color("91a0b0"))
			add_child(age_label)

	if sample_count != 12 or seen_routes.size() != 4 or not wave_contract_ok:
		push_error("four-route airframe wave visual setup incomplete")
		get_tree().quit(1)
		return

	var hit_zone_title := Label.new()
	hit_zone_title.text = "SMALL AIRCRAFT — HIT LOCATION CHANGES THE LOSS OF CONTROL"
	hit_zone_title.position = Vector2(42.0, 748.0)
	hit_zone_title.add_theme_font_size_override("font_size", 18)
	hit_zone_title.add_theme_color_override("font_color", Color("e9eef5"))
	add_child(hit_zone_title)
	var hit_zone_contract_ok := true
	for i in HIT_ZONE_NAMES.size():
		var sample_pos := Vector2(130.0 + float(i) * 250.0, 860.0)
		var ac := Aircraft.new()
		ac.params = CRASH_PARAMS.duplicate(true)
		ac.callsign = "F14-ZONE"
		ac.team = CombatUnit.TEAM_HOSTILE
		ac.set_physics_process(false)
		add_child(ac)
		ac.global_position = sample_pos
		ac.altitude = 5200.0
		ac.speed = 240.0
		ac.heading = 0.0
		var incoming := Vector2.ZERO if i == 4 else Vector2(0.0, -600.0)
		var impact := AircraftDestruction.record_hit(
			ac, sample_pos + HIT_ZONE_OFFSETS[i], incoming)
		ac._start_destroy()
		ac._update_destroy(0.32)
		ac.global_position = sample_pos
		ac.queue_redraw()
		var manager := MissileManager.new()
		manager.target_list = []
		add_child(manager)
		manager.set_physics_process(false)
		manager.spawn_flash(impact, 0.0, 0.48)
		manager._update_hit_flashes(0.10)
		manager.queue_redraw()
		if ac._last_hit_zone != EXPECTED_HIT_ZONES[i]:
			hit_zone_contract_ok = false
		var zone_label := Label.new()
		zone_label.text = "%s\nYAW %+4.0f°/s   ROLL %+4.0f°/s" % [
			HIT_ZONE_NAMES[i], rad_to_deg(ac._destroy_spin),
			rad_to_deg(ac._destroy_bank_rate)]
		zone_label.position = sample_pos + Vector2(-88.0, 54.0)
		zone_label.add_theme_font_size_override("font_size", 12)
		zone_label.add_theme_color_override("font_color", Color("91a0b0"))
		add_child(zone_label)
	if not hit_zone_contract_ok:
		push_error("hit-location visual contract incomplete")
		get_tree().quit(1)
		return

	var crash_title := Label.new()
	crash_title.text = "SMALL AIRCRAFT CRASH — MODEL STAYS OPAQUE THROUGH THE END FLASH"
	crash_title.position = Vector2(42.0, 970.0)
	crash_title.add_theme_font_size_override("font_size", 18)
	crash_title.add_theme_color_override("font_color", Color("e9eef5"))
	add_child(crash_title)
	var crash_scales: Array[float] = []
	var crash_alphas: Array[float] = []
	for i in CRASH_PROGRESS_SAMPLES.size():
		var progress := CRASH_PROGRESS_SAMPLES[i]
		var sample_pos := Vector2(130.0 + float(i) * 300.0, 1080.0)
		var ac := Aircraft.new()
		ac.params = CRASH_PARAMS.duplicate(true)
		ac.callsign = "F14-LOSS"
		ac.team = CombatUnit.TEAM_HOSTILE
		ac.set_physics_process(false)
		add_child(ac)
		ac.global_position = sample_pos
		ac.altitude = 6000.0
		ac.speed = 230.0
		ac.heading = 0.0
		ac.rotation = ac.heading
		ac.bank_angle = deg_to_rad(28.0)
		ac.set_meta("_last_damage_kind", "missile")
		ac._start_destroy()
		# 固定自旋便于同一张样张比较四个时间切片，不消耗随机结果差异。
		ac._destroy_spin = deg_to_rad(160.0)
		var elapsed := ac._destroy_duration_total * progress
		ac._update_destroy(elapsed)
		ac.global_position = sample_pos
		crash_scales.append(ac._destroy_visual_scale)
		crash_alphas.append(ac._destroy_visual_alpha)
		ac.queue_redraw()

		var progress_label := Label.new()
		progress_label.text = "%d%%  S %.2f  A %.2f" % [
			roundi(progress * 100.0), ac._destroy_visual_scale,
			ac._destroy_visual_alpha]
		progress_label.position = sample_pos + Vector2(-62.0, 68.0)
		progress_label.add_theme_font_size_override("font_size", 13)
		progress_label.add_theme_color_override("font_color", Color("91a0b0"))
		add_child(progress_label)

	var crash_contract_ok := crash_scales.size() == 4 and crash_alphas.size() == 4
	for i in range(1, crash_scales.size()):
		crash_contract_ok = crash_contract_ok \
			and crash_scales[i] < crash_scales[i - 1] \
			and is_equal_approx(crash_alphas[i], 1.0)
	crash_contract_ok = crash_contract_ok \
		and is_equal_approx(crash_alphas[0], 1.0) \
		and is_equal_approx(crash_scales.back(), AircraftDestruction.CRASH_MODEL_END_SCALE) \
		and is_equal_approx(crash_alphas.back(), 1.0)
	if not crash_contract_ok:
		push_error("crash shrink/fade visual contract incomplete")
		get_tree().quit(1)
		return

	for _frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := "res://bench/results/hit_flash_visual.png"
	var error := get_viewport().get_texture().get_image().save_png(output)
	print("[hit_flash_visual] large_routes=%d samples=%d hit_zones=%d crash_samples=%d screenshot=%s err=%d" % [
		seen_routes.size(), sample_count, HIT_ZONE_NAMES.size(), crash_scales.size(), output, error])
	get_tree().quit(0 if error == OK else 1)
