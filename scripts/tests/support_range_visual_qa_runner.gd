extends Node2D

## 真实 AircraftRenderer / CanvasItem 路径：绿=ALLY AWACS 8000m，蓝=玩家 ESM 3000m。

const PreviewAircraft := preload("res://scripts/tests/aircraft_silhouette_preview.gd")
const SupportRangeOverlayScript := preload("res://scripts/survivor/support_range_overlay.gd")


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))

	var background := ColorRect.new()
	background.color = Color("071018")
	background.position = Vector2.ZERO
	background.size = Vector2(1920, 1080)
	add_child(background)

	_add_label("AGL SUPPORT RANGE — RUNTIME CANVAS QA", Vector2(48, 30), 26,
		Color("dce9f2"))
	_add_label("ALLY AWACS 8000m", Vector2(48, 75), 18,
		GameConstants.COL_FRIEND_ALLY)
	_add_label("PLAYER ESM POD 3000m", Vector2(48, 105), 18,
		GameConstants.COL_FRIEND_PLAYER)

	# 真实世界半径按 0.18× 缩到同一张 1920×1080 样张；两圈重叠便于检查阵营色层级。
	var world := Node2D.new()
	world.position = Vector2(900.0, 540.0)
	world.scale = Vector2.ONE * 0.18
	add_child(world)

	var awacs := PreviewAircraft.new()
	awacs.params = (load("res://resources/enemy_tu160.tres") as AircraftParams).duplicate(true)
	awacs.params.display_name = "AWACS"
	awacs.params.icon_color = GameConstants.COL_FRIEND_ALLY
	awacs.params.wing_color = GameConstants.COL_FRIEND_ALLY
	awacs.team = CombatUnit.TEAM_ALLY
	awacs.altitude = 5500.0
	world.add_child(awacs)
	var awacs_range: Node2D = SupportRangeOverlayScript.new()
	awacs_range.setup(AwacsSupportEvent.BUFF_RADIUS_PX, awacs.team)
	awacs.add_child(awacs_range)

	var player := PreviewAircraft.new()
	player.params = (load("res://resources/player/player_ea18g.tres") as AircraftParams).duplicate(true)
	player.params.equipment.append(load("res://resources/esm_pod.tres").duplicate(true))
	player.team = CombatUnit.TEAM_PLAYER
	player.altitude = 5500.0
	player.position = Vector2(1800.0, 500.0)
	player.draw_esm_range = true
	world.add_child(player)

	_add_center_marker(Vector2(900.0, 540.0), GameConstants.COL_FRIEND_ALLY, "AWACS")
	_add_center_marker(Vector2(1224.0, 630.0), GameConstants.COL_FRIEND_PLAYER, "EA-18G / ESM")

	for _frame in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := "res://bench/results/support_range_visual.png"
	var error := get_viewport().get_texture().get_image().save_png(output)
	print("[support_range_visual] screenshot=%s err=%d" % [output, error])
	get_tree().quit(0 if error == OK else 1)


func _add_label(text: String, position: Vector2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)


func _add_center_marker(position: Vector2, color: Color, text: String) -> void:
	var marker := Label.new()
	marker.text = "+  " + text
	marker.position = position + Vector2(-8.0, -14.0)
	marker.add_theme_font_size_override("font_size", 16)
	marker.add_theme_color_override("font_color", color)
	add_child(marker)
