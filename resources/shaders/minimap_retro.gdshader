shader_type canvas_item;

// 战术缩略图复古 shader：像素化 + 扫描线 + 色调
// 挂在 tactical_map._map_panel.material 上，所有绘制（底图/矢量/标记）统一走这个风格

// 像素化
uniform float pixel_size : hint_range(1.0, 16.0) = 4.0;
// 扫描线
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.30;
uniform float scanline_period_px : hint_range(1.0, 20.0) = 3.0;
// 色调（默认 CRT 战术屏绿）
uniform vec4 tint : source_color = vec4(0.70, 1.00, 0.75, 1.0);
uniform float saturation : hint_range(0.0, 2.0) = 0.55;
uniform float brightness : hint_range(0.0, 2.0) = 0.95;
// 边缘荧光（模拟 CRT 边缘发光）
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.25;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

void fragment() {
	// 像素化：SCREEN_UV 量化到像素网格 —— 用 screen_tex 重采样
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px_uv = floor(SCREEN_UV * screen_size / pixel_size) * pixel_size / screen_size;
	vec4 color = texture(screen_tex, px_uv);

	// 饱和度
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	color.rgb = mix(vec3(gray), color.rgb, saturation);

	// 亮度
	color.rgb *= brightness;

	// 色调叠加
	color.rgb *= tint.rgb;

	// 扫描线：周期性暗带（按屏幕 Y 像素）
	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159 / scanline_period_px);
	color.rgb *= 1.0 - (1.0 - scan) * scanline_strength;

	// 暗角：屏幕边缘变暗
	if (vignette_strength > 0.001) {
		vec2 from_center = SCREEN_UV - 0.5;
		float vign = 1.0 - smoothstep(0.25, 0.75, length(from_center)) * vignette_strength;
		color.rgb *= vign;
	}

	color.rgb = clamp(color.rgb, 0.0, 1.0);
	COLOR = color;
}
