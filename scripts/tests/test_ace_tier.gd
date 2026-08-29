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
var _test_cfg := OS.get_temp_dir().path_join("agl_ace_career_test_%d.cfg" % OS.get_process_id())

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
	_test_rotation_balance()
	_test_herbst_profile_gate()
	_test_callsign_reservation()
	_test_ace_archive()
	_test_ace_music_contract()

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
	# 七队齐 + 字段完整
	var expected := ["marathon", "2ndwave", "orion", "gimmick", "goofighters", "vulture", "whitetea"]
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
	# 固定第一槽（2026-08-23）：六支非宿敌 210s 同池；宿敌/未实装仍排除
	_check("209.9s 池为空", AceSquadProfiles.pool_at(209.9).is_empty(),
		str(AceSquadProfiles.pool_at(209.9)))
	_check("210s 池含 marathon", AceSquadProfiles.pool_at(210.0).has("marathon"),
		str(AceSquadProfiles.pool_at(210.0)))
	_check("宿敌 orion 永不进轮换池", not AceSquadProfiles.pool_at(9999.0).has("orion"),
		str(AceSquadProfiles.pool_at(9999.0)))
	var unimplemented_leak := false
	for id in AceSquadProfiles.pool_at(9999.0):
		if not bool(AceSquadProfiles.PROFILES[id].get("implemented", false)):
			unimplemented_leak = true
	_check("未实装队不进池", not unimplemented_leak, str(AceSquadProfiles.pool_at(9999.0)))


# ── 6b. 新局轮换 + 标准化击破时间预算 ──
func _test_rotation_balance() -> void:
	print("── 随机轮换 / TTK 预算 ──")
	var ids := ["marathon", "2ndwave", "gimmick", "goofighters", "vulture", "whitetea"]
	var pool := AceSquadProfiles.pool_at(210.0)
	for id in ids:
		_check("210s 第一槽含 %s" % id, pool.has(id), str(pool))
	_check("默认局 209.9s 尚未开放第一槽",
		AceSquadProfiles.scheduled_wave_count(209.9, 600.0) == 0, "209.9/600")
	_check("默认局 210.0s 开放第一槽",
		AceSquadProfiles.scheduled_wave_count(210.0, 600.0) == 1, "210/600")
	_check("默认局 419.9s 尚未开放第二槽",
		AceSquadProfiles.scheduled_wave_count(419.9, 600.0) == 1, "419.9/600")
	_check("默认局 420.0s 开放第二槽",
		AceSquadProfiles.scheduled_wave_count(420.0, 600.0) == 2, "420/600")
	_check("延长局在真实倒数 180s 开放第二槽",
		AceSquadProfiles.scheduled_wave_count(449.9, 630.0) == 1 \
		and AceSquadProfiles.scheduled_wave_count(450.0, 630.0) == 2, "450/630")
	_check("第二槽到点后不被王牌 +60s 倒拨关闭",
		AceSquadProfiles.advance_scheduled_wave_count(2, 360.0, 600.0) == 2,
		"opened=2, rewound=360/600")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260801
	var order := AceSquadProfiles.build_run_order(rng, "marathon")
	var unique := {}
	for id in order:
		unique[id] = true
	_check("局内顺序无放回", order.size() == ids.size() and unique.size() == ids.size(), str(order))
	_check("连续两局首队不重复", not order.is_empty() and String(order[0]) != "marathon", str(order))
	for id in ids:
		var ttk := AceSquadProfiles.estimated_ttk_s(id)
		_check("%s 估算 TTK 在 60~90s" % id,
			ttk >= AceSquadProfiles.TTK_TARGET_MIN_S and ttk <= AceSquadProfiles.TTK_TARGET_MAX_S,
			"%.0fs / %.0f DU" % [ttk, AceSquadProfiles.defeat_units(id)])
	_check("VULTURE 8 机零 flare = 8 DU",
		is_equal_approx(AceSquadProfiles.defeat_units("vulture"), 8.0),
		"%.0f DU" % AceSquadProfiles.defeat_units("vulture"))
	_check("WhiteTea 三机三层防御 = 9 DU",
		is_equal_approx(AceSquadProfiles.defeat_units("whitetea"), 9.0),
		"%.0f DU" % AceSquadProfiles.defeat_units("whitetea"))
	_check("WhiteTea 标准化 TTK = 70s",
		is_equal_approx(AceSquadProfiles.estimated_ttk_s("whitetea"), 70.0),
		"%.0fs" % AceSquadProfiles.estimated_ttk_s("whitetea"))
	var wt: Dictionary = AceSquadProfiles.PROFILES["whitetea"]
	var wt_herbst: Dictionary = wt.get("herbst", {})
	_check("WhiteTea 机炮骑士 + J-turn 分层配置",
		String(wt.get("tactics", "")) == "gun_lancer" \
		and String(wt.get("gun", "")) == "ace" \
		and int(wt.get("missile_count", -1)) == 0 \
		and int(wt_herbst.get("max_uses", 0)) == 1 \
		and bool(wt_herbst.get("requires_flares_empty", false)), str(wt))
	_check("Teacher 改为 1 flare 且不叠机动规避",
		int(AceSquadProfiles.PROFILES["2ndwave"]["elements"][0].get("flares", 0)) == 1 \
		and not AceSquadProfiles.PROFILES["2ndwave"]["elements"][0].has("evade"),
		str(AceSquadProfiles.PROFILES["2ndwave"]["elements"][0]))


# ── 6c. WhiteTea J-turn 分层门 / 次数上限 ──
func _test_herbst_profile_gate() -> void:
	print("── WhiteTea J-turn 门 ──")
	var ac := Aircraft.new()
	var hm := HerbstManeuver.new()
	hm._aircraft = ac
	hm.max_uses = 1
	hm.requires_flares_empty = true
	ac.flares_remaining = 1
	_check("flare 尚存时禁止 J-turn", not hm.can_activate, "flares=1")
	ac.flares_remaining = 0
	_check("flare 耗尽后解锁 J-turn", hm.can_activate, "flares=0")
	hm.uses_consumed = 1
	_check("单次用尽后永久禁止", not hm.can_activate, "uses=1/1")
	# 默认值保持 Poltergeist / 玩家既有可重复语义。
	hm.max_uses = -1
	hm.requires_flares_empty = false
	hm.uses_consumed = 99
	_check("默认无限次回归", hm.can_activate, "max_uses=-1")
	hm.free()
	ac.free()


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
	# 与 career_archive bench 一致：测试档放系统临时目录，Shadow/CI 不依赖 user:// 写权限。
	if FileAccess.file_exists(_test_cfg):
		DirAccess.remove_absolute(_test_cfg)
	var archive = load("res://scripts/meta/career_archive.gd").new()
	archive.config_path = _test_cfg
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
	archive2.config_path = _test_cfg
	archive2.reload_from_disk()
	_check("落盘重读一致", archive2.get_ace_defeats("marathon") == 2 \
		and archive2.get_orion_kills() == 1, "defeats=%d orion=%d" \
		% [archive2.get_ace_defeats("marathon"), archive2.get_orion_kills()])
	DirAccess.remove_absolute(_test_cfg)
	archive.free()
	archive2.free()


# ── 9. 非 BOSS 王牌专属 BGM 契约 ──
func _test_ace_music_contract() -> void:
	print("── 王牌专属 BGM 生命周期 ──")
	var ace_ids := ["ace_battle_01", "ace_battle_02", "ace_battle_03", "ace_battle_04"]
	var pool_ready := true
	for i in ace_ids.size():
		var id := String(ace_ids[i])
		pool_ready = pool_ready and String(AudioManager.MUSIC_FILES.get(id, "")) \
			== "res://audio/music/ace_battle_%02d.ogg" % (i + 1) \
			and AudioManager.has_music(id) and AudioManager._get_music(id) != null
	_check("四首 ace_battle 随机池已登记且可加载", pool_ready, str(ace_ids))
	_check("单曲自然结束信号已登记", AudioManager.has_signal("music_track_finished"),
		"music_track_finished(id)")
	AudioManager.play_music_playlist(["battle_coast", "battle_coast_2"], 0.0, 2.0)
	AudioManager._active_music.seek(12.5)
	var interrupted_position := AudioManager._active_music.get_playback_position()
	var mode = load("res://scripts/survivor/survivor_mode.gd").new()
	var started := bool(mode.begin_ace_battle_music())
	var picked_id := AudioManager.current_music_id()
	_check("血条浮现从四首可用池随机取得一首 one-shot",
		started and picked_id in ace_ids and String(mode._active_ace_music_id) == picked_id,
		"picked=%s" % picked_id)
	var interrupted_player: AudioStreamPlayer = AudioManager._music_interrupt_checkpoint.get("player") \
		as AudioStreamPlayer
	var cut_position := interrupted_player.get_playback_position()
	mode._on_music_track_finished(picked_id)
	var resumed_position := AudioManager._active_music.get_playback_position()
	_check("Ace 单曲自然结束后从被掐断位置继续地图曲",
		String(mode._active_ace_music_id).is_empty() \
			and AudioManager.current_music_id() == "battle_coast" \
			and AudioManager._active_music == interrupted_player \
			and absf(resumed_position - cut_position) < 0.1,
		"current=%s trigger=%.2f cut=%.2f resumed=%.2f" % [AudioManager.current_music_id(),
			interrupted_position, cut_position, resumed_position])
	mode.free()
	_check("普通战斗歌单资源可加载",
		AudioManager.has_music("battle_coast") and AudioManager.has_music("battle_coast_2"),
		"battle_coast + battle_coast_2")
	var previous_id := AudioManager.current_music_id()
	AudioManager.crossfade_music("__missing_ace_music_probe__", 0.0, true)
	_check("缺失曲不会夺走当前 BGM 权威",
		AudioManager.current_music_id() == previous_id,
		"before=%s after=%s" % [previous_id, AudioManager.current_music_id()])
	var export_cfg := ConfigFile.new()
	var export_ok := export_cfg.load("res://export_presets.cfg") == OK
	var export_exclude := String(export_cfg.get_value("preset.0", "exclude_filter", "")) \
		if export_ok else ""
	var patch_exclude := String(export_cfg.get_value(
		"preset.0", "patch_delta_exclude_filters", "")) if export_ok else ""
	_check("正式导出明确排除全部音频收件母版",
		export_ok and "audio_intake/*" in export_exclude \
			and "audio_intake/*" in patch_exclude,
		"export=%s patch=%s" % [export_exclude, patch_exclude])
	_check("主菜单循环曲已登记且可加载",
		String(AudioManager.MUSIC_FILES.get("main_menu", "")) \
			== "res://audio/music/main_menu.ogg" \
			and AudioManager.has_music("main_menu") \
			and AudioManager._get_music("main_menu") != null,
		"main_menu.ogg")


func _check(name: String, got: bool, note: String) -> void:
	if got: _pass += 1
	else: _fail += 1
	print("  %s %-28s — %s" % ["✓" if got else "✗", name, note])
