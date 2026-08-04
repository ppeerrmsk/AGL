extends RefCounted

## 无头行为验收：机体签名技能批（spec aircraft-signature-skills）
##
## A 表完整性（41 条约定）/ B 驾驶门控与前置 / C milestone_plus 数组化 /
## D apply 分支（params 类）/ E 致死拦截判序 / F 负面状态免疫 /
## G 全频段压制流速 / H 先敌开火（锁数+装填）/ I 机动 accessor 注入 /
## J 超速截击正面发射门 / K 传感器融合越肩发射门 / L 静态账本清零
##
## 运行：godot --headless --path . -- --bench=sig_skills（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 722 机体签名技能（门控 / 继承底座 / 效果注入） ════════")
	_test_table_conventions()
	_test_offer_rules()
	_test_pool_gating()
	_test_milestone_plus_list()
	_test_apply_branches()
	_test_death_save()
	_test_status_immunity()
	_test_x13_suppress()
	_test_f22_first_look()
	_test_mobility_accessors()
	_test_mig31_forward_gate()
	_test_f35_relay_gate()
	_test_static_ledger_reset()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


# ── A. 表完整性：41 条签名技全 CLASSIFIED ×1 + exclusive_to 单机型 + 轴有效 ──
func _test_table_conventions() -> void:
	print("── A. 表完整性：sig_* 40 条 + 围猎（f14_squad_lock_slow）改档 ──")
	var sig_count := 0
	var all_ok := true
	var detail := ""
	for u in SurvivorData.UPGRADES:
		var uid := str(u.get("id", ""))
		if not uid.begins_with("sig_"):
			continue
		sig_count += 1
		if SurvivorData.get_rarity(u) != SurvivorData.Rarity.CLASSIFIED:
			all_ok = false
			detail += "%s 稀有度非 CLASSIFIED; " % uid
		if int(u.get("max_stacks", 0)) != 1:
			all_ok = false
			detail += "%s max_stacks≠1; " % uid
		var excl: Variant = u.get("exclusive_to", null)
		if excl == null or (excl as Array).size() != 1:
			all_ok = false
			detail += "%s exclusive_to 非单机型; " % uid
		var axis := StringName(str(u.get("axis", "")))
		if not SurvivorData.AXES.has(axis):
			all_ok = false
			detail += "%s axis 无效; " % uid
	_check("sig_* 条目数 = 40", sig_count == 40, "got %d" % sig_count)
	_check("全表约定（CLASSIFIED / ×1 / 单机型 / 轴有效）", all_ok, detail)
	var gaze := _find_upgrade("f14_squad_lock_slow")
	_check("围猎（f14_squad_lock_slow）改档 CLASSIFIED",
		SurvivorData.get_rarity(gaze) == SurvivorData.Rarity.CLASSIFIED, "")


func _test_offer_rules() -> void:
	print("── B. 第四槽规则：30% 边界 / 41 机映射 / 前置不阻断出示 ──")
	_check("专属第四槽概率 = 30%",
		is_equal_approx(SurvivorData.SIGNATURE_OFFER_CHANCE, 0.30), "")
	_check("roll=0 命中", SurvivorData.signature_offer_hit(0.0), "")
	_check("roll<0.30 命中", SurvivorData.signature_offer_hit(0.299999), "")
	_check("roll=0.30 不命中", not SurvivorData.signature_offer_hit(0.30), "")
	_check("越界 roll 不命中",
		not SurvivorData.signature_offer_hit(-0.01)
		and not SurvivorData.signature_offer_hit(1.0), "")

	var mapped_count := 0
	var mapped_ok := true
	for raw in EvolutionSystem.all_nodes():
		var node: Dictionary = raw
		var node_id := StringName(str(node.get("id", "")))
		var upgrade := SurvivorData.signature_upgrade_for_aircraft(node_id)
		if not upgrade.is_empty():
			mapped_count += 1
			mapped_ok = mapped_ok and SurvivorData.is_signature_upgrade(upgrade)
	_check("41 个进化节点均映射到专属技能", mapped_count == 41 and mapped_ok,
		"mapped=%d" % mapped_count)
	_check("F-14 映射围猎",
		SurvivorData.signature_upgrade_id_for_aircraft(&"f14") == "f14_squad_lock_slow", "")

	var gated := _find_upgrade("sig_su27")
	_check("技能前置仍由效果层自然等待，不改变专属身份",
		SurvivorData.is_signature_upgrade(gated)
		and not SurvivorData.is_upgrade_available_for(gated, &"su27", null, {}, []), "")


# ── B. 驾驶门控：exclusive_to 按当前 ACE 机型过滤 + requires_skill 前置 ──
func _test_pool_gating() -> void:
	print("── B. 驾驶门控：本机可刷 / 他机不可刷 / 特殊机动前置 / 隐身来源前置 ──")
	var u_f15 := _find_upgrade("sig_f15")
	_check("驾驶 F-15 → sig_f15 可刷",
		SurvivorData.is_upgrade_available_for(u_f15, &"f15", null, {}, []), "")
	_check("驾驶 F-16 → sig_f15 不可刷",
		not SurvivorData.is_upgrade_available_for(u_f15, &"f16", null, {}, []), "")
	var u_su27 := _find_upgrade("sig_su27")
	_check("Su-27 无特殊机动技 → 不可刷",
		not SurvivorData.is_upgrade_available_for(u_su27, &"su27", null, {}, []), "")
	_check("Su-27 持眼镜蛇 → 可刷",
		SurvivorData.is_upgrade_available_for(u_su27, &"su27", null, {"cobra_skill": 1}, []), "")
	var u_f22 := _find_upgrade("sig_f22")
	_check("F-22 无隐身来源 → 不可刷",
		not SurvivorData.is_upgrade_available_for(u_f22, &"f22", null, {}, []), "")
	_check("F-22 持弹后潜匿 → 可刷",
		SurvivorData.is_upgrade_available_for(u_f22, &"f22", null, {"missile_cd_stealth": 1}, []), "")


# ── C. milestone_plus 数组化（AX-00 双轴 +1；单值口径兼容）──
func _test_milestone_plus_list() -> void:
	print("── C. milestone_plus：单值 / 数组 / 无 三形态 + cap=2 语义不变 ──")
	var lst_f15: Array[StringName] = SurvivorData.milestone_plus_list_of(_find_upgrade("sig_f15"))
	_check("sig_f15 → [knight]", lst_f15 == ([&"knight"] as Array[StringName]), "got %s" % [lst_f15])
	var lst_ax: Array[StringName] = SurvivorData.milestone_plus_list_of(_find_upgrade("sig_ax00"))
	_check("sig_ax00 → [knight, schemer] 双轴",
		lst_ax == ([&"knight", &"schemer"] as Array[StringName]), "got %s" % [lst_ax])
	_check("无字段 → 空", SurvivorData.milestone_plus_list_of({"id": "x"}).is_empty(), "")
	_check("单值口径兼容（milestone_plus_of 取首轴）",
		SurvivorData.milestone_plus_of(_find_upgrade("sig_ax00")) == &"knight", "")


# ── D. apply 分支：params 类签名技的字段写入 ──
func _test_apply_branches() -> void:
	print("── D. apply：静不稳定 / 多波段 / 霹雳长矛 / 高速炮艇（含 aim_assist 不倒退）/ 唯一的锁定 ──")
	var sp := SurvivorPlayer.new()
	var ac := _make_combat_aircraft()
	sp.aircraft = ac
	var g0: float = ac.params.max_g
	var roll0: float = ac.params.roll_rate
	sp.apply_upgrade(_find_upgrade("sig_mirage2000"))
	_check("静不稳定：max_g +2", is_equal_approx(ac.params.max_g, g0 + 2.0), "got %.1f" % ac.params.max_g)
	_check("静不稳定：roll ×1.3", is_equal_approx(ac.params.roll_rate, roll0 * 1.3), "")
	ac.params.radar_half_angle = 100.0
	sp.apply_upgrade(_find_upgrade("sig_su57"))
	_check("多波段：+40° 封顶 120", is_equal_approx(ac.params.radar_half_angle, 120.0),
		"got %.1f" % ac.params.radar_half_angle)
	var m0: int = ac.params.missile.max_count
	var r0: float = ac.params.missile.max_range_rear
	var l0: float = ac.params.missile.max_lifetime
	sp.apply_upgrade(_find_upgrade("sig_j20"))
	_check("霹雳长矛：导弹 +1", ac.params.missile.max_count == m0 + 1, "")
	_check("霹雳长矛：包线 ×1.4", is_equal_approx(ac.params.missile.max_range_rear, r0 * 1.4), "")
	_check("霹雳长矛：寿命 ×1.5", is_equal_approx(ac.params.missile.max_lifetime, l0 * 1.5), "")
	sp.apply_upgrade(_find_upgrade("sig_x44"))
	_check("高速炮艇：锥半角 → 90°", is_equal_approx(ac.params.gun.fire_cone_half_angle, 90.0),
		"got %.1f" % ac.params.gun.fire_cone_half_angle)
	_check("高速炮艇：普通机炮弹穿透开关已启用", ac.gun_bullet_penetration_active, "")
	sp.apply_upgrade(_find_upgrade("aim_assist"))
	_check("aim_assist 不把 90° 缩回 45°（cap 不倒退）",
		ac.params.gun.fire_cone_half_angle >= 90.0, "got %.1f" % ac.params.gun.fire_cone_half_angle)
	var rr0: float = ac.params.radar_range
	sp.apply_upgrade(_find_upgrade("sig_viggen"))
	_check("唯一的锁定：雷达 +250px（=500m）", is_equal_approx(ac.params.radar_range, rr0 + 250.0), "")
	_check("唯一的锁定：grace 字段置 3s", is_equal_approx(ac.sig_lock_retention_sec, 3.0), "")
	sp.apply_upgrade(_find_upgrade("sig_f16"))
	_check("智能鹰：XP 第二乘区 ×1.25", is_equal_approx(sp.sig_xp_mult, 1.25), "")
	ac.free()
	sp.free()


# ── E. 致死拦截：钛浴缸（血线+CD）/ 复活（每局一次）/ 共存判序 ──
func _test_death_save() -> void:
	print("── E. 致死拦截：钛浴缸保 1 HP（CD 60s）→ 复活 30%（一次）判序 ──")
	var ac := _make_combat_aircraft()
	ac.team = 0
	ac.set_meta("upgrade_stacks", {"sig_a10": 1, "sig_a12": 1})
	# 钛浴缸：受击前 20 HP（<30%）→ 保 1
	ac.hp = -5.0
	_check("钛浴缸触发（pre 20 < 30%）", ac._try_sig_death_save(20.0), "")
	_check("保 1 HP", is_equal_approx(ac.hp, 1.0), "got %.1f" % ac.hp)
	_check("进入 60s CD", ac._sig_a10_cheat_cd > 59.0, "")
	# CD 内再死 → 轮到 A-12 复活
	ac.hp = -5.0
	_check("CD 内二击 → A-12 复活接棒", ac._try_sig_death_save(1.0), "")
	_check("复活回 30% HP", is_equal_approx(ac.hp, 30.0), "got %.1f" % ac.hp)
	# 复活已用 + 钛浴缸 CD 中 → 第三击真死
	ac.hp = -5.0
	_check("复活已用 + CD 中 → 不再拦截", not ac._try_sig_death_save(1.0), "")
	# 血线外（≥30%）且复活可用 → 跳过钛浴缸直接复活
	var ac2 := _make_combat_aircraft()
	ac2.team = 0
	ac2.set_meta("upgrade_stacks", {"sig_a10": 1, "sig_a12": 1})
	ac2.hp = -5.0
	_check("满血被秒（pre 100 ≥ 30%）→ 钛浴缸不触发、复活兜底", ac2._try_sig_death_save(100.0), "")
	_check("复活回 30%", is_equal_approx(ac2.hp, 30.0), "")
	ac.free()
	ac2.free()


# ── F. 电战预算：免疫 JAM/SLOW/FEAR、不挡增益 ──
func _test_status_immunity() -> void:
	print("── F. 电战预算：负面全免 / 增益照收 ──")
	var ac := _make_combat_aircraft()
	ac.team = 0
	ac.sig_status_immune = true
	ac.apply_status(StatusEffects.JAM, 5.0)
	ac.apply_status(StatusEffects.SLOW, 5.0)
	ac.apply_status(StatusEffects.FEAR, 5.0)
	_check("JAM 被免疫", not ac.has_status(StatusEffects.JAM), "")
	_check("SLOW 被免疫", not ac.has_status(StatusEffects.SLOW), "")
	_check("FEAR 被免疫", not ac.has_status(StatusEffects.FEAR), "")
	ac.apply_status(StatusEffects.OVERLOAD, 5.0)
	_check("OVERLOAD（增益）照收", ac.has_status(StatusEffects.OVERLOAD), "")
	ac.free()


# ── G. 全频段压制：被锁敌机负面倒计时 ×0.6（增益不受影响）──
func _test_x13_suppress() -> void:
	print("── G. 全频段压制：FEAR 流速 0.6 / BLOODLUST 正常 / 未锁定正常 ──")
	StatusEffects.sig_x13_active = true
	var foe := _make_combat_aircraft()
	foe.team = CombatUnit.TEAM_HOSTILE
	foe.is_locked = true
	foe.status_effects[StatusEffects.FEAR] = 10.0
	foe.status_effects[StatusEffects.BLOODLUST] = 10.0
	StatusEffects.tick(foe, 1.0)
	_check("被锁敌机 FEAR 剩 9.4（流速 0.6）",
		is_equal_approx(float(foe.status_effects[StatusEffects.FEAR]), 9.4),
		"got %.2f" % float(foe.status_effects[StatusEffects.FEAR]))
	_check("BLOODLUST（增益）剩 9.0（正常流速）",
		is_equal_approx(float(foe.status_effects[StatusEffects.BLOODLUST]), 9.0), "")
	foe.is_locked = false
	StatusEffects.tick(foe, 1.0)
	_check("未锁定 → FEAR 正常流速（9.4→8.4）",
		is_equal_approx(float(foe.status_effects[StatusEffects.FEAR]), 8.4),
		"got %.2f" % float(foe.status_effects[StatusEffects.FEAR]))
	StatusEffects.sig_x13_active = false
	foe.free()


# ── H. 先敌开火：隐身锁数 / STEALTH 上升沿装填 ──
func _test_f22_first_look() -> void:
	print("── H. 先敌开火：STEALTH 期间锁数 +2 / 上升沿全装填 / 沿内不重复 ──")
	var sig: Dictionary = SurvivorData.upgrade_by_id("sig_f22")
	_check("先敌开火为默认全队范围（僚机也持有效果）",
		str(sig.get("scope", "")) == "" and not sig.has("classes") \
		and SurvivorData.upgrade_applies_to_machine(sig, [], false), str(sig))
	var ac := _make_combat_aircraft()
	ac.team = 0
	ac.set_meta("upgrade_stacks", {"sig_f22": 1})
	ac.max_simultaneous_locks = 4
	_check("无 STEALTH → 保持当前锁数 4", ac.effective_max_locks() == 4, "")
	ac.ammo = 3
	ac.missiles_remaining = 1
	ac.apply_status(StatusEffects.STEALTH, 5.0)
	ac.status_stealth_active = true  # 无头下代跑 StatusEffects.update 的派生
	_check("上升沿：机炮回满", ac.ammo == ac.params.gun.max_ammo, "got %d" % ac.ammo)
	_check("上升沿：导弹回满", ac.missiles_remaining == ac.params.missile.max_count, "")
	_check("STEALTH 中锁数 4→6（加算 +2）", ac.effective_max_locks() == 6,
		"got %d" % ac.effective_max_locks())
	ac.ammo = 5
	ac.apply_status(StatusEffects.STEALTH, 8.0)  # 沿内刷新：不再装填
	_check("沿内刷新不重复装填", ac.ammo == 5, "got %d" % ac.ammo)
	ac.free()


# ── I. 机动 accessor：三发推力 +2G / 地形跟随低空 +8% ──
func _test_mobility_accessors() -> void:
	print("── I. accessor：J-36 突击 buff / 狂风低空增速 ──")
	var ac := _make_combat_aircraft()
	var g_base: float = AircraftPhysics.effective_max_g(ac)
	ac.sig_j36_assault_active = true
	_check("三发推力：持续 G +2",
		is_equal_approx(AircraftPhysics.effective_max_g(ac), g_base + 2.0), "")
	ac.sig_j36_assault_active = false
	var v_base: float = AircraftPhysics.effective_max_speed_kmh(ac)
	ac.sig_tornado_active = true
	ac.altitude = 1000.0  # LOW 档
	_check("地形跟随：低空顶速 ×1.08",
		is_equal_approx(AircraftPhysics.effective_max_speed_kmh(ac), v_base * 1.08), "")
	ac.altitude = 9000.0  # HIGH 档
	_check("地形跟随：高空无加成",
		is_equal_approx(AircraftPhysics.effective_max_speed_kmh(ac), v_base), "")
	ac.free()


# ── J. 超速截击：只从正面雷达锥选满锁目标 ──
func _test_mig31_forward_gate() -> void:
	print("── J. 超速截击：正面满锁可发 / 后半球残留满锁不可发 ──")
	var ac := _make_combat_aircraft()
	var manager := MissileManager.new()
	var front := CombatUnit.new()
	var rear := CombatUnit.new()
	ac.team = CombatUnit.TEAM_PLAYER
	ac.heading = 0.0
	ac.global_position = Vector2.ZERO
	ac.params.lock_time = 2.0
	ac.params.radar_range = 2000.0
	ac.params.radar_half_angle = 120.0  # 模拟继承“多波段搜索”后的超宽雷达锥
	ac.params.missile.min_range = 0.0
	ac.missile_manager = manager
	front.team = CombatUnit.TEAM_HOSTILE
	front.global_position = Vector2(0.0, -300.0)
	rear.team = CombatUnit.TEAM_HOSTILE
	rear.global_position = Vector2(100.0, 20.0)  # 更近、偏轴约 101°：仍在 ±120° 雷达锥，但已属后半球
	ac.radar_targets[front] = 2.0
	ac.radar_targets[rear] = 2.0
	_check("正面目标胜过更近且仍在宽雷达锥内的后半球满锁",
		ac._sig_mig31_pick_target() == front, "应选择 front")
	ac.radar_targets.erase(front)
	_check("宽雷达锥内只有后半球满锁 → 不发射", ac._sig_mig31_pick_target() == null, "")
	ac.radar_targets.clear()
	ac.missile_manager = null
	ac.free()
	manager.free()
	front.free()
	rear.free()


# ── K. 传感器融合：ACE 满锁后僚机豁免自身锥门/锁定门 ──
func _test_f35_relay_gate() -> void:
	print("── K. 传感器融合：ACE 满锁 → 僚机越肩发射门放行 ──")
	var ace := _make_combat_aircraft()
	var wing := _make_combat_aircraft()
	var tgt := CombatUnit.new()
	ace.team = CombatUnit.TEAM_PLAYER
	wing.team = CombatUnit.TEAM_PLAYER
	tgt.team = CombatUnit.TEAM_HOSTILE
	ace.params.lock_time = 2.6
	ace.set_combat_target(tgt)
	AircraftRenderer.player_ref = ace
	SkillHooks.sig_f35_active = true
	_check("ACE 未满锁 → 不放行", not AircraftWeapons._sig_f35_relay_ok(wing, tgt), "")
	ace.radar_targets[tgt] = 2.6
	_check("ACE 满锁同目标 → 僚机放行", AircraftWeapons._sig_f35_relay_ok(wing, tgt), "")
	var other := CombatUnit.new()
	other.team = CombatUnit.TEAM_HOSTILE
	_check("非 ACE 当前目标 → 不放行", not AircraftWeapons._sig_f35_relay_ok(wing, other), "")
	SkillHooks.sig_f35_active = false
	_check("技能关闭 → 不放行", not AircraftWeapons._sig_f35_relay_ok(wing, tgt), "")
	AircraftRenderer.player_ref = null
	ace.free()
	wing.free()
	tgt.free()
	other.free()


# ── L. 队级账本位（static）跨局清零：survivor_mode._ready 必须显式重置 ──
func _test_static_ledger_reset() -> void:
	print("── L. 静态账本位：源码含新局清零（跨局残留防回归）──")
	var src: String = FileAccess.get_file_as_string("res://scripts/survivor/survivor_mode.gd")
	var ready_idx: int = src.find("func _ready()")
	var head: String = src.substr(ready_idx, 2000) if ready_idx >= 0 else ""
	for f in ["StatusEffects.sig_x13_active = false", "SkillHooks.sig_fcas_active = false",
			"SkillHooks.sig_f35_active = false", "SkillHooks.sig_x90_active = false"]:
		_check("_ready 清零 %s" % f.split(" =")[0], head.contains(f), "未在 _ready 头部找到")


# ── helpers ──

func _find_upgrade(id: String) -> Dictionary:
	for u in SurvivorData.UPGRADES:
		if str(u.get("id", "")) == id:
			return u
	push_error("test_sig_skills: 表中找不到 %s" % id)
	return {}


func _make_combat_aircraft() -> Aircraft:
	var ac := Aircraft.new()
	var p := AircraftParams.new()
	p.max_hp = 100.0
	p.gun = GunParams.new()
	p.gun.max_ammo = 500
	p.missile = MissileParams.new()
	p.missile.max_count = 6
	ac.params = p
	ac.hp = 100.0
	ac.ammo = 500
	ac.missiles_remaining = 6
	return ac


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % label)
	else:
		_fail += 1
		print("  ✗ %s — %s" % [label, detail])
