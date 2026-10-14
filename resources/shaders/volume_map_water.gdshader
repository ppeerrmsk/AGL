shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec3 water_color : source_color = vec3(0.23, 0.36, 0.35);
uniform bool sediment_enabled = false;
uniform sampler2D sediment_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sediment_mean_srgb = vec3(0.4);
uniform vec3 sediment_mean_linear = vec3(0.15);
varying vec2 water_world;
void vertex() {
	water_world = VERTEX.xz;
}
void fragment() {
	vec3 water = water_color;
	if (sediment_enabled) {
		vec3 mean_color = OUTPUT_IS_SRGB ? sediment_mean_srgb : sediment_mean_linear;
		float broad = dot(texture(sediment_texture, water_world / 4096.0).rgb / max(mean_color, vec3(0.01)), vec3(0.333333));
		float fine = dot(texture(sediment_texture, water_world / 700.0).rgb / max(mean_color, vec3(0.01)), vec3(0.333333));
		water *= clamp(0.85 + broad * 0.15 + (fine - 1.0) * 0.025, 0.91, 1.09);
	}
	ALBEDO = water;
	ALPHA = 1.0;
}
