shader_type spatial;
render_mode depth_draw_never, cull_disabled, ambient_light_disabled, specular_disabled;
#include "map_contact_ao.gdshaderinc"
uniform sampler2D map_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D relief_texture : filter_linear, repeat_disable;
uniform float opacity = 1.0;
uniform float luma_scale = 1.0;

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

void vertex() {
	contact_ao_position = VERTEX;
	map_uv = (tile_origin_px + UV * tile_texture_size_px) / level_size_px;
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(map_texture, 0));
	vec4 color = texture(map_texture, UV);

	if (edge_gain > 0.001) {
		vec3 weights = vec3(0.299, 0.587, 0.114);
		float tl = dot(texture(map_texture, UV + vec2(-texel.x, -texel.y)).rgb, weights);
		float tm = dot(texture(map_texture, UV + vec2(0.0, -texel.y)).rgb, weights);
		float tr = dot(texture(map_texture, UV + vec2(texel.x, -texel.y)).rgb, weights);
		float ml = dot(texture(map_texture, UV + vec2(-texel.x, 0.0)).rgb, weights);
		float mr = dot(texture(map_texture, UV + vec2(texel.x, 0.0)).rgb, weights);
		float bl = dot(texture(map_texture, UV + vec2(-texel.x, texel.y)).rgb, weights);
		float bm = dot(texture(map_texture, UV + vec2(0.0, texel.y)).rgb, weights);
		float br = dot(texture(map_texture, UV + vec2(texel.x, texel.y)).rgb, weights);
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
	vec2 relief_uv = (map_uv * 256.0 + 0.5) / 257.0;
	vec3 relief_normal = texture(relief_texture, relief_uv).rgb;
	float relief_shade = 1.0 + clamp((dot(normalize(vec3(relief_normal.x * 6.0, relief_normal.y, relief_normal.z * 6.0)), normalize(vec3(-0.4, 0.8, -0.5))) - 0.780720058) * 2.0, -0.45, 0.24);
	vec3 base = clamp(color.rgb, 0.0, 1.0) * luma_scale * relief_shade;
ALBEDO = base; EMISSION = base * 0.65 * contact_ao_visibility(); ALPHA = opacity; ROUGHNESS = 1.0;
}

void light() { DIFFUSE_LIGHT += ALBEDO * ATTENUATION * 0.35; }
