extends RefCounted

## 表现层几何合同：共享 triangle packet 不接受退化面，爆点在近轴航向仍保持合法批次，
## 地图/尾迹/爆点共用的 RenderingServer 提交签名可在 Godot 4.7 headless 下执行。

const TrianglePacket = preload("res://scripts/rendering/canvas_triangle_packet.gd")
const ExplosionPresenterScript = preload("res://scripts/rendering/explosion_presenter.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 表现层三角批次与爆点几何 ════════")
	_test_packet_building()
	_test_hit_flash_geometry()
	_test_rendering_server_submission()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _test_packet_building() -> void:
	var packet := TrianglePacket.create()
	_check(TrianglePacket.append_triangle(packet, Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN,
		Color.WHITE, 0.5), "合法三角进入共享 packet")
	_check(not TrianglePacket.append_triangle(packet, Vector2.ZERO, Vector2.RIGHT,
		Vector2(2.0, 0.0), Color.WHITE, 0.5), "退化三角被统一面积门拒绝")
	TrianglePacket.append_rect(packet, Rect2(2.0, 3.0, 4.0, 5.0), Color.RED)
	_check((packet["points"] as PackedVector2Array).size() == 9
		and (packet["indices"] as PackedInt32Array).size() == 9
		and (packet["colors"] as PackedColorArray).size() == 9,
		"矩形复用两三角并保持 points/indices/colors 对齐")
	var sequential := TrianglePacket.sequential_indices(9)
	_check(sequential.size() == 9 and sequential[0] == 0 and sequential[8] == 8,
		"顺序索引覆盖无索引爆点批次")


func _test_hit_flash_geometry() -> void:
	for heading in [0.0, 0.00001, PI * 0.25, PI * 0.5, PI - 0.00001]:
		var packet := ExplosionPresenterScript.hit_flash_cube_packet(
			Vector2(13.0, -8.0), heading, 22.0, 0.8)
		var points: PackedVector2Array = packet["points"]
		var colors: PackedColorArray = packet["colors"]
		var valid := not points.is_empty() and points.size() == colors.size() and points.size() % 3 == 0
		for index in range(0, points.size(), 3):
			valid = valid and absf((points[index + 1] - points[index]).cross(
				points[index + 2] - points[index])) >= 0.5
		_check(valid, "爆点 heading=%.5f 的面批次无退化三角" % heading)
		_check((packet["edge_points"] as PackedVector2Array).size() == 24
			and (packet["edge_colors"] as PackedColorArray).size() == 12,
			"爆点 heading=%.5f 保留 12 条结构棱" % heading)


func _test_rendering_server_submission() -> void:
	var item := RenderingServer.canvas_item_create()
	var valid := TrianglePacket.submit_arrays(
		item, PackedInt32Array([0, 1, 2]),
		PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN]),
		PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]))
	var invalid := TrianglePacket.submit_arrays(
		item, PackedInt32Array([0, 1]),
		PackedVector2Array([Vector2.ZERO, Vector2.RIGHT]),
		PackedColorArray([Color.WHITE, Color.WHITE]))
	RenderingServer.free_rid(item)
	_check(valid, "共享 packet 使用 Godot 4.7 triangle-array 签名提交")
	_check(not invalid, "共享 packet 拒绝非三角索引")


func _check(condition: bool, message: String) -> void:
	if condition:
		_pass += 1
		print("  ✓ ", message)
	else:
		_fail += 1
		printerr("  ✗ ", message)
