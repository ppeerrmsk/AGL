extends RefCounted

## 未关注战区最简模拟：激活矩阵与 100+ 潜在成员不得进入实体层。

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 未关注战区最简模拟 ════════")
	_test_activation_matrix()
	_test_hundred_plus_latent_population()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_activation_matrix() -> void:
	_check("远处普通 AVAILABLE 保持 LATENT",
		not ZoneMission.zone_simulation_should_activate(
			ZoneData.State.AVAILABLE, 2, 5000.0, 1200.0))
	_check("普通 SELECTED 在远处也进入 LIVE",
		ZoneMission.zone_simulation_should_activate(
			ZoneData.State.SELECTED, 2, 5000.0, 1200.0))
	_check("未选择但进入圆内会进入 LIVE",
		ZoneMission.zone_simulation_should_activate(
			ZoneData.State.AVAILABLE, 1, 1199.0, 1200.0))
	_check("3★全局威胁公开即进入 LIVE",
		ZoneMission.zone_simulation_should_activate(
			ZoneData.State.AVAILABLE, 3, 50000.0, 1200.0))
	_check("LOCKED/CLEARED 不得激活",
		not ZoneMission.zone_simulation_should_activate(
			ZoneData.State.LOCKED, 3, 0.0, 1200.0)
		and not ZoneMission.zone_simulation_should_activate(
			ZoneData.State.CLEARED, 3, 0.0, 1200.0))


func _test_hundred_plus_latent_population() -> void:
	var potential_members := 0
	var live_members := 0
	for _zone_index in range(12):
		var roster_size := 10
		potential_members += roster_size
		if ZoneMission.zone_simulation_should_activate(
				ZoneData.State.AVAILABLE, 2, 20000.0, 3500.0):
			live_members += roster_size
	_check("120 名潜在普通战区成员全部停留在战略层",
		potential_members == 120 and live_members == 0)


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
