extends RefCounted
## 北岸静态低楼试色；原轮廓/高度/标高楼/区外材质保留，不新增draw或纹理。
const Transfer := preload("res://scripts/experiments/tokyo_canvas_color.gd")
const LIGHT := "DIFFUSE_LIGHT += ALBEDO * ATTENUATION * 0.50 * (0.60 + 0.40 * max(dot(NORMAL, LIGHT), 0.0));"


static func shader_code(original: String, directional: float) -> String:
	if directional not in [0.10,0.25] or original.count(LIGHT) != 1 or original.contains("low_light_local"):
		return ""
	if original.count("ROUGHNESS = 1.0;") != 1 or original.count("void vertex() {") != 1:
		return ""
	var declarations := Transfer.SHADER_CODE+"\nvarying vec3 low_light_local;\nvarying float low_light_inside;\n"
	var fragment := """
	low_light_inside = float(low_light_local.x >= -6300.0 && low_light_local.x <= -2300.0 && low_light_local.z >= -3700.0 && low_light_local.z <= -1700.0);
	if (low_light_inside > 0.5) {
	 vec3 target = clamp(COLOR.rgb,vec3(0.0),vec3(1.0));
	 ALBEDO = OUTPUT_IS_SRGB ? canvas_inverse_input(canvas_linear_target(target),target) : pow(target,vec3(2.2));
	 EMISSION = vec3(0.0);
	}
	ROUGHNESS = 1.0;
"""
	var light := "if(low_light_inside > 0.5) { DIFFUSE_LIGHT += vec3(%s + %s * ATTENUATION * (0.60 + 0.40 * max(dot(NORMAL,LIGHT),0.0))); } else { %s }" % [str(1.0-directional),str(directional),LIGHT]
	return original.replace("void vertex() {",declarations+"\nvoid vertex() {\n low_light_local=VERTEX;").replace("ROUGHNESS = 1.0;",fragment).replace(LIGHT,light)
