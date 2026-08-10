class_name DeadairFieldVisual
extends RefCounted

## 单个静态圆网格 + GPU 扫描带；不新增 process/draw，CPU 成本不随帧率增长。

const RADIUS_PX: float = 1500.0 ## 3000m
const SEGMENTS: int = 64

const SHADER_CODE: String = """
shader_type canvas_item;
render_mode unshaded;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float radius = length(local_pos);
	float body = 1.0 - smoothstep(1430.0, 1500.0, radius);
	float rim = smoothstep(1380.0, 1460.0, radius) * (1.0 - smoothstep(1460.0, 1500.0, radius));
	float scan_phase = fract(radius / 310.0 - TIME * 0.22);
	float scan = (1.0 - smoothstep(0.0, 0.12, abs(scan_phase - 0.5))) * body;
	float spoke = 0.5 + 0.5 * sin(atan(local_pos.y, local_pos.x) * 12.0 + TIME * 0.8);
	vec3 dark_field = vec3(0.18, 0.02, 0.15);
	vec3 scan_color = vec3(0.60, 0.08, 0.42);
	vec3 color = mix(dark_field, scan_color, scan * (0.42 + spoke * 0.18));
	float alpha = body * (0.055 + scan * 0.065) + rim * 0.62;
	COLOR = vec4(color, alpha);
}
"""


static func attach(host: Aircraft) -> Polygon2D:
	var field := Polygon2D.new()
	field.name = "DeadairField"
	field.z_index = -2
	var points := PackedVector2Array()
	for i in range(SEGMENTS):
		var angle := TAU * float(i) / float(SEGMENTS)
		points.append(Vector2(cos(angle), sin(angle)) * RADIUS_PX)
	field.polygon = points
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	field.material = material
	host.add_child(field)
	return field


static func collapse(host: Aircraft) -> void:
	if host == null or not is_instance_valid(host):
		return
	var field := host.get_node_or_null("DeadairField") as Polygon2D
	if field == null:
		return
	var tween := host.create_tween()
	tween.set_parallel(true)
	tween.tween_property(field, "scale", Vector2(0.08, 0.08), 0.6)
	tween.tween_property(field, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(field.queue_free)
