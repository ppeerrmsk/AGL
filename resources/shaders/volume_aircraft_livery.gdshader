shader_type spatial;
render_mode vertex_lighting, cull_back;

// MultiMesh COLOR 已包含“制作顶点色 × icon_color”。机翼顶点 alpha=0.5，
// INSTANCE_CUSTOM.rgb 保存 wing_color / icon_color；相乘后恢复制作顶点色 × wing_color。
varying vec3 wing_livery_ratio;

void vertex() {
	wing_livery_ratio = INSTANCE_CUSTOM.rgb;
	ROUGHNESS = 0.82;
}

void fragment() {
	float wing_mask = 1.0 - step(0.75, COLOR.a);
	ALBEDO = COLOR.rgb * mix(vec3(1.0), wing_livery_ratio, wing_mask);
	ROUGHNESS = 0.82;
	SPECULAR = 0.0;
}
