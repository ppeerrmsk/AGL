shader_type canvas_item;
render_mode blend_premul_alpha;
// 透明3D视口已含预乘颜色，合成时不能再次乘alpha；仅由天气验收样板临时使用。
void fragment() {
    COLOR = texture(TEXTURE, UV);
}
