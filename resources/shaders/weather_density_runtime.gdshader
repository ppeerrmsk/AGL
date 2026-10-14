shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, fog_disabled;
uniform sampler3D cloud_noise : filter_linear, repeat_enable;
uniform float weather_time = 0.0;
uniform float cloud_seed = 0.0;
uniform int march_steps = 24;
uniform bool scan_enabled = true;
uniform bool dust_mode = false;
uniform float loop_period = 28.0;
uniform vec2 drift_velocity = vec2(0.007,0.002);
uniform bool drift_enabled = true;
uniform sampler2D authority_mask : filter_linear, repeat_disable;
uniform bool masked_cloud = false;
uniform bool runtime_storm = false;
uniform float storm_half_width = 2500.0;
uniform float storm_half_world = 32000.0;
uniform float storm_direction = 1.0;
varying vec3 local_position;
varying vec3 ray_direction;

float merge_body(float a, float b) {
    float h = max(0.20-abs(a-b),0.0)/0.20;
    return max(a,b)+h*h*0.05;
}

float cloud_density(vec3 p) {
    float phase = TAU*weather_time/loop_period;
    float offset = cloud_seed*7.0;
    vec3 flow = vec3(cos(phase),sin(phase),sin(phase*2.0+offset))*0.16 + vec3(cloud_seed);
    float broad = texture(cloud_noise, p * 0.85 + flow * 0.2).r;
    float detail = texture(cloud_noise, p * 2.7 + flow).r;
    float fine = texture(cloud_noise, p * 9.0 + flow * 1.7).r;
    p.xz += vec2(sin(phase+offset+p.z*3.0),cos(phase*2.0-offset+p.x*4.0))*0.055;
    p.z *= mix(0.87,1.16,cloud_seed);
    p.y += 0.12 * sin(p.x*5.0 + phase + offset);
    float breathe = sin(phase+offset)*0.065;
    float body = 1.0-length((p-vec3(-0.43,-0.10,0.13))/vec3(0.40,0.39+breathe,0.40));
    body = merge_body(body,1.0-length((p-vec3(0.02,0.05,-0.16))/vec3(0.46,0.57-breathe,0.48)));
    body = merge_body(body,1.0-length((p-vec3(0.44,-0.08,0.18+0.10*sin(offset)))/vec3(0.29+cloud_seed*0.14,0.41+breathe,0.40)));
    body = merge_body(body,1.0-length((p-vec3(-0.12+0.16*sin(offset),-0.22,0.42))/vec3(0.39,0.30,0.24+cloud_seed*0.13)));
    body += (broad-0.48)*0.80 + (detail-0.50)*0.32 + (fine-0.5)*0.10;
    float boundary = 1.0 - smoothstep(0.80,0.98,max(abs(p.x),max(abs(p.y),abs(p.z))));
    return smoothstep(0.03,0.34,body) * boundary;
}

float dust_density(vec3 p) {
    float phase=TAU*weather_time/loop_period;
    float front=0.28+0.12*sin(p.z*7.0+phase)+0.06*sin(p.z*16.0-phase*2.0);
    vec3 rolled=vec3(p.x*cos(phase)-p.y*sin(phase),p.x*sin(phase)+p.y*cos(phase),p.z);
    float billow=texture(cloud_noise,rolled*vec3(0.85,1.1,2.4)+vec3(0.1*sin(phase),0.0,0.2*cos(phase))).r;
    float detail=texture(cloud_noise,rolled*5.0+vec3(sin(phase*2.0),cos(phase*2.0),0.0)*0.18).r;
    float ridge=exp(-pow((p.x-front+0.22)*2.7,2.0));
    float height=-0.35+0.97*ridge+0.18*sin(p.z*8.0+phase)+0.10*cos(p.x*8.0-phase);
    float tail=-0.79+0.12*sin(p.z*5.0-phase)+0.06*cos(p.z*13.0+phase*2.0);
    float wall=(1.0-smoothstep(front-0.24,front+0.08,p.x))*smoothstep(tail-0.18,tail+0.26,p.x);
    float vertical=smoothstep(-0.99,-0.77,p.y)*(1.0-smoothstep(height-0.26,height+0.20,p.y));
    float ends=1.0-smoothstep(0.68,0.98,abs(p.z));
    return wall*vertical*ends*smoothstep(0.14,0.65,billow*0.76+detail*0.24);
}

float density(vec3 p) {
    if(runtime_storm) {
        float x=p.x*(storm_half_width+260.0);
        float z=p.z*storm_half_world;
        float left=sin(z*0.0017-0.61)*148.0+sin(z*0.00053+0.427)*96.0;
        float right=sin(z*0.0017+1.73)*148.0+sin(z*0.00053-1.211)*96.0;
        float edge=min(x+storm_half_width-left,storm_half_width+right-x);
        float front=(storm_direction>0.0 ? storm_half_width+right-x : x+storm_half_width-left);
        float phase=TAU*weather_time/18.0;
        float ridge=exp(-pow((front-650.0)/750.0,2.0));
        float height=-0.50+1.28*ridge+0.12*sin(z*0.003+phase);
        vec3 q=vec3(x/1800.0,p.y,z/1800.0);
        vec3 roll=vec3(q.x*cos(phase)-q.y*sin(phase),q.x*sin(phase)+q.y*cos(phase),q.z);
        float billow=texture(cloud_noise,roll).r;
        return smoothstep(0.0,720.0,edge)*smoothstep(-1.0,-0.85,p.y)*(1.0-smoothstep(height-0.24,height+0.2,p.y))*smoothstep(0.14,0.65,billow);
    }
    if(dust_mode) { return dust_density(p); }
    if(masked_cloud) { return cloud_density(p)*smoothstep(0.015,0.32,texture(authority_mask,p.xz*0.5+0.5).r); }
    return cloud_density(p);
}

void vertex() {
    local_position = VERTEX;
    ray_direction = normalize((inverse(MODELVIEW_MATRIX) * vec4(0.0,0.0,-1.0,0.0)).xyz);
    if(drift_enabled) { VERTEX.xz += drift_velocity*weather_time; }
}

void fragment() {
    vec3 direction = normalize(ray_direction);
    vec3 safe_direction = sign(direction) * max(abs(direction),vec3(0.0001));
    safe_direction += vec3(0.000001);
    vec3 exits = (sign(safe_direction) - local_position) / safe_direction;
    float distance_to_exit = min(exits.x,min(exits.y,exits.z));
    float step_length = max(0.0,distance_to_exit)/float(march_steps);
    vec3 p = local_position + direction*step_length*0.5;
    vec3 radiance = vec3(0.0);
    vec3 surface_sum = vec3(0.0);
    float transmittance = 1.0;
    for (int i=0;i<48;i++) {
        if (i >= march_steps || transmittance < 0.025) { break; }
        float d = density(p);
        if (d > 0.005) {
            vec3 light_dir = vec3(-0.42,0.84,-0.34);
            float shade = clamp(0.40+(d-density(p+light_dir*0.22))*1.8 + p.y*0.20,0.12,1.0);
            vec3 tone = mix(vec3(0.33,0.38,0.39),vec3(0.90,0.92,0.89),shade);
            if(dust_mode) { tone=mix(vec3(0.27,0.22,0.15),vec3(0.75,0.60,0.37),shade); }
            float opacity = 1.0-exp(-d*step_length*5.5);
            float weight = transmittance*opacity;
            surface_sum += weight*p;
            radiance += weight*tone;
            transmittance *= 1.0-opacity;
        }
        p += direction*step_length;
    }
    float alpha = 1.0-transmittance;
    vec3 color = radiance/max(alpha,0.0001);
    vec3 surface = surface_sum/max(alpha,0.0001);
    vec2 grid = surface.xz*vec2(23.0,14.0);
    float point_distance = length(fract(grid)-0.5);
    float aa = max(fwidth(point_distance),0.03);
    float dots = 1.0-smoothstep(0.06,0.06+aa,point_distance);
    float scan_distance = abs(sin(surface.z*21.0+surface.y*8.0+surface.x*2.0));
    float scan = (1.0-smoothstep(0.012,0.04,scan_distance))*smoothstep(0.65,0.85,texture(cloud_noise,surface*1.5).r);
    float glint=0.85+0.15*sin(surface.x*4.0+weather_time*TAU/loop_period);
    if (scan_enabled) { color += (dots*0.13+scan*0.08)*glint*smoothstep(0.25,0.7,alpha); }
    ALBEDO = color;
    ALPHA = alpha*0.89;
}
