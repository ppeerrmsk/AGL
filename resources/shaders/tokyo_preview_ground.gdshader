shader_type spatial;
render_mode ambient_light_disabled, specular_disabled, cull_disabled;
uniform sampler2D map_texture : source_color, filter_linear;
uniform float luma_scale = 1.0;
void fragment() {
	vec3 raw = texture(map_texture, UV).rgb;
	float gray = dot(raw, vec3(0.299, 0.587, 0.114));
	vec3 base = (mix(vec3(gray), raw, 0.40) * 0.70 - 0.5) * 1.25 + 0.5;
	base = clamp(base * vec3(0.78, 0.82, 0.80) * luma_scale, vec3(0.0), vec3(1.0));
	ALBEDO = base;
	EMISSION = base * 0.70;
	ROUGHNESS = 1.0;
}
void light() {
	DIFFUSE_LIGHT += ALBEDO * ATTENUATION * 0.30;
}
