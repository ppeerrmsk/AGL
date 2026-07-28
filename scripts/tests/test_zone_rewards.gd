extends RefCounted

## 无头验收：战区奖励去重 + 航母整局保证（spec zone-reward-docking / zone-reward-arsenal，
## 用户 2026-07-24 重定）：
##   A. 武器/技能/航母整局唯一（出现过永不再出）；僚机豁免=可重复保底
##   B. 僚机作为保底可重复出现（collectible 用尽后 roll 落到僚机）
##   C. 航母整局保证：pity——CARRIER_PITY_ROLLS 次 roll 内必然出现一次航母
##
## 运行：godot --headless --path . -- --bench=zone_rewards（或 --bench=all）

var _pass := 0
var _fail := 0


func run() -> void:
	print("\n════════ 战区奖励去重 + 航母保证 ════════")
	_test_no_duplicate_collectibles()
	_test_wingman_repeatable()
	_test_carrier_guaranteed()
	_test_airfield_zones()
	print("──────── 结果：%d 通过 / %d 失败 ────────" % [_pass, _fail])
	print("══════════════════════════════════════════════════\n")


## 连续 roll n 次（合成 id 绕过 _rewards.has 守卫，不入 ZONES 活跃集 → 只验整局去重链）
func _roll_n(zd: ZoneData, n: int) -> Array:
	var out: Array = []
	for i in n:
		var zid := StringName("T%d" % i)
		zd._assign_reward(zid)
		out.append(zd._rewards[zid])
	return out


# ── A. 武器/技能/航母整局唯一 ──
func _test_no_duplicate_collectibles() -> void:
	print("── A. 武器/技能/航母整局唯一（僚机豁免）──")
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


# ── B. 僚机保底可重复 ──
func _test_wingman_repeatable() -> void:
	print("── B. 僚机作为保底可重复出现 ──")
	var zd := ZoneData.new()
	var rolls := _roll_n(zd, 60)
	var wingman_count := 0
	for r in rolls:
		if String(r.get("kind", "")) == "wingman":
			wingman_count += 1
	# collectible 仅十余个，用尽后大量 roll 落到僚机保底
	_check("僚机重复出现（≥2）", wingman_count >= 2, "got %d" % wingman_count)


# ── C. 航母整局保证 ──
func _test_carrier_guaranteed() -> void:
	print("── C. 航母整局保证（pity ≤ %d roll 必现）──" % ZoneData.CARRIER_PITY_ROLLS)
	var all_ok := true
	# 30 局：每局都必须在 CARRIER_PITY_ROLLS 次 roll 内出现一次航母（_carrier_reward_assigned）
	# 注：ZoneData.new() 在 _init 已 roll A/B（2 次），故这里再补齐到 pity 阈值即可
	for _trial in 30:
		var zd := ZoneData.new()
		_roll_n(zd, ZoneData.CARRIER_PITY_ROLLS)
		if not zd._carrier_reward_assigned:
			all_ok = false
	_check("30 局航母均在保证窗口内出现", all_ok, "")


# ── D. 机场解放战区（spec airfield-liberation-zones）──
func _test_airfield_zones() -> void:
	print("── D. 机场解放战区数据层 ──")
	var zd := ZoneData.new()
	_check("ZONES = 7 随机 + 3 机场 = 10", ZoneData.ZONES.size() == 10, "got %d" % ZoneData.ZONES.size())
	_check("AIRFIELD_IDS = 3", ZoneData.AIRFIELD_IDS.size() == 3, "got %d" % ZoneData.AIRFIELD_IDS.size())
	for af in ZoneData.AIRFIELD_IDS:
		_check("%s 开局 AVAILABLE" % af, zd.get_state(af) == ZoneData.State.AVAILABLE, "")
		_check("is_airfield(%s)" % af, zd.is_airfield(af), "")
		_check("mission_type(%s)==airfield" % af, zd.get_mission_type(af) == "airfield", zd.get_mission_type(af))
	# 随机战区回归不被机场影响
	_check("A 仍 AVAILABLE 且非机场", zd.get_state(&"A") == ZoneData.State.AVAILABLE and not zd.is_airfield(&"A"), "")
	_check("C 仍 LOCKED", zd.get_state(&"C") == ZoneData.State.LOCKED, "")
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


func _check(desc: String, cond: bool, detail: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ %s" % desc)
	else:
		_fail += 1
		print("  ✗ %s (%s)" % [desc, detail])
