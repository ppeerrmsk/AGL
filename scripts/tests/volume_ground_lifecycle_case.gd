extends RefCounted
const Probe := preload("res://scripts/experiments/volume_world_probe.gd")
const Presenter := preload("res://scripts/experiments/volume_ground_presenter.gd")
const Catalog := preload("res://scripts/experiments/volume_ground_catalog.gd")
class Host:
	extends Node2D
	var camera := Camera2D.new()
	var _map_features: CanvasItem
	var _building_renderer: CanvasItem
var _fail := 0
var _pass := 0


func run(parent: Node) -> int:
	var host := Host.new()
	parent.add_child(host)
	host.add_child(host.camera)
	host.camera.zoom = Vector2.ONE * 2.0
	host.camera.make_current()
	var units: Array[GroundUnit] = [AAGunUnit.new(), SAMUnit.new(), RadarStation.new(),
		AtmosphereArtilleryUnit.new(), LandCarrierUnit.new(), ArmoredTrainSegment.new()]
	for i in units.size():
		var unit := units[i]
		unit.params = AircraftParams.new()
		unit.params.display_name = "GROUND QA"
		unit.params.max_hp = 100
		unit.position = Vector2(i * 45 - 110, 0)
		host.add_child(unit)
		unit.process_mode = Node.PROCESS_MODE_DISABLED
		CombatUnit.all_units.append(unit)
	var child := Tier3SiegeCIWS.new()
	child.params = AircraftParams.new()
	child.configure(units[4], Vector2(125, -190))
	host.add_child(child)
	child.process_mode = Node.PROCESS_MODE_DISABLED
	child._physics_process(.016)
	CombatUnit.all_units.append(child)
	units.append(child)
	for kind in 3:
		var target := StrategicTarget.new()
		target.target_kind = kind
		target.params = AircraftParams.new()
		target.params.max_hp = 100
		target.position = Vector2((kind - 1) * 70, -65)
		host.add_child(target)
		target.process_mode = Node.PROCESS_MODE_DISABLED
		CombatUnit.all_units.append(target)
		units.append(target)
	var cannon := Tier3SuperCannonPart.new()
	cannon.params = AircraftParams.new()
	cannon.params.max_hp = 100
	cannon.position = Vector2(0, 70)
	host.add_child(cannon)
	cannon.process_mode = Node.PROCESS_MODE_DISABLED
	CombatUnit.all_units.append(cannon)
	units.append(cannon)
	var probe := Probe.new()
	host.add_child(probe)
	probe.setup(host, "volume_3d_ground_lifecycle", {"include_map": false, "prewarm_catalog": true})
	probe.set_process(false)
	probe._process(.11)
	_check(probe._ground_presenter.last_bodies == units.size(), "all real ground actors are submitted")
	for unit in units:
		_check(unit.has_meta(Presenter.BODY_META), "3D owns body only; unit remains visible")
		_check(unit.visible and unit.hp == 100.0, "presentation leaves HP and visibility intact")
	var aa: AAGunUnit = units[0]
	aa.turret_heading = 1.25
	probe._process(.016)
	if DisplayServer.get_name() != "headless":
		var route := "ground_full_aa_turret"
		var submitted: Transform3D = probe._batches[route].multimesh.get_instance_transform(0)
		var expected: Basis = probe._display_ground * Basis(Vector3.UP, -aa.turret_heading)
		_check(submitted.basis.is_equal_approx(expected), "GPU turret follows authoritative aim")
	var train: ArmoredTrainSegment = units[5]
	_check(probe._ground_presenter.marker_points.size() == 12, "pre-stage cross is above composite")
	train.segment_index = 13
	train.set_targetable(true)
	train.set_damageable(true)
	probe._process(.11)
	_check(probe._ground_presenter.marker_points.size() == 48, "tail weakpoint keeps eight foreground edges")
	train.take_damage(1000, null, "missile")
	await parent.get_tree().process_frame
	probe._process(.11)
	_check(train.is_destroyed and train.detached and train.has_meta(Presenter.BODY_META),
		"real tail damage detaches the same 3D model")
	_check(probe._ground_presenter.marker_points.is_empty(), "destroyed segment clears foreground markers")
	for unit in units:
		if unit is StrategicTarget:
			unit.take_bomber_damage(1000, CombatUnit.TEAM_HOSTILE if unit.team != CombatUnit.TEAM_HOSTILE else CombatUnit.TEAM_PLAYER)
			await parent.get_tree().process_frame
			probe._process(.11)
			_check(unit.is_destroyed and unit.has_meta(Presenter.BODY_META), "real bomber hit preserves strategic 3D wreck")
	cannon.take_damage(1000, null, "missile")
	await parent.get_tree().process_frame
	probe._process(.11)
	_check(cannon.is_destroyed and cannon.has_meta(Presenter.BODY_META), "real cannon death retains 3D model")
	units[4].take_damage(1000, null, "missile")
	child._physics_process(.016)
	var child_value: Variant = child
	CombatUnit.all_units.erase(child)
	units.erase(child)
	await parent.get_tree().process_frame
	probe._process(.016)
	probe._process(.11)
	_check(not is_instance_valid(child_value), "dead owner frees its real weapon; weak cache consumer completes")
	probe.set_bodies_enabled(false)
	for unit in units:
		_check(not unit.has_meta(Presenter.BODY_META), "toggle restores 2D body")
	probe.set_bodies_enabled(true)
	_check(aa.has_meta(Presenter.BODY_META), "toggle rebuilds surviving ground state")
	CombatUnit.all_units.erase(aa)
	probe._refresh_members()
	_check(not aa.has_meta(Presenter.BODY_META), "removed but live actor restores its fallback")
	CombatUnit.all_units.append(aa)
	probe._refresh_members()
	probe._process(.016)
	probe.queue_free()
	await parent.get_tree().process_frame
	_check(not aa.has_meta(Presenter.BODY_META), "renderer exit restores surviving ground actor")
	for unit in units:
		CombatUnit.all_units.erase(unit)
	host.queue_free()
	await parent.get_tree().process_frame
	print("[Ground lifecycle] pass=%d fail=%d" % [_pass, _fail])
	return _fail


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Ground lifecycle: " + label)
