extends Aircraft

## Visual QA 专用：复用真实 AircraftRenderer，但不启动物理、武器与尾迹。

var draw_runtime_label: bool = false
var draw_bank_volume: bool = true
var draw_esm_range: bool = false
var draw_combat_target_line: bool = false
var draw_probe_calls: int = 0
var draw_probe_usec: int = 0


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	queue_redraw()


func _draw() -> void:
	var started_usec := Time.get_ticks_usec()
	if draw_esm_range:
		AircraftRenderer.draw_esm_aura(self)
	if draw_combat_target_line:
		AircraftRenderer.draw_target_line(self)
	AircraftRenderer.draw_aircraft_icon(self, draw_bank_volume)
	if draw_runtime_label:
		if _font == null:
			_font = ThemeDB.fallback_font
		# 与 Aircraft._draw 保持同一状态栏分流，UAV 不能被 QA helper 误画成载人机完整栏。
		if is_drone:
			AircraftRenderer.draw_data_label_drone(self)
		elif AircraftRenderer.should_draw_compact_label(self):
			AircraftRenderer.draw_data_label_compact(self)
		elif hide_data_label:
			AircraftRenderer.draw_data_label_minimal(self)
		else:
			AircraftRenderer.draw_data_label(self)
	draw_probe_calls += 1
	draw_probe_usec += Time.get_ticks_usec() - started_usec


func reset_draw_probe() -> void:
	draw_probe_calls = 0
	draw_probe_usec = 0
