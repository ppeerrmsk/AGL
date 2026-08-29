extends Node2D

## 用 Godot 真实 CanvasItem / AircraftRenderer 路径生成固定顶视轮廓样张。

const PreviewAircraft := preload("res://scripts/tests/aircraft_silhouette_preview.gd")
const PlayableSetup := preload("res://scripts/survivor/survivor_playable_setup.gd")

const SAMPLES: Array[Dictionary] = [
	{"path": "res://resources/player/player_f15c.tres", "label": "F-15C / PLAYER", "color": Color("4d83e6")},
	{"path": "res://resources/enemy_f15.tres", "label": "F-15 / ENEMY SAME PNG", "color": Color("e05245")},
	{"path": "res://resources/player/player_f14.tres", "profile": "res://resources/playable_f14.tres", "label": "F-14 PLAYER / RUNTIME NAME", "color": Color("4d83e6")},
	{"path": "res://resources/enemy_f104.tres", "label": "F-104", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_f104c.tres", "label": "F-104C / SAME MODEL", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_f4e.tres", "label": "F-4E / EXISTING MODEL", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_mig23.tres", "label": "MIG-23 / EXISTING MODEL", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_mig21f13.tres", "label": "MIG-21F-13 / NEW", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_j35f.tres", "label": "J 35F / NEW", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_ea6b.tres", "label": "EA-6B / NEW", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_jaguar.tres", "label": "JAGUAR / NEW", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_a10.tres", "label": "A-10", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_rafale.tres", "label": "RAFALE", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_typhoon.tres", "label": "TYPHOON", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_gripen_c.tres", "label": "GRIPEN", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_yf23.tres", "label": "YF-23", "color": Color("4d83e6")},
	{"path": "res://resources/enemy_fck1.tres", "label": "F-CK-1", "color": Color("4d83e6")},
	{"path": "res://resources/player/player_j36.tres", "label": "J-36 CONCEPT", "color": Color("9e73d6")},
	{"path": "res://resources/player/player_f47.tres", "label": "F-47 CONCEPT", "color": Color("9e73d6")},
	{"path": "res://resources/enemy_tu160.tres", "label": "TU-160", "color": Color("e05245"), "preview_scale": 0.72},
	{"path": "res://resources/friendly_b1b.tres", "label": "B-1B", "color": Color("4d83e6"), "preview_scale": 0.72},
	{"path": "res://resources/enemy_ah64.tres", "label": "AH-64", "color": Color("e05245"), "preview_scale": 1.25},
	{"path": "res://resources/enemy_ch47.tres", "label": "CH-47", "color": Color("61ad73"), "preview_scale": 0.72},
	{"path": "res://resources/enemy_uav.tres", "label": "MQ-109 / SHARED UAV PNG", "color": Color("e05245"), "preview_scale": 1.5},
	{"path": "res://resources/enemy_uav_missile.tres", "label": "MQ-110 / SAME PNG", "color": Color("d69743"), "preview_scale": 1.5},
	{"path": "res://resources/enemy_uav_mg_laser.tres", "label": "MQ-111 / SAME PNG", "color": Color("9e73d6"), "preview_scale": 1.5},
	{"path": "res://resources/enemy_uav_commander.tres", "label": "SENTINEL / LEGACY", "color": Color("e05245"), "preview_scale": 1.5},
	{"path": "res://resources/enemy_deadair.tres", "label": "DEADAIR / LEGACY", "color": Color("e05245")},
	{"path": "res://resources/enemy_mother_goose.tres", "label": "MOTHER GOOSE / LEGACY", "color": Color("e05245"), "preview_scale": 1.0},
]


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var ea6b_error := _ea6b_symmetry_error()
	if ea6b_error < 0.0 or ea6b_error > 0.08:
		push_error("[aircraft_silhouette_visual] EA-6B silhouette incomplete/asymmetric: %.3f" % ea6b_error)
		get_tree().quit(1)
		return
	var background := ColorRect.new()
	background.color = Color("071018")
	background.position = Vector2.ZERO
	background.size = Vector2(1920, 1080)
	add_child(background)

	var title := Label.new()
	title.text = "AGL AIRCRAFT TOP-VIEW SILHOUETTES — GODOT RUNTIME QA"
	title.position = Vector2(54, 22)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("dce9f2"))
	add_child(title)

	for index in range(SAMPLES.size()):
		var sample: Dictionary = SAMPLES[index]
		var resource := load(String(sample.path)) as AircraftParams
		if resource == null:
			push_error("[aircraft_silhouette_visual] missing params: %s" % sample.path)
			get_tree().quit(1)
			return
		var column := index % 6
		var row := index / 6
		var center := Vector2(160 + column * 320, 130 + row * 190)
		var aircraft := PreviewAircraft.new()
		aircraft.params = resource.duplicate(true)
		aircraft.params.icon_color = sample.color
		aircraft.params.wing_color = sample.color
		if sample.has("profile"):
			var profile := load(String(sample.profile)) as PlayableAircraft
			if profile == null:
				push_error("[aircraft_silhouette_visual] missing profile: %s" % sample.profile)
				get_tree().quit(1)
				return
			PlayableSetup.deep_dup_weapons(aircraft.params)
			PlayableSetup.apply(aircraft, profile)
			aircraft.callsign = "Ultra"
		aircraft.altitude = 5500.0
		aircraft.position = center
		aircraft.scale = Vector2.ONE * float(sample.get("preview_scale", 2.55))
		add_child(aircraft)

		var label := Label.new()
		label.text = String(sample.label)
		label.position = center + Vector2(-150, 58)
		label.size = Vector2(300, 30)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color("a8bdc9"))
		add_child(label)

	for _frame in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := "res://bench/results/aircraft_silhouette_visual.png"
	var error := get_viewport().get_texture().get_image().save_png(output)
	print("[aircraft_silhouette_visual] screenshot=%s err=%d samples=%d ea6b_symmetry=%.3f" % [
		output, error, SAMPLES.size(), ea6b_error])
	get_tree().quit(0 if error == OK else 1)


## 防止三视图裁切再次把半边识别图当成正式轮廓；0=完全对称，1=单侧缺失。
func _ea6b_symmetry_error() -> float:
	var image := Image.new()
	var png_bytes := FileAccess.get_file_as_bytes(
		"res://resources/aircraft_silhouettes/ea6b_detail.png")
	if png_bytes.is_empty() or image.load_png_from_buffer(png_bytes) != OK:
		return -1.0
	var difference := 0.0
	var occupied := 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width() / 2):
			var left := image.get_pixel(x, y).a
			var right := image.get_pixel(image.get_width() - 1 - x, y).a
			difference += absf(left - right)
			occupied += maxf(left, right)
	return difference / maxf(occupied, 0.001)
