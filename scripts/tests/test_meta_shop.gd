extends RefCounted

## 生涯商店无头测试（spec career-shop §5/§6 + doctrine-unlocks §6 阶段 1）
## 覆盖：起手机解锁纯判定 / 商品上架纯判定 / 购买早退分支 / owned 持久化 roundtrip
##      + 学说门控（AND 语义 / sig_* 豁免 / 渐进上架 / 定价表 / legacy 迁移幂等）
## 运行：godot --headless --path . -- --bench=meta_shop
##
## 存档隔离：MetaShop 实例注入 user://meta_shop_test.cfg，绝不碰真存档；
## 购买测试只走"未知商品/已拥有"的早退分支，不触发 MeritLedger.spend（真账本零变动）

const TEST_CFG := "user://meta_shop_test.cfg"
const TEST_LEGACY_CFG := "user://loadout_test.cfg"

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


# ── H. legacy loadout.cfg 迁移（spec doctrine-unlocks §3.4）──

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
