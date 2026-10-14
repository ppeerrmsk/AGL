shader_type spatial;
render_mode unshaded, cull_back;
// 造型比较先看实体轮廓，避免透明视口的边缘混合干扰判断。
void fragment() {
	ALBEDO = COLOR.rgb;
}
