extends Node2D

## 同一真实 AircraftRenderer 路径并排比较旧纸片投影与体积投影，并记录 CPU 绘制构建成本。

const PreviewAircraft := preload("res://scripts/tests/aircraft_silhouette_preview.gd")

const ANGLES: Array[float] = [0.0, 30.0, 60.0, 80.0, 90.0, 120.0, 180.0]
const SAMPLES: Array[Dictionary] = [
	{"path": "res://resources/player/player_f14.tres", "label": "F-14", "scale": 1.70, "color": Color("4d83e6")},
	{"path": "res://resources/player/player_a10.tres", "label": "A-10", "scale": 1.70, "color": Color("4d83e6")},
	{"path": "res://resources/enemy_tu160.tres", "label": "TU-160", "scale": 0.82, "color": Color("e05245")},
	{"path": "res://resources/enemy_uav.tres", "label": "MQ-109", "scale": 3.20, "color": Color("d69743")},
	{"path": "res://resources/player/player_j36.tres", "label": "J-36 LEGACY", "scale": 1.70, "color": Color("9e73d6")},
]

var _flat_aircraft: Array[PreviewAircraft] = []
var _volume_aircraft: Array[PreviewAircraft] = []


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	_build_background()
	if not _build_matrix():
		get_tree().quit(1)
		return

	for _frame in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot_path := "res://bench/results/aircraft_bank_volume_visual.png"
	var screenshot_error := get_viewport().get_texture().get_image().save_png(screenshot_path)

	var flat_result := await _measure_group(_flat_aircraft)
	var volume_result := await _measure_group(_volume_aircraft)
	var report_error := _write_perf_report(flat_result, volume_result)
	print("[aircraft_bank_volume_visual] screenshot=%s err=%d flat=%s volume=%s report_err=%d" % [
		screenshot_path, screenshot_error, str(flat_result), str(volume_result), report_error])
	get_tree().quit(0 if screenshot_error == OK and report_error == OK else 1)


func _build_background() -> void:
	var background := ColorRect.new()
	background.color = Color("071018")
	background.position = Vector2.ZERO
	background.size = Vector2(1920, 1080)
	add_child(background)

	var title := Label.new()
	title.text = "AGL AIRCRAFT BANK VOLUME — REAL RENDERER QA"
	title.position = Vector2(48, 20)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("dce9f2"))
	add_child(title)

	var legend := Label.new()
	legend.text = "F = previous flat cos(bank)    V = volume shell + top/belly    |    every cell uses the same source silhouette"
	legend.position = Vector2(50, 58)
	legend.add_theme_font_size_override("font_size", 15)
	legend.add_theme_color_override("font_color", Color("8fa8b8"))
	add_child(legend)


func _build_matrix() -> bool:
	for column in range(ANGLES.size()):
		var angle_label := Label.new()
		angle_label.text = "%d°" % int(ANGLES[column])
		angle_label.position = Vector2(210 + column * 238, 98)
		angle_label.size = Vector2(120, 28)
		angle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		angle_label.add_theme_font_size_override("font_size", 17)
		angle_label.add_theme_color_override("font_color", Color("dce9f2"))
		add_child(angle_label)

	for row in range(SAMPLES.size()):
		var sample := SAMPLES[row]
		var params := load(String(sample.path)) as AircraftParams
		if params == null:
			push_error("[aircraft_bank_volume_visual] missing params: %s" % sample.path)
			return false
		var center_y := 190.0 + row * 174.0
		var model_label := Label.new()
		model_label.text = String(sample.label)
		model_label.position = Vector2(24, center_y - 14.0)
		model_label.size = Vector2(170, 28)
		model_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		model_label.add_theme_font_size_override("font_size", 16)
		model_label.add_theme_color_override("font_color", Color("a8bdc9"))
		add_child(model_label)

		for column in range(ANGLES.size()):
			var center_x := 270.0 + column * 238.0
			var flat := _make_aircraft(params, sample, Vector2(center_x - 45.0, center_y), ANGLES[column], false)
			var volume := _make_aircraft(params, sample, Vector2(center_x + 45.0, center_y), ANGLES[column], true)
			_flat_aircraft.append(flat)
			_volume_aircraft.append(volume)
	return true


func _make_aircraft(params: AircraftParams, sample: Dictionary, pos: Vector2,
		angle_deg: float, volume_enabled: bool) -> PreviewAircraft:
	var aircraft := PreviewAircraft.new()
	aircraft.params = params.duplicate(true)
	aircraft.params.icon_color = sample.color
	aircraft.params.wing_color = sample.color
	aircraft.bank_angle = deg_to_rad(angle_deg)
	aircraft.draw_bank_volume = volume_enabled
	aircraft.position = pos
	aircraft.scale = Vector2.ONE * float(sample.scale)
	add_child(aircraft)
	return aircraft


func _measure_group(group: Array[PreviewAircraft]) -> Dictionary:
	for aircraft in group:
		aircraft.reset_draw_probe()
	var wall_started := Time.get_ticks_usec()
	const PERF_FRAMES := 90
	for frame in range(PERF_FRAMES):
		for index in range(group.size()):
			var phase_deg := fmod(float(frame * 5 + index * 11), 360.0)
			group[index].bank_angle = deg_to_rad(phase_deg)
			group[index].queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var wall_usec := Time.get_ticks_usec() - wall_started
	var calls := 0
	var cpu_usec := 0
	for aircraft in group:
		calls += aircraft.draw_probe_calls
		cpu_usec += aircraft.draw_probe_usec
	return {
		"calls": calls,
		"cpu_usec": cpu_usec,
		"cpu_us_per_draw": float(cpu_usec) / maxf(float(calls), 1.0),
		"wall_ms_per_frame": float(wall_usec) / 1000.0 / float(PERF_FRAMES),
	}


func _write_perf_report(flat: Dictionary, volume: Dictionary) -> Error:
	var flat_cpu := float(flat.cpu_us_per_draw)
	var volume_cpu := float(volume.cpu_us_per_draw)
	var delta_cpu := volume_cpu - flat_cpu
	var delta_pct := delta_cpu / maxf(flat_cpu, 0.0001) * 100.0
	var text := "AGL AIRCRAFT BANK VOLUME PERF\n"
	text += "samples=%d angles=%d perf_frames=90\n" % [SAMPLES.size(), ANGLES.size()]
	text += "flat calls=%d cpu_usec=%d cpu_us_per_draw=%.4f wall_ms_per_frame=%.4f\n" % [
		int(flat.calls), int(flat.cpu_usec), flat_cpu, float(flat.wall_ms_per_frame)]
	text += "volume calls=%d cpu_usec=%d cpu_us_per_draw=%.4f wall_ms_per_frame=%.4f\n" % [
		int(volume.calls), int(volume.cpu_usec), volume_cpu, float(volume.wall_ms_per_frame)]
	text += "delta_cpu_us_per_draw=%+.4f delta_cpu_pct=%+.2f%%\n" % [delta_cpu, delta_pct]
	var file := FileAccess.open("res://bench/results/aircraft_bank_volume_perf.txt", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK
