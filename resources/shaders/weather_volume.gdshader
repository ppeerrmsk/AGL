shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
uniform vec2 wind_offset = vec2(0.0);
uniform float weather_time = 0.0;
void vertex() {
    VERTEX.xz += wind_offset;
    VERTEX.y += 12.0 * sin(weather_time * 0.35 + VERTEX.x * 0.001) * COLOR.a;
}
void fragment() {
    ALBEDO = COLOR.rgb;
    ALPHA = COLOR.a;
}
