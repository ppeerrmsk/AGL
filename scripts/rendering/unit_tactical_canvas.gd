extends Node2D
## 仅活跃动态标记拥有此 Canvas；由世界覆盖层统一调度，无逐实体 _process。
const DisplayPacing := preload("res://scripts/util/display_pacing.gd")
var subject: WeakRef


static func visible_aircraft(value: Variant) -> Aircraft:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value) or not value is Aircraft:
		return null
	var ac := value as Aircraft
	if not ac.is_inside_tree() or ac.is_queued_for_deletion() or not ac.is_visible_in_tree():
		return null
	if ac.sensor_hidden:
		return null
	if ac.is_destroyed or ac._cloak_alpha <= 0.0:
		return ac if ac._tactic_popup_timer > 0.0 else null
	if ac.is_hidden_from_player_sensors():
		return ac if ac.is_mission_target and ac._sensor_contact_visual_alpha <= 0.001 else null
	return ac


static func needed(ac: Aircraft) -> bool:
	if ac._tactic_popup_timer > 0.0 or (ac.is_mission_target and ac.is_hidden_from_player_sensors()):
		return true
	if not ac._flare_particles.is_empty() or ac.formation_debug or ac.deadair_exposure_ratio > 0.0:
		return true
	if ac.equipment_state.has(RailgunEquipment.STATE_KEY) or ac.equipment_state.has(LaserEquipment.STATE_KEY):
		return true
	if ac.is_drone:
		return false
	return ac.team == 0 or ac.selected or ac.incoming_lock_progress > 0.0 or ac.is_locked or ac.is_mission_target


func bind(ac: Node2D) -> void:
	subject = weakref(ac)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func present() -> bool:
	var unit := visible_subject(subject.get_ref() if subject != null else null)
	if unit == null or not needs_subject(unit):
		visible = false
		return false
	visible = true
	var parent_canvas := get_parent() as Node2D
	transform = parent_canvas.get_global_transform_with_canvas().affine_inverse() * unit.get_canvas_transform() * DisplayPacing.display_global_transform(unit)
	self_modulate = unit.modulate
	if unit is Aircraft:
		var ac := unit as Aircraft
		var contact_alpha := 1.0 if ac.has_meta(CombatUnit.META_PRESENTATION_ACTOR_ACTIVE) else ac._sensor_contact_visual_alpha
		if not ac.is_destroyed and ac._cloak_alpha > 0.0 and not ac.is_hidden_from_player_sensors():
			self_modulate.a *= minf(ac._cloak_alpha, contact_alpha)
	queue_redraw()
	return true


func _draw() -> void:
	var unit := visible_subject(subject.get_ref() if subject != null else null)
	if unit is Missile:
		(unit as Missile)._draw_incoming_warning(self)
		return
	if unit is CombatUnit and not unit is Aircraft:
		AircraftRenderer.draw_deadair_exposure(unit as CombatUnit, self)
		return
	var ac := visible_aircraft(subject.get_ref() if subject != null else null)
	if ac == null:
		return
	if ac.is_destroyed or ac._cloak_alpha <= 0.0:
		AircraftRenderer.draw_tactic_popup(ac, self)
		return
	if ac.is_hidden_from_player_sensors():
		AircraftRenderer.draw_sensor_unknown_target(ac, self)
		return
	if not ac.is_drone:
		AircraftRenderer.draw_target_line(ac, self)
		AircraftRenderer.draw_lock_indicator(ac, self)
		AircraftRenderer.draw_target_bracket(ac, ac.is_mission_target, self)
	if AircraftRenderer.safe_player_ref() == ac:
		AircraftRenderer.draw_secondary_lock_indicators(ac, self)
	AircraftRenderer.draw_railgun_telegraph(ac, self)
	AircraftRenderer.draw_railgun_beam(ac, self)
	AircraftRenderer.draw_laser_beams(ac, self)
	AircraftRenderer.draw_flare_particles(ac, self)
	AircraftRenderer.draw_deadair_exposure(ac, self)
	if not ac.is_drone and not ac.has_meta("parent_carrier") and AircraftRenderer.should_draw_compact_label(ac):
		AircraftRenderer.draw_reload_indicators(ac, self)
	AircraftRenderer.draw_tactic_popup(ac, self)
	if ac.formation_debug:
		AircraftRenderer.draw_formation_debug(ac, self)


static func visible_subject(value: Variant) -> Node2D:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null
	if value is Missile:
		var missile := value as Missile
		if missile.is_inside_tree() and not missile.is_queued_for_deletion() and missile.is_visible_in_tree() and missile.is_active:
			return missile
		return null
	if value is CombatUnit and not value is Aircraft:
		var combat_unit := value as CombatUnit
		if combat_unit.is_inside_tree() and not combat_unit.is_queued_for_deletion() \
				and combat_unit.is_visible_in_tree() and not combat_unit.is_destroyed and not combat_unit.sensor_hidden:
			return combat_unit
		return null
	return visible_aircraft(value)


static func needs_subject(unit: Node2D) -> bool:
	if unit is Missile:
		return (unit as Missile).is_incoming_warning_for(AircraftRenderer.safe_player_ref())
	if unit is CombatUnit and not unit is Aircraft:
		return (unit as CombatUnit).deadair_exposure_ratio > 0.0
	return needed(unit as Aircraft)
