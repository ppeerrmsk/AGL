extends RefCounted
## HLOD默认只修正重复底色相乘；纯色几何检查显式开启，不作为已批准画面。
const Surface := preload("res://resources/shaders/tokyo_volume_surface.gdshader")
const LIGHT := "DIFFUSE_LIGHT += ALBEDO * ATTENUATION *"


static func shader_code() -> String:
	assert(Surface.code.count(LIGHT)==1)
	# GLES3最终合成已经将diffuse_light乘以albedo，不能在light()再乘一次。
	# legacy_tint仅供同一帧场景A/B取证，默认修正。
	return Surface.code.replace("shader_type spatial;", "shader_type spatial;\nuniform bool legacy_tint = false;").replace(LIGHT,"DIFFUSE_LIGHT += (legacy_tint ? ALBEDO : vec3(1.0)) * ATTENUATION *")


static func textured_code() -> String:
	# 显式纯色几何对照：暴露XZ投影纹理掩盖的方格代理；默认不启用。
	var code := shader_code().replace("specular_disabled;","specular_disabled, cull_disabled;")
	code=code.replace("shader_type spatial;","shader_type spatial;\nuniform sampler2D overview : filter_linear_mipmap, repeat_disable;\nuniform bool wall_solid_color = false;\nuniform bool ordinary_building = false;")
	# 沿用早期volume_preview_factory的LOW_WALL色，不用普通网格占位色冒充墙面。
	var wall := Color("747c79")
	var wall_code := "vec3(%.9f,%.9f,%.9f)" % [wall.r,wall.g,wall.b]
	var roof := Color(preload("res://scripts/experiments/tokyo_palette.gd").PAIRS["929789"])
	var roof_code := "vec3(%.9f,%.9f,%.9f)" % [roof.r,roof.g,roof.b]
	return code.replace("vec3 base = COLOR.rgb;","vec4 sample_color=texture(overview,UV);\nif(sample_color.a<0.001){discard;}\nvec3 base=sample_color.rgb/max(sample_color.a,0.001);\nif(wall_solid_color && ordinary_building){base=abs(normalize(world_normal).y)<0.50 ? "+wall_code+" : "+roof_code+";}")


static func native_code() -> String:
	# 原生顶点仍为旧平坦色板；在插值前精确映射一次，未知色与alpha不变。
	var remap := ""
	var pairs: Dictionary = preload("res://scripts/experiments/tokyo_palette.gd").PAIRS
	for old: String in pairs:
		var source := Color.html(old)
		var target := Color.html(pairs[old])
		remap+="if(COLOR.a==1.0 && all(lessThan(abs(COLOR.rgb-vec3(%.9f,%.9f,%.9f)),vec3(0.0000039)))) { COLOR.rgb=vec3(%.9f,%.9f,%.9f); }\n" % [source.r,source.g,source.b,target.r,target.g,target.b]
	return shader_code().replace("void vertex() {","void vertex() {\n"+remap)
