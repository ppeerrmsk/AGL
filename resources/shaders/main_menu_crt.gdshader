shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 rect_pixel_size = vec2(920.0, 540.0);
uniform float curvature = 0.065;
uniform float scanline_strength = 0.16;
uniform float grille_strength = 0.055;
uniform float bloom_strength = 0.14;
uniform float vignette_strength = 0.62;
uniform float noise_strength = 0.018;

float random_value(vec2 value) {
	return fract(sin(dot(value, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 local = UV * 2.0 - 1.0;
	float radius_squared = dot(local, local);
	vec2 curved = local * (1.0 + curvature * radius_squared);
	vec2 rect_span = rect_pixel_size * SCREEN_PIXEL_SIZE;
	vec2 rect_min = SCREEN_UV - UV * rect_span;
	vec2 rect_max = rect_min + rect_span;
	vec2 warped_uv = SCREEN_UV + (curved - local) * 0.5 * rect_span;
	warped_uv = clamp(warped_uv, rect_min + SCREEN_PIXEL_SIZE, rect_max - SCREEN_PIXEL_SIZE);

	vec3 source = texture(screen_texture, warped_uv).rgb;
	vec2 bloom_step = SCREEN_PIXEL_SIZE * 1.75;
	vec3 bloom = texture(screen_texture, clamp(warped_uv + vec2(bloom_step.x, 0.0), rect_min, rect_max)).rgb;
	bloom += texture(screen_texture, clamp(warped_uv - vec2(bloom_step.x, 0.0), rect_min, rect_max)).rgb;
	bloom += texture(screen_texture, clamp(warped_uv + vec2(0.0, bloom_step.y), rect_min, rect_max)).rgb;
	bloom += texture(screen_texture, clamp(warped_uv - vec2(0.0, bloom_step.y), rect_min, rect_max)).rgb;
	source += bloom * (bloom_strength * 0.25);

	float pixel_y = UV.y * rect_pixel_size.y;
	float scanline = 1.0 - scanline_strength * (0.5 + 0.5 * sin(pixel_y * 3.14159265));
	float pixel_x = UV.x * rect_pixel_size.x;
	float grille = 1.0 - grille_strength * (0.5 + 0.5 * cos(pixel_x * 2.0943951));
	float flicker = 0.985 + 0.015 * sin(TIME * 7.0);
	float rolling_band = 1.0 + 0.032 * exp(-pow(fract(UV.y + TIME * 0.055) - 0.5, 2.0) * 180.0);
	float noise = (random_value(floor(UV * rect_pixel_size) + floor(TIME * 24.0)) - 0.5) * noise_strength;

	vec2 rounded = abs(curved) - vec2(0.94, 0.91);
	float rounded_distance = length(max(rounded, vec2(0.0)))
		+ min(max(rounded.x, rounded.y), 0.0) - 0.055;
	float inside = 1.0 - smoothstep(-0.008, 0.012, rounded_distance);
	float vignette = 1.0 - vignette_strength * smoothstep(0.22, 1.65, radius_squared);

	float glare = exp(-length(local - vec2(-0.48, -0.56)) * 4.4) * 0.052;
	vec3 color = source * scanline * grille * flicker * rolling_band * vignette;
	color += vec3(noise) + vec3(0.08, 0.12, 0.09) * glare;
	COLOR = vec4(max(color, vec3(0.0)) * inside, 1.0);
}
