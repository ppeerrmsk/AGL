shader_type canvas_item;
render_mode unshaded;

uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform float intensity : hint_range(0.0, 1.5) = 0.0;
uniform float optical_mix : hint_range(0.0, 1.0) = 0.0;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float box_d = sd_round_box(p, vec2(0.72, 0.80), 0.10);
	float disc_d = length(p * vec2(1.0, 0.78)) - 0.72;
	float shape_d = mix(box_d, min(box_d, disc_d), optical_mix);
	float outside = smoothstep(0.24, 0.0, max(shape_d, 0.0));
	float hollow = smoothstep(0.025, 0.095, abs(shape_d));
	float pulse = 0.82 + 0.18 * sin(TIME * (2.0 + optical_mix * 1.5) + p.x * 3.0);
	float scan = 0.88 + 0.12 * sin((UV.y + TIME * 0.10) * 120.0);
	float alpha = outside * hollow * intensity * pulse * scan;
	COLOR = vec4(glow_color.rgb, alpha * 0.52);
}
