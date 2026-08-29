extends RefCounted

const EnemyPoolRegistry = preload("res://scripts/survivor/enemy_pool_registry.gd")
const F22Multilock = preload("res://scripts/survivor/f22_multilock.gd")
const SchemerMultilock = preload("res://scripts/survivor/schemer_multilock.gd")
const SnowblindController = preload("res://scripts/survivor/snowblind_controller.gd")
const SnowblindShroudVisual = preload("res://scripts/survivor/snowblind_shroud_visual.gd")

class SentinelWatchdogProbe extends SurvivorSpawner:
	var spawned_escort_count := 0

	func _spawn_sentinel_escort_uavs(_commander: Aircraft, _sq: Squad, count: int) -> void:
		spawned_escort_count += count


class SpawnPickProbe extends SurvivorSpawner:
	var probe_response := 9
	var probe_budget := 0

	func get_response_level() -> int:
		return probe_response

	func _get_token_budget() -> int:
		return probe_budget


class MultilockModeProbe extends RefCounted:
	var game_time: float = 20.0


class MultilockSpawnerProbe extends RefCounted:
	var mode := MultilockModeProbe.new()
	var player_aircraft: Aircraft = null

	func _get_ai(_aircraft: Aircraft):
		return null

## 无头行为验收：刷怪池配置（2026-07-28 平衡批）
##
## A 敌人高度分档表（按机型定位分化，不再全员均匀随机）
## B BOSS 专属机型不得从常规刷怪通道漏出
## C AF-03 可见性（旅途池门槛 + 战区池在册）
## D 机体专属技能普通池排除
## E ADBS 护卫零 Token 选型与退役门
## F 全部 57 型敌机的常规池/专用入口覆盖
## G 常规池数学可达性与五响应截面产出率
##
## 运行：godot --headless --path . -- --bench=spawn_pool（或 --bench=all）

var _pass := 0
var _fail := 0

## 抽样次数：够大以让"从不出现某档"的断言稳定，又不至于拖慢回归门
const SAMPLES := 3000
const POOL_RATE_SAMPLES := 30000
const POOL_RATE_LEVELS: Array[int] = [1, 4, 7, 10, 13]
const FIRE_SAFE_TEST_DELTA: float = 0.20

## 不进常规池的 14 型必须有明确专用入口；这里同时钉住资源、工厂映射和入口源码。
const DEDICATED_ENEMY_ROUTES: Array[Dictionary] = [
	{"type": 12, "id": "tu160", "resource": "res://resources/enemy_tu160.tres",
		"route": "res://scripts/survivor/survivor_spawner.gd", "route_token": "_create_enemy(EnemyType.TU160"},
	{"type": 13, "id": "ah64", "resource": "res://resources/enemy_ah64.tres",
		"route": "res://scripts/survivor/survivor_spawner.gd", "route_token": "_create_enemy(EnemyType.AH64"},
	{"type": 14, "id": "ch47", "resource": "res://resources/enemy_ch47.tres",
		"route": "res://scripts/survivor/survivor_spawner.gd", "route_token": "_create_enemy(EnemyType.CH47"},
	{"type": 15, "id": "f47", "resource": "res://resources/enemy_f47.tres",
		"route": "res://scripts/survivor/f47_ace_squad.gd", "route_token": "enemy_type = 15"},
	{"type": 16, "id": "f14_poltergeist", "resource": "res://resources/enemy_f14_poltergeist.tres",
		"route": "res://scripts/survivor/poltergeist_squad.gd", "route_token": "EnemyType.F14_POLTERGEIST"},
	{"type": 18, "id": "uav_laser", "resource": "res://resources/enemy_uav_laser.tres",
		"route": "res://scripts/survivor/survivor_spawner.gd", "route_token": "_create_enemy(EnemyType.UAV_LASER"},
	{"type": 22, "id": "fa18", "resource": "res://resources/enemy_fa18.tres",
		"route": "res://scripts/survivor/carrier_strike_group.gd", "route_token": "EnemyType.FA18"},
	{"type": 24, "id": "f15", "resource": "res://resources/enemy_f15.tres",
		"route": "res://scripts/survivor/ace_squad_profiles.gd", "route_token": "EnemyType.F15"},
	{"type": 25, "id": "f16", "resource": "res://resources/enemy_f16.tres",
		"route": "res://scripts/survivor/ace_squad_profiles.gd", "route_token": "EnemyType.F16"},
	{"type": 26, "id": "mirage2000", "resource": "res://resources/enemy_mirage2000.tres",
		"route": "res://scripts/survivor/ace_squad_profiles.gd", "route_token": "EnemyType.MIRAGE2000"},
	{"type": 27, "id": "su47", "resource": "res://resources/enemy_su47.tres",
		"route": "res://scripts/survivor/ace_squad_profiles.gd", "route_token": "EnemyType.SU47"},
	{"type": 28, "id": "cre", "resource": "res://resources/enemy_cre.tres",
		"route": "res://scripts/events/orion_nemesis_event.gd", "route_token": "EnemyType.CRE"},
	{"type": 29, "id": "yf23", "resource": "res://resources/enemy_yf23.tres",
		"route": "res://scripts/survivor/f47_ace_squad.gd", "route_token": "EnemyType.YF23"},
	{"type": 55, "id": "fck1", "resource": "res://resources/enemy_fck1.tres",
		"route": "res://scripts/survivor/ace_squad_profiles.gd", "route_token": "EnemyType.FCK1"},
]


func run() -> void:
	print("\n════════ 刷怪池配置（常规池 / ADBS 护卫 / 高度 / BOSS 隔离） ════════")
	_test_altitude_table_shape()
	_test_altitude_role_bias()
	_test_patrol_altitude_bands()
	_test_boss_only_isolation()
	_test_af03_visibility()
	_test_signature_random_exclusion()
	_test_regular_enemy_registry()
	_test_multilock_freed_reference_safety()
	_test_enemy_type_route_coverage()
	_test_regular_pool_reachability_and_rates()
	_test_adbs_escort_pool()
	_test_sentinel_escort_cohesion()
	_test_debug_near_spawn()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 高度权重表结构 ──
func _test_altitude_table_shape() -> void:
	print("── A. 高度权重表：三档权重齐全 / 非负 / 总和 > 0 ──")
	var shape_ok := true
	var detail := ""
	for etype in SurvivorData.ENEMY_ALTITUDE_WEIGHTS:
		var w: Array = SurvivorData.ENEMY_ALTITUDE_WEIGHTS[etype]
		if w.size() != 3:
			shape_ok = false
			detail += "type%d 档数≠3; " % int(etype)
			continue
		var total := 0.0
		for v in w:
			if float(v) < 0.0:
				shape_ok = false
				detail += "type%d 负权重; " % int(etype)
			total += float(v)
		if total <= 0.0:
			shape_ok = false
			detail += "type%d 总权重=0; " % int(etype)
	_check("全部登记类型三档权重合法", shape_ok, detail)
	# 未登记类型：回退均匀随机（不崩、值域合法）
	var fallback_ok := true
	for i in 200:
		var t: int = SurvivorData.pick_altitude_tier(9999)
		if t < 0 or t > 2:
			fallback_ok = false
			break
	_check("未登记类型回退均匀随机且值域合法", fallback_ok, "")


# ── B. 定位偏好：截击机偏高空 / 攻击机偏低空 / 多用途偏中空 ──
func _test_altitude_role_bias() -> void:
	print("── B. 定位偏好：MiG-31/F-104 高空 · A-7/Q-5 低空 · MiG-29 中空 ──")
	# 高空截击：MiG-31(6) / F-104(20) 权重表里 LOW = 0 → 永不落 LOW
	for pair in [[6, "MiG-31"], [20, "F-104"]]:
		var etype: int = int(pair[0])
		var nm: String = str(pair[1])
		var counts := _sample_tiers(etype)
		_check("%s 从不刷在低空档" % nm, counts[0] == 0, "LOW=%d" % counts[0])
		_check("%s 高空档占多数" % nm, counts[2] > counts[0] + counts[1],
			"L/M/H=%d/%d/%d" % counts)
	# 贴地攻击：A-7(10) / Q-5(11) 权重表里 HIGH = 0 → 永不落 HIGH
	for pair in [[10, "A-7"], [11, "Q-5"]]:
		var etype: int = int(pair[0])
		var nm: String = str(pair[1])
		var counts := _sample_tiers(etype)
		_check("%s 从不刷在高空档" % nm, counts[2] == 0, "HIGH=%d" % counts[2])
		_check("%s 低空档占多数" % nm, counts[0] > counts[1] + counts[2],
			"L/M/H=%d/%d/%d" % counts)
	# AF-03(17)：电磁炮狙击手要高度取射界
	var af := _sample_tiers(17)
	_check("AF-03 从不刷在低空档", af[0] == 0, "LOW=%d" % af[0])
	_check("AF-03 高空档占多数", af[2] > af[0] + af[1], "L/M/H=%d/%d/%d" % af)
	# 多用途 MiG-29(2)：三档都有，中空最多
	var mig := _sample_tiers(2)
	_check("MiG-29 三档都会出现", mig[0] > 0 and mig[1] > 0 and mig[2] > 0,
		"L/M/H=%d/%d/%d" % mig)
	_check("MiG-29 中空档最多", mig[1] > mig[0] and mig[1] > mig[2],
		"L/M/H=%d/%d/%d" % mig)


## 抽 SAMPLES 次，返回 [LOW 次数, MID 次数, HIGH 次数]
func _sample_tiers(etype: int) -> Array:
	var counts := [0, 0, 0]
	for i in SAMPLES:
		counts[SurvivorData.pick_altitude_tier(etype)] += 1
	return counts


# ── C. 档位 → 作战偏好高度区间 ──
func _test_patrol_altitude_bands() -> void:
	print("── C. patrol_altitude 跟随档位（战术层交战高度不再被拉回中空）──")
	var bands := [[1500.0, 3000.0], [4500.0, 6500.0], [8500.0, 11000.0]]
	for tier in 3:
		var lo: float = float(bands[tier][0])
		var hi: float = float(bands[tier][1])
		var in_range := true
		for i in 200:
			var a: float = SurvivorData.patrol_altitude_for_tier(tier)
			if a < lo or a > hi:
				in_range = false
				break
		_check("档位 %d 的 patrol_altitude ∈ [%.0f, %.0f]" % [tier, lo, hi], in_range, "")
	# 越界档位夹紧，不崩
	var clamp_ok: bool = SurvivorData.patrol_altitude_for_tier(-5) >= 1500.0 \
		and SurvivorData.patrol_altitude_for_tier(99) <= 11000.0
	_check("越界档位被夹紧", clamp_ok, "")
	# 三档区间互不重叠 —— 重叠了"高空敌机"就不再是高空敌机
	_check("三档区间互不重叠", bands[0][1] < bands[1][0] and bands[1][1] < bands[2][0], "")


# ── D. BOSS 专属机型隔离 ──
func _test_boss_only_isolation() -> void:
	print("── D. BOSS 专属机型：不在战区池 / 后期随机桶显式排除 ──")
	_check("BOSS_ONLY_TYPES 含 F-47(15) 与 F-14 Poltergeist(16)",
		SurvivorData.BOSS_ONLY_TYPES.has(15) and SurvivorData.BOSS_ONLY_TYPES.has(16),
		str(SurvivorData.BOSS_ONLY_TYPES))
	# 它们的 cost ≥ LATE_GAME_MIN_TOKEN，所以**只能**靠黑名单挡住 ——
	# 这条断言就是在钉死"别再退回用 cost 数值偶然过滤"
	var by_cost_would_leak := true
	for t in [15, 16]:
		if int(SurvivorData.TOKEN_COST.get(t, 0)) < SurvivorData.LATE_GAME_MIN_TOKEN:
			by_cost_would_leak = false
	_check("光靠 cost 门槛挡不住它们（故黑名单不可删）", by_cost_would_leak, "")
	# 战区池同样不得含 BOSS 机型
	var zone_clean := true
	var leaked := ""
	for row_any in SurvivorData.ZONE_ENEMY_TABLE:
		var row: Dictionary = row_any
		if SurvivorData.BOSS_ONLY_TYPES.has(int(row["type"])):
			zone_clean = false
			leaked += "type%d " % int(row["type"])
	_check("战区池不含 BOSS 专属机型", zone_clean, leaked)


# ── E. AF-03 可见性 ──
func _test_af03_visibility() -> void:
	print("── E. AF-03：旅途池门槛下调 + 战区池在册（原配置整局遇不到）──")
	_check("解锁等级 = 7", SurvivorData.AF03_UNLOCK_LEVEL == 7,
		"got %d" % SurvivorData.AF03_UNLOCK_LEVEL)
	_check("概率上限 = 0.26", is_equal_approx(SurvivorData.AF03_CHANCE_MAX, 0.26),
		"got %.2f" % SurvivorData.AF03_CHANCE_MAX)
	# 上限必须够得着：解锁后要能在合理等级内爬到 CHANCE_MAX
	var lv_to_max: float = SurvivorData.AF03_CHANCE_MAX / SurvivorData.AF03_CHANCE_PER_LEVEL
	_check("概率能在 6 级内爬满上限", lv_to_max <= 6.0, "需 %.1f 级" % lv_to_max)
	# 战区池在册
	var in_zone_pool := false
	var zone_row: Dictionary = {}
	for row_any in SurvivorData.ZONE_ENEMY_TABLE:
		var row: Dictionary = row_any
		if int(row["type"]) == 17:
			in_zone_pool = true
			zone_row = row
	_check("AF-03 已进战区池", in_zone_pool, "")
	if in_zone_pool:
		_check("战区池 AF-03 不淘汰（retire = -1）", int(zone_row["retire"]) == -1,
			str(zone_row))
		# 精英定位：权重不得高于主力机（MiG-29 0.9）
		_check("战区池权重保持精英稀有度（≤ 0.6）",
			float(zone_row["base_weight"]) <= 0.6, str(zone_row))
	# 实例上限仍为 1 —— 抬出场率不等于放开同时在场数
	_check("同时在场上限仍为 1", int(SurvivorData.TOKEN_INSTANCE_CAP.get(17, -1)) == 1,
		"got %s" % str(SurvivorData.TOKEN_INSTANCE_CAP.get(17, -1)))


# ── F. 签名技普通池排除 ──
func _test_signature_random_exclusion() -> void:
	print("── F. 普通升级池：专属/次世代排除（专属只走机场二选一）──")
	_check("is_signature_upgrade 认 sig_ 前缀",
		SurvivorData.is_signature_upgrade({"id": "sig_f15"}), "")
	_check("is_signature_upgrade 认 F-14 围猎特例",
		SurvivorData.is_signature_upgrade({"id": "f14_squad_lock_slow"}), "")
	_check("is_signature_upgrade 不误伤普通技",
		not SurvivorData.is_signature_upgrade({"id": "gun_damage"}), "")
	_check("is_signature_upgrade 容忍缺 id 字段",
		not SurvivorData.is_signature_upgrade({}), "")
	_check("sig_* 不进普通随机池",
		not SurvivorData.is_normal_random_candidate({"id": "sig_f15"}), "")
	_check("F-14 围猎不进普通随机池",
		not SurvivorData.is_normal_random_candidate({"id": "f14_squad_lock_slow"}), "")
	_check("普通金卡仍进池、次世代红卡不进池",
		SurvivorData.is_normal_random_candidate({"id": "gold", "rarity": SurvivorData.Rarity.CLASSIFIED})
		and not SurvivorData.is_normal_random_candidate({"id": "red", "rarity": SurvivorData.Rarity.NEXT_GEN}), "")


# ── G. 常规敌机数据注册表 ──
func _test_regular_enemy_registry() -> void:
	print("── G. 常规敌机注册表：原型/角色/过滤/三队防重复 ──")
	var ids: Dictionary = {}
	var types: Dictionary = {}
	var rows_valid := true
	var detail := ""
	for row in EnemyPoolRegistry.ROWS:
		var id: String = str(row["id"])
		var type_idx: int = int(row["type"])
		if ids.has(id) or types.has(type_idx):
			rows_valid = false
			detail += "duplicate=%s/%d " % [id, type_idx]
		ids[id] = true
		types[type_idx] = true
		if str(row["archetype"]) not in EnemyPoolRegistry.ARCHETYPES \
				or str(row["role"]) not in EnemyPoolRegistry.ROLES:
			rows_valid = false
			detail += "invalid=%s " % id
		if SurvivorData.BOSS_ONLY_TYPES.has(type_idx):
			rows_valid = false
			detail += "boss_leak=%s " % id
		if int(row["token_cost"]) != int(SurvivorData.TOKEN_COST.get(type_idx, -999)):
			rows_valid = false
			detail += "token_mismatch=%s " % id
	_check("注册行 id/type 唯一，原型角色合法，BOSS 隔离，Token 对拍", rows_valid, detail)

	for level in [1, 5, 10]:
		var total := 0.0
		for weight in EnemyPoolRegistry.role_weights(level).values():
			total += float(weight)
		_check("响应等级 %d 角色权重归一" % level, is_equal_approx(total, 1.0), "sum=%.3f" % total)

	var lv1: Array[Dictionary] = EnemyPoolRegistry.eligible_rows(1, 99, {})
	var lv1_types: Array[int] = []
	for row in lv1:
		lv1_types.append(int(row["type"]))
	_check("Lv1 只解锁 UAV/UCAV/F-4E", lv1_types.size() == 3 \
		and lv1_types.has(0) and lv1_types.has(1) and lv1_types.has(23), str(lv1_types))
	var lv5: Array[Dictionary] = EnemyPoolRegistry.eligible_rows(5, 99, {})
	var lv5_types: Array[int] = []
	for row in lv5:
		lv5_types.append(int(row["type"]))
	_check("Lv5 淘汰早期 UAV/UCAV", not lv5_types.has(0) and not lv5_types.has(1), str(lv5_types))
	_check("预算过滤高成本机", EnemyPoolRegistry.eligible_rows(20, 0, {}).is_empty(), "")
	_check("实例上限过滤 Sentinel", EnemyPoolRegistry.row_for_type(4) not in \
		EnemyPoolRegistry.eligible_rows(10, 99, {4: 1}), "")

	var same_role: Array[Dictionary] = [EnemyPoolRegistry.row_for_type(7), EnemyPoolRegistry.row_for_type(2)]
	var picked: Dictionary = EnemyPoolRegistry.pick_row(same_role, 10, [7], 0.5, 0.0)
	_check("最近三支同型在有替代时被排除", int(picked.get("type", -1)) == 2, str(picked))

	var audited: AircraftParams = load("res://resources/enemy_su35.tres").duplicate(true)
	audited.flare = audited.flare.duplicate()
	audited.flare.max_flares = 1
	audited.flare.burst_count = 1
	audited.flare.fail_chance = 0.10
	var audit_errors: Array[String] = EnemyPoolRegistry.audit_enemy_params(
		EnemyPoolRegistry.row_for_type(21), audited)
	_check("Su-35 普通敌机走廊样本通过审计", audit_errors.is_empty(), str(audit_errors))
	audited.radar_range = 6000.0
	_check("未特批 6000px 雷达被审计拒绝",
		not EnemyPoolRegistry.audit_enemy_params(EnemyPoolRegistry.row_for_type(21), audited).is_empty(), "")

	var f22: AircraftParams = load("res://resources/enemy_f22.tres")
	var f22_errors: Array[String] = EnemyPoolRegistry.audit_enemy_params(
		EnemyPoolRegistry.row_for_type(30), f22)
	_check("F-22 敌版参数走廊与资源依赖审计通过", f22_errors.is_empty(), str(f22_errors))
	_check("F-22 无机炮且只有一枚不补充热诱弹",
		f22.gun == null and f22.flare.max_flares == 1 and f22.flare.burst_count == 1, "")
	var solo_alloc: Array = F22Multilock.allocate_unique_targets([
		[true, true, true, true, true, true, true, true, true]], 9)
	_check("单架 F-22 每轮最多四个不同目标", solo_alloc[0].size() == 4, str(solo_alloc))
	var squad_alloc: Array = F22Multilock.allocate_unique_targets([
		[true, true, true, true, true, true, true, true, true],
		[true, true, true, true, true, true, true, true, true],
		[true, true, true, true, true, true, true, true, true]], 9)
	var allocated_ids: Dictionary = {}
	var allocated_total := 0
	for member_targets in squad_alloc:
		for target_idx in member_targets:
			allocated_ids[int(target_idx)] = true
			allocated_total += 1
	_check("三架 F-22 对九机分配九个且不重复", allocated_total == 9 and allocated_ids.size() == 9, str(squad_alloc))
	var single_target_alloc: Array = F22Multilock.allocate_unique_targets([[true], [true], [true]], 1)
	var single_target_shots := 0
	for member_targets in single_target_alloc:
		single_target_shots += member_targets.size()
	_check("三架 F-22 对单机每轮仍只分配一锁", single_target_shots == 1, str(single_target_alloc))
	var f22_source := FileAccess.get_file_as_string("res://scripts/survivor/f22_multilock.gd")
	_check("F-22 控制器按生成登记且不做 5Hz 场景子节点全扫",
		f22_source.contains("func register(aircraft: Aircraft)") \
			and not f22_source.contains("spawner.mode.get_children()"), "")

	var snowblind_row := EnemyPoolRegistry.row_for_type(31)
	_check("Snowblind 本体 4 Token，Lv8 解锁且 10 Token 才允许最低完整编成",
		int(snowblind_row["token_cost"]) == 4 \
			and snowblind_row in EnemyPoolRegistry.eligible_rows(8, 10, {}) \
			and snowblind_row not in EnemyPoolRegistry.eligible_rows(7, 99, {}) \
			and snowblind_row not in EnemyPoolRegistry.eligible_rows(8, 9, {}), "")
	_check("Snowblind 同场上限一架",
		snowblind_row not in EnemyPoolRegistry.eligible_rows(20, 99, {31: 1}), "")
	var snowblind: AircraftParams = load("res://resources/enemy_snowblind.tres")
	var snowblind_errors := EnemyPoolRegistry.audit_enemy_params(snowblind_row, snowblind)
	_check("Snowblind 精确复用 Sentinel 支援机体且无武器/热诱弹",
		snowblind_errors.is_empty(), str(snowblind_errors))

	var state := SnowblindController.next_reveal_state(false, true, false, 0.0, 0.0, 0.2)
	_check("玩家进入 4000m 幕立即揭露", bool(state["revealed"]), str(state))
	state = SnowblindController.next_reveal_state(true, true, false, 2.8, 0.0, 0.2)
	state = SnowblindController.next_reveal_state(true, false, true,
		float(state["reveal_elapsed"]), 1.8, 0.2)
	_check("已揭露满 3s 且离开 4500m 满 2s 后重新隐蔽", not bool(state["revealed"]), str(state))
	state = SnowblindController.next_reveal_state(true, false, true, 1.0, 1.8, 0.2)
	_check("离场满 2s 但最低揭露时间未满仍保持可见", bool(state["revealed"]), str(state))

	var outside := CombatUnit.new()
	var inside := CombatUnit.new()
	inside.sensor_shroud_id = 42
	inside.sensor_hidden = true
	_check("未揭露幕阻断跨边界交战但不改变阵营/物理对象",
		outside.is_sensor_engagement_obscured(inside) \
			and inside.is_sensor_engagement_obscured(outside), "")
	inside.sensor_shroud_id = 0
	inside.sensor_hidden = false
	_check("揭露后跨边界门立即解除", not outside.is_sensor_engagement_obscured(inside), "")
	outside.free()
	inside.free()
	var visual_instance = SnowblindShroudVisual.new()
	var visual_methods: Array = visual_instance.get_script().get_script_method_list()
	var visual_method_names: Array[String] = []
	for method in visual_methods:
		visual_method_names.append(str(method["name"]))
	_check("Snowblind 雪花圈无 _process/_physics_process/_draw",
		not visual_method_names.has("_process") and not visual_method_names.has("_physics_process") \
			and not visual_method_names.has("_draw"), str(visual_method_names))
	_check("Snowblind 雪幕半径削弱为 4000m 且保留 500m 复隐滞回",
		is_equal_approx(SnowblindController.RADIUS_PX, 2000.0) \
			and is_equal_approx(SnowblindController.EXIT_RADIUS_PX, 2250.0) \
			and is_equal_approx(SnowblindShroudVisual.RADIUS_PX, 2000.0), "")
	var snowblind_controller_source := FileAccess.get_file_as_string(
		"res://scripts/survivor/snowblind_controller.gd")
	_check("Snowblind 本体仍由雪幕隐藏，圆心只显示不可交互 shader 轮廓",
		snowblind_controller_source.contains("if ac == host:") \
			and SnowblindShroudVisual.SHADER_CODE.contains("core_outline"), "")
	var spawner_source := FileAccess.get_file_as_string("res://scripts/survivor/survivor_spawner.gd")
	_check("Snowblind 创建当帧主动登记且编成后立即刷新，不依赖 Token 重算",
		spawner_source.contains("_snowblind_controller.register(enemy)") \
			and spawner_source.contains("_snowblind_controller.refresh_now()") \
			and spawner_source.contains("_snowblind_controller.tick(delta)"), "")
	_check("Snowblind 未破幕为实体高遮蔽层，破幕后才降为低透明度",
		SnowblindShroudVisual.SHADER_CODE.contains("solid_alpha = 1.0") \
			and SnowblindShroudVisual.SHADER_CODE.contains("uniform float concealment"), "")
	_check("Snowblind 进出圈视觉共用 0.8s 缓入缓出且不拖延玩法显隐",
		is_equal_approx(SnowblindShroudVisual.TRANSITION_S, 0.8) \
			and visual_method_names.has("set_concealed") \
			and snowblind_controller_source.contains("SnowblindShroudVisual.set_concealed"),
			str(visual_method_names))
	var visual_host := Aircraft.new()
	var shroud := SnowblindShroudVisual.attach(visual_host)
	_check("Snowblind 雪幕固定在飞机下层且不继承宿主 Z，玩家入圈后机体仍可读",
		shroud.z_index == SnowblindShroudVisual.WORLD_Z_INDEX \
			and not shroud.z_as_relative \
			and shroud.z_index < 0 \
			and shroud.z_index > -10, str({"z": shroud.z_index,
				"relative": shroud.z_as_relative}))
	visual_host.free()

	var batch_a_ok := true
	var batch_a_detail := ""
	for type_idx in range(32, 40):
		var row := EnemyPoolRegistry.row_for_type(type_idx)
		var params: AircraftParams = load(str(row.get("resource_path", "")))
		var errors := EnemyPoolRegistry.audit_enemy_params(row, params)
		if not errors.is_empty():
			batch_a_ok = false
			batch_a_detail += "%s=%s; " % [row.get("id", type_idx), errors]
	_check("批 A 八架敌版全部通过 Token 参数走廊与 player 依赖审计", batch_a_ok, batch_a_detail)
	var batch_b_ok := true
	var batch_b_detail := ""
	for type_idx in range(40, 49):
		var row := EnemyPoolRegistry.row_for_type(type_idx)
		var params: AircraftParams = load(str(row.get("resource_path", "")))
		var errors := EnemyPoolRegistry.audit_enemy_params(row, params)
		if not errors.is_empty():
			batch_b_ok = false
			batch_b_detail += "%s=%s; " % [row.get("id", type_idx), errors]
	_check("批 B 九架敌版全部通过 Token 参数走廊与 player 依赖审计", batch_b_ok, batch_b_detail)
	_check("Gripen C 多锁为队级 3 且每机 1；Rafale 为单机 2",
		EnemyPoolRegistry.row_for_type(42).get("multilock_mode") == "team3" \
			and int(EnemyPoolRegistry.row_for_type(42).get("lock_count")) == 1 \
			and EnemyPoolRegistry.row_for_type(43).get("multilock_mode") == "per2" \
			and int(EnemyPoolRegistry.row_for_type(43).get("lock_count")) == 2, "")
	var batch_c_ok := true
	var batch_c_detail := ""
	for type_idx in range(49, 55):
		var row := EnemyPoolRegistry.row_for_type(type_idx)
		var params: AircraftParams = load(str(row.get("resource_path", "")))
		var errors := EnemyPoolRegistry.audit_enemy_params(row, params)
		if not errors.is_empty():
			batch_c_ok = false
			batch_c_detail += "%s=%s; " % [row.get("id", type_idx), errors]
	_check("批 C 余下六架敌版全部通过 Token 参数走廊与 player 依赖审计", batch_c_ok, batch_c_detail)

	var tech_types := [9, 6, 21, 32, 33, 34, 35, 36, 37, 38, 39,
		40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 30, 52, 53, 54]
	var archetype_counts := {"Gladiator": 0, "Lancer": 0, "Schemer": 0}
	var tech_ids: Dictionary = {}
	for type_idx in tech_types:
		var row := EnemyPoolRegistry.row_for_type(type_idx)
		tech_ids[str(row.get("id", ""))] = true
		var archetype := str(row.get("archetype", ""))
		archetype_counts[archetype] = int(archetype_counts.get(archetype, 0)) + 1
	_check("T1–T3 科技树 27 架全部有唯一常规敌版 profile",
		tech_types.size() == 27 and tech_ids.size() == 27, str(tech_ids.keys()))
	_check("27 架互斥原型统计为 Gladiator12/Lancer9/Schemer6",
		int(archetype_counts["Gladiator"]) == 12 and int(archetype_counts["Lancer"]) == 9 \
			and int(archetype_counts["Schemer"]) == 6, str(archetype_counts))
	_check("F-35 双锁、Gripen E 队级三锁；Su-57/F-15SMTD 挂后失速身份",
		EnemyPoolRegistry.row_for_type(50).get("multilock_mode") == "per2" \
			and EnemyPoolRegistry.row_for_type(51).get("multilock_mode") == "team3" \
			and bool(EnemyPoolRegistry.row_for_type(52).get("post_stall")) \
			and bool(EnemyPoolRegistry.row_for_type(49).get("post_stall")), "")


func _test_multilock_freed_reference_safety() -> void:
	print("── 多锁控制器：已释放登记机 / 齐射目标生命周期安全 ──")
	var spawner := MultilockSpawnerProbe.new()

	var schemer := SchemerMultilock.new(spawner)
	var freed_schemer := Aircraft.new()
	schemer.register(freed_schemer, "per2")
	freed_schemer.free()
	schemer._prune_and_restore()
	_check("Schemer 登记表跳过已释放飞机", not schemer.has_units(), "")
	var live_schemer := Aircraft.new()
	var freed_schemer_target := CombatUnit.new()
	schemer._queues[live_schemer] = [freed_schemer_target]
	schemer._fire_timers[live_schemer] = 0.0
	freed_schemer_target.free()
	schemer._update_queues(FIRE_SAFE_TEST_DELTA)
	_check("Schemer 齐射队列跳过已释放目标", not schemer._queues.has(live_schemer), "")
	live_schemer.free()
	schemer.shutdown()

	var f22 := F22Multilock.new(spawner)
	var freed_f22 := Aircraft.new()
	f22.register(freed_f22)
	freed_f22.free()
	f22._logic_step()
	_check("F-22 登记表跳过已释放飞机", f22._units.is_empty(), "")
	var live_f22 := Aircraft.new()
	var freed_f22_target := CombatUnit.new()
	var f22_queues: Dictionary = {}
	var f22_timers: Dictionary = {}
	f22_queues[live_f22] = [freed_f22_target]
	f22_timers[live_f22] = 0.0
	f22._group_states[1] = {
		"phase": "execute",
		"until": 0.0,
		"queues": f22_queues,
		"timers": f22_timers,
		"members": [live_f22],
	}
	freed_f22_target.free()
	f22._update_execution(FIRE_SAFE_TEST_DELTA)
	var f22_state: Dictionary = f22._group_states[1]
	_check("F-22 齐射队列跳过已释放目标",
		str(f22_state.get("phase", "")) == "egress", "")
	live_f22.free()
	f22.shutdown()


# ── H. 全机型产出路径：常规池 43 型 + 专用入口 14 型 ──
func _test_enemy_type_route_coverage() -> void:
	print("── H. 全机型路径：常规池资源/工厂 + 专用事件入口 ──")
	var covered: Dictionary = {}
	var regular_ok := true
	var regular_detail := ""
	var spawner_source := FileAccess.get_file_as_string("res://scripts/survivor/survivor_spawner.gd")
	for row in EnemyPoolRegistry.ROWS:
		var type_idx := int(row["type"])
		var resource_path := _regular_resource_path(row)
		var params := load(resource_path) as AircraftParams
		var enum_name := str(SurvivorSpawner.EnemyType.keys()[type_idx])
		if covered.has(type_idx) or params == null or not spawner_source.contains(resource_path):
			regular_ok = false
			regular_detail += "%s(res=%s,preload=%s); " % [
				row["id"], str(params != null), str(spawner_source.contains(resource_path))]
		# UAV 是工厂默认基底；其它类型必须在显式 match 或注册表预加载中留有枚举映射。
		if type_idx != int(SurvivorSpawner.EnemyType.UAV) \
				and not spawner_source.contains("EnemyType.%s" % enum_name):
			regular_ok = false
			regular_detail += "%s(factory); " % row["id"]
		covered[type_idx] = "regular"
	_check("43 型常规池均有可加载敌版资源且接入 Spawner 工厂", regular_ok, regular_detail)

	var dedicated_ok := true
	var dedicated_detail := ""
	for route in DEDICATED_ENEMY_ROUTES:
		var type_idx := int(route["type"])
		var params := load(str(route["resource"])) as AircraftParams
		var route_source := FileAccess.get_file_as_string(str(route["route"]))
		var enum_name := str(SurvivorSpawner.EnemyType.keys()[type_idx])
		if covered.has(type_idx) or params == null \
				or not spawner_source.contains("EnemyType.%s" % enum_name) \
				or not route_source.contains(str(route["route_token"])):
			dedicated_ok = false
			dedicated_detail += "%s(res=%s,factory=%s,route=%s); " % [
				route["id"], str(params != null),
				str(spawner_source.contains("EnemyType.%s" % enum_name)),
				str(route_source.contains(str(route["route_token"])))]
		covered[type_idx] = "dedicated"
	_check("14 型专用敌机均有资源、工厂映射与实际事件/BOSS/王牌入口",
		dedicated_ok, dedicated_detail)
	_check("EnemyType 57 型无遗漏且常规/专用分类互斥",
		covered.size() == SurvivorSpawner.EnemyType.size(),
		"covered=%d enum=%d" % [covered.size(), SurvivorSpawner.EnemyType.size()])


## 常规池旧类型没有 resource_path 字段；文件名仅有四个历史特例。
func _regular_resource_path(row: Dictionary) -> String:
	if row.has("resource_path"):
		return str(row["resource_path"])
	match int(row["type"]):
		SurvivorSpawner.EnemyType.UAV:
			return "res://resources/enemy_uav.tres"
		SurvivorSpawner.EnemyType.UCAV:
			return "res://resources/enemy_uav_missile.tres"
		SurvivorSpawner.EnemyType.MIG:
			return "res://resources/enemy_fighter.tres"
		SurvivorSpawner.EnemyType.UAV_COMMANDER:
			return "res://resources/enemy_uav_commander.tres"
		_:
			return "res://resources/enemy_%s.tres" % str(row["id"])


# ── I. 常规池可达性与真实防重复抽样率 ──
func _test_regular_pool_reachability_and_rates() -> void:
	print("── I. 常规池产出率：数学可达 + 最近三队防重复蒙特卡洛 ──")
	var reachable: Dictionary = {}
	var reach_detail := ""
	for row in EnemyPoolRegistry.ROWS:
		var level := int(row["unlock"])
		var candidates: Array[Dictionary] = EnemyPoolRegistry.eligible_rows(level, 1_000_000, {})
		var probability := float(_raw_selection_probabilities(candidates, level).get(int(row["type"]), 0.0))
		var rolls := _midpoint_rolls_for_row(candidates, level, row)
		var picked := EnemyPoolRegistry.pick_row(candidates, level, [], rolls.x, rolls.y)
		if probability > 0.0 and int(picked.get("type", -1)) == int(row["type"]):
			reachable[int(row["type"])] = true
		else:
			reach_detail += "%s(p=%.6f,picked=%s); " % [row["id"], probability, picked.get("id", "none")]
	_check("43 型常规敌机各自在解锁等级拥有非零概率且选型区间可命中",
		reachable.size() == EnemyPoolRegistry.ROWS.size(), reach_detail)

	var sampled_all: Dictionary = {}
	var sample_ok := true
	var sample_detail := ""
	for level in POOL_RATE_LEVELS:
		var candidates: Array[Dictionary] = EnemyPoolRegistry.eligible_rows(level, 1_000_000, {})
		var raw_rates := _raw_selection_probabilities(candidates, level)
		var hits: Dictionary = {}
		var recent: Array[int] = []
		var rng := RandomNumberGenerator.new()
		rng.seed = 0xA61 + level
		for i in POOL_RATE_SAMPLES:
			var picked := EnemyPoolRegistry.pick_row(candidates, level, recent, rng.randf(), rng.randf())
			var type_idx := int(picked.get("type", -1))
			hits[type_idx] = int(hits.get(type_idx, 0)) + 1
			sampled_all[type_idx] = true
			recent.append(type_idx)
			if recent.size() > 3:
				recent.pop_front()
		var rate_parts: Array[String] = []
		for row in candidates:
			var type_idx := int(row["type"])
			var sampled_rate := 100.0 * float(hits.get(type_idx, 0)) / POOL_RATE_SAMPLES
			var raw_rate := 100.0 * float(raw_rates.get(type_idx, 0.0))
			rate_parts.append("%s=%.2f/%.2f%%" % [row["id"], raw_rate, sampled_rate])
			if int(hits.get(type_idx, 0)) == 0:
				sample_ok = false
				sample_detail += "Lv%d:%s; " % [level, row["id"]]
		print("  · Lv%d 原始/防重复抽样：%s" % [level, ", ".join(rate_parts)])
	_check("五个响应截面中所有合格类型在 3 万次真实选型内均实际出现", sample_ok, sample_detail)
	_check("五个响应截面合计覆盖全部 43 型常规敌机",
		sampled_all.size() == EnemyPoolRegistry.ROWS.size(),
		"sampled=%d/%d" % [sampled_all.size(), EnemyPoolRegistry.ROWS.size()])


## 不考虑最近三队时的单次中队抽取率：P(role) × P(type | role)。
func _raw_selection_probabilities(candidates: Array[Dictionary], response_level: int) -> Dictionary:
	var result: Dictionary = {}
	var weights := EnemyPoolRegistry.role_weights(response_level)
	var role_totals: Dictionary = {}
	for row in candidates:
		var role := str(row["role"])
		role_totals[role] = float(role_totals.get(role, 0.0)) + float(row["weight"])
	var available_role_total := 0.0
	for role in role_totals:
		available_role_total += float(weights.get(role, 0.0))
	for row in candidates:
		var role := str(row["role"])
		var probability := float(weights.get(role, 0.0)) / available_role_total \
			* float(row["weight"]) / float(role_totals[role])
		result[int(row["type"])] = probability
	return result


## 取目标角色区间和目标机型区间的中点，直接证明 pick_row 存在能命中该行的骰值。
func _midpoint_rolls_for_row(candidates: Array[Dictionary], response_level: int,
		target: Dictionary) -> Vector2:
	var weights := EnemyPoolRegistry.role_weights(response_level)
	var roles: Array[String] = []
	for row in candidates:
		var role := str(row["role"])
		if role not in roles:
			roles.append(role)
	var role_total := 0.0
	var role_before := 0.0
	for role in roles:
		var weight := float(weights.get(role, 0.0))
		if role == str(target["role"]):
			role_before = role_total
		role_total += weight
	var type_total := 0.0
	var type_before := 0.0
	for row in candidates:
		if str(row["role"]) != str(target["role"]):
			continue
		if int(row["type"]) == int(target["type"]):
			type_before = type_total
		type_total += float(row["weight"])
	return Vector2(
		(role_before + float(weights[str(target["role"])]) * 0.5) / role_total,
		(type_before + float(target["weight"]) * 0.5) / type_total)


# ── J. ADBS 护卫池：不吃常规 Token，不穿透退役门 ──
func _test_adbs_escort_pool() -> void:
	print("── J. ADBS 护卫：零 Token 选型 / 近距伴飞 / 受警即接战 ──")
	var early_types: Array[int] = []
	for row in EnemyPoolRegistry.escort_rows(1):
		early_types.append(int(row["type"]))
	_check("响应 1 的护卫池保留 MQ-109/MQ-110/F-4E",
		early_types.has(0) and early_types.has(1) and early_types.has(23), str(early_types))

	var late_types: Array[int] = []
	for row in EnemyPoolRegistry.escort_rows(9):
		late_types.append(int(row["type"]))
	var forbidden := [0, 1, 4, 6, 9, 17, 31]
	var late_clean := true
	for type_idx in forbidden:
		if late_types.has(type_idx):
			late_clean = false
	_check("响应 9 不含退役 UAV、Sentinel、支援体或单机精英", late_clean, str(late_types))
	_check("响应 1/9/20 的零 Token 护卫池始终有合格战机",
		not EnemyPoolRegistry.escort_rows(1).is_empty() \
			and not EnemyPoolRegistry.escort_rows(9).is_empty() \
			and not EnemyPoolRegistry.escort_rows(20).is_empty(), "")

	var probe := SpawnPickProbe.new()
	_check("常规池预算为零时返回不刷，不再兜底 MQ-109", probe._pick_enemy_type() == -1, "")
	var escort_type := int(probe._pick_flee_escort_type())
	_check("同为零 Token 时 ADBS 护卫仍按等级选出非 MQ-109 战机",
		escort_type >= 0 and escort_type != int(SurvivorSpawner.EnemyType.UAV),
		"etype=%d" % escort_type)

	var protectee_a := _sentinel_probe_aircraft("ch47", Vector2.ZERO)
	var protectee_b := _sentinel_probe_aircraft("ch47", Vector2(0.0, 320.0))
	protectee_a.team = CombatUnit.TEAM_HOSTILE
	protectee_b.team = CombatUnit.TEAM_HOSTILE
	var protectees: Array[Aircraft] = [protectee_a, protectee_b]
	var escort_sq := probe._new_flee_escort_squad(protectees)
	var guard := _sentinel_probe_aircraft("tornado", Vector2.ZERO)
	guard.team = CombatUnit.TEAM_HOSTILE
	var guard_idx := SquadFactory.register_wingman(escort_sq, guard, true)
	var guard_ai := _sentinel_probe_ai(guard)
	_check("ADBS 护卫以运输机为移动长机，不再独自冲向出口",
		escort_sq.leader == protectee_a and escort_sq.members[1] == protectee_b \
			and guard_idx == 2 and guard_ai._state == AIController.AIState.SQUAD_FOLLOW,
		"leader=%s idx=%d state=%d" % [escort_sq.leader, guard_idx, guard_ai._state])
	_check("两运输机+首架护卫的楔形槽位距锚点小于 500m",
		escort_sq.get_formation_offset(guard_idx).length() \
			< 500.0 * CombatUnit.PIXELS_PER_METER,
		"slot_px=%.1f" % escort_sq.get_formation_offset(guard_idx).length())
	_check("三运输机+四护卫的最外槽位仍小于 700m",
		escort_sq.get_formation_offset(6).length() \
			< 700.0 * CombatUnit.PIXELS_PER_METER,
		"slot_px=%.1f" % escort_sq.get_formation_offset(6).length())

	var attacker := _sentinel_probe_aircraft("player", Vector2(1000.0, 0.0))
	attacker.team = CombatUnit.TEAM_PLAYER
	protectee_a.escort_guards = [guard]
	protectee_a.set_meta("_pending_attacker", attacker)
	guard.set_formation_target(protectee_a, escort_sq.get_wingman_target(guard_idx))
	protectee_a._alert_escort_guards()
	_check("护航对象受击时护卫同拍脱离编队并进入 ENGAGE",
		guard_ai._state == AIController.AIState.ENGAGE \
			and guard_ai._current_target == attacker and guard.combat_target == attacker \
			and not guard.formation_mode and guard.ai_override_pursuit,
		"state=%d formation=%s target=%s" % [
			guard_ai._state, guard.formation_mode, guard_ai._current_target])
	guard.kill_tally = 99  # 即使护卫已有战果，也不能抢走运输机的移动锚点。
	protectee_a.is_destroyed = true
	escort_sq.cleanup()
	_check("首架护航对象阵亡后优先换锚到下一架运输机",
		escort_sq.leader == protectee_b and guard_ai.squad_index == 1,
		"leader=%s guard_idx=%d" % [escort_sq.leader, guard_ai.squad_index])
	attacker.free()
	guard.free()
	protectee_a.free()
	protectee_b.free()
	probe.free()


# ── K. Sentinel 原生护卫凝聚 ──
func _test_sentinel_escort_cohesion() -> void:
	print("── K. Sentinel：原生护卫脱队召回 / hunter 豁免 ──")
	var watchdog := SentinelWatchdogProbe.new()
	var watchdog_mode := Node2D.new()
	watchdog.mode = watchdog_mode
	var solo := _sentinel_probe_aircraft("uav_commander", Vector2.ZERO)
	solo.team = CombatUnit.TEAM_HOSTILE
	var solo_sq := SquadFactory.create()
	SquadFactory.register_leader(solo_sq, solo)
	watchdog_mode.add_child(solo)
	watchdog._ensure_sentinels_escorted()
	watchdog._ensure_sentinels_escorted()
	_check("已有空 Squad 的 Sentinel 也补足 5 架，且只补一次",
		watchdog.spawned_escort_count == SurvivorSpawner.SENTINEL_MIN_ESCORT \
			and solo.has_meta("escort_watchdog_done"),
		"spawned=%d" % watchdog.spawned_escort_count)
	watchdog_mode.free()
	watchdog.free()

	var spawner := SurvivorSpawner.new()
	var commander := _sentinel_probe_aircraft("uav_commander", Vector2.ZERO)
	var escort := _sentinel_probe_aircraft("uav", Vector2(2000.0, 0.0))
	var sq := SquadFactory.create()
	SquadFactory.register_leader(sq, commander)
	SquadFactory.register_wingman(sq, escort, false)
	var escort_ai := _sentinel_probe_ai(escort)
	escort.set_meta("sentinel_native_escort", true)
	escort_ai.orbit_squad_leader = false
	escort_ai.shield_leader = false
	escort_ai.combat_zone_anchor = commander
	escort_ai.combat_zone_radius = 2500.0
	spawner._recall_detached_sentinel_escort(commander, sq, escort)
	_check("原生 MQ-109 超过 1800px 后恢复贴身护驾并清掉 hunter 锚",
		escort_ai.orbit_squad_leader and escort_ai.shield_leader \
			and escort_ai.combat_zone_anchor == null and escort.has_meta("sentinel_recall_active"), "")

	var hunter := _sentinel_probe_aircraft("uav", Vector2(2200.0, 0.0))
	SquadFactory.register_wingman(sq, hunter, false)
	var hunter_ai := _sentinel_probe_ai(hunter)
	hunter.set_meta("sentinel_native_escort", true)
	hunter.set_meta("sentinel_hunter", true)
	hunter_ai.combat_zone_anchor = commander
	hunter_ai.combat_zone_radius = 2500.0
	spawner._recall_detached_sentinel_escort(commander, sq, hunter)
	_check("CommanderAura 明确标记的 hunter 可离轴出击",
		not hunter_ai.orbit_squad_leader and not hunter_ai.shield_leader \
			and hunter_ai.combat_zone_anchor == commander \
			and not hunter.has_meta("sentinel_recall_active"), "")

	commander.free()
	escort.free()
	hunter.free()
	spawner.free()


func _sentinel_probe_aircraft(type_tag: String, pos: Vector2) -> Aircraft:
	var ac := Aircraft.new()
	ac.params = AircraftParams.new()
	ac.global_position = pos
	ac.set_meta("enemy_type", type_tag)
	var ai := AIController.new()
	ai.aircraft = ac
	ac.add_child(ai)
	return ac


func _sentinel_probe_ai(ac: Aircraft) -> AIController:
	for child in ac.get_children():
		if child is AIController:
			return child
	return null


func _test_debug_near_spawn() -> void:
	print("── L. F5 Debug：普通敌机即时刷新在玩家附近 ──")
	var spawner := SurvivorSpawner.new()
	var player := Aircraft.new()
	player.global_position = Vector2(321.0, -654.0)
	player.heading = 0.0
	spawner.player_aircraft = player
	var first := spawner._debug_spawn_point()
	var second := spawner._debug_spawn_point()
	var distance_ok := is_equal_approx(first.distance_to(player.global_position),
		SurvivorSpawner.DEBUG_SPAWN_DISTANCE_PX) \
		and is_equal_approx(second.distance_to(player.global_position),
			SurvivorSpawner.DEBUG_SPAWN_DISTANCE_PX)
	_check("近距点固定在玩家约 2200m 外且连续刷新不重叠", distance_ok and first != second,
		"first=%s second=%s" % [first, second])
	var debug_source := FileAccess.get_file_as_string(
		"res://scripts/survivor/survivor_debug_spawn.gd")
	_check("F5 单机/小队/Sentinel 明确走 debug_near_player 路径",
		debug_source.contains("_spawn_single(enum_idx, false, true)") \
			and debug_source.contains("_spawn_squad(enum_idx, size, false, false, true)") \
			and debug_source.contains("_spawn_commander_squad(size, true)"), "")
	player.free()
	spawner.free()


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])
