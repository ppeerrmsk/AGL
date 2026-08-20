extends RefCounted

const Renderer := preload("res://scripts/aircraft_renderer.gd")
const Catalog := preload("res://scripts/aircraft_silhouette_catalog.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 飞机滚转体积投影验收 ════════")
	_test_projection_geometry()
	_test_face_fade()
	_test_family_thickness()
	_test_visual_noise()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


func _test_projection_geometry() -> void:
	var p0 := Renderer.bank_volume_projection_for(0.0, 0.22)
	_check("0° 保持原顶视宽度", _near(p0.x, 1.0) and _near(p0.y, 1.0), str(p0))
	_check("0° 表面不偏移", _near(p0.z, 0.0), str(p0))

	var p90 := Renderer.bank_volume_projection_for(PI * 0.5, 0.22)
	_check("90° 顶面归零但壳层保留 22%", p90.x < 0.0001 and _near(p90.y, 0.22), str(p90))
	_check("90° 表面偏向滚转侧", p90.z > 0.09 and p90.z < 0.10, str(p90))

	var p60 := Renderer.bank_volume_projection_for(deg_to_rad(60.0), 0.22)
	_check("60° 壳层宽于顶面", p60.y > p60.x and p60.x > 0.49, str(p60))
	var pn60 := Renderer.bank_volume_projection_for(deg_to_rad(-60.0), 0.22)
	_check("左右滚转厚度对称、偏移反向",
		_near(p60.x, pn60.x) and _near(p60.y, pn60.y) and _near(p60.z, -pn60.z),
		"right=%s left=%s" % [p60, pn60])

	var p180 := Renderer.bank_volume_projection_for(PI, 0.22)
	_check("180° 机腹恢复完整宽度", _near(p180.x, 1.0) and _near(p180.y, 1.0), str(p180))
	var safe := Renderer.bank_volume_projection_for(PI * 0.5, -1.0)
	_check("负厚度安全钳到零", safe.y < 0.0001, str(safe))


func _test_face_fade() -> void:
	_check("正侧面隐藏顶面", Renderer.bank_volume_face_alpha_for(0.0) == 0.0, "face=0")
	_check("18% 宽度恢复完整表面", _near(Renderer.bank_volume_face_alpha_for(0.18), 1.0), "face=0.18")
	var mid := Renderer.bank_volume_face_alpha_for(0.09)
	_check("交界区平滑过渡", mid > 0.45 and mid < 0.55, "alpha=%.3f" % mid)


func _test_family_thickness() -> void:
	var ac := Aircraft.new()
	_check("默认战斗机厚度 22%", _near(Catalog.volume_thickness_for(ac), 0.22), "default")
	ac.set_meta("silhouette", "bomber")
	_check("轰炸机厚度 17%", _near(Catalog.volume_thickness_for(ac), 0.17), "bomber")
	ac.set_meta("silhouette", "apache")
	_check("直升机厚度 30%", _near(Catalog.volume_thickness_for(ac), 0.30), "apache")
	ac.set_meta("silhouette", "hyper_a")
	_check("低矮升力体厚度 14%", _near(Catalog.volume_thickness_for(ac), 0.14), "hyper_a")
	ac.free()


func _test_visual_noise() -> void:
	var a := Renderer.visual_noise01_for(123, 7, 456)
	var b := Renderer.visual_noise01_for(123, 7, 456)
	var c := Renderer.visual_noise01_for(123, 8, 456)
	_check("视觉噪声同输入可复现", is_equal_approx(a, b), "a=%.6f b=%.6f" % [a, b])
	_check("视觉噪声限制在 0..1", a >= 0.0 and a < 1.0, "a=%.6f" % a)
	_check("视觉噪声 salt 可分流", not is_equal_approx(a, c), "a=%.6f c=%.6f" % [a, c])


func _near(actual: float, expected: float, epsilon: float = 0.0001) -> bool:
	return absf(actual - expected) <= epsilon


func _check(label: String, condition: bool, detail: String) -> void:
	if condition:
		_pass += 1
		print("  ✓ %s — %s" % [label, detail])
	else:
		_fail += 1
		print("  ✗ %s — %s" % [label, detail])
