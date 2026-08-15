extends RefCounted

const DamageVignetteScript := preload("res://scripts/survivor/damage_vignette.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 屏幕外圈反馈验收 ════════")
	_test_priority_and_colors()
	_test_timing_and_geometry()
	_test_freed_player_reference()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_priority_and_colors() -> void:
	var heal: Color = DamageVignetteScript.feedback_color(0.0, 0.0, 1.0)
	var warn: Color = DamageVignetteScript.feedback_color(0.0, 1.0, 1.0)
	var hurt: Color = DamageVignetteScript.feedback_color(1.0, 1.0, 1.0)
	_check("治疗为绿", _same_color(heal, Color("40ff66"), 0.55), str(heal))
	_check("黄优先于绿", _same_color(warn, Color("ffd933"), 0.55), str(warn))
	_check("红优先于黄绿", _same_color(hurt, Color("ff2626"), 0.55), str(hurt))


func _test_timing_and_geometry() -> void:
	_check("攻击速度 6/s", is_equal_approx(
		DamageVignetteScript.advance_alpha(0.0, true, 0.1), 0.6), "0.1s → 0.6")
	_check("衰减速度 2.5/s", is_equal_approx(
		DamageVignetteScript.advance_alpha(1.0, false, 0.1), 0.75), "0.1s → 0.75")
	_check("1080p 短边厚度 16.2px", is_equal_approx(
		DamageVignetteScript.band_thickness(Vector2(1920.0, 1080.0)), 16.2), "ratio=1.5%")


func _test_freed_player_reference() -> void:
	var vignette = DamageVignetteScript.new()
	var aircraft := Aircraft.new()
	vignette.set_player(aircraft)
	aircraft.free()
	_check("玩家对象释放后引用安全折叠", vignette._live_player() == null, "instance id cleared")
	vignette.free()


func _same_color(actual: Color, rgb: Color, alpha: float) -> bool:
	return is_equal_approx(actual.r, rgb.r) and is_equal_approx(actual.g, rgb.g) \
		and is_equal_approx(actual.b, rgb.b) and is_equal_approx(actual.a, alpha)


func _check(label: String, condition: bool, detail: String) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s — %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [label, detail])
