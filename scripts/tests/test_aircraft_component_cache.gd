extends RefCounted

## Aircraft 高频 Cobra/Herbst 组件缓存的生命周期契约。

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 飞机组件缓存测试 ════════")
	var ac := Aircraft.new()
	_check("空组件查询返回 null", ac.get_maneuver() == null and ac.get_herbst() == null)

	var cobra := CobraManeuver.new()
	ac.add_child(cobra)
	_check("新增 Cobra 后命中同一实例", ac.get_maneuver() == cobra)
	_check("稳定结构重复查询保持实例", ac.get_maneuver() == cobra and ac.get_herbst() == null)

	ac.remove_child(cobra)
	cobra.free()
	var herbst := HerbstManeuver.new()
	ac.add_child(herbst)
	_check("同数量替换仍使缓存失效", ac.get_maneuver() == null and ac.get_herbst() == herbst)

	ac.remove_child(herbst)
	herbst.free()
	_check("移除组件后不保留释放引用", ac.get_herbst() == null)
	ac.free()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s" % label)
