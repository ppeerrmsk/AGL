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


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-28s — %s" % ["✓" if got else "✗", name, note])
