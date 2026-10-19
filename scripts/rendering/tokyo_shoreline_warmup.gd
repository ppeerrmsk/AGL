extends SubViewport
## 仅初始化使用，样本必在独立相机内；同一Shader资源的真实提交才算暖绘。
const RESERVE_BYTES := 512 * 1024
const FRAME_LIMIT := 120
var result: Dictionary = {}
var _stream: WeakRef
var _callbacks := 0
var _submitted := 0


func configure(stream: Node, source: ShaderMaterial, samples: int = Viewport.MSAA_4X) -> bool:
	if _stream != null or source == null or source.shader == null:
		return false
	result = {"state":"budget_rejected", "rendered":false, "submitted_frames":0,
		"reserved_bytes":0, "peak_reserved_bytes":0, "shader_id":source.shader.get_instance_id()}
	if not stream.reserve_auxiliary(get_instance_id(), RESERVE_BYTES):
		return false
	_stream = weakref(stream)
	result.state = "pending"
	result.reserved_bytes = RESERVE_BYTES
	result.peak_reserved_bytes = RESERVE_BYTES
	name = "ShorelineMaterialWarmup"
	size = Vector2i(64, 32)
	own_world_3d = true
	transparent_bg = true
	msaa_3d = samples
	positional_shadow_atlas_size = 0
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-.7,0,-.7),Vector3(.7,0,-.7),Vector3(.7,0,.7),Vector3(-.7,0,-.7),Vector3(.7,0,.7),Vector3(-.7,0,.7)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO,Vector2(.1,0),Vector2(.1,.1),Vector2.ZERO,Vector2(.1,.1),Vector2(0,.1)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	for i in 3:
		var material: ShaderMaterial = source.duplicate(false)
		material.shader = source.shader
		material.set_shader_parameter("shoreline_count", 0)
		material.set_shader_parameter("outgoing", i == 1)
		material.set_shader_parameter("lod_mix", 1.0 if i == 0 else .5)
		if source.shader.code.contains("shoreline_morph_t"):
			material.set_shader_parameter("shoreline_morph_t", float(i) * .5)
		var sample := MeshInstance3D.new()
		sample.mesh = mesh
		sample.material_override = material
		sample.position.x = (i - 1) * 2.0
		sample.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sample)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-35,0)
	sun.light_energy = .8
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.near = .1
	camera.far = 20.0
	camera.position = Vector3(0,5,0)
	camera.rotation_degrees.x = -90.0
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0,0,0,0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	camera.environment = environment
	add_child(camera)
	camera.make_current()
	return true


func _ready() -> void:
	if result.get("state", "") != "pending":
		return
	if DisplayServer.get_name() == "headless":
		result.state = "headless_skipped"
		queue_free()
		return
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	RenderingServer.frame_post_draw.connect(_after_draw)


func _after_draw() -> void:
	if result.get("state", "") != "pending":
		return
	_callbacks += 1
	var draws := get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	# 不是全局frame_post_draw次数；独立视口的三个样本都必须真正提交。
	if draws >= 3:
		_submitted += 1
	result.submitted_frames = _submitted
	result["draw_calls"] = draws
	if _submitted >= 2 or _callbacks >= FRAME_LIMIT:
		result.rendered = _submitted >= 2
		result.state = "ready" if result.rendered else "draw_timeout"
		close()


func close() -> void:
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	if RenderingServer.frame_post_draw.is_connected(_after_draw):
		RenderingServer.frame_post_draw.disconnect(_after_draw)
	if result.get("state", "") == "pending":
		result.state = "cancelled"
	queue_free()


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_after_draw):
		RenderingServer.frame_post_draw.disconnect(_after_draw)
	if result.get("state", "") == "pending":
		result.state = "cancelled"
	var stream: Variant = _stream.get_ref() if _stream != null else null
	if typeof(stream) == TYPE_OBJECT and is_instance_valid(stream):
		stream.release_auxiliary(get_instance_id())
	_stream = null
	result["reserved_bytes"] = 0
