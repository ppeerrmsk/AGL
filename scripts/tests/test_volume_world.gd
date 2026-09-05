extends RefCounted

const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Probe := preload("res://scripts/experiments/volume_world_probe.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_check(load("res://scripts/tests/test_volume_aircraft_catalog.gd").run(), "dedicated aircraft production batch")
	_check(load("res://scripts/tests/test_volume_map_factory.gd").new().run(), "static desert production batch")
	var manual_scene: PackedScene = load("res://scenes/tests/volume_3d_combat.tscn")
	_check(manual_scene != null and manual_scene.can_instantiate(), "manual combat scene available to F6")
	var manual_script: GDScript = load("res://scripts/experiments/volume_3d_combat.gd")
	_check(manual_script != null and manual_script.can_instantiate(), "manual combat script compiles")
	var smoke_script: GDScript = load("res://scripts/tests/volume_combat_smoke.gd")
	_check(smoke_script != null and smoke_script.can_instantiate(), "manual smoke script compiles before Visual")
	_check(load("res://scripts/experiments/volume_3d_lab.gd").COMBAT_SCENE_PATH
		== "res://scenes/tests/volume_3d_combat.tscn", "model viewer B key routes to manual battle")
	for kind in ["fighter", "a10", "mother_goose", "prop", "vls"]:
		var mesh := Factory.aircraft(kind)
		_check(mesh.get_surface_count() == 1, "%s single shared surface" % kind)
		_check(mesh.get_aabb().size.y > 1.0, "%s real thickness" % kind)
		_check(mesh.get_aabb().size.x > 0.0 and mesh.get_aabb().size.z > 0.0, "%s volume" % kind)
		var arrays := mesh.surface_get_arrays(0)
		_check(arrays[Mesh.ARRAY_VERTEX].size() == arrays[Mesh.ARRAY_NORMAL].size(), "%s normals" % kind)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		_check((vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).dot(normals[0]) < 0.0,
			"%s Godot clockwise front agrees with outward normal" % kind)
	_check(Factory.aircraft("mother_goose").get_aabb().size.x > 440.0, "Goose native wingspan")
	for angle in [0.0, 0.25, -0.25, 1.5]:
		for zoom in [0.2, 0.446, 1.0, 2.0]:
			var canvas := Transform2D(angle, Vector2(140, 300)).scaled_local(Vector2.ONE * zoom)
			var screen_center := Vector2(960, 540)
			var center := canvas.affine_inverse() * screen_center
			var point := Vector2(390, -820)
			var relative := Probe.camera_basis(canvas).inverse() * (Probe.world_point(point, 600) - Probe.world_point(center, 50000))
			var projected: Vector2 = screen_center + Vector2(relative.x, -relative.y) * zoom
			_check(projected.distance_to(canvas * point) < 0.001, "orthographic ground/click center match")
	var doc := MapDocument.load_from(Probe.MAP_PATH)
	_check(doc != null, "map document exists")
	if doc != null:
		var route := Factory.points_from(doc.railways[0].points)
		_check(route == ArmoredTrainBoss.train_route(), "rail mesh uses actual train route SSOT")
		_check(Factory.map_mesh(doc).get_surface_count() == 1, "static map merged once")
	var ac := Aircraft.new()
	Probe._set_body_override(ac, true)
	_check(ac.has_meta(Probe.BODY_META), "body override enabled")
	Probe._set_body_override(ac, false)
	_check(not ac.has_meta(Probe.BODY_META), "fallback restores old body")
	var reference: WeakRef = weakref(ac)
	ac.free()
	_check(reference.get_ref() == null, "weak cache does not retain freed aircraft")
	var mount := WeaponMount.new()
	var params := WeaponMountParams.new()
	params.max_hp = 200.0
	mount.initialize(params)
	_check(mount.apply_damage(200.0) and mount.destroyed, "real damage commits mount destruction")
	print("[Volume focused] pass=%d fail=%d" % [_pass, _fail])


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Volume: " + label)
