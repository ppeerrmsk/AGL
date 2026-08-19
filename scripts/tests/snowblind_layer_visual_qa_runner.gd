extends Node2D

## 真实 Snowblind shader + AircraftRenderer：玩家节点先生成、Snowblind 后生成，
## 专门覆盖曾让实体雪幕压住玩家机的 Canvas 排序回归。

const PreviewAircraft := preload("res://scripts/tests/aircraft_silhouette_preview.gd")
const SnowblindVisual := preload("res://scripts/survivor/snowblind_shroud_visual.gd")

var _transition_note: Label


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	RenderingServer.set_default_clear_color(Color("202a2e"))

	var camera := Camera2D.new()
	camera.zoom = Vector2(0.34, 0.34)
	add_child(camera)
	camera.make_current()

	_add_map_probes()

	# 先加玩家、后加 Snowblind：旧实现正是在这个正式局顺序下把玩家盖住。
	var player := PreviewAircraft.new()
	player.name = "PlayerBeforeSnowblind"
	player.params = (load("res://resources/player/player_f14.tres") as AircraftParams).duplicate(true)
	player.team = CombatUnit.TEAM_PLAYER
	player.callsign = "Ultra"
	player.altitude = 5500.0
	player.speed = 320.0
	player.hide_data_label = true
	player.draw_runtime_label = true
	player.position = Vector2(-520.0, 180.0)
	add_child(player)
	AircraftRenderer.player_ref = player

	var ally := PreviewAircraft.new()
	ally.name = "AllyBeforeSnowblind"
	ally.params = (load("res://resources/enemy_f15.tres") as AircraftParams).duplicate(true)
	ally.params.icon_color = GameConstants.COL_FRIEND_ALLY
	ally.params.wing_color = GameConstants.COL_FRIEND_ALLY
	ally.team = CombatUnit.TEAM_ALLY
	ally.callsign = "ALLY-PROBE"
	ally.altitude = 5500.0
	ally.speed = 280.0
	ally.hide_data_label = true
	ally.draw_runtime_label = true
	ally.position = Vector2(720.0, -340.0)
	add_child(ally)

	var host := PreviewAircraft.new()
	host.name = "SnowblindHostAfterPlayer"
	host.params = (load("res://resources/enemy_snowblind.tres") as AircraftParams).duplicate(true)
	host.team = CombatUnit.TEAM_HOSTILE
	host.sensor_hidden = true
	host.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(host)
	var shroud := SnowblindVisual.attach(host)

	_add_overlay(shroud)
	for _frame in range(8):
		await get_tree().process_frame
	_transition_note.text = "SOLID: concealment=%.3f" % _concealment(shroud)
	var solid_error := await _save_frame("res://bench/results/snowblind_layer_visual.png")

	SnowblindVisual.set_concealed(host, false)
	var breach_samples: Array[float] = [_concealment(shroud)]
	var breach_mid_error := OK
	for step in range(4):
		await get_tree().create_timer(0.2).timeout
		breach_samples.append(_concealment(shroud))
		if step == 1:
			_transition_note.text = "BREACH MIDPOINT 0.40s: concealment=%.3f" % breach_samples[-1]
			breach_mid_error = await _save_frame(
				"res://bench/results/snowblind_transition_breach_mid.png")

	SnowblindVisual.set_concealed(host, true)
	var restore_samples: Array[float] = [_concealment(shroud)]
	var restore_mid_error := OK
	for step in range(4):
		await get_tree().create_timer(0.2).timeout
		restore_samples.append(_concealment(shroud))
		if step == 1:
			_transition_note.text = "RESTORE MIDPOINT 0.40s: concealment=%.3f" % restore_samples[-1]
			restore_mid_error = await _save_frame(
				"res://bench/results/snowblind_transition_restore_mid.png")

	SnowblindVisual.set_concealed(host, false)
	await get_tree().create_timer(0.24).timeout
	var reversal_before := _concealment(shroud)
	SnowblindVisual.set_concealed(host, true)
	var reversal_after := _concealment(shroud)
	await get_tree().create_timer(0.2).timeout
	var reversal_progress := _concealment(shroud)
	var reversal_ok := absf(reversal_after - reversal_before) < 0.01 \
		and reversal_progress > reversal_after
	var transition_ok := breach_samples[0] > 0.99 and breach_samples[-1] < 0.05 \
		and restore_samples[0] < 0.05 and restore_samples[-1] > 0.95 \
		and _is_monotonic(breach_samples, false) \
		and _is_monotonic(restore_samples, true) and reversal_ok
	print("[snowblind_layer_visual] solid_err=%d breach_mid_err=%d restore_mid_err=%d z=%d relative=%s breach=%s restore=%s reversal=[%.3f, %.3f, %.3f]" % [
		solid_error, breach_mid_error, restore_mid_error, shroud.z_index,
		shroud.z_as_relative, str(breach_samples), str(restore_samples),
		reversal_before, reversal_after, reversal_progress])
	if not transition_ok:
		push_error("[snowblind_layer_visual] concealment transition is not smooth/complete")
	AircraftRenderer.player_ref = null
	get_tree().quit(0 if solid_error == OK and breach_mid_error == OK \
		and restore_mid_error == OK and transition_ok else 1)


func _add_map_probes() -> void:
	var map_fill := Polygon2D.new()
	map_fill.name = "MapProbe"
	map_fill.z_index = -50
	map_fill.polygon = PackedVector2Array([
		Vector2(-4000.0, -2500.0), Vector2(4000.0, -2500.0),
		Vector2(4000.0, 2500.0), Vector2(-4000.0, 2500.0),
	])
	map_fill.color = Color("5c6866")
	add_child(map_fill)
	for i in range(-7, 8):
		var grid := Line2D.new()
		grid.z_index = -49
		grid.width = 5.0
		grid.default_color = Color(0.12, 0.18, 0.18, 0.62)
		grid.points = PackedVector2Array([
			Vector2(float(i) * 400.0, -2400.0),
			Vector2(float(i) * 400.0, 2400.0),
		])
		add_child(grid)
	var surface_probe := Polygon2D.new()
	surface_probe.name = "GroundNavalProbe"
	surface_probe.z_index = -10
	surface_probe.polygon = PackedVector2Array([
		Vector2(-2600.0, 620.0), Vector2(2600.0, 620.0),
		Vector2(2600.0, 900.0), Vector2(-2600.0, 900.0),
	])
	surface_probe.color = Color("704733")
	add_child(surface_probe)


func _add_overlay(shroud: Polygon2D) -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var title := Label.new()
	title.text = "SNOWBLIND LAYER QA — PLAYER/ALLY MUST REMAIN ABOVE SOLID SHROUD"
	title.position = Vector2(38.0, 28.0)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("e7eef2"))
	overlay.add_child(title)
	var note := Label.new()
	note.text = "PASS: blue F-14 [Ultra] + green ally visible inside; map/grid/brown surface probe hidden under the field"
	note.position = Vector2(38.0, 64.0)
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color("c9d5da"))
	overlay.add_child(note)
	var z_note := Label.new()
	z_note.text = "runtime order: player -> ally -> Snowblind | shroud z=%d absolute" % shroud.z_index
	z_note.position = Vector2(38.0, 91.0)
	z_note.add_theme_font_size_override("font_size", 15)
	z_note.add_theme_color_override("font_color", Color("9fb3bc"))
	overlay.add_child(z_note)
	_transition_note = Label.new()
	_transition_note.position = Vector2(38.0, 118.0)
	_transition_note.add_theme_font_size_override("font_size", 15)
	_transition_note.add_theme_color_override("font_color", Color("b8cad2"))
	overlay.add_child(_transition_note)


func _concealment(shroud: Polygon2D) -> float:
	return float((shroud.material as ShaderMaterial).get_shader_parameter("concealment"))


func _save_frame(path: String) -> int:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image().save_png(path)


static func _is_monotonic(values: Array[float], increasing: bool) -> bool:
	for i in range(1, values.size()):
		if increasing and values[i] + 0.001 < values[i - 1]:
			return false
		if not increasing and values[i] - 0.001 > values[i - 1]:
			return false
	return true
