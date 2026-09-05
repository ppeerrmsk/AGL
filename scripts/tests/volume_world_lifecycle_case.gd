extends RefCounted
## 被默认 lifecycle_gauntlet 调用；真实伤害、真实 queue_free 与下一消费者 tick。
const Probe := preload("res://scripts/experiments/volume_world_probe.gd")

class Host:
	extends Node2D
	var camera := Camera2D.new()
	var _map_features: CanvasItem
	var _building_renderer: CanvasItem

var _fail := 0
var _pass := 0


func run(parent: Node) -> int:
	var host := Host.new()
	parent.add_child(host)
	host.add_child(host.camera)
	var ac := Aircraft.new()
	ac.params = AircraftParams.new()
	ac.set_physics_process(false)
	host.add_child(ac)
	# 正式场由 SurvivorMode 刷新注册表；此隔离 fixture 明确登记真实 SceneTree 单位。
	CombatUnit.all_units.append(ac)
	var probe := Probe.new()
	host.add_child(probe)
	probe.setup(host, "volume_3d_c1")
	probe.set_process(false)
	Probe._set_body_override(ac, true)
	var mount := WeaponMount.new()
	var params := WeaponMountParams.new()
	params.max_hp = 200.0
	params.local_offset = Vector2(-63, 21)
	mount.initialize(params)
	ac.set_meta(&"mg_mounts", [mount])
	probe._counts["prop"] = 0
	probe._sync_goose_mounts(ac, Color.WHITE)
	_check(int(probe._counts["prop"]) == 1, "live mount is submitted")
	mount.apply_damage(200.0)
	await parent.get_tree().process_frame
	probe._counts["prop"] = 0
	probe._sync_goose_mounts(ac, Color.WHITE)
	_check(mount.destroyed and int(probe._counts["prop"]) == 0, "real mount death removes proxy next frame")
	ac.take_damage(99999.0, null, "missile")
	await parent.get_tree().process_frame
	probe._process(0.11)
	_check(ac.is_destroyed and not ac.has_meta(Probe.BODY_META), "real aircraft damage restores wreck renderer")
	var retained: Variant = ac
	CombatUnit.all_units.erase(ac)
	ac.queue_free()
	await parent.get_tree().process_frame
	probe._process(0.01)
	probe._process(0.11)
	_check(not is_instance_valid(retained), "freed cache consumer executes to completion")
	var survivor := Aircraft.new()
	survivor.set_physics_process(false)
	host.add_child(survivor)
	CombatUnit.all_units.append(survivor)
	probe._refresh_members()
	Probe._set_body_override(survivor, true)
	probe.queue_free()
	await parent.get_tree().process_frame
	_check(not survivor.has_meta(Probe.BODY_META), "adapter teardown restores surviving body")
	CombatUnit.all_units.erase(survivor)
	host.queue_free()
	await parent.get_tree().process_frame
	print("[Volume lifecycle] pass=%d fail=%d" % [_pass, _fail])
	return _fail


func _check(value: bool, label: String) -> void:
	if value:
		_pass += 1
	else:
		_fail += 1
		push_error("Volume lifecycle: " + label)
