shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
#include "map_contact_ao.gdshaderinc"
uniform bool native_palette = false;
varying float roof_weight;
void vertex() {
	contact_ao_position = VERTEX * vec3(1.0, 1.35, 1.0);
	roof_weight = smoothstep(0.4, 0.9, NORMAL.y);
}
void fragment() {
	// 旧细部保留少量明度差，统一色相；背景原生网格已使用同一有限色板。
	float value = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec3 base = native_palette ? COLOR.rgb : mix(vec3(0.50, 0.47, 0.41), vec3(0.75, 0.71, 0.63), roof_weight) * clamp(value / 0.60, 0.88, 1.08);
	if (!OUTPUT_IS_SRGB) { base = pow(base, vec3(2.2)); }
	ALBEDO = base;
	EMISSION = base * 0.50 * mix(contact_ao_visibility(), 1.0, roof_weight);
	ROUGHNESS = 1.0;
}
void light() {
	DIFFUSE_LIGHT += ALBEDO * ATTENUATION * 0.50 * (0.60 + 0.40 * max(dot(normalize(NORMAL), LIGHT), 0.0));
}
