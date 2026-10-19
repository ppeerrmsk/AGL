extends RefCounted
## 静态试色：仅北岸普通低楼，远景收敛明度，近景保持原色和原几何。


static func weight(scale: float) -> float:
	if not is_finite(scale) or scale<=0:
		return 0.0
	return 1.0-smoothstep(.30,.50,scale)


static func shader_code(original: String, factor: float) -> String:
	if factor not in [.90,.80] or original.count("void vertex() {")!=1 or original.count("ROUGHNESS = 1.0;")!=1 or original.contains("low_tone_local"):
		return ""
	var vertex := "uniform float low_tone_weight=0.0;\nvarying vec3 low_tone_local;\nvoid vertex() {\nlow_tone_local=VERTEX;"
	var fragment := """
	if(low_tone_local.x>=-6300.0 && low_tone_local.x<=-2300.0 && low_tone_local.z>=-3700.0 && low_tone_local.z<=-1700.0){
	 float tone=mix(1.0,%s,low_tone_weight); ALBEDO*=tone; EMISSION*=tone;
	}
	ROUGHNESS = 1.0;
""" % str(factor)
	return original.replace("void vertex() {",vertex).replace("ROUGHNESS = 1.0;",fragment)
