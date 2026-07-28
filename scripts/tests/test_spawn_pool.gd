extends RefCounted

## 无头行为验收：刷怪池配置（2026-07-28 平衡批）
##
## A 敌人高度分档表（按机型定位分化，不再全员均匀随机）
## B BOSS 专属机型不得从常规刷怪通道漏出
## C AF-03 可见性（旅途池门槛 + 战区池在册）
## D 签名技 sig_* 抽卡权重乘区
##
## 运行：godot --headless --path . -- --bench=spawn_pool（或 --bench=all）

var _pass := 0
var _fail := 0

## 抽样次数：够大以让"从不出现某档"的断言稳定，又不至于拖慢回归门
const SAMPLES := 3000


func run() -> void:
	print("\n════════ 刷怪池配置（高度分档 / BOSS 隔离 / AF-03 / sig 权重） ════════")
	_test_altitude_table_shape()
	_test_altitude_role_bias()
	_test_patrol_altitude_bands()
	_test_boss_only_isolation()
	_test_af03_visibility()
	_test_sig_weight()
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
	for t in SurvivorData.BOSS_ONLY_TYPES:
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


# ── F. 签名技抽卡权重 ──
func _test_sig_weight() -> void:
	print("── F. sig_* 抽卡权重：×2.5 乘区 + 判别式共用 ──")
	_check("SIG_SKILL_WEIGHT_MULT = 2.5",
		is_equal_approx(SurvivorData.SIG_SKILL_WEIGHT_MULT, 2.5),
		"got %.2f" % SurvivorData.SIG_SKILL_WEIGHT_MULT)
	_check("is_signature_upgrade 认 sig_ 前缀",
		SurvivorData.is_signature_upgrade({"id": "sig_f15"}), "")
	_check("is_signature_upgrade 不误伤普通技",
		not SurvivorData.is_signature_upgrade({"id": "gun_damage"}), "")
	_check("is_signature_upgrade 容忍缺 id 字段",
		not SurvivorData.is_signature_upgrade({}), "")
	# 等效权重：CLASSIFIED 0.08 × 2.5 = 0.20，应落在 ADVANCED(0.25) 与 EXPERIMENTAL(0.15) 之间
	var eff: float = SurvivorData.RARITY_BASE_WEIGHT[SurvivorData.Rarity.CLASSIFIED] \
		* SurvivorData.SIG_SKILL_WEIGHT_MULT
	_check("sig 等效权重落在 EXPERIMENTAL 与 ADVANCED 之间",
		eff > SurvivorData.RARITY_BASE_WEIGHT[SurvivorData.Rarity.EXPERIMENTAL]
		and eff < SurvivorData.RARITY_BASE_WEIGHT[SurvivorData.Rarity.ADVANCED],
		"eff=%.3f" % eff)
	# 轴内抽卡：一张 sig + 一张同稀有度普通技，sig 应显著更常被抽中
	var sig_card := {"id": "sig_test", "axis": "gladiator",
		"rarity": SurvivorData.Rarity.CLASSIFIED, "keywords": []}
	var plain_card := {"id": "plain_test", "axis": "gladiator",
		"rarity": SurvivorData.Rarity.CLASSIFIED, "keywords": []}
	var sig_hits := 0
	for i in SAMPLES:
		var picked: Dictionary = SurvivorData.pick_card_for_axis(
			[sig_card, plain_card], {}, 10)
		if str(picked.get("id", "")) == "sig_test":
			sig_hits += 1
	var ratio: float = float(sig_hits) / float(SAMPLES)
	# 理论 2.5/3.5 ≈ 0.714；给足抽样噪声余量
	_check("同稀有度对拉时 sig 命中率约 0.71（实测 %.3f）" % ratio,
		ratio > 0.65 and ratio < 0.78, "hits=%d/%d" % [sig_hits, SAMPLES])


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s %s" % [label, detail])
