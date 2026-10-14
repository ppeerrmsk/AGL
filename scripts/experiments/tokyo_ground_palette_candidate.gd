extends RefCounted
## 只供静态审查：原生地表分类试色，不放大纹理或改变几何。
const Transfer := preload("res://scripts/experiments/tokyo_canvas_color.gd")
const LIGHT := preload("res://scripts/experiments/tokyo_low_light_candidate.gd").LIGHT
const COLORS: Array[Color] = [Color8(139,148,138),Color8(156,157,141),Color8(145,151,144),Color8(70,82,83),Color8(164,170,162),Color8(75,85,84),Color8(133,139,133),Color8(129,144,120),Color8(135,149,128),Color8(148,154,148),Color8(145,154,152)]


static func shader_code(original: String, bounds: Rect2 = Rect2(-6300,-3700,4000,2000)) -> String:
	if not preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd").valid_bounds(bounds):
		return ""
	if original.count(LIGHT)!=1 or original.count("ROUGHNESS = 1.0;")!=1 or original.count("void vertex() {")!=1 or original.contains("ground_palette_local"):
		return ""
	var declarations := Transfer.SHADER_CODE+"""
uniform vec3 ground_palette[11];
uniform int ground_palette_mask = -1;
uniform bool ground_palette_base_only = false;
uniform int ground_palette_only_class = -1;
varying vec3 ground_palette_local;
varying vec3 ground_palette_rgb;
varying float ground_palette_class;
varying float ground_palette_inside;
"""
	var vertex := "\n ground_palette_local=VERTEX; ground_palette_rgb=COLOR.rgb; ground_palette_class=-1.0;\n"
	for i in COLORS.size():
		var color := COLORS[i]
		vertex += " if(distance(COLOR.rgb,vec3(%.9f,%.9f,%.9f))<0.003) {ground_palette_class=%.1f; ground_palette_rgb=ground_palette[%d];}\n" % [color.r,color.g,color.b,float(i),i]
	var fragment := """
	ground_palette_inside = float(ground_palette_local.x >= -6300.0 && ground_palette_local.x <= -2300.0 && ground_palette_local.z >= -3700.0 && ground_palette_local.z <= -1700.0 && ground_palette_class >= -0.5);
	if(ground_palette_base_only && abs(ground_palette_class-9.0)>0.1) {ground_palette_inside=0.0;}
	if(ground_palette_only_class>=0 && abs(ground_palette_class-float(ground_palette_only_class))>0.1) {ground_palette_inside=0.0;}
	if(ground_palette_mask >= 0) {
	 if(ground_palette_local.x < -6300.0 || ground_palette_local.x > -2300.0 || ground_palette_local.z < -3700.0 || ground_palette_local.z > -1700.0) {discard;}
	 ALBEDO=vec3(0.0); EMISSION=vec3(float(abs(ground_palette_class-float(ground_palette_mask))<0.1));
	} else if(ground_palette_inside > 0.5) {
	 vec3 target=clamp(ground_palette_rgb,vec3(0.0),vec3(1.0));
	 ALBEDO=OUTPUT_IS_SRGB ? canvas_inverse_input(canvas_linear_target(target),target) : pow(target,vec3(2.2));
	 EMISSION=vec3(0.0);
	}
	ROUGHNESS = 1.0;
"""
	var light := "if(ground_palette_mask >= 0) {} else if(ground_palette_inside > 0.5) {DIFFUSE_LIGHT += vec3(0.75 + 0.25 * ATTENUATION);} else {"+LIGHT+"}"
	fragment = fragment.replace("-6300.0","%.6f" % bounds.position.x).replace("-2300.0","%.6f" % bounds.end.x).replace("-3700.0","%.6f" % bounds.position.y).replace("-1700.0","%.6f" % bounds.end.y)
	return original.replace("void vertex() {",declarations+"\nvoid vertex() {"+vertex).replace("ROUGHNESS = 1.0;",fragment).replace(LIGHT,light)


static func vectors(colors: Array[Color]) -> PackedVector3Array:
	var result := PackedVector3Array()
	for color in colors:
		result.append(Vector3(color.r,color.g,color.b))
	return result


static func semantic_colors(base: Color) -> Array[Color]:
	# 只校正共同底色偏差，保持类别相对色差；不把草地分别拟合成混合像素灰色。
	var delta := base-COLORS[9]
	var result: Array[Color] = []
	for color: Color in COLORS:
		result.append(Color(clampf(color.r+delta.r,0,1),clampf(color.g+delta.g,0,1),clampf(color.b+delta.b,0,1),1))
	return result
