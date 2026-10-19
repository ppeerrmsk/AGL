extends SubViewport
## 仅初始化时实际绘制两帧；独立世界，不显示到主画面，不改变玩法时钟。
signal finished(result: Dictionary)
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const MapFactory := preload("res://scripts/experiments/volume_map_factory.gd")
const FRAME_LIMIT := 2
var _frames := 0
var _submitted := 0
var _minimum_draws := 1


func configure(material: ShaderMaterial) -> void:
	name = "MaterialWarmup"
	size = Vector2i(32, 32)
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var geometry := Geometry.new()
	geometry.box(Vector3(0, 0.6, 0), Vector3.ONE, Color("96988b"))
	geometry.box(Vector3(0, -0.1, 0), Vector3(4, 0.2, 4), Color("7d8178"))
	var sample := MeshInstance3D.new()
	sample.name = "MaterialSample"
	sample.mesh = geometry.mesh()
	sample.material_override = material
	add_child(sample)
	var sun := DirectionalLight3D.new()
	sun.name = "WarmupSun"
	MapFactory.configure_sun(sun)
	sun.directional_shadow_max_distance = 20.0
	add_child(sun)
	var camera := Camera3D.new()
	camera.name = "WarmupCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.0
	camera.near = 0.1
	camera.far = 30.0
	camera.position = Vector3(3, 5, 5)
	camera.rotation_degrees = Vector3(-40, 30, 0)
	add_child(camera)
	camera.make_current()
	set_process(false)
	set_physics_process(false)


func configure_instanced(materials: Array[ShaderMaterial], environment: Environment) -> void:
	assert(not materials.is_empty())
	configure(materials[0])
	transparent_bg=true
	var original := get_node("MaterialSample") as MeshInstance3D
	var mesh := original.mesh
	original.free()
	_minimum_draws=materials.size()
	for index in materials.size():
		var sample := MultiMeshInstance3D.new()
		sample.name="InstancedWarmup%d" % index
		sample.multimesh=MultiMesh.new()
		sample.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		sample.multimesh.use_colors=true
		sample.multimesh.use_custom_data=true
		sample.multimesh.mesh=mesh
		sample.multimesh.instance_count=1
		sample.multimesh.set_instance_color(0,Color.WHITE)
		sample.multimesh.set_instance_custom_data(0,Color(0.4,0.6,0.8,0.5))
		sample.multimesh.set_instance_transform(0,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*0.3),Vector3((index-(materials.size()-1)*0.5)*1.2,0,0)))
		sample.material_override=materials[index]
		sample.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sample)
	(get_node("WarmupSun") as DirectionalLight3D).shadow_enabled=false
	(get_node("WarmupCamera") as Camera3D).environment=environment


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		finished.emit({"state": "headless_skipped", "rendered": false, "frames": 0})
		queue_free()
		return
	msaa_3d = get_parent().get_viewport().msaa_3d
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	RenderingServer.frame_post_draw.connect(_after_draw)


func _after_draw() -> void:
	_frames += 1
	if get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME) >= _minimum_draws:
		_submitted += 1
	if _frames >= FRAME_LIMIT:
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		RenderingServer.frame_post_draw.disconnect(_after_draw)
		finished.emit({"state": "finished", "rendered": _submitted == FRAME_LIMIT,
			"frames": _frames, "submitted_frames": _submitted, "size": "32x32"})
		queue_free()


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_after_draw):
		RenderingServer.frame_post_draw.disconnect(_after_draw)
