shader_type spatial;
render_mode vertex_lighting, cull_back, depth_prepass_alpha;

// 仅淡出实例用透明材质；共享原机型网格/涂装，其余阶段保留不透明深度路径。
varying vec4 livery_and_opacity;

void vertex() {
	livery_and_opacity = INSTANCE_CUSTOM;
	ROUGHNESS = 0.82;
}

void fragment() {
	float wing_mask = 1.0 - step(0.75, COLOR.a);
	ALBEDO = COLOR.rgb * mix(vec3(1.0), livery_and_opacity.rgb, wing_mask);
	ROUGHNESS = 0.82;
	SPECULAR = 0.0;
	ALPHA = livery_and_opacity.a;
}
