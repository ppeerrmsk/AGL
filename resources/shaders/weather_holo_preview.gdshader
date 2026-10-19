shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
varying vec2 plane;
void vertex() {
    plane = VERTEX.xz;
}
void fragment() {
    float stripe = abs(fract((plane.x + plane.y * 0.7) / 145.0) - 0.5);
    float edge = fwidth(stripe);
    float hatch = 1.0 - smoothstep(0.025, 0.025 + edge, stripe);
    ALBEDO = COLOR.rgb;
    ALPHA = COLOR.a * (0.12 + 0.88 * hatch);
}
