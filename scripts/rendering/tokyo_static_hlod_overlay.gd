extends "res://scripts/rendering/tokyo_hlod_overlay.gd"
## 显式高内存诊断候选：同池预载全部最细叶；不授予旧面数/实例上限或正式性能通过。
const STATIC_MIN_SCALE := 1.25
var _static_leaves: Array[Dictionary]=[]
var _static_group: Node3D
var _static_materials: Array[ShaderMaterial]=[]
var _static_index := 0
var _static_ready := false
var _static_visible := false
var _static_hidden := PackedInt32Array()
var _static_canvas := Transform2D(0,Vector2(INF,INF))
var _static_size := Vector2.ZERO
var _static_cost: Dictionary={}
var _static_charge := 0
var _static_nodes := 0


func _setup_geometry() -> void:
	var neighborhood := loading_neighborhood_on_setup
	loading_neighborhood_on_setup=false
	# 全叶替代中景固定集，保留远景根页；避免同时常驻两份覆盖同一区域的高费用表示。
	var display_limit := display_budget
	display_budget=mini(display_budget,96*1024*1024)
	super._setup_geometry()
	display_budget=display_limit
	loading_neighborhood_on_setup=neighborhood
	if not _enabled: return
	if cache_pool_limit!=3072*1024*1024 or not resident_foundation or _native==null:
		_enabled=false;_fallback="static candidate requires qualified 3GiB pool and foundation";return
	var stack: Array=_native._partition_roots.get("lod5_full",_native.catalog.configurations.lod5_full).duplicate()
	var meshes: PackedStringArray=_stream.residency_meshes.duplicate()
	while not stack.is_empty():
		var entry: Dictionary=stack.pop_back()
		if not entry.get("children",[]).is_empty(): stack.append_array(entry.children);continue
		_static_leaves.append(entry)
		meshes.append(entry.path)
	if not _stream.configure_residency(meshes,_stream.residency_images,cache_pool_limit,true):
		_enabled=false;_fallback="static residency rejected";return
	_static_charge=_stream.residency_bytes
	_static_group=Node3D.new()
	# 远景旋转不能给整套隐藏细块传播世界变换；近景才同步这一独立根。
	_static_group.top_level=true
	_city.add_child(_static_group)
	_camera.cull_mask=1
	for kind in 3:
		var material := ShaderMaterial.new()
		material.shader=_native_surface
		material.set_shader_parameter("facade_detail",kind==1)
		_static_materials.append(material)
	var covered_entries: Array[Dictionary]=[]
	for entry: Dictionary in _static_leaves:
		var covered_entry: Dictionary=entry.duplicate()
		covered_entry.mask=[true,true,true]
		covered_entries.append(covered_entry)
	_static_hidden=_native.covered({"configuration":"lod5_full","entries":covered_entries})
	# 临时邻区的base必须包含固定叶，接管时只能解除邻区保护。
	if neighborhood:
		var source: Variant=_source_ref.get_ref()
		var camera: Variant=_camera_ref.get_ref()
		if typeof(source)==TYPE_OBJECT and is_instance_valid(source) and typeof(camera)==TYPE_OBJECT and is_instance_valid(camera):
			prepare_loading_neighborhood(camera.position,clampf(camera.zoom.x,0.0973,preload_max_scale),source.get_viewport().get_visible_rect().size)


func _build_static() -> void:
	if _static_ready or not _enabled: return
	if int(OS.get_memory_info().get("free",0))<1024*1024*1024:
		_enabled=false;_fallback="static preload stopped below 1GiB available RAM";return
	var started := Time.get_ticks_usec()
	while _static_index<_static_leaves.size():
		var entry: Dictionary=_static_leaves[_static_index]
		var page: Resource=_stream.resource(entry.path)
		if page==null: return
		for kind in 3:
			if int(entry.triangles[kind])==0: continue
			var instance := MeshInstance3D.new()
			instance.mesh=page.meshes[kind]
			instance.material_override=_static_materials[kind]
			instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.layers=2
			_static_group.add_child(instance)
			_static_nodes+=1
		_static_index+=1
		if Time.get_ticks_usec()-started>=2000: return
	_static_ready=true


func _step_geometry(view_bounds: Rect2, scale_value: float, delta: float) -> bool:
	_build_static()
	if not _static_ready or scale_value<STATIC_MIN_SCALE:
		if _static_visible:
			_static_visible=false;_camera.cull_mask=1
			_sync_legacy()
		return super._step_geometry(view_bounds,scale_value,delta)
	output_scale=scale_value
	var changed := not _static_visible or _static_canvas!=_last_canvas or _static_size!=_last_size
	if not _static_visible:
		_static_visible=true;_camera.cull_mask=2
	if not _static_group.basis.is_equal_approx(_city.basis): _static_group.basis=_city.basis
	if changed:
		_static_cost=_visible_static_cost(view_bounds,scale_value)
		_static_canvas=_last_canvas;_static_size=_last_size
	_screen.show()
	_sync_legacy()
	return changed


func _visible_static_cost(view: Rect2, scale_value: float) -> Dictionary:
	# 与正式投影相同，逐层保守记录可见面；不把整图驻留量冒充屏幕面数。
	var canvas := Transform2D(_last_canvas.get_rotation(),Vector2.ZERO).scaled(Vector2.ONE*scale_value)
	canvas.origin=_last_size*0.5-canvas.basis_xform(view.get_center())
	var ray := VolumeProjection.ground_basis(canvas,TILT).inverse()*VolumeProjection.camera_basis(canvas,TILT).z
	var roof := -Vector2(ray.x,ray.z)/ray.y
	var stack: Array=_native._partition_roots.get("lod5_full",_native.catalog.configurations.lod5_full).duplicate()
	var faces := 0
	var active := 0
	var parts: Dictionary={}
	while not stack.is_empty():
		var entry: Dictionary=stack.pop_back()
		var visible := preload("res://scripts/experiments/tokyo_spatial_select.gd").visible(entry,view,canvas,_last_size,roof,Vector2.ZERO)
		if int(visible.faces)==0: continue
		if not entry.get("children",[]).is_empty(): stack.append_array(entry.children);continue
		active+=1;faces+=int(visible.faces)
		parts.merge(_native.pages[entry.path].components,true)
	var amount := 0
	for descriptor: Dictionary in parts.values(): amount+=int(descriptor.bytes)
	return {"active":active,"triangles":faces,"bytes":amount}


func _sync_legacy() -> void:
	if not _static_visible:
		super._sync_legacy();return
	var renderer: Variant=_legacy.get_ref() if _legacy!=null else null
	if typeof(renderer)!=TYPE_OBJECT or not is_instance_valid(renderer): return
	var sources := _static_hidden if _active and is_instance_valid(_screen) and _screen.visible else PackedInt32Array()
	if sources!=_hidden_sources and renderer.set_volume_coverage(self,sources): _hidden_sources=sources


func debug_state() -> Dictionary:
	var state := super.debug_state()
	state.merge({"static_native_required":true,"static_native_ready":_static_ready,"static_native_visible":_static_visible,
		"static_native_leaves":_static_leaves.size(),"static_native_built":_static_index,"static_native_nodes":_static_nodes,
		"static_native_residency_bytes":_static_charge,"static_native_min_scale":STATIC_MIN_SCALE,"static_native_accepted":false},true)
	if _static_visible:
		state.merge({"cut_ready":true,"fallback":"","selection_current":_static_canvas==_last_canvas and _static_size==_last_size,
			"active_cells":_static_cost.active,"ready_cells":_static_cost.active,"desired_cells":_static_cost.active,
			"triangles":_static_cost.triangles,"display_bytes":_static_cost.bytes,"native_cut":true,"committed_catalog":-3},true)
	return state
