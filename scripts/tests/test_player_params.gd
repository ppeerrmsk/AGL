extends RefCounted

## 无头验收：resources/player/ 43 份玩家机 params（spec player-aircraft-power-curve §2 v18 矩阵）
## 全量加载 / 矩阵锚点抽查 / 同族链逐轴单调 / 雷达走廊 / 王冠不越位 / 攻击线火箭
## 运行：godot --headless --path . -- --bench=player_params（或 --bench=all）

var _pass := 0
var _fail := 0

const IDS: Array[String] = [
	"f14", "f15", "a6e", "mirage3",
	"mirage2000", "f15c", "f15e", "fa18e", "ea18g", "f16", "gripen_c", "su27", "a10",
	"rafale", "tornado", "typhoon", "su34", "viggen", "mig31", "harrier",
	"f15smtd", "su35", "f35", "gripen_e", "f22", "su57", "j20", "a12",
	"yf23", "f47", "mig41", "faxx", "fcas", "gcap", "j36",
	"x09", "x13", "x02", "x21", "x44", "x77", "x90", "ax00",
]

const MISSILE_T1_T2_IDS: Array[String] = [
	"f14", "f15", "a6e", "mirage3",
	"mirage2000", "f15c", "f15e", "fa18e", "ea18g", "f16", "gripen_c", "su27", "a10",
	"rafale", "tornado", "typhoon", "su34", "viggen", "mig31", "harrier",
]
const MISSILE_T3_T4_IDS: Array[String] = [
	"f15smtd", "su35", "f35", "gripen_e", "f22", "su57", "j20", "a12",
	"yf23", "f47", "mig41", "faxx", "fcas", "gcap", "j36",
]
const MISSILE_T5_STANDARD_IDS: Array[String] = ["x09", "x13", "x02", "x44", "x77", "x90", "ax00"]

## 雷达三带走廊（spec radar-range-normalization §2.1/§2.2）：主题=航电身份，电战>骑士>斗士
## omni（X-02/AX-00）特则=同档电战王冠×≈0.9，走廊归电战带
const RADAR_BANDS: Dictionary = {
	"gladiator": [2100.0, 3400.0],   # 斗士：制空/攻击/格斗/隐身
	"knight": [2600.0, 4400.0],      # 骑士：远程/桥接/母舰
	"schemer": [3000.0, 5000.0],     # 电战 + omni 特则
}
const RADAR_BAND_BY_ID: Dictionary = {
	"f15": "gladiator", "a6e": "gladiator", "mirage2000": "gladiator",
	"f15c": "gladiator", "f15e": "gladiator", "su27": "gladiator", "a10": "gladiator",
	"tornado": "gladiator", "typhoon": "gladiator", "su34": "gladiator",
	"viggen": "gladiator", "harrier": "gladiator", "f15smtd": "gladiator",
	"su35": "gladiator", "f22": "gladiator", "su57": "gladiator", "a12": "gladiator",
	"yf23": "gladiator", "f47": "gladiator", "faxx": "gladiator", "x09": "gladiator", "x44": "gladiator",
	"x77": "gladiator",
	"f14": "knight", "mig31": "knight", "j20": "knight", "mig41": "knight",
	"gcap": "knight", "j36": "knight", "x21": "knight", "fa18e": "knight", "x90": "knight",
	"mirage3": "schemer", "ea18g": "schemer", "f16": "schemer", "gripen_c": "schemer", "rafale": "schemer",
	"f35": "schemer", "gripen_e": "schemer", "fcas": "schemer", "x13": "schemer",
	"x02": "schemer", "ax00": "schemer",
}


func run() -> void:
	print("\n════════ 玩家机 params 验收（43 机矩阵 v18） ════════")
	var p: Dictionary = {}
	var all_loaded := true
	for id in IDS:
		var res = load("res://resources/player/player_%s.tres" % id)
		if res == null or not (res is AircraftParams):
			all_loaded = false
			print("    ! 加载失败：%s" % id)
			continue
		p[id] = res
	_check("43 份全部加载为 AircraftParams", all_loaded and p.size() == 43, "got %d" % p.size())
	if p.size() != 43:
		_finish()
		return

	# 锚点抽查（矩阵 §2 直写值；雷达列按 radar-range-normalization §2.3）
	# 弹 2：F-14 是 T1 起手机，弹数与其余三张起手卡（F-15/A-6E/幻影 III）对齐（2026-07-29 用户定）
	_check("F-14 锚点（110HP/2000/雷达2600/锥32/锁2.8/弹2）",
		_row_eq(p["f14"], 110, 2000, 2600, 32, 2.8, 2), _row_str(p["f14"]))
	_check("X-13 航电王（雷达5000/锥46/锁1.4）",
		is_equal_approx(p["x13"].radar_range, 5000.0) and is_equal_approx(p["x13"].radar_half_angle, 46.0)
		and is_equal_approx(p["x13"].lock_time, 1.4), _row_str(p["x13"]))
	_check("X-44 全谱最肉（HP 200）", is_equal_approx(p["x44"].max_hp, 200.0), "")
	_check("鹞失速地板 140（全谱最低签名）", is_equal_approx(p["harrier"].stall_speed_base, 140.0),
		"got %.0f" % p["harrier"].stall_speed_base)
	_check("其余机失速地板 220（模板）", is_equal_approx(p["a6e"].stall_speed_base, 220.0), "")
	_check("EA-18G 锚点（135HP/1900/雷达3450/锥44/锁2.1/弹3）",
		_row_eq(p["ea18g"], 135, 1900, 3450, 44, 2.1, 3), _row_str(p["ea18g"]))
	_check("F/A-XX 锚点（185HP/2700/雷达3200/锥38/锁1.9/弹3）",
		_row_eq(p["faxx"], 185, 2700, 3200, 38, 1.9, 3), _row_str(p["faxx"]))
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

	# 雷达三带走廊（spec radar-range-normalization：全谱硬界 2100~5000）
	var corridor_ok := true
	for id in IDS:
		var band: Array = RADAR_BANDS[RADAR_BAND_BY_ID[id]]
		if p[id].radar_range < float(band[0]) or p[id].radar_range > float(band[1]):
			corridor_ok = false
			print("    ! 带外：%s(%s) radar=%.0f 带 %.0f~%.0f" % [
				id, RADAR_BAND_BY_ID[id], p[id].radar_range, float(band[0]), float(band[1])])
	_check("雷达三带走廊（斗士2100~3400/骑士2600~4400/电战·omni3000~5000）", corridor_ok, "")
	_check("三带分层抽查 T2（F-16电战 > MiG-31骑士 > F-15C斗士）",
		p["f16"].radar_range > p["mig31"].radar_range
		and p["mig31"].radar_range > p["f15c"].radar_range, "")
	_check("F-14 初始雷达收窄（≤2600，规范化主诉求）",
		p["f14"].radar_range <= 2600.0, "got %.0f" % p["f14"].radar_range)

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

	# 主导弹分档（内联 missile 单一权威源）：T1/T2=2、T3/T4=3、T5=4；仅 T5 远程 X-21=5。
	var missile_tier_ok := true
	for id in MISSILE_T1_T2_IDS:
		missile_tier_ok = missile_tier_ok and p[id].missile != null and p[id].missile.max_count == 2
	for id in MISSILE_T3_T4_IDS:
		missile_tier_ok = missile_tier_ok and p[id].missile != null and p[id].missile.max_count == 3
	for id in MISSILE_T5_STANDARD_IDS:
		missile_tier_ok = missile_tier_ok and p[id].missile != null and p[id].missile.max_count == 4
	missile_tier_ok = missile_tier_ok and p["x21"].missile != null and p["x21"].missile.max_count == 5
	_check("主导弹分档 T1/T2=2、T3/T4=3、T5=4、仅 X-21=5", missile_tier_ok, "")
	# T1 四张起手卡弹数一致（F-14 曾是 4，卡面写"导弹缩水"却比 F-16 多，2026-07-29 拉平为 2）
	_check("T1 起手四卡弹数齐平 = 2",
		p["f14"].missile.max_count == 2 and p["f15"].missile.max_count == 2
		and p["a6e"].missile.max_count == 2 and p["mirage3"].missile.max_count == 2, "")
	var f14_profile := AircraftDB.get_profile(&"f14")
	_check("F-14 起手档案显式锁定长机导弹数 = 2",
		f14_profile != null and f14_profile.missile_count_override == 2, "")
	_check("F-14 起手为双机编队（长机 + 1 僚机）",
		f14_profile != null and f14_profile.wingman_count == 1, "")
	# 特殊武器不自带（用户 2026-07-23 令："所有飞机都不要自带特殊武器，要从战区获取"）
	# 底线武器（机炮/导弹/热诱弹）仍随机体；火箭/电磁炮/激光/僚机/漂浮雷/QMAAM 一律战区+签名技获取
	var carries_special: String = ""
	for id in IDS:
		var prm: AircraftParams = p[id]
		if prm.rocket != null:
			carries_special += "%s(rocket) " % id
		if prm.equipment != null and not prm.equipment.is_empty():
			carries_special += "%s(equipment) " % id
		if prm.loyal_wingman != null or prm.torpedo != null or prm.secondary_missile != null:
			carries_special += "%s(wingman/mine/qmaam) " % id
	_check("43 机无一自带特殊武器（火箭/电磁炮/激光/僚机/雷/QMAAM）", carries_special == "", carries_special)
	_check("玩家 A-10 默认无火箭（只能从战区奖励取得）", p["a10"].rocket == null, "")
	var a10_legacy_base := load("res://resources/playable_a10_base.tres") as AircraftParams
	var a10_drone_variant := load("res://resources/playable_a10_drone.tres") as AircraftParams
	_check("A-10 旧基础与实验变体同样无火箭",
		a10_legacy_base != null and a10_legacy_base.rocket == null
		and a10_drone_variant != null and a10_drone_variant.rocket == null, "")
	_check("底线武器仍在（抽查 A-10/Su-34/X-44 有机炮+导弹）",
		p["a10"].gun != null and p["a10"].missile != null
		and p["su34"].missile != null and p["x44"].gun != null, "")

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


## 热诱弹按 tier 分档（2/3/4/5/6）+ 全族玩家特性统一 + 与敌机 default_flare 解耦
func _test_flare_tiers(p: Dictionary) -> void:
	print("── 热诱弹：tier 分档 2/3/4/5/6 + 玩家族特性统一 + 敌我解耦 ──")
	var want: Dictionary = {1: 2, 2: 3, 3: 4, 4: 5, 5: 6}
	var tree: Dictionary = _load_tree_tiers()
	_check("进化树 tier 表可读（43 机）", tree.size() == 43, "got %d" % tree.size())
	var bad: String = ""
	for id in IDS:
		var prm: AircraftParams = p[id]
		if prm.flare == null:
			bad += "%s 无 flare; " % id
			continue
		var expect: int = int(want.get(int(tree.get(id, 0)), -1))
		if prm.flare.max_flares != expect:
			bad += "%s(T%d) 期望 %d 实得 %d; " % [id, int(tree.get(id, 0)), expect, prm.flare.max_flares]
	_check("43 机 flare 数量全部符合 tier 档位", bad == "", bad)

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
	_check("43 机 flare 特性统一（burst=1 / jam=0.90 / nervousness=0）", traits_bad == "", traits_bad)

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


## 换机继承：技能加成必须叠在【新机自身基数】之上，且 max 与 remaining 同步
## （用户 2026-07-23 要求；分档前 41 机同为 30 发时此 bug 不可见）
func _test_flare_inheritance() -> void:
	print("── 换机继承：新机基数 + 技能加成（max 与 remaining 同步）──")
	var sp := SurvivorPlayer.new()
	var ac := Aircraft.new()
	ac.params = AircraftParams.new()
	# 起手 T1（2 发）
	ac.params.flare = load("res://resources/player/flare_t1.tres").duplicate()
	ac.flares_remaining = ac.params.flare.max_flares
	sp.aircraft = ac
	var shield: Dictionary = _find_upgrade("flare_shield")
	sp.apply_upgrade(shield)
	_check("T1(2) + 电子对抗(+2) → max 4", ac.params.flare.max_flares == 4,
		"got %d" % ac.params.flare.max_flares)
	_check("T1 叠加后 remaining 同步 4", ac.flares_remaining == 4, "got %d" % ac.flares_remaining)

	# 模拟进化换机：换成 T3 档新机 params（evolve() 的 flare 重置语义）
	ac.params = AircraftParams.new()
	ac.params.flare = load("res://resources/player/flare_t3.tres").duplicate()
	ac.flares_remaining = ac.params.flare.max_flares
	_check("换 T3 机：基数回到 4（未叠技能前）", ac.params.flare.max_flares == 4, "")
	# 换机重放（_replay_player_upgrades 语义：已持有技能无条件重挂）
	sp.apply_upgrade(shield)
	_check("换机重放后 max = 新机基数 4 + 加成 2 = 6", ac.params.flare.max_flares == 6,
		"got %d" % ac.params.flare.max_flares)
	_check("换机重放后 remaining 同步 6（不停留在旧基数）", ac.flares_remaining == 6,
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
