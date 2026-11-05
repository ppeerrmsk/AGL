extends RefCounted
## 世界状态栏只读快照：数据、可见性与文字在这里收口；不驱动武器或机体重绘。
const R = preload("res://scripts/aircraft_renderer.gd")


static func mode(item: Node2D) -> String:
	if not item.is_inside_tree() or item.is_queued_for_deletion() or not item.is_visible_in_tree():
		return ""
	# 演出借用演员时让出飞行画面；release 清标记后按现有刷新节拍恢复状态牌。
	if item.has_meta(CombatUnit.META_PRESENTATION_ACTOR_ACTIVE):
		return ""
	if item is Aircraft:
		var ac := item as Aircraft
		if ac.sensor_hidden:
			return ""
		if ac.is_destroyed:
			return "destroyed" if ac._destroy_status_timer > 0.0 else ""
		if ac._cloak_alpha <= 0.0 or ac.is_hidden_from_player_sensors() or ac.has_meta("parent_carrier"):
			return ""
		if ac.is_drone:
			return "drone"
		if R.should_draw_compact_label(ac):
			return "compact"
		return "minimal" if ac.hide_data_label else "full"
	if item is GroundUnit:
		if item.is_destroyed or item.sensor_hidden or not item.status_label_visible():
			return ""
		return "compact" if item._should_draw_compact_data_label() else "full"
	if item is NavalUnit:
		if item.is_destroyed or item.sensor_hidden or item.params == null:
			return ""
		item._compact_data_label_active = R.next_compact_label_state(
			item._compact_data_label_active, R.label_lod_scale(item))
		return "compact" if R.compact_label_visible(item._compact_data_label_active,
			Input.is_key_pressed(KEY_ALT)) else "full"
	if item is Missile:
		return "full" if item.is_active and item._should_draw_data_label() else ""
	return ""


static func screen_offset(item: Node2D) -> Vector2:
	if item is Aircraft:
		return R.data_label_screen_offset(item)
	var radius := 10.0
	if item is GroundUnit:
		radius = item._status_label_icon_radius_world()
	elif item is NavalUnit and item.params != null:
		radius = maxf(item.params.hull_width, item.params.hull_length) * 0.55
	var xform := item.get_global_transform_with_canvas()
	return R.unit_status_screen_offset_for(radius,
		xform.basis_xform(Vector2.RIGHT).length(), xform.origin)


static func build(item: Node2D, display_mode: String) -> Dictionary:
	if display_mode.is_empty():
		return {}
	var lines := PackedStringArray()
	var colors: Dictionary = {}
	var animated: Dictionary = {}
	var controlled := item is Aircraft and item == R.safe_player_ref()
	var palette: Array = []
	if item is Aircraft:
		_aircraft(item, display_mode, lines, colors, animated, controlled)
	elif item is GroundUnit:
		lines = item._status_label_lines(display_mode == "compact")
		if not lines.is_empty():
			lines[0] = R.english_status_identity(lines[0], "GROUND UNIT")
		R._append_status_label_lines(item, lines, colors)
	elif item is NavalUnit:
		lines.append(R.english_status_identity(item.full_name, item.ship_class_label))
		if display_mode != "compact":
			lines.append(R.status_heading_text(item.heading))
			lines.append(R.status_speed_knots_text(item.speed))
			lines.append(R.status_hp_text(item.hull_hp, item.hull_hp_max))
		R._append_status_label_lines(item, lines, colors)
	elif item is Missile:
		lines.append(R.english_status_identity(item.params.display_name if item.params else "MSL", "MISSILE"))
		lines.append(R.status_speed_knots_text(item.speed))
		var target: Variant = item.target
		var valid_target: bool = typeof(target) == TYPE_OBJECT and is_instance_valid(target) and target is CombatUnit and not target.is_destroyed
		var distance: float = item.global_position.distance_to(target.global_position) / CombatUnit.PIXELS_PER_METER if valid_target else 0.0
		lines.append(R.status_range_text(distance, valid_target))
		lines.append("GUIDED" if item.has_guidance else "UNGUIDED")
		palette = GameConstants.missile_label_colors(item.team)
	return {"item": weakref(item), "font": ThemeDB.fallback_font,
		"lines": lines, "row_colors": colors, "animated_rows": animated,
		"team": item.team, "controlled": controlled and display_mode != "destroyed",
		"palette": palette, "screen_offset_px": screen_offset(item)}


static func _aircraft(ac: Aircraft, display_mode: String, lines: PackedStringArray,
		colors: Dictionary, animated: Dictionary, controlled: bool) -> void:
	var model := R.compact_aircraft_name(ac.params.display_name) if ac.params else "AIRCRAFT"
	var identity := R.controlled_identity_label(ac) if ac.is_player_squad() else R.ally_identity_label(ac) if ac.team == CombatUnit.TEAM_ALLY else "%s [%s]" % [ac.callsign, model]
	if display_mode == "drone":
		identity = "DRONE"
	lines.append(R.english_status_identity(identity, "AIRCRAFT"))
	if display_mode == "destroyed":
		colors[lines.size()] = Color(1.0, 0.35, 0.28)
		lines.append("DESTROYED")
		lines.append(R.status_speed_knots_text(ac.speed))
		lines.append(R.status_altitude_text(ac.altitude, -maxf(absf(ac.vertical_speed), 5.1)))
		return
	if display_mode not in ["compact", "drone"]:
		lines.append(R.status_heading_text(ac.heading))
	lines.append(R.status_speed_knots_text(ac.speed))
	if display_mode not in ["compact", "drone"]:
		if controlled:
			colors[lines.size()] = R.altitude_tier_color(ac.get_altitude_tier(),
				ac.flat_altitude and absf(ac.vertical_speed) > 5.0)
		lines.append(R.status_altitude_text(ac.altitude, ac.vertical_speed))
		if display_mode == "minimal":
			lines.append("G %.1f" % ac.g_load)
		else:
			var player := R.safe_player_ref()
			if player != null and player != ac and not player.is_destroyed:
				lines.append(R.status_range_text(ac.global_position.distance_to(player.global_position) / CombatUnit.PIXELS_PER_METER))
			if ac.params and ac.params.flare:
				if controlled:
					colors[lines.size()] = R._wpn_color("FLR_READY" if ac.flares_remaining > 0 else "FLR_EMPTY")
				lines.append("FLR %d" % maxi(ac.flares_remaining, 0))
		_weapons(ac, lines, colors, animated, controlled, display_mode == "minimal")
		if ac.is_stalled:
			if controlled:
				animated[lines.size()] = "STALL"
			lines.append("STALL")
	# 无人机也显示真实状态；直写无敌只对当前操控机兜底，不泄漏出生演出保护。
	R._append_status_label_lines(ac, lines, colors, controlled)


static func _reload(lines: PackedStringArray, colors: Dictionary, label: String,
		progress: float, tag: String, controlled: bool) -> void:
	colors[lines.size()] = R.weapon_label_color(tag, controlled)
	lines.append("%s RELOAD %d%%" % [label, clampi(roundi(progress * 100.0), 0, 100)])


static func _weapons(ac: Aircraft, lines: PackedStringArray, colors: Dictionary,
		animated: Dictionary, controlled: bool, minimal: bool) -> void:
	if ac._gun_reload_active:
		_reload(lines, colors, "GUN", ac.gun_reload_progress, "GUN_RELOAD", controlled)
	if ac._missile_reload_active:
		_reload(lines, colors, "MSL", ac.missile_reload_progress, "MSL_RELOAD", controlled)
	if ac._secondary_reload_active and ac.secondary_missile_enabled and ac.params and ac.params.secondary_missile:
		_reload(lines, colors, R.english_status_identity(ac.params.secondary_missile.display_name, "SP"),
			R.secondary_reload_progress(ac), "SP_RELOAD", controlled)
	if ac.enable_flare_reload and ac.flares_remaining <= 0 and ac.params and ac.params.flare:
		animated[lines.size()] = "FLR_RELOAD"
		_reload(lines, colors, "FLR", ac.flare_reload_progress, "FLR_RELOAD", controlled)
	# 装备独立于热诱弹；仍只对当前操控机展示内部充能/热量。
	if not controlled or ac.params == null:
		return
	var rail: RailgunEquipment = ac.params.get_equipment_of_kind("railgun")
	if rail != null:
		var state: Dictionary = ac.equipment_state.get(RailgunEquipment.STATE_KEY, {})
		var tag := "RAIL_READY"
		var label := "RAIL READY"
		if bool(state.get("charging", false)):
			tag = "RAIL_CHG"
			label = "RAIL CHG %d%%" % clampi(roundi(float(state.get("charge_progress", 0.0)) * 100.0), 0, 100)
		elif float(state.get("cooldown", 0.0)) > 0.01:
			tag = "RAIL_CD"
			label = "RAIL CD %d%%" % clampi(roundi(float(state["cooldown"]) / maxf(rail.cooldown, 0.001) * 100.0), 0, 100)
		if not minimal or tag != "RAIL_READY":
			colors[lines.size()] = R._wpn_color(tag)
			lines.append(label)
	var laser: LaserEquipment = ac.params.get_equipment_of_kind("laser")
	if laser != null:
		var state: Dictionary = ac.equipment_state.get(LaserEquipment.STATE_KEY, {})
		if bool(state.get("overheating", false)):
			animated[lines.size()] = "LSR_OVERHEAT"
			lines.append("LSR OVERHEAT")
		else:
			var heat := clampi(roundi(float(state.get("heat", 0.0)) / maxf(laser.heat_max, 0.001) * 100.0), 0, 100)
			if not minimal or heat >= 50:
				colors[lines.size()] = R._wpn_color("LSR_HEAT", {"pct": heat})
				lines.append("LSR HEAT %d%%" % heat)


## 只观察行的增删和显示语义；连续数字仍按2Hz读取，不把动画当作数据刷新器。
static func event_key(item: Node2D, display_mode: String) -> Array:
	var key: Array = [display_mode, item.team, item == R.safe_player_ref()]
	if item is CombatUnit:
		key.append(item.status_effects.keys())
		key.append(item.status_jam_active)
	if item is Aircraft:
		key.append_array([item._gun_reload_active, item._missile_reload_active,
			item._secondary_reload_active, item.flares_remaining <= 0, item.is_stalled,
			item.is_afterburner_mode_active(), item.status_invincible_active,
			item.status_stealth_active, item.status_bloodlust_active, item.status_overload_active,
			item.status_fear_active, item.status_slow_active, item.is_cloaked, item.invulnerable,
			item.gun_tailed_active()])
	elif item is Missile:
		var target: Variant = item.target
		key.append(item.has_guidance)
		key.append(typeof(target) == TYPE_OBJECT and is_instance_valid(target)
			and target is CombatUnit and not target.is_destroyed)
	return key
