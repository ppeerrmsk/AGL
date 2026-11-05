extends RefCounted
## 真发射→目标死亡→跨LOD装填；无机体重绘读数刷新；跨兵种清理与切控。
const Snapshot := preload("res://scripts/ui/unit_status_snapshot.gd")
const Overlay := preload("res://scripts/ui/world_unit_status_overlay.gd")
const Preview := preload("res://scripts/tests/aircraft_silhouette_preview.gd")
var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[UnitStatus] FAIL " + label)


func run(host: Node) -> int:
	var old_player := AircraftRenderer.safe_player_ref()
	var old_units := CombatUnit.all_units.duplicate()
	var stage := Node2D.new()
	host.add_child(stage)
	var layer := CanvasLayer.new()
	stage.add_child(layer)
	var overlay := Overlay.new()
	layer.add_child(overlay)
	var camera := Camera2D.new()
	stage.add_child(camera)
	camera.make_current()
	var ac := Preview.new()
	ac.params = load("res://resources/enemy_f4e.tres").duplicate(true)
	ac.callsign = "BADGER"
	ac.team = CombatUnit.TEAM_HOSTILE
	ac.draw_runtime_label = true
	ac.position = Vector2(300, 220)
	stage.add_child(ac)
	AircraftRenderer.register_status_subject(ac)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	overlay._sync_registered_panels()
	check(_lines(ac).has("HDG 000"), "initial read")
	var draw_count := ac.draw_probe_calls
	ac.heading = deg_to_rad(42.0)
	ac.speed = 250.0
	ac.altitude = 3456.0
	ac._missile_reload_active = true
	ac.missile_reload_progress = 0.24
	ac.apply_status(StatusEffects.JAM, 10.0)
	await host.get_tree().create_timer(0.60).timeout
	check(_lines(ac).has("MSL RELOAD 24%") and _lines(ac).has("HDG 042")
		and _lines(ac).has("ALT 3456 M"), "read changes without body redraw")
	await _capture(host, "reload_24")
	ac.missile_reload_progress = 0.71
	ac.remove_status(StatusEffects.JAM)
	await host.get_tree().create_timer(0.60).timeout
	check(_lines(ac).has("MSL RELOAD 71%") and not _lines(ac).has("JAM 100%"), "progress and expired effect")
	await _capture(host, "reload_71")
	ac._missile_reload_active = false
	await host.get_tree().create_timer(0.10).timeout
	check(not _contains(_lines(ac), "MSL RELOAD"), "completion removes row")
	await _capture(host, "reload_complete")
	check(ac.draw_probe_calls == draw_count, "content does not request body redraw")
	# 控制权、隐藏、复现、zoom均不依赖机体重新登记。
	AircraftRenderer.player_ref = ac
	await host.get_tree().create_timer(0.10).timeout
	check(bool(AircraftRenderer.status_panel_entry(ac.get_instance_id()).get("controlled", false)), "control switch")
	ac.sensor_hidden = true
	await host.get_tree().create_timer(0.10).timeout
	check(AircraftRenderer.status_panel_entry(ac.get_instance_id()).is_empty(), "sensor hide")
	ac.sensor_hidden = false
	camera.zoom = Vector2.ONE * 0.2
	camera.force_update_scroll()
	await host.get_tree().create_timer(0.10).timeout
	check(not _contains(_lines(ac), "HDG "), "compact transition without draw")
	camera.zoom = Vector2.ONE
	camera.force_update_scroll()
	await host.get_tree().create_timer(0.10).timeout
	check(_lines(ac).has("HDG 042"), "full transition without draw")
	var cast := CinematicCast.new()
	cast.bind([ac], GameEvent.new())
	await host.get_tree().create_timer(0.10).timeout
	check(AircraftRenderer.status_panel_entry(ac.get_instance_id()).is_empty(), "cinematic actor hides panel")
	cast.release()
	await host.get_tree().create_timer(0.10).timeout
	check(_lines(ac).has("HDG 042"), "cinematic release restores panel")
	# 装备与热诱弹互不门控；状态列表由所有飞机档位共用。
	var rail := RailgunEquipment.new()
	var laser := LaserEquipment.new()
	ac.params.equipment.assign([rail, laser])
	ac.equipment_state[RailgunEquipment.STATE_KEY] = {"charging": true, "charge_progress": 0.5}
	ac.equipment_state[LaserEquipment.STATE_KEY] = {"overheating": true}
	ac.flares_remaining = 5
	var entry := Snapshot.build(ac, "minimal")
	check(entry["lines"].has("RAIL CHG 50%") and entry["lines"].has("LSR OVERHEAT"), "equipment independent of flare")
	ac.apply_status(StatusEffects.SLOW, 10.0)
	check(_contains(Snapshot.build(ac, "drone")["lines"], "SLOW"), "drone status")
	ac.remove_status(StatusEffects.SLOW)
	AircraftRenderer.player_ref = null
	var ground_ids: Array[int] = []
	for unit: GroundUnit in [GroundUnit.new(), AAGunUnit.new(), SAMUnit.new(), RadarStation.new(), AirburstAAUnit.new(), StrategicTarget.new()]:
		unit.team = CombatUnit.TEAM_HOSTILE
		stage.add_child(unit)
		unit.set_physics_process(false)
		AircraftRenderer.register_status_subject(unit)
		ground_ids.append(unit.get_instance_id())
		for sid: String in StatusEffects.DISPLAY_ORDER:
			unit.apply_status(sid, 10.0)
		var ground_entry := Snapshot.build(unit, "full")
		for sid: String in StatusEffects.DISPLAY_ORDER:
			check(ground_entry["lines"].has(StatusEffects.english_label(sid) + " 100%"), "ground effect " + sid)
		if unit is SAMUnit:
			check(ground_entry["lines"].has("RNG ---"), "SAM missing observer")
		var exits := [0]
		unit.tree_exited.connect(func(): exits[0] += 1)
		if unit is StrategicTarget:
			unit.take_bomber_damage(1000000.0, CombatUnit.TEAM_PLAYER)
		else:
			unit.take_damage(1000000.0, null, "gun")
		await host.get_tree().create_timer(0.10).timeout
		check(unit.is_destroyed
			and AircraftRenderer.status_panel_entry(unit.get_instance_id()).is_empty(), "real ground death removes panel")
		unit.queue_free()
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		check(exits[0] == 1, "ground exit signal once")
	_weapon_holds(stage)
	await _readout_edges(stage, host)
	for lod in [0, 1, 2]:
		await _reload_case(stage, host, lod)
	await _formation_reload_case(stage, host)
	# 已释放弱引用、树外来源和残留记录必须从两张表同时删除。
	var ac_id := ac.get_instance_id()
	ac.queue_free()
	await host.get_tree().create_timer(0.60).timeout
	check(not AircraftRenderer.status_subject_ids().has(ac_id)
		and not overlay._panels.has(ac_id), "free clears source and canvas")
	for id in ground_ids:
		check(not AircraftRenderer.status_subject_ids().has(id), "ground weak source cleared")
	stage.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	check(AircraftRenderer.status_panel_entry_count() == 0
		and AircraftRenderer.status_subject_ids().is_empty(), "scene exit clears registry")
	CombatUnit.all_units.assign(old_units)
	AircraftRenderer.player_ref = old_player
	print("[UnitStatus] reached end checks=%d failures=%d" % [checks, failures])
	return failures


func _reload_case(stage: Node2D, host: Node, lod: int) -> void:
	# 每个真实发射场景使用自己的交战账本，既保留正式发射门，也不消费其它用例的攻击名额。
	var old_director := EncounterDirector._active
	var director := EncounterDirector.new(null)
	var ac := Aircraft.new()
	ac.params = load("res://resources/enemy_f4e.tres").duplicate(true)
	ac.team = CombatUnit.TEAM_HOSTILE
	stage.add_child(ac)
	ac.set_physics_process(false)
	ac.use_tactical_planner = false
	ac.flat_altitude = true
	ac.altitude = 5500.0
	ac.target_altitude = 5500.0
	ac.speed = 240.0
	ac.target_speed_kmh = 864.0
	ac.lod_level = lod
	ac.enable_missile_reload = true
	ac.missile_reload_duration = 1.0
	ac.enable_gun_reload = true
	ac._gun_reload_active = true
	ac.gun_reload_duration = 1.0
	ac.ammo = 0
	ac.missiles_remaining = 1
	var manager := MissileManager.new()
	stage.add_child(manager)
	manager.set_physics_process(false)
	ac.missile_manager = manager
	var target := CombatUnit.new()
	target.team = CombatUnit.TEAM_PLAYER
	target.position = Vector2(0, -2000)
	stage.add_child(target)
	ac.set_combat_target(target)
	AircraftWeapons._fire_missile_at(ac, target, ac.params.missile)
	check(ac._missile_reload_active and ac.missiles_remaining == 0, "real shot starts reload LOD%d" % lod)
	for missile: Missile in Missile.active_missiles.duplicate():
		if missile.source == ac:
			missile.set_physics_process(false)
			missile.queue_free()
	target.take_damage(1000000.0, null, "gun")
	ac.clear_combat_target()
	target.queue_free()
	await host.get_tree().process_frame
	# 与真实物理相同的60Hz积分；每个LOD仍由生产入口自行节流。
	for tick in range(30):
		ac._physics_process(1.0 / 60.0)
	check(ac.missile_reload_progress > 0.40 and ac.gun_reload_progress > 0.40, "target loss does not freeze LOD%d" % lod)
	for tick in range(40):
		ac._physics_process(1.0 / 60.0)
	check(not ac._missile_reload_active and not ac._gun_reload_active and ac.missiles_remaining == ac.params.missile.max_count, "reload completes LOD%d" % lod)
	check(not _contains(Snapshot.build(ac, "full")["lines"], "MSL RELOAD"), "completed snapshot LOD%d" % lod)
	ac.queue_free()
	manager.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	director.shutdown()
	check(EncounterDirector._active == null, "shot fixture releases attack ledger LOD%d" % lod)
	EncounterDirector._active = old_director


static func _lines(item: Node2D) -> PackedStringArray:
	return AircraftRenderer.status_panel_entry(item.get_instance_id()).get("lines", PackedStringArray())


static func _contains(lines: PackedStringArray, prefix: String) -> bool:
	for line in lines:
		if line.begins_with(prefix):
			return true
	return false



func _weapon_holds(stage: Node2D) -> void:
	var ac := Aircraft.new()
	ac.params = load("res://resources/enemy_f4e.tres").duplicate(true)
	ac.params.gun = GunParams.new()
	ac.params.secondary_missile = ac.params.missile.duplicate(true)
	ac.params.secondary_missile.cooldown = 1.0
	ac.params.secondary_missile.max_count = 1
	stage.add_child(ac)
	ac.set_physics_process(false)
	ac.enable_missile_reload = true
	ac.missile_reload_duration = 1.0
	ac._missile_reload_active = true
	ac.missiles_remaining = 0
	ac.status_jam_active = true
	AircraftWeapons.update_missile(ac, 0.25)
	check(is_equal_approx(ac.missile_reload_progress, 0.25), "JAM main reload keeps time")
	ac.secondary_missile_enabled = true
	ac._secondary_reload_active = true
	ac.secondary_missiles_remaining = 0
	AircraftWeapons.update_secondary_missile(ac, 0.25)
	check(is_equal_approx(ac._secondary_reload_timer, 0.25), "JAM secondary reload keeps time")
	ac.status_jam_active = false
	ac.evasion_mode = true
	AircraftWeapons.update_secondary_missile(ac, 0.25)
	check(is_equal_approx(ac._secondary_reload_timer, 0.5), "evasion secondary reload keeps time")
	ac.evasion_mode = false
	ac.set_afterburner_mode_active(true)
	AircraftWeapons.update_secondary_missile(ac, 0.25)
	check(is_equal_approx(ac._secondary_reload_timer, 0.75), "AB secondary reload keeps time")
	AircraftWeapons.update_secondary_missile(ac, 0.25)
	check(not ac._secondary_reload_active and ac.secondary_missiles_remaining == 1, "secondary completes under ceasefire")
	ac.set_afterburner_mode_active(false)
	ac.team = CombatUnit.TEAM_PLAYER
	ac.set_meta("upgrade_stacks", {"sig_f22": 1})
	ac.ammo = 0
	ac._gun_reload_active = true
	ac.gun_reload_progress = 0.35
	ac.apply_status(StatusEffects.STEALTH, 5.0)
	check(not ac._gun_reload_active and not ac._missile_reload_active
		and ac.gun_reload_progress == 0.0 and ac.missile_reload_progress == 0.0
		and ac.ammo == ac.params.gun.max_ammo and ac.missiles_remaining == ac.params.missile.max_count,
		"real STEALTH skill refill clears active/progress")
	ac.queue_free()


func _readout_edges(stage: Node2D, host: Node) -> void:
	var target := CombatUnit.new()
	stage.add_child(target)
	var missile := Missile.new()
	missile.params = load("res://resources/default_missile.tres").duplicate(true)
	missile.target = target
	stage.add_child(missile)
	missile.set_physics_process(false)
	missile.position = target.position
	check(Snapshot.build(missile, "full")["lines"].has("RNG 0 M"), "zero range is a valid distance")
	var radar := RadarStation.new()
	stage.add_child(radar)
	radar.set_physics_process(false)
	radar.radar_targets[target] = 100.0
	check(radar._status_label_lines(false).has("TRK 1"), "radar live track")
	target.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	check(Snapshot.build(missile, "full")["lines"].has("RNG ---"), "freed target range unavailable")
	check(not _contains(radar._status_label_lines(false), "TRK"), "freed radar track excluded")
	missile.has_guidance = false
	check(Snapshot.build(missile, "full")["lines"].has("UNGUIDED"), "guidance loss readout")
	AircraftRenderer.register_status_subject(missile)
	missile.is_active = false
	check(Snapshot.mode(missile).is_empty(), "inactive missile hides")
	radar.radar_targets.clear()
	radar.apply_status(StatusEffects.JAM, 0.1)
	radar._physics_process_radar_station_untraced(0.2)
	check(not radar.has_status(StatusEffects.JAM), "radar status expires through real tick")
	radar.queue_free()
	missile.queue_free()
	var ship := NavalUnit.new()
	ship.params = load("res://resources/naval/frigate_ffg.tres").duplicate(true)
	stage.add_child(ship)
	ship.set_physics_process(false)
	ship.hull_hp = 31.0
	ship.heading = deg_to_rad(359.6)
	ship.apply_status(StatusEffects.JAM, 10.0)
	var entry := Snapshot.build(ship, "full")
	check(entry["lines"].has("HDG 000") and entry["lines"].has(AircraftRenderer.status_hp_text(31.0, ship.hull_hp_max))
		and entry["lines"].has("JAM 100%"), "naval hull/heading/status")
	check(not _contains(Snapshot.build(ship, "compact")["lines"], "HP "), "naval compact")
	ship.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame



func _formation_reload_case(stage: Node2D, host: Node) -> void:
	var leader := Aircraft.new()
	leader.params = load("res://resources/enemy_f4e.tres").duplicate(true)
	stage.add_child(leader)
	leader.set_physics_process(false)
	leader.altitude = 5500.0
	leader.speed = 240.0
	for lod in [0, 1, 2]:
		for phase in [-1, 0, 1, 2]:
			var ac := Aircraft.new()
			ac.params = leader.params.duplicate(true)
			ac.params.secondary_missile = ac.params.missile.duplicate(true)
			ac.params.secondary_missile.cooldown = 1.0
			ac.params.secondary_missile.max_count = 1
			stage.add_child(ac)
			ac.set_physics_process(false)
			ac.set_formation_target(leader, Vector2(50, 50))
			ac.lod_level = lod
			ac.altitude = 5500.0
			ac.speed = 240.0
			ac.enable_missile_reload = true
			ac._missile_reload_active = true
			ac.missile_reload_duration = 1.0
			ac.missiles_remaining = 0
			ac.secondary_missile_enabled = true
			ac._secondary_reload_active = true
			ac.secondary_missiles_remaining = 0
			if phase >= 0:
				ac.set_meta("dense_battle_sim_divisor", 3)
				ac.set_meta("dense_battle_sim_phase", phase)
			for tick in range(30):
				ac._physics_process(1.0 / 60.0)
			check(absf(ac.missile_reload_progress - 0.5) < 0.06
				and absf(ac._secondary_reload_timer - 0.5) < 0.06,
				"formation clock LOD%d phase%d" % [lod, phase])
			for tick in range(40):
				ac._physics_process(1.0 / 60.0)
			check(not ac._missile_reload_active and not ac._secondary_reload_active,
				"formation complete LOD%d phase%d" % [lod, phase])
			ac.queue_free()
			await host.get_tree().process_frame
			await host.get_tree().process_frame
	leader.queue_free()
	await host.get_tree().process_frame



static func _capture(host: Node, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := "res://bench/results/unit_status_%s.png" % label
	var result := host.get_viewport().get_texture().get_image().save_png(path)
	print("[UnitStatus] screenshot=%s result=%d" % [path, result])
