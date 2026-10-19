shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform float weather_time=0.0;
varying float opacity;
void vertex() {
    float age=fract(weather_time*(0.18+INSTANCE_CUSTOM.w*0.08)+INSTANCE_CUSTOM.x);
    VERTEX.x += (age-0.5)*2500.0 + weather_time*25.0;
    VERTEX.z += (INSTANCE_CUSTOM.y-0.5)*5000.0 + sin(age*TAU)*30.0;
    VERTEX.y += 30.0+INSTANCE_CUSTOM.z*110.0+sin(age*PI)*60.0;
    opacity=sin(age*PI)*0.23;
}
void fragment() {
    ALBEDO=vec3(0.85,0.70,0.45);
    ALPHA=opacity;
}
