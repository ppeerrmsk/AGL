extends "res://scripts/survivor/survivor_mode.gd"
## F6 手动实验入口；继承正式 Survivor，不复制玩法或用 bench AI 代替玩家。
const VolumeProbe := preload("res://scripts/experiments/volume_world_probe.gd")
const PROFILE_PATH := "res://resources/player/playable_f47.tres"
const SMOKE_SCENARIO := "volume_3d_combat"
var volume_probe: Node3D


func _ready() -> void:
	var automated := String(get_tree().get_meta("bench_scenario", "")) == SMOKE_SCENARIO
	# 只在显式自动 smoke 时有结束计时；F6 和 F8 重开始终是用户操作的 Boss Debug。
	for key in ["bench_mode", "bench_scenario", "bench_duration", "bench_demo", "ugc_map_path"]:
		if get_tree().has_meta(key):
			get_tree().remove_meta(key)
	get_tree().set_meta("boss_debug_mode", true)
	get_tree().set_meta("boss_debug_id", "MOTHER_GOOSE")
	get_tree().set_meta("boss_debug_scenario", "full")
	get_tree().set_meta("boss_debug_node_id", "f47")
	get_tree().set_meta("survivor_aircraft_resource", PROFILE_PATH)
	get_tree().set_meta("survivor_map_id", "boss_debug")
	get_tree().set_meta("map_preview_only", false)
	super._ready()
	volume_probe = VolumeProbe.new()
	volume_probe.name = "VolumeWorldProbe"
	# 演出暂停的是模拟；只读显示必须继续跟随导演相机和被唤醒的演员。
	volume_probe.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(volume_probe)
	# 不以 mother_goose 结尾：该后缀只用于性能采样的强制 BOSS 相机。
	volume_probe.setup(self, "volume_3d_manual")
	print("[Volume manual] F-47 squad vs Mother Goose. Click: orders; wheel: zoom; Space: follow; Tab: build; Esc: pause; F8: restart. No automatic timeout.")
	if automated:
		_run_volume_smoke.call_deferred()


func _run_volume_smoke() -> void:
	# 验证器独立于会被 F8 释放的场景，真实重开后仍继续验证；手动入口不创建它。
	var smoke_script: GDScript = load("res://scripts/tests/volume_combat_smoke.gd")
	if smoke_script == null or not smoke_script.can_instantiate():
		get_tree().quit(1)
		return
	var smoke: Node = smoke_script.new()
	get_tree().root.add_child(smoke)
	smoke.run(self)
