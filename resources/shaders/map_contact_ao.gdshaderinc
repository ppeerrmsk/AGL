// 离线有限距离接触遮蔽；坐标为源地图平面，不受相机/瓦片/投影矩阵影响。
uniform sampler2D contact_ao_texture : filter_linear_mipmap, repeat_disable;
uniform vec4 contact_ao_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float contact_ao_strength = 0.0;
varying vec3 contact_ao_position;

float contact_ao_visibility() {
	vec2 uv = (contact_ao_position.xz - contact_ao_rect.xy) / contact_ao_rect.zw;
	if (contact_ao_strength <= 0.0 || any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 1.0;
	}
	float foot = 1.0 - smoothstep(1.0, 10.0, contact_ao_position.y);
	return 1.0 - texture(contact_ao_texture, uv).r * contact_ao_strength * foot;
}
