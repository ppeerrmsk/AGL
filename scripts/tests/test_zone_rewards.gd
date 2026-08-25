extends RefCounted

const SurvivorModeScript = preload("res://scripts/survivor/survivor_mode.gd")
const SupportRangeOverlayScript = preload("res://scripts/survivor/support_range_overlay.gd")

## 无头验收：战区奖励类别保底 + 去重 + 航母整局保证（spec zone-reward-arsenal）：
##   A. 开局 A/B 随机各出一个 weapon / nextgen，确保每局至少一武器一技能
##   B. 武器/技能/航母整局唯一（出现过永不再出）；僚机豁免=可重复保底
##   C. 僚机作为保底可重复出现（collectible 用尽后 roll 落到僚机）
##   D. 航母整局保证：pity——CARRIER_PITY_ROLLS 次 roll 内必然出现一次航母
##
## 运行：godot --headless --path . -- --bench=zone_rewards（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 战区奖励类别保底 + 去重 + 航母保证 ════════")
	_test_nextgen_replacement()
	_test_reward_tuning()
	_test_support_range_visual_contract()
	_test_run_category_guarantees()
	_test_achievement_reward_gate()
	_test_no_duplicate_collectibles()
	_test_wingman_repeatable()
	_test_carrier_guaranteed()
	_test_airfield_zones()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


## 穿透能力合并进连锁弹头；次世代池按新清单固定为 6 项。
func _test_nextgen_replacement() -> void:
	print("── 0. 次世代清单（仅连锁弹头，不存在穿透弹头技能）──")
	var data_link := SurvivorData.upgrade_by_id("data_link")
	var penetration := SurvivorData.upgrade_by_id("missile_penetration")
	var chain := SurvivorData.upgrade_by_id("missile_bounce")
	var berserk := SurvivorData.upgrade_by_id("berserk_virus")
	var nextgen_ids: Array[String] = []
	for u in SurvivorData.UPGRADES:
		if int(u.get("rarity", -1)) == SurvivorData.Rarity.NEXT_GEN:
			nextgen_ids.append(String(u.get("id", "")))
	_check("数据链 = 普通 CLASSIFIED 且无 evolved",
		int(data_link.get("rarity", -1)) == SurvivorData.Rarity.CLASSIFIED
		and not bool(data_link.get("evolved", false)), str(data_link))
	_check("穿透弹头技能不存在", penetration.is_empty(), str(penetration))
	_check("连锁弹头 = NEXT_GEN + evolved",
		int(chain.get("rarity", -1)) == SurvivorData.Rarity.NEXT_GEN
		and bool(chain.get("evolved", false)), str(chain))
	_check("狂化病毒 = EXPERIMENTAL 普通池、非战区奖励",
		int(berserk.get("rarity", -1)) == SurvivorData.Rarity.EXPERIMENTAL
		and not bool(berserk.get("evolved", false))
		and SurvivorData.is_normal_random_candidate(berserk), str(berserk))
	_check("NEXT_GEN 池恰有 6 项，重型机炮保持不动",
		nextgen_ids.size() == 6 and nextgen_ids.has("missile_bounce")
		and nextgen_ids.has("gunship_mode") and nextgen_ids.has("heavy_gun") \
		and not nextgen_ids.has("berserk_virus")
		and not nextgen_ids.has("data_link"), str(nextgen_ids))


func _test_reward_tuning() -> void:
	print("── 0B. 奖励权重 / 航母保底 / ESM 数据 ──")
	_check("航母保底 = 第 4 次", ZoneData.CARRIER_PITY_ROLLS == 4,
		"got %d" % ZoneData.CARRIER_PITY_ROLLS)
	_check("三档类别权重已拍板", ZoneData.REWARD_KIND_WEIGHTS[1] == {
		"weapon": 60.0, "wingman": 25.0, "carrier": 0.0, "nextgen": 30.0}
		and ZoneData.REWARD_KIND_WEIGHTS[2] == {
		"weapon": 35.0, "wingman": 30.0, "carrier": 20.0, "nextgen": 30.0}
		and ZoneData.REWARD_KIND_WEIGHTS[3] == {
		"weapon": 15.0, "wingman": 25.0, "carrier": 45.0, "nextgen": 40.0}, "")
	var esm: Resource = load("res://resources/esm_pod.tres")
	_check("ESM = Sentinel 3km / 锁定×1.5 / reload×0.7", esm != null
		and is_equal_approx(float(esm.get("aura_radius_m")), 3000.0)
		and is_equal_approx(float(esm.get("aura_radius_m")) * CombatUnit.PIXELS_PER_METER,
			CommanderAura.AURA_RADIUS)
		and is_equal_approx(float(esm.get("lock_rate_mult")), 1.5)
		and is_equal_approx(float(esm.get("reload_time_mult")), 0.7), str(esm))


func _test_support_range_visual_contract() -> void:
	print("── 0C. AWACS / ESM 主战场范围色层 ──")
	var overlay = SupportRangeOverlayScript.new()
	overlay.setup(AwacsSupportEvent.BUFF_RADIUS_PX, CombatUnit.TEAM_ALLY)
	var ally_fill: Color = AircraftRenderer.support_range_fill_color(CombatUnit.TEAM_ALLY)
	var player_fill: Color = AircraftRenderer.support_range_fill_color(CombatUnit.TEAM_PLAYER)
	_check("AWACS 覆盖层使用权威 8000m 半径", is_equal_approx(overlay.radius_px,
		AwacsSupportEvent.BUFF_RADIUS_PX), str(overlay.radius_px))
	_check("范围填充区分 ALLY 绿 / 玩家蓝且保持低 alpha",
		ally_fill != player_fill
		and is_equal_approx(ally_fill.a, AircraftRenderer.SUPPORT_RANGE_FILL_ALPHA)
		and is_equal_approx(player_fill.a, AircraftRenderer.SUPPORT_RANGE_FILL_ALPHA)
		and is_equal_approx(SupportRangeOverlayScript.RANGE_FILL_ALPHA,
			AircraftRenderer.SUPPORT_RANGE_FILL_ALPHA)
		and is_equal_approx(SupportRangeOverlayScript.RANGE_RING_ALPHA,
			AircraftRenderer.SUPPORT_RANGE_RING_ALPHA),
		"ally=%s player=%s" % [ally_fill, player_fill])
	overlay.free()


## 连续 roll n 次（合成 id 绕过 _rewards.has 守卫，不入 ZONES 活跃集 → 只验整局去重链）
func _roll_n(zd: ZoneData, n: int) -> Array:
	var out: Array = []
	for i in n:
		var zid := StringName("T%d" % i)
		zd._assign_reward(zid)
		out.append(zd._rewards[zid])
	return out


# ── A. 每局至少一武器一技能 ──
func _test_run_category_guarantees() -> void:
	print("── A. 开局 A/B 类别保底（武器 + 次世代技能）──")
	var all_ok := true
	for _trial in 100:
		var zd := ZoneData.new()
		var kinds: Dictionary = {}
		for zid in [&"A", &"B"]:
			kinds[String(zd.get_reward(zid).get("kind", ""))] = true
		if not kinds.has("weapon") or not kinds.has("nextgen"):
			all_ok = false
			break
	_check("100 局 A/B 均恰含一项武器与一项技能", all_ok, "")


## 成就型奖励必须在开局 A/B 首次 roll 前拿到上下文；缺键也按未解锁处理。
## 这条守住 2026-08-01 实机回归：旧链先构造 ZoneData、后注入上下文，导致首轮 fail-open。
func _test_achievement_reward_gate() -> void:
	print("── A2. 无人机猎手成就门控（含开局首 roll）──")
	var locked_ctx := func() -> Dictionary:
		return {"loyal_wingman_unlocked": false}
	var unlocked_ctx := func() -> Dictionary:
		return {"loyal_wingman_unlocked": true}
	var missing_ctx := func() -> Dictionary:
		return {}
	var locked_hits := 0
	var missing_hits := 0
	var unlocked_hits := 0
	for _trial in 200:
		for entry in [[ZoneData.new(locked_ctx), "locked"],
				[ZoneData.new(missing_ctx), "missing"],
				[ZoneData.new(unlocked_ctx), "unlocked"]]:
			var zd: ZoneData = entry[0]
			for zid in [&"A", &"B"]:
				var reward := zd.get_reward(zid)
				if String(reward.get("weapon", "")) == "loyal_wingman":
					match String(entry[1]):
						"locked": locked_hits += 1
						"missing": missing_hits += 1
						"unlocked": unlocked_hits += 1
	_check("未解锁时开局 200 局零忠诚僚机", locked_hits == 0, "hits=%d" % locked_hits)
	_check("上下文缺键时 fail-closed", missing_hits == 0, "hits=%d" % missing_hits)
	_check("解锁后忠诚僚机仍可进入开局奖励", unlocked_hits > 0, "hits=%d" % unlocked_hits)


# ── B. 武器/技能/航母整局唯一 ──
func _test_no_duplicate_collectibles() -> void:
	print("── B. 武器/技能/航母整局唯一（僚机豁免）──")
	var zd := ZoneData.new()
	var rolls := _roll_n(zd, 60)
	var seen: Dictionary = {}
	var dup_ok := true
	for r in rolls:
		if String(r.get("kind", "")) == "wingman":
			continue  # 僚机可重复，不参与去重断言
		var rid := String(r.get("id", ""))
		if seen.has(rid):
			dup_ok = false
			print("   ✗ 重复 collectible id=%s" % rid)
		seen[rid] = true
	_check("60 次 roll 内武器/技能/航母无重复", dup_ok, "")


# ── C. 僚机保底可重复 ──
func _test_wingman_repeatable() -> void:
	print("── C. 僚机作为保底可重复出现 ──")
	var zd := ZoneData.new()
	var rolls := _roll_n(zd, 60)
	var wingman_count := 0
	for r in rolls:
		if String(r.get("kind", "")) == "wingman":
			wingman_count += 1
	# collectible 仅十余个，用尽后大量 roll 落到僚机保底
	_check("僚机重复出现（≥2）", wingman_count >= 2, "got %d" % wingman_count)


# ── D. 航母整局保证 ──
func _test_carrier_guaranteed() -> void:
	print("── D. 航母整局保证（pity ≤ %d roll 必现）──" % ZoneData.CARRIER_PITY_ROLLS)
	var all_ok := true
	# 30 局：每局都必须在 CARRIER_PITY_ROLLS 次 roll 内出现一次航母（_carrier_reward_assigned）
	# 注：ZoneData.new() 在 _init 已 roll A/B（2 次），故这里再补齐到 pity 阈值即可
	for _trial in 30:
		var zd := ZoneData.new()
		_roll_n(zd, ZoneData.CARRIER_PITY_ROLLS)
		if not zd._carrier_reward_assigned:
			all_ok = false
	_check("30 局航母均在保证窗口内出现", all_ok, "")


# ── E. 机场解放战区（spec airfield-liberation-zones）──
func _test_airfield_zones() -> void:
	print("── E. 机场解放战区数据层 ──")
	var zd := ZoneData.new()
	_check("ZONES = 7 随机 + 3 机场 = 10", ZoneData.ZONES.size() == 10, "got %d" % ZoneData.ZONES.size())
	_check("AIRFIELD_IDS = 3", ZoneData.AIRFIELD_IDS.size() == 3, "got %d" % ZoneData.AIRFIELD_IDS.size())
	for af in ZoneData.AIRFIELD_IDS:
		_check("%s 开局 AVAILABLE" % af, zd.get_state(af) == ZoneData.State.AVAILABLE, "")
		_check("is_airfield(%s)" % af, zd.is_airfield(af), "")
		_check("mission_type(%s)==airfield" % af, zd.get_mission_type(af) == "airfield", zd.get_mission_type(af))
	# 随机战区回归不被机场影响
	_check("A 仍 AVAILABLE 且非机场", zd.get_state(&"A") == ZoneData.State.AVAILABLE and not zd.is_airfield(&"A"), "")
	_check("C 保持 LOCKED，或仅作为额外可选任务开放",
		zd.get_state(&"C") == ZoneData.State.LOCKED \
			or (zd.get_state(&"C") == ZoneData.State.AVAILABLE \
				and ZoneData.is_optional_mission_type(zd.get_mission_type(&"C"))), "")
	# 难度定档（默认 1★，按热度写入）
	_check("AF_HANEDA 默认难度 1", zd.get_difficulty(&"AF_HANEDA") == 1, "got %d" % zd.get_difficulty(&"AF_HANEDA"))
	zd.set_airfield_difficulty(&"AF_HANEDA", 3)
	_check("AF_HANEDA 定档 3", zd.get_difficulty(&"AF_HANEDA") == 3, "got %d" % zd.get_difficulty(&"AF_HANEDA"))
	# dock_name_key 存在
	var z := zd.get_zone_by_id(&"AF_KISARAZU")
	_check("AF_KISARAZU 带 dock_name_key", String(z.get("dock_name_key", "")) == "DOCK_KISARAZU_NAME", "")
	# 解放：状态 CLEARED，且独立路径不动 _last_cleared（BOSS 时间闸不受影响）
	zd.liberate_airfield(&"AF_HANEDA")
	_check("解放后 AF_HANEDA CLEARED", zd.get_state(&"AF_HANEDA") == ZoneData.State.CLEARED, "")
	_check("机场解放不设 _last_cleared", zd._last_cleared == &"", "got %s" % zd._last_cleared)
	# 机场一次性：不进随机战区重开池（clear A → 重开池只含随机区，永不含机场）
	zd.mark_cleared(&"A")
	var reopened_airfield := false
	for af2 in ZoneData.AIRFIELD_IDS:
		if zd.get_state(af2) == ZoneData.State.AVAILABLE and af2 == &"AF_HANEDA":
			reopened_airfield = true  # 已解放的机场被重开 = bug
	_check("解放的机场不被随机重开池激活", not reopened_airfield, "")
	# 友军驻防：默认 AA×2；永久授权只追加一座 SAM，顺序与几何固定。
	var base_plan: Array = SurvivorModeScript.airfield_ally_plan(false)
	var entitled_plan: Array = SurvivorModeScript.airfield_ally_plan(true)
	_check("未购授权驻防计划 = AA×2", base_plan.size() == 2
		and base_plan[0]["kind"] == &"aa" and base_plan[1]["kind"] == &"aa", str(base_plan))
	_check("机场防空网授权计划 = AA→AA→SAM", entitled_plan.size() == 3
		and entitled_plan[0]["kind"] == &"aa" and entitled_plan[1]["kind"] == &"aa"
		and entitled_plan[2]["kind"] == &"sam", str(entitled_plan))
	_check("SAM 使用机场东侧固定挂点", entitled_plan[2]["offset"] == Vector2(240.0, 0.0),
		str(entitled_plan[2]))
	var sam_upgrade := SurvivorData.upgrade_by_id("airfield_sam_network")
	_check("机场防空网已从升级池移除", sam_upgrade.is_empty(), str(sam_upgrade))
	_check("机场防空网商店名称/描述已进入翻译资源",
		tr("METASHOP_ITEM_AIRFIELD_SAM_NAME") != "METASHOP_ITEM_AIRFIELD_SAM_NAME"
		and tr("METASHOP_ITEM_AIRFIELD_SAM_DESC") != "METASHOP_ITEM_AIRFIELD_SAM_DESC", "")
	# 授权 SAM：真实场景验 ALLY 转换、同机场幂等与战损不重生。
	var mode = SurvivorModeScript.new()
	mode._zone_data = zd
	mode._sam_scene = load("res://scenes/sam_unit.tscn")
	mode._sam_params = load("res://resources/sam_params.tres")
	mode._friendly_asset_aggro.register_airfield(&"airfield_AF_HANEDA",
		zd.get_zone_by_id(&"AF_HANEDA")["center"])
	var haneda_center: Vector2 = zd.get_zone_by_id(&"AF_HANEDA")["center"]
	mode._try_deploy_airfield_sam(&"AF_HANEDA", haneda_center, &"airfield_AF_HANEDA")
	_check("授权给机场部署 1 座 SAM", mode.get_child_count() == 1,
		"children=%d" % mode.get_child_count())
	var deployed_sam := mode.get_child(0) as CombatUnit
	_check("授权 SAM 转为 ALLY", deployed_sam != null
		and deployed_sam.team == CombatUnit.TEAM_ALLY, str(deployed_sam))
	mode._try_deploy_airfield_sam(&"AF_HANEDA", haneda_center, &"airfield_AF_HANEDA")
	_check("重复部署幂等：同机场仍只有 1 座 SAM", mode.get_child_count() == 1,
		"children=%d" % mode.get_child_count())
	deployed_sam.free()
	mode._try_deploy_airfield_sam(&"AF_HANEDA", haneda_center, &"airfield_AF_HANEDA")
	_check("授权 SAM 战损后不重生", mode.get_child_count() == 0,
		"children=%d" % mode.get_child_count())
	mode.free()
	# 三机场独立承诺：每座解放机场各部署一座。
	var all_zd := ZoneData.new()
	var all_mode = SurvivorModeScript.new()
	all_mode._zone_data = all_zd
	all_mode._sam_scene = load("res://scenes/sam_unit.tscn")
	all_mode._sam_params = load("res://resources/sam_params.tres")
	for af3 in ZoneData.AIRFIELD_IDS:
		all_zd.liberate_airfield(af3)
		var af3_center: Vector2 = all_zd.get_zone_by_id(af3)["center"]
		all_mode._friendly_asset_aggro.register_airfield(
			StringName("airfield_%s" % af3), af3_center)
		all_mode._try_deploy_airfield_sam(af3, af3_center, StringName("airfield_%s" % af3))
	_check("三座已解放机场各部署 1 座 SAM", all_mode.get_child_count() == 3,
		"children=%d" % all_mode.get_child_count())
	_check("三机场 SAM 承诺账本彼此独立", all_mode._airfield_sam_committed.size() == 3,
		str(all_mode._airfield_sam_committed))
	all_mode.free()


func _check(desc: String, cond: bool, detail: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ %s" % desc)
	else:
		_fail += 1
		print("  ✗ %s (%s)" % [desc, detail])
