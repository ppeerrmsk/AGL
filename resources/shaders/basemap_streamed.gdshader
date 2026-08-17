shader_type canvas_item;

// 三地图共享的稳定栅格 shader。每个瓦片只在创建时写入一次参数；
// 颗粒与暗角使用归一化地图坐标，不依赖 TIME，也不会在 LOD/瓦片边界跳相位。

uniform vec4 tint : source_color = vec4(1.0);
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.5, 2.0) = 1.0;
uniform float edge_floor : hint_range(0.0, 0.2) = 0.0;
uniform float edge_gain : hint_range(0.0, 3.0) = 0.0;
uniform float edge_cap : hint_range(0.0, 1.0) = 1.0;
uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform sampler2D grain_texture : repeat_enable, filter_linear_mipmap;
uniform float grain_strength : hint_range(0.0, 0.05) = 0.0;
uniform float grain_repeat : hint_range(1.0, 128.0) = 64.0;
uniform float vignette_strength : hint_range(0.0, 0.1) = 0.0;
uniform vec2 level_size_px = vec2(8704.0);
uniform vec2 tile_origin_px = vec2(0.0);
uniform vec2 tile_texture_size_px = vec2(8704.0);

varying vec2 map_uv;
varying vec4 item_modulate;

void vertex() {
	map_uv = (tile_origin_px + UV * tile_texture_size_px) / level_size_px;
	item_modulate = COLOR;
}

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec4 color = texture(TEXTURE, UV);

	if (edge_gain > 0.001) {
		vec3 weights = vec3(0.299, 0.587, 0.114);
		float tl = dot(texture(TEXTURE, UV + vec2(-texel.x, -texel.y)).rgb, weights);
		float tm = dot(texture(TEXTURE, UV + vec2(0.0, -texel.y)).rgb, weights);
		float tr = dot(texture(TEXTURE, UV + vec2(texel.x, -texel.y)).rgb, weights);
		float ml = dot(texture(TEXTURE, UV + vec2(-texel.x, 0.0)).rgb, weights);
		float mr = dot(texture(TEXTURE, UV + vec2(texel.x, 0.0)).rgb, weights);
		float bl = dot(texture(TEXTURE, UV + vec2(-texel.x, texel.y)).rgb, weights);
		float bm = dot(texture(TEXTURE, UV + vec2(0.0, texel.y)).rgb, weights);
		float br = dot(texture(TEXTURE, UV + vec2(texel.x, texel.y)).rgb, weights);
		float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
		float gy = -tl - 2.0 * tm - tr + bl + 2.0 * bm + br;
		float edge = min(max(sqrt(gx * gx + gy * gy) - edge_floor, 0.0) * edge_gain, edge_cap);
		color.rgb = mix(color.rgb, edge_color.rgb, edge);
	}

	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	color.rgb = mix(vec3(gray), color.rgb, saturation);
	color.rgb *= brightness;
	color.rgb = (color.rgb - 0.5) * contrast + 0.5;
	color.rgb *= tint.rgb;

	if (grain_strength > 0.0001) {
		// 64² 单通道蓝噪声跨三图复用；map_uv 保证所有 LOD/瓦片同相位，
		// mip 由像素 footprint 自动选择，避免缩放摩尔纹和程序 hash 编译尖峰。
		float grain = texture(grain_texture, map_uv * grain_repeat).r - 0.5;
		color.rgb += vec3(grain * grain_strength);
	}

	vec2 centered = map_uv * 2.0 - 1.0;
	float radial = clamp((dot(centered, centered) - 0.30) / 1.35, 0.0, 1.0);
	color.rgb *= 1.0 - radial * vignette_strength;
	COLOR = vec4(clamp(color.rgb, 0.0, 1.0), color.a) * item_modulate;
}
