shader_type spatial;
render_mode cull_disabled;
// 地图建筑专用；复用岩材质的低幅明暗，不改飞机或地理数据。
uniform sampler2D surface_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 surface_mean_srgb = vec3(0.4);
uniform vec3 surface_mean_linear = vec3(0.15);
varying vec2 surface_uv;
varying float roof_weight;
void vertex() {
	surface_uv = (VERTEX.xz + vec2(VERTEX.y * 0.7)) / 96.0;
	roof_weight = smoothstep(0.4, 0.9, NORMAL.y);
}
void fragment() {
	vec3 mean_color = OUTPUT_IS_SRGB ? surface_mean_srgb : surface_mean_linear;
	float grain = dot(texture(surface_texture, surface_uv).rgb / max(mean_color, vec3(0.01)), vec3(0.333333));
	float surface_value = mix(1.0, clamp(grain, 0.65, 1.20), mix(0.10, 0.22, roof_weight));
	ALBEDO = COLOR.rgb * surface_value;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
