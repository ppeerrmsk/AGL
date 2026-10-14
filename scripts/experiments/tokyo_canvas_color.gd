extends RefCounted
## GL近黑往返补偿；来源：Godot GLES3 tonemap_inc.glsl，必须以真实灰阶对照守门。
const SHADER_CODE := """
vec3 canvas_linear_target(vec3 color) {
 return pow((clamp(color,vec3(0.0),vec3(1.0))+vec3(0.055))/1.055,vec3(2.4));
}
vec3 canvas_inverse_input(vec3 target,vec3 estimate) {
 vec3 value = max(estimate,vec3(0.04));
 for(int i=0;i<5;i++) {
  vec3 error = value*(value*(value*0.305306011+0.682171111)+0.012522878)-target;
  vec3 slope = value*(value*0.915918033+1.364342222)+0.012522878;
  value = max(vec3(0.0),value-error/slope);
 }
 return value;
}
"""


static func finish(shadow: bool) -> String:
	var code := "vec3 source_rgb = clamp(color.rgb,0.0,1.0)*item_modulate.rgb; ALBEDO=source_rgb;"
	if shadow:
		code += " ROUGHNESS=1.0;"
	code += " if(OUTPUT_IS_SRGB) { vec3 target=canvas_linear_target(source_rgb); ALBEDO=canvas_inverse_input(target,source_rgb);"
	return code+" }"


static func input_for(value: float, weight: float = 1.0) -> float:
	var target := pow((clampf(value,0.0,1.0)+0.055)/1.055,2.4)*weight
	var result := maxf(value*weight,0.04)
	for n in 5:
		var error := result*(result*(result*0.305306011+0.682171111)+0.012522878)-target
		var slope := result*(result*0.915918033+1.364342222)+0.012522878
		result = maxf(0.0,result-error/slope)
	return result
