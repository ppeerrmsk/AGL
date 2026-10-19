shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// 岸线与路网共用几何抗锯齿，但岸线不能继承缺省白色顶点属性。
uniform bool vertex_color_enabled = false;
uniform bool rail_lod_enabled = false;
uniform bool route_coverage_enabled = false;
uniform bool watercourse_coverage_enabled = true;
uniform vec3 rail_far_color : source_color = vec3(0.34, 0.38, 0.33);
uniform vec4 line_color : source_color = vec4(0.43, 0.45, 0.36, 0.48);
uniform vec4 watercourse_color : source_color = vec4(0.30, 0.34, 0.29, 0.62);
uniform bool pixel_width_enabled = false;
uniform float minimum_width_px = 1.25;
varying vec2 line_world;
void vertex() {
	line_world = VERTEX.xz;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (pixel_width_enabled && !vertex_color_enabled && UV.x > 0.5 && length(UV2) > 0.0001) {
		vec4 other = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX + vec3(UV2.x, 0.0, UV2.y), 1.0));
		vec2 across_px = (other.xy / other.w - clip.xy / clip.w) * VIEWPORT_SIZE * 0.5;
		float width = length(across_px);
		float extra = max(0.0, minimum_width_px - width);
		clip.xy += across_px / max(width, 0.0001) * (UV.y - 0.5) * extra * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}
void fragment() {
	float edge_distance = 0.5 - abs(UV.y - 0.5);
	float aa = max(fwidth(UV.y), 0.0005);
	if (route_coverage_enabled && vertex_color_enabled) {
		// 同宽斜线不多削边；只改战术路线，河岸与原图回退沿用原覆盖。
		aa = max(length(vec2(dFdx(UV.y), dFdy(UV.y))), 0.0005);
	}
	vec4 ink = vertex_color_enabled ? COLOR : mix(line_color, watercourse_color, clamp(UV.x, 0.0, 1.0));
	if (rail_lod_enabled && vertex_color_enabled && UV2.x > 0.5) {
		float world_per_pixel = max(length(dFdx(line_world)), length(dFdy(line_world)));
		float detail = smoothstep(0.85, 1.70, 2.6 / max(world_per_pixel, 0.0001));
		if (UV2.x < 1.5) {
			ink.rgb = mix(rail_far_color, ink.rgb, detail);
		} else {
			ink.a *= detail;
		}
	}
	ALBEDO = ink.rgb;
	float coverage = smoothstep(0.0, aa * 0.65, edge_distance);
	if (watercourse_coverage_enabled && !vertex_color_enabled && UV.x > 0.5) {
		// 小于一像素时不再叠加向内削边，几何仍由原MSAA覆盖；三像素以上保持旧近景。
		coverage = mix(1.0, coverage, smoothstep(1.0, 3.0, 1.0 / aa));
	}
	ALPHA = ink.a * coverage;
}
