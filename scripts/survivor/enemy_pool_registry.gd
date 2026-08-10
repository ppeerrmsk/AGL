class_name EnemyPoolRegistry
extends RefCounted

## 常规敌机池的纯数据注册表与选型器。
## 不持有场景引用、不逐帧运行；Spawner 只在生成 tick 调用，便于无头测试与参数审计。

const ARCHETYPES: Array[String] = ["Gladiator", "Lancer", "Schemer"]
const ROLES: Array[String] = ["dogfight", "intercept", "strike", "ew", "legacy_fodder"]

## 现役常规池。type 使用 SurvivorSpawner.EnemyType 的稳定 int；事件/BOSS/王牌类型刻意不登记。
## spawn_budget_cost 可包含固定护卫，用于生成前过滤；单机实际 token_cost 仍由 SurvivorData 记账。
const ROWS: Array[Dictionary] = [
	{"type": 0, "id": "uav", "archetype": "Gladiator", "role": "legacy_fodder", "unlock": 1, "retire": 4, "weight": 1.2, "token_cost": 1, "instance_cap": -1, "spawn_min": 1, "spawn_max": 4},
	{"type": 1, "id": "ucav", "archetype": "Lancer", "role": "legacy_fodder", "unlock": 1, "retire": 4, "weight": 1.0, "token_cost": 2, "instance_cap": -1, "spawn_min": 1, "spawn_max": 4},
	{"type": 23, "id": "f4e", "archetype": "Lancer", "role": "legacy_fodder", "unlock": 1, "retire": 6, "weight": 1.0, "token_cost": 2, "instance_cap": -1, "spawn_min": 1, "spawn_max": 3},
	{"type": 5, "id": "f86", "archetype": "Gladiator", "role": "legacy_fodder", "unlock": 2, "retire": -1, "weight": 1.0, "token_cost": 3, "instance_cap": -1, "spawn_min": 1, "spawn_max": 3},
	{"type": 10, "id": "a7", "archetype": "Lancer", "role": "strike", "unlock": 3, "retire": -1, "weight": 1.0, "token_cost": 3, "instance_cap": -1, "spawn_min": 1, "spawn_max": 3},
	{"type": 7, "id": "mig23", "archetype": "Gladiator", "role": "dogfight", "unlock": 4, "retire": -1, "weight": 1.0, "token_cost": 4, "instance_cap": -1, "spawn_min": 1, "spawn_max": 3},
	{"type": 4, "id": "sentinel", "archetype": "Schemer", "role": "ew", "unlock": 4, "retire": -1, "weight": 0.35, "token_cost": 6, "spawn_budget_cost": 13, "instance_cap": 1, "spawn_min": 1, "spawn_max": 1, "escort_excluded": true},
	{"type": 11, "id": "q5", "archetype": "Lancer", "role": "strike", "unlock": 5, "retire": -1, "weight": 1.0, "token_cost": 4, "instance_cap": -1, "spawn_min": 1, "spawn_max": 3},
	{"type": 3, "id": "interceptor", "archetype": "Lancer", "role": "intercept", "unlock": 5, "retire": -1, "weight": 1.0, "token_cost": 5, "instance_cap": -1, "spawn_min": 1, "spawn_max": 3},
	{"type": 20, "id": "f104", "archetype": "Lancer", "role": "intercept", "unlock": 5, "retire": -1, "weight": 1.0, "token_cost": 4, "instance_cap": -1, "spawn_min": 1, "spawn_max": 3},
	{"type": 19, "id": "f4", "archetype": "Gladiator", "role": "dogfight", "unlock": 6, "retire": -1, "weight": 0.9, "token_cost": 5, "instance_cap": -1, "spawn_min": 1, "spawn_max": 3},
	{"type": 8, "id": "f100", "archetype": "Lancer", "role": "intercept", "unlock": 6, "retire": -1, "weight": 0.9, "token_cost": 5, "instance_cap": 3, "spawn_min": 1, "spawn_max": 3},
	{"type": 2, "id": "mig", "archetype": "Gladiator", "role": "dogfight", "unlock": 7, "retire": -1, "weight": 1.0, "token_cost": 4, "instance_cap": -1, "spawn_min": 1, "spawn_max": 3},
	{"type": 17, "id": "af03", "archetype": "Schemer", "role": "ew", "unlock": 7, "retire": -1, "weight": 0.45, "token_cost": 7, "instance_cap": 1, "spawn_min": 1, "spawn_max": 1, "escort_excluded": true},
	{"type": 9, "id": "su27", "archetype": "Gladiator", "role": "dogfight", "unlock": 8, "retire": -1, "weight": 0.65, "token_cost": 7, "instance_cap": 2, "spawn_min": 1, "spawn_max": 1, "escort_excluded": true},
	{"type": 6, "id": "mig31", "archetype": "Lancer", "role": "intercept", "unlock": 9, "retire": -1, "weight": 0.55, "token_cost": 8, "instance_cap": 2, "spawn_min": 1, "spawn_max": 1, "escort_excluded": true},
	{"type": 21, "id": "su35", "archetype": "Gladiator", "role": "dogfight", "unlock": 9, "retire": -1, "weight": 0.55, "token_cost": 8, "instance_cap": 3, "spawn_min": 1, "spawn_max": 3},
	{"type": 31, "id": "snowblind", "archetype": "Schemer", "role": "ew", "unlock": 8, "retire": -1, "weight": 0.45, "token_cost": 4, "spawn_budget_cost": 10, "instance_cap": 1, "spawn_min": 1, "spawn_max": 1, "cooldown_sec": 180.0, "stage_cap": 2, "support_body": true},
	{"type": 56, "id": "deadair", "resource_path": "res://resources/enemy_deadair.tres", "archetype": "Schemer", "role": "ew", "unlock": 9, "retire": -1, "weight": 0.40, "token_cost": 4, "spawn_budget_cost": 10, "instance_cap": 1, "spawn_min": 1, "spawn_max": 1, "cooldown_sec": 180.0, "stage_cap": 2, "support_body": true},
	{"type": 30, "id": "f22", "archetype": "Schemer", "role": "ew", "unlock": 13, "retire": -1, "weight": 0.35, "token_cost": 10, "instance_cap": 3, "spawn_min": 1, "spawn_max": 3, "cooldown_sec": 150.0, "stage_cap": 6},
	{"type": 32, "id": "f15", "resource_path": "res://resources/enemy_regular_f15.tres", "archetype": "Gladiator", "role": "dogfight", "unlock": 7, "retire": -1, "weight": 0.85, "token_cost": 6, "instance_cap": -1, "spawn_min": 2, "spawn_max": 3},
	{"type": 33, "id": "f14", "resource_path": "res://resources/enemy_f14.tres", "archetype": "Lancer", "role": "intercept", "unlock": 7, "retire": -1, "weight": 0.65, "token_cost": 6, "instance_cap": 3, "spawn_min": 2, "spawn_max": 2},
	{"type": 34, "id": "a6e", "resource_path": "res://resources/enemy_a6e.tres", "archetype": "Lancer", "role": "strike", "unlock": 3, "retire": -1, "weight": 0.90, "token_cost": 3, "instance_cap": -1, "spawn_min": 2, "spawn_max": 3},
	{"type": 35, "id": "mirage3", "resource_path": "res://resources/enemy_mirage3.tres", "archetype": "Lancer", "role": "intercept", "unlock": 2, "retire": -1, "weight": 0.90, "token_cost": 3, "instance_cap": -1, "spawn_min": 2, "spawn_max": 3},
	{"type": 36, "id": "mirage2000", "resource_path": "res://resources/enemy_regular_mirage2000.tres", "archetype": "Gladiator", "role": "dogfight", "unlock": 6, "retire": -1, "weight": 0.85, "token_cost": 5, "instance_cap": -1, "spawn_min": 2, "spawn_max": 3},
	{"type": 37, "id": "fa18e", "resource_path": "res://resources/enemy_fa18e.tres", "archetype": "Gladiator", "role": "dogfight", "unlock": 7, "retire": -1, "weight": 0.85, "token_cost": 6, "instance_cap": -1, "spawn_min": 2, "spawn_max": 3},
	{"type": 38, "id": "f16", "resource_path": "res://resources/enemy_regular_f16.tres", "archetype": "Gladiator", "role": "dogfight", "unlock": 5, "retire": -1, "weight": 1.0, "token_cost": 4, "instance_cap": -1, "spawn_min": 2, "spawn_max": 4},
	{"type": 39, "id": "a10", "resource_path": "res://resources/enemy_a10.tres", "archetype": "Gladiator", "role": "strike", "unlock": 4, "retire": -1, "weight": 0.80, "token_cost": 4, "instance_cap": -1, "spawn_min": 2, "spawn_max": 3},
	{"type": 40, "id": "f15c", "resource_path": "res://resources/enemy_f15c.tres", "archetype": "Gladiator", "role": "dogfight", "unlock": 9, "retire": -1, "weight": 0.65, "token_cost": 7, "instance_cap": 3, "spawn_min": 2, "spawn_max": 2},
	{"type": 41, "id": "f15e", "resource_path": "res://resources/enemy_f15e.tres", "archetype": "Lancer", "role": "strike", "unlock": 8, "retire": -1, "weight": 0.70, "token_cost": 6, "instance_cap": 3, "spawn_min": 2, "spawn_max": 2},
	{"type": 42, "id": "gripen_c", "resource_path": "res://resources/enemy_gripen_c.tres", "archetype": "Schemer", "role": "ew", "unlock": 6, "retire": -1, "weight": 0.60, "token_cost": 5, "instance_cap": 4, "spawn_min": 3, "spawn_max": 3, "multilock_mode": "team3", "lock_count": 1},
	{"type": 43, "id": "rafale", "resource_path": "res://resources/enemy_rafale.tres", "archetype": "Schemer", "role": "ew", "unlock": 9, "retire": -1, "weight": 0.50, "token_cost": 7, "instance_cap": 3, "spawn_min": 2, "spawn_max": 2, "multilock_mode": "per2", "lock_count": 2},
	{"type": 44, "id": "tornado", "resource_path": "res://resources/enemy_tornado.tres", "archetype": "Lancer", "role": "strike", "unlock": 6, "retire": -1, "weight": 0.85, "token_cost": 5, "instance_cap": -1, "spawn_min": 2, "spawn_max": 3},
	{"type": 45, "id": "typhoon", "resource_path": "res://resources/enemy_typhoon.tres", "archetype": "Gladiator", "role": "dogfight", "unlock": 9, "retire": -1, "weight": 0.60, "token_cost": 7, "instance_cap": 3, "spawn_min": 2, "spawn_max": 2},
	{"type": 46, "id": "su34", "resource_path": "res://resources/enemy_su34.tres", "archetype": "Lancer", "role": "strike", "unlock": 8, "retire": -1, "weight": 0.65, "token_cost": 6, "instance_cap": 3, "spawn_min": 2, "spawn_max": 2},
	{"type": 47, "id": "viggen", "resource_path": "res://resources/enemy_viggen.tres", "archetype": "Lancer", "role": "intercept", "unlock": 5, "retire": -1, "weight": 0.85, "token_cost": 4, "instance_cap": -1, "spawn_min": 2, "spawn_max": 3},
	{"type": 48, "id": "harrier", "resource_path": "res://resources/enemy_harrier.tres", "archetype": "Gladiator", "role": "dogfight", "unlock": 5, "retire": -1, "weight": 0.80, "token_cost": 4, "instance_cap": -1, "spawn_min": 2, "spawn_max": 3},
	{"type": 49, "id": "f15smtd", "resource_path": "res://resources/enemy_f15smtd.tres", "archetype": "Gladiator", "role": "dogfight", "unlock": 11, "retire": -1, "weight": 0.45, "token_cost": 8, "instance_cap": 2, "spawn_min": 1, "spawn_max": 2, "post_stall": true},
	{"type": 50, "id": "f35", "resource_path": "res://resources/enemy_f35.tres", "archetype": "Schemer", "role": "ew", "unlock": 11, "retire": -1, "weight": 0.45, "token_cost": 8, "instance_cap": 2, "spawn_min": 1, "spawn_max": 2, "multilock_mode": "per2", "lock_count": 2},
	{"type": 51, "id": "gripen_e", "resource_path": "res://resources/enemy_gripen_e.tres", "archetype": "Schemer", "role": "ew", "unlock": 10, "retire": -1, "weight": 0.50, "token_cost": 7, "instance_cap": 3, "spawn_min": 2, "spawn_max": 3, "multilock_mode": "team3", "lock_count": 1},
	{"type": 52, "id": "su57", "resource_path": "res://resources/enemy_su57.tres", "archetype": "Gladiator", "role": "dogfight", "unlock": 12, "retire": -1, "weight": 0.40, "token_cost": 9, "instance_cap": 2, "spawn_min": 1, "spawn_max": 2, "post_stall": true},
	{"type": 53, "id": "j20", "resource_path": "res://resources/enemy_j20.tres", "archetype": "Lancer", "role": "intercept", "unlock": 12, "retire": -1, "weight": 0.40, "token_cost": 9, "instance_cap": 2, "spawn_min": 1, "spawn_max": 2},
	{"type": 54, "id": "a12", "resource_path": "res://resources/enemy_a12.tres", "archetype": "Schemer", "role": "ew", "unlock": 13, "retire": -1, "weight": 0.35, "token_cost": 8, "instance_cap": 2, "spawn_min": 1, "spawn_max": 2},
]


static func row_for_type(type_idx: int) -> Dictionary:
	for row in ROWS:
		if int(row["type"]) == type_idx:
			return row
	return {}


static func role_weights(response_level: int) -> Dictionary:
	if response_level <= 4:
		return {"dogfight": 0.25, "intercept": 0.15, "strike": 0.20, "ew": 0.05, "legacy_fodder": 0.35}
	if response_level <= 9:
		return {"dogfight": 0.30, "intercept": 0.20, "strike": 0.20, "ew": 0.15, "legacy_fodder": 0.15}
	return {"dogfight": 0.30, "intercept": 0.25, "strike": 0.20, "ew": 0.20, "legacy_fodder": 0.05}


static func eligible_rows(response_level: int, remaining_budget: int, counts_by_type: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in ROWS:
		if response_level < int(row["unlock"]):
			continue
		var retire: int = int(row["retire"])
		if retire >= 0 and response_level > retire:
			continue
		if int(row.get("spawn_budget_cost", row["token_cost"])) > remaining_budget:
			continue
		var cap: int = int(row["instance_cap"])
		if cap > 0 and int(counts_by_type.get(int(row["type"]), 0)) >= cap:
			continue
		out.append(row)
	return out


## ADBS 逃跑组护卫不占常规 Token：只服从有效响应等级的解锁/退役门，
## 并排除必须走专用编成的指挥机、支援体与单机精英。
static func escort_rows(response_level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in eligible_rows(response_level, 1_000_000, {}):
		if bool(row.get("support_body", false)) or bool(row.get("escort_excluded", false)):
			continue
		out.append(row)
	return out


## role_roll 与 type_roll 均取 [0,1)。先按非空角色桶权重抽角色，再在桶内按机型权重抽取。
## recent_types 是最近三支常规中队；只要存在其它合格机型，就禁止重复这些类型。
static func pick_row(candidates: Array[Dictionary], response_level: int,
		recent_types: Array, role_roll: float, type_roll: float) -> Dictionary:
	if candidates.is_empty():
		return {}
	var non_recent_candidates: Array[Dictionary] = []
	for row in candidates:
		if int(row["type"]) not in recent_types:
			non_recent_candidates.append(row)
	if not non_recent_candidates.is_empty():
		candidates = non_recent_candidates
	var weights: Dictionary = role_weights(response_level)
	var available_roles: Array[String] = []
	for row in candidates:
		var role: String = str(row["role"])
		if role not in available_roles:
			available_roles.append(role)
	var role_total: float = 0.0
	for role in available_roles:
		role_total += float(weights.get(role, 0.0))
	var role_needle: float = clampf(role_roll, 0.0, 0.999999) * role_total
	var picked_role: String = available_roles[0]
	for role in available_roles:
		var role_weight: float = float(weights.get(role, 0.0))
		if role_needle < role_weight:
			picked_role = role
			break
		role_needle -= role_weight

	var role_rows: Array[Dictionary] = []
	for row in candidates:
		if str(row["role"]) == picked_role:
			role_rows.append(row)
	var type_total: float = 0.0
	for row in role_rows:
		type_total += float(row["weight"])
	var type_needle: float = clampf(type_roll, 0.0, 0.999999) * type_total
	for row in role_rows:
		var type_weight: float = float(row["weight"])
		if type_needle < type_weight:
			return row
		type_needle -= type_weight
	return role_rows.back()


## 新敌版参数审计门。返回空数组即通过；只使用敌版自身参数与单架 Token，不读取玩家机数据。
static func audit_enemy_params(row: Dictionary, params: AircraftParams) -> Array[String]:
	var errors: Array[String] = []
	if row.is_empty() or params == null:
		return ["missing row or params"]
	var resources: Array = [params, params.gun, params.missile, params.secondary_missile,
		params.rocket, params.flare, params.combat]
	for resource in resources:
		if resource != null and String(resource.resource_path).contains("res://resources/player/"):
			errors.append("player resource dependency: %s" % resource.resource_path)
	if bool(row.get("support_body", false)):
		if not is_equal_approx(params.max_hp, 55.0) or not is_equal_approx(params.radar_range, 1200.0) \
				or not is_equal_approx(params.lock_time, 99.0):
			errors.append("support body must match Sentinel hp/radar/lock")
		if params.gun != null or params.missile != null or params.secondary_missile != null \
				or params.rocket != null or params.flare != null:
			errors.append("support body must be unarmed and flareless")
		return errors
	var token: int = int(row["token_cost"])
	var hp_band: Vector2
	var radar_band: Vector2
	var lock_band: Vector2
	var flare_fail_band: Vector2
	if token <= 3:
		hp_band = Vector2(32.0, 45.0)
		radar_band = Vector2(2200.0, 3000.0)
		lock_band = Vector2(3.0, 4.0)
		flare_fail_band = Vector2(0.65, 1.0)
	elif token <= 6:
		hp_band = Vector2(45.0, 60.0)
		radar_band = Vector2(3200.0, 3800.0)
		lock_band = Vector2(2.8, 3.5)
		flare_fail_band = Vector2(0.45, 0.55)
	elif token <= 8:
		hp_band = Vector2(55.0, 70.0)
		radar_band = Vector2(4200.0, 4600.0)
		lock_band = Vector2(2.5, 3.2)
		flare_fail_band = Vector2(0.10, 0.20)
	else:
		hp_band = Vector2(60.0, 75.0)
		radar_band = Vector2(4200.0, 4600.0)
		lock_band = Vector2(2.5, 3.5)
		flare_fail_band = Vector2(0.10, 0.15)
	if params.max_hp < hp_band.x or params.max_hp > hp_band.y:
		errors.append("hp %.1f outside %.1f..%.1f" % [params.max_hp, hp_band.x, hp_band.y])
	var radar_max: float = 5200.0 if bool(row.get("radar_exception", false)) else radar_band.y
	if params.radar_range < radar_band.x or params.radar_range > radar_max:
		errors.append("radar %.1f outside %.1f..%.1f" % [params.radar_range, radar_band.x, radar_max])
	if params.radar_half_angle < 20.0 or params.radar_half_angle > 35.0:
		errors.append("radar half-angle %.1f outside 20..35" % params.radar_half_angle)
	if params.lock_time < lock_band.x or params.lock_time > lock_band.y:
		errors.append("lock %.2f outside %.2f..%.2f" % [params.lock_time, lock_band.x, lock_band.y])
	if params.flare:
		if params.flare.max_flares > 1 or params.flare.burst_count > 1:
			errors.append("flare count/burst exceeds 1")
		if params.flare.fail_chance < flare_fail_band.x - 0.0001 \
				or params.flare.fail_chance > flare_fail_band.y + 0.0001:
			errors.append("flare fail %.2f outside %.2f..%.2f" % [
				params.flare.fail_chance, flare_fail_band.x, flare_fail_band.y])
	return errors
