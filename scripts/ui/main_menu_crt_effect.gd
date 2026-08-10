class_name MainMenuCrtEffect
extends ColorRect

## 对入口菜单屏幕做局部凸面畸变、扫描线、荧光晕与玻璃暗角。

const CRT_SHADER: Shader = preload("res://resources/shaders/main_menu_crt.gdshader")

var _crt_material: ShaderMaterial


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	color = Color.WHITE
	_crt_material = ShaderMaterial.new()
	_crt_material.shader = CRT_SHADER
	material = _crt_material


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _crt_material != null:
		_crt_material.set_shader_parameter("rect_pixel_size", size)
