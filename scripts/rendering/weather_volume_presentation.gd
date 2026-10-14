extends Node3D
## GPU 连续动画；CPU 仅做稀疏块调度和天气权威采样，禁止逐粒 tick。
const CLOUD_SHADER := preload("res://resources/shaders/weather_volume.gdshader")
const SAND_SHADER := preload("res://resources/shaders/weather_sand.gdshader")
const GRIT_SHADER := preload("res://resources/shaders/weather_grit.gdshader")
const CHUNK := 4000.0
const CACHE_LIMIT := 96
var _source: WeakRef
var _cloud_material := ShaderMaterial.new()
var _sand_material := ShaderMaterial.new()
var _grit_material := ShaderMaterial.new()
var _chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _wanted: Dictionary = {}
var _sand := MeshInstance3D.new()
var _grit := MultiMeshInstance3D.new()
var _timer := 0.0
var _last_view := Rect2()
var _revision := -1
var _chunk_scale := 1
var _enabled := true
var _storm_signature := ""
var max_build_us := 0
var built_chunks := 0
var warm_results: Dictionary = {}


func setup(source: WeatherSystem) -> void:
	_source = weakref(source)
	_cloud_material.shader = CLOUD_SHADER
	_sand_material.shader = SAND_SHADER
	_grit_material.shader = GRIT_SHADER
	add_child(_sand)
	_sand.material_override = _sand_material
	_sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grit)
	_grit.material_override = _grit_material
	_grit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh(PackedVector3Array([Vector3(-12,0,0),Vector3(12,0,0),Vector3(0,0,3)]),
		PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE]))
	mm.instance_count = 128
	var rng := RandomNumberGenerator.new()
	rng.seed = 8341
	for i in range(128):
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.randf(),rng.randf(),rng.randf(),1))
	_grit.multimesh = mm
	_sand.hide()
	_grit.hide()
	source.set_meta(&"weather_volume_owner", weakref(self))
	source.queue_redraw()
	_prewarm_materials()


func _prewarm_materials() -> void:
	# 只在初始化临时暖绘两帧，普通Mesh与实例Mesh必须分别覆盖真实shader变体。
	if DisplayServer.get_name() == "headless":
		return
	var warm_script := preload("res://scripts/experiments/volume_material_warmup.gd")
	for material in [_cloud_material,_sand_material]:
		var warm: SubViewport = warm_script.new()
		warm.configure(material.duplicate())
		var key := "cloud" if material == _cloud_material else "sand"
		warm.finished.connect(func(result: Dictionary) -> void: warm_results[key] = result,CONNECT_ONE_SHOT)
		add_child(warm)
	var grit_warm: SubViewport = warm_script.new()
	var grit_sample := _grit_material.duplicate() as ShaderMaterial
	grit_sample.set_shader_parameter("field_size",Vector2.ZERO)
	var materials: Array[ShaderMaterial] = [grit_sample]
	grit_warm.configure_instanced(materials,Environment.new())
	var camera := grit_warm.get_node("WarmupCamera") as Camera3D
	camera.position = Vector3(0,200,0)
	camera.rotation = Vector3(-PI/2,0,0)
	camera.far = 400.0
	grit_warm.finished.connect(func(result: Dictionary) -> void: warm_results["grit"] = result,CONNECT_ONE_SHOT)
	add_child(grit_warm)


func sync(delta: float, canvas: Transform2D, viewport_size: Vector2, ground: Basis) -> void:
	if not _enabled:
		return
	var raw: Variant = _source.get_ref() if _source != null else null
	if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is WeatherSystem:
		hide()
		return
	var source: WeatherSystem = raw
	show()
	basis = ground
	if source.presentation_revision != _revision:
		_revision = source.presentation_revision
		for node: MeshInstance3D in _chunks.values():
			node.queue_free()
		_chunks.clear()
		_pending.clear()
		_timer = 0.0
	var wind := source._wind_offset()
	_cloud_material.set_shader_parameter("wind_offset", wind)
	_cloud_material.set_shader_parameter("weather_time", source._time)
	_sand_material.set_shader_parameter("weather_time", source._time)
	_grit_material.set_shader_parameter("weather_time", source._time)
	var inverse := canvas.affine_inverse()
	var view := Rect2(inverse * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(viewport_size.x,0), viewport_size, Vector2(0,viewport_size.y)]:
		view = view.expand(inverse * corner)
	view.position -= wind
	view = view.grow(1200.0)
	var desired_scale := _chunk_scale
	while maxf(view.size.x,view.size.y) > 28000.0*desired_scale:
		desired_scale *= 2
	while desired_scale > 1 and maxf(view.size.x,view.size.y) < 10000.0*desired_scale:
		desired_scale /= 2
	if desired_scale != _chunk_scale:
		_chunk_scale = desired_scale
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
		var key: Vector2i = _pending.pop_back()
		var started := Time.get_ticks_usec()
		var node := MeshInstance3D.new()
		node.mesh = build_cloud(source, key, _chunk_scale)
		node.material_override = _cloud_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# shader 世界风偏移也必须反映在 CPU 剔除包围盒中。
		node.extra_cull_margin = 24.0
		add_child(node)
		_chunks[key] = node
		built_chunks += 1
		max_build_us = maxi(max_build_us, Time.get_ticks_usec() - started)
	for key: Vector2i in _chunks:
		var node: MeshInstance3D = _chunks[key]
		node.visible = _wanted.has(key)
		if node.mesh.get_surface_count() > 0:
			var bounds := node.mesh.get_aabb()
			bounds.position += Vector3(wind.x,0,wind.y)
			node.custom_aabb = bounds
	_sync_storm(source, view.get_center() + wind, view.size)


func _select_chunks(view: Rect2) -> void:
	_wanted.clear()
	_pending.clear()
	var chunk_size := CHUNK * _chunk_scale
	for y in range(floori(view.position.y / chunk_size), ceili(view.end.y / chunk_size)):
		for x in range(floori(view.position.x / chunk_size), ceili(view.end.x / chunk_size)):
			var key := Vector2i(x,y)
			_wanted[key] = true
			if not _chunks.has(key):
				_pending.append(key)
	var center := view.get_center() / chunk_size
	_pending.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return Vector2(a).distance_squared_to(center) > Vector2(b).distance_squared_to(center))
	for key: Vector2i in _chunks.keys():
		if _chunks.size() + _pending.size() <= CACHE_LIMIT:
			break
		if not _wanted.has(key):
			_chunks[key].queue_free()
			_chunks.erase(key)


static func build_cloud(source: WeatherSystem, key: Vector2i, chunk_scale: int = 1) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var origin := Vector2(key) * CHUNK * chunk_scale
	for y in range(4):
		for x in range(2):
			var lattice := Vector2(key * Vector2i(2,4) + Vector2i(x,y))
			var phase := sin(lattice.dot(Vector2(12.98,78.2)))
			var center := origin + (Vector2(x*2000,y*1000) + Vector2(1000,500) + Vector2(phase,sin(lattice.dot(Vector2(39.3,-11.9))))*180.0)*chunk_scale
			var density := source._cloud_density_at(center.x,center.y)
			if density <= 0.04:
				continue
			var points: Array[Vector3] = []
			for ring in range(4):
				for segment in range(24):
					var angle := TAU*segment/24.0
					var radius := 1.0 + 0.20*sin(angle*3.0+phase*PI) + 0.08*cos(angle*5.0-phase)
					var offset := Vector2(cos(angle)*(1150+300*density)*(0.8+0.25*cos(lattice.x*17.1+lattice.y*3.4)),sin(angle)*(300+100*density)*(0.9+0.18*phase))*radius*float([0.60,1.0,0.90,0.58][ring])*chunk_scale
					offset = offset.rotated(0.35+0.25*phase)
					points.append(Vector3(center.x+offset.x,float([120.0,170.0,300+100*density,400+150*density][ring]),center.y+offset.y))
			points.append(Vector3(center.x,120,center.y))
			points.append(Vector3(center.x,440+200*density,center.y))
			for segment in range(24):
				var next := (segment+1)%24
				var faces := [[96,next,segment],[97,72+segment,72+next]]
				for ring in range(3):
					var lower := ring*24
					faces.append([lower+segment,lower+next,lower+24+next])
					faces.append([lower+segment,lower+24+next,lower+24+segment])
				for face in faces:
					var a: Vector3 = points[face[0]]
					var b: Vector3 = points[face[1]]
					var c: Vector3 = points[face[2]]
					var normal := (c-a).cross(b-a).normalized()
					var face_light := maxf(0,normal.dot(Vector3(-0.4,0.8,-0.3).normalized()))
					for index in face:
						var point: Vector3 = points[index]
						var height := inverse_lerp(120,440+200*density,point.y)
						var shade := 0.84+0.12*height+0.04*face_light
						var opacity := float([0.0,0.08,0.72,0.88][int(index)/24]) if index < 96 else (0.0 if index == 96 else 0.94)
						vertices.append(point)
						colors.append(Color(0.98*shade,0.99*shade,shade,opacity))
	return _mesh(vertices,colors)


static func _mesh(vertices: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _sync_storm(source: WeatherSystem, center: Vector2, size: Vector2) -> void:
	var active := source.is_sandstorm_active()
	_sand.visible = active
	_grit.visible = active
	if not source.sandstorm_enabled:
		return
	var width := source.sandstorm_band_width_px
	var storm_center := source.sandstorm_center_world()
	var signature := str([width, MapBoundary.world_half_px(),source.sandstorm_direction,source.sandstorm_tint])
	if signature != _storm_signature:
		_storm_signature = signature
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		for y in range(64):
			for x in range(16):
				var points: Array[Vector3] = []
				var shades: Array[Color] = []
				for uv in [Vector2(x,y),Vector2(x+1,y),Vector2(x+1,y+1),Vector2(x,y+1)]:
					var u: float = uv.x / 16.0
					var z: float = (uv.y/64.0-0.5)*MapBoundary.world_half_px()*2.0
					var edge_left := source._sandstorm_edge_wave(z,false)
					var edge_right := source._sandstorm_edge_wave(z,true)
					var px := (u-0.5)*width+lerpf(edge_left,edge_right,u)
					var edge := smoothstep(0.0,720.0,minf(u,1-u)*width)
					var front: float = u if source.sandstorm_direction.x > 0 else 1-u
					var ridge := exp(-pow((front-0.85)*9.0,2.0))
					points.append(Vector3(px,edge*(30+190*ridge),z))
					var tint := source.sandstorm_tint.darkened(0.18*(1-ridge))
					tint.a = edge
					shades.append(tint)
				for i in [0,1,2,0,2,3]:
					vertices.append(points[i])
					colors.append(shades[i])
		_sand.mesh = _mesh(vertices,colors)
	if not active:
		return
	_sand.position.x = storm_center.x
	var visible_width := maxf(1.0,minf(width-1440.0,size.x))
	_grit.visible = width > 1500.0 and absf(center.x-storm_center.x) < (width+size.x)*0.5
	var grit_center := clampf(center.x,storm_center.x-width*0.5+720+visible_width*0.5,storm_center.x+width*0.5-720-visible_width*0.5)
	var field_height := minf(size.y,MapBoundary.world_half_px()*2.0)
	var field_y := clampf(center.y,-MapBoundary.world_half_px()+field_height*0.5,MapBoundary.world_half_px()-field_height*0.5)
	_grit.position = Vector3(grit_center,0,field_y)
	_grit_material.set_shader_parameter("field_size",Vector2(visible_width,field_height))
	_grit_material.set_shader_parameter("direction",source.sandstorm_direction.x)
	_grit.custom_aabb = AABB(Vector3(-visible_width*0.5-30,0,-field_height*0.5-30),Vector3(visible_width+60,260,field_height+60))


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	var raw: Variant = _source.get_ref() if _source != null else null
	if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not raw is WeatherSystem:
		return
	if enabled:
		raw.set_meta(&"weather_volume_owner",weakref(self))
	else:
		var previous: Variant = raw.get_meta(&"weather_volume_owner") if raw.has_meta(&"weather_volume_owner") else null
		if previous is WeakRef and previous.get_ref() == self:
			raw.remove_meta(&"weather_volume_owner")
	raw.queue_redraw()


func summary() -> String:
	var visible_chunks := 0
	var triangles := 0
	for node: MeshInstance3D in _chunks.values():
		if node.visible and node.mesh.get_surface_count() > 0:
			visible_chunks += 1
			triangles += node.mesh.surface_get_array_len(0)/3
	return "weather_volume enabled=%s chunks=%d pending=%d cloud_triangles=%d storm=%s grit=%d max_chunk_build_us=%d\n" % [_enabled,visible_chunks,_pending.size(),triangles,_sand.visible,128 if _grit.visible else 0,max_build_us]


func _exit_tree() -> void:
	var raw: Variant = _source.get_ref() if _source != null else null
	if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is WeatherSystem:
		var owner_ref: Variant = raw.get_meta(&"weather_volume_owner") if raw.has_meta(&"weather_volume_owner") else null
		if owner_ref is WeakRef and owner_ref.get_ref() == self:
			raw.remove_meta(&"weather_volume_owner")
			raw.queue_redraw()
