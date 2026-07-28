extends RefCounted

## 王牌中队 tier 策略回归测试（specs/systems/ace-squadron-tier.md §2.1 / §2.3）
## 契约：
##   1. tier 成员判定唯一：F-47 / F-14 Poltergeist 是王牌中队，杂兵与 Sentinel 不是
##   2. 无等级缩放：三项系数恒为中性，且每次返回独立字典（不得共享 const 实例）
##   3. HP cap 显式豁免：王牌中队不受 ENEMY_HP_MISSILE_CAP 夹取
##   4. 血量高于全部玩家导弹伤害 → 耗尽热诱弹后必定先残血，不会被单发导弹直接击坠
##   5. tier 标记可打可查，未标记单位不误判
## 运行：godot --headless --path . -- --bench=ace_tier（或 --bench=all）

var _pass := 0
var _fail := 0

## 玩家可用导弹伤害（resources/*.tres 的落地值，spec §2.3 表）
const PLAYER_MISSILE_DAMAGE := {
	"QMAAM": 70.0,
	"MRM(默认)": 80.0,
	"AGM-65": 90.0,
}


func run() -> void:
	print("\n════════ 王牌中队 tier（成员/缩放/HP cap/残血保证） ════════")

	_test_membership()
	_test_no_scale()
	_test_hp_cap_exemption()
	_test_residual_hp_guarantee()
	_test_marking()
	_test_profiles()
	_test_callsign_reservation()
	_test_ace_archive()

	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])


# ── 1. 成员判定 ──
func _test_membership() -> void:
	var ET = SurvivorSpawner.EnemyType
	_check("F-47 是王牌中队", AceTier.is_ace_type(ET.F47), "F47")
	_check("F-14 Poltergeist 是王牌中队", AceTier.is_ace_type(ET.F14_POLTERGEIST), "F14")
	# 反例：容易被误判成"精英"的几个
	_check("Su-35 不是王牌中队", not AceTier.is_ace_type(ET.SU35), "顶级杂兵≠tier")
	_check("Sentinel 不是王牌中队", not AceTier.is_ace_type(ET.UAV_COMMANDER), "Schemer≠tier")
	_check("MiG-29 不是王牌中队", not AceTier.is_ace_type(ET.MIG), "主力威胁≠tier")


# ── 2. 无等级缩放 ──
func _test_no_scale() -> void:
	var s := AceTier.no_scale()
	_check("hp_mult 中性", is_equal_approx(float(s["hp_mult"]), 1.0), "%.2f" % float(s["hp_mult"]))
	_check("missile_add 中性", int(s["missile_add"]) == 0, "%d" % int(s["missile_add"]))
	_check("gun_damage_mult 中性", is_equal_approx(float(s["gun_damage_mult"]), 1.0),
			"%.2f" % float(s["gun_damage_mult"]))
	# 必须每次新建 —— 调用方会就地改，共享实例会串味
	var a := AceTier.no_scale()
	var b := AceTier.no_scale()
	a["hp_mult"] = 99.0
	_check("每次返回独立字典", is_equal_approx(float(b["hp_mult"]), 1.0),
			"改 a 不应影响 b（b.hp_mult=%.2f）" % float(b["hp_mult"]))


# ── 3. HP cap 豁免 ──
func _test_hp_cap_exemption() -> void:
	var ET = SurvivorSpawner.EnemyType
	_check("王牌中队豁免 HP cap", AceTier.exempt_from_hp_cap(ET.F47), "F47 不被夹")
	_check("杂兵不豁免 HP cap", not AceTier.exempt_from_hp_cap(ET.MIG), "MiG-29 仍守一击必杀")
	# 模拟 spawner 的夹取顺序：先 cap 再 apply_hp
	var p := AircraftParams.new()
	p.max_hp = 70.0
	if not AceTier.exempt_from_hp_cap(ET.F47):
		p.max_hp = minf(p.max_hp, SurvivorData.ENEMY_HP_MISSILE_CAP)
	AceTier.apply_hp(p)
	_check("最终血量 = 100", is_equal_approx(p.max_hp, AceTier.MAX_HP),
			"max_hp=%.1f（cap=%.1f 未生效）" % [p.max_hp, SurvivorData.ENEMY_HP_MISSILE_CAP])


# ── 4. 残血保证（本 tier 的核心承诺）──
func _test_residual_hp_guarantee() -> void:
	# spec §2.3：MAX_HP 必须高于全部玩家导弹伤害，否则"耗尽热诱弹→残血→再一发"的
	# 击杀序列退化成"耗尽→直接坠毁"，残血阶段消失
	for name in PLAYER_MISSILE_DAMAGE:
		var dmg: float = PLAYER_MISSILE_DAMAGE[name]
		var residual: float = AceTier.MAX_HP - dmg
		_check("扛住 %s 单发" % name, residual > 0.0,
				"%.0f 伤 → 剩 %.0f HP" % [dmg, residual])
	# 且必须真的"残"——留太多就不是残血了，两发内必须打死
	var strongest: float = 0.0
	for k in PLAYER_MISSILE_DAMAGE:
		strongest = maxf(strongest, float(PLAYER_MISSILE_DAMAGE[k]))
	var weakest: float = INF
	for k in PLAYER_MISSILE_DAMAGE:
		weakest = minf(weakest, float(PLAYER_MISSILE_DAMAGE[k]))
	_check("两发最弱导弹必死", weakest * 2.0 >= AceTier.MAX_HP,
			"2×%.0f=%.0f ≥ %.0f" % [weakest, weakest * 2.0, AceTier.MAX_HP])
	_check("最强导弹打不死", strongest < AceTier.MAX_HP,
			"%.0f < %.0f" % [strongest, AceTier.MAX_HP])


# ── 5. tier 标记 ──
func _test_marking() -> void:
	var n := Node2D.new()
	_check("未标记单位不误判", not AceTier.is_ace(n), "裸 Node2D")
	AceTier.mark(n)
	_check("标记后可查", AceTier.is_ace(n), "meta tier=ace")
	_check("null 安全", not AceTier.is_ace(null), "不崩")
	n.free()


# ── 6. 编成 profile 注册表（spec ace-squadron-tier §2.7 / §2.9，728 实装批）──
func _test_profiles() -> void:
	print("── profile 注册表 ──")
	# 六队齐 + 字段完整
	var expected := ["marathon", "2ndwave", "orion", "gimmick", "goofighters", "vulture"]
	for id in expected:
		var p: Dictionary = AceSquadProfiles.get_profile(id)
		_check("profile %s 存在且字段齐" % id,
			not p.is_empty() and p.has("codename") and p.has("name_key") and p.has("lore_key") \
			and p.has("color") and p.has("pool_time") and p.has("callsigns") and p.has("dodge"),
			String(p.get("codename", "MISSING")))
	# 呼号铁律：不与 CALLSIGNS 800 池撞名、全表不重复
	var seen: Dictionary = {}
	var pool_clash: Array = []
	var dup: Array = []
	for id in AceSquadProfiles.PROFILES:
		for cs_any in AceSquadProfiles.PROFILES[id].get("callsigns", []):
			var cs := String(cs_any)
			if cs in CallsignDB.CALLSIGNS:
				pool_clash.append(cs)
			if seen.has(cs):
				dup.append(cs)
			seen[cs] = true
	_check("固定呼号不在 800 池内", pool_clash.is_empty(), "撞名=%s" % str(pool_clash))
	_check("固定呼号全表无重复", dup.is_empty(), "重复=%s" % str(dup))
	# 时段档（728 用户改档：Marathon 中期 320s；宿敌不进池；未实装不进池）
	_check("250s 池不含 marathon（改档中期）", not AceSquadProfiles.pool_at(250.0).has("marathon"),
		str(AceSquadProfiles.pool_at(250.0)))
	_check("330s 池含 marathon", AceSquadProfiles.pool_at(330.0).has("marathon"),
		str(AceSquadProfiles.pool_at(330.0)))
	_check("宿敌 orion 永不进轮换池", not AceSquadProfiles.pool_at(9999.0).has("orion"),
		str(AceSquadProfiles.pool_at(9999.0)))
	var unimplemented_leak := false
	for id in AceSquadProfiles.pool_at(9999.0):
		if not bool(AceSquadProfiles.PROFILES[id].get("implemented", false)):
			unimplemented_leak = true
	_check("未实装队不进池", not unimplemented_leak, str(AceSquadProfiles.pool_at(9999.0)))


# ── 7. 呼号永久保留（tier §2.7：杂鱼抽不到、死亡不回池）──
func _test_callsign_reservation() -> void:
	print("── 呼号永久保留 ──")
	AceSquadProfiles.reserve_callsigns()
	_check("Pacer 已永久保留", CallsignDB.is_permanent("Pacer"), "")
	_check("池内代号词 Vulture 一并保留", CallsignDB.is_permanent("Vulture"), "EXTRA_RESERVED")
	# recycle 不放行
	CallsignDB.recycle("Pacer")
	var re_allocated := false
	for i in 900:   # 抽干整池也抽不到 Pacer
		if CallsignDB.allocate() == "Pacer":
			re_allocated = true
			break
	_check("recycle 后仍抽不到王牌呼号", not re_allocated, "永不回池")
	CallsignDB.reset()   # 清掉本测试污染的 _used
	_check("reset 后仍占位", not re_allocated and CallsignDB.is_permanent("Pacer"), "")


# ── 8. 生涯留档（tier §2.7：encounter/defeat + 首破日期；orion 计数=成长轴）──
func _test_ace_archive() -> void:
	print("── 生涯留档 ──")
	var archive = load("res://scripts/meta/career_archive.gd").new()
	archive.config_path = "user://_test_ace_career.cfg"
	archive.record_ace_encounter("marathon")
	archive.record_ace_defeat("marathon")
	archive.record_ace_defeat("marathon")
	_check("遭遇计数", archive.get_ace_encounters("marathon") == 1,
		"%d" % archive.get_ace_encounters("marathon"))
	_check("击破计数", archive.get_ace_defeats("marathon") == 2,
		"%d" % archive.get_ace_defeats("marathon"))
	_check("首破日期只记一次", archive.get_ace_first_defeat_date("marathon") != "",
		archive.get_ace_first_defeat_date("marathon"))
	_check("未击破队为剪影态", not archive.has_defeated_ace("vulture"), "")
	archive.record_ace_defeat("orion")
	_check("orion 击破即成长轴计数", archive.get_orion_kills() == 1,
		"%d" % archive.get_orion_kills())
	# 落盘→重读闭环
	var archive2 = load("res://scripts/meta/career_archive.gd").new()
	archive2.config_path = "user://_test_ace_career.cfg"
	archive2.reload_from_disk()
	_check("落盘重读一致", archive2.get_ace_defeats("marathon") == 2 \
		and archive2.get_orion_kills() == 1, "defeats=%d orion=%d" \
		% [archive2.get_ace_defeats("marathon"), archive2.get_orion_kills()])
	DirAccess.remove_absolute("user://_test_ace_career.cfg")
	archive.free()
	archive2.free()


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-28s — %s" % ["✓" if got else "✗", name, note])
