class_name SnowblindShroudVisual
extends RefCounted

## 单个静态圆形网格 + GPU 连续风雪。没有 _process/_draw/queue_redraw，CPU 成本不随帧率增长。

const RADIUS_PX: float = 2000.0
const SEGMENTS: int = 64
## 世界遮蔽层：压住地图/地面与海面单位，但必须低于 z=0 的飞机与操控反馈。
const WORLD_Z_INDEX: int = -1
## 破幕与复隐共用视觉节奏；玩法显隐仍由控制器在状态边沿即时切换。
const TRANSITION_S: float = 0.8
const _TARGET_META: StringName = &"_snowblind_concealment_target"
const _TWEEN_META: StringName = &"_snowblind_concealment_tween"

const SHADER_CODE: String = """
shader_type canvas_item;
render_mode unshaded;

varying vec2 local_pos;
uniform float concealment : hint_range(0.0, 1.0) = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float radius = length(local_pos);
	float body_mask = 1.0 - smoothstep(1780.0, 2000.0, radius);
	float rim = smoothstep(1680.0, 1900.0, radius) * (1.0 - smoothstep(1900.0, 2000.0, radius));

	// 连续漂移的实体雾团：锚定世界中的雪幕，不再随屏幕闪烁。
	vec2 wind = vec2(TIME * 0.055, TIME * -0.028);
	float cloud_large = value_noise(local_pos / 520.0 + wind);
	float cloud_small = value_noise(local_pos / 210.0 - wind * 1.7);
	float cloud = mix(cloud_large, cloud_small, 0.34);

	// 稀疏、缓慢的斜向雪带，只改变亮度，不制造高频 alpha 跳闪。
	vec2 snow_uv = local_pos / 34.0 + vec2(TIME * 0.34, TIME * 0.58);
	vec2 snow_cell = floor(snow_uv);
	float snow_seed = hash21(snow_cell);
	vec2 flake_pos = vec2(fract(snow_seed * 7.13), fract(snow_seed * 13.71));
	vec2 flake_delta = fract(snow_uv) - flake_pos;
	float flake_dist = length(vec2(flake_delta.x * 2.8, flake_delta.y));
	float streak = (1.0 - smoothstep(0.025, 0.11, flake_dist)) * step(0.78, snow_seed);

	vec3 fog_color = mix(vec3(0.50, 0.54, 0.58), vec3(0.78, 0.82, 0.86), cloud);
	fog_color += streak * 0.10;
	float solid_alpha = 1.0;
	float revealed_alpha = 0.08 + cloud * 0.04;
	float field_alpha = mix(revealed_alpha, solid_alpha, concealment);
	float rim_alpha = mix(0.12, 0.92, concealment);
	float alpha = body_mask * field_alpha + rim * rim_alpha;

	// 只显示“始作俑者”的不可交互轮廓；真实 Aircraft 仍处于 sensor_hidden。
	float core_d = segment_distance(local_pos, vec2(0.0, -34.0), vec2(9.0, 10.0));
	core_d = min(core_d, segment_distance(local_pos, vec2(9.0, 10.0), vec2(0.0, 29.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(0.0, 29.0), vec2(-9.0, 10.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(-9.0, 10.0), vec2(0.0, -34.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(-32.0, 8.0), vec2(0.0, -5.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(0.0, -5.0), vec2(32.0, 8.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(-27.0, 3.0), vec2(-27.0, 16.0)));
	core_d = min(core_d, segment_distance(local_pos, vec2(27.0, 3.0), vec2(27.0, 16.0)));
	float core_outline = (1.0 - smoothstep(0.9, 2.2, core_d)) * concealment;
	fog_color = mix(fog_color, vec3(0.68, 0.38, 0.34), core_outline);
	alpha = max(alpha, core_outline * 0.82);
	COLOR = vec4(fog_color, alpha);
}
"""


static func attach(host: Aircraft) -> Polygon2D:
	var shroud := Polygon2D.new()
	shroud.name = "SnowblindShroud"
	# 不继承宿主层级，避免场景树生成先后决定玩家机是否被雪幕盖住。
	shroud.z_as_relative = false
	shroud.z_index = WORLD_Z_INDEX
	var points := PackedVector2Array()
	for i in range(SEGMENTS):
		var a := TAU * float(i) / float(SEGMENTS)
		points.append(Vector2(cos(a), sin(a)) * RADIUS_PX)
	shroud.polygon = points
	shroud.color = Color(1.0, 1.0, 1.0, 1.0)
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	# Shader uniform 的源码默认值在材质侧首次读取可能仍是 null；显式建立运行时真值。
	material.set_shader_parameter("concealment", 1.0)
	shroud.material = material
	shroud.set_meta(_TARGET_META, true)
	host.add_child(shroud)
	return shroud


## 只渐变 shader 遮蔽强度；敌机传感器显隐、锁定与交战边界不等待视觉过渡。
## 若过渡中反向触发，从当前值平滑折返，不跳回端点。
static func set_concealed(host: Aircraft, concealed: bool, immediate: bool = false) -> void:
	if host == null or not is_instance_valid(host):
		return
	var shroud := host.get_node_or_null("SnowblindShroud") as Polygon2D
	if shroud == null or not shroud.material is ShaderMaterial:
		return
	var material := shroud.material as ShaderMaterial
	var current_variant: Variant = material.get_shader_parameter("concealment")
	var current := float(current_variant) \
		if typeof(current_variant) in [TYPE_FLOAT, TYPE_INT] else (1.0 if concealed else 0.0)
	var previous_target := bool(shroud.get_meta(_TARGET_META, current >= 0.5))
	if not immediate and previous_target == concealed:
		return
	_stop_transition(shroud)
	shroud.set_meta(_TARGET_META, concealed)
	var target := 1.0 if concealed else 0.0
	if immediate or not host.is_inside_tree() or is_equal_approx(current, target):
		material.set_shader_parameter("concealment", target)
		return
	var tween := host.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(material, ^"shader_parameter/concealment", target, TRANSITION_S).from(current)
	shroud.set_meta(_TWEEN_META, tween)


static func _stop_transition(shroud: Polygon2D) -> void:
	if not shroud.has_meta(_TWEEN_META):
		return
	var raw_tween: Variant = shroud.get_meta(_TWEEN_META)
	if typeof(raw_tween) == TYPE_OBJECT and raw_tween != null and is_instance_valid(raw_tween):
		var tween := raw_tween as Tween
		if tween != null and tween.is_valid():
			tween.kill()
	shroud.remove_meta(_TWEEN_META)
