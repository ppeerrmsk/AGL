
// 已驻留瓦片只读复用。地表接收实际三维阴影，不读取屏幕、TIME 或动态噪声。
uniform sampler2D map_texture : source_color, filter_linear, repeat_disable;
uniform vec3 tint : source_color = vec3(0.86, 0.84, 0.77);
uniform float saturation = 0.68;
uniform float brightness = 0.82;
uniform float contrast = 1.50;
uniform float opacity = 1.0;
uniform float luma_scale = 1.0;
uniform float detail_strength = 0.35;
uniform bool relief_enabled = false;
uniform bool source_is_satellite = false;
uniform bool terrain_detail_enabled = false;
uniform sampler2D terrain_detail_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 terrain_detail_mean_linear = vec3(0.15);
uniform vec3 terrain_detail_mean_srgb = vec3(0.40);
uniform bool clean_terrain_enabled = false;
uniform sampler2D clean_terrain_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 clean_terrain_world_rect;
uniform vec2 legacy_runway_start;
uniform vec2 legacy_runway_end;
uniform vec2 legacy_airport_boundary[18];
varying float vegetation_cover;
varying float terrain_height;
varying vec2 terrain_world;
#ifdef VOLUME_DECORATION
uniform vec4 decoration_world_rect;
uniform vec4 decoration_uv_rect;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 rock_mean_linear = vec3(0.15);
uniform vec3 rock_mean_srgb = vec3(0.40);
varying vec2 rock_uv;
varying float rock_weight;
#endif

void vertex() {
	terrain_height = VERTEX.y;
	terrain_world = VERTEX.xz;
#ifdef VOLUME_DECORATION
	UV = decoration_uv_rect.xy + (VERTEX.xz - decoration_world_rect.xy) / decoration_world_rect.zw * decoration_uv_rect.zw;
	vegetation_cover = 0.0;
	rock_uv = VERTEX.xz / 512.0;
	rock_weight = 1.0 - COLOR.a;
#else
	vegetation_cover = COLOR.r;
	if (relief_enabled) {
		vegetation_cover = CUSTOM0.w;
		NORMAL = vec3(CUSTOM0.x * 3.0, CUSTOM0.y, CUSTOM0.z * 3.0);
	}
#endif
}

vec3 crisp_sample(vec2 uv) {
	vec2 size = vec2(textureSize(map_texture, 0));
	vec2 position = uv * size - 0.5;
	vec2 base = floor(position) + 0.5;
	vec2 f = fract(position);
	vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
	vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
	vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
	vec2 w3 = f * f * (-0.5 + 0.5 * f);
	vec2 w12 = w1 + w2;
	vec2 p0 = (base - 1.0) / size;
	vec2 p12 = (base + w2 / w12) / size;
	vec2 p3 = (base + 2.0) / size;
	// Catmull–Rom 合并中间两权重为一次线性采样：9 taps，常量图保持常量。
	return clamp(
		texture(map_texture, vec2(p0.x, p0.y)).rgb * w0.x * w0.y
		+ texture(map_texture, vec2(p12.x, p0.y)).rgb * w12.x * w0.y
		+ texture(map_texture, vec2(p3.x, p0.y)).rgb * w3.x * w0.y
		+ texture(map_texture, vec2(p0.x, p12.y)).rgb * w0.x * w12.y
		+ texture(map_texture, p12).rgb * w12.x * w12.y
		+ texture(map_texture, vec2(p3.x, p12.y)).rgb * w3.x * w12.y
		+ texture(map_texture, vec2(p0.x, p3.y)).rgb * w0.x * w3.y
		+ texture(map_texture, vec2(p12.x, p3.y)).rgb * w12.x * w3.y
		+ texture(map_texture, p3).rgb * w3.x * w3.y, vec3(0.0), vec3(1.0));
}

void fragment() {
#ifdef VOLUME_DECORATION
	// 岩体沿同一世界投影取底色；不重复地表的边缘增强与水面邻域采样。
	vec3 raw = texture(map_texture, UV).rgb;
#else
	vec3 raw = crisp_sample(UV);
	vec2 texel = 1.0 / vec2(textureSize(map_texture, 0));
	float legacy_surface = 0.0;
	if (clean_terrain_enabled && terrain_world.x > 7670.0 && terrain_world.x < 8910.0
		&& terrain_world.y > 3370.0 && terrain_world.y < 4420.0) {
		// 只修真实机场多边形及16px羽化边，不把轴线包围盒跨到旁边公路。
		float distance_to_edge = 100000.0;
		bool inside = false;
		for (int i = 0; i < 18; i++) {
			vec2 a = legacy_airport_boundary[i];
			vec2 b = legacy_airport_boundary[(i + 1) % 18];
			vec2 ab = b - a;
			float along = clamp(dot(terrain_world - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
			distance_to_edge = min(distance_to_edge, length(terrain_world - a - ab * along));
			if ((a.y > terrain_world.y) != (b.y > terrain_world.y)) {
				float crossing = a.x + (terrain_world.y - a.y) * ab.x / ab.y;
				if (terrain_world.x < crossing) { inside = !inside; }
			}
		}
		legacy_surface = 1.0 - smoothstep(4.0, 16.0, inside ? -distance_to_edge : distance_to_edge);
		if (legacy_surface > 0.001) {
			vec2 clean_uv = clamp((terrain_world - clean_terrain_world_rect.xy)
				/ clean_terrain_world_rect.zw, vec2(0.0), vec2(1.0));
			vec3 clean_source = textureLod(clean_terrain_texture, clean_uv, 1.25).rgb;
			vec3 pale_sand_srgb = vec3(246.0, 231.0, 207.0) / 255.0;
			vec3 pale_sand_linear = vec3(0.92158, 0.79910, 0.62396);
			vec3 pale_sand = OUTPUT_IS_SRGB ? pale_sand_srgb : pale_sand_linear;
			// 周边2668个同源像素的分通道中位数；统一亮度会留下深色机场轮廓。
			vec3 carto_srgb = vec3(0.98212, 0.96982, 0.94994);
			vec3 carto = OUTPUT_IS_SRGB ? carto_srgb : pow((carto_srgb + 0.055) / 1.055, vec3(2.4));
			vec3 clean_raw = mix(pale_sand, clean_source, 0.18) * carto;
			raw = mix(raw, clean_raw, legacy_surface);
		}
	}
	vec3 local_mean = (texture(map_texture, UV + vec2(texel.x, 0.0)).rgb
		+ texture(map_texture, UV - vec2(texel.x, 0.0)).rgb
		+ texture(map_texture, UV + vec2(0.0, texel.y)).rgb
		+ texture(map_texture, UV - vec2(0.0, texel.y)).rgb) * 0.25;
	local_mean = mix(local_mean, raw, legacy_surface);
	// 水面内部烧入的单像素虚线：仅当四向邻域全为水色时抑制，外岸保留。
	vec3 east = texture(map_texture, UV + vec2(texel.x * 2.0, 0.0)).rgb;
	vec3 west = texture(map_texture, UV - vec2(texel.x * 2.0, 0.0)).rgb;
	vec3 north = texture(map_texture, UV + vec2(0.0, texel.y * 2.0)).rgb;
	vec3 south = texture(map_texture, UV - vec2(0.0, texel.y * 2.0)).rgb;
	float wet = (source_is_satellite ? 0.0 : 1.0) * step(0.03, east.b - east.r) * step(0.03, west.b - west.r)
		* step(0.03, north.b - north.r) * step(0.03, south.b - south.r);
	raw = mix(raw, (east + west + north + south) * 0.25, wet);
	local_mean = mix(local_mean, raw, wet);
	// 只增强源图真实边缘；幅度有界，不能从噪声生成不存在的道路。
	raw += clamp(raw - local_mean, vec3(-0.12), vec3(0.12)) * detail_strength;
#endif
	float gray = dot(raw, vec3(0.299, 0.587, 0.114));
	vec3 styled = mix(vec3(gray), raw, saturation) * brightness;
	styled = clamp(((styled - 0.5) * contrast + 0.5) * tint * luma_scale, vec3(0.0), vec3(1.0));
	if (relief_enabled && !source_is_satellite) {
		// 高坡以岩色分层，保留源图细节；不是重复覆盖一片纯色地块。
		float upland = smoothstep(80.0, 320.0, terrain_height);
		styled *= mix(vec3(1.0), vec3(1.12, 1.04, 0.91), upland * 0.65);
		// 曲率不是遥感植被分类；仅保留弱枯草色，不生成绿色森林带。
		styled = mix(styled, styled * vec3(0.98, 0.96, 0.83), vegetation_cover * 0.30);
		if (terrain_detail_enabled) {
			vec3 detail_mean = OUTPUT_IS_SRGB ? terrain_detail_mean_srgb : terrain_detail_mean_linear;
			vec3 terrain_detail = texture(terrain_detail_texture, terrain_world / 2048.0).rgb;
			vec3 variation = clamp(terrain_detail / max(detail_mean, vec3(0.01)), vec3(0.78), vec3(1.22));
			// 复用已经驻留的岩面纹理作为弱微地貌，不新增第二套地图或纯色色块。
			styled *= mix(vec3(1.0), variation * vec3(1.03, 0.99, 0.94), 0.08);
		}
	}
#ifdef VOLUME_DECORATION
	// 纹理只调制已完成地图调色的岩面，避免再次以高对比把深色照片压成黑块。
	if (rock_weight > 0.001) {
		vec3 mean_color = OUTPUT_IS_SRGB ? rock_mean_srgb : rock_mean_linear;
		vec3 variation = clamp(texture(rock_texture, rock_uv).rgb / max(mean_color, vec3(0.01)), vec3(0.75), vec3(1.25));
		styled *= mix(vec3(1.0), variation * vec3(0.99, 0.94, 0.89), rock_weight);
	}
#endif
	ALBEDO = styled;
	EMISSION = styled * 0.25;
	ROUGHNESS = 1.0;
	#ifdef VOLUME_TRANSPARENT
	ALPHA = opacity;
	#endif
}

void light() {
	// 引擎在合成光照时会乘 ALBEDO；真实影像不重复平方底色，旧 CARTO 外观暂保持。
	vec3 source_response = source_is_satellite ? vec3(1.0) : ALBEDO;
	DIFFUSE_LIGHT += source_response * ATTENUATION * (0.20 + 0.75 * max(dot(normalize(NORMAL), LIGHT), 0.0));
}
