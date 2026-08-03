extends RefCounted

## 生涯商店无头测试（spec career-shop §5/§6 + doctrine-unlocks §6 阶段 1）
## 覆盖：起手机解锁纯判定 / 商品上架纯判定 / 购买早退分支 / owned 持久化 roundtrip
##      + 学说门控（AND 语义 / sig_* 豁免 / 渐进上架 / 定价表 / legacy 迁移幂等）
## 运行：godot --headless --path . -- --bench=meta_shop
##
## 存档隔离：MetaShop 实例注入 user://meta_shop_test.cfg，绝不碰真存档；
## 购买测试只走"未知商品/已拥有"的早退分支，不触发 MeritLedger.spend（真账本零变动）

## CI/多用户 Windows 下 user:// 可能落到无写权限的宿主档案；tmp/ 有 .gdignore，
## 可写且不会在 bench 运行中触发 Godot 资源扫描。
const TEST_CFG := "res://tmp/meta_shop_test.cfg"
const TEST_LEGACY_CFG := "res://tmp/loadout_test.cfg"

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 生涯商店测试 ════════")
	_test_aircraft_unlock()
	_test_item_listed()
	_test_buy_early_outs()
	_test_roundtrip()
	_test_doctrine_listing()
	_test_doctrine_gating()
	_test_doctrine_prices()
	_test_signature_catalog()
	_test_support_entitlements()
	_test_shop_categories()
	_test_legacy_migration()
	_cleanup_test_cfg()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("════════════════════════════════\n")


# ── A. 起手机解锁纯判定（spec §2.1）──

func _test_aircraft_unlock() -> void:
	print("── aircraft_unlock_ok ──")
	_expect("f15 恒解锁", MetaShop.aircraft_unlock_ok("f15", 0, 0, false), true)
	_expect("f14 未败航母锁定", MetaShop.aircraft_unlock_ok("f14", 0, 999, true), false)
	_expect("f14 首败航母解锁", MetaShop.aircraft_unlock_ok("f14", 1, 0, false), true)
	_expect("a6e 29地面锁定", MetaShop.aircraft_unlock_ok("a6e", 9, 29, true), false)
	_expect("a6e 30地面解锁", MetaShop.aircraft_unlock_ok("a6e", 0, 30, false), true)
	_expect("mirage3 未购锁定", MetaShop.aircraft_unlock_ok("mirage3", 9, 999, false), false)
	_expect("mirage3 已购解锁", MetaShop.aircraft_unlock_ok("mirage3", 0, 0, true), true)
	_expect("未列机型默认不锁", MetaShop.aircraft_unlock_ok("f16", 0, 0, false), true)


# ── B. 商品上架纯判定（spec §2.2）──

func _test_item_listed() -> void:
	print("── item_listed_ok ──")
	_expect("幻影恒上架", MetaShop.item_listed_ok(MetaShop.ITEM_MIRAGE3, 0, 0), true)
	_expect("dock_wingman 无停靠不架", MetaShop.item_listed_ok(MetaShop.ITEM_DOCK_WINGMAN, 0, 9), false)
	_expect("dock_wingman 首停靠上架", MetaShop.item_listed_ok(MetaShop.ITEM_DOCK_WINGMAN, 1, 0), true)
	_expect("op_time 无撤离不架", MetaShop.item_listed_ok(MetaShop.ITEM_OP_TIME, 9, 0), false)
	_expect("op_time 首撤离上架", MetaShop.item_listed_ok(MetaShop.ITEM_OP_TIME, 0, 1), true)
	_expect("未知商品不架", MetaShop.item_listed_ok("nope", 9, 9), false)


# ── C. 购买早退分支（不触发 spend，真功勋零变动）──

func _test_buy_early_outs() -> void:
	print("── buy 早退 ──")
	var shop := _fresh_shop()
	var merit_before: int = MeritLedger.get_total()
	_expect("未知商品拒购", shop.buy("nope"), false)
	shop.debug_grant(MetaShop.ITEM_MIRAGE3)
	_expect("已拥有拒购", shop.buy(MetaShop.ITEM_MIRAGE3), false)
	_expect("真功勋零变动", MeritLedger.get_total() == merit_before, true)
	_expect("目录价格可读", shop.get_price(MetaShop.ITEM_DOCK_WINGMAN) > 0, true)
	shop.free()


# ── D. owned 持久化 roundtrip ──

func _test_roundtrip() -> void:
	print("── 持久化 roundtrip ──")
	var a := _fresh_shop()
	a.debug_grant(MetaShop.ITEM_OP_TIME)
	a.free()
	var b := _load_shop()
	_expect("授予已落盘", b.is_owned(MetaShop.ITEM_OP_TIME), true)
	_expect("未授予不在", b.is_owned(MetaShop.ITEM_DOCK_WINGMAN), false)
	b.debug_reset()
	b.free()
	var c := _load_shop()
	_expect("重置后清空", c.is_owned(MetaShop.ITEM_OP_TIME), false)
	c.free()


# ── E. 学说渐进上架（spec doctrine-unlocks §3.2）──

func _test_doctrine_listing() -> void:
	print("── doctrine 上架 ──")
	_expect("入门嗜血恒上架", MetaShop.doctrine_listed_ok("doctrine_bloodlust", false), true)
	_expect("入门骑士恒上架", MetaShop.doctrine_listed_ok("doctrine_chivalry", false), true)
	_expect("进阶隐身未集齐不架", MetaShop.doctrine_listed_ok("doctrine_stealth", false), false)
	_expect("进阶隐身集齐上架", MetaShop.doctrine_listed_ok("doctrine_stealth", true), true)
	_expect("未知学说不架", MetaShop.doctrine_listed_ok("doctrine_nope", true), false)
	var shop := _fresh_shop()
	_expect("零存档 starter 未集齐", shop.all_starter_doctrines_owned(), false)
	shop.debug_grant("doctrine_bloodlust")
	_expect("只买嗜血仍未集齐", shop.all_starter_doctrines_owned(), false)
	shop.debug_grant("doctrine_chivalry")
	_expect("两张齐 → 进阶放行", shop.all_starter_doctrines_owned(), true)
	_expect("实例 is_listed 走学说分支", shop.is_listed("doctrine_stealth"), true)
	shop.free()


# ── F. 学说门控判定（spec doctrine-unlocks §3.1）──

func _test_doctrine_gating() -> void:
	print("── doctrine 门控 ──")
	var shop := _fresh_shop()
	# 零拥有：门控词挡、非门控词放
	_expect("stealth 词未解锁", shop.is_keyword_unlocked("stealth"), false)
	_expect("非门控词恒放行", shop.is_keyword_unlocked("evasion_mode"), true)
	_expect("门控技能被挡", shop.is_upgrade_gated({"id": "vapor_dodge", "keywords": ["stealth"]}), true)
	_expect("无词技能放行", shop.is_upgrade_gated({"id": "hp_up", "keywords": []}), false)
	_expect("缺 keywords 字段放行", shop.is_upgrade_gated({"id": "hp_up"}), false)
	# sig_* 豁免（D3）：驾驶门控已足够，不受 doctrine 二次门控
	_expect("sig_f22 豁免 stealth", shop.is_upgrade_gated({"id": "sig_f22", "keywords": ["stealth"]}), false)
	_expect("F-14 围猎同样豁免", shop.is_upgrade_gated({"id": "f14_squad_lock_slow", "keywords": []}), false)
	# AND 语义：双词技任一学说缺失即挡
	shop.debug_grant("doctrine_jam")
	_expect("jam 词已解锁", shop.is_keyword_unlocked("jam"), true)
	_expect("双词技缺 overload 仍挡",
		shop.is_upgrade_gated({"id": "jam_self_overload", "keywords": ["jam", "overload"]}), true)
	shop.debug_grant("doctrine_overload")
	_expect("双词技集齐放行",
		shop.is_upgrade_gated({"id": "jam_self_overload", "keywords": ["jam", "overload"]}), false)
	shop.free()


# ── G. 定价表完整性（spec doctrine-unlocks §2.1）──

func _test_doctrine_prices() -> void:
	print("── doctrine 定价 ──")
	var expected := {
		"doctrine_chivalry": 800, "doctrine_bloodlust": 1000, "doctrine_fear": 1000,
		"doctrine_overload": 1100, "doctrine_jam": 1200, "doctrine_stealth": 1400,
	}
	var total := 0
	var all_ok := true
	for did in expected:
		var p: int = int((MetaShop.DOCTRINES[did] as Dictionary)["price"])
		total += p
		if p != int(expected[did]):
			all_ok = false
	_expect("六张定价符合公式表", all_ok, true)
	_expect("全买合计 6500", total == 6500, true)
	_expect("每词恰有一张学说", MetaShop.GATED_KEYWORDS.size() == MetaShop.DOCTRINES.size(), true)


# ── H. 41 机专属目录 / 定价 / F-14 特例（aircraft-signature-progression §2.1）──

func _test_signature_catalog() -> void:
	print("── signature 目录 ──")
	var nodes := MetaShop.signature_nodes()
	var tier_counts := {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	var total := 0
	var all_known := true
	var all_mapped := true
	for raw in nodes:
		var nd := raw as Dictionary
		var node_id := StringName(nd.get("id", ""))
		var item_id := MetaShop.signature_item_id(node_id)
		all_known = all_known and MetaShop.signature_item_known(item_id)
		all_mapped = all_mapped and not SurvivorData.signature_upgrade_for_aircraft(node_id).is_empty()
		var tier := int(nd.get("tier", 0))
		tier_counts[tier] = int(tier_counts.get(tier, 0)) + 1
		total += MetaShop.signature_price_for_tier(tier)
	_expect("进化树恰有 41 个专属商品", nodes.size() == 41, true)
	_expect("41 项商品 id 全合法", all_known, true)
	_expect("41 项技能映射全存在", all_mapped, true)
	_expect("Tier 数量 4/15/8/6/8", tier_counts == {1: 4, 2: 15, 3: 8, 4: 6, 5: 8}, true)
	_expect("全购合计 28600", total == 28600, true)
	_expect("F-14 映射围猎",
		SurvivorData.signature_upgrade_id_for_aircraft(&"f14") == "f14_squad_lock_slow", true)
	_expect("围猎进入统一签名判别",
		SurvivorData.is_signature_upgrade(SurvivorData.upgrade_by_id("f14_squad_lock_slow")), true)
	_expect("未发现不上架", MetaShop.signature_listed_ok("signature_f15", false), false)
	_expect("发现后上架", MetaShop.signature_listed_ok("signature_f15", true), true)
	_expect("未知节点拒绝", MetaShop.signature_item_known("signature_nope"), false)


# ── I. 战场支援许可（正式局查购买，非正式局 fail-open）──

func _test_support_entitlements() -> void:
	print("── 战场支援权益 ──")
	_expect("AWACS 恒上架", MetaShop.item_listed_ok(MetaShop.ITEM_AWACS, 0, 0), true)
	_expect("AWACS 定价 3000", int((MetaShop.CATALOG[MetaShop.ITEM_AWACS] as Dictionary)["price"]) == 3000, true)
	_expect("制空支援恒上架", MetaShop.item_listed_ok(MetaShop.ITEM_ZONE_AIR_SUPPORT, 0, 0), true)
	_expect("对地支援恒上架", MetaShop.item_listed_ok(MetaShop.ITEM_ZONE_GROUND_SUPPORT, 0, 0), true)
	_expect("王牌截击支援恒上架", MetaShop.item_listed_ok(MetaShop.ITEM_ACE_F15_SUPPORT, 0, 0), true)
	_expect("机场防空网授权恒上架", MetaShop.item_listed_ok(MetaShop.ITEM_AIRFIELD_SAM_SUPPORT, 0, 0), true)
	_expect("两项战区支援各定价 3000",
		int((MetaShop.CATALOG[MetaShop.ITEM_ZONE_AIR_SUPPORT] as Dictionary)["price"]) == 3000
		and int((MetaShop.CATALOG[MetaShop.ITEM_ZONE_GROUND_SUPPORT] as Dictionary)["price"]) == 3000, true)
	_expect("王牌截击支援定价 3000",
		int((MetaShop.CATALOG[MetaShop.ITEM_ACE_F15_SUPPORT] as Dictionary)["price"]) == 3000, true)
	_expect("机场防空网授权定价 3000",
		int((MetaShop.CATALOG[MetaShop.ITEM_AIRFIELD_SAM_SUPPORT] as Dictionary)["price"]) == 3000, true)
	var shop := _fresh_shop()
	_expect("未购 AWACS 正式局关闭", shop.is_awacs_entitled(true), false)
	_expect("未购 AWACS 非正式局 fail-open", shop.is_awacs_entitled(false), true)
	_expect("未购制空支援正式局关闭", shop.is_zone_air_support_entitled(true), false)
	_expect("未购制空支援非正式局 fail-open", shop.is_zone_air_support_entitled(false), true)
	_expect("未购对地支援正式局关闭", shop.is_zone_ground_support_entitled(true), false)
	_expect("未购对地支援非正式局 fail-open", shop.is_zone_ground_support_entitled(false), true)
	_expect("未购王牌截击支援正式局关闭", shop.is_ace_f15_support_entitled(true), false)
	_expect("未购王牌截击支援非正式局 fail-open", shop.is_ace_f15_support_entitled(false), true)
	_expect("未购机场防空网正式局关闭", shop.is_airfield_sam_entitled(true), false)
	_expect("未购机场防空网非正式局 fail-open", shop.is_airfield_sam_entitled(false), true)
	shop.debug_grant(MetaShop.ITEM_AWACS)
	shop.debug_grant(MetaShop.ITEM_ZONE_AIR_SUPPORT)
	shop.debug_grant(MetaShop.ITEM_ZONE_GROUND_SUPPORT)
	shop.debug_grant(MetaShop.ITEM_ACE_F15_SUPPORT)
	shop.debug_grant(MetaShop.ITEM_AIRFIELD_SAM_SUPPORT)
	_expect("购入 AWACS 正式局开启", shop.is_awacs_entitled(true), true)
	_expect("购入制空支援正式局开启", shop.is_zone_air_support_entitled(true), true)
	_expect("购入对地支援正式局开启", shop.is_zone_ground_support_entitled(true), true)
	_expect("购入王牌截击支援正式局开启", shop.is_ace_f15_support_entitled(true), true)
	_expect("购入机场防空网正式局开启", shop.is_airfield_sam_entitled(true), true)
	shop.free()


# ── J. 商店四分页结构（未知专属仍只走匿名占位）──

func _test_shop_categories() -> void:
	print("── 商店四分页 ──")
	var ui_script: Script = load("res://scripts/meta/meta_shop_ui.gd")
	var ui: Node2D = ui_script.new()
	ui.call("_build_ui")
	var tabs := ui.get("_tabs") as TabContainer
	var support_box := ui.get("_support_box") as VBoxContainer
	var career_box := ui.get("_career_box") as VBoxContainer
	var signature_box := ui.get("_signature_box") as VBoxContainer
	_expect("商店恰有四个分类页", tabs.get_tab_count() == 4, true)
	_expect("战场支援页有 AWACS + 四项战斗支援", support_box.get_child_count() == 5, true)
	_expect("机体与后勤页保留三件基础商品", career_box.get_child_count() == 3, true)
	_expect("机体专属页已生成内容", signature_box.get_child_count() > 0, true)
	ui.free()


# ── K. legacy loadout.cfg 迁移（spec doctrine-unlocks §3.4）──

func _test_legacy_migration() -> void:
	print("── legacy 迁移 ──")
	# 造一份老存档：2 张 doctrine + 2 件数值配件
	var legacy := ConfigFile.new()
	legacy.set_value("owned", "parts", ["doctrine_fear", "doctrine_stealth", "gun_dmg_t1", "ecm_t2"])
	legacy.save(TEST_LEGACY_CFG)
	var shop := _fresh_shop()
	shop.legacy_loadout_path = TEST_LEGACY_CFG
	shop.migrate_legacy_loadout()
	_expect("doctrine 已搬入", shop.is_owned("doctrine_fear") and shop.is_owned("doctrine_stealth"), true)
	_expect("数值件丢弃不退款（D2）", shop.is_owned("gun_dmg_t1") or shop.is_owned("ecm_t2"), false)
	_expect("legacy 文件已删除", FileAccess.file_exists(TEST_LEGACY_CFG), false)
	# 幂等：再跑一次（文件已不存在）不炸不变
	shop.migrate_legacy_loadout()
	_expect("重复迁移无副作用", shop.is_owned("doctrine_fear"), true)
	shop.free()
	# 迁移结果已落盘
	var reloaded := _load_shop()
	_expect("迁移结果落盘", reloaded.is_owned("doctrine_stealth"), true)
	reloaded.free()


# ── helpers ──

func _fresh_shop() -> Node:
	var s: Node = load("res://scripts/meta/meta_shop.gd").new()
	s.config_path = TEST_CFG
	s.debug_reset()
	return s

func _load_shop() -> Node:
	var s: Node = load("res://scripts/meta/meta_shop.gd").new()
	s.config_path = TEST_CFG
	s.reload_from_disk()
	return s

func _cleanup_test_cfg() -> void:
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))

func _expect(name: String, got: bool, want: bool) -> void:
	if got == want:
		_pass += 1
		print("  ✓ %s" % name)
	else:
		_fail += 1
		printerr("  ✗ %s → %s（期望 %s）" % [name, got, want])
