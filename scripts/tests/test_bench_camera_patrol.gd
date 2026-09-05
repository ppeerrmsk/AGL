extends RefCounted

## 自动战斗巡检镜头：确定性、全战线覆盖、缩放和旋转边界。

const Patrol = preload("res://scripts/bench/bench_camera_patrol.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 自动战斗巡检镜头测试 ════════")
	_test_deterministic_and_looping()
	_test_full_battlefield_coverage()
	_test_zoom_and_rotation_envelope()
	_test_hover_hitbox_is_screen_space()
	_test_segment_transitions_are_continuous()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_deterministic_and_looping() -> void:
	var first := Patrol.sample(7.25, 12000.0, 0.20)
	var repeated := Patrol.sample(7.25, 12000.0, 0.20)
	var looped := Patrol.sample(7.25 + Patrol.PERIOD_SECONDS, 12000.0, 0.20)
	_check("相同输入得到相同镜头姿态", first == repeated)
	_check("完整周期后严格回到同一轨迹点", _samples_near(first, looped, 0.001))


func _test_full_battlefield_coverage() -> void:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	var visited_mask := 0
	var count := Patrol.segment_count()
	for i in range(181):
		var t := float(i) / 180.0 * Patrol.PERIOD_SECONDS
		var state := Patrol.sample(t, 12000.0, 0.20)
		var pos: Vector2 = state["position"]
		min_pos = min_pos.min(pos)
		max_pos = max_pos.max(pos)
		visited_mask |= 1 << int(state["segment"])
	_check("一个周期访问全部巡检段", visited_mask == (1 << count) - 1)
	_check("镜头扫到南北两端战线", min_pos.y < -3600.0 and max_pos.y > 3600.0)
	_check("镜头扫到左右两侧战线", min_pos.x < -850.0 and max_pos.x > 850.0)
	_check("巡检位置不越出战场跨度", min_pos.y >= -4800.0 and max_pos.y <= 4800.0)


func _test_zoom_and_rotation_envelope() -> void:
	var min_zoom := INF
	var max_zoom := 0.0
	var min_rotation := INF
	var max_rotation := -INF
	for i in range(181):
		var state := Patrol.sample(float(i) / 180.0 * Patrol.PERIOD_SECONDS,
			12000.0, 0.20)
		min_zoom = minf(min_zoom, float(state["zoom"]))
		max_zoom = maxf(max_zoom, float(state["zoom"]))
		var rotation_deg := rad_to_deg(float(state["rotation"]))
		min_rotation = minf(min_rotation, rotation_deg)
		max_rotation = maxf(max_rotation, rotation_deg)
	_check("缩放覆盖总览与近景", min_zoom <= 0.201 and max_zoom >= 0.335)
	_check("缩放始终位于正式可达范围", min_zoom >= CameraController.ZOOM_MIN
		and max_zoom <= Patrol.ZOOM_MAX)
	_check("视角向两个方向旋转", min_rotation <= -13.5 and max_rotation >= 11.5)
	_check("旋转幅度保持可读", min_rotation >= -14.01 and max_rotation <= 12.01)


func _test_hover_hitbox_is_screen_space() -> void:
	var normal_world_radius := CameraController.hover_radius_world_for_zoom(1.0)
	var overview_world_radius := CameraController.hover_radius_world_for_zoom(
		CameraController.ZOOM_MIN)
	_check("总览缩放下 hover 命中半径仍保持 30 屏幕像素",
		is_equal_approx(normal_world_radius, CameraController.HOVER_RADIUS)
		and is_equal_approx(
			overview_world_radius * CameraController.ZOOM_MIN,
			CameraController.HOVER_RADIUS))


func _test_segment_transitions_are_continuous() -> void:
	var continuous := true
	var segment_duration := Patrol.PERIOD_SECONDS / float(Patrol.segment_count())
	for i in range(1, Patrol.segment_count()):
		var edge := float(i) * segment_duration
		var before := Patrol.sample(edge - 0.001, 12000.0, 0.20)
		var after := Patrol.sample(edge + 0.001, 12000.0, 0.20)
		var before_pos: Vector2 = before["position"]
		var after_pos: Vector2 = after["position"]
		if before_pos.distance_to(after_pos) > 0.1 \
				or absf(float(before["zoom"]) - float(after["zoom"])) > 0.001 \
				or absf(float(before["rotation"]) - float(after["rotation"])) > 0.001:
			continuous = false
			break
	_check("分段边界没有镜头跳变", continuous)


func _samples_near(a: Dictionary, b: Dictionary, tolerance: float) -> bool:
	var a_pos: Vector2 = a["position"]
	var b_pos: Vector2 = b["position"]
	return a_pos.distance_to(b_pos) <= tolerance \
		and absf(float(a["zoom"]) - float(b["zoom"])) <= tolerance \
		and absf(float(a["rotation"]) - float(b["rotation"])) <= tolerance \
		and int(a["segment"]) == int(b["segment"])


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
