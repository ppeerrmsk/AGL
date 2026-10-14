extends RefCounted
const Layer := preload("res://scripts/experiments/tokyo_static_shadow.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var rows := [{"size": 1024, "max_scale": 1.28}, {"size": 2048, "max_scale": 2.56}, {"size": 4096, "max_scale": 5.12}]
	_check(Layer.choose_row(rows, 1.28)["size"] == 1024, "coarse bound inclusive")
	_check(Layer.choose_row(rows, 1.281)["size"] == 2048, "nearer view selects fresh higher resolution")
	_check(Layer.choose_row(rows, 5.0)["size"] == 4096, "close view uses high resolution")
	_check(Layer.choose_row(rows, 5.121).is_empty() and Layer.choose_row(rows, 0).is_empty(), "reject missing resolution")
	_check(Layer.shader_code("invalid source").is_empty(), "shader source drift rejected")
	var code := Layer.shader_code(preload("res://resources/shaders/tokyo_volume_surface.gdshader").code)
	_check(code.contains("static_local = VERTEX") and code.contains("static_receiver"), "shadow uses source coordinates and receiver role")
	var layer := Layer.new()
	layer.close()
	layer.close()
	_check(layer._owner == null and layer._texture == null, "empty cleanup is idempotent")
	_check(load("res://scripts/tests/tokyo_static_shadow_review.gd").can_instantiate(), "static shadow Visual compiles")
	print("[R59 static shadow test] pass=", _pass, " fail=", _fail)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("[Bench] R59 " + label)
