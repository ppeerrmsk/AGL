extends RefCounted
const Catalog := preload("res://scripts/experiments/volume_ground_catalog.gd")
const Presenter := preload("res://scripts/experiments/volume_ground_presenter.gd")
var _pass := 0
var _fail := 0


func run() -> bool:
	_check(not Presenter.detail_mode_for(false, 25.99) and Presenter.detail_mode_for(false, 26),
		"ground LOD enters full at 26px")
	_check(Presenter.detail_mode_for(true, 20) and not Presenter.detail_mode_for(true, 19.99),
		"ground LOD exits full below 20px without boundary flicker")
	var ground := GroundUnit.new()
	ground.params = AircraftParams.new()
	ground.params.icon_color = Color.YELLOW
	for faction in [CombatUnit.TEAM_PLAYER, CombatUnit.TEAM_HOSTILE, CombatUnit.TEAM_ALLY]:
		ground.team = faction
		_check(Presenter.body_color_for(ground).is_equal_approx(GameConstants.team_color(faction)),
			"live faction overrides fixed resource paint")
		ground.is_destroyed = true
		_check(Presenter.body_color_for(ground).is_equal_approx(GameConstants.team_color(faction).darkened(.65)),
			"destroyed body retains its faction hue")
		ground.is_destroyed = false
	_check(ground.params.icon_color == Color.YELLOW, "shared resource paint remains unchanged")
	ground.free()
	for key in Catalog.keys():
		for detailed in [true, false]:
			var mesh := Catalog.build(key, detailed)
			_check(mesh != null and mesh == Catalog.build(key, detailed), key + " cached")
			if mesh == null:
				continue
			var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
			var valid := vertices.size() > 0
			for i in range(0, vertices.size(), 3):
				var cross := (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i])
				valid = valid and cross.is_finite() and cross.length_squared() > .000001 \
					and cross.normalized().dot(normals[i]) < -.99
			var budget := 2600 if key == "land_carrier" else (1200 if key.begins_with("train_") else 900)
			_check(valid and vertices.size() / 3 <= budget, key + " finite geometry / winding / budget")
		_check(Catalog.build(key, false).surface_get_array_len(0) <= Catalog.build(key).surface_get_array_len(0),
			key + " distant geometry never adds triangles")
	_check(Catalog.build("unknown") == null, "unadapted identities retain 2D fallback")
	_check(is_equal_approx(Catalog.build("land_carrier").get_aabb().size.z, 620.0), "carrier length unchanged")
	print("[Volume ground] pass=%d fail=%d" % [_pass, _fail])
	return _fail == 0


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Volume ground: " + label)
