extends RefCounted

## 航母 CIWS 真实弹道 bench：直接驱动 NavalWeapons + BulletManager 的现役子弹、
## 散布、12px 碰撞半径、距离衰减与四挂点独占目标逻辑；导弹按各型号最大速度正向直飞。
## 运行：godot --headless --path . -- --bench=ciws_intercept

const DT: float = 1.0 / 60.0
const ISOLATED_TRIALS: int = 100
const SALVO_TRIALS: int = 20
const START_RANGE_PX: float = 1390.0

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 航母 CIWS 真实弹道审计 ════════")
	_check("四座 CIWS", _ciws_mount_count() == 4, "count=%d" % _ciws_mount_count())
	_check("获取距离 1400px", is_equal_approx(NavalWeapons.CIWS_INTERCEPT_RANGE_PX, 1400.0), "")
	_check("真弹周期 2", NavalWeapons.CIWS_REAL_BULLET_CYCLE == 2, "")
	_check("拦截伤害 10", is_equal_approx(NavalWeapons.CIWS_DAMAGE_PER_BULLET, 10.0), "")

	for version in [1, 4, 8]:
		var intercepted := 0
		var penetrated := 0
		for trial in range(ISOLATED_TRIALS):
			var result := _simulate(version, 1, 71000 + version * 1000 + trial)
			intercepted += int(result["intercepted"])
			penetrated += int(result["penetrated"])
		var rate := float(intercepted) / float(ISOLATED_TRIALS)
		print("  V%d isolated: intercepted=%d penetrated=%d rate=%.1f%%" % [
			version, intercepted, penetrated, rate * 100.0])
		_check("V%d 孤弹全部结算" % version, intercepted + penetrated == ISOLATED_TRIALS,
			"resolved=%d" % (intercepted + penetrated))
		if version == 1:
			_check("V1 孤弹具备有效拦截率", rate >= 0.50, "rate=%.1f%%" % (rate * 100.0))

	var penetration_by_size: Dictionary = {}
	for salvo_size in [2, 4, 5, 8]:
		var total_intercepted := 0
		var total_penetrated := 0
		for trial in range(SALVO_TRIALS):
			var result := _simulate(4, salvo_size, 81000 + salvo_size * 1000 + trial)
			total_intercepted += int(result["intercepted"])
			total_penetrated += int(result["penetrated"])
		penetration_by_size[salvo_size] = total_penetrated
		print("  V4 salvo×%d: intercepted=%d penetrated=%d penetration=%.1f%%" % [
			salvo_size, total_intercepted, total_penetrated,
			100.0 * float(total_penetrated) / float(salvo_size * SALVO_TRIALS)])
		_check("V4 ×%d 全部结算" % salvo_size,
			total_intercepted + total_penetrated == salvo_size * SALVO_TRIALS, "")
	_check("5 枚齐射可穿透四挂点并发", int(penetration_by_size[5]) > 0,
		"penetrated=%d" % int(penetration_by_size[5]))
	_check("8 枚齐射穿透不少于 4 枚齐射", int(penetration_by_size[8]) >= int(penetration_by_size[4]),
		"p4=%d p8=%d" % [int(penetration_by_size[4]), int(penetration_by_size[8])])

	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _simulate(version: int, salvo_size: int, rng_seed: int) -> Dictionary:
	seed(rng_seed)
	var params: NavalParams = load("res://resources/naval/carrier_cv.tres").duplicate(true)
	params.default_team = CombatUnit.TEAM_ALLY
	params.hull_hp_max = 300.0
	var ship := NavalUnit.new()
	ship.params = params
	ship.team = CombatUnit.TEAM_ALLY
	ship.altitude = 5000.0  # bench 中跳过 BuildingRenderer 查询；不影响 CIWS 空间弹道
	ship.global_position = Vector2.ZERO
	for cfg in params.mount_configs:
		var mount := WeaponMount.new()
		mount.initialize(cfg)
		ship.mounts.append(mount)

	var bullets := BulletManager.new()
	var missiles := MissileManager.new()
	bullets.missile_manager = missiles
	bullets.combat_unit_list = []
	ship.bullet_manager = bullets
	ship.missile_manager = missiles
	CombatUnit.all_units = []

	var missile_params: MissileParams = load(
		"res://resources/weapons/enemy_missile_v%d.tres" % version)
	var flight: Array[Dictionary] = []
	for i in range(salvo_size):
		var m := Missile.new()
		m.params = missile_params
		m.team = CombatUnit.TEAM_HOSTILE
		m.target = ship
		var x := (float(i) - float(salvo_size - 1) * 0.5) * 30.0
		m.global_position = Vector2(x, -START_RANGE_PX)
		var to_ship := ship.global_position - m.global_position
		m.heading = atan2(to_ship.x, -to_ship.y)
		m.speed = missile_params.max_speed
		m.intercept_hp = missile_params.intercept_hp
		missiles.add_child(m)
		flight.append({"missile": m, "resolved": false, "intercepted": false})

	var intercepted := 0
	var penetrated := 0
	var elapsed := 0.0
	while elapsed < 8.0 and intercepted + penetrated < salvo_size:
		elapsed += DT
		for item in flight:
			if item["resolved"] == true:
				continue
			var m: Missile = item["missile"]
			if m._fading_out:
				item["resolved"] = true
				item["intercepted"] = true
				intercepted += 1
				m.is_active = false
				continue
			var fwd := Vector2(sin(m.heading), -cos(m.heading))
			m.global_position += fwd * m.speed * CombatUnit.PIXELS_PER_METER * DT
			# MissileManager 对 NavalUnit 的真实有效引信半径 = hull_length / 2。
			if m.global_position.distance_to(ship.global_position) < params.hull_length * 0.5:
				item["resolved"] = true
				penetrated += 1
				m.is_active = false
		ship._update_subsystems(DT)
		bullets._physics_process(DT)

	# 超时按穿透计，防测试静默漏结算。
	for item in flight:
		if item["resolved"] != true:
			item["resolved"] = true
			penetrated += 1

	CombatUnit.all_units = []
	bullets.free()
	missiles.free()
	ship.free()
	return {"intercepted": intercepted, "penetrated": penetrated}


func _ciws_mount_count() -> int:
	var params: NavalParams = load("res://resources/naval/carrier_cv.tres")
	var count := 0
	for cfg in params.mount_configs:
		if cfg.weapon_type == WeaponMountParams.WeaponType.CIWS:
			count += 1
	return count


func _check(name: String, got: bool, note: String) -> void:
	if got:
		_pass += 1
	else:
		_fail += 1
	print("  %s %-32s — %s" % ["✓" if got else "✗", name, note])
