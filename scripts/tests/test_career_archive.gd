extends RefCounted

## 生涯档案无头测试（spec career-archive §5/§6）
## 覆盖：BOSS 轮换纯函数偏好序 / 地形过滤顺延 / 档案存取 roundtrip / uav_hunter 成就幂等
## 运行：godot --headless --path . -- --bench=career_archive
##
## 存档隔离：CareerArchive 实例注入 user://career_test.cfg，绝不碰真档案 user://career.cfg

const TEST_CFG := "user://career_test.cfg"
const W := "WRAITH_SQUADRON"
const C := "CARRIER_STRIKE_GROUP"
const G := "MOTHER_GOOSE"

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 生涯档案测试 ════════")
	_test_rotation_candidates()
	_test_pick_by_rotation_filtered()
	_test_boss_name_keys()
	_test_roundtrip()
	_test_uav_hunter_achievement()
	_test_codex_alignment()
	_test_codex_counting()
	_test_info_codex()
	_test_csv_columns()
	_cleanup_test_cfg()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("════════════════════════════════\n")


# ── A. 轮换偏好序（纯函数，roll 显式注入）──

func _test_rotation_candidates() -> void:
	print("── rotation_candidates 偏好序 ──")
	# 生涯首遇：ROTATION 原序（雷斯中队最优先）
	_expect_arr("首遇空档案", BossRegistry.rotation_candidates({}, 0.9), [W, C, G])
	_expect_arr("未知 last 回退原序",
		BossRegistry.rotation_candidates({"last": "NOPE", "defeated": {}}, 0.9), [W, C, G])
	# 打过 → 必换：下一个优先，last 垫底（roll 无关）
	_expect_arr("击败雷斯→航母优先",
		BossRegistry.rotation_candidates({"last": W, "defeated": {W: true}}, 0.9), [C, G, W])
	_expect_arr("击败航母→Goose优先",
		BossRegistry.rotation_candidates({"last": C, "defeated": {C: true}}, 0.9), [G, W, C])
	_expect_arr("击败Goose→环绕回雷斯",
		BossRegistry.rotation_candidates({"last": G, "defeated": {G: true}}, 0.9), [W, C, G])
	# 没打过：roll < 0.5 推进 / 否则重复优先
	_expect_arr("未败雷斯 roll0.1→推进",
		BossRegistry.rotation_candidates({"last": W, "defeated": {}}, 0.1), [C, G, W])
	_expect_arr("未败雷斯 roll0.9→重复",
		BossRegistry.rotation_candidates({"last": W, "defeated": {W: false}}, 0.9), [W, C, G])


# ── B. 地形过滤顺延（filtered = 地图池∩地形过滤后的候选）──

func _test_pick_by_rotation_filtered() -> void:
	print("── pick_by_rotation 过滤顺延 ──")
	# 击败雷斯本该轮到航母，但 CSG 被陆地滤掉 → 顺延 Goose（击败分支 roll 无关，可测）
	_expect_str("CSG被滤→顺延Goose",
		BossRegistry.pick_by_rotation([W, G], {"last": W, "defeated": {W: true}}), G)
	# 池里只剩 last 自己 → 垫底兜底命中
	_expect_str("只剩雷斯→垫底兜底",
		BossRegistry.pick_by_rotation([W], {"last": W, "defeated": {W: true}}), W)


# ── B2. 通关结算副标题的 BOSS 名 ──
# 副标题曾硬编码"Wraith 中队已被击毁"，打航母/Goose 也照抄（2026-07-28 修）。
# 这里守两件事：每个注册 BOSS 都有 name_key 且三语有译文；未知 id 必须退回通用文案。

func _test_boss_name_keys() -> void:
	print("── 结算 BOSS 名 ──")
	var no_key: Array = []
	var no_tr: Array = []
	for boss_id in BossRegistry.BOSS_DEFS:
		var key := BossRegistry.name_key_for(String(boss_id))
		if key.is_empty():
			no_key.append(String(boss_id))
		elif tr(key) == key:
			no_tr.append(key)
	_expect_bool("每个 BOSS 都有 name_key", no_key.is_empty(), true)
	if not no_key.is_empty():
		print("     缺 name_key=%s" % str(no_key))
	_expect_bool("BOSS 名三语有译文", no_tr.is_empty(), true)
	if not no_tr.is_empty():
		print("     缺译文 key=%s" % str(no_tr))
	# 未注册 id / 空串 → 空 key，HUD 据此退回 HUD_VICTORY_SUBTITLE_GENERIC
	_expect_str("未知 id 无 name_key", BossRegistry.name_key_for("NOPE"), "")
	_expect_str("空 id 无 name_key", BossRegistry.name_key_for(""), "")
	# 副标题两条文案本身也要有译文（FMT 还必须留着 %s，否则 % 运算会崩）
	_expect_bool("副标题格式串有译文",
		tr("HUD_VICTORY_SUBTITLE_FMT") != "HUD_VICTORY_SUBTITLE_FMT", true)
	_expect_bool("副标题格式串含 %s",
		tr("HUD_VICTORY_SUBTITLE_FMT").contains("%s"), true)
	_expect_bool("通用副标题有译文",
		tr("HUD_VICTORY_SUBTITLE_GENERIC") != "HUD_VICTORY_SUBTITLE_GENERIC", true)


# ── C. 存取 roundtrip ──

func _test_roundtrip() -> void:
	print("── 存档 roundtrip ──")
	var a := _fresh_archive()
	a.record_run_started()
	a.record_air_kill("mig")
	a.record_air_kill("mig")
	a.record_air_kill("uav")
	a.record_ground_kill()
	a.record_boss_encounter(W)
	a.record_boss_defeat(W)
	a.record_victory("default")
	a.record_death()
	a.record_retreat()
	a.record_docking("airfield")
	a.record_docking("carrier")
	a.record_docking("airfield")
	a.flush()
	a.free()

	var b := _load_archive()
	_expect_int("runs_started", b.get_runs_started(), 1)
	_expect_int("air mig", b.get_air_kills("mig"), 2)
	_expect_int("air uav", b.get_air_kills("uav"), 1)
	_expect_int("ground", b.get_ground_kills(), 1)
	_expect_int("boss接战", b.get_boss_encounters(W), 1)
	_expect_int("boss击败", b.get_boss_defeats(W), 1)
	_expect_str("last_boss", b.get_last_boss(), W)
	_expect_int("victories", b.get_victories("default"), 1)
	_expect_int("deaths", b.get_deaths(), 1)
	_expect_int("retreats", b.get_retreats(), 1)
	_expect_int("dock机场", b.get_dockings("airfield"), 2)
	_expect_int("dock航母", b.get_dockings("carrier"), 1)
	_expect_int("dock总数", b.get_dockings(), 3)
	var hist: Dictionary = b.build_boss_history()
	_expect_str("history.last", String(hist.get("last", "")), W)
	_expect_bool("history.defeated", bool((hist.get("defeated", {}) as Dictionary).get(W, false)), true)
	b.free()


# ── D. uav_hunter 成就：族内混算 + 一次性 + 幂等 ──

func _test_uav_hunter_achievement() -> void:
	print("── uav_hunter 成就 ──")
	var a := _fresh_archive()
	var hits := [0]
	a.achievement_unlocked.connect(func(_id: String) -> void: hits[0] += 1)
	for i in 15:
		a.record_air_kill("uav")
	for i in 14:
		a.record_air_kill("ucav")
	_expect_bool("29杀未解锁", a.is_achievement_unlocked(a.ACHIEVEMENT_UAV_HUNTER), false)
	_expect_int("29杀无信号", hits[0], 0)
	a.record_air_kill("uav_laser")  # 第 30 杀（族内混算）
	_expect_bool("30杀解锁", a.is_achievement_unlocked(a.ACHIEVEMENT_UAV_HUNTER), true)
	_expect_int("解锁信号一次", hits[0], 1)
	for i in 5:
		a.record_air_kill("uav")
	_expect_int("超额不重发", hits[0], 1)
	_expect_int("族外mig不计入", a.get_uav_family_kills(), 35)
	a.flush()
	a.free()
	# 解锁状态持久化
	var b := _load_archive()
	_expect_bool("解锁已落盘", b.is_achievement_unlocked(b.ACHIEVEMENT_UAV_HUNTER), true)
	b.free()


# ── helpers ──

# ── E. 敌人图鉴对齐（spec career-archive §2.6）──
# 图鉴 id 必须与真实系统标识一一对上：拼错一个字符 → 该条目永远显示 0，
# 而且**不会报错**（静默腐烂）。这组断言就是防这个的。

func _test_codex_alignment() -> void:
	print("── 敌人图鉴 id 对齐 ──")
	var tags: Array = SurvivorSpawner.all_type_tags()
	var bad_air: Array = []
	for e in EnemyCodex.ENTRIES:
		var k := int(e["kind"])
		var id := String(e["id"])
		match k:
			EnemyCodex.Kind.AIR, EnemyCodex.Kind.ADDS:
				if id not in tags:
					bad_air.append(id)
			EnemyCodex.Kind.ACE:
				if AceSquadProfiles.get_profile(id).is_empty():
					bad_air.append(id)
			EnemyCodex.Kind.BOSS:
				if not BossRegistry.BOSS_DEFS.has(id):
					bad_air.append(id)
	_expect_bool("全部条目 id 对齐真实系统", bad_air.is_empty(), true)
	if not bad_air.is_empty():
		print("     失配 id=%s" % str(bad_air))
	# 反向：真实敌人不该在图鉴里缺席（王牌/BOSS 专属机型除外——它们归所属中队条目）
	var covered: Array = []
	for e in EnemyCodex.ENTRIES:
		covered.append(String(e["id"]))
	var exempt := ["f47", "f14_poltergeist", "f15", "f16", "mirage2000", "su47", "cre"]
	var missing: Array = []
	for t in tags:
		if t not in covered and t not in exempt:
			missing.append(t)
	_expect_bool("无敌人漏收录", missing.is_empty(), true)
	if not missing.is_empty():
		print("     漏收录 tag=%s" % str(missing))
	# 三语齐全：每条的 name/desc 都要有译文（tr 未命中会原样返回 key）
	var no_tr: Array = []
	for e in EnemyCodex.ENTRIES:
		for key in [EnemyCodex.name_key(e), EnemyCodex.desc_key(e)]:
			if key == "" or tr(key) == key:
				no_tr.append(key)
	_expect_bool("全部条目有译文", no_tr.is_empty(), true)
	if not no_tr.is_empty():
		print("     缺译文 key=%s" % str(no_tr))
	# 分组不漏条目（SECTIONS 覆盖全部 kind）
	var grouped := 0
	for s in EnemyCodex.SECTIONS:
		grouped += EnemyCodex.entries_of(int(s["kind"])).size()
	_expect_int("分组覆盖全部条目", grouped, EnemyCodex.ENTRIES.size())


func _test_codex_counting() -> void:
	print("── 敌人图鉴计数路由 ──")
	var a := _fresh_archive()
	# 注入到 autoload 的替身不可行 → 直接验 CareerArchive 的读写对，
	# 图鉴的 defeat_count 只是这些 getter 的分派（同一数据源）
	a.record_air_kill("mig")
	a.record_air_kill("mig")
	a.record_ground_kill("sam")
	a.record_ground_kill("aa")
	a.record_ground_kill("aa")
	_expect_int("空中逐型计数", a.get_air_kills("mig"), 2)
	_expect_int("地面逐型计数 sam", a.get_ground_kills_by_type("sam"), 1)
	_expect_int("地面逐型计数 aa", a.get_ground_kills_by_type("aa"), 2)
	_expect_int("地面总数仍聚合", a.get_ground_kills(), 3)
	_expect_int("未打过的型为 0", a.get_ground_kills_by_type("radar"), 0)
	# 逐型落盘 → 重读一致（图鉴跨局显示的基础）
	a.flush()
	var b := _load_archive()
	_expect_int("逐型地面落盘重读", b.get_ground_kills_by_type("aa"), 2)
	_expect_int("空中落盘重读", b.get_air_kills("mig"), 2)
	# 无 tag 调用（旧路径兼容）：只加总数，不污染逐型
	b.record_ground_kill()
	_expect_int("无 tag 只加总数", b.get_ground_kills(), 4)
	_expect_int("无 tag 不污染逐型", b.get_ground_kills_by_type("aa"), 2)
	a.free()
	b.free()


# ── F. 游戏信息手册（spec career-archive §2.7）──

func _test_info_codex() -> void:
	print("── 游戏信息手册 ──")
	# 分组不漏条目
	var grouped := 0
	for s in GameInfoCodex.SECTIONS:
		grouped += GameInfoCodex.entries_of(String(s["id"])).size()
	_expect_int("分组覆盖全部条目", grouped, GameInfoCodex.ENTRIES.size())
	# 三语齐全（标题 + 正文；tip 条目的正文复用战术地图小技巧）
	var no_tr: Array = []
	for e in GameInfoCodex.ENTRIES:
		for key in [GameInfoCodex.title_key(e), GameInfoCodex.body_key(e)]:
			if key == "" or tr(key) == key:
				no_tr.append(key)
	for s in GameInfoCodex.SECTIONS:
		var k := String(s["title_key"])
		if tr(k) == k:
			no_tr.append(k)
	_expect_bool("手册条目译文齐全", no_tr.is_empty(), true)
	if not no_tr.is_empty():
		print("     缺译文 key=%s" % str(no_tr))
	# tip 条目必须指向战术地图**在用**的小技巧（写错 key = 手册显示原始 key）
	var tips_in_use: Array = []
	for k in TacticalMap._TIP_KEYS:
		tips_in_use.append(String(k))
	var bad_tip: Array = []
	for e in GameInfoCodex.ENTRIES:
		if GameInfoCodex.is_tip(e) and String(e["tip"]) not in tips_in_use:
			bad_tip.append(String(e["tip"]))
	_expect_bool("tip 条目对齐战术地图轮播表", bad_tip.is_empty(), true)
	if not bad_tip.is_empty():
		print("     失配 tip=%s" % str(bad_tip))


# ── G. 翻译表结构（防"逗号把字段切碎"这类静默错位）──
# tr() 命中检查抓不到它：列错位后 zh 仍正确、en 被截断、ja 落到第 4 列之外，
# 于是"有译文"通过而玩家看到的是半句话。这里直接查列数。

func _test_csv_columns() -> void:
	print("── 翻译表结构 ──")
	var f := FileAccess.open("res://i18n/translations.csv", FileAccess.READ)
	if f == null:
		_expect_bool("translations.csv 可读", false, true)
		return
	var bad: Array = []
	var total := 0
	var header := f.get_csv_line()
	var cols := header.size()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() == 0 or (row.size() == 1 and String(row[0]).strip_edges() == ""):
			continue
		total += 1
		if row.size() != cols:
			bad.append("%s(%d列)" % [String(row[0]), row.size()])
	f.close()
	_expect_bool("全部行列数一致（%d 行 × %d 列）" % [total, cols], bad.is_empty(), true)
	if not bad.is_empty():
		print("     异常行 %d 条，前 8：%s" % [bad.size(), str(bad.slice(0, 8))])


func _fresh_archive() -> Node:
	var a: Node = load("res://scripts/meta/career_archive.gd").new()
	a.config_path = TEST_CFG
	a.debug_reset()
	return a

func _load_archive() -> Node:
	var a: Node = load("res://scripts/meta/career_archive.gd").new()
	a.config_path = TEST_CFG
	a.reload_from_disk()
	return a

func _cleanup_test_cfg() -> void:
	var gp := ProjectSettings.globalize_path(TEST_CFG)
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(gp)

func _expect_arr(name: String, got: Array, want: Array) -> void:
	_tally(name, got == want, "%s（期望 %s）" % [got, want])

func _expect_str(name: String, got: String, want: String) -> void:
	_tally(name, got == want, "%s（期望 %s）" % [got, want])

func _expect_int(name: String, got: int, want: int) -> void:
	_tally(name, got == want, "%d（期望 %d）" % [got, want])

func _expect_bool(name: String, got: bool, want: bool) -> void:
	_tally(name, got == want, "%s（期望 %s）" % [got, want])

func _tally(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % name)
	else:
		_fail += 1
		printerr("  ✗ %s → %s" % [name, detail])
