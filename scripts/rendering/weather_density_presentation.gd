extends "res://scripts/rendering/weather_volume_presentation.gd"
## 正式天气适配层：共享密度纹理；GPU形变，CPU只在分块装载时采样权威场。
const DENSITY_SHADER := preload("res://resources/shaders/weather_density_runtime.gdshader")
var _noise := NoiseTexture3D.new()
var _ready_density := false
var _box := BoxMesh.new()


func setup(source: WeatherSystem) -> void:
	_box.size = Vector3.ONE * 2.0
	super.setup(source)
	# 异步噪声就绪前继续显示原天气，不能先接管再留下空白。
	source.remove_meta(&"weather_volume_owner")
	hide()
	_cloud_material.shader = DENSITY_SHADER
	_sand_material.shader = DENSITY_SHADER
	_sand.mesh = _box
	for material in [_cloud_material, _sand_material]:
		material.set_shader_parameter("cloud_noise", _noise)
		material.set_shader_parameter("drift_enabled", false)
	_sand_material.set_shader_parameter("dust_mode", true)
	_sand_material.set_shader_parameter("runtime_storm", true)
	_sand_material.set_shader_parameter("scan_enabled", false)
	_sand_material.set_shader_parameter("loop_period", 18.0)
	_noise.width = 64
	_noise.height = 64
	_noise.depth = 64
	_noise.seamless = true
	var noise := FastNoiseLite.new()
	noise.seed = 270927
	noise.frequency = 0.075
	noise.fractal_octaves = 4
	_noise.changed.connect(_noise_ready, CONNECT_ONE_SHOT)
	_noise.noise = noise


func _prewarm_materials() -> void:
	# 父类初始化时纹理尚未完成，等 changed 后再暖绘正式材质。
	pass


func _noise_ready() -> void:
	_ready_density = true
	var raw: Variant = _source.get_ref() if _source != null else null
	if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw):
		hide()
		return
	super._prewarm_materials()
	set_enabled(_enabled)


func set_enabled(enabled: bool) -> void:
	if _ready_density:
		super.set_enabled(enabled)
		var raw: Variant = _source.get_ref() if _source != null else null
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw):
			hide()
	else:
		_enabled = enabled
		hide()


func sync(delta: float, canvas: Transform2D, viewport_size: Vector2, ground: Basis) -> void:
	if not _enabled or not _ready_density:
		return
	var raw: Variant = _source.get_ref() if _source != null else null
	if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is WeatherSystem:
		hide()
		return
	var source: WeatherSystem = raw
	show()
	basis = ground
	var wind := source._wind_offset()
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(viewport_size.x,0), viewport_size, Vector2(0,viewport_size.y)]:
		view = view.expand(inverse * corner)
	view.position -= wind
	view = view.grow(1600.0)
	var desired := _chunk_scale
	while maxf(view.size.x,view.size.y) > 28000.0 * desired:
		desired *= 2
	while desired > 1 and maxf(view.size.x,view.size.y) < 10000.0 * desired:
		desired /= 2
	if source.presentation_revision != _revision or desired != _chunk_scale:
		_revision = source.presentation_revision
		_chunk_scale = desired
		for node: MeshInstance3D in _chunks.values():
			node.queue_free()
		_chunks.clear()
		_pending.clear()
		_timer = 0.0
	_timer -= delta
	if _timer <= 0.0 or view.position.distance_squared_to(_last_view.position) > 640000.0 or not view.size.is_equal_approx(_last_view.size):
		_timer = 0.5
		_last_view = view
		_select_chunks(view)
	for i in range(mini(2, _pending.size())):
		if _chunks.size() >= CACHE_LIMIT:
			break
		var key: Vector2i = _pending.pop_back()
		var started := Time.get_ticks_usec()
		var node := _build_density_chunk(source,key)
		add_child(node)
		_chunks[key] = node
		built_chunks += 1
		max_build_us = maxi(max_build_us,Time.get_ticks_usec()-started)
	for key: Vector2i in _chunks:
		var node: MeshInstance3D = _chunks[key]
		node.visible = _wanted.has(key) and node.mesh != null
		if not node.visible:
			continue
		var center := (Vector2(key)+Vector2.ONE*0.5)*CHUNK*_chunk_scale+wind
		node.position.x = center.x
		node.position.z = center.y
		var material := node.material_override as ShaderMaterial
		material.set_shader_parameter("weather_time", source._time)
		material.set_shader_parameter("march_steps",16 if _chunk_scale > 1 else 24)
	_sync_storm(source,view.get_center()+wind,view.size)
	_grit_material.set_shader_parameter("weather_time",source._time)


func _build_density_chunk(source: WeatherSystem, key: Vector2i) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var span := CHUNK * _chunk_scale
	var image := Image.create(32,32,false,Image.FORMAT_R8)
	var peak := 0.0
	for y in range(32):
		for x in range(32):
			var point := (Vector2(key)+(Vector2(x,y)+Vector2.ONE*0.5)/32.0)*span
			var density := source._cloud_density_at(point.x,point.y)
			peak = maxf(peak,density)
			image.set_pixel(x,y,Color(density,0,0))
	if peak <= 0.04:
		return node
	var seed_value := fposmod(sin(Vector2(key).dot(Vector2(12.9898,78.233)))*43758.5453,1.0)
	var material := _cloud_material.duplicate() as ShaderMaterial
	material.set_shader_parameter("authority_mask",ImageTexture.create_from_image(image))
	material.set_shader_parameter("masked_cloud",true)
	material.set_shader_parameter("cloud_seed",seed_value)
	material.set_shader_parameter("loop_period",28.0+24.0*seed_value)
	node.mesh = _box
	node.material_override = material
	var height := 380.0+peak*240.0
	node.scale = Vector3(span*0.5,height,span*0.5)
	node.position.y = height+140.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _sync_storm(source: WeatherSystem, center: Vector2, size: Vector2) -> void:
	var active := source.is_sandstorm_active()
	_sand.visible = active
	_grit.visible = active
	if not active:
		return
	var width := source.sandstorm_band_width_px
	var half_world := MapBoundary.world_half_px()
	var storm_center := source.sandstorm_center_world()
	_sand.scale = Vector3(width*0.5+260.0,600.0,half_world)
	_sand.position = Vector3(storm_center.x,580.0,0)
	_sand_material.set_shader_parameter("weather_time",source._time)
	_sand_material.set_shader_parameter("storm_half_width",width*0.5)
	_sand_material.set_shader_parameter("storm_half_world",half_world)
	_sand_material.set_shader_parameter("storm_direction",source.sandstorm_direction.x)
	var visible_width := maxf(1.0,minf(width-1440.0,size.x))
	_grit.visible = width > 1500.0 and absf(center.x-storm_center.x) < (width+size.x)*0.5
	var grit_center := clampf(center.x,storm_center.x-width*0.5+720+visible_width*0.5,storm_center.x+width*0.5-720-visible_width*0.5)
	var field_height := minf(size.y,half_world*2.0)
	var field_y := clampf(center.y,-half_world+field_height*0.5,half_world-field_height*0.5)
	_grit.position = Vector3(grit_center,0,field_y)
	_grit_material.set_shader_parameter("field_size",Vector2(visible_width,field_height))
	_grit_material.set_shader_parameter("direction",source.sandstorm_direction.x)
	_grit.custom_aabb = AABB(Vector3(-visible_width*0.5-30,0,-field_height*0.5-30),Vector3(visible_width+60,260,field_height+60))


func summary() -> String:
	var visible_chunks := 0
	for node: MeshInstance3D in _chunks.values():
		if node.visible and node.mesh != null:
			visible_chunks += 1
	return "weather_density ready=%s enabled=%s chunks=%d cached=%d pending=%d steps=%d storm=%s grit=%d max_chunk_build_us=%d\n" % [_ready_density,_enabled,visible_chunks,_chunks.size(),_pending.size(),16 if _chunk_scale>1 else 24,_sand.visible,128 if _grit.visible else 0,max_build_us]
