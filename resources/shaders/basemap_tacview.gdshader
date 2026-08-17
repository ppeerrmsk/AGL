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
// 与 streamed 路径共享的世界空间静态蓝噪声；整图 UV 即全图归一化坐标。
// 禁止 TIME/hash，避免默认 PNG 路径闪烁并让两条路径使用同一颗粒权威。
uniform sampler2D grain_texture : repeat_enable, filter_linear_mipmap;
uniform float grain_strength : hint_range(0.0, 0.05) = 0.0;
uniform float grain_repeat : hint_range(1.0, 128.0) = 64.0;

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

	// --- 世界空间静态颗粒 ---
	if (grain_strength > 0.0001) {
		float grain = texture(grain_texture, UV * grain_repeat).r - 0.5;
		color.rgb += vec3(grain * grain_strength);
	}

	color.rgb = clamp(color.rgb, 0.0, 1.0);
	COLOR = color;
}
