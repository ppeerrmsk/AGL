shader_type canvas_item;
uniform vec2 world_origin;
uniform vec2 world_dx;
uniform vec2 world_dy;
uniform vec4 bounds = vec4(-520.0, -13870.0, 1120.0, -12730.0);
uniform float edge_feather = 80.0;
void fragment() {
	vec2 world = world_origin + UV.x * world_dx + UV.y * world_dy;
	float edge = min(min(world.x - bounds.x, bounds.z - world.x), min(world.y - bounds.y, bounds.w - world.y));
	vec4 color = texture(TEXTURE, UV);
	if (edge_feather > 0.0) { color.a *= smoothstep(0.0, edge_feather, edge); }
	COLOR = color;
}
