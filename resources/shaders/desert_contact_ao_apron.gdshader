shader_type spatial;
render_mode specular_disabled;
#include "map_contact_ao.gdshaderinc"
void vertex() { contact_ao_position = VERTEX; }
void fragment() {
	// 对应原 Geometry.material 的顶点色、Burley、粗糙度与环境光；AO 不影响直射。
	vec3 base = COLOR.rgb;
	if (!OUTPUT_IS_SRGB) { base = pow(base, vec3(2.2)); }
	ALBEDO = base;
	ROUGHNESS = 0.82;
	AO = contact_ao_visibility();
	AO_LIGHT_AFFECT = 0.0;
}
