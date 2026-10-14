extends "res://scripts/survivor/survivor_mode.gd"
## 完整沙漠流程的显式实验入口；显示层之外复用正式战区、单位和任务。
const VolumeProbe := preload("res://scripts/experiments/volume_world_probe.gd")
const MAP_PATH := "res://resources/maps/desert_railway_preview.aglmap"
var volume_probe: Node3D


func _ready() -> void:
	var scenario := String(get_tree().get_meta("bench_scenario", ""))
	var automated := scenario == "volume_3d_desert"
	var route_test := scenario == "volume_desert_route"
	var route_duration := float(get_tree().get_meta("bench_duration", 180.0))
	_allow_formal_aircraft_volume = false
	if route_test:
		var route_script: GDScript = load("res://scripts/tests/volume_desert_route.gd")
		if route_script == null or not route_script.can_instantiate() or not route_script.is_isolated_profile(
				OS.get_executable_path(), OS.get_user_data_dir()):
			printerr("[Volume route] REFUSED before Survivor: isolated user:// required; actual=", OS.get_user_data_dir())
			get_tree().quit(1)
			return
	for key in ["bench_mode", "bench_scenario", "bench_duration", "bench_demo",
			"boss_debug_mode", "boss_debug_id", "boss_debug_scenario", "boss_debug_node_id", "boss_debug_level"]:
		if get_tree().has_meta(key):
			get_tree().remove_meta(key)
	get_tree().set_meta("survivor_map_id", "desert_railway_preview")
	get_tree().set_meta("ugc_map_path", MAP_PATH)
	get_tree().set_meta("map_preview_only", false)
	get_tree().set_meta("survivor_aircraft_resource", "res://resources/player/playable_f15c.tres")
	super._ready()
	volume_probe = VolumeProbe.new()
	volume_probe.name = "VolumeWorldProbe"
	volume_probe.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(volume_probe)
	volume_probe.setup(self, "volume_3d_desert_manual")
	print("[Volume desert] Full desert gameplay, F-15C start. Click orders; Tab map; F8 restart. Experimental graphics, not performance approved. Normal rewards apply.")
	if route_test:
		var route: Node = load("res://scripts/tests/volume_desert_route.gd").new()
		get_tree().root.add_child(route)
		route.run_route.call_deferred(self, route_duration)
	if automated:
		var smoke_script: GDScript = load("res://scripts/tests/volume_desert_smoke.gd")
		if smoke_script == null or not smoke_script.can_instantiate():
			get_tree().quit(1)
			return
		var smoke: Node = smoke_script.new()
		get_tree().root.add_child(smoke)
		smoke.run.call_deferred(self)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		get_viewport().set_input_as_handled()
		Presentation.clear_all()
		get_tree().reload_current_scene()
		return
	super._unhandled_input(event)


func _start_first_run_tutorial() -> void:
	# 实验不消费或写入首次教学完成标记；不改变正式入口。
	pass


func archive_enabled() -> bool:
	return false


func _maybe_start_wingman_switch_tutorial() -> void:
	pass
