shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float weather_time = 0.0;
varying vec2 sand_position;
void vertex() {
    sand_position = VERTEX.xz;
    VERTEX.y += 8.0 * sin(VERTEX.z * 0.006 + weather_time * 0.7) * COLOR.a;
}
void fragment() {
    float streak = pow(max(0.0, sin(sand_position.y * 0.022 + sin(sand_position.x * 0.004 - weather_time * 0.5))), 12.0);
    ALBEDO = COLOR.rgb + vec3(0.10, 0.065, 0.015) * streak;
    ALPHA = COLOR.a * (0.12 + 0.04 * streak);
}
