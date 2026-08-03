class_name SnowblindShroudVisual
extends RefCounted

## 单个静态圆形网格 + GPU 连续风雪。没有 _process/_draw/queue_redraw，CPU 成本不随帧率增长。

const RADIUS_PX: float = 2000.0
const SEGMENTS: int = 64

const SHADER_CODE: String = """
shader_type canvas_item;
render_mode unshaded;

varying vec2 local_pos;
uniform float concealment : hint_range(0.0, 1.0) = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float radius = length(local_pos);
	float body_mask = 1.0 - smoothstep(1780.0, 2000.0, radius);
	float rim = smoothstep(1680.0, 1900.0, radius) * (1.0 - smoothstep(1900.0, 2000.0, radius));

	// 连续漂移的实体雾团：锚定世界中的雪幕，不再随屏幕闪烁。
	vec2 wind = vec2(TIME * 0.055, TIME * -0.028);
	float cloud_large = value_noise(local_pos / 520.0 + wind);
	float cloud_small = value_noise(local_pos / 210.0 - wind * 1.7);
	float cloud = mix(cloud_large, cloud_small, 0.34);

	// 稀疏、缓慢的斜向雪带，只改变亮度，不制造高频 alpha 跳闪。
	vec2 snow_uv = local_pos / 34.0 + vec2(TIME * 0.34, TIME * 0.58);
	vec2 snow_cell = floor(snow_uv);
	float snow_seed = hash21(snow_cell);
	vec2 flake_pos = vec2(fract(snow_seed * 7.13), fract(snow_seed * 13.71));
	vec2 flake_delta = fract(snow_uv) - flake_pos;
	float flake_dist = length(vec2(flake_delta.x * 2.8, flake_delta.y));
	float streak = (1.0 - smoothstep(0.025, 0.11, flake_dist)) * step(0.78, snow_seed);

	vec3 fog_color = mix(vec3(0.50, 0.54, 0.58), vec3(0.78, 0.82, 0.86), cloud);
	fog_color += streak * 0.10;
	float solid_alpha = 1.0;
	float revealed_alpha = 0.08 + cloud * 0.04;
	float field_alpha = mix(revealed_alpha, solid_alpha, concealment);
	float rim_alpha = mix(0.12, 0.92, concealment);
	float alpha = body_mask * field_alpha + rim * rim_alpha;

	// 只显示“始作俑者”的不可交互轮廓；真实 Aircraft 仍处于 sensor_hidden。
	float core_d = segment_distance(local_pos, vec2(0.0, -34.0), vec2(9.0, 10.0));
	core_d = min(core_d, segment_distance(local_pos, vec2(9.0, 10.0), vec2(0.0, 29.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(0.0, 29.0), vec2(-9.0, 10.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(-9.0, 10.0), vec2(0.0, -34.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(-32.0, 8.0), vec2(0.0, -5.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(0.0, -5.0), vec2(32.0, 8.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(-27.0, 3.0), vec2(-27.0, 16.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(27.0, 3.0), vec2(27.0, 16.0)));
	float core_outline = (1.0 - smoothstep(0.9, 2.2, core_d)) * concealment;
	fog_color = mix(fog_color, vec3(0.68, 0.38, 0.34), core_outline);
	alpha = max(alpha, core_outline * 0.82);
	COLOR = vec4(fog_color, alpha);
}
"""


static func attach(host: Aircraft) -> Polygon2D:
	var shroud := Polygon2D.new()
	shroud.name = "SnowblindShroud"
	var points := PackedVector2Array()
	for i in range(SEGMENTS):
		var a := TAU * float(i) / float(SEGMENTS)
		points.append(Vector2(cos(a), sin(a)) * RADIUS_PX)
	shroud.polygon = points
	shroud.color = Color(1.0, 1.0, 1.0, 1.0)
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	shroud.material = material
	host.add_child(shroud)
	return shroud
