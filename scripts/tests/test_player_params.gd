extends RefCounted

const SurvivorSelectScript := preload("res://scripts/survivor/survivor_select.gd")

## 无头验收：resources/player/ 50 份玩家机 params。
## 全量加载 / 进化边雷达与武器平滑 / 雷达最终上限 / 王冠不越位 / 特殊武器隔离。
## 运行：godot --headless --path . -- --bench=player_params（或 --bench=all）

var _pass := 0
var _fail := 0

const IDS: Array[String] = [
	"mig21f13", "f104c", "j35f", "ea6b",
	"mig23", "f4e", "jaguar", "f14", "f15", "a6e", "mirage3",
	"mirage2000", "f15c", "f15e", "fa18e", "ea18g", "f16", "gripen_c", "su27", "a10",
	"rafale", "tornado", "typhoon", "su34", "viggen", "mig31", "harrier",
	"f15smtd", "su35", "f35", "gripen_e", "f22", "su57", "j20", "a12",
	"yf23", "f47", "mig41", "faxx", "fcas", "gcap", "j36",
	"x09", "x13", "x02", "x21", "x44", "x77", "x90", "ax00",
]

const MISSILE_T0_T2_IDS: Array[String] = [
	"mig21f13", "f104c", "j35f", "ea6b",
	"mig23", "f4e", "jaguar", "f14", "f15", "a6e", "mirage3",
	"mirage2000", "f15c", "f15e", "fa18e", "ea18g", "f16", "gripen_c", "su27", "a10",
	"rafale", "tornado", "typhoon", "su34", "viggen", "mig31", "harrier",
]
const MISSILE_T3_IDS: Array[String] = ["f15smtd", "su35", "f35", "gripen_e", "f22", "su57", "j20", "a12"]
const MISSILE_T4_STANDARD_IDS: Array[String] = ["yf23", "f47", "faxx", "fcas"]
const MISSILE_T4_RANGE_IDS: Array[String] = ["mig41", "gcap", "j36"]
const MISSILE_T5_STANDARD_IDS: Array[String] = ["x09", "x13", "x02", "x44", "x77", "x90", "ax00"]

## 机炮弹量按游戏定位分档，不随 tier 单调上升；180 是用户确认的易用性硬下限。
const GUN_AMMO_BY_ID: Dictionary = {
	"f104c": 180, "ea6b": 180, "f14": 180, "ea18g": 180, "mig31": 180,
	"f35": 180, "j20": 180, "yf23": 180, "mig41": 180, "gcap": 180,
	"j36": 180, "x13": 180, "x21": 180, "x77": 180,
	"f4e": 200, "mirage3": 200, "fa18e": 200, "f16": 200, "gripen_c": 200,
	"rafale": 200, "gripen_e": 200, "fcas": 200, "x02": 200, "x90": 200,
	"ax00": 200,
	"mig21f13": 240, "j35f": 240, "mig23": 240, "f15": 240, "mirage2000": 240,
	"f15c": 240, "su27": 240, "typhoon": 240, "f15smtd": 240, "su35": 240,
	"f22": 240, "su57": 240, "f47": 240, "x09": 240,
	"jaguar": 280, "a6e": 280, "f15e": 280, "tornado": 280, "su34": 280,
	"viggen": 280, "harrier": 280, "a12": 280, "faxx": 280,
	"a10": 320, "x44": 320,
}
const GUN_AMMO_BANDS: Array[int] = [180, 200, 240, 280, 320]

## 各 tier 的基础雷达走廊；机种身份在带内分化，代际位置由走廊和进化边共同约束。
const RADAR_TIER_BANDS: Dictionary = {
	0: [1900.0, 2400.0],
	1: [2200.0, 2800.0],
	2: [2550.0, 3200.0],
	3: [2850.0, 3400.0],
	4: [3200.0, 3900.0],
	5: [3450.0, 4400.0],
}


func run() -> void:
	print("\n════════ 玩家机 params 验收（50 机平滑曲线） ════════")
	var p: Dictionary = {}
	var all_loaded := true
	for id in IDS:
		var res = load("res://resources/player/player_%s.tres" % id)
		if res == null or not (res is AircraftParams):
			all_loaded = false
			print("    ! 加载失败：%s" % id)
			continue
		p[id] = res
	_check("50 份全部加载为 AircraftParams", all_loaded and p.size() == 50, "got %d" % p.size())
	if p.size() != 50:
		_finish()
		return
	var start_ids: Array[String] = []
	for entry in SurvivorSelectScript.PLAYABLE_LIST:
		start_ids.append(str(entry.get("id", "")))
	_check("选机页保留既有四机，并追加四架局外解锁 T0",
		start_ids == ["f15", "f14", "a6e", "mirage3", "mig21f13", "f104c", "j35f", "ea6b"],
		str(start_ids))
	var expected_start_benefits := {
		"mig21f13": &"gun_multishot", "f104c": &"rocket_ffar",
		"j35f": &"qmaam", "ea6b": &"esm_pod",
	}
	var start_benefits_ok := true
	var start_benefit_names_ok := true
	for id in expected_start_benefits:
		var profile := AircraftDB.get_profile(StringName(id))
		start_benefits_ok = start_benefits_ok and profile != null \
			and profile.starting_benefit_id == expected_start_benefits[id]
		var benefit_id: StringName = expected_start_benefits[id]
		start_benefit_names_ok = start_benefit_names_ok \
			and SurvivorSelectScript.STARTING_BENEFIT_NAME_KEYS.has(benefit_id) \
			and not String(SurvivorSelectScript.STARTING_BENEFIT_NAME_KEYS[benefit_id]).is_empty()
	_check("T0 四机声明机场等价开局礼包", start_benefits_ok, str(expected_start_benefits))
	_check("选机页为 T0 四种开局礼包声明玩家可见名称", start_benefit_names_ok,
		str(SurvivorSelectScript.STARTING_BENEFIT_NAME_KEYS))
	_check("MiG-21 开局机炮吊舱复用正式技能条目",
		not SurvivorData.upgrade_by_id("gun_multishot").is_empty(), "")

	# 锚点抽查（矩阵 §2 直写值；雷达列按 radar-range-normalization §2.3）
	# 弹 2：F-14 是 T1 起手机，弹数与其余三张起手卡（F-15/A-6E/幻影 III）对齐（2026-07-29 用户定）
	_check("T0 四机雷达均位于 1900~2400",
		p["mig21f13"].radar_range == 1900.0 and p["f104c"].radar_range == 1950.0
		and p["j35f"].radar_range == 2200.0 and p["ea6b"].radar_range == 2400.0, "")
	_check("F-104C 高速代价锁定 72 HP", is_equal_approx(p["f104c"].max_hp, 72.0),
		"got %.0f" % p["f104c"].max_hp)
	_check("F-14 锚点（110HP/2000/雷达2500/锥32/锁2.8/弹2）",
		_row_eq(p["f14"], 110, 2000, 2500, 32, 2.8, 2), _row_str(p["f14"]))
	_check("X-13 航电王（雷达4400/锥46/锁1.4）",
		is_equal_approx(p["x13"].radar_range, 4400.0) and is_equal_approx(p["x13"].radar_half_angle, 46.0)
		and is_equal_approx(p["x13"].lock_time, 1.4), _row_str(p["x13"]))
	_check("X-44 全谱最肉（HP 200）", is_equal_approx(p["x44"].max_hp, 200.0), "")
	_check("鹞失速地板 140（全谱最低签名）", is_equal_approx(p["harrier"].stall_speed_base, 140.0),
		"got %.0f" % p["harrier"].stall_speed_base)
	_check("其余机失速地板 220（模板）", is_equal_approx(p["a6e"].stall_speed_base, 220.0), "")
	_check("EA-18G 锚点（135HP/1900/雷达3150/锥44/锁2.1/弹2）",
		_row_eq(p["ea18g"], 135, 1900, 3150, 44, 2.1, 2), _row_str(p["ea18g"]))
	_check("F/A-XX 锚点（185HP/2700/雷达3300/锥38/锁1.9/弹3）",
		_row_eq(p["faxx"], 185, 2700, 3300, 38, 1.9, 3), _row_str(p["faxx"]))
	var faxx_profile := AircraftDB.get_profile(&"faxx")
	_check("F/A-XX 机炮核心档案（伤×1.5/程1400/锥10/瞄准0.75）",
		faxx_profile != null and is_equal_approx(faxx_profile.gun_damage_mult, 1.5)
		and is_equal_approx(faxx_profile.gun_range_override, 1400.0)
		and is_equal_approx(faxx_profile.gun_cone_override, 10.0)
		and is_equal_approx(faxx_profile.base_pilot_aim_skill, 0.75), "")

	# 结构极限 = 持续 G + 3（全谱规则）
	var structural_ok := true
	for id in IDS:
		if not is_equal_approx(p[id].max_g_structural, p[id].max_g + 3.0):
			structural_ok = false
	_check("全谱 max_g_structural = max_g + 3", structural_ok, "")

	# 雷达按 tier 平滑，同时检查每条真实进化边，防跨级跳变与反向大跌。
	var tiers := _load_tree_tiers()
	var corridor_ok := true
	for id in IDS:
		var band: Array = RADAR_TIER_BANDS[int(tiers[id])]
		if p[id].radar_range < float(band[0]) or p[id].radar_range > float(band[1]):
			corridor_ok = false
			print("    ! 带外：%s(T%d) radar=%.0f 带 %.0f~%.0f" % [
				id, int(tiers[id]), p[id].radar_range, float(band[0]), float(band[1])])
	_check("雷达 tier 走廊 T0 1900~2400 → T5 3450~4400", corridor_ok, "")
	_check("三带分层抽查 T2（F-16电战 > MiG-31骑士 > F-15C斗士）",
		p["f16"].radar_range > p["mig31"].radar_range
		and p["mig31"].radar_range > p["f15c"].radar_range, "")
	_check("F-14 雷达收窄（≤2500）", p["f14"].radar_range <= 2500.0, "got %.0f" % p["f14"].radar_range)
	_test_evolution_edge_smoothing(p)
	_test_effective_radar_cap()
	_test_enemy_weapon_scaling()

	# 同族链逐轴单调（同类纯升级规则 §1.3 抽查）
	_check("F-15→F-15C→S/MTD 逐轴不倒退",
		_chain_monotonic(p, ["f15", "f15c", "f15smtd"]), "")
	_check("鹰狮 C→E 逐轴不倒退", _chain_monotonic(p, ["gripen_c", "gripen_e"]), "")
	_check("远程线 F-14→MiG-31→J-20→MiG-41→X-21 速度递增",
		p["f14"].max_speed < p["mig31"].max_speed and p["mig31"].max_speed < p["j20"].max_speed
		and p["j20"].max_speed < p["mig41"].max_speed and p["mig41"].max_speed < p["x21"].max_speed, "")

	# 王冠不越位：AX-00 全轴第二（不夺任何单项冠军）
	_check("AX-00 不夺极速冠（< X-21）", p["ax00"].max_speed < p["x21"].max_speed, "")
	_check("AX-00 不夺航电冠（雷达 < X-13）", p["ax00"].radar_range < p["x13"].radar_range, "")
	_check("AX-00 不夺 G 冠（< X-09）", p["ax00"].max_g < p["x09"].max_g, "")
	_check("AX-00 不夺肉冠（HP < X-44）", p["ax00"].max_hp < p["x44"].max_hp, "")

	# 主导弹分档：T0~T2=2、T3=3、T4=3（远程三机4）、T5=4、X-21=5。
	var missile_tier_ok := true
	for id in MISSILE_T0_T2_IDS:
		missile_tier_ok = missile_tier_ok and p[id].missile != null and p[id].missile.max_count == 2
	for id in MISSILE_T3_IDS:
		missile_tier_ok = missile_tier_ok and p[id].missile != null and p[id].missile.max_count == 3
	for id in MISSILE_T4_STANDARD_IDS:
		missile_tier_ok = missile_tier_ok and p[id].missile != null and p[id].missile.max_count == 3
	for id in MISSILE_T4_RANGE_IDS:
		missile_tier_ok = missile_tier_ok and p[id].missile != null and p[id].missile.max_count == 4
	for id in MISSILE_T5_STANDARD_IDS:
		missile_tier_ok = missile_tier_ok and p[id].missile != null and p[id].missile.max_count == 4
	missile_tier_ok = missile_tier_ok and p["x21"].missile != null and p["x21"].missile.max_count == 5
	_check("主导弹分档 T0~T2=2、T3=3、T4远程=4、T5=4、X-21=5", missile_tier_ok, "")
	# T1 四张起手卡弹数一致（F-14 曾是 4，卡面写"导弹缩水"却比 F-16 多，2026-07-29 拉平为 2）
	_check("T1 起手四卡弹数齐平 = 2",
		p["f14"].missile.max_count == 2 and p["f15"].missile.max_count == 2
		and p["a6e"].missile.max_count == 2 and p["mirage3"].missile.max_count == 2, "")
	var f14_profile := AircraftDB.get_profile(&"f14")
	_check("F-14 起手档案显式锁定长机导弹数 = 2",
		f14_profile != null and f14_profile.missile_count_override == 2, "")
	_check("F-14 起手为双机编队（长机 + 1 僚机）",
		f14_profile != null and f14_profile.wingman_count == 1, "")
	# 特殊武器不烤入机体；T0 机场等价礼包只写 profile，开局走正式授予入口入库。
	# 底线武器（机炮/导弹/热诱弹）仍随机体。
	var carries_special: String = ""
	for id in IDS:
		var prm: AircraftParams = p[id]
		if prm.rocket != null:
			carries_special += "%s(rocket) " % id
		if prm.equipment != null and not prm.equipment.is_empty():
			carries_special += "%s(equipment) " % id
		if prm.loyal_wingman != null or prm.torpedo != null or prm.secondary_missile != null:
			carries_special += "%s(wingman/mine/qmaam) " % id
	_check("50 机基参无一烤入特殊武器（火箭/电磁炮/激光/僚机/雷/QMAAM）", carries_special == "", carries_special)
	_check("玩家 A-10 默认无火箭（只能从战区奖励取得）", p["a10"].rocket == null, "")
	var a10_legacy_base := load("res://resources/playable_a10_base.tres") as AircraftParams
	var a10_drone_variant := load("res://resources/playable_a10_drone.tres") as AircraftParams
	_check("A-10 旧基础与实验变体同样无火箭",
		a10_legacy_base != null and a10_legacy_base.rocket == null
		and a10_drone_variant != null and a10_drone_variant.rocket == null, "")
	_check("底线武器仍在（抽查 A-10/Su-34/X-44 有机炮+导弹）",
		p["a10"].gun != null and p["a10"].missile != null
		and p["su34"].missile != null and p["x44"].gun != null, "")

	_test_gun_ammo_profiles(p)
	# 热诱弹分档 + 敌我解耦（spec player-aircraft-power-curve §2.6）
	_test_flare_tiers(p)
	_test_flare_inheritance()
	_test_shared_resource_isolation()
	_finish()


## ⚠ 共享武器库隔离（用户 2026-07-23 硬要求："改玩家机炮的技能不能对敌人生效"）
## default_gun / default_combat 被 41 玩家机与 12 敌机同时引用 → 玩家升级若直改 params.gun
## 而未先深拷，会**污染磁盘资源实例**，敌机当场一起变强，且污染跨局残留（load 缓存不重置）。
## 两条玩家机产生路径都必须隔离：① spawn 走 deep_dup_weapons ② evolve 换机走 duplicate(true)
func _test_shared_resource_isolation() -> void:
	print("── 共享武器库隔离：玩家升级不得污染 default_gun（敌机同引用）──")
	var shared_gun: GunParams = load("res://resources/default_gun.tres")
	var shared_combat: Resource = load("res://resources/default_combat.tres")
	var base_dmg: float = shared_gun.bullet_damage
	var base_ammo: int = shared_gun.max_ammo

	# 路径 ①：spawn（survivor_mode 三处调用 deep_dup_weapons）
	var p1: AircraftParams = load("res://resources/player/player_f15.tres").duplicate(true)
	SurvivorPlayableSetup.deep_dup_weapons(p1)
	_check("spawn 路径：gun 已脱离共享实例", p1.gun != shared_gun, "仍指向 default_gun")
	_check("spawn 路径：combat 已脱离共享实例", p1.combat != shared_combat, "仍指向 default_combat")

	# ⚠ 引擎事实（本版本实测）：duplicate(true) **不深拷**子资源 —— 单靠它 gun 仍是共享实例。
	# 这正是 evolve 必须显式补 deep_dup_weapons 的原因；本条守住"别以为 duplicate(true) 够用"。
	var p_raw: AircraftParams = load("res://resources/player/player_f22.tres").duplicate(true)
	_check("（前提）duplicate(true) 单独用**不足以**隔离 gun —— 故 evolve 必须补深拷",
		p_raw.gun == shared_gun, "本引擎版本已能深拷？可复查 evolve 是否仍需 deep_dup_weapons")

	# 路径 ②：evolve 换机的真实序列（duplicate(true) + deep_dup_weapons）
	var p2: AircraftParams = load("res://resources/player/player_f22.tres").duplicate(true)
	SurvivorPlayableSetup.deep_dup_weapons(p2)
	_check("evolve 路径：gun 已脱离共享实例", p2.gun != shared_gun, "")
	_check("evolve 路径：combat 已脱离共享实例", p2.combat != shared_combat, "")

	# 源码守卫：防有人日后把 evolve 里的 deep_dup_weapons 当"冗余"删掉
	var evo_src: String = FileAccess.get_file_as_string("res://scripts/survivor/evolution_system.gd")
	_check("evolve() 源码含 deep_dup_weapons（删掉即污染敌机）",
		evo_src.contains("SurvivorPlayableSetup.deep_dup_weapons(ac.params)"), "")

	# 端到端：对两条路径的机各应用机炮升级，断言磁盘共享资源纹丝不动
	var sp := SurvivorPlayer.new()
	for prm in [p1, p2]:
		var ac := Aircraft.new()
		ac.params = prm
		ac.ammo = prm.gun.max_ammo if prm.gun else 0
		sp.aircraft = ac
		# 用直改 params 的分支（gun_damage 不自带 duplicate）——最能暴露污染
		sp.apply_upgrade(_find_upgrade("gun_damage"))
		ac.free()
	_check("应用机炮升级后 default_gun.bullet_damage 不变（敌机不受影响）",
		is_equal_approx(shared_gun.bullet_damage, base_dmg),
		"被污染：%.2f → %.2f" % [base_dmg, shared_gun.bullet_damage])
	_check("应用后 default_gun.max_ammo 不变",
		shared_gun.max_ammo == base_ammo,
		"被污染：%d → %d" % [base_ammo, shared_gun.max_ammo])
	sp.free()


## 玩家机炮弹量通过 profile 覆盖共享 default_gun；出生应用和进化换机都必须拿到新机满仓。
func _test_gun_ammo_profiles(p: Dictionary) -> void:
	print("── 机炮弹量：按定位五档 + 180 易用性地板 + 进化装满 ──")
	_check("机炮弹量表覆盖全部 50 机", GUN_AMMO_BY_ID.size() == IDS.size(),
		"got %d" % GUN_AMMO_BY_ID.size())
	var bad: String = ""
	var seen_bands: Dictionary = {}
	var base_bad: String = ""
	for id in IDS:
		var expected: int = int(GUN_AMMO_BY_ID.get(id, -1))
		var profile := AircraftDB.get_profile(StringName(id))
		if profile == null:
			bad += "%s(profile missing); " % id
			continue
		if profile.gun_ammo_override != expected or not GUN_AMMO_BANDS.has(expected):
			bad += "%s(expect=%d profile=%d); " % [id, expected, profile.gun_ammo_override]
			continue
		seen_bands[expected] = true
		if p[id].gun == null or p[id].gun.max_ammo != 200:
			base_bad += "%s(base=%s); " % [id, str(p[id].gun.max_ammo if p[id].gun else -1)]
			continue
		var ac := Aircraft.new()
		ac.params = profile.base_params.duplicate(true)
		SurvivorPlayableSetup.deep_dup_weapons(ac.params)
		SurvivorPlayableSetup.apply(ac, profile)
		if ac.params.gun == null or ac.params.gun.max_ammo != expected:
			bad += "%s(applied=%s); " % [id, str(ac.params.gun.max_ammo if ac.params.gun else -1)]
		ac.free()
	_check("50 机 profile 弹量精确命中 180/200/240/280/320 表", bad == "", bad)
	_check("五个弹量档均有机体且最低档为 180",
		seen_bands.size() == GUN_AMMO_BANDS.size() and seen_bands.has(180), str(seen_bands.keys()))
	_check("50 份 base 仍保持共享回退值 200（只在深拷 profile 上覆盖）", base_bad == "", base_bad)
	var shared_gun := load("res://resources/default_gun.tres") as GunParams
	_check("敌机/未配置档案 default_gun 仍为 200", shared_gun != null and shared_gun.max_ammo == 200, "")

	# 真实 evolve() 路径：旧机剩 17 发，换 A-10 后必须同时得到 320 上限与 320 当前弹量。
	var start_profile := AircraftDB.get_profile(&"f14")
	var evo_ac := Aircraft.new()
	evo_ac.params = start_profile.base_params.duplicate(true)
	SurvivorPlayableSetup.deep_dup_weapons(evo_ac.params)
	SurvivorPlayableSetup.apply(evo_ac, start_profile)
	evo_ac.ammo = 17
	var evolved: bool = EvolutionSystem.evolve(evo_ac, &"a10", false, false)
	_check("进化换机把机炮当前弹量重置为新机满仓",
		evolved and evo_ac.params.gun != null and evo_ac.params.gun.max_ammo == 320
		and evo_ac.ammo == 320,
		"evolved=%s max=%s ammo=%d" % [str(evolved),
			str(evo_ac.params.gun.max_ammo if evo_ac.params and evo_ac.params.gun else -1), evo_ac.ammo])
	evo_ac.free()


## 热诱弹按 tier 分档（2/3/4/5/6）+ 全族玩家特性统一 + 与敌机 default_flare 解耦
func _test_flare_tiers(p: Dictionary) -> void:
	print("── 热诱弹：tier 分档 2/3/4/5/6 + 玩家族特性统一 + 敌我解耦 ──")
	var want: Dictionary = {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6}
	var tree: Dictionary = _load_tree_tiers()
	_check("进化树 tier 表可读（50 机）", tree.size() == 50, "got %d" % tree.size())
	var bad: String = ""
	for id in IDS:
		var prm: AircraftParams = p[id]
		if prm.flare == null:
			bad += "%s 无 flare; " % id
			continue
		var expect: int = 2 if id == "ea6b" else int(want.get(int(tree.get(id, 0)), -1))
		if prm.flare.max_flares != expect:
			bad += "%s(T%d) 期望 %d 实得 %d; " % [id, int(tree.get(id, 0)), expect, prm.flare.max_flares]
	_check("50 机 flare 数量符合 tier 档位（EA-6B 以 2 发体现电战生存性）", bad == "", bad)

	# 玩家族统一特性（与敌用 default_flare 的 burst2 / jam0.55 / nervous0.5 区分开）
	var traits_bad: String = ""
	for id in IDS:
		var f: FlareParams = p[id].flare
		if f == null:
			continue
		if f.burst_count != 1 or not is_equal_approx(f.base_jam_chance, 0.90) \
				or not is_equal_approx(f.nervousness, 0.0):
			traits_bad += "%s(burst=%d jam=%.2f nerv=%.2f); " % [
				id, f.burst_count, f.base_jam_chance, f.nervousness]
	_check("50 机 flare 特性统一（burst=1 / jam=0.90 / nervousness=0）", traits_bad == "", traits_bad)

	# 解耦：玩家机不得再引用敌用 default_flare（改敌机数值不牵动玩家手感）
	var enemy_flare = load("res://resources/default_flare.tres")
	var coupled: String = ""
	for id in IDS:
		if p[id].flare == enemy_flare:
			coupled += id + " "
	_check("玩家机不引用敌用 default_flare（敌我解耦）", coupled == "", coupled)
	_check("敌用 default_flare 未被本批改动（仍 30/burst2/jam0.55）",
		enemy_flare != null and enemy_flare.max_flares == 30 and enemy_flare.burst_count == 2
		and is_equal_approx(enemy_flare.base_jam_chance, 0.55), "")


## 换机继承：电子对抗套件只提供锁定防护，不改变新机自身热诱弹基数。
func _test_flare_inheritance() -> void:
	print("── 换机继承：电子对抗套件不改变热诱弹基数 ──")
	var sp := SurvivorPlayer.new()
	var ac := Aircraft.new()
	ac.params = AircraftParams.new()
	# 起手 T1（2 发）
	ac.params.flare = load("res://resources/player/flare_t1.tres").duplicate()
	ac.flares_remaining = ac.params.flare.max_flares
	sp.aircraft = ac
	var shield: Dictionary = _find_upgrade("flare_shield")
	sp.apply_upgrade(shield)
	_check("T1(2) + 电子对抗 → max 仍为 2", ac.params.flare.max_flares == 2,
		"got %d" % ac.params.flare.max_flares)
	_check("T1 电子对抗后 remaining 仍为 2", ac.flares_remaining == 2, "got %d" % ac.flares_remaining)

	# 模拟进化换机：换成 T3 档新机 params（evolve() 的 flare 重置语义）
	ac.params = AircraftParams.new()
	ac.params.flare = load("res://resources/player/flare_t3.tres").duplicate()
	ac.flares_remaining = ac.params.flare.max_flares
	_check("换 T3 机：基数回到 4（未叠技能前）", ac.params.flare.max_flares == 4, "")
	# 换机重放（_replay_player_upgrades 语义：已持有技能无条件重挂）不改变新机基数。
	sp.apply_upgrade(shield)
	_check("换机重放后 max 仍为新机基数 4", ac.params.flare.max_flares == 4,
		"got %d" % ac.params.flare.max_flares)
	_check("换机重放后 remaining 仍为新机基数 4", ac.flares_remaining == 4,
		"got %d" % ac.flares_remaining)
	ac.free()
	sp.free()


## 读进化树 tier（id → tier）；测试自读 JSON，不依赖 EvolutionSystem 缓存状态
func _load_tree_tiers() -> Dictionary:
	var out: Dictionary = {}
	var txt: String = FileAccess.get_file_as_string("res://resources/evolution/evolution_tree.json")
	var data: Variant = JSON.parse_string(txt)
	if data == null:
		return out
	var nodes: Variant = data.get("nodes", data) if data is Dictionary else data
	if nodes is Array:
		for n in nodes:
			out[str(n.get("id", ""))] = int(n.get("tier", 0))
	return out


## 所有真实进化边都必须保持雷达、机炮与导弹的局部平滑；允许换定位时小幅回撤，禁止跨档暴涨。
func _test_evolution_edge_smoothing(p: Dictionary) -> void:
	print("── 真实进化边：雷达 / 机炮 / 导弹局部平滑 ──")
	var txt: String = FileAccess.get_file_as_string("res://resources/evolution/evolution_tree.json")
	var data: Variant = JSON.parse_string(txt)
	var nodes: Array = data.get("nodes", []) if data is Dictionary else []
	var bad: String = ""
	for n in nodes:
		var parent_id := str(n.get("id", ""))
		if not p.has(parent_id):
			continue
		var parent_profile := AircraftDB.get_profile(StringName(parent_id))
		for child_v in n.get("exits", []):
			var child_id := str(child_v)
			if not p.has(child_id):
				continue
			var child_profile := AircraftDB.get_profile(StringName(child_id))
			var radar_ratio: float = p[child_id].radar_range / maxf(p[parent_id].radar_range, 1.0)
			var gun_ratio: float = child_profile.gun_damage_mult / maxf(parent_profile.gun_damage_mult, 0.01)
			var parent_range: float = parent_profile.gun_range_override if parent_profile.gun_range_override > 0.0 else 800.0
			var child_range: float = child_profile.gun_range_override if child_profile.gun_range_override > 0.0 else 800.0
			var range_ratio := child_range / maxf(parent_range, 1.0)
			var missile_step: int = p[child_id].missile.max_count - p[parent_id].missile.max_count
			if radar_ratio < 0.90 or radar_ratio > 1.35 \
				or gun_ratio < 0.90 or gun_ratio > 1.35 \
				or range_ratio < 0.85 or range_ratio > 1.35 \
				or missile_step < 0 or missile_step > 1:
				bad += "%s→%s(radar %.2f gun %.2f range %.2f missile %+d); " % [
					parent_id, child_id, radar_ratio, gun_ratio, range_ratio, missile_step]
	_check("全部进化边的雷达/机炮不倒退过量且单步≤35%，导弹单步≤1", bad == "", bad)


func _test_effective_radar_cap() -> void:
	var ac := Aircraft.new()
	ac.params = AircraftParams.new()
	ac.params.radar_range = 99999.0
	ac.altitude = 15000.0
	ac.category_radar_mult = 9.0
	ac.ew_expert_radar_bonus_px = 99999.0
	_check("最终有效雷达硬上限 = 9000 px",
		is_equal_approx(ac.effective_radar_range_px(), Aircraft.MAX_EFFECTIVE_RADAR_RANGE_PX),
		"got %.0f" % ac.effective_radar_range_px())
	ac.free()


func _test_enemy_weapon_scaling() -> void:
	var f4e := load("res://resources/enemy_f4e.tres") as AircraftParams
	var af03 := load("res://resources/enemy_af03.tres") as AircraftParams
	_check("敌 F-4E 雷达回到前期带（2600 / 锁定3.4s）",
		f4e != null and is_equal_approx(f4e.radar_range, 2600.0)
		and is_equal_approx(f4e.lock_time, 3.4), "")
	_check("AF-03 远程特色保留但基础雷达压到 4800", af03 != null
		and is_equal_approx(af03.radar_range, 4800.0), "")
	var lv20 := SurvivorData.enemy_scale_for_level(20)
	_check("普通敌机等级只加耐久，不再重复增加弹量/机炮伤害",
		float(lv20.get("hp_mult", 1.0)) > 1.0
		and int(lv20.get("missile_add", -1)) == 0
		and is_equal_approx(float(lv20.get("gun_damage_mult", 0.0)), 1.0), str(lv20))


func _find_upgrade(id: String) -> Dictionary:
	for u in SurvivorData.UPGRADES:
		if str(u.get("id", "")) == id:
			return u
	return {}


func _row_eq(prm: AircraftParams, hp: float, spd: float, radar: float, cone: float, lock: float, msl: int) -> bool:
	return is_equal_approx(prm.max_hp, hp) and is_equal_approx(prm.max_speed, spd) \
		and is_equal_approx(prm.radar_range, radar) and is_equal_approx(prm.radar_half_angle, cone) \
		and is_equal_approx(prm.lock_time, lock) and prm.missile != null and prm.missile.max_count == msl


func _row_str(prm: AircraftParams) -> String:
	return "hp=%.0f spd=%.0f radar=%.0f cone=%.0f lock=%.1f" % [
		prm.max_hp, prm.max_speed, prm.radar_range, prm.radar_half_angle, prm.lock_time]


## 同族链每轴 ≥ 前代（HP/极速/巡航/加速/G/雷达/锥；锁定耗时 ≤ 前代）
func _chain_monotonic(p: Dictionary, chain: Array) -> bool:
	for i in range(1, chain.size()):
		var a: AircraftParams = p[chain[i - 1]]
		var b: AircraftParams = p[chain[i]]
		if b.max_hp < a.max_hp or b.max_speed < a.max_speed or b.cruise_speed < a.cruise_speed \
			or b.acceleration < a.acceleration or b.max_g < a.max_g \
			or b.radar_range < a.radar_range or b.radar_half_angle < a.radar_half_angle \
			or b.lock_time > a.lock_time:
			print("    ! 倒退：%s → %s" % [chain[i - 1], chain[i]])
			return false
	return true


func _finish() -> void:
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s — %s" % [label, detail])
