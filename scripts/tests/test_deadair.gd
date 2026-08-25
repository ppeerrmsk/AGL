extends RefCounted

const DeadairController = preload("res://scripts/survivor/deadair_controller.gd")
const EnemyPoolRegistry = preload("res://scripts/survivor/enemy_pool_registry.gd")

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ DEADAIR 累积 JAM 光环 ════════")
	_test_unit_accumulation()
	_test_unit_grace_and_decay()
	_test_missile_acceleration_and_exit_reset()
	_test_runtime_jam_path()
	_test_registry_and_body()
	_test_support_field_mutual_exclusion()
	_test_tier3_priority_replacement()
	_test_i18n_resources()
	_test_automation_audio_gate()
	print("──────── 结果：%d 通过 / %d 失败 ────────\n" % [_pass, _fail])


func _test_unit_accumulation() -> void:
	var exposure := 0.0
	for _i in range(39):
		exposure = float(DeadairController.next_unit_exposure(exposure, 0.0, true, 0.2)["exposure"])
	_check("单位 7.8s 尚未 JAM", exposure < DeadairController.UNIT_THRESHOLD_S, str(exposure))
	exposure = float(DeadairController.next_unit_exposure(exposure, 0.0, true, 0.2)["exposure"])
	_check("单位 8.0s 达到 JAM 阈值", is_equal_approx(exposure, 8.0), str(exposure))


func _test_unit_grace_and_decay() -> void:
	var state := DeadairController.next_unit_exposure(6.0, 0.0, false, 1.0)
	_check("离场 1s 宽限不衰减", is_equal_approx(float(state["exposure"]), 6.0), str(state))
	state = DeadairController.next_unit_exposure(float(state["exposure"]),
		float(state["outside"]), false, 0.5)
	_check("宽限后按 2/s 衰减", is_equal_approx(float(state["exposure"]), 5.0), str(state))


func _test_missile_acceleration_and_exit_reset() -> void:
	var exposure := 0.0
	for _i in range(9):
		exposure = DeadairController.next_missile_exposure(exposure, true, 0.2)
	_check("导弹 1.8s 尚未失导", exposure < 8.0, str(exposure))
	exposure = DeadairController.next_missile_exposure(exposure, true, 0.2)
	_check("导弹 2.0s 达到失导阈值", is_equal_approx(exposure, 8.0), str(exposure))
	_check("导弹离场立即清零", is_zero_approx(
		DeadairController.next_missile_exposure(exposure, false, 0.2)), "")


func _test_runtime_jam_path() -> void:
	var saved_units := CombatUnit.all_units.duplicate()
	var host := Aircraft.new()
	var friendly := Aircraft.new()
	var ally := Aircraft.new()
	var ground := GroundUnit.new()
	var naval := NavalUnit.new()
	var hostile_peer := Aircraft.new()
	host.team = CombatUnit.TEAM_HOSTILE
	friendly.team = CombatUnit.TEAM_PLAYER
	ally.team = CombatUnit.TEAM_ALLY
	ground.team = CombatUnit.TEAM_PLAYER
	naval.team = CombatUnit.TEAM_ALLY
	hostile_peer.team = CombatUnit.TEAM_HOSTILE
	host.global_position = Vector2.ZERO
	friendly.global_position = Vector2(100.0, 0.0)
	ally.global_position = Vector2(120.0, 0.0)
	ground.global_position = Vector2(140.0, 0.0)
	naval.global_position = Vector2(160.0, 0.0)
	hostile_peer.global_position = Vector2(180.0, 0.0)
	CombatUnit.all_units = [host, friendly, ally, ground, naval, hostile_peer]
	var controller := DeadairController.new(null)
	controller.register(host)
	for _i in range(40):
		controller._tick_units(host, 0.2)
	_check("真实 CombatUnit 路径在 8s 写入标准 JAM 容器", friendly.has_status(StatusEffects.JAM),
		"status=%s" % str(friendly.status_effects))
	_check("TEAM_ALLY/地面/海军使用同一敌对口径", ally.has_status(StatusEffects.JAM)
		and ground.has_status(StatusEffects.JAM) and naval.has_status(StatusEffects.JAM),
		"ally=%s ground=%s naval=%s" % [ally.status_effects, ground.status_effects, naval.status_effects])
	_check("HOSTILE 同阵营单位完全不受场影响", not hostile_peer.has_status(StatusEffects.JAM)
		and is_zero_approx(hostile_peer.deadair_exposure_ratio), str(hostile_peer.status_effects))
	# status_jam_active 由 CombatUnit 的状态 tick 派生；控制器只负责写标准容器，不能伪造派生标记。
	var missile := Missile.new()
	missile.team = CombatUnit.TEAM_PLAYER
	missile.global_position = Vector2(100.0, 0.0)
	Missile.active_missiles.append(missile)
	for _i in range(10):
		controller._tick_missiles(host, 0.2)
	_check("真实 Missile 路径在 2s 永久失导", missile.is_flare_jammed and not missile.has_guidance,
		"jam=%s guidance=%s" % [missile.is_flare_jammed, missile.has_guidance])
	controller.retire(host)
	_check("来源退役同拍移除它施加的 JAM 与暴露效果",
		not friendly.has_status(StatusEffects.JAM) and not ally.has_status(StatusEffects.JAM) \
			and not ground.has_status(StatusEffects.JAM) and not naval.has_status(StatusEffects.JAM) \
			and is_zero_approx(friendly.deadair_exposure_ratio),
		"friendly=%s ally=%s ground=%s naval=%s" % [friendly.status_effects,
			ally.status_effects, ground.status_effects, naval.status_effects])
	_check("来源退役不倒带已经结算的导弹永久失导", missile.is_flare_jammed \
		and not missile.has_guidance, "jam=%s guidance=%s" % [missile.is_flare_jammed,
			missile.has_guidance])
	Missile.active_missiles.erase(missile)
	CombatUnit.all_units.assign(saved_units)
	missile.free()
	hostile_peer.free()
	naval.free()
	ground.free()
	ally.free()
	friendly.free()
	host.free()


func _test_registry_and_body() -> void:
	var row := EnemyPoolRegistry.row_for_type(int(SurvivorSpawner.EnemyType.DEADAIR))
	var params := load("res://resources/enemy_deadair.tres") as AircraftParams
	_check("常规池数值固定为 response9/token4/budget10/cap1", not row.is_empty()
		and int(row["unlock"]) == 9 and int(row["token_cost"]) == 4
		and int(row["spawn_budget_cost"]) == 10 and int(row["instance_cap"]) == 1, str(row))
	_check("纯支援机体通过敌版审计", EnemyPoolRegistry.audit_enemy_params(row, params).is_empty(),
		str(EnemyPoolRegistry.audit_enemy_params(row, params)))


func _test_support_field_mutual_exclusion() -> void:
	var spawner := SurvivorSpawner.new()
	spawner._token_count_by_type[int(SurvivorSpawner.EnemyType.SNOWBLIND)] = 1
	_check("Snowblind 在场时禁止生成 DEADAIR", not spawner._can_spawn_type(
		int(SurvivorSpawner.EnemyType.DEADAIR), 99), "")
	spawner._token_count_by_type.clear()
	spawner._token_count_by_type[int(SurvivorSpawner.EnemyType.DEADAIR)] = 1
	_check("DEADAIR 在场时禁止生成 Snowblind", not spawner._can_spawn_type(
		int(SurvivorSpawner.EnemyType.SNOWBLIND), 99), "")
	spawner.free()


func _test_tier3_priority_replacement() -> void:
	var old_host := Aircraft.new()
	old_host.global_position = Vector2(100.0, 0.0)
	var tier3_host := Aircraft.new()
	tier3_host.global_position = Vector2(900.0, 0.0)
	var controller := DeadairController.new(null)
	controller.register(old_host)
	controller.replace_with_priority(tier3_host)
	var snapshot := controller.field_snapshot()
	_check("3★ DEADAIR 优先接管唯一干扰场且旧来源不会复活",
		bool(old_host.get_meta(&"support_field_retired", false)) \
			and snapshot.get("position", Vector2.ZERO) == tier3_host.global_position, str(snapshot))
	controller.shutdown()
	old_host.free()
	tier3_host.free()


func _test_i18n_resources() -> void:
	var ok := true
	var detail := ""
	for locale in ["zh", "en", "ja"]:
		var translation := load("res://i18n/meta.%s.translation" % locale) as Translation
		var name_text := str(translation.get_message("CODEX_DEADAIR_NAME")) if translation else ""
		var desc_text := str(translation.get_message("CODEX_DEADAIR_DESC")) if translation else ""
		if name_text.is_empty() or desc_text.is_empty():
			ok = false
			detail += "%s missing; " % locale
	_check("图鉴名称与说明已写入中英日 Translation 资源", ok, detail)


func _test_automation_audio_gate() -> void:
	var master_bus_idx := AudioServer.get_bus_index("Master")
	_check("所有 --bench 运行时静音 Master 总线",
		master_bus_idx >= 0 and AudioServer.is_bus_mute(master_bus_idx), "")


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])
