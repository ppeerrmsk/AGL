extends Node2D

## 真实 BulletManager Visual：同一 8 发双侧涟发在近段 / 过渡段 / 远段的固定样张。

const ORIGIN_X := 260.0
const ROW_Y := [300.0, 500.0, 700.0]
const LAUNCH_HEADING := PI * 0.5
const ROCKET_SPEED_MS := 600.0
const STRAIGHT_DISTANCE_M := 180.0
const TRANSITION_DISTANCE_M := 320.0
const SPREAD_RAD := deg_to_rad(14.0)
const RIPPLE_INTERVAL := 0.08

var _source: CombatUnit


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	RenderingServer.set_default_clear_color(Color("0b1118"))

	var camera := Camera2D.new()
	camera.position = Vector2(500.0, 520.0)
	camera.zoom = Vector2(1.7, 1.7)
	add_child(camera)
	camera.make_current()

	_source = CombatUnit.new()
	_source.team = CombatUnit.TEAM_PLAYER
	_source.altitude = 5000.0
	_source.visible = false
	_source.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_source)

	_add_overlay_text()
	queue_redraw()

	var near_manager := _make_manager()
	await _spawn_ripple(near_manager, ROW_Y[0], 4)
	await get_tree().create_timer(0.12).timeout
	near_manager.set_physics_process(false)

	var transition_manager := _make_manager()
	await _spawn_ripple(transition_manager, ROW_Y[1], 8)
	await get_tree().create_timer(0.05).timeout
	transition_manager.set_physics_process(false)

	var far_manager := _make_manager()
	await _spawn_ripple(far_manager, ROW_Y[2], 8)
	await get_tree().create_timer(0.85).timeout
	far_manager.set_physics_process(false)

	await RenderingServer.frame_post_draw
	var output := "res://bench/results/rocket_trajectory_visual.png"
	var error := get_viewport().get_texture().get_image().save_png(output)
	print("[rocket_trajectory_visual] screenshot=%s err=%d" % [output, error])
	get_tree().quit(0 if error == OK else 1)


func _make_manager() -> BulletManager:
	var manager := BulletManager.new()
	manager.combat_unit_list = []
	add_child(manager)
	return manager


func _spawn_ripple(manager: BulletManager, row_y: float, count: int) -> void:
	var plan := AircraftWeapons.rocket_burst_plan(count, SPREAD_RAD, RIPPLE_INTERVAL)
	for i in range(plan.size()):
		var entry: Dictionary = plan[i]
		var pylon := int(entry["pylon"])
		var origin := Vector2(ORIGIN_X, row_y + float(pylon) * 18.0)
		manager.spawn_rocket(origin, LAUNCH_HEADING, ROCKET_SPEED_MS, _source,
			0.0, 2000.0, 0.0, 0.0, 0.0, float(entry["spread_offset"]),
			STRAIGHT_DISTANCE_M, TRANSITION_DISTANCE_M)
		if i < plan.size() - 1:
			await get_tree().create_timer(RIPPLE_INTERVAL).timeout


func _add_overlay_text() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_add_label(overlay, "ROCKET RIPPLE TRAJECTORY — REAL BULLET MANAGER PATH",
		Vector2(42.0, 26.0), 24, Color("e7edf3"))
	_add_label(overlay, "8-round alternating wing pylons  |  straight 180m  |  smooth spread over next 320m  |  final ±14°",
		Vector2(42.0, 60.0), 17, Color("8ea4b8"))
	_add_label(overlay, "NEAR — rockets leave both pylons as parallel streams",
		Vector2(42.0, 112.0), 18, Color("65d6ff"))
	_add_label(overlay, "TRANSITION — one continuous ripple spans straight and opening phases",
		Vector2(42.0, 458.0), 18, Color("ffd166"))
	_add_label(overlay, "FAR — the same ripple has reached the original fan spread",
		Vector2(42.0, 798.0), 18, Color("ff8b5e"))


func _add_label(parent: Node, value: String, pos: Vector2, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _draw() -> void:
	var straight_px := STRAIGHT_DISTANCE_M * CombatUnit.PIXELS_PER_METER
	var transition_px := TRANSITION_DISTANCE_M * CombatUnit.PIXELS_PER_METER
	for row_y in ROW_Y:
		# 真实世界距离带：蓝=严格直飞，琥珀=渐进展开；虚线位置在实际 180m/500m。
		draw_rect(Rect2(Vector2(ORIGIN_X, row_y - 45.0), Vector2(straight_px, 90.0)),
			Color(0.15, 0.55, 0.78, 0.10), true)
		draw_rect(Rect2(Vector2(ORIGIN_X + straight_px, row_y - 45.0),
			Vector2(transition_px, 90.0)), Color(0.95, 0.62, 0.18, 0.08), true)
		draw_dashed_line(Vector2(ORIGIN_X + straight_px, row_y - 58.0),
			Vector2(ORIGIN_X + straight_px, row_y + 58.0), Color("4ab8dc"), 1.0, 5.0)
		draw_dashed_line(Vector2(ORIGIN_X + straight_px + transition_px, row_y - 58.0),
			Vector2(ORIGIN_X + straight_px + transition_px, row_y + 58.0), Color("d68a34"), 1.0, 5.0)
		draw_line(Vector2(ORIGIN_X, row_y), Vector2(ORIGIN_X + 600.0, row_y),
			Color(0.52, 0.62, 0.7, 0.22), 1.0)
		# 极简俯视飞机 + 两侧挂点，作为真实出膛位置的视觉锚。
		var aircraft := PackedVector2Array([
			Vector2(ORIGIN_X + 12.0, row_y),
			Vector2(ORIGIN_X - 10.0, row_y - 12.0),
			Vector2(ORIGIN_X - 5.0, row_y),
			Vector2(ORIGIN_X - 10.0, row_y + 12.0),
		])
		draw_polyline(aircraft, Color("aebdca"), 1.5, true)
		draw_circle(Vector2(ORIGIN_X, row_y - 18.0), 2.2, Color("65d6ff"))
		draw_circle(Vector2(ORIGIN_X, row_y + 18.0), 2.2, Color("65d6ff"))
