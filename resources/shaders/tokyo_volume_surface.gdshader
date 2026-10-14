shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
uniform bool facade_detail = false;
uniform float lod_mix = 1.0;
uniform bool outgoing = false;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}
void fragment() {
	// 两档互补覆盖，不以半透明 ALPHA 叠加两次地表照明。
	float pattern = fract(dot(floor(FRAGCOORD.xy), vec2(0.754877666, 0.569840296)));
	if ((outgoing && pattern < lod_mix) || (!outgoing && pattern >= lod_mix)) { discard; }
	vec3 base = COLOR.rgb;
	if (facade_detail && COLOR.a > 0.5 && abs(normalize(world_normal).y) < 0.50) {
		float phase = world_position.y / 1.8;
		float footprint = fwidth(phase);
		float line = 1.0 - smoothstep(0.08, 0.08 + max(footprint, 0.04), abs(fract(phase) - 0.5));
		base *= 1.0 - line * 0.22 * (1.0 - smoothstep(0.45, 1.0, footprint));
	}
	if (!OUTPUT_IS_SRGB) { base = pow(base, vec3(2.2)); }
	ALBEDO = base;
	EMISSION = base * 0.50;
	ROUGHNESS = 1.0;
}
void light() {
	DIFFUSE_LIGHT += ALBEDO * ATTENUATION * 0.50 * (0.60 + 0.40 * max(dot(NORMAL, LIGHT), 0.0));
}
