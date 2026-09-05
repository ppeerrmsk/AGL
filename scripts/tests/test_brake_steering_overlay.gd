extends RefCounted

const OverlayScript := preload("res://scripts/survivor/brake_steering_overlay.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 急刹虚拟摇杆验收 ════════")
	_test_lifecycle_and_mapping()
	_test_edge_clamp()
	_test_stall_lock()
	_test_flight_data_and_gun_reference()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_lifecycle_and_mapping() -> void:
	var overlay = OverlayScript.new()
	overlay.size = Vector2(1280.0, 720.0)
	overlay.begin(Vector2(640.0, 360.0))
	var initial: Dictionary = overlay.debug_snapshot()
	_check("按下立即显示减速状态", initial.active and overlay.visible, str(initial))
	_check("摇杆锚定右键按下点", initial.anchor == Vector2(640.0, 360.0), str(initial.anchor))
	overlay.update_steer(Vector2(720.0, 500.0), 0.75)
	var steered: Dictionary = overlay.debug_snapshot()
	_check("舵量驱动摇杆帽水平位移", steered.knob_offset == Vector2(30.0, 0.0), str(steered.knob_offset))
	overlay.end()
	_check("松开原子隐藏并清零", not overlay.visible and not overlay.debug_snapshot().active \
		and is_zero_approx(float(overlay.debug_snapshot().steer)), str(overlay.debug_snapshot()))
	overlay.free()


func _test_edge_clamp() -> void:
	var center := OverlayScript.display_center_for(Vector2(3.0, 710.0), Vector2(1280.0, 720.0))
	_check("屏幕边缘夹紧且提示完整", center == Vector2(184.0, 616.0), str(center))
	_check("左右满舵镜像", OverlayScript.knob_offset_for(-1.0) == Vector2(-40.0, 0.0) \
		and OverlayScript.knob_offset_for(1.0) == Vector2(40.0, 0.0), "travel=40")


func _test_stall_lock() -> void:
	var overlay = OverlayScript.new()
	overlay.size = Vector2(1280.0, 720.0)
	overlay.begin(Vector2(500.0, 300.0))
	overlay.update_steer(Vector2(700.0, 300.0), 1.0)
	overlay.set_stall_locked(true)
	var locked: Dictionary = overlay.debug_snapshot()
	_check("失速锁定保留手势状态", locked.active and locked.stall_locked and is_equal_approx(locked.steer, 1.0), str(locked))
	overlay.set_stall_locked(false)
	_check("恢复保护结束解除锁定", not overlay.debug_snapshot().stall_locked, str(overlay.debug_snapshot()))
	overlay.free()


func _test_flight_data_and_gun_reference() -> void:
	var overlay = OverlayScript.new()
	overlay.size = Vector2(1280.0, 720.0)
	overlay.begin(Vector2(640.0, 360.0))
	overlay.set_flight_data(423.6, 1280.2, 217, 320, false)
	var data: Dictionary = overlay.debug_snapshot()
	_check("速度、剩余/最大弹药与有效射程明确发布", data.speed_kmh == 424 \
		and data.gun_range_m == 1280 and data.gun_ammo == 217 \
		and data.gun_max_ammo == 320 and not data.gun_ammo_infinite, str(data))
	overlay.set_flight_data(423.6, 1280.2, 217, 320, true)
	_check("无限弹药状态单独发布", overlay.debug_snapshot().gun_ammo_infinite,
		str(overlay.debug_snapshot()))
	overlay.free()

	var ac := Aircraft.new()
	ac.team = 0
	ac.hard_brake = true
	AircraftRenderer.player_ref = ac
	_check("当前操控机急刹时显示正式机炮射界",
		AircraftRenderer.should_show_gun_reference(ac), "hard_brake player")
	ac.hard_brake = false
	_check("非 hover 且未急刹时不常驻射界",
		not AircraftRenderer.should_show_gun_reference(ac), "idle player")
	AircraftRenderer.player_ref = null
	ac.free()


func _check(label: String, condition: bool, detail: String) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s — %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [label, detail])
