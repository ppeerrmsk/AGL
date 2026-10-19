// 克制军事地形：颜色只来自面材质与既有高度，不采样地图/噪声纹理。
#include "map_contact_ao.gdshaderinc"
uniform float opacity = 1.0;
#ifdef VOLUME_DECORATION
uniform vec3 sand_color : source_color = vec3(0.58, 0.55, 0.46);
#else
uniform vec3 sand_color : source_color = vec3(0.68, 0.63, 0.53);
// 以平地受光为支点收紧坡面明暗，不改变地形/贴地AO/米黄色板。
uniform float relief_contrast : hint_range(1.0, 2.0) = 1.5;
#endif
#ifdef VOLUME_DECORATION
uniform vec3 rock_color : source_color = vec3(0.52, 0.48, 0.40);
#else
// 米黄沙地与稍浅砂岩；仅换色相明度，保留原坡向和高度层次。
uniform vec3 rock_color : source_color = vec3(0.77, 0.71, 0.60);
#endif
varying float terrain_height;
void vertex() {
	contact_ao_position = VERTEX;
	terrain_height = VERTEX.y;
#ifndef VOLUME_DECORATION
	// 只放大已有坡向的照明响应；顶点与玩法高度完全不变。
	NORMAL = vec3(CUSTOM0.x * 6.0, CUSTOM0.y, CUSTOM0.z * 6.0);
#endif
}
void fragment() {
	vec3 base = mix(sand_color, rock_color, smoothstep(65.0, 300.0, terrain_height) * 0.60);
	ALBEDO = base;
	EMISSION = base * 0.28 * contact_ao_visibility();
	ROUGHNESS = 1.0;
#ifdef VOLUME_TRANSPARENT
	ALPHA = opacity;
#endif
}
void light() {
	float slope_light = max(dot(normalize(NORMAL), LIGHT), 0.0);
#ifndef VOLUME_DECORATION
	// 太阳俯角50度；连续坡向响应，不引入色阶条带或新的山形折面。
	float flat_light = 0.7660444431;
	// 极暗/极亮端渐收，避免硬截断把整片阴坡压成同色块。
	float shoulder = min(slope_light / flat_light, (1.0 - slope_light) / (1.0 - flat_light));
	slope_light += (relief_contrast - 1.0) * (slope_light - flat_light) * shoulder;
#endif
	DIFFUSE_LIGHT += ALBEDO * ATTENUATION * 1.18 * (0.10 + 0.90 * slope_light);
}
