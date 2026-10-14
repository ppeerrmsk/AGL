extends RefCounted
## 共享地面表现适配器：仅缓存弱引用，逻辑、火控、命中和生命周期仍由真实单位持有。
const Catalog := preload("res://scripts/experiments/volume_ground_catalog.gd")
const BODY_META := &"volume_3d_ground"
var _members: Array[WeakRef] = []
var last_bodies := 0
var last_parts := 0
var peak_bodies := 0
var peak_parts := 0
var _detail_states: Dictionary = {}
var marker_points := PackedVector2Array()
var marker_colors := PackedColorArray()


func refresh_members() -> void:
	var previous := _members.duplicate()
	_members.clear()
	var alive: Dictionary = {}
	for raw: Variant in CombatUnit.all_units:
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not (raw is GroundUnit):
			continue
		if Catalog.key_for(raw).is_empty():
			continue
		_members.append(weakref(raw))
		alive[raw.get_instance_id()] = true
	for ref: WeakRef in previous:
		var raw: Variant = ref.get_ref()
		if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is GroundUnit \
				and not alive.has(raw.get_instance_id()):
			_set_override(raw, false)
	for id in _detail_states.keys():
		if not alive.has(id):
			_detail_states.erase(id)


func restore() -> void:
	for ref in _members:
		var raw: Variant = ref.get_ref()
		if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is GroundUnit:
			_set_override(raw, false)
	_detail_states.clear()


static func _set_override(unit: GroundUnit, active: bool) -> void:
	if bool(unit.get_meta(BODY_META, false)) == active:
		return
	if active:
		unit.set_meta(BODY_META, true)
	else:
		unit.remove_meta(BODY_META)
	unit.queue_redraw()


func sync(probe: Node3D, view: Rect2, canvas: Transform2D, output_scale: float) -> void:
	last_bodies = 0
	last_parts = 0
	marker_points = PackedVector2Array()
	marker_colors = PackedColorArray()
	for ref in _members:
		var raw: Variant = ref.get_ref()
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not (raw is GroundUnit):
			continue
		var unit: GroundUnit = raw
		var key := Catalog.key_for(unit)
		var radius := 400.0 if unit is LandCarrierUnit else (180.0 if unit is ArmoredTrainSegment else 65.0)
		var active: bool = probe.bodies_enabled and unit.is_visible_in_tree() and not unit.sensor_hidden \
			and unit.modulate.a >= .999 and unit.self_modulate.a >= .999 \
			and view.grow(radius * canvas.x.length()).has_point(canvas * unit.global_position)
		_set_override(unit, active)
		if not active:
			continue
		if unit is ArmoredTrainSegment and not unit.is_destroyed:
			_markers(unit, canvas * unit.global_transform)
		var size := 620.0 if unit is LandCarrierUnit else (236.0 if unit is ArmoredTrainSegment else 24.0)
		if unit is Tier3SuperCannonPart:
			size = 158.0
		elif unit is StrategicTarget:
			size = 68.0 if unit.target_kind == StrategicTarget.TargetKind.WAREHOUSE else 48.0
		var px := size * maxf(canvas.x.length(), canvas.y.length()) * output_scale
		var id := unit.get_instance_id()
		var detailed := detail_mode_for(bool(_detail_states.get(id, false)), px)
		_detail_states[id] = detailed
		var color := body_color_for(unit)
		var alpha := clampf(unit._destroy_timer / 2.0, 0.0, 1.0) if unit.is_destroyed else 1.0
		# 脱轨分段以真实 rotation 继续旋出；不重新套回 heading。
		var body := Transform3D(Basis(Vector3.UP, -unit.global_rotation),
			Vector3(unit.global_position.x, 0, unit.global_position.y))
		var owner: Variant = unit.get("owner_tank") if unit.has_meta(&"tier3_child_mount") else null
		var attached := typeof(owner) == TYPE_OBJECT and is_instance_valid(owner) and owner is GroundUnit
		if attached:
			# 真挂点替换为台面武器，不再给每个舰载炮塔画一辆履带车。
			body.origin.y = Catalog.DECK_HEIGHT + 1.0 if owner is LandCarrierUnit else \
				(Catalog.TRAIN_DECK_HEIGHT + 6.0 if owner is ArmoredTrainSegment else 5.0)
			var weapon_key := "vls_mount" if unit is SAMUnit else ("flak_turret" if unit is AirburstAAUnit else "aa_turret")
			var mount_scale := 2.3 if owner is ArmoredTrainSegment else 1.0
			body.basis = body.basis.scaled(Vector3.ONE * mount_scale)
			if unit is AAGunUnit:
				body.basis = Basis(Vector3.UP, -unit.turret_heading).scaled(Vector3.ONE * mount_scale)
			_emit(probe, weapon_key, body, color, alpha, detailed)
		else:
			_emit(probe, key, body, color, alpha, detailed)
			_parts(probe, unit, key, body, color, alpha, detailed)
		last_bodies += 1
	peak_bodies = maxi(peak_bodies, last_bodies)
	peak_parts = maxi(peak_parts, last_parts)


func _emit(probe: Node3D, key: String, transform: Transform3D, color: Color, alpha: float, detailed: bool) -> void:
	probe._submit("ground_" + ("full_" if detailed else "simple_") + key,
		transform, color, Color.TRANSPARENT, alpha, 0.0)
	last_parts += 1


static func detail_mode_for(current: bool, projected_span_px: float) -> bool:
	return projected_span_px >= (20.0 if current else 26.0)


static func body_color_for(unit: GroundUnit) -> Color:
	# 地面机体/附属武器的阵营识别统一读真实 team；不读取旧资源中固定的敌方色。
	# 不修改资源，更不改变飞机 icon_color/wing_color 或指挥/状态语义。
	var color := GameConstants.team_color(unit.team)
	if unit is ArmoredTrainSegment and unit.damageable:
		color = color.lightened(.20)
	return color.darkened(.65) if unit.is_destroyed else color


func _markers(unit: ArmoredTrainSegment, transform: Transform2D) -> void:
	# 与二维回退共享权威端点；放在合成纹理上方，不能让新车顶挡住尾节弱点。
	var lines := unit.armor_marker_lines()
	var color := GameConstants.team_color(unit.team)
	color = color.lightened(.35) if unit.damageable else Color(color, .34)
	var half_width := 1.5 if unit.damageable else 1.0
	for i in range(0, lines.size(), 2):
		var a := lines[i]
		var b := lines[i + 1]
		var normal := (b - a).normalized().orthogonal() * half_width
		marker_points.append_array(PackedVector2Array([transform * (a + normal),
			transform * (a - normal), transform * (b - normal), transform * (a + normal),
			transform * (b - normal), transform * (b + normal)]))
		for vertex in 6:
			marker_colors.append(color)


func _parts(probe: Node3D, unit: GroundUnit, key: String, body: Transform3D,
		color: Color, alpha: float, detailed: bool) -> void:
	var part := ""
	var height := 5.0
	var local_z := 0.0
	var heading := unit.global_rotation
	var part_scale := 1.0
	if unit is Tier3SuperCannonPart:
		part = "super_cannon_turret"
		height = 11
		heading = unit.heading
	elif unit is AtmosphereArtilleryUnit:
		part = "gun_turret"
		heading = unit.barrel_heading
	elif unit is AAGunUnit:
		part = "flak_turret" if unit is AirburstAAUnit else "aa_turret"
		heading = unit.turret_heading
	elif unit is SAMUnit:
		part = "sam_launcher"
	elif unit is RadarStation:
		part = "radar_head"
		height = 15
		local_z = -3
		heading = unit.heading + unit._dish_rotation
	elif unit is Tier3SiegeTank:
		part = "gun_turret"
		part_scale = 3
	elif unit is ArmoredTrainSegment:
		for z in [-unit._bogie_half_span_px, unit._bogie_half_span_px]:
			_emit(probe, "train_bogie", body * Transform3D(Basis.IDENTITY, Vector3(0, 0, z)), color, alpha, detailed)
		if unit.segment_index == ArmoredTrainSegment.RAILGUN_INDEX:
			part = "railgun_turret"
			height = Catalog.TRAIN_DECK_HEIGHT
			var manager: Variant = unit.train_manager
			if typeof(manager) == TYPE_OBJECT and is_instance_valid(manager):
				heading = float(manager.railgun_heading())
		elif unit.segment_index == ArmoredTrainSegment.RADAR_INDEX:
			part = "radar_head"
			height = 60
			local_z = -60
			part_scale = 2.3
	if part.is_empty():
		return
	var point := body * Vector3(0, height, local_z)
	var transform := Transform3D(Basis(Vector3.UP, -heading).scaled(Vector3.ONE * part_scale), point)
	var part_color := color.lightened(.32) if unit.is_firing and not unit.is_destroyed else color
	_emit(probe, part, transform, part_color, alpha, detailed)
