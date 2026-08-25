extends SceneTree

const _I18N_CATALOG := preload("res://scripts/i18n_catalog.gd")

## 地图扩展 + 增援入场 无头回归（specs: map-expansion §5 / reinforcement-ingress §5 的可自动化子集）
## 用法: <godot> --headless --path . --script res://scripts/tests/test_map_expansion.gd
## 覆盖：
##   1. 关键脚本 parse 冒烟（spawner / survivor_mode 等 load 不报错）
##   2. 世界常量派生（真边界 WORLD_HALF_PX=16000 / 旧核心入口=15000 / 出生点距入口 1100px）
##   3. 战区几何约束（随机战区两两缘距 ≥2000 / 离边 ≥1500，spec map-expansion §2.4；
##      机场战区圆心=现实机场烘焙坐标不可挪，豁免为 缘距 ≥1000 / 离边 ≥0，
##      裁决见 spec airfield-liberation-zones §2.5）
##   4. ground 战区在新烘焙地理上的陆地占比（zone_has_land 同法采样）
##   5. BOSS 南北锚点水面吸附结果在水面
##   6. is_on_land 抽查（湾心=水 / 旧横滨核心=陆 + 新外圈参考读数）
##   7. 增援入场纯函数：边界参数点在界上+法线朝外 / 退场点在界外 / 锚点避区

var fails := 0

## ⚠ 不要在编译期引用 ZoneData/SurvivorData（const preload 或裸 class_name 标识符都算）：
## --script 引导下本文件编译早于 autoload 注册，引用会把依赖 EventLogger 的脚本提前
## 编译成坏对象并缓存（症状：runtime .new() 报 "Nonexistent function 'new' in base 'GDScript'"）。
## 必须运行时 load() 后经脚本对象访问（与 test_target_selection 同法）。
var _ZD: GDScript
var _SD: GDScript

func _initialize() -> void:
	print("=== test_map_expansion ===")
	_ZD = load("res://scripts/survivor/zone_data.gd")
	_SD = load("res://scripts/survivor/survivor_data.gd")
	_check_parse()
	_check_basemap_error_contract()
	_check_constants()
	_check_zone_geometry()
	MapGeography.ensure_ready()
	_check_known_points()
	_check_zone_land()
	_check_boss_anchors()
	_check_ingress_helpers()
	_check_reward_dedup()
	_check_reward_desc()
	if fails == 0:
		print("[PASS] test_map_expansion 全部通过")
	else:
		printerr("[FAIL] test_map_expansion %d 项未过" % fails)
	quit(1 if fails > 0 else 0)

func _ok(cond: bool, label: String, detail: String = "") -> void:
	if cond:
		print("  [ok] %s %s" % [label, detail])
	else:
		fails += 1
		printerr("  [FAIL] %s %s" % [label, detail])

func _check_parse() -> void:
	print("[parse] 关键脚本加载冒烟")
	for p in [
		"res://scripts/survivor/survivor_spawner.gd",
		"res://scripts/survivor/survivor_mode.gd",
		"res://scripts/survivor/survivor_data.gd",
		"res://scripts/survivor/zone_data.gd",
		"res://scripts/survivor/map_boundary.gd",
		"res://scripts/survivor/zone_mission.gd",
		"res://scripts/survivor/adbs_manager.gd",
		"res://scripts/survivor/dock_point.gd",
		"res://scripts/survivor/tactical_map.gd",
		"res://scripts/survivor/map_feature_renderer.gd",
		"res://scripts/survivor/zone_hint.gd",
		"res://scripts/survivor/ace_support_squad.gd",
		"res://scripts/events/ace_reinforcement_event.gd",
		"res://scripts/survivor/survivor_player.gd",
		"res://scripts/survivor/survivor_debug_spawn.gd",
	]:
		var s := load(p)
		_ok(s != null and (s as GDScript).can_instantiate(), "load+compile", p)

func _check_basemap_error_contract() -> void:
	print("[map-ui] 底图失败可见报错契约")
	var renderer = load("res://scripts/survivor/map_feature_renderer.gd").new()
	var hint = load("res://scripts/survivor/zone_hint.gd").new()
	_ok(renderer.has_signal("basemap_load_failed"), "MapFeatureRenderer 暴露失败信号")
	_ok(hint.has_method("show_error_temp"), "ZoneHint 暴露红色错误 toast")
	renderer.free()
	hint.free()

	var required_keys := [
		"MAP_BASEMAP_ERROR_FMT",
		"MAP_BASEMAP_ERROR_REASON_MISSING_TEXTURE",
		"MAP_BASEMAP_ERROR_REASON_MISSING_METADATA",
		"MAP_BASEMAP_ERROR_REASON_INVALID_METADATA",
		"MAP_BASEMAP_ERROR_REASON_TEXTURE_LOAD_FAILED",
	]
	var i18n_rows: Dictionary = _I18N_CATALOG.audit().get("rows", {})
	for key in required_keys:
		_ok(i18n_rows.has(key), "报错文案三语 key", key)

	var previous_locale := TranslationServer.get_locale()
	for locale in ["zh", "en", "ja"]:
		TranslationServer.set_locale(locale)
		var translated := TranslationServer.translate("MAP_BASEMAP_ERROR_FMT")
		_ok(translated != "MAP_BASEMAP_ERROR_FMT" and translated.contains("%s"),
			"编译翻译资源包含底图报错", locale)
	TranslationServer.set_locale(previous_locale)

func _check_constants() -> void:
	print("[const] 世界常量")
	_ok(is_equal_approx(MapBoundary.WORLD_HALF_PX, 16000.0), "WORLD_HALF_PX=16000", str(MapBoundary.WORLD_HALF_PX))
	_ok(is_equal_approx(MapBoundary.CORE_HALF_PX, 15000.0), "旧 60km 核心入口=15000", str(MapBoundary.CORE_HALF_PX))
	var core_edge := MapBoundary.CORE_HALF_PX - MapBoundary.PLAYER_START_OFFSET_PX.y
	var world_edge := MapBoundary.WORLD_HALF_PX - MapBoundary.PLAYER_START_OFFSET_PX.y
	_ok(is_equal_approx(core_edge, 1100.0), "出生点距外缘入口 1100px", str(core_edge))
	_ok(is_equal_approx(world_edge, 2100.0), "出生点距真边界 2100px", str(world_edge))

func _check_zone_geometry() -> void:
	print("[zone] 几何约束（spec map-expansion §2.4；机场豁免见 airfield-liberation-zones §2.5）")
	var half := MapBoundary.WORLD_HALF_PX
	var zones: Array = _ZD.ZONES
	for i in range(zones.size()):
		var zi: Dictionary = zones[i]
		var ci: Vector2 = zi["center"]
		var ri: float = zi["radius"]
		var i_af := bool(zi.get("airfield", false))
		var border_clear := half - maxf(absf(ci.x), absf(ci.y)) - ri
		## 机场圆心是现实机场烘焙质心（不可挪），豁免 1500 警戒带，只保"圆整体在图内"
		var border_min := 0.0 if i_af else 1500.0
		_ok(border_clear >= border_min, "%s 离边 ≥%d" % [zi["id"], int(border_min)], "%.0f" % border_clear)
		for j in range(i + 1, zones.size()):
			var zj: Dictionary = zones[j]
			var gap := ci.distance_to(zj["center"]) - ri - float(zj["radius"])
			## 机场参与的组合豁免到 ≥1000（不重叠 + 最小走廊）；随机战区之间仍 ≥2000
			var gap_min := 1000.0 if (i_af or bool(zj.get("airfield", false))) else 2000.0
			_ok(gap >= gap_min, "%s↔%s 缘距 ≥%d" % [zi["id"], zj["id"], int(gap_min)], "%.0f" % gap)

func _check_known_points() -> void:
	print("[land] is_on_land 抽查")
	_ok(not MapGeography.is_on_land(Vector2.ZERO), "湾心(0,0) = 水")
	_ok(MapGeography.is_on_land(Vector2(-3200, -2500)), "旧横滨核心(-3200,-2500) = 陆")
	# 新外圈参考读数（不断言，供人工核对：LAND_MASK 只含城区+道路外扩，山林会读水）
	for probe in [
		["西带川崎丘陵", Vector2(-11000, -3000)],
		["东带千叶内陆", Vector2(12000, -3000)],
		["玩家出生点(湾口)", Vector2(0, 13900)],
	]:
		print("    [info] %s %s → %s" % [probe[0], probe[1], "陆" if MapGeography.is_on_land(probe[1]) else "水"])

func _land_fraction(center: Vector2, radius: float) -> float:
	var hits := 0
	var n := 48
	if MapGeography.is_on_land_strict(center):
		hits += 1
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var t := fposmod(float(i) * 0.618033, 1.0)
		var r := sqrt(t) * radius
		if MapGeography.is_on_land_strict(center + Vector2(cos(a), sin(a)) * r):
			hits += 1
	return float(hits) / float(n + 1)

func _check_zone_land() -> void:
	var threshold: float = _ZD.LAND_FRACTION_THRESHOLD
	print("[zone] ground 战区陆地占比（阈值 %.2f）" % threshold)
	var zd = _ZD.new()
	for z in _ZD.ZONES:
		if str(z.get("mission_type", "")) != "ground":
			continue
		var frac := _land_fraction(z["center"], float(z["radius"]) * 0.85)
		_ok(frac >= threshold, "%s ground 陆地占比" % z["label"], "%.2f" % frac)
		_ok(zd.zone_has_land(z["id"]), "%s zone_has_land" % z["label"])

func _check_boss_anchors() -> void:
	print("[boss] 南北锚点水面吸附")
	var zd = _ZD.new()
	for entry in [["北", _ZD.BOSS_NORTH_CENTER], ["南", _ZD.BOSS_SOUTH_CENTER]]:
		var snap_pos: Vector2 = zd._snap_to_water(entry[1], _ZD.BOSS_RADIUS)
		_ok(not MapGeography.is_on_land(snap_pos), "BOSS_%s 吸附后在水面" % entry[0],
			"%s → %s" % [entry[1], snap_pos.round()])

func _check_ingress_helpers() -> void:
	print("[ingress] 纯函数（spec reinforcement-ingress）")
	var sp = load("res://scripts/survivor/survivor_spawner.gd").new()
	var half := MapBoundary.world_half_px()
	var all_on_border := true
	var all_outward := true
	for i in range(32):
		var res: Array = sp._perimeter_point_normal(float(i) / 32.0)
		var pos: Vector2 = res[0]
		var nrm: Vector2 = res[1]
		if absf(maxf(absf(pos.x), absf(pos.y)) - half) > 0.5:
			all_on_border = false
		if (pos + nrm * 100.0).length() <= pos.length():
			all_outward = false
	_ok(all_on_border, "周长参数点全在边界上")
	_ok(all_outward, "外法线全部朝外")
	var exit_pt: Vector2 = sp._nearest_exit_point(Vector2(14000, 3000))
	var free_outset: float = _SD.EGRESS_FREE_OUTSET_PX
	_ok(MapBoundary.distance_to_edge(exit_pt) <= -free_outset,
		"退场点在界外 ≥%d px" % int(free_outset), str(exit_pt.round()))
	var clearance: float = _SD.ANCHOR_ZONE_CLEARANCE_PX
	var clear_ok := true
	for k in range(200):
		var p := Vector2(randf_range(-half, half), randf_range(-half, half))
		if sp._anchor_clears_zones(p):
			for z in _ZD.ZONES:
				if p.distance_to(z["center"]) < float(z["radius"]) + clearance - 0.01:
					clear_ok = false
	_ok(clear_ok, "_anchor_clears_zones 与几何一致")
	sp.free()

## 战区奖励去重（spec zone-reward-docking）：同时开放的战区不给同样的奖励。
## 开局恒有 2 个活跃战区（A/B），5 种奖励 > 2 → 去重后 id 必不同、必不同时航母。
func _check_reward_dedup() -> void:
	print("[reward] 同批战区奖励去重")
	var same := 0
	var carrier_clash := 0
	for i in range(200):
		var zd = _ZD.new()
		var ra := String((zd.get_reward(&"A") as Dictionary).get("id", ""))
		var rb := String((zd.get_reward(&"B") as Dictionary).get("id", ""))
		if ra != "" and ra == rb:
			same += 1
		if ra == "reward_carrier" and rb == "reward_carrier":
			carrier_clash += 1
	_ok(same == 0, "开局 A/B 奖励 id 200 局无重复", "clash=%d" % same)
	_ok(carrier_clash == 0, "开局 A/B 从不同时航母", "clash=%d" % carrier_clash)

## 战区奖励说明文案（Tab 面板奖励名下方那行）：每种奖励都要解析出 desc key 且 key 在分表里有行。
## 守的是"加了新武器件/新 NEXT_GEN 技能却忘了配说明" → 面板只显示一个光秃秃的名字。
func _check_reward_desc() -> void:
	print("[reward] 奖励说明文案覆盖")
	var csv_keys: Dictionary = _I18N_CATALOG.audit().get("rows", {})
	_ok(csv_keys.size() > 100, "本地化分表可读", "keys=%d" % csv_keys.size())

	var missing_key: Array[String] = []
	var missing_row: Array[String] = []
	# ① 实体奖励：航母 / 僚机 / 六种武器件
	var probes: Array[Dictionary] = [
		{"kind": "carrier", "id": "reward_carrier"},
		{"kind": "wingman", "id": "reward_wingman"},
	]
	for w in _ZD.REWARD_WEAPON_NAME_KEYS.keys():
		probes.append({"kind": "weapon", "weapon": String(w), "id": "reward_weapon_%s" % String(w)})
	for pr in probes:
		var k: String = _ZD.reward_desc_key(pr)
		if k == "":
			missing_key.append(String(pr.get("weapon", pr["kind"])))
		elif not csv_keys.has(k):
			missing_row.append(k)
	# ② 次世代技术（战区奖励唯一发放口）：desc 直接沿用升级表条目
	for u in _SD.UPGRADES:
		if int(u.get("rarity", -1)) != _SD.Rarity.NEXT_GEN:
			continue
		var k2: String = _ZD.reward_desc_key({"kind": "nextgen", "id": String(u["id"])})
		if k2 == "":
			missing_key.append(String(u["id"]))
		elif not csv_keys.has(k2):
			missing_row.append(k2)
	_ok(missing_key.is_empty(), "每种奖励都能解析出说明 key", "缺=%s" % str(missing_key))
	_ok(missing_row.is_empty(), "说明 key 在本地化分表里都有行", "缺=%s" % str(missing_row))
