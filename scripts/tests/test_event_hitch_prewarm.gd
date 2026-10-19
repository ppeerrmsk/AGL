extends RefCounted

## 无头验收：事件型一次性冻结的缓存 / 预热只改变"何时做"，结果与原算法逐值一致。
## 运行：bench/run.cmd event_hitch_prewarm 1 300 Shadow Headless（或 --bench=all）
##   A. TerminalText.resolve_font_layout 缓存 + 宽度先判 vs 原逐字号试探（逐值相同）
##   B. ZoneData.zone_has_land Loading 预算记忆 vs 原多边形现场计算（地理替换即失效）
##      注：未做陆地网格/包围盒加速——Godot is_point_in_polygon 的 float32 射线擦顶点毛刺
##      （远离岸线的点 ±0.05px 内结果翻转，抽样约 1/13000）使任何空间加速都无法逐值一致。
##   D. ADBS 城区候选：质心缓存 + 战区快照 vs 原逐城区扫描（同种子同结果）
##   E. AudioManager 预载常驻 / 王牌支援模板常驻 / 轮廓预热（含加载失败负缓存） / 升级弹窗预热批次不调度解锁
##   F. 3★ 威胁通知字形预热：文案构成与 SurvivorMode 同源 key、覆盖全部 profile 与战区标签，
##      离屏透明真实 ZoneHint 走正式 show_warning_banner / show_temp，沉淀后释放

const WarzoneTimePanelScript := preload("res://scripts/survivor/warzone_time_panel.gd")
const AircraftSilhouetteCatalog := preload("res://scripts/aircraft_silhouette_catalog.gd")
const AdbsManagerScript := preload("res://scripts/survivor/adbs_manager.gd")
const RuntimePrewarmScript := preload("res://scripts/survivor/survivor_runtime_prewarm.gd")

var _pass := 0
var _fail := 0
var _free_after: Array = []


func run() -> void:
	print("\n════════ 事件型冻结预热 / 缓存一致性验收 ════════")
	_test_layout_equivalence()
	_test_time_panel_cache()
	_test_ink_cache_ring()
	_test_zone_land_memo()
	_test_adbs_city_candidates()
	_test_audio_resident()
	_test_ace_templates()
	_test_silhouette_prewarm()
	_test_upgrade_prewarm_batch()
	_test_notice_prewarm()
	for obj in _free_after:
		if is_instance_valid(obj):
			obj.free()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════\n")


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  ✓ ", label)
	else:
		_fail += 1
		print("  ✗ ", label, ("  " + detail) if detail != "" else "")


# ───────────────────────── A. 排版 ─────────────────────────

## 修改前的 resolve_font_layout 原文（逐字号试探，每步都测轮廓 + 直接 get_string_size）。
static func _legacy_resolve(font: Font, value: String, bounds: Vector2,
		fixed_font_size: int = 0) -> Vector3:
	var candidate := fixed_font_size
	if candidate <= 0:
		var reference_size := maxi(roundi(bounds.y), 1)
		var reference_ink := TerminalText.measure_ink_bounds(font, value, reference_size)
		if TerminalText.has_visible_ink(reference_ink):
			var reference_height := reference_ink.y - reference_ink.x
			candidate = maxi(int(floor(float(reference_size) * bounds.y / reference_height)), 1)
		else:
			candidate = TerminalText.largest_line_font_size_for_height(font, bounds.y)
		candidate = mini(candidate,
			maxi(int(ceil(bounds.y * TerminalText.MAX_INK_FONT_SIZE_MULTIPLIER)), 1))
	var ink := TerminalText.measure_ink_bounds(font, value, candidate)
	if fixed_font_size <= 0:
		while candidate > 1 and not _legacy_fits(font, value, candidate, ink, bounds):
			candidate -= 1
			ink = TerminalText.measure_ink_bounds(font, value, candidate)
		var maximum := maxi(int(ceil(bounds.y * TerminalText.MAX_INK_FONT_SIZE_MULTIPLIER)), 1)
		while candidate < maximum:
			var next_ink := TerminalText.measure_ink_bounds(font, value, candidate + 1)
			if not _legacy_fits(font, value, candidate + 1, next_ink, bounds):
				break
			candidate += 1
			ink = next_ink
	if not TerminalText.has_visible_ink(ink):
		ink = Vector2(-font.get_ascent(candidate), font.get_descent(candidate))
	return Vector3(float(candidate), ink.x, ink.y)


static func _legacy_fits(font: Font, value: String, font_size: int, ink: Vector2,
		bounds: Vector2) -> bool:
	if not TerminalText.has_visible_ink(ink) or ink.y - ink.x > bounds.y:
		return false
	return font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= bounds.x


func _layout_fonts() -> Array[Font]:
	var msdf := TerminalText.CHAKRA_PETCH_BOLD.duplicate(true) as FontFile
	msdf.multichannel_signed_distance_field = true
	msdf.fallbacks.append(ThemeDB.fallback_font)
	var silk := TerminalText.new()
	silk.font_face = TerminalText.FontFace.SILKSCREEN
	var silk_font := silk._get_text_font()
	silk.free()
	return [TerminalText.CHAKRA_PETCH_BOLD, TerminalText.CHAKRA_PETCH_MEDIUM,
		TerminalText.CHAKRA_PETCH_LIGHT, msdf, silk_font, ThemeDB.fallback_font]


func _test_layout_equivalence() -> void:
	print("── A. resolve_font_layout 缓存 vs 原逐字号试探 ──")
	var values: Array[String] = ["9", ":", "--:--", "100%", "9999", "SPD", "MSL", "GUN",
		"0123456789%s", "剩余时间", "BOSS 阶段", "Lv.99", "ffi", "A g", "", " "]
	var bounds_list: Array[Vector2] = []
	for w in [6.0, 25.5, 40.0, 133.3, 1000000.0]:
		for h in [5.0, 9.5, 18.0, 27.25, 36.0, 54.0]:
			bounds_list.append(Vector2(w, h))
	var compared := 0
	var mismatches: Array[String] = []
	var legacy_us := 0
	var cold_us := 0
	var warm_us := 0
	for font in _layout_fonts():
		for value in values:
			for bounds in bounds_list:
				for fixed in [0, 15]:
					var t0 := Time.get_ticks_usec()
					var expected := _legacy_resolve(font, value, bounds, fixed)
					legacy_us += Time.get_ticks_usec() - t0
					# 冷：清掉布局/宽度缓存（轮廓缓存双方共用，保持热，以只比较搜索本身）
					TerminalText._layout_cache.clear()
					TerminalText._layout_keys.clear()
					TerminalText._layout_cursor = 0
					t0 = Time.get_ticks_usec()
					var cold := TerminalText.resolve_font_layout(font, value, bounds, fixed)
					cold_us += Time.get_ticks_usec() - t0
					t0 = Time.get_ticks_usec()
					var warm := TerminalText.resolve_font_layout(font, value, bounds, fixed)
					warm_us += Time.get_ticks_usec() - t0
					compared += 1
					if cold != expected or warm != expected:
						if mismatches.size() < 8:
							mismatches.append("%s/%s/%s/%d legacy=%s new=%s cached=%s" % [
								font.resource_path.get_file(), value, bounds, fixed,
								expected, cold, warm])
	_check("新排版与原算法逐值相同（%d 组：6 字体 × 16 文本 × 30 区域 × 2 字号规则）" % compared,
		mismatches.is_empty(), "\n    ".join(mismatches))
	print("    [layout] legacy=%dus cold=%dus cached=%dus（%d 次）" % [
		legacy_us, cold_us, warm_us, compared])
	# layout_fits 公开签名语义不变
	var font: Font = TerminalText.CHAKRA_PETCH_BOLD
	var ok := true
	for size in [8, 12, 20, 36, 60]:
		var ink := TerminalText.measure_ink_bounds(font, "9999", size)
		for bounds in [Vector2(40, 18), Vector2(200, 80), Vector2(10, 100)]:
			ok = ok and TerminalText.layout_fits(font, "9999", size, ink, bounds) \
				== _legacy_fits(font, "9999", size, ink, bounds)
	_check("layout_fits 结果与原实现一致", ok)


func _test_time_panel_cache() -> void:
	print("── A2. 战区计时面板逐格布局缓存 ──")
	var panel = WarzoneTimePanelScript.new()
	panel._ready()
	_free_after.append(panel)
	var rect: Rect2 = WarzoneTimePanelScript.digit_rect(0)
	var expected: Vector3 = _legacy_resolve(panel._display_font, "9", rect.size, 0)
	var same := true
	for _i in 50:
		same = same and panel._cached_text_layout(panel._display_font, "9", rect.size, 0) == expected
	_check("计时数字格布局与原算法相同且重复查表", same \
		and panel._text_layout_resolutions == 1, "resolutions=%d" % panel._text_layout_resolutions)
	var label_rect: Rect2 = WarzoneTimePanelScript.label_rect()
	var label: String = panel.localized_remaining_label()
	_check("本地化标签固定字号布局与原算法相同",
		panel._cached_text_layout(panel._localized_font, label, label_rect.size, 15)
			== _legacy_resolve(panel._localized_font, label, label_rect.size, 15))


func _test_ink_cache_ring() -> void:
	print("── A3. 轮廓缓存满容量环形淘汰 ──")
	TerminalText.reset_measure_caches()
	var font: Font = TerminalText.CHAKRA_PETCH_BOLD
	var first := TerminalText.measure_ink_bounds(font, "105", 36)
	for n in TerminalText.MAX_INK_BOUNDS_CACHE_ENTRIES + 50:
		TerminalText.measure_ink_bounds(font, str(n), 36)
	_check("满容量后条目数保持上限（不整库清空）",
		TerminalText._ink_bounds_cache.size() == TerminalText.MAX_INK_BOUNDS_CACHE_ENTRIES,
		"size=%d" % TerminalText._ink_bounds_cache.size())
	_check("最近条目仍命中、被淘汰条目重测值不变",
		TerminalText._ink_bounds_cache.has("%d:36:%s" % [font.get_instance_id(),
			str(TerminalText.MAX_INK_BOUNDS_CACHE_ENTRIES + 49)])
		and TerminalText.measure_ink_bounds(font, "105", 36) == first)


# ───────────────────────── B. 战区陆地可用性 ─────────────────────────

func _test_zone_land_memo() -> void:
	print("── B. zone_has_land 预算记忆 vs 现场多边形计算 ──")
	MapGeography.ensure_ready()
	ZoneData._zone_land_memo.clear()
	var t0 := Time.get_ticks_usec()
	ZoneData.prewarm_zone_land()
	var prewarm_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var same := true
	var detail := ""
	var direct_us := 0
	for z in ZoneData.ZONES:
		var memo := ZoneData.zone_has_land(z["id"])
		t0 = Time.get_ticks_usec()
		var direct := true if not (z.get("ground_spawn_polygons", []) as Array).is_empty() \
			else ZoneData._zone_land_fraction_ok(z)
		direct_us = maxi(direct_us, Time.get_ticks_usec() - t0)
		if memo != direct:
			same = false
			detail += "%s memo=%s direct=%s " % [z["id"], memo, direct]
	_check("%d 个常量战区陆地可用性与原多边形现场计算一致（Loading 预算 %.1fms，单战区现场最多 %.1fms）" % [
		ZoneData.ZONES.size(), prewarm_ms, direct_us / 1000.0], same, detail)
	t0 = Time.get_ticks_usec()
	for z in ZoneData.ZONES:
		ZoneData.zone_has_land(z["id"])
	_check("预算后战区解锁查询只读表（%dus / 全部战区）" % (Time.get_ticks_usec() - t0),
		ZoneData._zone_land_memo.size() > 0)
	var original: Array = MapGeographyData.LAND_MASK_POLYGONS
	MapGeographyData.LAND_MASK_POLYGONS = original.duplicate()
	var invalidated := not ZoneData._zone_land_memo_valid()
	MapGeographyData.LAND_MASK_POLYGONS = original
	_check("地理数组被替换（UGC/换图）后记忆自动失效", invalidated and ZoneData._zone_land_memo_valid())


# ───────────────────────── D. ADBS ─────────────────────────

func _test_adbs_city_candidates() -> void:
	print("── D. ADBS 城区候选：缓存 vs 原逐城区扫描 ──")
	MapGeography.ensure_ready()
	var zones := ZoneData.new()
	var states := [ZoneData.State.AVAILABLE, ZoneData.State.SELECTED, ZoneData.State.LOCKED]
	var i := 0
	for z in zones.get_zone_definitions():
		zones.set_state(z["id"], states[i % states.size()])
		i += 1
	var stub_script := GDScript.new()
	stub_script.source_code = "extends Node\nvar _zone_data\n"
	stub_script.reload()
	var stub: Node = stub_script.new()
	stub.set("_zone_data", zones)
	var manager = AdbsManagerScript.new()
	manager.mode = stub
	var player := Aircraft.new()
	manager._player = player
	_free_after.append_array([manager, player, stub])
	var same := true
	var detail := ""
	var legacy_us := 0
	var new_us := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for trial in 24:
		player.global_position = Vector2(rng.randf_range(-15000, 15000), rng.randf_range(-15000, 15000))
		seed(1000 + trial)
		var t0 := Time.get_ticks_usec()
		var legacy := _legacy_pick_city_center(manager)
		legacy_us += Time.get_ticks_usec() - t0
		seed(1000 + trial)
		t0 = Time.get_ticks_usec()
		var current: Vector2 = manager._pick_city_center()
		new_us += Time.get_ticks_usec() - t0
		if legacy != current:
			same = false
			detail = "trial=%d legacy=%s new=%s" % [trial, legacy, current]
	_check("24 组玩家位置 × 同随机种子：候选与抽取结果一致（原 %.2fms / 新 %.2fms 合计）" % [
		legacy_us / 1000.0, new_us / 1000.0], same, detail)


## 修改前的 _pick_city_center 原文（逐城区算质心 + 逐城区重扫战区表）。
func _legacy_pick_city_center(manager) -> Vector2:
	var pp: Vector2 = manager._player.global_position
	var candidates: Array[Vector2] = []
	for poly_any in MapGeography.URBAN_DISTRICTS:
		var poly: PackedVector2Array = poly_any
		if poly.is_empty():
			continue
		var s := Vector2.ZERO
		for p in poly:
			s += p
		var c := s / poly.size()
		if not AdbsManagerScript.city_heli_spawn_candidate_allowed(pp, c, manager._pos_in_any_zone(c)):
			continue
		candidates.append(c)
	if candidates.is_empty():
		return Vector2.INF
	return candidates[randi() % candidates.size()]


# ───────────────────────── E. 常驻 / 预热 ─────────────────────────

func _test_audio_resident() -> void:
	print("── E1. 音乐 / 引擎声预载常驻 ──")
	AudioManager.prefetch_music(["battle_coast_2", "ace_battle_02"])
	AudioManager.prefetch_sfx(["engine_f16", "gun_fire"])
	var music := AudioManager._get_music("ace_battle_02")
	var path := String(AudioManager.MUSIC_FILES["ace_battle_02"])
	_check("预载曲目取回后常驻，再取同一实例",
		music != null and AudioManager.is_stream_resident(path)
			and AudioManager._get_music("ace_battle_02") == music)
	var engine := AudioManager._get_sfx("engine_f16")
	_check("引擎循环 WAV 常驻，再取同一实例",
		engine != null and AudioManager._get_sfx("engine_f16") == engine
			and AudioManager.is_stream_resident(String(AudioManager.SFX_FILES["engine_f16"])))
	_check("武器音仍走 AutoLoad 预载表", AudioManager._get_sfx("gun_fire") == AudioManager.WEAPON_SFX["gun_fire"])
	var coast := AudioManager._get_music("battle_coast_2")
	var original_loop: bool = coast is AudioStreamOggVorbis and (coast as AudioStreamOggVorbis).loop
	AudioManager._apply_loop(coast, true)
	_check("常驻实例的循环标志仍由每次播放入口重设", coast is AudioStreamOggVorbis
		and (coast as AudioStreamOggVorbis).loop)
	AudioManager._apply_loop(coast, original_loop)
	_check("未知曲目 id 预载被忽略", _prefetch_unknown_is_noop())
	# 预载只入队，_process 每帧最多发起一个线程请求（不在一帧里压满加载线程）
	var queued_before: int = AudioManager._prefetch_queue.size()
	var pending_before: int = AudioManager._stream_pending.size()
	var probe_ids := ["boss_csg", "boss_csg_phase2", "boss_round_table"]
	var expected_new := 0
	for id: String in probe_ids:
		var p := String(AudioManager.MUSIC_FILES[id])
		if not AudioManager.is_stream_resident(p) and not AudioManager._stream_pending.has(p) \
				and not AudioManager._prefetch_queue.has(p):
			expected_new += 1
	AudioManager.prefetch_music(probe_ids)
	var queued_after: int = AudioManager._prefetch_queue.size()
	var pending_mid: int = AudioManager._stream_pending.size()
	AudioManager._process(0.0)
	_check("预载只入队且每帧最多发起一个线程请求（新入队 %d）" % expected_new,
		queued_after == queued_before + expected_new and pending_mid == pending_before
			and AudioManager._prefetch_queue.size() == maxi(queued_after - 1, 0)
			and AudioManager._stream_pending.size() <= pending_before + 1)
	var round_table := AudioManager._get_music("boss_round_table")
	_check("未发起即取用：移出队列并按原路径同步加载后常驻",
		round_table != null and not AudioManager._prefetch_queue.has(
			String(AudioManager.MUSIC_FILES["boss_round_table"]))
			and AudioManager.is_stream_resident(String(AudioManager.MUSIC_FILES["boss_round_table"])))
	# Loading 预载清单按前缀取，不为读常量编译 survivor_mode.gd；这里锁定覆盖关系
	var survivor_consts: Dictionary = (load("res://scripts/survivor/survivor_mode.gd") as Script).get_script_constant_map()
	var ids: Array[String] = RuntimePrewarmScript.music_ids_for_map("default")
	var desert_ids: Array[String] = RuntimePrewarmScript.music_ids_for_map(RuntimePrewarmScript.DESERT_MAP_ID)
	var covers := true
	for id in survivor_consts.get("DEFAULT_BATTLE_MUSIC_IDS", []) + survivor_consts.get("ACE_BATTLE_MUSIC_IDS", []):
		covers = covers and ids.has(String(id))
	_check("预载清单覆盖 SurvivorMode 常规歌单与王牌曲，沙漠追加专用曲，含全部 boss* 曲",
		covers and not survivor_consts.get("DEFAULT_BATTLE_MUSIC_IDS", []).is_empty()
			and desert_ids.has(RuntimePrewarmScript.DESERT_ACE_MUSIC_ID) and not ids.has(RuntimePrewarmScript.DESERT_ACE_MUSIC_ID)
			and ids.has("boss") and ids.has("boss_mothergoose_2"))


func _prefetch_unknown_is_noop() -> bool:
	var before: int = AudioManager._stream_pending.size() + AudioManager._prefetch_queue.size()
	AudioManager.prefetch_music(["__missing__", ""])
	return AudioManager._stream_pending.size() + AudioManager._prefetch_queue.size() == before


func _test_ace_templates() -> void:
	print("── E2. 王牌支援编成模板常驻 ──")
	var count := AceSupportSquad.prewarm_templates()
	var all_resident := true
	for path: String in AceSupportSquad._template_cache:
		all_resident = all_resident and AceSupportSquad._template(path) == load(path)
	_check("全部 profile 模板（%d 份）常驻且与 load() 同一实例" % count,
		count >= 3 and AceSupportSquad._template_cache.size() >= count and all_resident)
	var gun_a: Resource = AceSupportSquad._template(AceSupportSquad.ACE_GUN_RES).duplicate(true)
	var gun_b: Resource = AceSupportSquad._template(AceSupportSquad.ACE_GUN_RES).duplicate(true)
	_check("每架仍拿独立副本", gun_a != gun_b)


func _test_silhouette_prewarm() -> void:
	print("── E3. 机型轮廓预热 ──")
	var t0 := Time.get_ticks_usec()
	var done := AircraftSilhouetteCatalog.prewarm_textures(0)
	var cold_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var cached := true
	for key: String in AircraftSilhouetteCatalog.TEXTURE_PATHS:
		cached = cached and AircraftSilhouetteCatalog._texture_cache.has(key)
	_check("全部 %d 个轮廓已解码进缓存（%.1fms）" % [
		AircraftSilhouetteCatalog.TEXTURE_PATHS.size(), cold_ms], done and cached)
	_check("再次预热零成本返回完成", AircraftSilhouetteCatalog.prewarm_textures(1))
	# 导出包缺导入产物时：失败 key 负缓存，绘制不再重试/刷告警，预热照常收尾。
	var probe_key := "f16"
	var saved: Variant = AircraftSilhouetteCatalog._texture_cache.get(probe_key, null)
	AircraftSilhouetteCatalog._texture_cache.erase(probe_key)
	var missing := AircraftSilhouetteCatalog._load_texture(probe_key,
		"res://resources/aircraft_silhouettes/__missing_probe_detail.png")
	var retried := AircraftSilhouetteCatalog._texture_for(probe_key) != null
	var done_with_failure := AircraftSilhouetteCatalog.prewarm_textures(0)
	_check("加载失败负缓存：同 key 不再重试，预热照常完成",
		missing == null and not retried and done_with_failure
		and AircraftSilhouetteCatalog._texture_failed.has(probe_key))
	AircraftSilhouetteCatalog._texture_failed.erase(probe_key)
	if saved != null:
		AircraftSilhouetteCatalog._texture_cache[probe_key] = saved


func _test_upgrade_prewarm_batch() -> void:
	print("── E4. 升级弹窗预热批次 ──")
	var ui := SurvivorUpgradeUI.new()
	ui._build_ui()
	_free_after.append(ui)
	var batch: Array[Dictionary] = []
	for i in 4:
		batch.append(SurvivorData.UPGRADES[i])
	ui.prewarm_render_batch(batch)
	var names_ok := true
	for i in 4:
		names_ok = names_ok and ui._name_labels[i].text == TranslationServer.translate(
			str(batch[i].get("name", ""))) and ui._buttons[i].visible
	_check("预热批次与 populate 填同一套卡片文本", names_ok)
	_check("预热批次不解锁输入", ui._input_locked)
	var generation: int = ui._populate_generation
	ui.populate(batch)
	_check("populate 行为保持：递增批次号并保持输入锁定直到延时解锁",
		ui._populate_generation == generation + 1 and ui._input_locked)
	# 批量主题覆盖 / 未变字色跳过：最终覆盖值必须与逐条直写的公式一致（含重复填同卡的跳过路径）。
	var styled_ok := true
	var rounds: Array = [batch, batch, [SurvivorData.UPGRADES[40], SurvivorData.UPGRADES[90],
		SurvivorData.UPGRADES[120]], batch]
	for r: Array in rounds:
		var typed: Array[Dictionary] = []
		typed.assign(r)
		ui.populate(typed)
		for i in typed.size():
			styled_ok = styled_ok and _card_style_matches(ui, i, typed[i])
	_check("填卡后字色/徽章样式盒与原逐条写入公式一致（4 轮含重复卡）", styled_ok)


func _card_style_matches(ui: SurvivorUpgradeUI, i: int, choice: Dictionary) -> bool:
	var axis: StringName = SurvivorData.axis_of_upgrade(choice)
	var axis_color: Color = SurvivorData.AXIS_COLORS.get(axis, Color.WHITE)
	var rarity: int = SurvivorData.get_rarity(choice)
	var rarity_color: Color = SurvivorData.RARITY_COLORS[rarity] \
		if rarity < SurvivorData.RARITY_COLORS.size() else Color.WHITE
	var light: bool = not bool(ui._media_surfaces[i].label_is_dark)
	var primary := Color(0.055, 0.06, 0.075) if light else Color(0.94, 0.96, 1.0)
	var ab: Label = ui._axis_badges[i]
	var ab_style := ab.get_theme_stylebox("normal") as StyleBoxFlat
	var src_style := ui._source_badges[i].get_theme_stylebox("normal") as StyleBoxFlat
	var rb: Label = ui._rarity_badges[i]
	var rb_style := rb.get_theme_stylebox("normal") as StyleBoxFlat
	return ui._name_labels[i].get_theme_color("font_color") == primary \
		and ab.get_theme_color("font_color") == (axis_color.darkened(0.38) if light else axis_color) \
		and ab_style.border_color == axis_color and ab_style.border_width_left == 4 \
		and ab_style.bg_color == Color(axis_color.r, axis_color.g, axis_color.b, 0.12) \
		and ui._source_badges[i].get_theme_color("font_color") == axis_color.lightened(0.18) \
		and src_style.border_color == Color(axis_color, 0.88) \
		and rb.get_theme_color("font_color") == rarity_color.lightened(0.62 if light else 0.10) \
		and rb_style.border_color == Color(rarity_color, 0.82 if light else 0.52) \
		and (ui._note_panels[i].get_theme_stylebox("panel") as StyleBoxFlat).border_color \
			== Color(SurvivorData.RARITY_COLORS[rarity] if rarity < SurvivorData.RARITY_COLORS.size() else Color.WHITE, 0.86)


# ───────────────────────── F. 3★ 威胁通知 ─────────────────────────

func _test_notice_prewarm() -> void:
	print("── F. 3★ 威胁通知字形预热 ──")
	# profile 名 key 必须覆盖 i18n 里全部 TIER3_PROFILE_*（新增 profile 时同步预热清单）
	var csv := FileAccess.get_file_as_string("res://i18n/gameplay.csv")
	var i18n_keys: Array[String] = []
	for line in csv.split("\n"):
		if line.begins_with("TIER3_PROFILE_"):
			i18n_keys.append(line.get_slice(",", 0))
	var keys: Array[String] = RuntimePrewarmScript.TIER3_PROFILE_NAME_KEYS
	var covers := not i18n_keys.is_empty() and i18n_keys.size() == keys.size()
	for key in i18n_keys:
		covers = covers and keys.has(key)
	_check("预热 profile 名覆盖 i18n 全部 TIER3_PROFILE_*（%d 项）" % i18n_keys.size(), covers)
	# 文案模板与 profile 名 key 与 SurvivorMode 横幅/解除提示处理函数同源
	var source := FileAccess.get_file_as_string("res://scripts/survivor/survivor_mode.gd")
	var name_fn := _function_source(source, "_tier3_profile_name")
	var handler := _function_source(source, "_on_tier3_threat_changed")
	var same_keys := name_fn.count("tr(\"TIER3_PROFILE_") == keys.size()
	for key in keys:
		same_keys = same_keys and name_fn.contains("tr(\"%s\")" % key)
	_check("profile 名 key 与 SurvivorMode._tier3_profile_name 分支一一对应", same_keys)
	_check("横幅 / 解除提示模板与 SurvivorMode._on_tier3_threat_changed 相同",
		handler.contains("tr(\"%s\") %% [zone_label, profile_name]" % RuntimePrewarmScript.TIER3_ACTIVE_FMT_KEY)
			and handler.contains("tr(\"%s\") %% [zone_label, profile_name]" % RuntimePrewarmScript.TIER3_NEUTRALIZED_FMT_KEY))
	var texts: Array[PackedStringArray] = RuntimePrewarmScript.tier3_notice_texts()
	var labels_ok := texts.size() == keys.size()
	for i in texts.size():
		var profile_name := String(TranslationServer.translate(keys[i]))
		labels_ok = labels_ok and texts[i].size() == 2 and texts[i][0].contains(profile_name) \
			and texts[i][1].contains(profile_name)
		for z: Dictionary in ZoneData.ZONES:
			if not bool(z.get("airfield", false)):
				labels_ok = labels_ok and texts[i][0].contains(String(z["label"])) \
					and texts[i][1].contains(String(z["label"]))
	_check("每个 profile 一组横幅/解除文案，含全部常规战区标签与本地化 profile 名", labels_ok)

	# 树外构造（同步测试期间 root 正在挂子节点，add_child 会失败）；ZoneHint 图层由其自身 _ready 设置，此处不验
	var prewarm: Node = RuntimePrewarmScript.new()
	_free_after.append(prewarm)
	var first_done: bool = prewarm._step_notice_text()
	var hints: Array = prewarm._notice_hints.duplicate()
	var shown := not first_done and hints.size() == texts.size()
	for i in hints.size():
		var hint: ZoneHint = hints[i]
		var banner := NotificationTerminalBar.split_graphic_prefix(texts[i][0], "⚠")
		var toast := NotificationTerminalBar.split_graphic_prefix(texts[i][1], "✓")
		shown = shown and hint.offset == RuntimePrewarmScript.UPGRADE_LAYER_OFFSET \
			and hint._warn_bg.visible and hint._warn_bg._icon == banner[0] and hint._warn_bg._body == banner[1] \
			and hint._warn_bg._accent == ZoneHint.WARNING_ACCENT_COLOR \
			and hint._temp_bg.visible and hint._temp_bg._icon == toast[0] and hint._temp_bg._body == toast[1]
		for child in hint.get_children():
			shown = shown and (child as CanvasItem).modulate.a == 0.0
	_check("首帧每组文案一个离屏透明真实 ZoneHint（正式横幅/提示配置）", shown)
	var settle_ok := true
	for _i in RuntimePrewarmScript.NOTICE_SETTLE_FRAMES:
		settle_ok = settle_ok and not prewarm._step_notice_text()
	var released: bool = prewarm._step_notice_text()
	for hint in hints:
		released = released and (hint as Node).is_queued_for_deletion()
	_check("沉淀 %d 帧后完成并释放全部预热 ZoneHint" % RuntimePrewarmScript.NOTICE_SETTLE_FRAMES,
		settle_ok and released and prewarm._notice_hints.is_empty())


## 取 GDScript 源码中顶层函数 name 的函数体（到下一个顶层 func 为止）。
static func _function_source(source: String, name: String) -> String:
	var start := source.find("\nfunc %s(" % name)
	if start < 0:
		return ""
	var stop := source.find("\nfunc ", start + 1)
	return source.substr(start, (stop if stop >= 0 else source.length()) - start)
