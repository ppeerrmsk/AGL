shader_type canvas_item;

// Tacview 风格主地图 shader：饱和度压制 + 色调 + 边缘检测描边
// Inspector 里调参数即时生效

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.5, 2.0) = 1.0;
// 边缘检测：在色彩转换处画描边（道路、海岸、建筑边界）
uniform float edge_strength : hint_range(0.0, 3.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// 噪点：加一点噪点模拟 CRT 颗粒感
uniform float noise_strength : hint_range(0.0, 0.3) = 0.0;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec4 color = texture(TEXTURE, UV);

	// --- Sobel 边缘检测 ---
	if (edge_strength > 0.01) {
		vec3 lum_w = vec3(0.299, 0.587, 0.114);
		float tl = dot(texture(TEXTURE, UV + vec2(-texel.x, -texel.y)).rgb, lum_w);
		float tm = dot(texture(TEXTURE, UV + vec2(0.0, -texel.y)).rgb, lum_w);
		float tr = dot(texture(TEXTURE, UV + vec2(texel.x, -texel.y)).rgb, lum_w);
		float ml = dot(texture(TEXTURE, UV + vec2(-texel.x, 0.0)).rgb, lum_w);
		float mr = dot(texture(TEXTURE, UV + vec2(texel.x, 0.0)).rgb, lum_w);
		float bl = dot(texture(TEXTURE, UV + vec2(-texel.x, texel.y)).rgb, lum_w);
		float bm = dot(texture(TEXTURE, UV + vec2(0.0, texel.y)).rgb, lum_w);
		float br = dot(texture(TEXTURE, UV + vec2(texel.x, texel.y)).rgb, lum_w);
		float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
		float gy = -tl - 2.0 * tm - tr + bl + 2.0 * bm + br;
		float edge = clamp(sqrt(gx * gx + gy * gy) * edge_strength, 0.0, 1.0);
		color.rgb = mix(color.rgb, edge_color.rgb, edge);
	}

	// --- 饱和度 ---
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	color.rgb = mix(vec3(gray), color.rgb, saturation);

	// --- 亮度 + 对比度 ---
	color.rgb *= brightness;
	color.rgb = (color.rgb - 0.5) * contrast + 0.5;

	// --- 色调 ---
	color.rgb *= tint.rgb;

	// --- 噪点 ---
	if (noise_strength > 0.001) {
		float n = rand(UV * 999.0 + TIME * 0.1) - 0.5;
		color.rgb += vec3(n * noise_strength);
	}

	color.rgb = clamp(color.rgb, 0.0, 1.0);
	COLOR = color;
}
