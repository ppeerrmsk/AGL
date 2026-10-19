shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float weather_time = 0.0;
uniform vec2 field_size = vec2(5000.0, 8000.0);
uniform float direction = 1.0;
varying float opacity;
void vertex() {
    float age = fract(weather_time * 0.18 + INSTANCE_CUSTOM.x);
    VERTEX.x += (age - 0.5) * field_size.x * direction;
    VERTEX.z += (INSTANCE_CUSTOM.y - 0.5) * field_size.y;
    VERTEX.y += 30.0 + INSTANCE_CUSTOM.z * 150.0 + sin(age * 3.14159265) * 40.0;
    opacity = sin(age * 3.14159265) * 0.28;
}
void fragment() { ALBEDO = vec3(0.77, 0.59, 0.31); ALPHA = opacity; }
